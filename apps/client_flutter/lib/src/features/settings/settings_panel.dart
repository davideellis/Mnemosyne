import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../notes/sync_models.dart';
import '../notes/vault_models.dart';
import 'workspace_settings.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    required this.note,
    required this.noteIsTrashed,
    required this.notes,
    required this.trashedNotes,
    required this.noteCount,
    required this.settings,
    required this.syncStatus,
    required this.lastSyncAttempt,
    required this.lastSyncSuccess,
    required this.lastSyncError,
    required this.devices,
    required this.onSettingsChanged,
    super.key,
  });

  final VaultNote? note;
  final bool noteIsTrashed;
  final List<VaultNote> notes;
  final List<VaultNote> trashedNotes;
  final int noteCount;
  final WorkspaceSettings settings;
  final String syncStatus;
  final String lastSyncAttempt;
  final String lastSyncSuccess;
  final String? lastSyncError;
  final List<RegisteredDevice> devices;
  final ValueChanged<WorkspaceSettings> onSettingsChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surfaceContainerHigh,
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
          _ChoiceTile(
            title: 'Theme',
            subtitle: settings.themeMode,
            icon: Icons.palette_outlined,
            value: settings.themeMode,
            options: const <String>['system', 'light', 'dark'],
            onChanged: (value) => onSettingsChanged(
              settings.copyWith(themeMode: value),
            ),
          ),
          _ToggleTile(
            title: 'Sync',
            subtitle: settings.autoSyncEnabled
                ? 'Automatic + manual'
                : 'Manual only',
            icon: Icons.sync_outlined,
            value: settings.autoSyncEnabled,
            onChanged: (value) => onSettingsChanged(
              settings.copyWith(autoSyncEnabled: value),
            ),
          ),
          _SettingTile(
            title: 'Sync Status',
            subtitle: syncStatus,
            icon: Icons.cloud_done_outlined,
          ),
          _SettingTile(
            title: 'Last Attempt',
            subtitle: lastSyncAttempt,
            icon: Icons.schedule_outlined,
          ),
          _SettingTile(
            title: 'Last Success',
            subtitle: lastSyncSuccess,
            icon: Icons.check_circle_outline,
          ),
          if (lastSyncError != null)
            _SettingTile(
              title: 'Last Error',
              subtitle: lastSyncError!,
              icon: Icons.error_outline,
            ),
          _ToggleTile(
            title: 'Backlinks',
            subtitle: settings.backlinksEnabled ? 'Enabled' : 'Disabled',
            icon: Icons.call_split_outlined,
            value: settings.backlinksEnabled,
            onChanged: (value) => onSettingsChanged(
              settings.copyWith(backlinksEnabled: value),
            ),
          ),
          _ChoiceTile(
            title: 'Graph view',
            subtitle: 'Depth ${settings.graphDepth}',
            icon: Icons.hub_outlined,
            value: settings.graphDepth.toString(),
            options: const <String>['1', '2', '3'],
            onChanged: (value) => onSettingsChanged(
              settings.copyWith(graphDepth: int.parse(value)),
            ),
          ),
          const _SettingTile(
            title: 'Trash',
            subtitle: 'Synced across devices',
            icon: Icons.delete_outline,
          ),
          _SettingTile(
            title: 'Trashed Notes',
            subtitle: '${trashedNotes.length} in synced trash',
            icon: Icons.restore_from_trash_outlined,
          ),
          _SettingTile(
            title: 'Registered Devices',
            subtitle:
                devices.isEmpty ? 'No devices loaded' : '${devices.length} device(s)',
            icon: Icons.devices_outlined,
          ),
          if (devices.isNotEmpty)
            Card(
              child: Column(
                children: [
                  for (final device in devices)
                    ListTile(
                      leading: const Icon(Icons.devices_outlined),
                      title: Text(device.deviceName),
                      subtitle: Text(device.platform),
                    ),
                ],
              ),
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
              title: 'State',
              subtitle: noteIsTrashed ? 'In trash' : 'Active',
              icon: noteIsTrashed
                  ? Icons.delete_outline
                  : Icons.description_outlined,
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
              subtitle: settings.backlinksEnabled
                  ? (note!.backlinks.isEmpty
                      ? 'No backlinks yet'
                      : note!.backlinks.join(', '))
                  : 'Disabled for this workspace',
              icon: Icons.call_split_outlined,
            ),
            const SizedBox(height: 16),
            _GraphCard(
              selectedNote: note!,
              notes: notes,
              settings: settings,
            ),
          ],
        ],
      ),
    );
  }
}

class _GraphCard extends StatelessWidget {
  const _GraphCard({
    required this.selectedNote,
    required this.notes,
    required this.settings,
  });

  final VaultNote selectedNote;
  final List<VaultNote> notes;
  final WorkspaceSettings settings;

  @override
  Widget build(BuildContext context) {
    final linkedTitles = _graphNodeLabels(
      selectedNote: selectedNote,
      notes: notes,
      settings: settings,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Graph',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: CustomPaint(
                painter: _GraphPainter(
                  centerLabel: selectedNote.title,
                  nodeLabels: linkedTitles,
                ),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              linkedTitles.isEmpty
                  ? 'No linked notes yet.'
                  : 'Showing ${linkedTitles.length} connected notes within depth ${settings.graphDepth}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  List<String> _graphNodeLabels({
    required VaultNote selectedNote,
    required List<VaultNote> notes,
    required WorkspaceSettings settings,
  }) {
    final noteByTitle = <String, VaultNote>{
      for (final note in notes) note.title: note,
    };
    final visited = <String>{selectedNote.title};
    final labels = <String>{};
    var frontier = <String>{selectedNote.title};

    for (var depth = 0; depth < settings.graphDepth; depth++) {
      if (frontier.isEmpty) {
        break;
      }

      final nextFrontier = <String>{};
      for (final title in frontier) {
        final note = noteByTitle[title];
        if (note == null) {
          continue;
        }

        final neighbors = <String>{
          ...note.wikilinks.where(noteByTitle.containsKey),
          if (settings.backlinksEnabled)
            ...note.backlinks.where(noteByTitle.containsKey),
        };
        for (final neighbor in neighbors) {
          if (visited.add(neighbor)) {
            labels.add(neighbor);
            nextFrontier.add(neighbor);
          }
        }
      }
      frontier = nextFrontier;
    }

    final sorted = labels.toList()..sort();
    return sorted.take(14).toList(growable: false);
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
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        secondary: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: DropdownButton<String>(
          value: value,
          onChanged: (next) {
            if (next != null) {
              onChanged(next);
            }
          },
          items: [
            for (final option in options)
              DropdownMenuItem<String>(
                value: option,
                child: Text(option),
              ),
          ],
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  const _GraphPainter({
    required this.centerLabel,
    required this.nodeLabels,
  });

  final String centerLabel;
  final List<String> nodeLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final edgePaint = Paint()
      ..color = const Color(0xFF8C7E66)
      ..strokeWidth = 1.5;
    final centerPaint = Paint()..color = const Color(0xFF1F6B52);
    final nodePaint = Paint()..color = const Color(0xFFD4B483);
    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
    );

    final radius = size.shortestSide * 0.32;
    for (var index = 0; index < nodeLabels.length; index++) {
      final angle = (index / nodeLabels.length) * 6.28318530718;
      final nodeCenter = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawLine(center, nodeCenter, edgePaint);
      canvas.drawCircle(nodeCenter, 18, nodePaint);
      _paintLabel(canvas, textPainter, nodeLabels[index], nodeCenter);
    }

    canvas.drawCircle(center, 24, centerPaint);
    _paintLabel(canvas, textPainter, centerLabel, center,
        textColor: Colors.white);
  }

  void _paintLabel(
    Canvas canvas,
    TextPainter textPainter,
    String label,
    Offset center, {
    Color textColor = const Color(0xFF2D2418),
  }) {
    textPainter.text = TextSpan(
      text: label,
      style: TextStyle(
        color: textColor,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    );
    textPainter.layout(minWidth: 0, maxWidth: 72);
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) {
    return centerLabel != oldDelegate.centerLabel ||
        nodeLabels.join('|') != oldDelegate.nodeLabels.join('|');
  }
}
