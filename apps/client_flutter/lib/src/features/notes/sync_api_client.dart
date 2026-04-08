import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sync_models.dart';
import 'vault_models.dart';

class SyncApiClient {
  SyncApiClient({
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<SyncSession> bootstrapAccount({
    required Uri baseUri,
    required String email,
    required String password,
    required String deviceName,
    required String platform,
  }) async {
    final response = await _post(
      baseUri,
      '/v1/account/bootstrap',
      <String, dynamic>{
        'email': email,
        'passwordVerifier': _passwordVerifier(email, password),
        'encryptedMasterKeyForPassword': _opaqueEnvelope('master:$email:pw'),
        'encryptedMasterKeyForRecovery':
            _opaqueEnvelope('master:$email:recovery'),
        'recoveryKeyHint': 'saved-locally',
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
        'passwordVerifier': _passwordVerifier(email, password),
      },
    );

    final body = _decodeJson(response);
    return SyncSession(
      accountId: body['accountId'] as String,
      sessionToken: body['sessionToken'] as String,
      email: email,
    );
  }

  Future<SyncResult> syncVault({
    required Uri baseUri,
    required SyncSession session,
    required List<VaultNote> notes,
    required String cursor,
    required String deviceName,
    required String platform,
  }) async {
    final pushResponse = await _post(
      baseUri,
      '/v1/sync/push',
      <String, dynamic>{
        'sessionToken': session.sessionToken,
        'cursor': cursor,
        'changes': notes
            .map((note) => _encodeNoteChange(note, deviceName, platform))
            .toList(),
      },
    );

    final pushBody = _decodeJson(pushResponse);
    final nextCursor = (pushBody['cursor'] as String?) ?? cursor;

    final pullResponse = await _post(
      baseUri,
      '/v1/sync/pull',
      <String, dynamic>{
        'sessionToken': session.sessionToken,
        'cursor': nextCursor,
      },
    );

    final pullBody = _decodeJson(pullResponse);
    final changes = (pullBody['changes'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
            (change) => _decodeRemoteNoteChange(change.cast<String, dynamic>()))
        .toList(growable: false);
    return SyncResult(
      cursor: (pullBody['cursor'] as String?) ?? nextCursor,
      pushedCount: notes.length,
      pulledCount: changes.length,
      pulledChanges: changes,
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

  Map<String, dynamic> _encodeNoteChange(
    VaultNote note,
    String deviceName,
    String platform,
  ) {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final metadata = <String, dynamic>{
      'title': note.title,
      'relativePath': note.relativePath,
      'tags': note.tags,
      'wikilinks': note.wikilinks,
    };

    // Placeholder transport envelopes for early integration work.
    return <String, dynamic>{
      'changeId': '${note.objectId}:$timestamp',
      'objectId': note.objectId,
      'kind': 'note',
      'operation': 'upsert',
      'logicalTimestamp': timestamp,
      'originDeviceId': _deviceId(deviceName, platform),
      'encryptedMetadata': _opaqueEnvelope(jsonEncode(metadata)),
      'encryptedPayload': _opaqueEnvelope(note.markdown),
    };
  }

  String _passwordVerifier(String email, String password) {
    return _opaqueEnvelope('$email::$password');
  }

  String _deviceId(String deviceName, String platform) {
    return base64Url.encode(utf8.encode('$deviceName::$platform'));
  }

  String _opaqueEnvelope(String value) {
    return base64Encode(utf8.encode(value));
  }

  RemoteNoteChange _decodeRemoteNoteChange(Map<String, dynamic> json) {
    final metadataEnvelope = json['encryptedMetadata'] as String? ?? '';
    final payloadEnvelope = json['encryptedPayload'] as String? ?? '';
    final metadata = _decodeEnvelopeJson(metadataEnvelope);

    return RemoteNoteChange(
      changeId: json['changeId'] as String? ?? '',
      objectId: json['objectId'] as String? ?? '',
      operation: json['operation'] as String? ?? 'upsert',
      relativePath: metadata['relativePath'] as String? ?? '',
      title: metadata['title'] as String? ?? '',
      markdown: _decodeEnvelopeText(payloadEnvelope),
      tags: (metadata['tags'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      wikilinks: (metadata['wikilinks'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  Map<String, dynamic> _decodeEnvelopeJson(String encoded) {
    if (encoded.isEmpty) {
      return const <String, dynamic>{};
    }

    final decoded = _decodeEnvelopeText(encoded);
    if (decoded.isEmpty) {
      return const <String, dynamic>{};
    }

    final json = jsonDecode(decoded);
    if (json is Map<String, dynamic>) {
      return json;
    }
    return const <String, dynamic>{};
  }

  String _decodeEnvelopeText(String encoded) {
    if (encoded.isEmpty) {
      return '';
    }

    try {
      return utf8.decode(base64Decode(encoded));
    } catch (_) {
      return '';
    }
  }
}
