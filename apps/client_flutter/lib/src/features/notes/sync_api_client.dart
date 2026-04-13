import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sync_crypto_service.dart';
import 'sync_models.dart';

class SyncApiException implements Exception {
  const SyncApiException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() => 'HTTP $statusCode: $message';
}

class SyncApiClient {
  SyncApiClient({
    http.Client? httpClient,
    SyncCryptoService? cryptoService,
    Duration? requestTimeout,
  })  : _httpClient = httpClient ?? http.Client(),
        _cryptoService = cryptoService ?? SyncCryptoService(),
        _requestTimeout = requestTimeout ?? const Duration(seconds: 15);

  final http.Client _httpClient;
  final SyncCryptoService _cryptoService;
  final Duration _requestTimeout;

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
      sessionExpiresAt: body['sessionExpiresAt'] == null
          ? null
          : DateTime.tryParse(body['sessionExpiresAt'] as String),
      encryptedMasterKeyForPassword:
          body['encryptedMasterKeyForPassword'] as String? ??
              bootstrapMaterial.encryptedMasterKeyForPassword,
      encryptedMasterKeyForRecovery:
          body['encryptedMasterKeyForRecovery'] as String? ??
              bootstrapMaterial.encryptedMasterKeyForRecovery,
      wrappedMasterKeyForApproval:
          body['wrappedMasterKeyForApproval'] as String? ?? '',
      masterKeyMaterial: bootstrapMaterial.masterKeyMaterial,
      recoveryKeyHint: body['recoveryKeyHint'] as String? ?? recoveryKeyHint,
    );
  }

  Future<SyncSession> login({
    required Uri baseUri,
    required String email,
    required String password,
    required String deviceName,
    required String platform,
  }) async {
    final response = await _post(
      baseUri,
      '/v1/auth/login',
      <String, dynamic>{
        'email': email,
        'passwordVerifier': await _passwordVerifier(email, password),
        'device': <String, dynamic>{
          'deviceId': _deviceId(deviceName, platform),
          'deviceName': deviceName,
          'platform': platform,
        },
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
      sessionExpiresAt: body['sessionExpiresAt'] == null
          ? null
          : DateTime.tryParse(body['sessionExpiresAt'] as String),
      encryptedMasterKeyForPassword: encryptedMasterKeyForPassword,
      encryptedMasterKeyForRecovery:
          body['encryptedMasterKeyForRecovery'] as String? ?? '',
      wrappedMasterKeyForApproval:
          body['wrappedMasterKeyForApproval'] as String? ?? '',
      masterKeyMaterial: masterKeyMaterial,
      recoveryKeyHint: body['recoveryKeyHint'] as String? ?? '',
    );
  }

  Future<void> logout({
    required Uri baseUri,
    required SyncSession session,
  }) async {
    await _post(
      baseUri,
      '/v1/auth/logout',
      <String, dynamic>{
        'sessionToken': session.sessionToken,
      },
    );
  }

  Future<SyncSession> recover({
    required Uri baseUri,
    required String email,
    required String recoveryKey,
    required String deviceName,
    required String platform,
  }) async {
    final response = await _post(
      baseUri,
      '/v1/auth/recover',
      <String, dynamic>{
        'email': email,
        'recoveryVerifier':
            await _cryptoService.recoveryVerifierForKey(recoveryKey),
        'device': <String, dynamic>{
          'deviceId': _deviceId(deviceName, platform),
          'deviceName': deviceName,
          'platform': platform,
        },
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

    return _sessionFromBody(
      body,
      email: email,
      masterKeyMaterial: masterKeyMaterial,
    );
  }

  Future<String> startDeviceApproval({
    required Uri baseUri,
    required SyncSession session,
    required String approvalCode,
  }) async {
    final wrappedKeyBlob = await _cryptoService.wrapMasterKeyWithApprovalCode(
      approvalCode: approvalCode,
      masterKeyMaterial: session.masterKeyMaterial,
    );
    final response = await _post(
      baseUri,
      '/v1/devices/approval/start',
      <String, dynamic>{
        'sessionToken': session.sessionToken,
        'approvalVerifier':
            await _cryptoService.approvalVerifierForCode(approvalCode),
        'wrappedKeyBlob': wrappedKeyBlob,
      },
    );
    final body = _decodeJson(response);
    return body['expiresAt'] as String? ?? '';
  }

  Future<SyncSession> consumeDeviceApproval({
    required Uri baseUri,
    required String email,
    required String approvalCode,
    required String deviceName,
    required String platform,
  }) async {
    final response = await _post(
      baseUri,
      '/v1/devices/approval/consume',
      <String, dynamic>{
        'email': email,
        'approvalVerifier':
            await _cryptoService.approvalVerifierForCode(approvalCode),
        'device': <String, dynamic>{
          'deviceId': _deviceId(deviceName, platform),
          'deviceName': deviceName,
          'platform': platform,
        },
      },
    );

    final body = _decodeJson(response);
    final wrappedKeyBlob = body['wrappedMasterKeyForApproval'] as String? ?? '';
    final masterKeyMaterial = wrappedKeyBlob.isEmpty
        ? ''
        : await _cryptoService.unwrapMasterKeyWithApprovalCode(
            approvalCode: approvalCode,
            wrappedKeyBlob: wrappedKeyBlob,
          );
    return _sessionFromBody(
      body,
      email: email,
      masterKeyMaterial: masterKeyMaterial,
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

    if (encodedChanges.isEmpty) {
      final pullResult = await pullVault(
        baseUri: baseUri,
        session: session,
        cursor: cursor,
      );
      return SyncResult(
        cursor: pullResult.cursor,
        pushedCount: 0,
        pulledCount: pullResult.pulledCount,
        pulledChanges: pullResult.pulledChanges,
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
    final pulledChanges = <RemoteSyncChange>[];
    for (final change in (pullBody['changes'] as List<dynamic>? ?? const [])) {
      if (change is Map) {
        pulledChanges.add(
          await _decodeRemoteNoteChange(
              session, change.cast<String, dynamic>()),
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

  Future<List<RegisteredDevice>> listDevices({
    required Uri baseUri,
    required SyncSession session,
  }) async {
    final response = await _post(
      baseUri,
      '/v1/devices/list',
      <String, dynamic>{
        'sessionToken': session.sessionToken,
      },
    );
    final body = _decodeJson(response);
    return (body['devices'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map(
          (entry) => RegisteredDevice(
            deviceId: entry['deviceId'] as String? ?? '',
            deviceName: entry['deviceName'] as String? ?? '',
            platform: entry['platform'] as String? ?? '',
            lastSeenAt: entry['lastSeenAt'] == null
                ? null
                : DateTime.tryParse(entry['lastSeenAt'] as String),
          ),
        )
        .toList(growable: false);
  }

  Future<void> revokeDevice({
    required Uri baseUri,
    required SyncSession session,
    required String deviceId,
  }) async {
    await _post(
      baseUri,
      '/v1/devices/revoke',
      <String, dynamic>{
        'sessionToken': session.sessionToken,
        'deviceId': deviceId,
      },
    );
  }

  Future<RemoteSyncChange> restoreTrash({
    required Uri baseUri,
    required SyncSession session,
    required String objectId,
  }) async {
    final response = await _post(
      baseUri,
      '/v1/trash/restore',
      <String, dynamic>{
        'sessionToken': session.sessionToken,
        'objectId': objectId,
      },
    );
    return _decodeRemoteNoteChange(session, _decodeJson(response));
  }

  Future<http.Response> _post(
      Uri baseUri, String path, Map<String, dynamic> payload) async {
    final response = await _sendRequest(() {
      return _httpClient.post(
        baseUri.resolve(path),
        headers: const <String, String>{
          'content-type': 'application/json',
        },
        body: jsonEncode(payload),
      );
    });

    if (response.statusCode >= 400) {
      final body =
          response.body.isEmpty ? response.reasonPhrase : response.body;
      throw SyncApiException(
        statusCode: response.statusCode,
        message: '$body',
      );
    }
    return response;
  }

  Future<http.Response> _sendRequest(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request().timeout(_requestTimeout);
    } on SyncApiException {
      rethrow;
    } on Exception catch (error) {
      throw SyncApiException(
        statusCode: 0,
        message: error is TimeoutException
            ? 'Request timed out after ${_requestTimeout.inSeconds}s.'
            : 'Request failed: $error',
      );
    }
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
      if (change.kind == 'note') ...<String, dynamic>{
        'title': change.title,
        'relativePath': change.relativePath,
        'tags': change.tags,
        'wikilinks': change.wikilinks,
      },
      if (change.kind == 'settings') 'settings': change.settings,
    };

    final encryptedPayload = await _cryptoService.encryptNote(
      masterKeyMaterial: session.masterKeyMaterial,
      metadata: metadata,
      markdown: change.markdown,
    );

    return <String, dynamic>{
      'changeId': '${change.objectId}:$timestamp:${change.operation}',
      'objectId': change.objectId,
      'kind': change.kind,
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

  Future<RemoteSyncChange> _decodeRemoteNoteChange(
    SyncSession session,
    Map<String, dynamic> json,
  ) async {
    final decrypted = await _cryptoService.decryptNote(
      masterKeyMaterial: session.masterKeyMaterial,
      encryptedMetadata: json['encryptedMetadata'] as String? ?? '',
      encryptedPayload: json['encryptedPayload'] as String? ?? '',
    );
    final metadata = decrypted.metadata;

    return RemoteSyncChange(
      changeId: json['changeId'] as String? ?? '',
      objectId: json['objectId'] as String? ?? '',
      kind: json['kind'] as String? ?? 'note',
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
      settings: (metadata['settings'] as Map<dynamic, dynamic>? ?? const {})
          .map((key, value) => MapEntry(key as String, value)),
    );
  }

  SyncSession _sessionFromBody(
    Map<String, dynamic> body, {
    required String email,
    required String masterKeyMaterial,
  }) {
    return SyncSession(
      accountId: body['accountId'] as String,
      sessionToken: body['sessionToken'] as String,
      email: email,
      sessionExpiresAt: body['sessionExpiresAt'] == null
          ? null
          : DateTime.tryParse(body['sessionExpiresAt'] as String),
      encryptedMasterKeyForPassword:
          body['encryptedMasterKeyForPassword'] as String? ?? '',
      encryptedMasterKeyForRecovery:
          body['encryptedMasterKeyForRecovery'] as String? ?? '',
      wrappedMasterKeyForApproval:
          body['wrappedMasterKeyForApproval'] as String? ?? '',
      masterKeyMaterial: masterKeyMaterial,
      recoveryKeyHint: body['recoveryKeyHint'] as String? ?? '',
    );
  }
}
