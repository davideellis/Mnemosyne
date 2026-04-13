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
    this.lastNoteFolder,
    this.session,
    this.settings = const WorkspaceSettings(),
    this.showGraphPanel = true,
    this.showVaultPanel = false,
    this.showWorkspacePanel = false,
    this.syncCursor,
    this.vaultRootPath,
  });

  final String? apiBaseUrl;
  final String? email;
  final Map<String, String> knownNoteDigests;
  final String? knownSettingsDigest;
  final Map<String, String> knownTrashDigests;
  final String? lastNoteFolder;
  final SyncSession? session;
  final WorkspaceSettings settings;
  final bool showGraphPanel;
  final bool showVaultPanel;
  final bool showWorkspacePanel;
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
      'lastNoteFolder': lastNoteFolder,
      'settings': settings.toJson(),
      'showGraphPanel': showGraphPanel,
      'showVaultPanel': showVaultPanel,
      'showWorkspacePanel': showWorkspacePanel,
      'syncCursor': syncCursor,
      'vaultRootPath': vaultRootPath,
      'session': sessionValue == null
          ? null
          : <String, dynamic>{
              'accountId': sessionValue.accountId,
              'sessionToken': sessionValue.sessionToken,
              'email': sessionValue.email,
              'sessionExpiresAt':
                  sessionValue.sessionExpiresAt?.toUtc().toIso8601String(),
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
      lastNoteFolder: json['lastNoteFolder'] as String?,
      settings: WorkspaceSettings.fromJson(
        (json['settings'] as Map<String, dynamic>?) ??
            const <String, dynamic>{},
      ),
      showGraphPanel: json['showGraphPanel'] as bool? ?? true,
      showVaultPanel: json['showVaultPanel'] as bool? ?? false,
      showWorkspacePanel: json['showWorkspacePanel'] as bool? ?? false,
      syncCursor: json['syncCursor'] as String?,
      vaultRootPath: json['vaultRootPath'] as String?,
      session: sessionJson == null
          ? null
          : SyncSession(
              accountId: sessionJson['accountId'] as String,
              sessionToken: sessionJson['sessionToken'] as String,
              email: sessionJson['email'] as String,
              sessionExpiresAt: sessionJson['sessionExpiresAt'] == null
                  ? null
                  : DateTime.tryParse(
                      sessionJson['sessionExpiresAt'] as String,
                    ),
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
