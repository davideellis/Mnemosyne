import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/status_chip.dart';
import '../onboarding/onboarding_card.dart';
import '../settings/settings_panel.dart';
import '../settings/workspace_settings.dart';
import 'app_state_repository.dart';
import 'local_vault_repository.dart';
import 'markdown_editor_pane.dart';
import 'note_search_service.dart';
import 'secure_key_repository.dart';
import 'sync_api_client.dart';
import 'sync_models.dart';
import 'unsaved_changes_dialog.dart';
import 'vault_models.dart';

class NotesWorkspacePage extends StatefulWidget {
  const NotesWorkspacePage({super.key});

  @override
  State<NotesWorkspacePage> createState() => _NotesWorkspacePageState();
}

class _NotesWorkspacePageState extends State<NotesWorkspacePage> {
  final LocalVaultRepository _repository = LocalVaultRepository();
  final AppStateRepository _appStateRepository = AppStateRepository();
  final SecureKeyRepository _secureKeyRepository = SecureKeyRepository();
  final SyncApiClient _syncApiClient = SyncApiClient();
  final NoteSearchService _noteSearchService = const NoteSearchService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _editorController = TextEditingController();
  final TextEditingController _apiBaseUrlController =
      TextEditingController(text: 'http://127.0.0.1:8080');
  final TextEditingController _vaultPathController = TextEditingController();
  final TextEditingController _emailController =
      TextEditingController(text: 'demo@mnemosyne.local');
  final TextEditingController _passwordController =
      TextEditingController(text: 'demo-password');
  StreamSubscription<VaultSnapshot>? _vaultWatchSubscription;
  Timer? _autoSyncTimer;

  VaultSnapshot? _snapshot;
  VaultNote? _selectedNote;
  bool _selectedNoteIsTrashed = false;
  SyncSession? _session;
  bool _isLoading = true;
  bool _isCreating = false;
  bool _isRenaming = false;
  bool _isSaving = false;
  bool _isDeleting = false;
  bool _isSyncing = false;
  bool _isAuthenticating = false;
  String? _statusLabel;
  Map<String, String> _knownNoteDigests = <String, String>{};
  String? _knownSettingsDigest;
  Map<String, String> _knownTrashDigests = <String, String>{};
  String? _lastNoteFolder;
  String? _selectedFolderFilter;
  WorkspaceSettings _settings = const WorkspaceSettings();
  bool _showWorkspacePanel = true;
  String _syncCursor = '';
  String? _syncMessage;
  DateTime? _lastSyncAttemptAt;
  DateTime? _lastSyncSuccessAt;
  DateTime? _nextAutoSyncAttemptAt;
  String? _lastSyncError;
  int _autoSyncFailureCount = 0;
  List<RegisteredDevice> _registeredDevices = const <RegisteredDevice>[];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChange);
    _editorController.addListener(_handleEditorChange);
    _loadVault();
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _vaultWatchSubscription?.cancel();
    _searchController.dispose();
    _editorController.dispose();
    _apiBaseUrlController.dispose();
    _vaultPathController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadVault() async {
    final persistedState = await _appStateRepository.load();
    final hydratedSession = await _hydrateSession(persistedState.session);
    final snapshot = persistedState.vaultRootPath == null
        ? await _repository.loadInitialVault()
        : await _repository.loadVaultAtPath(persistedState.vaultRootPath!);
    final initialNote = snapshot.notes.isEmpty ? null : snapshot.notes.first;
    if (!mounted) {
      return;
    }

    setState(() {
      _snapshot = snapshot;
      _selectedNote = initialNote;
      _selectedNoteIsTrashed = false;
      _session = hydratedSession;
      _knownNoteDigests =
          Map<String, String>.from(persistedState.knownNoteDigests);
      _knownSettingsDigest = persistedState.knownSettingsDigest;
      _knownTrashDigests =
          Map<String, String>.from(persistedState.knownTrashDigests);
      _lastNoteFolder = persistedState.lastNoteFolder;
      _settings = persistedState.settings;
      _showWorkspacePanel = persistedState.showWorkspacePanel;
      _syncCursor = persistedState.syncCursor ?? '';
      _apiBaseUrlController.text =
          persistedState.apiBaseUrl ?? _apiBaseUrlController.text;
      _vaultPathController.text = snapshot.rootPath;
      _emailController.text = persistedState.email ?? _emailController.text;
      _isLoading = false;
      _statusLabel = hydratedSession == null ? 'Loaded locally' : 'Signed in';
      _syncMessage = hydratedSession == null
          ? 'Local vault ready.'
          : 'Restored signed-in session for ${hydratedSession.email}.';
      _editorController.text = initialNote?.markdown ?? '';
    });
    _startWatchingVault(snapshot.rootPath);
    if (hydratedSession != null) {
      unawaited(_refreshRegisteredDevices());
    }
  }

  Future<SyncSession?> _hydrateSession(SyncSession? session) async {
    if (session == null) {
      return null;
    }

    if (session.masterKeyMaterial.isNotEmpty) {
      await _secureKeyRepository.saveMasterKey(
        accountId: session.accountId,
        masterKeyMaterial: session.masterKeyMaterial,
      );
      return session;
    }

    final storedMasterKey =
        await _secureKeyRepository.loadMasterKey(session.accountId);
    if (storedMasterKey == null || storedMasterKey.isEmpty) {
      return session;
    }

    return session.copyWith(masterKeyMaterial: storedMasterKey);
  }

  Future<void> _saveSelectedNote() async {
    final snapshot = _snapshot;
    final note = _selectedNote;
    if (snapshot == null || note == null || _selectedNoteIsTrashed) {
      return;
    }

    setState(() {
      _isSaving = true;
      _statusLabel = 'Saving locally';
    });

    final updatedSnapshot = await _repository.saveNote(
      rootPath: snapshot.rootPath,
      note: note,
      markdown: _editorController.text,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _replaceSnapshot(
        updatedSnapshot,
        statusLabel: 'Saved locally',
        preferredObjectId: note.objectId,
        preferTrashed: false,
      );
      _isSaving = false;
    });
    await _persistState();
    _scheduleAutoSync();
  }

  Future<void> _createNote() async {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }

    final draft = await showDialog<_NewNoteDraft>(
      context: context,
      builder: (context) => _NewNoteDialog(
        folders: snapshot.folders,
        lastUsedFolder: _lastNoteFolder ?? _selectedFolderFilter,
      ),
    );
    if (draft == null) {
      return;
    }

    setState(() {
      _isCreating = true;
      _statusLabel = 'Creating note';
      _syncMessage = null;
    });

    try {
      final updatedSnapshot = await _repository.createNote(
        rootPath: snapshot.rootPath,
        relativePath: draft.relativePath,
        title: draft.title,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _lastNoteFolder = _folderForRelativePath(draft.relativePath);
        _replaceSnapshot(updatedSnapshot, statusLabel: 'Created locally');
        _isCreating = false;
      });
      await _persistState();
      _scheduleAutoSync();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCreating = false;
        _statusLabel = 'Create failed';
        _syncMessage = error.toString();
      });
    }
  }

  Future<void> _renameSelectedNote() async {
    final snapshot = _snapshot;
    final note = _selectedNote;
    if (snapshot == null || note == null || _selectedNoteIsTrashed) {
      return;
    }

    final draft = await showDialog<_RenameNoteDraft>(
      context: context,
      builder: (context) => _RenameNoteDialog(note: note),
    );
    if (draft == null) {
      return;
    }

    setState(() {
      _isRenaming = true;
      _statusLabel = 'Renaming note';
      _syncMessage = null;
    });

    try {
      final updatedSnapshot = await _repository.renameNote(
        rootPath: snapshot.rootPath,
        note: note,
        relativePath: draft.relativePath,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _lastNoteFolder = _folderForRelativePath(draft.relativePath);
        _replaceSnapshot(
          updatedSnapshot,
          statusLabel: 'Renamed locally',
          preferredObjectId: _normalizeRelativePath(draft.relativePath),
          preferTrashed: false,
        );
        _isRenaming = false;
      });
      await _persistState();
      _scheduleAutoSync();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isRenaming = false;
        _statusLabel = 'Rename failed';
        _syncMessage = error.toString();
      });
    }
  }

  Future<void> _deleteSelectedNote() async {
    final snapshot = _snapshot;
    final note = _selectedNote;
    if (snapshot == null || note == null || _selectedNoteIsTrashed) {
      return;
    }

    setState(() {
      _isDeleting = true;
      _statusLabel = 'Moving to trash';
    });

    final updatedSnapshot = await _repository.deleteNote(
      rootPath: snapshot.rootPath,
      note: note,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _replaceSnapshot(
        updatedSnapshot,
        statusLabel: 'Moved to trash',
        preferredObjectId: note.objectId,
        preferTrashed: true,
      );
      _isDeleting = false;
    });
    await _persistState();
    _scheduleAutoSync();
  }

  Future<void> _restoreSelectedNote() async {
    final snapshot = _snapshot;
    final note = _selectedNote;
    if (snapshot == null || note == null || !_selectedNoteIsTrashed) {
      return;
    }

    setState(() {
      _isDeleting = true;
      _statusLabel = _session == null ? 'Restoring locally' : 'Restoring note';
      _syncMessage = null;
    });

    if (_session != null &&
        !await _ensureActiveSession(
          'Your sync session expired on this device. Sign in again to continue syncing.',
        )) {
      try {
        final restoredChange = await _syncApiClient.restoreTrash(
          baseUri: _parseBaseUri(),
          session: _session!,
          objectId: note.objectId,
        );
        final updatedSnapshot = await _repository.applyRemoteChanges(
          rootPath: snapshot.rootPath,
          changes: <RemoteSyncChange>[restoredChange],
        );

        if (!mounted) {
          return;
        }

        setState(() {
          _replaceSnapshot(
            updatedSnapshot,
            statusLabel: 'Restored from sync',
            preferredObjectId: note.objectId,
            preferTrashed: false,
          );
          _knownNoteDigests = _buildKnownDigests(updatedSnapshot);
          _knownTrashDigests = _buildTrashDigests(updatedSnapshot);
          _syncMessage = 'Restored note across synced devices.';
          _isDeleting = false;
        });
        await _persistState();
        return;
      } catch (error) {
        if (!mounted) {
          return;
        }
        if (error is SyncApiException && error.statusCode == 401) {
          await _handleUnauthorizedSession(
            'Your sync session is no longer valid. Sign in again to continue syncing.',
          );
        } else {
          setState(() {
            _syncMessage =
                'Restore will continue locally and sync later. $error';
          });
        }
      }
    }

    final updatedSnapshot = await _repository.restoreNote(
      rootPath: snapshot.rootPath,
      note: note,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _replaceSnapshot(
        updatedSnapshot,
        statusLabel: 'Restored locally',
        preferredObjectId: note.objectId,
        preferTrashed: false,
      );
      _isDeleting = false;
      _syncMessage ??= 'Restored locally.';
    });
    await _persistState();
    _scheduleAutoSync();
  }

  Future<void> _openVaultFromInput() async {
    if (!await _confirmSelectionChange('this vault')) {
      return;
    }

    final selectedPath = _vaultPathController.text.trim();
    if (selectedPath.isEmpty) {
      setState(() {
        _syncMessage = 'Enter a local vault path first.';
        _statusLabel = 'Vault path required';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusLabel = 'Opening vault';
      _syncMessage = null;
    });

    final snapshot = await _repository.loadVaultAtPath(selectedPath);
    if (!mounted) {
      return;
    }

    setState(() {
      _replaceSnapshot(snapshot, statusLabel: 'Loaded locally');
      _vaultPathController.text = snapshot.rootPath;
      _isLoading = false;
    });
    await _persistState();
    await _startWatchingVault(snapshot.rootPath);
  }

  Future<void> _bootstrapAccount() async {
    await _authenticate(bootstrap: true);
  }

  Future<void> _login() async {
    await _authenticate(bootstrap: false);
  }

  Future<void> _recover() async {
    final recoveryKey = await showDialog<String>(
      context: context,
      builder: (context) => const _RecoveryKeyDialog(),
    );
    if (recoveryKey == null || recoveryKey.trim().isEmpty) {
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _syncMessage = null;
      _statusLabel = 'Recovering access';
    });

    try {
      final session = await _syncApiClient.recover(
        baseUri: _parseBaseUri(),
        email: _emailController.text.trim(),
        recoveryKey: recoveryKey.trim(),
        deviceName: _currentDeviceName(),
        platform: Platform.operatingSystem,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _session = session;
        _statusLabel = 'Recovered';
        _syncMessage = 'Recovered access for ${session.email}.';
      });
      await _secureKeyRepository.saveMasterKey(
        accountId: session.accountId,
        masterKeyMaterial: session.masterKeyMaterial,
      );
      await _persistState();
      await _refreshRegisteredDevices();
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (error is SyncApiException && error.statusCode == 401) {
        await _handleUnauthorizedSession(
          'Your sync session is no longer valid. Sign in again to continue.',
        );
        return;
      }
      setState(() {
        _syncMessage = error.toString();
        _statusLabel = 'Recovery failed';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
        });
      }
    }
  }

  Future<void> _startDeviceApproval() async {
    final session = _session;
    if (session == null || session.masterKeyMaterial.isEmpty) {
      setState(() {
        _statusLabel = 'Approval unavailable';
        _syncMessage =
            'Sign in on an existing device before approving another one.';
      });
      return;
    }
    if (await _ensureActiveSession(
      'Your sync session expired on this device. Sign in again to approve devices.',
    )) {
      return;
    }

    final approvalCode = _generateApprovalCode();
    setState(() {
      _statusLabel = 'Creating approval code';
      _syncMessage = null;
    });

    try {
      final expiresAt = await _syncApiClient.startDeviceApproval(
        baseUri: _parseBaseUri(),
        session: session,
        approvalCode: approvalCode,
      );
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => _ApprovalCodeDialog(
          approvalCode: approvalCode,
          expiresAt: expiresAt,
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _statusLabel = 'Approval ready';
        _syncMessage = 'Approval code created for a new device.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (error is SyncApiException && error.statusCode == 401) {
        await _handleUnauthorizedSession(
          'Your sync session is no longer valid. Sign in again to approve devices.',
        );
        return;
      }
      setState(() {
        _statusLabel = 'Approval failed';
        _syncMessage = error.toString();
      });
    }
  }

  Future<void> _consumeDeviceApproval() async {
    final approvalCode = await showDialog<String>(
      context: context,
      builder: (context) => const _ApprovalCodeEntryDialog(),
    );
    if (approvalCode == null || approvalCode.trim().isEmpty) {
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _syncMessage = null;
      _statusLabel = 'Approving device';
    });

    try {
      final session = await _syncApiClient.consumeDeviceApproval(
        baseUri: _parseBaseUri(),
        email: _emailController.text.trim(),
        approvalCode: approvalCode.trim(),
        deviceName: _currentDeviceName(),
        platform: Platform.operatingSystem,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _session = session;
        _statusLabel = 'Device approved';
        _syncMessage = 'Approved this device for ${session.email}.';
      });
      await _secureKeyRepository.saveMasterKey(
        accountId: session.accountId,
        masterKeyMaterial: session.masterKeyMaterial,
      );
      await _persistState();
      await _refreshRegisteredDevices();
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (error is SyncApiException && error.statusCode == 401) {
        await _handleUnauthorizedSession(
          'Your sync session is no longer valid. Sign in again to continue.',
        );
        return;
      }
      setState(() {
        _statusLabel = 'Approval failed';
        _syncMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    final session = _session;
    if (session != null) {
      try {
        await _syncApiClient.logout(
          baseUri: _parseBaseUri(),
          session: session,
        );
      } catch (_) {
        // Local sign-out should still complete if the remote session is already gone.
      }
      await _secureKeyRepository.deleteMasterKey(session.accountId);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _session = null;
      _registeredDevices = const <RegisteredDevice>[];
      _statusLabel = 'Signed out';
      _syncMessage =
          'This device is disconnected from sync. Local notes remain available.';
      _lastSyncError = null;
      _lastSyncAttemptAt = null;
      _lastSyncSuccessAt = null;
      _nextAutoSyncAttemptAt = null;
      _autoSyncFailureCount = 0;
    });
    await _persistState();
  }

  Future<void> _handleUnauthorizedSession(String message) async {
    final session = _session;
    if (session != null) {
      await _secureKeyRepository.deleteMasterKey(session.accountId);
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _session = null;
      _registeredDevices = const <RegisteredDevice>[];
      _statusLabel = 'Session expired';
      _syncMessage = message;
      _lastSyncError = message;
      _nextAutoSyncAttemptAt = null;
      _autoSyncFailureCount = 0;
    });
    await _persistState();
  }

  bool _isSessionExpired(SyncSession? session) {
    final expiresAt = session?.sessionExpiresAt;
    if (expiresAt == null) {
      return false;
    }
    return !expiresAt.isAfter(DateTime.now().toUtc());
  }

  Future<bool> _ensureActiveSession(String message) async {
    final session = _session;
    if (!_isSessionExpired(session)) {
      return false;
    }

    await _handleUnauthorizedSession(message);
    return true;
  }

  Future<void> _authenticate({required bool bootstrap}) async {
    setState(() {
      _isAuthenticating = true;
      _syncMessage = null;
      _statusLabel = bootstrap ? 'Creating account' : 'Signing in';
    });

    try {
      final baseUri = _parseBaseUri();
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final recoveryKey = bootstrap ? _generateRecoveryKey() : null;
      final recoveryKeyHint = recoveryKey == null ? null : 'saved-locally';

      final session = bootstrap
          ? await _syncApiClient.bootstrapAccount(
              baseUri: baseUri,
              email: email,
              password: password,
              recoveryKey: recoveryKey!,
              recoveryKeyHint: recoveryKeyHint!,
              deviceName: _currentDeviceName(),
              platform: Platform.operatingSystem,
            )
          : await _syncApiClient.login(
              baseUri: baseUri,
              email: email,
              password: password,
              deviceName: _currentDeviceName(),
              platform: Platform.operatingSystem,
            );

      if (!mounted) {
        return;
      }

      setState(() {
        _session = session;
        _statusLabel = 'Signed in';
        _syncMessage = bootstrap
            ? 'Account created. Save your recovery key before you continue.'
            : 'Loaded account ${session.email}';
      });
      await _secureKeyRepository.saveMasterKey(
        accountId: session.accountId,
        masterKeyMaterial: session.masterKeyMaterial,
      );
      await _persistState();
      await _refreshRegisteredDevices();
      if (bootstrap && recoveryKey != null && mounted) {
        await _showRecoveryKeyDialog(recoveryKey);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (error is SyncApiException && error.statusCode == 401) {
        await _handleUnauthorizedSession(
          'Your sync session is no longer valid. Sign in again to continue.',
        );
        return;
      }
      setState(() {
        _syncMessage = error.toString();
        _statusLabel = 'Auth failed';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
        });
      }
    }
  }

  Future<void> _syncVault({bool automatic = false}) async {
    final snapshot = _snapshot;
    final session = _session;
    if (snapshot == null || session == null) {
      setState(() {
        _syncMessage = 'Sign in before syncing.';
        _statusLabel = 'Sync unavailable';
      });
      return;
    }
    if (await _ensureActiveSession(
      'Your sync session expired on this device. Sign in again to continue syncing.',
    )) {
      return;
    }

    setState(() {
      _isSyncing = true;
      _statusLabel = 'Syncing';
      _syncMessage = null;
      _lastSyncAttemptAt = DateTime.now();
      _nextAutoSyncAttemptAt = null;
    });

    try {
      final pendingChanges = _buildSyncChanges(snapshot);
      final result = await _syncApiClient.syncVault(
        baseUri: _parseBaseUri(),
        session: session,
        changes: pendingChanges,
        cursor: _syncCursor,
        deviceName: _currentDeviceName(),
        platform: Platform.operatingSystem,
      );

      final pulledNoteChanges = result.pulledChanges
          .where((change) => change.kind == 'note')
          .toList(growable: false);
      final remoteSettings = _latestRemoteSettings(result.pulledChanges);
      final refreshedSnapshot = pulledNoteChanges.isEmpty
          ? snapshot
          : await _repository.applyRemoteChanges(
              rootPath: snapshot.rootPath,
              changes: pulledNoteChanges,
            );
      final effectiveSettings = remoteSettings ?? _settings;

      if (!mounted) {
        return;
      }

      setState(() {
        _replaceSnapshot(refreshedSnapshot, statusLabel: 'Up to date');
        _knownNoteDigests = _buildKnownDigests(refreshedSnapshot);
        _knownTrashDigests = _buildTrashDigests(refreshedSnapshot);
        _settings = effectiveSettings;
        _knownSettingsDigest = effectiveSettings.digest();
        _syncCursor = result.cursor;
        _lastSyncSuccessAt = DateTime.now();
        _nextAutoSyncAttemptAt = null;
        _lastSyncError = null;
        _autoSyncFailureCount = 0;
        _syncMessage =
            'Pushed ${result.pushedCount} changes, pulled ${result.pulledCount} changes.';
      });
      await _persistState();
      await _refreshRegisteredDevices();
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (error is SyncApiException && error.statusCode == 401) {
        await _handleUnauthorizedSession(
          'Your sync session is no longer valid. Sign in again to continue syncing.',
        );
        return;
      }
      setState(() {
        _statusLabel = 'Sync failed';
        _nextAutoSyncAttemptAt = null;
        _lastSyncError = error.toString();
        _syncMessage = error.toString();
      });
      if (automatic) {
        _scheduleRetryAfterFailure();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  void _handleSearchChange() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
    });
  }

  void _handleEditorChange() {
    final selectedNote = _selectedNote;
    if (selectedNote == null || _selectedNoteIsTrashed) {
      return;
    }
    final isDirty = _editorController.text != selectedNote.markdown;
    final nextLabel = isDirty ? 'Unsaved local edits' : 'Loaded locally';
    if (_statusLabel != nextLabel && !_isSaving) {
      setState(() {
        _statusLabel = nextLabel;
      });
    }
  }

  void _selectNote(VaultNote note) {
    setState(() {
      _selectedNote = note;
      _selectedNoteIsTrashed = false;
      _editorController.text = note.markdown;
      _statusLabel = 'Loaded locally';
    });
  }

  Future<void> _selectNoteWithGuard(VaultNote note) async {
    if (!await _confirmSelectionChange(note.title)) {
      return;
    }
    if (!mounted) {
      return;
    }
    _selectNote(note);
  }

  void _selectTrashedNote(VaultNote note) {
    setState(() {
      _selectedNote = note;
      _selectedNoteIsTrashed = true;
      _editorController.text = note.markdown;
      _statusLabel = 'Loaded from trash';
    });
  }

  Future<void> _selectTrashedNoteWithGuard(VaultNote note) async {
    if (!await _confirmSelectionChange(note.title)) {
      return;
    }
    if (!mounted) {
      return;
    }
    _selectTrashedNote(note);
  }

  Future<void> _openLinkedNote(String target) async {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }

    final normalizedTarget = target.trim().toLowerCase();
    for (final note in snapshot.notes) {
      final matchesTitle = note.title.trim().toLowerCase() == normalizedTarget;
      final matchesBasename = note.relativePath
              .split('/')
              .last
              .replaceAll('.md', '')
              .toLowerCase() ==
          normalizedTarget;
      final matchesPath = note.relativePath.toLowerCase() == normalizedTarget ||
          note.relativePath.toLowerCase() == '$normalizedTarget.md';
      if (matchesTitle || matchesBasename || matchesPath) {
        await _selectNoteWithGuard(note);
        return;
      }
    }

    setState(() {
      _statusLabel = 'Link not found locally';
      _syncMessage = 'No local note matched "$target".';
    });
  }

  bool _hasUnsavedEdits() {
    final selectedNote = _selectedNote;
    if (selectedNote == null || _selectedNoteIsTrashed) {
      return false;
    }
    return _editorController.text != selectedNote.markdown;
  }

  Future<bool> _confirmSelectionChange(String targetLabel) async {
    if (!_hasUnsavedEdits()) {
      return true;
    }

    final action = await showDialog<UnsavedChangesAction>(
      context: context,
      builder: (context) => UnsavedChangesDialog(targetLabel: targetLabel),
    );

    switch (action) {
      case UnsavedChangesAction.save:
        await _saveSelectedNote();
        return mounted && !_hasUnsavedEdits();
      case UnsavedChangesAction.discard:
        return true;
      case UnsavedChangesAction.cancel:
      case null:
        return false;
    }
  }

  Uri _parseBaseUri() {
    final raw = _apiBaseUrlController.text.trim();
    final parsed = Uri.tryParse(raw);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      throw Exception('Enter a valid sync API URL.');
    }
    return parsed;
  }

  String _generateRecoveryKey() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final groups = List<String>.generate(4, (_) {
      return List<String>.generate(
        4,
        (_) => alphabet[random.nextInt(alphabet.length)],
      ).join();
    });
    return groups.join('-');
  }

  String _generateApprovalCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final groups = List<String>.generate(3, (_) {
      return List<String>.generate(
        4,
        (_) => alphabet[random.nextInt(alphabet.length)],
      ).join();
    });
    return groups.join('-');
  }

  String _currentDeviceName() {
    final hostName = Platform.localHostname.trim();
    return switch (Platform.operatingSystem) {
      'windows' => hostName.isEmpty ? 'Windows Desktop' : 'Windows $hostName',
      'macos' => hostName.isEmpty ? 'Mac Desktop' : 'Mac $hostName',
      'ios' => 'iPhone or iPad',
      'android' => 'Android Device',
      _ => 'Mnemosyne Device',
    };
  }

  String _normalizeRelativePath(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    return normalized.toLowerCase().endsWith('.md')
        ? normalized
        : '$normalized.md';
  }

  Future<void> _showRecoveryKeyDialog(String recoveryKey) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Save your recovery key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This key is required to recover your encrypted notes if you lose your password.',
            ),
            const SizedBox(height: 12),
            SelectableText(
              recoveryKey,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
            ),
            const SizedBox(height: 12),
            const Text(
              'The server cannot recover this key for you.',
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('I saved it'),
          ),
        ],
      ),
    );
  }

  Future<void> _openCommandPalette() async {
    final noteCommands = _filteredNotes(_snapshot?.notes ?? const <VaultNote>[])
        .take(12)
        .map(
          (note) => _WorkspaceCommand(
            label: 'Open ${note.title}',
            shortcutLabel: note.relativePath,
            icon: Icons.description_outlined,
            onSelected: () async {
              await _selectNoteWithGuard(note);
            },
          ),
        )
        .toList(growable: false);

    final commands = <_WorkspaceCommand>[
      _WorkspaceCommand(
        label: 'Create note',
        shortcutLabel: 'Ctrl/Cmd+N',
        icon: Icons.note_add_outlined,
        onSelected: _createNote,
      ),
      _WorkspaceCommand(
        label: 'Save note',
        shortcutLabel: 'Ctrl/Cmd+S',
        icon: Icons.save_outlined,
        enabled: _selectedNote != null && !_selectedNoteIsTrashed && !_isSaving,
        onSelected: _saveSelectedNote,
      ),
      _WorkspaceCommand(
        label: 'Rename note',
        shortcutLabel: 'Ctrl/Cmd+R',
        icon: Icons.drive_file_rename_outline,
        enabled:
            _selectedNote != null && !_selectedNoteIsTrashed && !_isRenaming,
        onSelected: _renameSelectedNote,
      ),
      _WorkspaceCommand(
        label: _selectedNoteIsTrashed ? 'Restore note' : 'Move note to trash',
        shortcutLabel: 'Ctrl/Cmd+D',
        icon: _selectedNoteIsTrashed
            ? Icons.restore_from_trash_outlined
            : Icons.delete_outline,
        enabled: _selectedNote != null && !_isDeleting,
        onSelected:
            _selectedNoteIsTrashed ? _restoreSelectedNote : _deleteSelectedNote,
      ),
      _WorkspaceCommand(
        label: 'Sync now',
        shortcutLabel: 'Ctrl/Cmd+Shift+S',
        icon: Icons.cloud_upload_outlined,
        enabled: _session != null && !_isSyncing,
        onSelected: _syncVault,
      ),
      _WorkspaceCommand(
        label: 'Open vault',
        shortcutLabel: 'Ctrl/Cmd+O',
        icon: Icons.folder_open,
        onSelected: _openVaultFromInput,
      ),
      ...noteCommands,
    ];

    final selected = await showDialog<_WorkspaceCommand>(
      context: context,
      builder: (context) => _CommandPaletteDialog(commands: commands),
    );
    if (selected != null && mounted) {
      await selected.onSelected();
    }
  }

  Future<void> _persistState() {
    final snapshot = _snapshot;
    return _appStateRepository.save(
      PersistedAppState(
        apiBaseUrl: _apiBaseUrlController.text.trim(),
        email: _emailController.text.trim(),
        session: _session,
        knownNoteDigests: _knownNoteDigests,
        knownSettingsDigest: _knownSettingsDigest,
        knownTrashDigests: _knownTrashDigests,
        lastNoteFolder: _lastNoteFolder,
        settings: _settings,
        showWorkspacePanel: _showWorkspacePanel,
        syncCursor: _syncCursor,
        vaultRootPath: snapshot?.rootPath,
      ),
    );
  }

  Future<void> _startWatchingVault(String rootPath) async {
    await _vaultWatchSubscription?.cancel();
    var isFirstEvent = true;
    _vaultWatchSubscription =
        _repository.watchVault(rootPath).listen((snapshot) {
      if (!mounted) {
        return;
      }
      if (isFirstEvent) {
        isFirstEvent = false;
        return;
      }

      setState(() {
        _replaceSnapshot(snapshot, statusLabel: 'Detected local change');
      });
      _scheduleAutoSync();
    });
  }

  void _scheduleAutoSync() {
    if (_session == null || !_settings.autoSyncEnabled) {
      if (_nextAutoSyncAttemptAt != null) {
        setState(() {
          _nextAutoSyncAttemptAt = null;
        });
      }
      return;
    }

    _autoSyncTimer?.cancel();
    final queuedAt = DateTime.now().add(const Duration(seconds: 2));
    setState(() {
      _nextAutoSyncAttemptAt = queuedAt;
    });
    _autoSyncTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _isSyncing) {
        return;
      }
      final snapshot = _snapshot;
      if (snapshot == null || _buildSyncChanges(snapshot).isEmpty) {
        if (mounted) {
          setState(() {
            _nextAutoSyncAttemptAt = null;
          });
        }
        return;
      }

      setState(() {
        _statusLabel = 'Queued auto sync';
        _nextAutoSyncAttemptAt = null;
      });
      unawaited(_syncVault(automatic: true));
    });
  }

  Future<void> _refreshRegisteredDevices() async {
    final session = _session;
    if (session == null) {
      return;
    }
    if (await _ensureActiveSession(
      'Your sync session expired on this device. Sign in again to load devices.',
    )) {
      return;
    }

    try {
      final devices = await _syncApiClient.listDevices(
        baseUri: _parseBaseUri(),
        session: session,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _registeredDevices = devices;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (error is SyncApiException && error.statusCode == 401) {
        await _handleUnauthorizedSession(
          'Your sync session is no longer valid. Sign in again to load devices.',
        );
        return;
      }
      setState(() {
        _registeredDevices = const <RegisteredDevice>[];
      });
    }
  }

  Future<void> _revokeDevice(RegisteredDevice device) async {
    final session = _session;
    if (session == null) {
      return;
    }
    if (await _ensureActiveSession(
      'Your sync session expired on this device. Sign in again to manage devices.',
    )) {
      return;
    }
    if (!mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Revoke device'),
            content: Text(
              'Disconnect ${device.deviceName} from sync? It will need the recovery key or a new approval code to reconnect.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Revoke'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      return;
    }

    setState(() {
      _statusLabel = 'Revoking device';
      _syncMessage = null;
    });

    try {
      await _syncApiClient.revokeDevice(
        baseUri: _parseBaseUri(),
        session: session,
        deviceId: device.deviceId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _statusLabel = 'Device revoked';
        _syncMessage = '${device.deviceName} was removed from this account.';
      });
      await _refreshRegisteredDevices();
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (error is SyncApiException && error.statusCode == 401) {
        await _handleUnauthorizedSession(
          'Your sync session is no longer valid. Sign in again to manage devices.',
        );
        return;
      }
      setState(() {
        _statusLabel = 'Revoke failed';
        _syncMessage = error.toString();
      });
    }
  }

  void _scheduleRetryAfterFailure() {
    if (_session == null || !_settings.autoSyncEnabled) {
      return;
    }

    _autoSyncFailureCount += 1;
    final delaySeconds = min(30, 2 * _autoSyncFailureCount);
    _autoSyncTimer?.cancel();
    final retryAt = DateTime.now().add(Duration(seconds: delaySeconds));
    setState(() {
      _nextAutoSyncAttemptAt = retryAt;
      _syncMessage = 'Retrying sync at ${_formatTimestamp(retryAt)}.';
    });
    _autoSyncTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!mounted || _isSyncing) {
        return;
      }
      final snapshot = _snapshot;
      if (snapshot == null || _buildSyncChanges(snapshot).isEmpty) {
        if (mounted) {
          setState(() {
            _nextAutoSyncAttemptAt = null;
          });
        }
        return;
      }
      setState(() {
        _statusLabel = 'Retrying sync';
        _nextAutoSyncAttemptAt = null;
      });
      unawaited(_syncVault(automatic: true));
    });
  }

  String _syncStateSummary() {
    if (_isSessionExpired(_session)) {
      return 'Session expired';
    }
    if (_isSyncing) {
      return 'Syncing now';
    }
    if (_lastSyncError != null) {
      return _nextAutoSyncAttemptAt == null
          ? 'Retrying after failure'
          : 'Retry scheduled';
    }
    if (_lastSyncSuccessAt != null) {
      return 'Up to date';
    }
    if (_session == null) {
      return 'Local only';
    }
    return 'Ready to sync';
  }

  String _formatTimestamp(DateTime? value) {
    if (value == null) {
      return 'Never';
    }
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.month}/${local.day} $hour:$minute $suffix';
  }

  String _formatNextAutoSyncAttempt() {
    if (_session == null) {
      return 'Not scheduled';
    }
    final nextAttempt = _nextAutoSyncAttemptAt;
    if (nextAttempt == null) {
      return _settings.autoSyncEnabled ? 'No retry queued' : 'Disabled';
    }
    return _formatTimestamp(nextAttempt);
  }

  void _replaceSnapshot(
    VaultSnapshot snapshot, {
    String? statusLabel,
    String? preferredObjectId,
    bool? preferTrashed,
  }) {
    final targetObjectId = preferredObjectId ?? _selectedNote?.objectId;
    final targetIsTrashed = preferTrashed ?? _selectedNoteIsTrashed;

    VaultNote? matchingNote;
    var nextSelectedIsTrashed = false;
    if (targetObjectId != null) {
      final preferredCollection =
          targetIsTrashed ? snapshot.trashedNotes : snapshot.notes;
      for (final note in preferredCollection) {
        if (note.objectId == targetObjectId) {
          matchingNote = note;
          nextSelectedIsTrashed = targetIsTrashed;
          break;
        }
      }
      if (matchingNote == null) {
        final fallbackCollection =
            targetIsTrashed ? snapshot.notes : snapshot.trashedNotes;
        for (final note in fallbackCollection) {
          if (note.objectId == targetObjectId) {
            matchingNote = note;
            nextSelectedIsTrashed = !targetIsTrashed;
            break;
          }
        }
      }
    }

    final nextSelectedNote = matchingNote ??
        (snapshot.notes.isNotEmpty
            ? snapshot.notes.first
            : (snapshot.trashedNotes.isEmpty
                ? null
                : snapshot.trashedNotes.first));
    if (matchingNote == null && nextSelectedNote != null) {
      nextSelectedIsTrashed = snapshot.notes.isEmpty;
    }

    final shouldPreserveEditor = _selectedNote != null &&
        _editorController.text != _selectedNote!.markdown &&
        !_selectedNoteIsTrashed;

    _snapshot = snapshot;
    if (_selectedFolderFilter != null &&
        !snapshot.folders.contains(_selectedFolderFilter)) {
      _selectedFolderFilter = null;
    }
    _selectedNote = nextSelectedNote;
    _selectedNoteIsTrashed = nextSelectedIsTrashed;
    _vaultPathController.text = snapshot.rootPath;
    if (!shouldPreserveEditor) {
      _editorController.text = nextSelectedNote?.markdown ?? '';
    }
    _statusLabel = statusLabel ?? _statusLabel;
  }

  Future<void> _updateSettings(WorkspaceSettings nextSettings) async {
    if (_settings.digest() == nextSettings.digest()) {
      return;
    }

    setState(() {
      _settings = nextSettings;
      _statusLabel = 'Updated settings locally';
      _syncMessage = 'Workspace settings saved on this device.';
    });
    await _persistState();
    _scheduleAutoSync();
  }

  String? _folderForRelativePath(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    final slashIndex = normalized.lastIndexOf('/');
    if (slashIndex <= 0) {
      return null;
    }
    final folder = normalized.substring(0, slashIndex);
    return folder.isEmpty ? null : folder;
  }

  List<SyncPushChange> _buildSyncChanges(VaultSnapshot snapshot) {
    final nextDigests = _buildKnownDigests(snapshot);
    final nextTrashDigests = _buildTrashDigests(snapshot);
    final changes = <SyncPushChange>[];

    for (final note in snapshot.notes) {
      final nextDigest = nextDigests[note.objectId];
      final knownDigest = _knownNoteDigests[note.objectId];
      if (nextDigest == null || nextDigest == knownDigest) {
        continue;
      }
      changes.add(
        SyncPushChange(
          objectId: note.objectId,
          kind: 'note',
          operation: 'upsert',
          relativePath: note.relativePath,
          title: note.title,
          markdown: note.markdown,
          tags: note.tags,
          wikilinks: note.wikilinks,
        ),
      );
    }

    for (final note in snapshot.trashedNotes) {
      final nextDigest = nextTrashDigests[note.objectId];
      final knownDigest = _knownTrashDigests[note.objectId];
      if (nextDigest == null || nextDigest == knownDigest) {
        continue;
      }
      changes.add(
        SyncPushChange(
          objectId: note.objectId,
          kind: 'note',
          operation: 'trash',
          relativePath: note.relativePath,
          title: note.title,
          markdown: note.markdown,
          tags: note.tags,
          wikilinks: note.wikilinks,
        ),
      );
    }

    for (final objectId in _knownTrashDigests.keys) {
      if (nextTrashDigests.containsKey(objectId) ||
          !nextDigests.containsKey(objectId)) {
        continue;
      }
      final note =
          snapshot.notes.firstWhere((item) => item.objectId == objectId);
      changes.add(
        SyncPushChange(
          objectId: note.objectId,
          kind: 'note',
          operation: 'restore',
          relativePath: note.relativePath,
          title: note.title,
          markdown: note.markdown,
          tags: note.tags,
          wikilinks: note.wikilinks,
        ),
      );
    }

    final nextSettingsDigest = _settings.digest();
    if (nextSettingsDigest != _knownSettingsDigest) {
      changes.add(
        SyncPushChange(
          objectId: 'workspace-settings',
          kind: 'settings',
          operation: 'upsert',
          settings: _settings.toJson(),
        ),
      );
    }

    return changes;
  }

  WorkspaceSettings? _latestRemoteSettings(List<RemoteSyncChange> changes) {
    WorkspaceSettings? latest;
    for (final change in changes) {
      if (change.kind != 'settings' ||
          change.objectId != 'workspace-settings' ||
          change.operation != 'upsert' ||
          change.settings.isEmpty) {
        continue;
      }
      latest = WorkspaceSettings.fromJson(change.settings);
    }
    return latest;
  }

  Map<String, String> _buildKnownDigests(VaultSnapshot snapshot) {
    return <String, String>{
      for (final note in snapshot.notes)
        note.objectId: LocalVaultRepository.noteDigest(note),
    };
  }

  Map<String, String> _buildTrashDigests(VaultSnapshot snapshot) {
    return <String, String>{
      for (final note in snapshot.trashedNotes)
        note.objectId: LocalVaultRepository.noteDigest(note),
    };
  }

  ThemeData _workspaceTheme(BuildContext context) {
    final systemBrightness = MediaQuery.platformBrightnessOf(context);
    final brightness = switch (_settings.themeMode) {
      'light' => Brightness.light,
      'dark' => Brightness.dark,
      _ => systemBrightness,
    };
    final scheme = ColorScheme.fromSeed(
      seedColor: _paletteSeedColor(_settings.colorPalette),
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF11161A) : const Color(0xFFF5F2E8),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF182028) : Colors.white,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF182028) : Colors.white,
      ),
      useMaterial3: true,
    );
  }

  Color _paletteSeedColor(String palette) {
    return switch (palette) {
      'ocean' => const Color(0xFF1F6FA3),
      'amber' => const Color(0xFFB87316),
      'rose' => const Color(0xFFB14C6D),
      'slate' => const Color(0xFF5D6B80),
      _ => const Color(0xFF1C6E5B),
    };
  }

  Widget _buildSidebarPane({
    required ThemeData theme,
    required VaultSnapshot? snapshot,
    required List<VaultNote> selectedTrashedNotes,
    required List<String> selectedFolders,
    required VaultNote? selectedNote,
    required String statusLabel,
  }) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Mnemosyne',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          StatusChip(label: statusLabel),
          const SizedBox(height: 20),
          Text(
            'Vault',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(snapshot?.rootPath ?? ''),
          const SizedBox(height: 12),
          TextField(
            controller: _vaultPathController,
            decoration: const InputDecoration(
              labelText: 'Vault path',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _openVaultFromInput,
            icon: const Icon(Icons.folder_open),
            label: const Text('Open vault'),
          ),
          const SizedBox(height: 20),
          Text(
            'Folders',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            selected: _selectedFolderFilter == null,
            leading: const Icon(Icons.notes_outlined),
            title: const Text('All notes'),
            trailing: Text(
              '${_countNotesInFolder(snapshot?.notes ?? const <VaultNote>[], null)}',
            ),
            onTap: () {
              setState(() {
                _selectedFolderFilter = null;
              });
            },
          ),
          for (final folder in selectedFolders)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              selected: _selectedFolderFilter == folder,
              title: Text(folder),
              leading: const Icon(Icons.folder_open_outlined),
              trailing: Text(
                '${_countNotesInFolder(snapshot?.notes ?? const <VaultNote>[], folder)}',
              ),
              onTap: () {
                setState(() {
                  _selectedFolderFilter = folder;
                });
              },
            ),
          if (selectedTrashedNotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Trash',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            for (final note in selectedTrashedNotes)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(note.title),
                subtitle: Text(note.relativePath),
                leading: const Icon(Icons.delete_outline),
                selected: _selectedNoteIsTrashed &&
                    selectedNote?.objectId == note.objectId,
                onTap: () => unawaited(_selectTrashedNoteWithGuard(note)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsPane({
    required VaultSnapshot? snapshot,
    required VaultNote? selectedNote,
    required int pendingSyncChanges,
  }) {
    return SettingsPanel(
      note: selectedNote,
      noteIsTrashed: _selectedNoteIsTrashed,
      notes: snapshot?.notes ?? const <VaultNote>[],
      trashedNotes: snapshot?.trashedNotes ?? const <VaultNote>[],
      noteCount: snapshot?.notes.length ?? 0,
      settings: _settings,
      syncStatus: _syncStateSummary(),
      pendingSyncChanges: pendingSyncChanges,
      lastSyncAttempt: _formatTimestamp(_lastSyncAttemptAt),
      lastSyncSuccess: _formatTimestamp(_lastSyncSuccessAt),
      lastSyncError: _lastSyncError,
      nextAutoSyncAttempt: _formatNextAutoSyncAttempt(),
      sessionExpiresAt: _session?.sessionExpiresAt,
      devices: _registeredDevices,
      currentDeviceName: _currentDeviceName(),
      currentPlatform: Platform.operatingSystem,
      onSettingsChanged: _updateSettings,
      onRevokeDevice: _revokeDevice,
      accountSection: OnboardingCard(
        apiBaseUrlController: _apiBaseUrlController,
        emailController: _emailController,
        passwordController: _passwordController,
        session: _session,
        syncMessage: _syncMessage,
        isAuthenticating: _isAuthenticating,
        onBootstrap: _bootstrapAccount,
        onLogin: _login,
        onRecover: _recover,
        onConsumeApproval: _consumeDeviceApproval,
        onStartApproval: _startDeviceApproval,
        onSignOut: _signOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _workspaceTheme(context);
    final snapshot = _snapshot;
    final notes = _filteredNotes(snapshot?.notes ?? const []);
    final trashedNotes = _filteredNotes(snapshot?.trashedNotes ?? const []);
    final selectedNote = _selectedNote;
    final selectedFolders = snapshot?.folders ?? const <String>[];
    final pendingSyncChanges =
        snapshot == null ? 0 : _buildSyncChanges(snapshot).length;
    final statusLabel = _isLoading
        ? 'Opening vault'
        : (_statusLabel ?? (_session == null ? 'Local only' : 'Up to date'));

    return Theme(
      data: theme,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
              unawaited(_openCommandPalette()),
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
              unawaited(_openCommandPalette()),
          const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
              unawaited(_openCommandPalette()),
          const SingleActivator(LogicalKeyboardKey.keyP, meta: true): () =>
              unawaited(_openCommandPalette()),
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
              unawaited(_createNote()),
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
              unawaited(_createNote()),
          const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
              unawaited(_openVaultFromInput()),
          const SingleActivator(LogicalKeyboardKey.keyO, meta: true): () =>
              unawaited(_openVaultFromInput()),
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
              unawaited(_saveSelectedNote()),
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
              unawaited(_saveSelectedNote()),
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            control: true,
            shift: true,
          ): () => unawaited(_syncVault()),
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            meta: true,
            shift: true,
          ): () => unawaited(_syncVault()),
          const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
              unawaited(_renameSelectedNote()),
          const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () =>
              unawaited(_renameSelectedNote()),
          const SingleActivator(LogicalKeyboardKey.keyD, control: true): () =>
              unawaited(
                _selectedNoteIsTrashed
                    ? _restoreSelectedNote()
                    : _deleteSelectedNote(),
              ),
          const SingleActivator(LogicalKeyboardKey.keyD, meta: true): () =>
              unawaited(
                _selectedNoteIsTrashed
                    ? _restoreSelectedNote()
                    : _deleteSelectedNote(),
              ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: SafeArea(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, shellConstraints) {
                        final isNarrowShell = shellConstraints.maxWidth < 1200;
                        final sidebarPane = _buildSidebarPane(
                          theme: theme,
                          snapshot: snapshot,
                          selectedTrashedNotes: trashedNotes,
                          selectedFolders: selectedFolders,
                          selectedNote: selectedNote,
                          statusLabel: statusLabel,
                        );
                        final settingsPane = _buildSettingsPane(
                          snapshot: snapshot,
                          selectedNote: selectedNote,
                          pendingSyncChanges: pendingSyncChanges,
                        );

                        final workspacePane = Column(
                          children: [
                            _TopBar(
                              compact: isNarrowShell,
                              showWorkspacePanel: _showWorkspacePanel,
                              searchController: _searchController,
                              isCreating: _isCreating,
                              isRenaming: _isRenaming,
                              isSaving: _isSaving,
                              isDeleting: _isDeleting,
                              isSyncing: _isSyncing,
                              selectedNoteIsTrashed: _selectedNoteIsTrashed,
                              onCreate: _createNote,
                              onRename: _renameSelectedNote,
                              onSave: _saveSelectedNote,
                              onDeleteOrRestore: _selectedNoteIsTrashed
                                  ? _restoreSelectedNote
                                  : _deleteSelectedNote,
                              onToggleWorkspacePanel: () async {
                                setState(() {
                                  _showWorkspacePanel = !_showWorkspacePanel;
                                });
                                await _persistState();
                              },
                              onCommandPalette: _openCommandPalette,
                              onSync: () => _syncVault(),
                            ),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final notesPane = _NotesListPane(
                                    notes: notes,
                                    trashedNotes: trashedNotes,
                                    selectedNoteId: selectedNote?.objectId,
                                    selectedNoteIsTrashed:
                                        _selectedNoteIsTrashed,
                                    backlinksEnabled:
                                        _settings.backlinksEnabled,
                                    onSelect: (note) {
                                      unawaited(_selectNoteWithGuard(note));
                                    },
                                    onSelectTrash: (note) {
                                      unawaited(
                                          _selectTrashedNoteWithGuard(note));
                                    },
                                  );
                                  final editorPane = _EditorPane(
                                    note: selectedNote,
                                    isTrashed: _selectedNoteIsTrashed,
                                    backlinksEnabled:
                                        _settings.backlinksEnabled,
                                    controller: _editorController,
                                    onOpenLinkedNote: _openLinkedNote,
                                  );

                                  if (isNarrowShell) {
                                    final tabChildren = <Widget>[
                                      notesPane,
                                      editorPane,
                                      if (_showWorkspacePanel) settingsPane,
                                    ];
                                    return DefaultTabController(
                                      length: tabChildren.length,
                                      child: Column(
                                        children: [
                                          TabBar(
                                            tabs: [
                                              const Tab(text: 'Notes'),
                                              const Tab(text: 'Editor'),
                                              if (_showWorkspacePanel)
                                                const Tab(text: 'Settings'),
                                            ],
                                          ),
                                          Expanded(
                                            child: TabBarView(
                                                children: tabChildren),
                                          ),
                                        ],
                                      ),
                                    );
                                  }

                                  final isCompact = constraints.maxWidth < 1100;
                                  if (isCompact) {
                                    return Column(
                                      children: [
                                        Expanded(child: notesPane),
                                        const Divider(height: 1),
                                        Expanded(child: editorPane),
                                        if (_showWorkspacePanel) ...[
                                          const Divider(height: 1),
                                          SizedBox(
                                            height: 320,
                                            child: settingsPane,
                                          ),
                                        ],
                                      ],
                                    );
                                  }

                                  return Row(
                                    children: [
                                      SizedBox(width: 320, child: notesPane),
                                      Expanded(child: editorPane),
                                      if (_showWorkspacePanel)
                                        SizedBox(
                                            width: 320, child: settingsPane),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        );

                        if (isNarrowShell) {
                          final sidebarHeight = min(
                            420.0,
                            max(280.0, shellConstraints.maxHeight * 0.38),
                          );
                          return Column(
                            children: [
                              SizedBox(
                                  height: sidebarHeight, child: sidebarPane),
                              const Divider(height: 1),
                              Expanded(child: workspacePane),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            SizedBox(width: 280, child: sidebarPane),
                            Expanded(child: workspacePane),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }

  List<VaultNote> _filteredNotes(List<VaultNote> source) {
    return _noteSearchService.filterAndRank(
      notes: source,
      query: _searchQuery,
      folderFilter: _selectedFolderFilter,
    );
  }

  bool _noteMatchesFolder(VaultNote note, String folder) {
    return note.relativePath == folder ||
        note.relativePath.startsWith('$folder/');
  }

  int _countNotesInFolder(List<VaultNote> notes, String? folder) {
    if (folder == null) {
      return notes.length;
    }
    return notes.where((note) => _noteMatchesFolder(note, folder)).length;
  }
}

class _NewNoteDraft {
  const _NewNoteDraft({
    required this.title,
    required this.relativePath,
  });

  final String title;
  final String relativePath;
}

class _RenameNoteDraft {
  const _RenameNoteDraft({
    required this.relativePath,
  });

  final String relativePath;
}

class _NewNoteDialog extends StatefulWidget {
  const _NewNoteDialog({
    required this.folders,
    this.lastUsedFolder,
  });

  final List<String> folders;
  final String? lastUsedFolder;

  @override
  State<_NewNoteDialog> createState() => _NewNoteDialogState();
}

class _NewNoteDialogState extends State<_NewNoteDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _fileNameController = TextEditingController();
  late String _selectedFolder;
  bool _didEditFileName = false;

  @override
  void initState() {
    super.initState();
    final normalizedFolders = widget.folders.toSet().toList()..sort();
    final preferredFolder = widget.lastUsedFolder;
    _selectedFolder =
        preferredFolder != null && normalizedFolders.contains(preferredFolder)
            ? preferredFolder
            : '';
    _titleController.addListener(_syncFileNameFromTitle);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _fileNameController.dispose();
    super.dispose();
  }

  void _syncFileNameFromTitle() {
    if (_didEditFileName) {
      return;
    }
    final slug = _slugify(_titleController.text);
    if (_fileNameController.text != slug) {
      _fileNameController.text = slug;
    }
  }

  String _slugify(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return normalized;
  }

  @override
  Widget build(BuildContext context) {
    final folderOptions = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: '',
        child: Text('Vault root'),
      ),
      for (final folder in widget.folders.toSet().toList()..sort())
        DropdownMenuItem<String>(
          value: folder,
          child: Text(folder),
        ),
    ];

    return AlertDialog(
      title: const Text('Create note'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedFolder,
            decoration: const InputDecoration(
              labelText: 'Folder',
              border: OutlineInputBorder(),
            ),
            items: folderOptions,
            onChanged: (value) {
              setState(() {
                _selectedFolder = value ?? '';
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _fileNameController,
            decoration: const InputDecoration(
              labelText: 'File name',
              hintText: 'new-note',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _didEditFileName = true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final title = _titleController.text.trim();
            final fileName = _slugify(_fileNameController.text);
            if (title.isEmpty || fileName.isEmpty) {
              return;
            }
            final filePath = '$fileName.md';
            final relativePath = _selectedFolder.isEmpty
                ? filePath
                : '$_selectedFolder/$filePath';
            Navigator.of(context).pop(
              _NewNoteDraft(title: title, relativePath: relativePath),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _RenameNoteDialog extends StatefulWidget {
  const _RenameNoteDialog({
    required this.note,
  });

  final VaultNote note;

  @override
  State<_RenameNoteDialog> createState() => _RenameNoteDialogState();
}

class _RenameNoteDialogState extends State<_RenameNoteDialog> {
  late final TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: widget.note.relativePath);
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename or move note'),
      content: TextField(
        controller: _pathController,
        decoration: const InputDecoration(
          labelText: 'Vault path',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final relativePath = _pathController.text.trim();
            if (relativePath.isEmpty) {
              return;
            }
            Navigator.of(context).pop(
              _RenameNoteDraft(relativePath: relativePath),
            );
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _RecoveryKeyDialog extends StatefulWidget {
  const _RecoveryKeyDialog();

  @override
  State<_RecoveryKeyDialog> createState() => _RecoveryKeyDialogState();
}

class _RecoveryKeyDialogState extends State<_RecoveryKeyDialog> {
  final TextEditingController _recoveryKeyController = TextEditingController();

  @override
  void dispose() {
    _recoveryKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter recovery key'),
      content: TextField(
        controller: _recoveryKeyController,
        decoration: const InputDecoration(
          labelText: 'Recovery key',
          hintText: 'AAAA-BBBB-CCCC-DDDD',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final recoveryKey = _recoveryKeyController.text.trim();
            if (recoveryKey.isEmpty) {
              return;
            }
            Navigator.of(context).pop(recoveryKey);
          },
          child: const Text('Recover'),
        ),
      ],
    );
  }
}

class _ApprovalCodeDialog extends StatelessWidget {
  const _ApprovalCodeDialog({
    required this.approvalCode,
    required this.expiresAt,
  });

  final String approvalCode;
  final String expiresAt;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Approve a new device'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter this code on the new device. It can only be used once.',
          ),
          const SizedBox(height: 12),
          SelectableText(
            approvalCode,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
          ),
          if (expiresAt.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Expires at $expiresAt'),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _ApprovalCodeEntryDialog extends StatefulWidget {
  const _ApprovalCodeEntryDialog();

  @override
  State<_ApprovalCodeEntryDialog> createState() =>
      _ApprovalCodeEntryDialogState();
}

class _ApprovalCodeEntryDialogState extends State<_ApprovalCodeEntryDialog> {
  final TextEditingController _approvalCodeController = TextEditingController();

  @override
  void dispose() {
    _approvalCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter approval code'),
      content: TextField(
        controller: _approvalCodeController,
        decoration: const InputDecoration(
          labelText: 'Approval code',
          hintText: 'AAAA-BBBB-CCCC',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final approvalCode = _approvalCodeController.text.trim();
            if (approvalCode.isEmpty) {
              return;
            }
            Navigator.of(context).pop(approvalCode);
          },
          child: const Text('Approve'),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.compact,
    required this.showWorkspacePanel,
    required this.searchController,
    required this.isCreating,
    required this.isRenaming,
    required this.isSaving,
    required this.isDeleting,
    required this.isSyncing,
    required this.selectedNoteIsTrashed,
    required this.onCreate,
    required this.onRename,
    required this.onSave,
    required this.onDeleteOrRestore,
    required this.onToggleWorkspacePanel,
    required this.onCommandPalette,
    required this.onSync,
  });

  final bool compact;
  final bool showWorkspacePanel;
  final TextEditingController searchController;
  final bool isCreating;
  final bool isRenaming;
  final bool isSaving;
  final bool isDeleting;
  final bool isSyncing;
  final bool selectedNoteIsTrashed;
  final VoidCallback onCreate;
  final VoidCallback onRename;
  final VoidCallback onSave;
  final VoidCallback onDeleteOrRestore;
  final VoidCallback onToggleWorkspacePanel;
  final VoidCallback onCommandPalette;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final actionButtons = <Widget>[
      FilledButton.icon(
        onPressed: isCreating ? null : onCreate,
        icon: Icon(isCreating ? Icons.sync : Icons.note_add_outlined),
        label: Text(isCreating ? 'Creating' : 'New note'),
      ),
      FilledButton.tonalIcon(
        onPressed: isRenaming || selectedNoteIsTrashed ? null : onRename,
        icon: Icon(isRenaming ? Icons.sync : Icons.drive_file_rename_outline),
        label: Text(isRenaming ? 'Renaming' : 'Rename'),
      ),
      FilledButton.icon(
        onPressed: isSaving || selectedNoteIsTrashed ? null : onSave,
        icon: Icon(isSaving ? Icons.sync : Icons.save_outlined),
        label: Text(isSaving ? 'Saving' : 'Save'),
      ),
      FilledButton.tonalIcon(
        onPressed: isDeleting ? null : onDeleteOrRestore,
        icon: Icon(
          isDeleting
              ? Icons.sync
              : (selectedNoteIsTrashed
                  ? Icons.restore_from_trash_outlined
                  : Icons.delete_outline),
        ),
        label: Text(
          isDeleting
              ? (selectedNoteIsTrashed ? 'Restoring' : 'Deleting')
              : (selectedNoteIsTrashed ? 'Restore' : 'Delete'),
        ),
      ),
      FilledButton.tonalIcon(
        onPressed: onCommandPalette,
        icon: const Icon(Icons.keyboard_command_key),
        label: const Text('Command'),
      ),
      FilledButton.tonalIcon(
        onPressed: onToggleWorkspacePanel,
        icon: Icon(
          showWorkspacePanel
              ? Icons.chevron_right_outlined
              : Icons.chevron_left_outlined,
        ),
        label: Text(showWorkspacePanel ? 'Hide panel' : 'Show panel'),
      ),
      FilledButton.tonalIcon(
        onPressed: isSyncing ? null : onSync,
        icon: Icon(isSyncing ? Icons.sync : Icons.cloud_upload_outlined),
        label: Text(isSyncing ? 'Syncing' : 'Sync now'),
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFD7D0C1))),
      ),
      child: compact
          ? Column(
              children: [
                SearchBar(
                  controller: searchController,
                  hintText: 'Search notes on this device',
                  leading: const Icon(Icons.search),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: actionButtons,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: SearchBar(
                    controller: searchController,
                    hintText: 'Search notes on this device',
                    leading: const Icon(Icons.search),
                  ),
                ),
                const SizedBox(width: 12),
                ..._withHorizontalSpacing(actionButtons, 12),
              ],
            ),
    );
  }
}

List<Widget> _withHorizontalSpacing(List<Widget> children, double spacing) {
  if (children.isEmpty) {
    return const <Widget>[];
  }

  final widgets = <Widget>[];
  for (var index = 0; index < children.length; index++) {
    if (index > 0) {
      widgets.add(SizedBox(width: spacing));
    }
    widgets.add(children[index]);
  }
  return widgets;
}

class _WorkspaceCommand {
  const _WorkspaceCommand({
    required this.label,
    required this.shortcutLabel,
    required this.icon,
    required this.onSelected,
    this.enabled = true,
  });

  final String label;
  final String shortcutLabel;
  final IconData icon;
  final Future<void> Function() onSelected;
  final bool enabled;
}

class _CommandPaletteDialog extends StatefulWidget {
  const _CommandPaletteDialog({
    required this.commands,
  });

  final List<_WorkspaceCommand> commands;

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  final TextEditingController _queryController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredCommands = widget.commands.where((command) {
      if (_query.isEmpty) {
        return true;
      }
      final haystack =
          '${command.label} ${command.shortcutLabel}'.toLowerCase();
      return haystack.contains(_query);
    }).toList(growable: false);

    return AlertDialog(
      title: const Text('Command palette'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _queryController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search commands',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _query = value.trim().toLowerCase();
                });
              },
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: filteredCommands.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final command = filteredCommands[index];
                  return Card(
                    child: ListTile(
                      enabled: command.enabled,
                      leading: Icon(command.icon),
                      title: Text(command.label),
                      subtitle: Text(command.shortcutLabel),
                      onTap: command.enabled
                          ? () => Navigator.of(context).pop(command)
                          : null,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _NotesListPane extends StatelessWidget {
  const _NotesListPane({
    required this.notes,
    required this.trashedNotes,
    required this.selectedNoteId,
    required this.selectedNoteIsTrashed,
    required this.backlinksEnabled,
    required this.onSelect,
    required this.onSelectTrash,
  });

  final List<VaultNote> notes;
  final List<VaultNote> trashedNotes;
  final String? selectedNoteId;
  final bool selectedNoteIsTrashed;
  final bool backlinksEnabled;
  final ValueChanged<VaultNote> onSelect;
  final ValueChanged<VaultNote> onSelectTrash;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty && trashedNotes.isEmpty) {
      return const Center(
        child: Text('No Markdown notes matched the current search.'),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final note in notes) ...[
          _NoteCard(
            note: note,
            backlinksEnabled: backlinksEnabled,
            isSelected:
                !selectedNoteIsTrashed && note.objectId == selectedNoteId,
            onTap: () => onSelect(note),
          ),
          const SizedBox(height: 12),
        ],
        if (trashedNotes.isNotEmpty) ...[
          Text(
            'Trash',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          for (final note in trashedNotes) ...[
            _NoteCard(
              note: note,
              trashed: true,
              backlinksEnabled: backlinksEnabled,
              isSelected:
                  selectedNoteIsTrashed && note.objectId == selectedNoteId,
              onTap: () => onSelectTrash(note),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.backlinksEnabled,
    required this.isSelected,
    required this.onTap,
    this.trashed = false,
  });

  final VaultNote note;
  final bool backlinksEnabled;
  final bool isSelected;
  final VoidCallback onTap;
  final bool trashed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = isSelected
        ? (trashed
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.secondaryContainer)
        : theme.cardTheme.color ?? theme.colorScheme.surface;

    return Card(
      color: backgroundColor,
      child: ListTile(
        onTap: onTap,
        title: Text(note.title),
        subtitle: Text(
          '${note.relativePath}\nUpdated ${_formatNoteTimestamp(note.modifiedAt)}',
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (trashed)
              const Icon(Icons.delete_outline, size: 18)
            else if (note.tags.isNotEmpty)
              Text(
                '#${note.tags.first}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            Text(
              trashed
                  ? 'trashed'
                  : (backlinksEnabled
                      ? '${note.backlinks.length} backlinks'
                      : 'backlinks off'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatNoteTimestamp(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final targetDay = DateTime(local.year, local.month, local.day);
  final timeText = _formatTimeOfDay(local);

  if (targetDay == today) {
    return 'today at $timeText';
  }
  if (targetDay == today.subtract(const Duration(days: 1))) {
    return 'yesterday at $timeText';
  }
  return '${local.month}/${local.day}/${local.year} $timeText';
}

String _formatTimeOfDay(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

class _EditorPane extends StatelessWidget {
  const _EditorPane({
    required this.note,
    required this.isTrashed,
    required this.backlinksEnabled,
    required this.controller,
    required this.onOpenLinkedNote,
  });

  final VaultNote? note;
  final bool isTrashed;
  final bool backlinksEnabled;
  final TextEditingController controller;
  final ValueChanged<String> onOpenLinkedNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant),
          right: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: note == null
          ? const Center(child: Text('Select a note to start editing.'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note!.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(note!.relativePath, style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                if (isTrashed)
                  Text(
                    'This note is in trash and is read-only until restored.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF8A5B2C),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in note!.tags) Chip(label: Text('#$tag')),
                    for (final link in note!.wikilinks)
                      ActionChip(
                        avatar: const Icon(Icons.link, size: 16),
                        label: Text(link),
                        onPressed: () => onOpenLinkedNote(link),
                      ),
                    if (backlinksEnabled)
                      for (final backlink in note!.backlinks)
                        ActionChip(
                          avatar: const Icon(Icons.call_split, size: 16),
                          label: Text(backlink),
                          onPressed: () => onOpenLinkedNote(backlink),
                        ),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: MarkdownEditorPane(
                    controller: controller,
                    isReadOnly: isTrashed,
                    onOpenInternalLink: onOpenLinkedNote,
                  ),
                ),
              ],
            ),
    );
  }
}
