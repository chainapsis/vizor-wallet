import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/network_config.dart';
import '../security/password_policy.dart';

const kWalletDbNameKey = 'zcash_wallet_db_name';
const kThemeModeKey = 'zcash_theme_mode';
const kPrivacyModeEnabledKey = 'zcash_privacy_mode_enabled';
const kRpcEndpointUrlKey = 'zcash_rpc_endpoint_url';
const kRpcEndpointPresetKey = 'zcash_rpc_endpoint_preset';
const _secureStoreSaltKey = 'zcash_secure_store_salt';
const _passwordVerifierKey = 'zcash_password_verifier';
const _passwordVerifierSaltKey = 'zcash_password_verifier_salt';
const _passwordRotationInProgressKey = 'zcash_rotation_in_progress';
const _passwordRotationRollbackFailedKind = 'rollbackFailed';
const _accountMnemonicKeyPrefix = 'zcash_account_mnemonic_';

class PasswordRotationRecoveryFailedException implements Exception {
  const PasswordRotationRecoveryFailedException();

  @override
  String toString() =>
      'Password rotation rollback failed; automatic recovery is unsafe.';
}

class AppSecureStore {
  AppSecureStore._({FlutterSecureStorage? storage})
    : _storage = storage ?? _defaultStorage();

  @visibleForTesting
  AppSecureStore.testing({required FlutterSecureStorage storage})
    : _storage = storage;

  static final AppSecureStore instance = AppSecureStore._();

  static FlutterSecureStorage _defaultStorage() {
    final service = secureStoreServiceForNetwork(kZcashDefaultNetworkName);
    return FlutterSecureStorage(
      iOptions: IOSOptions(
        accountName: service,
        accessibility: KeychainAccessibility.first_unlock,
      ),
      aOptions: kZcashDefaultNetworkName == 'main'
          ? AndroidOptions.defaultOptions
          : AndroidOptions(sharedPreferencesName: service),
      mOptions: MacOsOptions(
        accountName: service,
        accessibility: KeychainAccessibility.first_unlock,
        usesDataProtectionKeychain: true,
      ),
    );
  }

  static final Cipher _cipher = AesGcm.with256bits();
  static final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 100000,
    bits: 256,
  );

  final FlutterSecureStorage _storage;
  final _secretMutationLock = _AsyncLock();
  SecretKey? _cachedSecretKey;
  String? _sessionPassword;

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
  }) {
    return _secretMutationLock.run(() async {
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
    });
  }

  Future<void> writeString(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<void> writeSecretString(String key, String value) {
    return _secretMutationLock.run(() async {
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
    });
  }

  Future<void> delete(String key) async {
    if (key.startsWith(_accountMnemonicKeyPrefix)) {
      await _secretMutationLock.run(() => _storage.delete(key: key));
      return;
    }
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
    final error = validateRequiredWalletPassword(password);
    if (error != null) {
      throw ArgumentError(error);
    }
    final salt = _randomBytes(16);
    final verifier = await _derivePasswordVerifier(password, salt);
    await writePlain(_passwordVerifierSaltKey, base64Encode(salt));
    await writePlain(_passwordVerifierKey, verifier);
    setSessionPassword(password);
  }

  /// Rotates the wallet password and re-encrypts every app-managed encrypted
  /// secure-storage payload so mnemonic entries remain readable afterwards.
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    // Secret writes and password rotation share one lock so a mnemonic cannot
    // be encrypted with the old key after rotation has taken its key snapshot.
    return _secretMutationLock.run(() async {
      final existingRecoveryRecord = await readPlain(
        _passwordRotationInProgressKey,
      );
      // Defense in depth: bootstrap normally reports this state, but password
      // changes must still refuse to overwrite the sticky failure marker.
      if (existingRecoveryRecord != null &&
          _isRollbackFailedRotationRecord(existingRecoveryRecord)) {
        throw const PasswordRotationRecoveryFailedException();
      }
      if (!isWalletPasswordValid(currentPassword)) {
        return false;
      }
      if (currentPassword == newPassword) {
        throw ArgumentError(kWalletPasswordMustDifferMessage);
      }
      final newPasswordError = validateRequiredWalletPassword(newPassword);
      if (newPasswordError != null) {
        throw ArgumentError(newPasswordError);
      }

      final isCurrentPasswordValid = await verifyPasswordOnly(currentPassword);
      if (!isCurrentPasswordValid) {
        return false;
      }

      final oldVerifierSalt = await readPlain(_passwordVerifierSaltKey);
      final oldVerifier = await readPlain(_passwordVerifierKey);
      final currentSecretKey = await _deriveSecretKeyForPassword(
        currentPassword,
      );
      final newSecretKey = await _deriveSecretKeyForPassword(newPassword);
      try {
        final storedValues = await _storage.readAll();
        final rotatedSecrets = <_PasswordRotationEntry>[];

        for (final entry in storedValues.entries) {
          if (!entry.key.startsWith(_accountMnemonicKeyPrefix)) continue;

          final payload = _EncryptedPayload.tryParse(entry.value);
          if (payload == null) {
            throw StateError(
              'Failed to parse secure-storage value for "${entry.key}".',
            );
          }

          final clearText = await _decryptPayloadForKey(
            entry.key,
            payload,
            currentSecretKey,
          );
          final rotatedValue = await _encryptStringWithKey(
            clearText,
            newSecretKey,
          );
          rotatedSecrets.add(
            _PasswordRotationEntry(
              key: entry.key,
              originalValue: entry.value,
              rotatedValue: rotatedValue,
            ),
          );
        }

        final newVerifierSalt = _randomBytes(16);
        final newVerifier = await _derivePasswordVerifier(
          newPassword,
          newVerifierSalt,
        );

        final rotation = _PasswordRotationRecord(
          oldVerifierSalt: oldVerifierSalt,
          oldVerifier: oldVerifier,
          newVerifierSalt: base64Encode(newVerifierSalt),
          newVerifier: newVerifier,
          entries: rotatedSecrets,
        );
        await writePlain(_passwordRotationInProgressKey, rotation.serialize());

        try {
          await _writeRotatedPasswordState(rotation);
        } catch (error, stackTrace) {
          await _rollbackPasswordRotation(rotation, currentPassword);
          Error.throwWithStackTrace(error, stackTrace);
        }

        setSessionPassword(newPassword);
        await _deleteRotationRecordBestEffort();
      } finally {
        currentSecretKey.destroy();
        newSecretKey.destroy();
      }

      return true;
    });
  }

  Future<void> recoverInterruptedPasswordRotation() async {
    final raw = await readPlain(_passwordRotationInProgressKey);
    if (raw == null || raw.isEmpty) return;
    if (_isRollbackFailedRotationRecord(raw)) {
      throw const PasswordRotationRecoveryFailedException();
    }

    final rotation = _PasswordRotationRecord.tryParse(raw);
    if (rotation == null) {
      await delete(_passwordRotationInProgressKey);
      throw StateError('Password rotation recovery record is invalid.');
    }

    await _writeRotatedPasswordState(rotation);
    await _deleteRotationRecordBestEffort();
    clearSessionPassword();
  }

  Future<void> clearPasswordConfiguration() async {
    await delete(_passwordVerifierSaltKey);
    await delete(_passwordVerifierKey);
    await delete(_passwordRotationInProgressKey);
    clearSessionPassword();
  }

  /// Checks the wallet password without opening or refreshing the encrypted
  /// storage session. Use this for in-app re-authentication prompts where the
  /// wallet is already unlocked and callers only need a fresh password check.
  Future<bool> verifyPasswordOnly(String password) async {
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
    return derived == storedVerifier;
  }

  Future<bool> verifyPassword(String password) async {
    final isMatch = await verifyPasswordOnly(password);
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

  Future<SecretKey> _deriveSecretKeyForPassword(String password) async {
    final salt = await _getOrCreateSalt();
    return _kdf.deriveKeyFromPassword(password: password, nonce: salt);
  }

  Future<String> _decryptPayload(
    _EncryptedPayload payload,
    SecretKey secretKey,
  ) async {
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

  Future<String> _decryptPayloadForKey(
    String key,
    _EncryptedPayload payload,
    SecretKey secretKey,
  ) async {
    try {
      return await _decryptPayload(payload, secretKey);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        StateError('Failed to decrypt secure-storage value for "$key": $error'),
        stackTrace,
      );
    }
  }

  Future<String> _encryptStringWithKey(
    String value,
    SecretKey secretKey,
  ) async {
    final nonce = _randomBytes(12);
    final secretBox = await _cipher.encrypt(
      utf8.encode(value),
      secretKey: secretKey,
      nonce: nonce,
    );
    return _EncryptedPayload(
      nonce: secretBox.nonce,
      cipherText: secretBox.cipherText,
      mac: secretBox.mac.bytes,
    ).serialize();
  }

  Future<String> _derivePasswordVerifier(
    String password,
    List<int> salt,
  ) async {
    final key = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    try {
      return base64Encode(await key.extractBytes());
    } finally {
      key.destroy();
    }
  }

  Future<void> _writeRotatedPasswordState(
    _PasswordRotationRecord rotation,
  ) async {
    for (final entry in rotation.entries) {
      await writePlain(entry.key, entry.rotatedValue);
    }
    await writePlain(_passwordVerifierSaltKey, rotation.newVerifierSalt);
    await writePlain(_passwordVerifierKey, rotation.newVerifier);
  }

  Future<void> _rollbackPasswordRotation(
    _PasswordRotationRecord rotation,
    String currentPassword,
  ) async {
    try {
      final rollbackRecord = rotation.toRollbackRecord();
      if (rollbackRecord != null) {
        await writePlain(
          _passwordRotationInProgressKey,
          rollbackRecord.serialize(),
        );
      }
      for (final entry in rotation.entries) {
        await writePlain(entry.key, entry.originalValue);
      }
      if (rotation.oldVerifierSalt == null) {
        await delete(_passwordVerifierSaltKey);
      } else {
        await writePlain(_passwordVerifierSaltKey, rotation.oldVerifierSalt!);
      }
      if (rotation.oldVerifier == null) {
        await delete(_passwordVerifierKey);
      } else {
        await writePlain(_passwordVerifierKey, rotation.oldVerifier!);
      }
      setSessionPassword(currentPassword);
      await _deleteRotationRecordBestEffort();
    } catch (rollbackError, rollbackStackTrace) {
      await _markRollbackFailedBestEffort();
      debugPrint(
        'AppSecureStore: rollback failed: $rollbackError\n$rollbackStackTrace',
      );
    }
  }

  Future<void> _deleteRotationRecordBestEffort() async {
    try {
      await delete(_passwordRotationInProgressKey);
    } catch (error, stackTrace) {
      debugPrint(
        'AppSecureStore: failed to delete rotation record: $error\n$stackTrace',
      );
    }
  }

  Future<void> _markRollbackFailedBestEffort() async {
    try {
      // If rollback cannot even replace the forward journal, do not let the
      // next boot silently roll forward after the UI reported failure.
      await writePlain(
        _passwordRotationInProgressKey,
        jsonEncode({'v': 1, 'kind': _passwordRotationRollbackFailedKind}),
      );
    } catch (error, stackTrace) {
      debugPrint(
        'AppSecureStore: failed to mark rollback failure: $error\n$stackTrace',
      );
    }
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

class _AsyncLock {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final completer = Completer<void>();
    _tail = completer.future;

    return previous
        .then((_) => Future<T>.sync(action))
        .whenComplete(() => completer.complete());
  }
}

class _PasswordRotationEntry {
  const _PasswordRotationEntry({
    required this.key,
    required this.originalValue,
    required this.rotatedValue,
  });

  final String key;
  final String originalValue;
  final String rotatedValue;
}

class _PasswordRotationRecord {
  const _PasswordRotationRecord({
    required this.oldVerifierSalt,
    required this.oldVerifier,
    required this.newVerifierSalt,
    required this.newVerifier,
    required this.entries,
  });

  final String? oldVerifierSalt;
  final String? oldVerifier;
  final String newVerifierSalt;
  final String newVerifier;
  final List<_PasswordRotationEntry> entries;

  String serialize() {
    return jsonEncode({
      'v': 1,
      'oldVerifierSalt': oldVerifierSalt,
      'oldVerifier': oldVerifier,
      'newVerifierSalt': newVerifierSalt,
      'newVerifier': newVerifier,
      'entries': entries
          .map(
            (entry) => {
              'key': entry.key,
              'originalValue': entry.originalValue,
              'rotatedValue': entry.rotatedValue,
            },
          )
          .toList(),
    });
  }

  static _PasswordRotationRecord? tryParse(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      if (json['v'] != 1) return null;

      final entriesJson = json['entries'];
      if (entriesJson is! List) return null;

      return _PasswordRotationRecord(
        oldVerifierSalt: json['oldVerifierSalt'] as String?,
        oldVerifier: json['oldVerifier'] as String?,
        newVerifierSalt: json['newVerifierSalt'] as String,
        newVerifier: json['newVerifier'] as String,
        entries: entriesJson
            .map(
              (entry) => _PasswordRotationEntry(
                key: (entry as Map<String, dynamic>)['key'] as String,
                originalValue: entry['originalValue'] as String,
                rotatedValue: entry['rotatedValue'] as String,
              ),
            )
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }

  _PasswordRotationRecord? toRollbackRecord() {
    final oldSalt = oldVerifierSalt;
    final oldPasswordVerifier = oldVerifier;
    if (oldSalt == null || oldPasswordVerifier == null) return null;

    return _PasswordRotationRecord(
      oldVerifierSalt: newVerifierSalt,
      oldVerifier: newVerifier,
      newVerifierSalt: oldSalt,
      newVerifier: oldPasswordVerifier,
      entries: entries
          .map(
            (entry) => _PasswordRotationEntry(
              key: entry.key,
              originalValue: entry.rotatedValue,
              rotatedValue: entry.originalValue,
            ),
          )
          .toList(),
    );
  }
}

bool _isRollbackFailedRotationRecord(String raw) {
  try {
    final json = jsonDecode(raw);
    return json is Map<String, dynamic> &&
        json['v'] == 1 &&
        json['kind'] == _passwordRotationRollbackFailedKind;
  } catch (_) {
    return false;
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
