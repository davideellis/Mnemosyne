import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sync_crypto_service.dart';
import 'sync_models.dart';

class SyncApiClient {
  SyncApiClient({
    http.Client? httpClient,
    SyncCryptoService? cryptoService,
  })  : _httpClient = httpClient ?? http.Client(),
        _cryptoService = cryptoService ?? SyncCryptoService();

  final http.Client _httpClient;
  final SyncCryptoService _cryptoService;

  Future<SyncSession> bootstrapAccount({
    required Uri baseUri,
    required String email,
    required String password,
    required String recoveryKey,
    required String recoveryKeyHint,
    required String deviceName,
    required String platform,
  }) async {
    final bootstrapMaterial = await _cryptoService.createBootstrapMaterial(
      email: email,
      password: password,
      recoveryKey: recoveryKey,
    );
    final response = await _post(
      baseUri,
      '/v1/account/bootstrap',
      <String, dynamic>{
        'email': email,
        'passwordVerifier': bootstrapMaterial.passwordVerifier,
        'recoveryVerifier': bootstrapMaterial.recoveryVerifier,
        'encryptedMasterKeyForPassword':
            bootstrapMaterial.encryptedMasterKeyForPassword,
        'encryptedMasterKeyForRecovery':
            bootstrapMaterial.encryptedMasterKeyForRecovery,
        'recoveryKeyHint': recoveryKeyHint,
        'device': <String, dynamic>{
          'deviceId': _deviceId(deviceName, platform),
          'deviceName': deviceName,
          'platform': platform,
        },
      },
    );

    final body = _decodeJson(response);
    return SyncSession(
      accountId: body['accountId'] as String,
      sessionToken: body['sessionToken'] as String,
      email: email,
      encryptedMasterKeyForPassword:
          body['encryptedMasterKeyForPassword'] as String? ??
              bootstrapMaterial.encryptedMasterKeyForPassword,
      encryptedMasterKeyForRecovery:
          body['encryptedMasterKeyForRecovery'] as String? ??
              bootstrapMaterial.encryptedMasterKeyForRecovery,
      masterKeyMaterial: bootstrapMaterial.masterKeyMaterial,
      recoveryKeyHint: body['recoveryKeyHint'] as String? ?? recoveryKeyHint,
    );
  }

  Future<SyncSession> login({
    required Uri baseUri,
    required String email,
    required String password,
  }) async {
    final response = await _post(
      baseUri,
      '/v1/auth/login',
      <String, dynamic>{
        'email': email,
        'passwordVerifier': await _passwordVerifier(email, password),
      },
    );

    final body = _decodeJson(response);
    final encryptedMasterKeyForPassword =
        body['encryptedMasterKeyForPassword'] as String? ?? '';
    final masterKeyMaterial = encryptedMasterKeyForPassword.isEmpty
        ? ''
        : await _cryptoService.unwrapMasterKeyWithPassword(
            email: email,
            password: password,
            encryptedMasterKeyForPassword: encryptedMasterKeyForPassword,
          );
    return SyncSession(
      accountId: body['accountId'] as String,
      sessionToken: body['sessionToken'] as String,
      email: email,
      encryptedMasterKeyForPassword: encryptedMasterKeyForPassword,
      encryptedMasterKeyForRecovery:
          body['encryptedMasterKeyForRecovery'] as String? ?? '',
      masterKeyMaterial: masterKeyMaterial,
      recoveryKeyHint: body['recoveryKeyHint'] as String? ?? '',
    );
  }

  Future<SyncSession> recover({
    required Uri baseUri,
    required String email,
    required String recoveryKey,
  }) async {
    final response = await _post(
      baseUri,
      '/v1/auth/recover',
      <String, dynamic>{
        'email': email,
        'recoveryVerifier':
            await _cryptoService.recoveryVerifierForKey(recoveryKey),
      },
    );

    final body = _decodeJson(response);
    final encryptedMasterKeyForRecovery =
        body['encryptedMasterKeyForRecovery'] as String? ?? '';
    final masterKeyMaterial = encryptedMasterKeyForRecovery.isEmpty
        ? ''
        : await _cryptoService.unwrapMasterKeyWithRecovery(
            recoveryKey: recoveryKey,
            encryptedMasterKeyForRecovery: encryptedMasterKeyForRecovery,
          );

    return SyncSession(
      accountId: body['accountId'] as String,
      sessionToken: body['sessionToken'] as String,
      email: email,
      encryptedMasterKeyForPassword:
          body['encryptedMasterKeyForPassword'] as String? ?? '',
      encryptedMasterKeyForRecovery: encryptedMasterKeyForRecovery,
      masterKeyMaterial: masterKeyMaterial,
      recoveryKeyHint: body['recoveryKeyHint'] as String? ?? '',
    );
  }

  Future<SyncResult> syncVault({
    required Uri baseUri,
    required SyncSession session,
    required List<SyncPushChange> changes,
    required String cursor,
    required String deviceName,
    required String platform,
  }) async {
    if (session.masterKeyMaterial.isEmpty) {
      throw Exception(
        'This session does not have a local master key. Sign in again to continue syncing.',
      );
    }

    final encodedChanges = <Map<String, dynamic>>[];
    for (final change in changes) {
      encodedChanges.add(
        await _encodeNoteChange(change, session, deviceName, platform),
      );
    }

    final pushResponse = await _post(
      baseUri,
      '/v1/sync/push',
      <String, dynamic>{
        'sessionToken': session.sessionToken,
        'cursor': cursor,
        'changes': encodedChanges,
      },
    );

    final pushBody = _decodeJson(pushResponse);
    final nextCursor = (pushBody['cursor'] as String?) ?? cursor;

    final pullResult = await pullVault(
      baseUri: baseUri,
      session: session,
      cursor: nextCursor,
    );
    return SyncResult(
      cursor: pullResult.cursor,
      pushedCount: changes.length,
      pulledCount: pullResult.pulledCount,
      pulledChanges: pullResult.pulledChanges,
    );
  }

  Future<SyncResult> pullVault({
    required Uri baseUri,
    required SyncSession session,
    required String cursor,
  }) async {
    final pullResponse = await _post(
      baseUri,
      '/v1/sync/pull',
      <String, dynamic>{
        'sessionToken': session.sessionToken,
        'cursor': cursor,
      },
    );

    final pullBody = _decodeJson(pullResponse);
    final pulledChanges = <RemoteNoteChange>[];
    for (final change in (pullBody['changes'] as List<dynamic>? ?? const [])) {
      if (change is Map) {
        pulledChanges.add(
          await _decodeRemoteNoteChange(session, change.cast<String, dynamic>()),
        );
      }
    }

    return SyncResult(
      cursor: (pullBody['cursor'] as String?) ?? cursor,
      pushedCount: 0,
      pulledCount: pulledChanges.length,
      pulledChanges: pulledChanges,
    );
  }

  Future<http.Response> _post(
      Uri baseUri, String path, Map<String, dynamic> payload) async {
    final response = await _httpClient.post(
      baseUri.resolve(path),
      headers: const <String, String>{
        'content-type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode >= 400) {
      final body =
          response.body.isEmpty ? response.reasonPhrase : response.body;
      throw Exception('HTTP ${response.statusCode}: $body');
    }
    return response;
  }

  Map<String, dynamic> _decodeJson(http.Response response) {
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _encodeNoteChange(
    SyncPushChange change,
    SyncSession session,
    String deviceName,
    String platform,
  ) async {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final metadata = <String, dynamic>{
      'title': change.title,
      'relativePath': change.relativePath,
      'tags': change.tags,
      'wikilinks': change.wikilinks,
    };

    final encryptedPayload = await _cryptoService.encryptNote(
      masterKeyMaterial: session.masterKeyMaterial,
      metadata: metadata,
      markdown: change.markdown,
    );

    return <String, dynamic>{
      'changeId': '${change.objectId}:$timestamp:${change.operation}',
      'objectId': change.objectId,
      'kind': 'note',
      'operation': change.operation,
      'logicalTimestamp': timestamp,
      'originDeviceId': _deviceId(deviceName, platform),
      'encryptedMetadata': encryptedPayload.encryptedMetadata,
      'encryptedPayload': encryptedPayload.encryptedPayload,
    };
  }

  Future<String> _passwordVerifier(String email, String password) async {
    return _cryptoService.passwordVerifierForCredentials(
      email: email,
      password: password,
    );
  }

  String _deviceId(String deviceName, String platform) {
    return base64Url.encode(utf8.encode('$deviceName::$platform'));
  }

  Future<RemoteNoteChange> _decodeRemoteNoteChange(
    SyncSession session,
    Map<String, dynamic> json,
  ) async {
    final decrypted = await _cryptoService.decryptNote(
      masterKeyMaterial: session.masterKeyMaterial,
      encryptedMetadata: json['encryptedMetadata'] as String? ?? '',
      encryptedPayload: json['encryptedPayload'] as String? ?? '',
    );
    final metadata = decrypted.metadata;

    return RemoteNoteChange(
      changeId: json['changeId'] as String? ?? '',
      objectId: json['objectId'] as String? ?? '',
      operation: json['operation'] as String? ?? 'upsert',
      relativePath: metadata['relativePath'] as String? ?? '',
      title: metadata['title'] as String? ?? '',
      markdown: decrypted.markdown,
      tags: (metadata['tags'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      wikilinks: (metadata['wikilinks'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
    );
  }

}
