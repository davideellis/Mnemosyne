import 'package:flutter/material.dart';

import '../onboarding/onboarding_card.dart';
import '../settings/settings_panel.dart';
import '../../widgets/status_chip.dart';

class NotesWorkspacePage extends StatelessWidget {
  const NotesWorkspacePage({super.key});

  static const _folders = <String>[
    'Journal',
    'Projects',
    'Reading',
    'Archive',
  ];

  static const _notes = <({String title, String path, String excerpt})>[
    (
      title: 'Welcome to Mnemosyne',
      path: 'Journal/welcome.md',
      excerpt:
          'Notes are plain Markdown files stored in your chosen folder and synced end-to-end encrypted.',
    ),
    (
      title: 'Roadmap',
      path: 'Projects/roadmap.md',
      excerpt:
          'MVP includes single-user sync, folders, tags, wikilinks, backlinks, graph view, and synced trash.',
    ),
    (
      title: 'Recovery Key',
      path: 'Journal/recovery-key.md',
      excerpt:
          'Recovery keys are required because operators cannot decrypt or recover note contents for you.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Row(
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
                  const StatusChip(label: 'Up to date'),
                  const SizedBox(height: 20),
                  Text(
                    'Vault',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('C:\\Users\\you\\Documents\\Mnemosyne'),
                  const SizedBox(height: 20),
                  Text(
                    'Folders',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final folder in _folders)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(folder),
                      leading: const Icon(Icons.folder_open_outlined),
                    ),
                  const Spacer(),
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
                            hintText: 'Search notes on this device',
                            leading: const Icon(Icons.search),
                            onTap: () {},
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.sync),
                          label: const Text('Sync now'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        SizedBox(
                          width: 320,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(20),
                            itemCount: _notes.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final note = _notes[index];
                              return Card(
                                color: const Color(0xFFFFFBF2),
                                child: ListTile(
                                  title: Text(note.title),
                                  subtitle: Text(note.path),
                                  trailing: const Icon(Icons.chevron_right),
                                ),
                              );
                            },
                          ),
                        ),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: const BoxDecoration(
                              border: Border(
                                left: BorderSide(color: Color(0xFFD7D0C1)),
                                right: BorderSide(color: Color(0xFFD7D0C1)),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _notes.first.title,
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _notes.first.path,
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(height: 20),
                                Expanded(
                                  child: TextField(
                                    expands: true,
                                    maxLines: null,
                                    minLines: null,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      hintText: 'Write Markdown here...',
                                    ),
                                    controller: TextEditingController(
                                      text:
                                          '# Welcome to Mnemosyne\n\n'
                                          'This desktop shell shows the core MVP surfaces:\n'
                                          '- local Markdown files\n'
                                          '- synced folders\n'
                                          '- local search\n'
                                          '- synced settings\n'
                                          '- backlinks and graph view\n',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 320,
                          child: SettingsPanel(),
                        ),
                      ],
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
}

