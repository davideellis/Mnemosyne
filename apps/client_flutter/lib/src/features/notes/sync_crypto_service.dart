import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';

class BootstrapKeyMaterial {
  const BootstrapKeyMaterial({
    required this.passwordVerifier,
    required this.recoveryVerifier,
    required this.encryptedMasterKeyForPassword,
    required this.encryptedMasterKeyForRecovery,
    required this.masterKeyMaterial,
  });

  final String passwordVerifier;
  final String recoveryVerifier;
  final String encryptedMasterKeyForPassword;
  final String encryptedMasterKeyForRecovery;
  final String masterKeyMaterial;
}

class EncryptedNotePayload {
  const EncryptedNotePayload({
    required this.encryptedMetadata,
    required this.encryptedPayload,
  });

  final String encryptedMetadata;
  final String encryptedPayload;
}

class DecryptedNotePayload {
  const DecryptedNotePayload({
    required this.metadata,
    required this.markdown,
  });

  final Map<String, dynamic> metadata;
  final String markdown;
}

class SyncCryptoService {
  SyncCryptoService({
    Cryptography? cryptography,
  });

  static const int _kdfIterations = 210000;
  static const int _keyLength = 32;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;

  Future<BootstrapKeyMaterial> createBootstrapMaterial({
    required String email,
    required String password,
    required String recoveryKey,
  }) async {
    final masterKey = _randomBytes(_keyLength);
    final passwordSalt = _randomBytes(_saltLength);
    final recoverySalt = _randomBytes(_saltLength);
    final passwordKey = await _deriveKey(
      password,
      salt: passwordSalt,
      context: email.toLowerCase(),
    );
    final recoveryDerivedKey = await _deriveKey(
      _normalizeRecoveryKey(recoveryKey),
      salt: recoverySalt,
      context: 'recovery',
    );

    return BootstrapKeyMaterial(
      passwordVerifier: await passwordVerifierForCredentials(
        email: email,
        password: password,
      ),
      recoveryVerifier: await recoveryVerifierForKey(recoveryKey),
      encryptedMasterKeyForPassword: await _wrapKey(
        masterKey,
        wrappingKey: passwordKey,
        salt: passwordSalt,
      ),
      encryptedMasterKeyForRecovery: await _wrapKey(
        masterKey,
        wrappingKey: recoveryDerivedKey,
        salt: recoverySalt,
      ),
      masterKeyMaterial: _encodeBytes(masterKey),
    );
  }

  Future<String> recoveryVerifierForKey(String recoveryKey) async {
    final recoveryVerifierKey = await _deriveKey(
      _normalizeRecoveryKey(recoveryKey),
      salt: utf8.encode('mnemosyne-recovery-verifier'),
      context: 'recovery-verifier',
    );
    return _passwordVerifier(recoveryVerifierKey);
  }

  Future<String> passwordVerifierForCredentials({
    required String email,
    required String password,
  }) async {
    final passwordVerifierKey = await _deriveKey(
      password,
      salt: utf8.encode(email.toLowerCase()),
      context: 'password-verifier',
    );
    return _passwordVerifier(passwordVerifierKey);
  }

  Future<String> approvalVerifierForCode(String approvalCode) async {
    final approvalVerifierKey = await _deriveKey(
      _normalizeApprovalCode(approvalCode),
      salt: utf8.encode('mnemosyne-approval-verifier'),
      context: 'approval-verifier',
    );
    return _passwordVerifier(approvalVerifierKey);
  }

  Future<String> unwrapMasterKeyWithPassword({
    required String email,
    required String password,
    required String encryptedMasterKeyForPassword,
  }) async {
    final envelope = _decodeEnvelope(encryptedMasterKeyForPassword);
    final passwordKey = await _deriveKey(
      password,
      salt: _decodeBytes(envelope['salt'] as String? ?? ''),
      context: email.toLowerCase(),
      iterations: (envelope['iterations'] as num?)?.toInt() ?? _kdfIterations,
    );
    final masterKey = await _decryptEnvelope(
      envelope: envelope,
      secretKeyBytes: passwordKey,
    );
    return _encodeBytes(masterKey);
  }

  Future<EncryptedNotePayload> encryptNote({
    required String masterKeyMaterial,
    required Map<String, dynamic> metadata,
    required String markdown,
  }) async {
    final secretKeyBytes = _decodeBytes(masterKeyMaterial);
    final encryptedMetadata = await _encryptEnvelope(
      plaintext: utf8.encode(jsonEncode(metadata)),
      secretKeyBytes: secretKeyBytes,
    );
    final encryptedPayload = await _encryptEnvelope(
      plaintext: utf8.encode(markdown),
      secretKeyBytes: secretKeyBytes,
    );
    return EncryptedNotePayload(
      encryptedMetadata: encryptedMetadata,
      encryptedPayload: encryptedPayload,
    );
  }

  Future<String> unwrapMasterKeyWithRecovery({
    required String recoveryKey,
    required String encryptedMasterKeyForRecovery,
  }) async {
    final envelope = _decodeEnvelope(encryptedMasterKeyForRecovery);
    final recoveryDerivedKey = await _deriveKey(
      _normalizeRecoveryKey(recoveryKey),
      salt: _decodeBytes(envelope['salt'] as String? ?? ''),
      context: 'recovery',
      iterations: (envelope['iterations'] as num?)?.toInt() ?? _kdfIterations,
    );
    final masterKey = await _decryptEnvelope(
      envelope: envelope,
      secretKeyBytes: recoveryDerivedKey,
    );
    return _encodeBytes(masterKey);
  }

  Future<String> wrapMasterKeyWithApprovalCode({
    required String approvalCode,
    required String masterKeyMaterial,
  }) async {
    final approvalSalt = _randomBytes(_saltLength);
    final approvalKey = await _deriveKey(
      _normalizeApprovalCode(approvalCode),
      salt: approvalSalt,
      context: 'device-approval',
    );
    return _wrapKey(
      _decodeBytes(masterKeyMaterial),
      wrappingKey: approvalKey,
      salt: approvalSalt,
    );
  }

  Future<String> unwrapMasterKeyWithApprovalCode({
    required String approvalCode,
    required String wrappedKeyBlob,
  }) async {
    final envelope = _decodeEnvelope(wrappedKeyBlob);
    final approvalKey = await _deriveKey(
      _normalizeApprovalCode(approvalCode),
      salt: _decodeBytes(envelope['salt'] as String? ?? ''),
      context: 'device-approval',
      iterations: (envelope['iterations'] as num?)?.toInt() ?? _kdfIterations,
    );
    final masterKey = await _decryptEnvelope(
      envelope: envelope,
      secretKeyBytes: approvalKey,
    );
    return _encodeBytes(masterKey);
  }

  Future<DecryptedNotePayload> decryptNote({
    required String masterKeyMaterial,
    required String encryptedMetadata,
    required String encryptedPayload,
  }) async {
    final secretKeyBytes = _decodeBytes(masterKeyMaterial);
    final metadataJson = utf8.decode(
      await _decryptEnvelope(
        envelope: _decodeEnvelope(encryptedMetadata),
        secretKeyBytes: secretKeyBytes,
      ),
    );
    final markdown = utf8.decode(
      await _decryptEnvelope(
        envelope: _decodeEnvelope(encryptedPayload),
        secretKeyBytes: secretKeyBytes,
      ),
    );

    final decodedMetadata = jsonDecode(metadataJson);
    return DecryptedNotePayload(
      metadata: decodedMetadata is Map<String, dynamic>
          ? decodedMetadata
          : const <String, dynamic>{},
      markdown: markdown,
    );
  }

  Future<List<int>> _deriveKey(
    String secret, {
    required List<int> salt,
    required String context,
    int iterations = _kdfIterations,
  }) async {
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: _keyLength * 8,
    );
    final nonce = utf8.encode('$context:${_encodeBytes(salt)}');
    final derivedKey = await algorithm.deriveKeyFromPassword(
      password: secret,
      nonce: Uint8List.fromList(nonce),
    );
    return derivedKey.extractBytes();
  }

  String _passwordVerifier(List<int> derivedPasswordKey) {
    final digest = hashes.sha256.convert(
      <int>[
        ...derivedPasswordKey,
        ...utf8.encode('mnemosyne-password-verifier-v1'),
      ],
    );
    return _encodeBytes(digest.bytes);
  }

  Future<String> _wrapKey(
    List<int> plaintextKey, {
    required List<int> wrappingKey,
    required List<int> salt,
  }) async {
    return _encryptEnvelope(
      plaintext: plaintextKey,
      secretKeyBytes: wrappingKey,
      salt: salt,
      iterations: _kdfIterations,
    );
  }

  Future<String> _encryptEnvelope({
    required List<int> plaintext,
    required List<int> secretKeyBytes,
    List<int>? salt,
    int? iterations,
  }) async {
    final algorithm = AesGcm.with256bits();
    final secretBox = await algorithm.encrypt(
      plaintext,
      secretKey: SecretKey(secretKeyBytes),
      nonce: _randomBytes(_nonceLength),
    );

    final envelope = <String, dynamic>{
      'v': 1,
      'alg': 'A256GCM',
      'nonce': _encodeBytes(secretBox.nonce),
      'ciphertext': _encodeBytes(secretBox.cipherText),
      'mac': _encodeBytes(secretBox.mac.bytes),
    };
    if (salt != null) {
      envelope['salt'] = _encodeBytes(salt);
    }
    if (iterations != null) {
      envelope['iterations'] = iterations;
    }

    return base64Encode(utf8.encode(jsonEncode(envelope)));
  }

  Future<List<int>> _decryptEnvelope({
    required Map<String, dynamic> envelope,
    required List<int> secretKeyBytes,
  }) async {
    final algorithm = AesGcm.with256bits();
    final secretBox = SecretBox(
      _decodeBytes(envelope['ciphertext'] as String? ?? ''),
      nonce: _decodeBytes(envelope['nonce'] as String? ?? ''),
      mac: Mac(_decodeBytes(envelope['mac'] as String? ?? '')),
    );

    return algorithm.decrypt(
      secretBox,
      secretKey: SecretKey(secretKeyBytes),
    );
  }

  Map<String, dynamic> _decodeEnvelope(String encodedEnvelope) {
    if (encodedEnvelope.isEmpty) {
      throw const FormatException('Missing encrypted envelope.');
    }
    final decoded = utf8.decode(base64Decode(encodedEnvelope));
    final json = jsonDecode(decoded);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Encrypted envelope was not a JSON object.');
    }
    return json;
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  String _normalizeRecoveryKey(String recoveryKey) {
    return recoveryKey.replaceAll('-', '').replaceAll(' ', '').toUpperCase();
  }

  String _normalizeApprovalCode(String approvalCode) {
    return approvalCode.replaceAll('-', '').replaceAll(' ', '').toUpperCase();
  }

  String _encodeBytes(List<int> bytes) {
    return base64Encode(bytes);
  }

  List<int> _decodeBytes(String encoded) {
    if (encoded.isEmpty) {
      return const <int>[];
    }
    return base64Decode(encoded);
  }
}
