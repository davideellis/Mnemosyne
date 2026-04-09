import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../notes/vault_models.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    required this.note,
    required this.noteIsTrashed,
    required this.notes,
    required this.trashedNotes,
    required this.noteCount,
    super.key,
  });

  final VaultNote? note;
  final bool noteIsTrashed;
  final List<VaultNote> notes;
  final List<VaultNote> trashedNotes;
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
          _SettingTile(
            title: 'Trashed Notes',
            subtitle: '${trashedNotes.length} in synced trash',
            icon: Icons.restore_from_trash_outlined,
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
              subtitle: note!.backlinks.isEmpty
                  ? 'No backlinks yet'
                  : note!.backlinks.join(', '),
              icon: Icons.call_split_outlined,
            ),
            const SizedBox(height: 16),
            _GraphCard(
              selectedNote: note!,
              notes: notes,
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
  });

  final VaultNote selectedNote;
  final List<VaultNote> notes;

  @override
  Widget build(BuildContext context) {
    final noteTitles = notes.map((note) => note.title).toSet();
    final linkedTitles = <String>{
      ...selectedNote.wikilinks,
      ...selectedNote.backlinks,
    }.where(noteTitles.contains).toList()
      ..sort();

    return Card(
      color: Colors.white,
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
                  : 'Showing ${linkedTitles.length} connected notes from this device.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
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
