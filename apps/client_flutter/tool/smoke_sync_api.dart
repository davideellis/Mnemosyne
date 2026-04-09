import 'dart:io';

import 'package:mnemosyne/src/features/notes/sync_api_client.dart';
import 'package:mnemosyne/src/features/notes/sync_models.dart';

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  final baseUrl = options['base-url'];
  final email = options['email'];
  final password = options['password'];
  final recoveryKey = options['recovery-key'] ?? 'TEST-KEY1-TEST-KEY2';
  final bootstrap = options.containsKey('bootstrap');
  final recover = options.containsKey('recover');
  final settingsSync = options.containsKey('settings-sync');

  if (baseUrl == null || email == null || password == null) {
    stderr.writeln(
      'Usage: flutter pub run tool/smoke_sync_api.dart '
      '--base-url <url> --email <email> --password <password> '
      '[--recovery-key <key>] [--bootstrap]',
    );
    exitCode = 64;
    return;
  }

  final client = SyncApiClient();
  final baseUri = Uri.parse(baseUrl);

  final session = bootstrap
      ? await client.bootstrapAccount(
          baseUri: baseUri,
          email: email,
          password: password,
          recoveryKey: recoveryKey,
          recoveryKeyHint: 'cli-bootstrap',
          deviceName: 'Smoke Runner',
          platform: Platform.operatingSystem,
        )
      : recover
          ? await client.recover(
              baseUri: baseUri,
              email: email,
              recoveryKey: recoveryKey,
            )
          : await client.login(
              baseUri: baseUri,
              email: email,
              password: password,
            );

  final objectId = 'smoke-${DateTime.now().toUtc().millisecondsSinceEpoch}';
  final relativePath = 'Smoke/$objectId.md';
  final markdown = '# Smoke Test\n\nSynced at ${DateTime.now().toUtc().toIso8601String()}\n';
  final themeMode = options['theme-mode'] ?? 'dark';
  final graphDepth = int.tryParse(options['graph-depth'] ?? '') ?? 3;
  final settingsPayload = <String, dynamic>{
    'themeMode': themeMode,
    'autoSyncEnabled': false,
    'backlinksEnabled': false,
    'graphDepth': graphDepth,
  };

  final pushResult = await client.syncVault(
    baseUri: baseUri,
    session: session,
    changes: settingsSync
        ? <SyncPushChange>[
            SyncPushChange(
              objectId: 'workspace-settings',
              kind: 'settings',
              operation: 'upsert',
              settings: settingsPayload,
            ),
          ]
        : <SyncPushChange>[
            SyncPushChange(
              objectId: objectId,
              kind: 'note',
              operation: 'upsert',
              relativePath: relativePath,
              title: 'Smoke Test',
              markdown: markdown,
              tags: const <String>['smoke'],
              wikilinks: const <String>[],
            ),
          ],
    cursor: '',
    deviceName: 'Smoke Runner',
    platform: Platform.operatingSystem,
  );

  final secondSession = await client.login(
    baseUri: baseUri,
    email: email,
    password: password,
  );
  final pullResult = await client.pullVault(
    baseUri: baseUri,
    session: secondSession,
    cursor: '',
  );

  if (settingsSync) {
    final matchingChanges = pullResult.pulledChanges
        .where((change) => change.objectId == 'workspace-settings')
        .toList(growable: false);
    if (matchingChanges.isEmpty ||
        matchingChanges.last.settings['themeMode'] != themeMode ||
        matchingChanges.last.settings['graphDepth'] != graphDepth ||
        matchingChanges.last.settings['autoSyncEnabled'] != false) {
      stderr.writeln(
        'Settings smoke test failed. Expected a round-tripped workspace settings change.',
      );
      stderr.writeln('Push cursor: ${pushResult.cursor}');
      stderr.writeln('Pull cursor: ${pullResult.cursor}');
      stderr.writeln('Matches: ${matchingChanges.length}');
      exitCode = 1;
      return;
    }
  } else {
    final matchingChanges = pullResult.pulledChanges
        .where((change) => change.objectId == objectId)
        .toList(growable: false);
    if (matchingChanges.length != 1 ||
        matchingChanges.first.markdown != markdown) {
      stderr.writeln(
        'Smoke test failed. Expected one round-tripped note for $objectId.',
      );
      stderr.writeln('Push cursor: ${pushResult.cursor}');
      stderr.writeln('Pull cursor: ${pullResult.cursor}');
      stderr.writeln('Matches: ${matchingChanges.length}');
      exitCode = 1;
      return;
    }
  }

  stdout.writeln('Smoke test passed.');
  stdout.writeln('Object: $objectId');
  stdout.writeln('Push cursor: ${pushResult.cursor}');
  stdout.writeln('Pull cursor: ${pullResult.cursor}');
}

Map<String, String> _parseArgs(List<String> args) {
  final options = <String, String>{};
  for (var index = 0; index < args.length; index++) {
    final arg = args[index];
    if (!arg.startsWith('--')) {
      continue;
    }

    final key = arg.substring(2);
    final next = index + 1 < args.length ? args[index + 1] : null;
    if (next == null || next.startsWith('--')) {
      options[key] = 'true';
      continue;
    }

    options[key] = next;
    index += 1;
  }
  return options;
}
