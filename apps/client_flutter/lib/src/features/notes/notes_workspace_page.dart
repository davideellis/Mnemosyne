import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/status_chip.dart';
import '../onboarding/onboarding_card.dart';
import '../settings/settings_panel.dart';
import 'app_state_repository.dart';
import 'local_vault_repository.dart';
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

  VaultSnapshot? _snapshot;
  VaultNote? _selectedNote;
  SyncSession? _session;
  bool _isLoading = true;
  bool _isCreating = false;
  bool _isSaving = false;
  bool _isDeleting = false;
  bool _isSyncing = false;
  bool _isAuthenticating = false;
  String? _statusLabel;
  Map<String, String> _knownNoteDigests = <String, String>{};
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
      _session = persistedState.session;
      _knownNoteDigests = Map<String, String>.from(
        persistedState.knownNoteDigests,
      );
      _syncCursor = persistedState.syncCursor ?? '';
      _apiBaseUrlController.text =
          persistedState.apiBaseUrl ?? _apiBaseUrlController.text;
      _vaultPathController.text = snapshot.rootPath;
      _emailController.text = persistedState.email ?? _emailController.text;
      _isLoading = false;
      _statusLabel =
          persistedState.session == null ? 'Loaded locally' : 'Signed in';
      _syncMessage = persistedState.session == null
          ? 'Local vault ready.'
          : 'Restored signed-in session for ${persistedState.session!.email}.';
      _editorController.text = initialNote?.markdown ?? '';
    });
    _startWatchingVault(snapshot.rootPath);
  }

  Future<void> _saveSelectedNote() async {
    final snapshot = _snapshot;
    final note = _selectedNote;
    if (snapshot == null || note == null) {
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

    VaultNote? updatedNote;
    for (final candidate in updatedSnapshot.notes) {
      if (candidate.objectId == note.objectId) {
        updatedNote = candidate;
        break;
      }
    }

    setState(() {
      _snapshot = updatedSnapshot;
      _selectedNote = updatedNote ??
          (updatedSnapshot.notes.isEmpty ? null : updatedSnapshot.notes.first);
      _editorController.text = _selectedNote?.markdown ?? '';
      _statusLabel = 'Saved locally';
      _isSaving = false;
    });
    await _persistState();
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

  Future<void> _deleteSelectedNote() async {
    final snapshot = _snapshot;
    final note = _selectedNote;
    if (snapshot == null || note == null) {
      return;
    }

    setState(() {
      _isDeleting = true;
      _statusLabel = 'Deleting locally';
    });

    final updatedSnapshot = await _repository.deleteNote(
      rootPath: snapshot.rootPath,
      note: note,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _replaceSnapshot(updatedSnapshot, statusLabel: 'Deleted locally');
      _isDeleting = false;
    });
    await _persistState();
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

      final session = bootstrap
          ? await _syncApiClient.bootstrapAccount(
              baseUri: baseUri,
              email: email,
              password: password,
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
        _syncMessage =
            '${bootstrap ? 'Created' : 'Loaded'} account ${session.email}';
      });
      await _persistState();
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
      final result = await _syncApiClient.syncVault(
        baseUri: _parseBaseUri(),
        session: session,
        changes: _buildSyncChanges(snapshot),
        cursor: _syncCursor,
        deviceName: 'Windows Desktop',
        platform: 'windows',
      );

      final refreshedSnapshot = result.pulledChanges.isEmpty
          ? snapshot
          : await _repository.applyRemoteChanges(
              rootPath: snapshot.rootPath,
              changes: result.pulledChanges,
            );

      if (!mounted) {
        return;
      }

      setState(() {
        _replaceSnapshot(
          refreshedSnapshot,
          statusLabel: 'Up to date',
        );
        _knownNoteDigests = _buildKnownDigests(refreshedSnapshot);
        _syncCursor = result.cursor;
        _syncMessage =
            'Pushed ${result.pushedCount} notes, pulled ${result.pulledCount} changes.';
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
    if (selectedNote == null) {
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
      _editorController.text = note.markdown;
      _statusLabel = 'Loaded locally';
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

  Future<void> _persistState() {
    final snapshot = _snapshot;
    return _appStateRepository.save(
      PersistedAppState(
        apiBaseUrl: _apiBaseUrlController.text.trim(),
        email: _emailController.text.trim(),
        session: _session,
        knownNoteDigests: _knownNoteDigests,
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
    });
  }

  void _replaceSnapshot(
    VaultSnapshot snapshot, {
    String? statusLabel,
  }) {
    final previousNote = _selectedNote;
    VaultNote? matchingNote;
    if (previousNote != null) {
      for (final note in snapshot.notes) {
        if (note.objectId == previousNote.objectId) {
          matchingNote = note;
          break;
        }
      }
    }
    final nextSelectedNote =
        matchingNote ?? (snapshot.notes.isEmpty ? null : snapshot.notes.first);
    final shouldPreserveEditor =
        previousNote != null && _editorController.text != previousNote.markdown;

    _snapshot = snapshot;
    _selectedNote = nextSelectedNote;
    _vaultPathController.text = snapshot.rootPath;
    if (!shouldPreserveEditor) {
      _editorController.text = nextSelectedNote?.markdown ?? '';
    }
    _statusLabel = statusLabel ?? _statusLabel;
  }

  List<SyncPushChange> _buildSyncChanges(VaultSnapshot snapshot) {
    final nextDigests = _buildKnownDigests(snapshot);
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
          operation: 'upsert',
          relativePath: note.relativePath,
          title: note.title,
          markdown: note.markdown,
          tags: note.tags,
          wikilinks: note.wikilinks,
        ),
      );
    }

    for (final objectId in _knownNoteDigests.keys) {
      if (nextDigests.containsKey(objectId)) {
        continue;
      }

      changes.add(
        SyncPushChange(
          objectId: objectId,
          operation: 'trash',
          relativePath: objectId,
          title: objectId,
          markdown: '',
          tags: const <String>[],
          wikilinks: const <String>[],
        ),
      );
    }

    return changes;
  }

  Map<String, String> _buildKnownDigests(VaultSnapshot snapshot) {
    return <String, String>{
      for (final note in snapshot.notes)
        note.objectId: LocalVaultRepository.noteDigest(note),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = _snapshot;
    final notes = _filteredNotes(snapshot?.notes ?? const []);
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
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Color(0xFFD7D0C1)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: SearchBar(
                                  controller: _searchController,
                                  hintText: 'Search notes on this device',
                                  leading: const Icon(Icons.search),
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilledButton.icon(
                                onPressed: _isCreating ? null : _createNote,
                                icon: Icon(
                                  _isCreating
                                      ? Icons.sync
                                      : Icons.note_add_outlined,
                                ),
                                label:
                                    Text(_isCreating ? 'Creating' : 'New note'),
                              ),
                              const SizedBox(width: 12),
                              FilledButton.icon(
                                onPressed: _isSaving ? null : _saveSelectedNote,
                                icon: Icon(_isSaving
                                    ? Icons.sync
                                    : Icons.save_outlined),
                                label: Text(_isSaving ? 'Saving' : 'Save'),
                              ),
                              const SizedBox(width: 12),
                              FilledButton.tonalIcon(
                                onPressed:
                                    _isDeleting ? null : _deleteSelectedNote,
                                icon: Icon(
                                  _isDeleting
                                      ? Icons.sync
                                      : Icons.delete_outline,
                                ),
                                label:
                                    Text(_isDeleting ? 'Deleting' : 'Delete'),
                              ),
                              const SizedBox(width: 12),
                              FilledButton.tonalIcon(
                                onPressed: _isSyncing ? null : _syncVault,
                                icon: Icon(_isSyncing
                                    ? Icons.sync
                                    : Icons.cloud_upload_outlined),
                                label:
                                    Text(_isSyncing ? 'Syncing' : 'Sync now'),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isCompact = constraints.maxWidth < 1100;

                              if (isCompact) {
                                return Column(
                                  children: [
                                    Expanded(
                                      child: _NotesListPane(
                                        notes: notes,
                                        selectedNoteId: selectedNote?.objectId,
                                        onSelect: _selectNote,
                                      ),
                                    ),
                                    const Divider(height: 1),
                                    Expanded(
                                      child: _EditorPane(
                                        note: selectedNote,
                                        controller: _editorController,
                                      ),
                                    ),
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  SizedBox(
                                    width: 320,
                                    child: _NotesListPane(
                                      notes: notes,
                                      selectedNoteId: selectedNote?.objectId,
                                      onSelect: _selectNote,
                                    ),
                                  ),
                                  Expanded(
                                    child: _EditorPane(
                                      note: selectedNote,
                                      controller: _editorController,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 320,
                                    child: SettingsPanel(
                                      note: selectedNote,
                                      notes: snapshot?.notes ??
                                          const <VaultNote>[],
                                      noteCount: snapshot?.notes.length ?? 0,
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
              _NewNoteDraft(
                title: title,
                relativePath: relativePath,
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _NotesListPane extends StatelessWidget {
  const _NotesListPane({
    required this.notes,
    required this.selectedNoteId,
    required this.onSelect,
  });

  final List<VaultNote> notes;
  final String? selectedNoteId;
  final ValueChanged<VaultNote> onSelect;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return const Center(
        child: Text('No Markdown notes matched the current search.'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: notes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final note = notes[index];
        final isSelected = note.objectId == selectedNoteId;
        return Card(
          color: isSelected ? const Color(0xFFE9F5EE) : const Color(0xFFFFFBF2),
          child: ListTile(
            onTap: () => onSelect(note),
            title: Text(note.title),
            subtitle: Text(note.relativePath),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (note.tags.isNotEmpty)
                  Text(
                    '#${note.tags.first}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                Text(
                  '${note.backlinks.length} backlinks',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EditorPane extends StatelessWidget {
  const _EditorPane({
    required this.note,
    required this.controller,
  });

  final VaultNote? note;
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
                Text(
                  note!.relativePath,
                  style: theme.textTheme.bodySmall,
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
