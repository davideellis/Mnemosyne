import 'package:flutter/material.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

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

