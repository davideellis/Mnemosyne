import 'package:flutter/material.dart';

import '../../widgets/status_chip.dart';
import '../onboarding/onboarding_card.dart';
import '../settings/settings_panel.dart';
import 'local_vault_repository.dart';
import 'vault_models.dart';

class NotesWorkspacePage extends StatefulWidget {
  const NotesWorkspacePage({super.key});

  @override
  State<NotesWorkspacePage> createState() => _NotesWorkspacePageState();
}

class _NotesWorkspacePageState extends State<NotesWorkspacePage> {
  final LocalVaultRepository _repository = LocalVaultRepository();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _editorController = TextEditingController();

  VaultSnapshot? _snapshot;
  VaultNote? _selectedNote;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _statusLabel;
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
    _searchController.dispose();
    _editorController.dispose();
    super.dispose();
  }

  Future<void> _loadVault() async {
    final snapshot = await _repository.loadInitialVault();
    final initialNote = snapshot.notes.isEmpty ? null : snapshot.notes.first;
    if (!mounted) {
      return;
    }

    setState(() {
      _snapshot = snapshot;
      _selectedNote = initialNote;
      _isLoading = false;
      _statusLabel = 'Loaded locally';
      _editorController.text = initialNote?.markdown ?? '';
    });
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
      _selectedNote = updatedNote ?? (updatedSnapshot.notes.isEmpty ? null : updatedSnapshot.notes.first);
      _editorController.text = _selectedNote?.markdown ?? '';
      _statusLabel = 'Saved locally';
      _isSaving = false;
    });
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = _snapshot;
    final notes = _filteredNotes(snapshot?.notes ?? const []);
    final selectedNote = _selectedNote;
    final selectedFolders = snapshot?.folders ?? const <String>[];
    final statusLabel = _isLoading ? 'Opening vault' : (_statusLabel ?? 'Up to date');

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
                                  leading: const Icon(Icons.folder_open_outlined),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const OnboardingCard(),
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
                                onPressed: _isSaving ? null : _saveSelectedNote,
                                icon: Icon(_isSaving ? Icons.sync : Icons.save_outlined),
                                label: Text(_isSaving ? 'Saving' : 'Save'),
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
                    for (final tag in note!.tags)
                      Chip(label: Text('#$tag')),
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
