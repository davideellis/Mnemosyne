import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnemosyne/src/features/notes/sync_models.dart';
import 'package:mnemosyne/src/features/notes/vault_models.dart';
import 'package:mnemosyne/src/features/settings/settings_panel.dart';
import 'package:mnemosyne/src/features/settings/workspace_settings.dart';

void main() {
  testWidgets('renders sync and note details with device actions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    RegisteredDevice? revokedDevice;
    WorkspaceSettings? updatedSettings;

    final note = VaultNote(
      objectId: 'note-1',
      title: 'Daily Note',
      relativePath: 'journal/daily-note.md',
      modifiedAt: DateTime.parse('2026-04-10T15:30:00Z'),
      markdown: '# Daily Note',
      tags: const ['daily', 'journal'],
      wikilinks: const ['Project Plan'],
      backlinks: const ['Inbox'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            note: note,
            noteIsTrashed: false,
            notes: [
              note,
              VaultNote(
                objectId: 'note-2',
                title: 'Project Plan',
                relativePath: 'projects/project-plan.md',
                modifiedAt: DateTime.parse('2026-04-10T10:00:00Z'),
                markdown: '# Plan',
                tags: const [],
                wikilinks: const ['Inbox'],
                backlinks: const ['Daily Note'],
              ),
              VaultNote(
                objectId: 'note-3',
                title: 'Inbox',
                relativePath: 'Inbox.md',
                modifiedAt: DateTime.parse('2026-04-09T09:00:00Z'),
                markdown: '# Inbox',
                tags: const [],
                wikilinks: const ['Daily Note'],
                backlinks: const ['Project Plan'],
              ),
            ],
            trashedNotes: const [],
            noteCount: 3,
            settings: const WorkspaceSettings(),
            syncStatus: 'Up to date',
            pendingSyncChanges: 2,
            lastSyncAttempt: '4/10/2026 10:30 AM',
            lastSyncSuccess: '4/10/2026 10:31 AM',
            lastSyncError: null,
            nextAutoSyncAttempt: '4/10/2026 10:36 AM',
            sessionExpiresAt: DateTime.parse('2026-04-11T15:30:00Z'),
            devices: const [
              RegisteredDevice(
                deviceId: 'device-1',
                deviceName: 'Workstation',
                platform: 'windows',
              ),
              RegisteredDevice(
                deviceId: 'device-2',
                deviceName: 'Phone',
                platform: 'android',
                lastSeenAt: null,
              ),
            ],
            currentDeviceName: 'Workstation',
            currentPlatform: 'windows',
            onSettingsChanged: (settings) => updatedSettings = settings,
            onRevokeDevice: (device) => revokedDevice = device,
            accountSection: const Card(
              child: ListTile(
                title: Text('Sync Account'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('Up to date'), findsOneWidget);
    expect(find.text('2 change(s) waiting to sync'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.link_off_outlined));
    await tester.pump();
    expect(revokedDevice?.deviceId, 'device-2');

    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(updatedSettings?.autoSyncEnabled, isFalse);

    await tester.scrollUntilVisible(
      find.text('Palette'),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.byType(DropdownButton<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ocean').last);
    await tester.pumpAndSettle();
    expect(updatedSettings?.colorPalette, 'ocean');

    await tester.scrollUntilVisible(
      find.text('Sync & Account'),
      300,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Sync & Account'), findsOneWidget);
    expect(find.text('Sync Account'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('journal/daily-note.md'),
      300,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Selected Note'), findsOneWidget);
    expect(find.text('journal/daily-note.md'), findsOneWidget);
  });
}
