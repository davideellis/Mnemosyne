import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../settings/workspace_settings.dart';
import 'sync_models.dart';

class PersistedAppState {
  const PersistedAppState({
    this.apiBaseUrl,
    this.email,
    this.knownNoteDigests = const <String, String>{},
    this.knownSettingsDigest,
    this.knownTrashDigests = const <String, String>{},
    this.session,
    this.settings = const WorkspaceSettings(),
    this.syncCursor,
    this.vaultRootPath,
  });

  final String? apiBaseUrl;
  final String? email;
  final Map<String, String> knownNoteDigests;
  final String? knownSettingsDigest;
  final Map<String, String> knownTrashDigests;
  final SyncSession? session;
  final WorkspaceSettings settings;
  final String? syncCursor;
  final String? vaultRootPath;

  Map<String, dynamic> toJson() {
    final sessionValue = session;
    return <String, dynamic>{
      'apiBaseUrl': apiBaseUrl,
      'email': email,
      'knownNoteDigests': knownNoteDigests,
      'knownSettingsDigest': knownSettingsDigest,
      'knownTrashDigests': knownTrashDigests,
      'settings': settings.toJson(),
      'syncCursor': syncCursor,
      'vaultRootPath': vaultRootPath,
      'session': sessionValue == null
          ? null
          : <String, dynamic>{
              'accountId': sessionValue.accountId,
              'sessionToken': sessionValue.sessionToken,
              'email': sessionValue.email,
              'encryptedMasterKeyForPassword':
                  sessionValue.encryptedMasterKeyForPassword,
              'encryptedMasterKeyForRecovery':
                  sessionValue.encryptedMasterKeyForRecovery,
              'wrappedMasterKeyForApproval':
                  sessionValue.wrappedMasterKeyForApproval,
              'recoveryKeyHint': sessionValue.recoveryKeyHint,
            },
    };
  }

  factory PersistedAppState.fromJson(Map<String, dynamic> json) {
    final sessionJson = json['session'] as Map<String, dynamic>?;
    final digestJson = json['knownNoteDigests'] as Map<String, dynamic>?;
    final trashDigestJson = json['knownTrashDigests'] as Map<String, dynamic>?;
    return PersistedAppState(
      apiBaseUrl: json['apiBaseUrl'] as String?,
      email: json['email'] as String?,
      knownNoteDigests: digestJson == null
          ? const <String, String>{}
          : digestJson.map(
              (key, value) => MapEntry(key, value as String),
            ),
      knownSettingsDigest: json['knownSettingsDigest'] as String?,
      knownTrashDigests: trashDigestJson == null
          ? const <String, String>{}
          : trashDigestJson.map(
              (key, value) => MapEntry(key, value as String),
            ),
      settings: WorkspaceSettings.fromJson(
        (json['settings'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      ),
      syncCursor: json['syncCursor'] as String?,
      vaultRootPath: json['vaultRootPath'] as String?,
      session: sessionJson == null
          ? null
          : SyncSession(
              accountId: sessionJson['accountId'] as String,
              sessionToken: sessionJson['sessionToken'] as String,
              email: sessionJson['email'] as String,
              encryptedMasterKeyForPassword:
                  sessionJson['encryptedMasterKeyForPassword'] as String? ?? '',
              encryptedMasterKeyForRecovery:
                  sessionJson['encryptedMasterKeyForRecovery'] as String? ?? '',
              wrappedMasterKeyForApproval:
                  sessionJson['wrappedMasterKeyForApproval'] as String? ?? '',
              masterKeyMaterial:
                  sessionJson['masterKeyMaterial'] as String? ?? '',
              recoveryKeyHint: sessionJson['recoveryKeyHint'] as String? ?? '',
            ),
    );
  }
}

class AppStateRepository {
  AppStateRepository({String? filePath}) : _filePath = filePath;

  final String? _filePath;

  Future<PersistedAppState> load() async {
    final file = await _stateFile();
    if (!await file.exists()) {
      return const PersistedAppState();
    }

    final raw = await file.readAsString();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return PersistedAppState.fromJson(json);
  }

  Future<void> save(PersistedAppState state) async {
    final file = await _stateFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
    );
  }

  Future<File> _stateFile() async {
    if (_filePath != null) {
      return File(_filePath);
    }
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return File(path.join(home, '.mnemosyne', 'app_state.json'));
  }
}
