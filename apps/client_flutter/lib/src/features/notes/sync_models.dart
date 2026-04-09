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
}

class SyncPushChange {
  const SyncPushChange({
    required this.objectId,
    required this.operation,
    required this.relativePath,
    required this.title,
    required this.markdown,
    required this.tags,
    required this.wikilinks,
  });

  final String objectId;
  final String operation;
  final String relativePath;
  final String title;
  final String markdown;
  final List<String> tags;
  final List<String> wikilinks;
}

class RemoteNoteChange {
  const RemoteNoteChange({
    required this.changeId,
    required this.objectId,
    required this.operation,
    required this.relativePath,
    required this.title,
    required this.markdown,
    required this.tags,
    required this.wikilinks,
  });

  final String changeId;
  final String objectId;
  final String operation;
  final String relativePath;
  final String title;
  final String markdown;
  final List<String> tags;
  final List<String> wikilinks;
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
  final List<RemoteNoteChange> pulledChanges;
}
