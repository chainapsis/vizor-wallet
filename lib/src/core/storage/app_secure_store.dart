import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../security/password_policy.dart';

const kWalletDbNameKey = 'zcash_wallet_db_name';
const _secureStoreSaltKey = 'zcash_secure_store_salt';
const _passwordVerifierKey = 'zcash_password_verifier';
const _passwordVerifierSaltKey = 'zcash_password_verifier_salt';
const _secureStoreService = 'com.keplr.vizor.secure_store';

class AppSecureStore {
  AppSecureStore._();

  static final AppSecureStore instance = AppSecureStore._();

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: _secureStoreService,
      accessibility: KeychainAccessibility.first_unlock,
    ),
    mOptions: MacOsOptions(
      accountName: _secureStoreService,
      accessibility: KeychainAccessibility.first_unlock,
      usesDataProtectionKeychain: true,
    ),
  );

  static final Cipher _cipher = AesGcm.with256bits();
  static final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 100000,
    bits: 256,
  );

  static SecretKey? _cachedSecretKey;
  static String? _sessionPassword;

  bool get hasSessionPassword => _sessionPassword != null;

  Future<String> ensureWalletDbName() async {
    final existing = await readPlain(kWalletDbNameKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final suffix = _randomHex(12);
    final dbName = 'zcash_wallet_$suffix.db';
    await writePlain(kWalletDbNameKey, dbName);
    return dbName;
  }

  Future<String?> readString(String key) async {
    return _storage.read(key: key);
  }

  Future<String?> readSecretStringWithOptions(
    String key, {
    bool requireUnlockedSession = false,
  }) async {
    if (requireUnlockedSession && !hasSessionPassword) {
      return null;
    }
    if (!hasSessionPassword) {
      throw StateError('Secret storage requires an unlocked session.');
    }

    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) return null;

    final payload = _EncryptedPayload.tryParse(raw);
    if (payload == null) {
      return null;
    }

    final secretKey = await _getSecretKey();
    final clearText = await _cipher.decrypt(
      SecretBox(
        payload.cipherText,
        nonce: payload.nonce,
        mac: Mac(payload.mac),
      ),
      secretKey: secretKey,
    );
    return utf8.decode(clearText);
  }

  Future<void> writeString(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<void> writeSecretString(String key, String value) async {
    final secretKey = await _getSecretKey();
    final nonce = _randomBytes(12);
    final secretBox = await _cipher.encrypt(
      utf8.encode(value),
      secretKey: secretKey,
      nonce: nonce,
    );
    await _storage.write(
      key: key,
      value: _EncryptedPayload(
        nonce: secretBox.nonce,
        cipherText: secretBox.cipherText,
        mac: secretBox.mac.bytes,
      ).serialize(),
    );
  }

  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  Future<void> deleteAll() async {
    await _storage.deleteAll();
    _cachedSecretKey = null;
    _sessionPassword = null;
  }

  Future<String?> readPlain(String key) {
    return _storage.read(key: key);
  }

  Future<void> writePlain(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  Future<bool> isPasswordConfigured() async {
    final verifier = await readPlain(_passwordVerifierKey);
    final salt = await readPlain(_passwordVerifierSaltKey);
    return verifier != null &&
        verifier.isNotEmpty &&
        salt != null &&
        salt.isNotEmpty;
  }

  Future<void> configurePassword(String password) async {
    final error = validateWalletPassword(password);
    if (error != null) {
      throw ArgumentError(error);
    }
    final salt = _randomBytes(16);
    final verifier = await _derivePasswordVerifier(password, salt);
    await writePlain(_passwordVerifierSaltKey, base64Encode(salt));
    await writePlain(_passwordVerifierKey, verifier);
    setSessionPassword(password);
  }

  Future<void> clearPasswordConfiguration() async {
    await delete(_passwordVerifierSaltKey);
    await delete(_passwordVerifierKey);
    clearSessionPassword();
  }

  Future<bool> verifyPassword(String password) async {
    if (!isWalletPasswordValid(password)) {
      return false;
    }
    final encodedSalt = await readPlain(_passwordVerifierSaltKey);
    final storedVerifier = await readPlain(_passwordVerifierKey);
    if (encodedSalt == null ||
        encodedSalt.isEmpty ||
        storedVerifier == null ||
        storedVerifier.isEmpty) {
      return false;
    }

    final derived = await _derivePasswordVerifier(
      password,
      base64Decode(encodedSalt),
    );
    final isMatch = derived == storedVerifier;
    if (isMatch) {
      setSessionPassword(password);
    }
    return isMatch;
  }

  void setSessionPassword(String password) {
    _sessionPassword = password;
    _cachedSecretKey = null;
  }

  void clearSessionPassword() {
    _sessionPassword = null;
    _cachedSecretKey = null;
  }

  Future<SecretKey> _getSecretKey() async {
    final sessionPassword = _sessionPassword;
    if (sessionPassword == null) {
      throw StateError('Secret storage requires an unlocked session.');
    }

    final cached = _cachedSecretKey;
    if (cached != null) return cached;

    final salt = await _getOrCreateSalt();
    final key = await _kdf.deriveKeyFromPassword(
      password: sessionPassword,
      nonce: salt,
    );
    _cachedSecretKey = key;
    return key;
  }

  Future<String> _derivePasswordVerifier(
    String password,
    List<int> salt,
  ) async {
    final key = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    return base64Encode(await key.extractBytes());
  }

  Future<List<int>> _getOrCreateSalt() async {
    final encoded = await readPlain(_secureStoreSaltKey);
    if (encoded != null && encoded.isNotEmpty) {
      return base64Decode(encoded);
    }

    final salt = _randomBytes(16);
    await writePlain(_secureStoreSaltKey, base64Encode(salt));
    return salt;
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  String _randomHex(int bytes) {
    final data = _randomBytes(bytes);
    final buffer = StringBuffer();
    for (final byte in data) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

class _EncryptedPayload {
  const _EncryptedPayload({
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  final List<int> nonce;
  final List<int> cipherText;
  final List<int> mac;

  String serialize() {
    return jsonEncode({
      'v': 1,
      'n': base64Encode(nonce),
      'c': base64Encode(cipherText),
      'm': base64Encode(mac),
    });
  }

  static _EncryptedPayload? tryParse(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      if (json['v'] != 1) return null;
      return _EncryptedPayload(
        nonce: base64Decode(json['n'] as String),
        cipherText: base64Decode(json['c'] as String),
        mac: base64Decode(json['m'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}
