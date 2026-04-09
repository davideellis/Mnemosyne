import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureKeyRepository {
  SecureKeyRepository({
    FlutterSecureStorage? storage,
  }) : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  Future<void> saveMasterKey({
    required String accountId,
    required String masterKeyMaterial,
  }) {
    return _storage.write(
      key: _keyForAccount(accountId),
      value: masterKeyMaterial,
    );
  }

  Future<String?> loadMasterKey(String accountId) {
    return _storage.read(key: _keyForAccount(accountId));
  }

  Future<void> deleteMasterKey(String accountId) {
    return _storage.delete(key: _keyForAccount(accountId));
  }

  String _keyForAccount(String accountId) => 'mnemosyne.master_key.$accountId';
}
