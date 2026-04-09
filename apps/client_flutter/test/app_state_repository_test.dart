import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnemosyne/src/features/notes/app_state_repository.dart';
import 'package:mnemosyne/src/features/notes/sync_models.dart';

void main() {
  test('persisted app state serializes session and vault data', () {
    const state = PersistedAppState(
      apiBaseUrl: 'http://127.0.0.1:8080',
      email: 'demo@mnemosyne.local',
      knownNoteDigests: <String, String>{'Journal/welcome.md': 'digest-1'},
      knownTrashDigests: <String, String>{'Journal/trashed.md': 'trash-digest'},
      syncCursor: 'cursor-1',
      vaultRootPath: '/tmp/MnemosyneDemoVault',
      session: SyncSession(
        accountId: 'acct_local',
        sessionToken: 'session_bootstrap',
        email: 'demo@mnemosyne.local',
        encryptedMasterKeyForPassword: 'enc-pw',
        encryptedMasterKeyForRecovery: 'enc-rec',
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
    expect(restored.knownTrashDigests['Journal/trashed.md'], 'trash-digest');
    expect(restored.syncCursor, state.syncCursor);
    expect(restored.vaultRootPath, state.vaultRootPath);
    expect(restored.session?.sessionToken, state.session?.sessionToken);
    expect(restored.session?.masterKeyMaterial, state.session?.masterKeyMaterial);
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
