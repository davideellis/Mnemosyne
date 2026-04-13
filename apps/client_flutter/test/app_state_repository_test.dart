import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnemosyne/src/features/notes/app_state_repository.dart';
import 'package:mnemosyne/src/features/notes/sync_models.dart';
import 'package:mnemosyne/src/features/settings/workspace_settings.dart';

void main() {
  test('persisted app state serializes session and vault data', () {
    final state = PersistedAppState(
      apiBaseUrl: 'http://127.0.0.1:8080',
      email: 'demo@mnemosyne.local',
      knownNoteDigests: <String, String>{'Journal/welcome.md': 'digest-1'},
      knownSettingsDigest:
          '{"themeMode":"dark","colorPalette":"ocean","autoSyncEnabled":false,"backlinksEnabled":false,"graphDepth":3}',
      knownTrashDigests: <String, String>{'Journal/trashed.md': 'trash-digest'},
      lastNoteFolder: 'Journal',
      settings: WorkspaceSettings(
        themeMode: 'dark',
        colorPalette: 'ocean',
        autoSyncEnabled: false,
        backlinksEnabled: false,
        graphDepth: 3,
      ),
      showGraphPanel: true,
      showVaultPanel: false,
      showWorkspacePanel: false,
      syncCursor: 'cursor-1',
      vaultRootPath: '/tmp/MnemosyneDemoVault',
      session: SyncSession(
        accountId: 'acct_local',
        sessionToken: 'session_bootstrap',
        email: 'demo@mnemosyne.local',
        sessionExpiresAt: DateTime.utc(2026, 5, 10, 12),
        encryptedMasterKeyForPassword: 'enc-pw',
        encryptedMasterKeyForRecovery: 'enc-rec',
        wrappedMasterKeyForApproval: 'enc-approval',
        masterKeyMaterial: 'master-key',
        recoveryKeyHint: 'saved-locally',
      ),
    );

    final restored = PersistedAppState.fromJson(
      jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
    );

    expect(restored.apiBaseUrl, state.apiBaseUrl);
    expect(restored.email, state.email);
    expect(restored.knownNoteDigests['Journal/welcome.md'], 'digest-1');
    expect(restored.knownSettingsDigest, state.knownSettingsDigest);
    expect(restored.knownTrashDigests['Journal/trashed.md'], 'trash-digest');
    expect(restored.lastNoteFolder, 'Journal');
    expect(restored.settings.themeMode, 'dark');
    expect(restored.settings.colorPalette, 'ocean');
    expect(restored.settings.autoSyncEnabled, isFalse);
    expect(restored.settings.backlinksEnabled, isFalse);
    expect(restored.settings.graphDepth, 3);
    expect(restored.showGraphPanel, isTrue);
    expect(restored.showVaultPanel, isFalse);
    expect(restored.showWorkspacePanel, isFalse);
    expect(restored.syncCursor, state.syncCursor);
    expect(restored.vaultRootPath, state.vaultRootPath);
    expect(restored.session?.sessionToken, state.session?.sessionToken);
    expect(restored.session?.sessionExpiresAt, state.session?.sessionExpiresAt);
    expect(restored.session?.wrappedMasterKeyForApproval, 'enc-approval');
    expect(restored.session?.masterKeyMaterial, isEmpty);
  });

  test('repository load returns empty state when no file exists', () async {
    final tempHome = await Directory.systemTemp.createTemp('mnemosyne_home_');
    addTearDown(() => tempHome.delete(recursive: true));

    final repository = AppStateRepository(
      filePath: '${tempHome.path}${Platform.pathSeparator}app_state.json',
    );
    final state = await repository.load();
    expect(state.session, isNull);
  });
}
