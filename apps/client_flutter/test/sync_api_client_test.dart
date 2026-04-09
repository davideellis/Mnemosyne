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
    expect(session.wrappedMasterKeyForApproval, isEmpty);
  });

  test('login unwraps a persisted master key from the server response',
      () async {
    final cryptoService = SyncCryptoService();
    final bootstrapMaterial = await cryptoService.createBootstrapMaterial(
      email: 'demo@mnemosyne.local',
      password: 'password',
      recoveryKey: 'AAAA-BBBB-CCCC-DDDD',
    );

    final client = SyncApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/auth/login');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['device'], isA<Map<String, dynamic>>());
        expect(
          (payload['device'] as Map<String, dynamic>)['deviceName'],
          'Windows Desktop',
        );
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
      deviceName: 'Windows Desktop',
      platform: 'windows',
    );

    expect(session.sessionToken, 'session_login');
    expect(session.masterKeyMaterial, bootstrapMaterial.masterKeyMaterial);
  });

  test('logout posts the current session token', () async {
    final client = SyncApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/auth/logout');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['sessionToken'], 'session_login');
        return http.Response(
          jsonEncode(<String, dynamic>{'status': 'ok'}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    await client.logout(
      baseUri: Uri.parse('http://127.0.0.1:8080'),
      session: const SyncSession(
        accountId: 'acct_local',
        sessionToken: 'session_login',
        email: 'demo@mnemosyne.local',
        encryptedMasterKeyForPassword: '',
        encryptedMasterKeyForRecovery: '',
        wrappedMasterKeyForApproval: '',
        masterKeyMaterial: '',
        recoveryKeyHint: '',
      ),
    );
  });

  test('recover unwraps a persisted master key from the recovery response',
      () async {
    final cryptoService = SyncCryptoService();
    final bootstrapMaterial = await cryptoService.createBootstrapMaterial(
      email: 'demo@mnemosyne.local',
      password: 'password',
      recoveryKey: 'AAAA-BBBB-CCCC-DDDD',
    );

    final client = SyncApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/auth/recover');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['device'], isA<Map<String, dynamic>>());
        expect(
          (payload['device'] as Map<String, dynamic>)['platform'],
          'windows',
        );
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
      deviceName: 'Windows Desktop',
      platform: 'windows',
    );

    expect(session.sessionToken, 'session_recovery');
    expect(session.masterKeyMaterial, bootstrapMaterial.masterKeyMaterial);
  });

  test('device approval start and consume transfer a wrapped master key',
      () async {
    final cryptoService = SyncCryptoService();
    final bootstrapMaterial = await cryptoService.createBootstrapMaterial(
      email: 'demo@mnemosyne.local',
      password: 'password',
      recoveryKey: 'AAAA-BBBB-CCCC-DDDD',
    );
    late Map<String, dynamic> startPayload;

    final client = SyncApiClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/v1/devices/approval/start') {
          startPayload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'expiresAt': '2026-04-09T19:30:00Z',
            }),
            201,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }

        return http.Response(
          jsonEncode(<String, dynamic>{
            'accountId': 'acct_local',
            'sessionToken': 'session_approval',
            'wrappedMasterKeyForApproval': startPayload['wrappedKeyBlob'],
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

    final signedInSession = SyncSession(
      accountId: 'acct_local',
      sessionToken: 'session_bootstrap',
      email: 'demo@mnemosyne.local',
      encryptedMasterKeyForPassword:
          bootstrapMaterial.encryptedMasterKeyForPassword,
      encryptedMasterKeyForRecovery:
          bootstrapMaterial.encryptedMasterKeyForRecovery,
      wrappedMasterKeyForApproval: '',
      masterKeyMaterial: bootstrapMaterial.masterKeyMaterial,
      recoveryKeyHint: 'saved-locally',
    );

    final expiresAt = await client.startDeviceApproval(
      baseUri: Uri.parse('http://127.0.0.1:8080'),
      session: signedInSession,
      approvalCode: 'ABCD-EFGH-IJKL',
    );
    expect(expiresAt, '2026-04-09T19:30:00Z');

    final approvedSession = await client.consumeDeviceApproval(
      baseUri: Uri.parse('http://127.0.0.1:8080'),
      email: 'demo@mnemosyne.local',
      approvalCode: 'ABCD-EFGH-IJKL',
      deviceName: 'Mac Desktop',
      platform: 'macos',
    );

    expect(approvedSession.sessionToken, 'session_approval');
    expect(
      approvedSession.masterKeyMaterial,
      bootstrapMaterial.masterKeyMaterial,
    );
    expect(approvedSession.wrappedMasterKeyForApproval, isNotEmpty);
  });

  test('listDevices returns registered devices for the session', () async {
    final client = SyncApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/devices/list');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'devices': <dynamic>[
              <String, dynamic>{
                'deviceId': 'device-1',
                'deviceName': 'Windows Desktop',
                'platform': 'windows',
                'lastSeenAt': '2026-04-09T19:30:00Z',
              },
              <String, dynamic>{
                'deviceId': 'device-2',
                'deviceName': 'Mac Desktop',
                'platform': 'macos',
              },
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final devices = await client.listDevices(
      baseUri: Uri.parse('http://127.0.0.1:8080'),
      session: const SyncSession(
        accountId: 'acct_local',
        sessionToken: 'session_bootstrap',
        email: 'demo@mnemosyne.local',
        encryptedMasterKeyForPassword: '',
        encryptedMasterKeyForRecovery: '',
        wrappedMasterKeyForApproval: '',
        masterKeyMaterial: '',
        recoveryKeyHint: '',
      ),
    );

    expect(devices, hasLength(2));
    expect(devices.first.deviceName, 'Windows Desktop');
    expect(devices.first.lastSeenAt, DateTime.parse('2026-04-09T19:30:00Z'));
    expect(devices.last.platform, 'macos');
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
                'kind': 'note',
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
        wrappedMasterKeyForApproval: '',
        masterKeyMaterial: bootstrapMaterial.masterKeyMaterial,
        recoveryKeyHint: 'saved-locally',
      ),
      changes: const <SyncPushChange>[
        SyncPushChange(
          objectId: 'note-1',
          kind: 'note',
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

  test('syncVault round-trips workspace settings changes', () async {
    final cryptoService = SyncCryptoService();
    final bootstrapMaterial = await cryptoService.createBootstrapMaterial(
      email: 'demo@mnemosyne.local',
      password: 'password',
      recoveryKey: 'AAAA-BBBB-CCCC-DDDD',
    );
    final encryptedRemoteSettings = await cryptoService.encryptNote(
      masterKeyMaterial: bootstrapMaterial.masterKeyMaterial,
      metadata: <String, dynamic>{
        'settings': <String, dynamic>{
          'themeMode': 'dark',
          'autoSyncEnabled': false,
          'backlinksEnabled': false,
          'graphDepth': 3,
        },
      },
      markdown: '',
    );

    late Map<String, dynamic> pushedChange;
    final client = SyncApiClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/v1/sync/push') {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          pushedChange = (payload['changes'] as List<dynamic>).single
              as Map<String, dynamic>;
          return http.Response(
            jsonEncode(<String, dynamic>{'cursor': 'cursor-1'}),
            202,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }

        return http.Response(
          jsonEncode(<String, dynamic>{
            'cursor': 'cursor-2',
            'changes': <dynamic>[
              <String, dynamic>{
                'changeId': 'settings-2',
                'objectId': 'workspace-settings',
                'kind': 'settings',
                'operation': 'upsert',
                'encryptedMetadata': encryptedRemoteSettings.encryptedMetadata,
                'encryptedPayload': encryptedRemoteSettings.encryptedPayload,
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
        wrappedMasterKeyForApproval: '',
        masterKeyMaterial: bootstrapMaterial.masterKeyMaterial,
        recoveryKeyHint: 'saved-locally',
      ),
      changes: const <SyncPushChange>[
        SyncPushChange(
          objectId: 'workspace-settings',
          kind: 'settings',
          operation: 'upsert',
          settings: <String, dynamic>{
            'themeMode': 'dark',
            'autoSyncEnabled': false,
            'backlinksEnabled': false,
            'graphDepth': 3,
          },
        ),
      ],
      cursor: '',
      deviceName: 'Windows Desktop',
      platform: 'windows',
    );

    expect(pushedChange['kind'], 'settings');
    expect(result.pulledChanges.single.kind, 'settings');
    expect(result.pulledChanges.single.settings['themeMode'], 'dark');
    expect(result.pulledChanges.single.settings['autoSyncEnabled'], isFalse);
  });
}
