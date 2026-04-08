import 'package:flutter/material.dart';

import '../notes/vault_models.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    required this.note,
    required this.noteCount,
    super.key,
  });

  final VaultNote? note;
  final int noteCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: const Color(0xFFF0EBDC),
      padding: const EdgeInsets.all(20),
      child: ListView(
        children: [
          Text(
            'Workspace',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          _SettingTile(
            title: 'Notes',
            subtitle: '$noteCount local Markdown files',
            icon: Icons.description_outlined,
          ),
          const _SettingTile(
            title: 'Theme',
            subtitle: 'System',
            icon: Icons.palette_outlined,
          ),
          const _SettingTile(
            title: 'Sync',
            subtitle: 'Automatic + manual',
            icon: Icons.sync_outlined,
          ),
          const _SettingTile(
            title: 'Backlinks',
            subtitle: 'Enabled',
            icon: Icons.call_split_outlined,
          ),
          const _SettingTile(
            title: 'Graph view',
            subtitle: 'Depth 2',
            icon: Icons.hub_outlined,
          ),
          const _SettingTile(
            title: 'Trash',
            subtitle: 'Synced across devices',
            icon: Icons.delete_outline,
          ),
          if (note != null) ...[
            const SizedBox(height: 24),
            Text(
              'Selected Note',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            _SettingTile(
              title: 'Path',
              subtitle: note!.relativePath,
              icon: Icons.folder_outlined,
            ),
            _SettingTile(
              title: 'Tags',
              subtitle: note!.tags.isEmpty ? 'None yet' : note!.tags.join(', '),
              icon: Icons.sell_outlined,
            ),
            _SettingTile(
              title: 'Wikilinks',
              subtitle: note!.wikilinks.isEmpty
                  ? 'No outgoing links'
                  : note!.wikilinks.join(', '),
              icon: Icons.link_outlined,
            ),
            _SettingTile(
              title: 'Backlinks',
              subtitle: note!.backlinks.isEmpty
                  ? 'No backlinks yet'
                  : note!.backlinks.join(', '),
              icon: Icons.call_split_outlined,
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}
