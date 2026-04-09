class SyncSession {
  const SyncSession({
    required this.accountId,
    required this.sessionToken,
    required this.email,
    required this.encryptedMasterKeyForPassword,
    required this.encryptedMasterKeyForRecovery,
    required this.masterKeyMaterial,
    required this.recoveryKeyHint,
  });

  final String accountId;
  final String sessionToken;
  final String email;
  final String encryptedMasterKeyForPassword;
  final String encryptedMasterKeyForRecovery;
  final String masterKeyMaterial;
  final String recoveryKeyHint;

  SyncSession copyWith({
    String? accountId,
    String? sessionToken,
    String? email,
    String? encryptedMasterKeyForPassword,
    String? encryptedMasterKeyForRecovery,
    String? masterKeyMaterial,
    String? recoveryKeyHint,
  }) {
    return SyncSession(
      accountId: accountId ?? this.accountId,
      sessionToken: sessionToken ?? this.sessionToken,
      email: email ?? this.email,
      encryptedMasterKeyForPassword:
          encryptedMasterKeyForPassword ?? this.encryptedMasterKeyForPassword,
      encryptedMasterKeyForRecovery:
          encryptedMasterKeyForRecovery ?? this.encryptedMasterKeyForRecovery,
      masterKeyMaterial: masterKeyMaterial ?? this.masterKeyMaterial,
      recoveryKeyHint: recoveryKeyHint ?? this.recoveryKeyHint,
    );
  }
}

class SyncPushChange {
  const SyncPushChange({
    required this.objectId,
    required this.kind,
    required this.operation,
    this.relativePath = '',
    this.title = '',
    this.markdown = '',
    this.tags = const <String>[],
    this.wikilinks = const <String>[],
    this.settings = const <String, dynamic>{},
  });

  final String objectId;
  final String kind;
  final String operation;
  final String relativePath;
  final String title;
  final String markdown;
  final List<String> tags;
  final List<String> wikilinks;
  final Map<String, dynamic> settings;
}

class RemoteSyncChange {
  const RemoteSyncChange({
    required this.changeId,
    required this.objectId,
    required this.kind,
    required this.operation,
    this.relativePath = '',
    this.title = '',
    this.markdown = '',
    this.tags = const <String>[],
    this.wikilinks = const <String>[],
    this.settings = const <String, dynamic>{},
  });

  final String changeId;
  final String objectId;
  final String kind;
  final String operation;
  final String relativePath;
  final String title;
  final String markdown;
  final List<String> tags;
  final List<String> wikilinks;
  final Map<String, dynamic> settings;
}

class SyncResult {
  const SyncResult({
    required this.cursor,
    required this.pushedCount,
    required this.pulledCount,
    required this.pulledChanges,
  });

  final String cursor;
  final int pushedCount;
  final int pulledCount;
  final List<RemoteSyncChange> pulledChanges;
}
