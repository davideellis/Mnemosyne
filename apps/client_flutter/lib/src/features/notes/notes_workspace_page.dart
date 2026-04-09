import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/status_chip.dart';
import '../onboarding/onboarding_card.dart';
import '../settings/settings_panel.dart';
import '../settings/workspace_settings.dart';
import 'app_state_repository.dart';
import 'local_vault_repository.dart';
import 'secure_key_repository.dart';
import 'sync_api_client.dart';
import 'sync_models.dart';
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
  WorkspaceSettings _settings = const WorkspaceSettings();
  String _syncCursor = '';
  String? _syncMessage;
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
      _settings = persistedState.settings;
      _syncCursor = persistedState.syncCursor ?? '';
      _apiBaseUrlController.text =
          persistedState.apiBaseUrl ?? _apiBaseUrlController.text;
      _vaultPathController.text = snapshot.rootPath;
      _emailController.text = persistedState.email ?? _emailController.text;
      _isLoading = false;
      _statusLabel =
          hydratedSession == null ? 'Loaded locally' : 'Signed in';
      _syncMessage = hydratedSession == null
          ? 'Local vault ready.'
          : 'Restored signed-in session for ${hydratedSession.email}.';
      _editorController.text = initialNote?.markdown ?? '';
    });
    _startWatchingVault(snapshot.rootPath);
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
      builder: (context) => const _NewNoteDialog(),
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
      _statusLabel = 'Restoring locally';
    });

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
    });
    await _persistState();
    _scheduleAutoSync();
  }

  Future<void> _openVaultFromInput() async {
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
    } catch (error) {
      if (!mounted) {
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
              deviceName: 'Windows Desktop',
              platform: 'windows',
            )
          : await _syncApiClient.login(
              baseUri: baseUri,
              email: email,
              password: password,
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
      if (bootstrap && recoveryKey != null && mounted) {
        await _showRecoveryKeyDialog(recoveryKey);
      }
    } catch (error) {
      if (!mounted) {
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

  Future<void> _syncVault() async {
    final snapshot = _snapshot;
    final session = _session;
    if (snapshot == null || session == null) {
      setState(() {
        _syncMessage = 'Sign in before syncing.';
        _statusLabel = 'Sync unavailable';
      });
      return;
    }

    setState(() {
      _isSyncing = true;
      _statusLabel = 'Syncing';
      _syncMessage = null;
    });

    try {
      final pendingChanges = _buildSyncChanges(snapshot);
      final result = await _syncApiClient.syncVault(
        baseUri: _parseBaseUri(),
        session: session,
        changes: pendingChanges,
        cursor: _syncCursor,
        deviceName: 'Windows Desktop',
        platform: 'windows',
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
        _syncMessage =
            'Pushed ${result.pushedCount} changes, pulled ${result.pulledCount} changes.';
      });
      await _persistState();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusLabel = 'Sync failed';
        _syncMessage = error.toString();
      });
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

  void _selectTrashedNote(VaultNote note) {
    setState(() {
      _selectedNote = note;
      _selectedNoteIsTrashed = true;
      _editorController.text = note.markdown;
      _statusLabel = 'Loaded from trash';
    });
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
        settings: _settings,
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
      return;
    }

    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _isSyncing) {
        return;
      }
      final snapshot = _snapshot;
      if (snapshot == null || _buildSyncChanges(snapshot).isEmpty) {
        return;
      }

      setState(() {
        _statusLabel = 'Queued auto sync';
      });
      unawaited(_syncVault());
    });
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = _snapshot;
    final notes = _filteredNotes(snapshot?.notes ?? const []);
    final trashedNotes = _filteredNotes(snapshot?.trashedNotes ?? const []);
    final selectedNote = _selectedNote;
    final selectedFolders = snapshot?.folders ?? const <String>[];
    final statusLabel = _isLoading
        ? 'Opening vault'
        : (_statusLabel ?? (_session == null ? 'Local only' : 'Up to date'));

    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Row(
                children: [
                  Container(
                    width: 280,
                    padding: const EdgeInsets.all(20),
                    color: const Color(0xFFE5E0D2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                        Expanded(
                          child: ListView(
                            children: [
                              for (final folder in selectedFolders)
                                ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(folder),
                                  leading:
                                      const Icon(Icons.folder_open_outlined),
                                ),
                            ],
                          ),
                        ),
                        if (trashedNotes.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Trash',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 140,
                            child: ListView(
                              children: [
                                for (final note in trashedNotes)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(note.title),
                                    subtitle: Text(note.relativePath),
                                    leading: const Icon(Icons.delete_outline),
                                    selected: _selectedNoteIsTrashed &&
                                        selectedNote?.objectId == note.objectId,
                                    onTap: () => _selectTrashedNote(note),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        OnboardingCard(
                          apiBaseUrlController: _apiBaseUrlController,
                          emailController: _emailController,
                          passwordController: _passwordController,
                          session: _session,
                          syncMessage: _syncMessage,
                          isAuthenticating: _isAuthenticating,
                          onBootstrap: _bootstrapAccount,
                          onLogin: _login,
                          onRecover: _recover,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        _TopBar(
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
                          onSync: _syncVault,
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isCompact = constraints.maxWidth < 1100;
                              final notesPane = _NotesListPane(
                                notes: notes,
                                trashedNotes: trashedNotes,
                                selectedNoteId: selectedNote?.objectId,
                                selectedNoteIsTrashed: _selectedNoteIsTrashed,
                                onSelect: _selectNote,
                                onSelectTrash: _selectTrashedNote,
                              );
                              final editorPane = _EditorPane(
                                note: selectedNote,
                                isTrashed: _selectedNoteIsTrashed,
                                controller: _editorController,
                              );

                              if (isCompact) {
                                return Column(
                                  children: [
                                    Expanded(child: notesPane),
                                    const Divider(height: 1),
                                    Expanded(child: editorPane),
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  SizedBox(width: 320, child: notesPane),
                                  Expanded(child: editorPane),
                                  SizedBox(
                                    width: 320,
                                    child: SettingsPanel(
                                      note: selectedNote,
                                      noteIsTrashed: _selectedNoteIsTrashed,
                                      notes: snapshot?.notes ??
                                          const <VaultNote>[],
                                      trashedNotes: snapshot?.trashedNotes ??
                                          const <VaultNote>[],
                                      noteCount: snapshot?.notes.length ?? 0,
                                      settings: _settings,
                                      onSettingsChanged: _updateSettings,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  List<VaultNote> _filteredNotes(List<VaultNote> source) {
    if (_searchQuery.isEmpty) {
      return source;
    }

    return source.where((note) {
      final haystack = [
        note.title,
        note.relativePath,
        note.markdown,
        note.tags.join(' '),
        note.wikilinks.join(' '),
      ].join('\n').toLowerCase();
      return haystack.contains(_searchQuery);
    }).toList(growable: false);
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
  const _NewNoteDialog();

  @override
  State<_NewNoteDialog> createState() => _NewNoteDialogState();
}

class _NewNoteDialogState extends State<_NewNoteDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _pathController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          TextField(
            controller: _pathController,
            decoration: const InputDecoration(
              labelText: 'Vault path',
              hintText: 'Journal/new-note.md',
              border: OutlineInputBorder(),
            ),
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
            final relativePath = _pathController.text.trim();
            if (title.isEmpty || relativePath.isEmpty) {
              return;
            }
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

class _TopBar extends StatelessWidget {
  const _TopBar({
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
    required this.onSync,
  });

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
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFD7D0C1))),
      ),
      child: Row(
        children: [
          Expanded(
            child: SearchBar(
              controller: searchController,
              hintText: 'Search notes on this device',
              leading: const Icon(Icons.search),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: isCreating ? null : onCreate,
            icon: Icon(isCreating ? Icons.sync : Icons.note_add_outlined),
            label: Text(isCreating ? 'Creating' : 'New note'),
          ),
          const SizedBox(width: 12),
          FilledButton.tonalIcon(
            onPressed: isRenaming || selectedNoteIsTrashed ? null : onRename,
            icon:
                Icon(isRenaming ? Icons.sync : Icons.drive_file_rename_outline),
            label: Text(isRenaming ? 'Renaming' : 'Rename'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: isSaving || selectedNoteIsTrashed ? null : onSave,
            icon: Icon(isSaving ? Icons.sync : Icons.save_outlined),
            label: Text(isSaving ? 'Saving' : 'Save'),
          ),
          const SizedBox(width: 12),
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
          const SizedBox(width: 12),
          FilledButton.tonalIcon(
            onPressed: isSyncing ? null : onSync,
            icon: Icon(isSyncing ? Icons.sync : Icons.cloud_upload_outlined),
            label: Text(isSyncing ? 'Syncing' : 'Sync now'),
          ),
        ],
      ),
    );
  }
}

class _NotesListPane extends StatelessWidget {
  const _NotesListPane({
    required this.notes,
    required this.trashedNotes,
    required this.selectedNoteId,
    required this.selectedNoteIsTrashed,
    required this.onSelect,
    required this.onSelectTrash,
  });

  final List<VaultNote> notes;
  final List<VaultNote> trashedNotes;
  final String? selectedNoteId;
  final bool selectedNoteIsTrashed;
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
    required this.isSelected,
    required this.onTap,
    this.trashed = false,
  });

  final VaultNote note;
  final bool isSelected;
  final VoidCallback onTap;
  final bool trashed;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isSelected
          ? (trashed ? const Color(0xFFF7E7D8) : const Color(0xFFE9F5EE))
          : const Color(0xFFFFFBF2),
      child: ListTile(
        onTap: onTap,
        title: Text(note.title),
        subtitle: Text(note.relativePath),
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
              trashed ? 'trashed' : '${note.backlinks.length} backlinks',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorPane extends StatelessWidget {
  const _EditorPane({
    required this.note,
    required this.isTrashed,
    required this.controller,
  });

  final VaultNote? note;
  final bool isTrashed;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: Color(0xFFD7D0C1)),
          right: BorderSide(color: Color(0xFFD7D0C1)),
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
                      Chip(
                        avatar: const Icon(Icons.link, size: 16),
                        label: Text(link),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: TextField(
                    controller: controller,
                    readOnly: isTrashed,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Write Markdown here...',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
