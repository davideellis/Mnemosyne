import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mnemosyne/src/features/notes/sync_api_client.dart';
import 'package:mnemosyne/src/features/notes/sync_models.dart';
import 'package:mnemosyne/src/features/notes/vault_models.dart';

void main() {
  test('bootstrapAccount returns a sync session', () async {
    final client = SyncApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v1/account/bootstrap');
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
      deviceName: 'Windows Desktop',
      platform: 'windows',
    );

    expect(session.accountId, 'acct_local');
    expect(session.sessionToken, 'session_bootstrap');
    expect(session.email, 'demo@mnemosyne.local');
  });

  test('syncVault pushes notes then pulls updates', () async {
    var requestCount = 0;
    final client = SyncApiClient(
      httpClient: MockClient((request) async {
        requestCount += 1;
        if (request.url.path == '/v1/sync/push') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'cursor': 'cursor-1',
              'changes': <dynamic>[]
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
                'encryptedMetadata': base64Encode(
                  utf8.encode(
                    jsonEncode(<String, dynamic>{
                      'title': 'Remote',
                      'relativePath': 'Journal/remote.md',
                      'tags': <String>['remote'],
                      'wikilinks': <String>['Welcome'],
                    }),
                  ),
                ),
                'encryptedPayload': base64Encode(utf8.encode('# Remote')),
              },
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final result = await client.syncVault(
      baseUri: Uri.parse('http://127.0.0.1:8080'),
      session: const SyncSession(
        accountId: 'acct_local',
        sessionToken: 'session_bootstrap',
        email: 'demo@mnemosyne.local',
      ),
      notes: const <VaultNote>[
        VaultNote(
          objectId: 'note-1',
          title: 'Welcome',
          relativePath: 'Journal/welcome.md',
          markdown: '# Welcome',
          tags: <String>['journal'],
          wikilinks: <String>['Roadmap'],
          backlinks: <String>[],
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
