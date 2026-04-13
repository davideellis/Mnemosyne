import 'dart:io';
import 'dart:convert';

import 'package:mnemosyne/src/features/notes/sync_api_client.dart';
import 'package:mnemosyne/src/features/notes/sync_crypto_service.dart';
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
  final startApproval = options.containsKey('start-approval');
  final consumeApproval = options.containsKey('consume-approval');
  final listDevices = options.containsKey('list-devices');
  final revokeDevice = options.containsKey('revoke-device');
  final trashRestore = options.containsKey('trash-restore');
  final approvalRoundtrip = options.containsKey('approval-roundtrip');
  final staleWrite = options.containsKey('stale-write');
  final full = options.containsKey('full');
  final logout = options.containsKey('logout');
  final approvalCode = options['approval-code'] ?? 'ABCD-EFGH-IJKL';
  final deviceName = options['device-name'] ?? 'Smoke Runner';
  final devicePlatform = options['device-platform'] ?? Platform.operatingSystem;
  final targetDeviceId = options['target-device-id'];

  if (baseUrl == null || email == null || password == null) {
    stderr.writeln(
      'Usage: flutter pub run tool/smoke_sync_api.dart '
      '--base-url <url> --email <email> --password <password> '
      '[--recovery-key <key>] [--bootstrap] [--device-name <name>] '
      '[--device-platform <platform>]',
    );
    exitCode = 64;
    return;
  }

  final client = SyncApiClient();
  final baseUri = Uri.parse(baseUrl);

  if (startApproval) {
    final session = await client.login(
      baseUri: baseUri,
      email: email,
      password: password,
      deviceName: deviceName,
      platform: devicePlatform,
    );
    final expiresAt = await client.startDeviceApproval(
      baseUri: baseUri,
      session: session,
      approvalCode: approvalCode,
    );
    stdout.writeln('Approval started.');
    stdout.writeln('Code: $approvalCode');
    stdout.writeln('Expires at: $expiresAt');
    return;
  }

  if (listDevices) {
    final session = await client.login(
      baseUri: baseUri,
      email: email,
      password: password,
      deviceName: deviceName,
      platform: devicePlatform,
    );
    final devices = await client.listDevices(
      baseUri: baseUri,
      session: session,
    );
    stdout.writeln('Devices: ${devices.length}');
    for (final device in devices) {
      final lastSeenAt =
          device.lastSeenAt?.toUtc().toIso8601String() ?? 'unknown';
      stdout.writeln(
        '- ${device.deviceName} (${device.platform}) lastSeenAt=$lastSeenAt',
      );
    }
    return;
  }

  if (revokeDevice) {
    if (targetDeviceId == null || targetDeviceId.isEmpty) {
      stderr.writeln('--target-device-id is required with --revoke-device');
      exitCode = 64;
      return;
    }
    final session = await client.login(
      baseUri: baseUri,
      email: email,
      password: password,
      deviceName: deviceName,
      platform: devicePlatform,
    );
    await client.revokeDevice(
      baseUri: baseUri,
      session: session,
      deviceId: targetDeviceId,
    );
    stdout.writeln('Revoked device: $targetDeviceId');
    return;
  }

  if (logout) {
    final session = await client.login(
      baseUri: baseUri,
      email: email,
      password: password,
      deviceName: deviceName,
      platform: devicePlatform,
    );
    await client.logout(
      baseUri: baseUri,
      session: session,
    );
    stdout.writeln('Logout completed.');
    return;
  }

  final session = bootstrap
      ? await client.bootstrapAccount(
          baseUri: baseUri,
          email: email,
          password: password,
          recoveryKey: recoveryKey,
          recoveryKeyHint: 'cli-bootstrap',
          deviceName: deviceName,
          platform: devicePlatform,
        )
      : recover
          ? await client.recover(
              baseUri: baseUri,
              email: email,
              recoveryKey: recoveryKey,
              deviceName: deviceName,
              platform: devicePlatform,
            )
          : consumeApproval
              ? await client.consumeDeviceApproval(
                  baseUri: baseUri,
                  email: email,
                  approvalCode: approvalCode,
                  deviceName: deviceName,
                  platform: devicePlatform,
                )
              : await client.login(
                  baseUri: baseUri,
                  email: email,
                  password: password,
                  deviceName: deviceName,
                  platform: devicePlatform,
                );

  if (session.sessionExpiresAt != null) {
    stdout.writeln(
      'Session expires at: ${session.sessionExpiresAt!.toUtc().toIso8601String()}',
    );
  }

  if (full) {
    await _runFullSmoke(
      client: client,
      baseUri: baseUri,
      session: session,
      email: email,
      password: password,
      approvalCode: approvalCode,
      deviceName: deviceName,
      devicePlatform: devicePlatform,
    );
    return;
  }

  if (approvalRoundtrip) {
    await _runApprovalRoundtrip(
      client: client,
      baseUri: baseUri,
      session: session,
      email: email,
      password: password,
      approvalCode: approvalCode,
      deviceName: deviceName,
      devicePlatform: devicePlatform,
    );
    return;
  }

  if (staleWrite) {
    await _runStaleWriteSmoke(
      client: client,
      baseUri: baseUri,
      session: session,
      deviceName: deviceName,
      devicePlatform: devicePlatform,
    );
    return;
  }

  if (trashRestore) {
    await _runTrashRestoreSmoke(
      client: client,
      baseUri: baseUri,
      session: session,
      deviceName: deviceName,
      devicePlatform: devicePlatform,
    );
    return;
  }

  final objectId = 'smoke-${DateTime.now().toUtc().millisecondsSinceEpoch}';
  final relativePath = 'Smoke/$objectId.md';
  final markdown =
      '# Smoke Test\n\nSynced at ${DateTime.now().toUtc().toIso8601String()}\n';
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
    deviceName: deviceName,
    platform: devicePlatform,
  );

  final secondSession = await client.login(
    baseUri: baseUri,
    email: email,
    password: password,
    deviceName: deviceName,
    platform: devicePlatform,
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

Future<void> _runFullSmoke({
  required SyncApiClient client,
  required Uri baseUri,
  required SyncSession session,
  required String email,
  required String password,
  required String approvalCode,
  required String deviceName,
  required String devicePlatform,
}) async {
  stdout.writeln('Running full smoke flow...');

  await _runNoteSmoke(
    client: client,
    baseUri: baseUri,
    session: session,
    deviceName: deviceName,
    devicePlatform: devicePlatform,
  );
  if (exitCode != 0) {
    return;
  }
  await _runSettingsSmoke(
    client: client,
    baseUri: baseUri,
    session: session,
    deviceName: deviceName,
    devicePlatform: devicePlatform,
  );
  if (exitCode != 0) {
    return;
  }
  await _runTrashRestoreSmoke(
    client: client,
    baseUri: baseUri,
    session: session,
    deviceName: deviceName,
    devicePlatform: devicePlatform,
  );
  if (exitCode != 0) {
    return;
  }
  await _runApprovalRoundtrip(
    client: client,
    baseUri: baseUri,
    session: session,
    email: email,
    password: password,
    approvalCode: approvalCode,
    deviceName: deviceName,
    devicePlatform: devicePlatform,
  );
  if (exitCode != 0) {
    return;
  }
  await _runStaleWriteSmoke(
    client: client,
    baseUri: baseUri,
    session: session,
    deviceName: deviceName,
    devicePlatform: devicePlatform,
  );
  if (exitCode != 0) {
    return;
  }

  stdout.writeln('Full smoke flow passed.');
}

Future<void> _runNoteSmoke({
  required SyncApiClient client,
  required Uri baseUri,
  required SyncSession session,
  required String deviceName,
  required String devicePlatform,
}) async {
  final objectId = 'smoke-${DateTime.now().toUtc().millisecondsSinceEpoch}';
  final relativePath = 'Smoke/$objectId.md';
  final markdown =
      '# Smoke Test\n\nSynced at ${DateTime.now().toUtc().toIso8601String()}\n';

  final pushResult = await client.syncVault(
    baseUri: baseUri,
    session: session,
    changes: <SyncPushChange>[
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
    deviceName: deviceName,
    platform: devicePlatform,
  );

  final pullResult = await client.pullVault(
    baseUri: baseUri,
    session: session,
    cursor: '',
  );

  final matchingChanges = pullResult.pulledChanges
      .where((change) => change.objectId == objectId)
      .toList(growable: false);
  if (matchingChanges.length != 1 ||
      matchingChanges.first.markdown != markdown) {
    stderr.writeln(
      'Note smoke test failed. Expected one round-tripped note for $objectId.',
    );
    stderr.writeln('Push cursor: ${pushResult.cursor}');
    stderr.writeln('Pull cursor: ${pullResult.cursor}');
    stderr.writeln('Matches: ${matchingChanges.length}');
    exitCode = 1;
    return;
  }

  stdout.writeln('Note sync passed for $objectId.');
}

Future<void> _runSettingsSmoke({
  required SyncApiClient client,
  required Uri baseUri,
  required SyncSession session,
  required String deviceName,
  required String devicePlatform,
}) async {
  final themeMode = 'dark';
  final graphDepth = 3;
  final settingsPayload = <String, dynamic>{
    'themeMode': themeMode,
    'autoSyncEnabled': false,
    'backlinksEnabled': false,
    'graphDepth': graphDepth,
  };

  final pushResult = await client.syncVault(
    baseUri: baseUri,
    session: session,
    changes: <SyncPushChange>[
      SyncPushChange(
        objectId: 'workspace-settings',
        kind: 'settings',
        operation: 'upsert',
        settings: settingsPayload,
      ),
    ],
    cursor: '',
    deviceName: deviceName,
    platform: devicePlatform,
  );
  final pullResult = await client.pullVault(
    baseUri: baseUri,
    session: session,
    cursor: '',
  );

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

  stdout.writeln('Settings sync passed.');
}

Future<void> _runTrashRestoreSmoke({
  required SyncApiClient client,
  required Uri baseUri,
  required SyncSession session,
  required String deviceName,
  required String devicePlatform,
}) async {
  final objectId = 'trash-${DateTime.now().toUtc().millisecondsSinceEpoch}';
  final relativePath = 'Smoke/$objectId.md';

  await client.syncVault(
    baseUri: baseUri,
    session: session,
    changes: <SyncPushChange>[
      SyncPushChange(
        objectId: objectId,
        kind: 'note',
        operation: 'upsert',
        relativePath: relativePath,
        title: 'Trash Restore',
        markdown: '# Trash Restore',
      ),
    ],
    cursor: '',
    deviceName: deviceName,
    platform: devicePlatform,
  );

  await client.syncVault(
    baseUri: baseUri,
    session: session,
    changes: <SyncPushChange>[
      SyncPushChange(
        objectId: objectId,
        kind: 'note',
        operation: 'trash',
        relativePath: relativePath,
        title: 'Trash Restore',
        markdown: '# Trash Restore',
      ),
    ],
    cursor: '',
    deviceName: deviceName,
    platform: devicePlatform,
  );

  final restored = await client.restoreTrash(
    baseUri: baseUri,
    session: session,
    objectId: objectId,
  );
  if (restored.operation != 'restore' || restored.objectId != objectId) {
    stderr.writeln('Trash restore smoke test failed for $objectId.');
    exitCode = 1;
    return;
  }

  stdout.writeln('Trash restore passed for $objectId.');
}

Future<void> _runApprovalRoundtrip({
  required SyncApiClient client,
  required Uri baseUri,
  required SyncSession session,
  required String email,
  required String password,
  required String approvalCode,
  required String deviceName,
  required String devicePlatform,
}) async {
  final approvalDeviceName = '$deviceName Approval';
  final approvalPlatform = '${devicePlatform}_approval';

  final expiresAt = await client.startDeviceApproval(
    baseUri: baseUri,
    session: session,
    approvalCode: approvalCode,
  );
  if (expiresAt.isEmpty) {
    stderr.writeln('Approval smoke test failed: missing expiry.');
    exitCode = 1;
    return;
  }

  final approvedSession = await client.consumeDeviceApproval(
    baseUri: baseUri,
    email: email,
    approvalCode: approvalCode,
    deviceName: approvalDeviceName,
    platform: approvalPlatform,
  );
  if (approvedSession.masterKeyMaterial.isEmpty) {
    stderr.writeln('Approval smoke test failed: approved device has no key.');
    exitCode = 1;
    return;
  }

  final devices = await client.listDevices(baseUri: baseUri, session: session);
  final approvedDevice = devices.where((device) {
    return device.deviceName == approvalDeviceName &&
        device.platform == approvalPlatform;
  }).toList(growable: false);
  if (approvedDevice.isEmpty) {
    stderr.writeln('Approval smoke test failed: approved device not listed.');
    exitCode = 1;
    return;
  }

  await client.revokeDevice(
    baseUri: baseUri,
    session: session,
    deviceId: approvedDevice.single.deviceId,
  );

  try {
    await client.pullVault(
      baseUri: baseUri,
      session: approvedSession,
      cursor: '',
    );
    stderr.writeln('Approval smoke test failed: revoked session still worked.');
    exitCode = 1;
    return;
  } on SyncApiException catch (error) {
    if (error.statusCode != 401) {
      stderr.writeln(
        'Approval smoke test failed: expected 401 after revoke, got ${error.statusCode}.',
      );
      exitCode = 1;
      return;
    }
  }

  final refreshed = await client.login(
    baseUri: baseUri,
    email: email,
    password: password,
    deviceName: deviceName,
    platform: devicePlatform,
  );
  final refreshedDevices =
      await client.listDevices(baseUri: baseUri, session: refreshed);
  final stillPresent = refreshedDevices.any((device) {
    return device.deviceName == approvalDeviceName &&
        device.platform == approvalPlatform;
  });
  if (stillPresent) {
    stderr.writeln(
      'Approval smoke test failed: revoked device still listed after refresh.',
    );
    exitCode = 1;
    return;
  }

  stdout.writeln('Approval + revoke passed.');
}

Future<void> _runStaleWriteSmoke({
  required SyncApiClient client,
  required Uri baseUri,
  required SyncSession session,
  required String deviceName,
  required String devicePlatform,
}) async {
  final objectId = 'stale-${DateTime.now().toUtc().millisecondsSinceEpoch}';
  final relativePath = 'Smoke/$objectId.md';
  final latestMarkdown = '# Fresh\n\nThis is the latest write.\n';
  final staleMarkdown = '# Stale\n\nThis write should be ignored.\n';

  await client.syncVault(
    baseUri: baseUri,
    session: session,
    changes: <SyncPushChange>[
      SyncPushChange(
        objectId: objectId,
        kind: 'note',
        operation: 'upsert',
        relativePath: relativePath,
        title: 'Fresh',
        markdown: latestMarkdown,
        tags: const <String>['smoke'],
      ),
    ],
    cursor: '',
    deviceName: deviceName,
    platform: devicePlatform,
  );

  final staleTimestamp = DateTime.now()
      .toUtc()
      .subtract(const Duration(minutes: 5))
      .toIso8601String();
  await _pushRawChange(
    baseUri: baseUri,
    session: session,
    change: await _encodeRawChange(
      session: session,
      objectId: objectId,
      relativePath: relativePath,
      title: 'Stale',
      markdown: staleMarkdown,
      tags: const <String>['smoke', 'stale'],
      logicalTimestamp: staleTimestamp,
      originDeviceId: '${deviceName}_stale::$devicePlatform',
      changeId: '$objectId:$staleTimestamp:upsert',
    ),
  );

  final pullResult = await client.pullVault(
    baseUri: baseUri,
    session: session,
    cursor: '',
  );
  final matchingChanges = pullResult.pulledChanges
      .where((change) => change.objectId == objectId)
      .toList(growable: false);
  if (matchingChanges.isEmpty ||
      matchingChanges.last.markdown != latestMarkdown) {
    stderr.writeln(
      'Stale-write smoke test failed. Expected the freshest note body to survive.',
    );
    stderr.writeln('Matches: ${matchingChanges.length}');
    if (matchingChanges.isNotEmpty) {
      stderr.writeln('Latest markdown: ${matchingChanges.last.markdown}');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('Stale-write protection passed for $objectId.');
}

Future<Map<String, dynamic>> _encodeRawChange({
  required SyncSession session,
  required String objectId,
  required String relativePath,
  required String title,
  required String markdown,
  required List<String> tags,
  required String logicalTimestamp,
  required String originDeviceId,
  required String changeId,
}) async {
  final crypto = SyncCryptoService();
  final encryptedPayload = await crypto.encryptNote(
    masterKeyMaterial: session.masterKeyMaterial,
    metadata: <String, dynamic>{
      'title': title,
      'relativePath': relativePath,
      'tags': tags,
      'wikilinks': const <String>[],
    },
    markdown: markdown,
  );

  return <String, dynamic>{
    'changeId': changeId,
    'objectId': objectId,
    'kind': 'note',
    'operation': 'upsert',
    'logicalTimestamp': logicalTimestamp,
    'originDeviceId': originDeviceId,
    'encryptedMetadata': encryptedPayload.encryptedMetadata,
    'encryptedPayload': encryptedPayload.encryptedPayload,
  };
}

Future<void> _pushRawChange({
  required Uri baseUri,
  required SyncSession session,
  required Map<String, dynamic> change,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(baseUri.resolve('/v1/sync/push'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(<String, dynamic>{
      'sessionToken': session.sessionToken,
      'cursor': '',
      'changes': <Map<String, dynamic>>[change],
    }));

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      throw Exception(
          'Raw push failed (${response.statusCode}): $responseBody');
    }
  } finally {
    client.close(force: true);
  }
}
