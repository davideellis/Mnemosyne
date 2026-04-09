import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mnemosyne/src/features/notes/sync_api_client.dart';
import 'package:mnemosyne/src/features/notes/sync_crypto_service.dart';
import 'package:mnemosyne/src/features/notes/sync_models.dart';

void main() {
  test('bootstrapAccount returns a sync session', () async {
    final client = SyncApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/account/bootstrap');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['recoveryKeyHint'], 'local-safe');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'accountId': 'acct_local',
            'sessionToken': 'session_bootstrap',
          }),
          201,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final session = await client.bootstrapAccount(
      baseUri: Uri.parse('http://127.0.0.1:8080'),
      email: 'demo@mnemosyne.local',
      password: 'password',
      recoveryKey: 'AAA-BBB-CCC-DDD',
      recoveryKeyHint: 'local-safe',
      deviceName: 'Windows Desktop',
      platform: 'windows',
    );

    expect(session.accountId, 'acct_local');
    expect(session.sessionToken, 'session_bootstrap');
    expect(session.email, 'demo@mnemosyne.local');
    expect(session.masterKeyMaterial, isNotEmpty);
    expect(session.encryptedMasterKeyForPassword, isNotEmpty);
  });

  test('login unwraps a persisted master key from the server response', () async {
    final cryptoService = SyncCryptoService();
    final bootstrapMaterial = await cryptoService.createBootstrapMaterial(
      email: 'demo@mnemosyne.local',
      password: 'password',
      recoveryKey: 'AAAA-BBBB-CCCC-DDDD',
    );

    final client = SyncApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/auth/login');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'accountId': 'acct_local',
            'sessionToken': 'session_login',
            'encryptedMasterKeyForPassword':
                bootstrapMaterial.encryptedMasterKeyForPassword,
            'encryptedMasterKeyForRecovery':
                bootstrapMaterial.encryptedMasterKeyForRecovery,
            'recoveryKeyHint': 'saved-locally',
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final session = await client.login(
      baseUri: Uri.parse('http://127.0.0.1:8080'),
      email: 'demo@mnemosyne.local',
      password: 'password',
    );

    expect(session.sessionToken, 'session_login');
    expect(session.masterKeyMaterial, bootstrapMaterial.masterKeyMaterial);
  });

  test('recover unwraps a persisted master key from the recovery response', () async {
    final cryptoService = SyncCryptoService();
    final bootstrapMaterial = await cryptoService.createBootstrapMaterial(
      email: 'demo@mnemosyne.local',
      password: 'password',
      recoveryKey: 'AAAA-BBBB-CCCC-DDDD',
    );

    final client = SyncApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/auth/recover');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'accountId': 'acct_local',
            'sessionToken': 'session_recovery',
            'encryptedMasterKeyForPassword':
                bootstrapMaterial.encryptedMasterKeyForPassword,
            'encryptedMasterKeyForRecovery':
                bootstrapMaterial.encryptedMasterKeyForRecovery,
            'recoveryKeyHint': 'saved-locally',
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
      cryptoService: cryptoService,
    );

    final session = await client.recover(
      baseUri: Uri.parse('http://127.0.0.1:8080'),
      email: 'demo@mnemosyne.local',
      recoveryKey: 'AAAA-BBBB-CCCC-DDDD',
    );

    expect(session.sessionToken, 'session_recovery');
    expect(session.masterKeyMaterial, bootstrapMaterial.masterKeyMaterial);
  });

  test('syncVault pushes notes then pulls decrypted updates', () async {
    final cryptoService = SyncCryptoService();
    final bootstrapMaterial = await cryptoService.createBootstrapMaterial(
      email: 'demo@mnemosyne.local',
      password: 'password',
      recoveryKey: 'AAAA-BBBB-CCCC-DDDD',
    );
    final encryptedRemoteNote = await cryptoService.encryptNote(
      masterKeyMaterial: bootstrapMaterial.masterKeyMaterial,
      metadata: <String, dynamic>{
        'title': 'Remote',
        'relativePath': 'Journal/remote.md',
        'tags': <String>['remote'],
        'wikilinks': <String>['Welcome'],
      },
      markdown: '# Remote',
    );

    var requestCount = 0;
    final client = SyncApiClient(
      httpClient: MockClient((request) async {
        requestCount += 1;
        if (request.url.path == '/v1/sync/push') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'cursor': 'cursor-1',
              'changes': <dynamic>[],
            }),
            202,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }

        return http.Response(
          jsonEncode(<String, dynamic>{
            'cursor': 'cursor-2',
            'changes': <dynamic>[
              <String, dynamic>{
                'changeId': 'change-2',
                'objectId': 'note-2',
                'operation': 'upsert',
                'encryptedMetadata': encryptedRemoteNote.encryptedMetadata,
                'encryptedPayload': encryptedRemoteNote.encryptedPayload,
              },
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
      cryptoService: cryptoService,
    );

    final result = await client.syncVault(
      baseUri: Uri.parse('http://127.0.0.1:8080'),
      session: SyncSession(
        accountId: 'acct_local',
        sessionToken: 'session_bootstrap',
        email: 'demo@mnemosyne.local',
        encryptedMasterKeyForPassword:
            bootstrapMaterial.encryptedMasterKeyForPassword,
        encryptedMasterKeyForRecovery:
            bootstrapMaterial.encryptedMasterKeyForRecovery,
        masterKeyMaterial: bootstrapMaterial.masterKeyMaterial,
        recoveryKeyHint: 'saved-locally',
      ),
      changes: const <SyncPushChange>[
        SyncPushChange(
          objectId: 'note-1',
          operation: 'upsert',
          title: 'Welcome',
          relativePath: 'Journal/welcome.md',
          markdown: '# Welcome',
          tags: <String>['journal'],
          wikilinks: <String>['Roadmap'],
        ),
      ],
      cursor: '',
      deviceName: 'Windows Desktop',
      platform: 'windows',
    );

    expect(requestCount, 2);
    expect(result.cursor, 'cursor-2');
    expect(result.pushedCount, 1);
    expect(result.pulledCount, 1);
    expect(result.pulledChanges, hasLength(1));
    expect(result.pulledChanges.first.relativePath, 'Journal/remote.md');
    expect(result.pulledChanges.first.markdown, '# Remote');
  });
}
