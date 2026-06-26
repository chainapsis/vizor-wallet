import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        debugPrint,
        defaultTargetPlatform,
        kDebugMode,
        kIsWeb,
        visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/local_test_profile.dart';
import '../config/network_config.dart';
import '../security/password_policy.dart';
import '../../rust/api/secret.dart' as rust_secret;

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
const _accountMnemonicMigrationCompleteKey =
    'zcash_mnemonic_storage_migrated_v1';
const _votingHotkeyKeyPrefix = 'zcash_account_voting_hotkey_';
const _e2eUseFirstUnlockMnemonicKeychain = bool.fromEnvironment(
  'ZCASH_E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN',
);

class PasswordRotationRecoveryFailedException implements Exception {
  const PasswordRotationRecoveryFailedException();

  @override
  String toString() =>
      'Password rotation rollback failed; automatic recovery is unsafe.';
}

class SecureStorageUnavailableException implements Exception {
  const SecureStorageUnavailableException({
    required this.operation,
    required this.cause,
  });

  final String operation;
  final Object cause;

  @override
  String toString() => 'Secure storage unavailable during $operation: $cause';
}

class AppSecureStore {
  AppSecureStore._({
    FlutterSecureStorage? storage,
    FlutterSecureStorage? mnemonicStorage,
  }) : _storage = storage ?? _defaultStorage(),
       _mnemonicStorage = mnemonicStorage ?? _defaultMnemonicStorage();

  @visibleForTesting
  AppSecureStore.testing({
    required FlutterSecureStorage storage,
    FlutterSecureStorage? mnemonicStorage,
  }) : _storage = storage,
       _mnemonicStorage = mnemonicStorage ?? storage;

  static final AppSecureStore instance = AppSecureStore._();

  static FlutterSecureStorage _defaultStorage() {
    final service = secureStoreServiceForNetwork(kZcashDefaultNetworkName);
    final macOsService = _macOsSecureStoreServiceForNetwork(
      kZcashDefaultNetworkName,
    );
    return FlutterSecureStorage(
      iOptions: IOSOptions(
        accountName: service,
        accessibility: KeychainAccessibility.first_unlock,
      ),
      aOptions: kZcashDefaultNetworkName == 'main'
          ? AndroidOptions.defaultOptions
          : AndroidOptions(sharedPreferencesName: service),
      mOptions: MacOsOptions(
        accountName: macOsService,
        accessibility: KeychainAccessibility.first_unlock,
        usesDataProtectionKeychain: true,
      ),
    );
  }

  static FlutterSecureStorage _defaultMnemonicStorage() {
    final service = secureStoreServiceForNetwork(kZcashDefaultNetworkName);
    final macOsService = _mnemonicSecureStoreServiceForNetwork(
      kZcashDefaultNetworkName,
    );
    return FlutterSecureStorage(
      iOptions: IOSOptions(
        accountName: service,
        accessibility: KeychainAccessibility.first_unlock,
      ),
      aOptions: kZcashDefaultNetworkName == 'main'
          ? AndroidOptions.defaultOptions
          : AndroidOptions(sharedPreferencesName: service),
      mOptions: MacOsOptions(
        accountName: macOsService,
        accessibility: kDebugMode && _e2eUseFirstUnlockMnemonicKeychain
            ? KeychainAccessibility.first_unlock
            : KeychainAccessibility.unlocked,
        usesDataProtectionKeychain: true,
      ),
    );
  }

  final FlutterSecureStorage _storage;
  final FlutterSecureStorage _mnemonicStorage;
  final _secretMutationLock = _AsyncLock();
  String? _sessionPassword;

  bool get hasSessionPassword => _sessionPassword != null;

  String requireSessionPasswordForNativeSecretUse() {
    final password = _sessionPassword;
    if (password == null) {
      throw StateError('Secret storage requires an unlocked session.');
    }
    return password;
  }

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
    return _runStorageOperation('read "$key"', () => _storage.read(key: key));
  }

  Future<String?> readSecretStringWithOptions(
    String key, {
    bool requireUnlockedSession = false,
  }) {
    return _secretMutationLock.run(() async {
      if (_shouldSkipLockedSecretRead(requireUnlockedSession)) return null;
      final raw = await _runStorageOperation(
        'read secret "$key"',
        () => _storage.read(key: key),
      );
      return _decryptStoredSecretString(
        raw,
        key: key,
        requireUnlockedSession: requireUnlockedSession,
      );
    });
  }

  Future<String?> readAccountMnemonic(
    String accountUuid, {
    bool requireUnlockedSession = false,
  }) {
    return _secretMutationLock.run(() async {
      if (_shouldSkipLockedSecretRead(requireUnlockedSession)) return null;
      final key = _accountMnemonicKey(accountUuid);
      final raw = await _runStorageOperation(
        'read account mnemonic "$accountUuid"',
        () => _mnemonicStorage.read(key: key),
      );
      return _decryptStoredSecretString(
        raw,
        key: key,
        requireUnlockedSession: requireUnlockedSession,
      );
    });
  }

  Future<Uint8List?> readAccountMnemonicBytes(
    String accountUuid, {
    bool requireUnlockedSession = false,
  }) {
    return _secretMutationLock.run(() async {
      if (_shouldSkipLockedSecretRead(requireUnlockedSession)) return null;
      final key = _accountMnemonicKey(accountUuid);
      final raw = await _runStorageOperation(
        'read account mnemonic bytes "$accountUuid"',
        () => _mnemonicStorage.read(key: key),
      );
      return _decryptStoredSecretBytes(
        raw,
        key: key,
        requireUnlockedSession: requireUnlockedSession,
      );
    });
  }

  /// Reads the voting hotkey for an account and round.
  ///
  /// Hotkeys are session secrets, so callers must have an unlocked wallet
  /// session. A locked session returns `null` instead of touching platform
  /// secure storage.
  Future<List<int>?> readVotingHotkey({
    required String accountUuid,
    required String roundId,
  }) async {
    final encoded = await readSecretStringWithOptions(
      votingHotkeyStorageKey(accountUuid: accountUuid, roundId: roundId),
      requireUnlockedSession: true,
    );
    if (encoded == null || encoded.isEmpty) return null;
    return base64Decode(encoded);
  }

  Future<void> writeString(String key, String value) async {
    await _runStorageOperation(
      'write "$key"',
      () => _storage.write(key: key, value: value),
    );
  }

  Future<void> writeSecretString(String key, String value) {
    return _secretMutationLock.run(() async {
      await _runStorageOperation(
        'write secret "$key"',
        () async =>
            _storage.write(key: key, value: await _encryptSecretString(value)),
      );
    });
  }

  Future<void> writeAccountMnemonic(String accountUuid, String mnemonic) {
    return _secretMutationLock.run(() async {
      await _runStorageOperation(
        'write account mnemonic "$accountUuid"',
        () async => _mnemonicStorage.write(
          key: _accountMnemonicKey(accountUuid),
          value: await _encryptSecretString(mnemonic),
        ),
      );
    });
  }

  /// Stores a voting hotkey as an encrypted secret for an account and round.
  Future<void> writeVotingHotkey({
    required String accountUuid,
    required String roundId,
    required List<int> hotkey,
  }) {
    return writeSecretString(
      votingHotkeyStorageKey(accountUuid: accountUuid, roundId: roundId),
      base64Encode(hotkey),
    );
  }

  /// Removes one voting hotkey for an account and round.
  Future<void> deleteVotingHotkey({
    required String accountUuid,
    required String roundId,
  }) {
    return delete(
      votingHotkeyStorageKey(accountUuid: accountUuid, roundId: roundId),
    );
  }

  /// Removes every voting hotkey for an account.
  Future<void> deleteVotingHotkeysForAccount(String accountUuid) {
    return _secretMutationLock.run(() async {
      final prefix = _votingHotkeyAccountPrefix(accountUuid);
      final storedValues = await _runStorageOperation(
        'read voting hotkeys for account "$accountUuid"',
        _storage.readAll,
      );
      for (final key in storedValues.keys.toList(growable: false)) {
        if (!key.startsWith(prefix)) continue;
        await _runStorageOperation(
          'delete voting hotkey "$key"',
          () => _storage.delete(key: key),
        );
      }
    });
  }

  Future<void> delete(String key) async {
    if (key.startsWith(_accountMnemonicKeyPrefix)) {
      await _secretMutationLock.run(() async {
        await _runStorageOperation(
          'delete account mnemonic "$key"',
          () => _mnemonicStorage.delete(key: key),
        );
        await _deleteLegacyAccountMnemonicBestEffort(key);
      });
      return;
    }
    if (key.startsWith(_votingHotkeyKeyPrefix)) {
      await _secretMutationLock.run(() async {
        await _runStorageOperation(
          'delete "$key"',
          () => _storage.delete(key: key),
        );
      });
      return;
    }
    await _runStorageOperation(
      'delete "$key"',
      () => _storage.delete(key: key),
    );
  }

  Future<void> deleteAccountMnemonic(String accountUuid) {
    final key = _accountMnemonicKey(accountUuid);
    return _secretMutationLock.run(() async {
      await _runStorageOperation(
        'delete account mnemonic "$accountUuid"',
        () => _mnemonicStorage.delete(key: key),
      );
      await _deleteLegacyAccountMnemonicBestEffort(key);
    });
  }

  Future<void> deleteAll() {
    return _secretMutationLock.run(() async {
      await _runStorageOperation('delete all', _storage.deleteAll);
      if (!identical(_mnemonicStorage, _storage)) {
        await _runStorageOperation(
          'delete all account mnemonics',
          _mnemonicStorage.deleteAll,
        );
      }
      _sessionPassword = null;
    });
  }

  Future<String?> readPlain(String key) {
    return _runStorageOperation('read "$key"', () => _storage.read(key: key));
  }

  Future<void> writePlain(String key, String value) {
    return _runStorageOperation(
      'write "$key"',
      () => _storage.write(key: key, value: value),
    );
  }

  /// Deletes plain storage entries whose keys start with [prefix].
  ///
  /// Secret values that use the mnemonic or voting hotkey storage helpers should
  /// keep using their dedicated deletion paths.
  Future<void> deletePlainKeysWithPrefix(String prefix) async {
    if (prefix.isEmpty) return;
    final storedValues = await _runStorageOperation(
      'read keys with prefix "$prefix"',
      _storage.readAll,
    );
    for (final key in storedValues.keys.toList(growable: false)) {
      if (!key.startsWith(prefix)) continue;
      await _runStorageOperation(
        'delete "$key"',
        () => _storage.delete(key: key),
      );
    }
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
    final saltBase64 = base64Encode(salt);
    final verifier = await _derivePasswordVerifier(password, saltBase64);
    await writePlain(_passwordVerifierSaltKey, saltBase64);
    await writePlain(_passwordVerifierKey, verifier);
    setSessionPassword(password);
  }

  /// Rotates the wallet password and re-encrypts every app-managed secret.
  ///
  /// Account mnemonics and voting hotkeys are both encrypted with the wallet
  /// password, but they may live in different secure storage backends.
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
      final secretSaltBase64 = await _getOrCreateSaltBase64();
      final migration = await _migrateAccountMnemonicsAfterUnlockLocked();
      if (!migration.legacyCleanupComplete) {
        throw StateError(
          'Failed to migrate account mnemonics before password rotation.',
        );
      }
      final storedValues = await _runStorageOperation(
        'read all account mnemonics',
        _mnemonicStorage.readAll,
      );
      final rotatedSecrets = <_PasswordRotationEntry>[];
      final rollbackSecrets = <_PasswordRotationRollbackEntry>[];

      for (final entry in storedValues.entries) {
        if (!entry.key.startsWith(_accountMnemonicKeyPrefix)) continue;

        if (!_isEncryptedPayload(entry.value)) {
          throw StateError(
            'Failed to parse secure-storage value for "${entry.key}".',
          );
        }

        final clearText = await _decryptPayloadBytesForKey(
          entry.key,
          entry.value,
          currentPassword,
          secretSaltBase64,
        );
        final rotatedValue = await _encryptBytesWithPassword(
          clearText,
          newPassword,
          secretSaltBase64,
        );
        rotatedSecrets.add(
          _PasswordRotationEntry(key: entry.key, rotatedValue: rotatedValue),
        );
        rollbackSecrets.add(
          _PasswordRotationRollbackEntry(
            key: entry.key,
            originalValue: entry.value,
          ),
        );
      }
      final votingHotkeyValues = await _runStorageOperation(
        'read all voting hotkeys',
        _storage.readAll,
      );
      for (final entry in votingHotkeyValues.entries) {
        if (!entry.key.startsWith(_votingHotkeyKeyPrefix)) continue;

        if (!_isEncryptedPayload(entry.value)) {
          throw StateError(
            'Failed to parse secure-storage value for "${entry.key}".',
          );
        }

        final clearText = await _decryptPayloadBytesForKey(
          entry.key,
          entry.value,
          currentPassword,
          secretSaltBase64,
        );
        final rotatedValue = await _encryptBytesWithPassword(
          clearText,
          newPassword,
          secretSaltBase64,
        );
        rotatedSecrets.add(
          _PasswordRotationEntry(key: entry.key, rotatedValue: rotatedValue),
        );
        rollbackSecrets.add(
          _PasswordRotationRollbackEntry(
            key: entry.key,
            originalValue: entry.value,
          ),
        );
      }

      final newVerifierSalt = _randomBytes(16);
      final newVerifierSaltBase64 = base64Encode(newVerifierSalt);
      final newVerifier = await _derivePasswordVerifier(
        newPassword,
        newVerifierSaltBase64,
      );

      final rotation = _PasswordRotationRecord(
        newVerifierSalt: newVerifierSaltBase64,
        newVerifier: newVerifier,
        entries: rotatedSecrets,
      );
      final rollbackSnapshot = _PasswordRotationRollbackSnapshot(
        oldVerifierSalt: oldVerifierSalt,
        oldVerifier: oldVerifier,
        entries: rollbackSecrets,
      );
      await writePlain(_passwordRotationInProgressKey, rotation.serialize());

      try {
        await _writeRotatedPasswordState(rotation);
      } catch (error, stackTrace) {
        await _rollbackPasswordRotation(rollbackSnapshot, currentPassword);
        Error.throwWithStackTrace(error, stackTrace);
      }

      setSessionPassword(newPassword);
      await _deleteRotationRecordBestEffort();

      return true;
    });
  }

  /// Stable secure-storage key for one account's hotkey in one voting round.
  static String votingHotkeyStorageKey({
    required String accountUuid,
    required String roundId,
  }) {
    return '${_votingHotkeyAccountPrefix(accountUuid)}$roundId';
  }

  static String _votingHotkeyAccountPrefix(String accountUuid) {
    return '$_votingHotkeyKeyPrefix${accountUuid}_';
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

  Future<void> clearPasswordConfiguration() {
    return _secretMutationLock.run(() async {
      await _runStorageOperation(
        'delete password verifier salt',
        () => _storage.delete(key: _passwordVerifierSaltKey),
      );
      await _runStorageOperation(
        'delete password verifier',
        () => _storage.delete(key: _passwordVerifierKey),
      );
      await _runStorageOperation(
        'delete password rotation record',
        () => _storage.delete(key: _passwordRotationInProgressKey),
      );
      clearSessionPassword();
    });
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

    final derived = await _derivePasswordVerifier(password, encodedSalt);
    return derived == storedVerifier;
  }

  Future<bool> verifyPassword(String password) async {
    final isMatch = await verifyPasswordOnly(password);
    if (isMatch) {
      setSessionPassword(password);
      try {
        final migratedForRead = await migrateAccountMnemonicsAfterUnlock();
        if (!migratedForRead) {
          clearSessionPassword();
          return false;
        }
      } catch (error, stackTrace) {
        clearSessionPassword();
        debugPrint(
          'AppSecureStore: failed to migrate account mnemonics after unlock: '
          '$error\n$stackTrace',
        );
        return false;
      }
    }
    return isMatch;
  }

  Future<bool> migrateAccountMnemonicsAfterUnlock() {
    return _secretMutationLock.run(() async {
      final migration = await _migrateAccountMnemonicsAfterUnlockLocked();
      return migration.mnemonicsAvailable;
    });
  }

  void setSessionPassword(String password) {
    _sessionPassword = password;
  }

  void clearSessionPassword() {
    _sessionPassword = null;
  }

  Future<T> _runStorageOperation<T>(
    String operation,
    Future<T> Function() body,
  ) async {
    try {
      return await body();
    } on SecureStorageUnavailableException {
      rethrow;
    } on PlatformException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        SecureStorageUnavailableException(operation: operation, cause: error),
        stackTrace,
      );
    }
  }

  bool _shouldSkipLockedSecretRead(bool requireUnlockedSession) {
    return requireUnlockedSession && !hasSessionPassword;
  }

  Future<String?> _decryptStoredSecretString(
    String? raw, {
    required String key,
    required bool requireUnlockedSession,
  }) async {
    if (requireUnlockedSession && !hasSessionPassword) {
      return null;
    }
    if (!hasSessionPassword) {
      throw StateError('Secret storage requires an unlocked session.');
    }
    if (raw == null || raw.isEmpty) return null;

    if (!_isEncryptedPayload(raw)) {
      return null;
    }

    final saltBase64 = await _getOrCreateSaltBase64();
    return _decryptPayloadForKey(key, raw, _sessionPassword!, saltBase64);
  }

  Future<Uint8List?> _decryptStoredSecretBytes(
    String? raw, {
    required String key,
    required bool requireUnlockedSession,
  }) async {
    if (requireUnlockedSession && !hasSessionPassword) {
      return null;
    }
    if (!hasSessionPassword) {
      throw StateError('Secret storage requires an unlocked session.');
    }
    if (raw == null || raw.isEmpty) return null;

    if (!_isEncryptedPayload(raw)) {
      return null;
    }

    final saltBase64 = await _getOrCreateSaltBase64();
    return _decryptPayloadBytesForKey(key, raw, _sessionPassword!, saltBase64);
  }

  Future<String> _encryptSecretString(String value) async {
    final password = _sessionPassword;
    if (password == null) {
      throw StateError('Secret storage requires an unlocked session.');
    }
    final saltBase64 = await _getOrCreateSaltBase64();
    return _encryptStringWithPassword(value, password, saltBase64);
  }

  Future<String> _encryptStringWithPassword(
    String value,
    String password,
    String saltBase64,
  ) async {
    return _encryptBytesWithPassword(utf8.encode(value), password, saltBase64);
  }

  Future<String> _encryptBytesWithPassword(
    List<int> clearText,
    String password,
    String saltBase64,
  ) async {
    try {
      return await rust_secret.encryptSecretPayload(
        plainBytes: clearText,
        password: password,
        saltBase64: saltBase64,
      );
    } finally {
      _zeroizeList(clearText);
    }
  }

  Future<_AccountMnemonicMigrationResult>
  _migrateAccountMnemonicsAfterUnlockLocked() async {
    if (!_usesSeparateMacOsMnemonicStorage ||
        identical(_mnemonicStorage, _storage)) {
      return _AccountMnemonicMigrationResult.complete;
    }
    if (await readPlain(_accountMnemonicMigrationCompleteKey) == 'true') {
      return _AccountMnemonicMigrationResult.complete;
    }

    final legacyValues = await _runStorageOperation(
      'read legacy secure storage values',
      _storage.readAll,
    );
    var mnemonicsAvailable = true;
    var legacyCleanupComplete = true;
    for (final entry in legacyValues.entries) {
      if (!_isAccountMnemonicKey(entry.key)) continue;

      try {
        final existing = await _runStorageOperation(
          'read migrated account mnemonic "${entry.key}"',
          () => _mnemonicStorage.read(key: entry.key),
        );
        if (existing == null) {
          await _runStorageOperation(
            'write migrated account mnemonic "${entry.key}"',
            () => _mnemonicStorage.write(key: entry.key, value: entry.value),
          );
        }
      } catch (error, stackTrace) {
        mnemonicsAvailable = false;
        legacyCleanupComplete = false;
        debugPrint(
          'AppSecureStore: failed to copy account mnemonic "${entry.key}": '
          '$error\n$stackTrace',
        );
        continue;
      }

      try {
        await _runStorageOperation(
          'delete legacy account mnemonic "${entry.key}"',
          () => _storage.delete(key: entry.key),
        );
      } catch (error, stackTrace) {
        legacyCleanupComplete = false;
        debugPrint(
          'AppSecureStore: failed to delete legacy account mnemonic '
          '"${entry.key}": '
          '$error\n$stackTrace',
        );
      }
    }
    if (legacyCleanupComplete) {
      try {
        await writePlain(_accountMnemonicMigrationCompleteKey, 'true');
      } catch (error, stackTrace) {
        debugPrint(
          'AppSecureStore: failed to mark account mnemonic migration complete: '
          '$error\n$stackTrace',
        );
      }
    }
    return _AccountMnemonicMigrationResult(
      mnemonicsAvailable: mnemonicsAvailable,
      legacyCleanupComplete: legacyCleanupComplete,
    );
  }

  Future<void> _deleteLegacyAccountMnemonicBestEffort(String key) async {
    if (!_usesSeparateMacOsMnemonicStorage ||
        identical(_mnemonicStorage, _storage)) {
      return;
    }
    try {
      await _runStorageOperation(
        'delete legacy account mnemonic "$key"',
        () => _storage.delete(key: key),
      );
    } catch (error, stackTrace) {
      debugPrint(
        'AppSecureStore: failed to delete legacy account mnemonic "$key": '
        '$error\n$stackTrace',
      );
    }
  }

  Future<String> _decryptPayloadForKey(
    String key,
    String payloadJson,
    String password,
    String saltBase64,
  ) async {
    try {
      final clearText = await rust_secret.decryptSecretPayload(
        payloadJson: payloadJson,
        password: password,
        saltBase64: saltBase64,
      );
      try {
        return utf8.decode(clearText);
      } finally {
        _zeroizeList(clearText);
      }
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        StateError('Failed to decrypt secure-storage value for "$key": $error'),
        stackTrace,
      );
    }
  }

  Future<Uint8List> _decryptPayloadBytesForKey(
    String key,
    String payloadJson,
    String password,
    String saltBase64,
  ) async {
    try {
      return await rust_secret.decryptSecretPayload(
        payloadJson: payloadJson,
        password: password,
        saltBase64: saltBase64,
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        StateError('Failed to decrypt secure-storage value for "$key": $error'),
        stackTrace,
      );
    }
  }

  Future<String> _derivePasswordVerifier(String password, String saltBase64) {
    return rust_secret.deriveSecretPasswordVerifier(
      password: password,
      saltBase64: saltBase64,
    );
  }

  void _zeroizeList(List<int> value) {
    try {
      value.fillRange(0, value.length, 0);
    } catch (_) {
      // Best effort only: FFI/generated calls may return fixed or
      // unmodifiable list views.
    }
  }

  Future<void> _writeRotatedPasswordState(
    _PasswordRotationRecord rotation,
  ) async {
    for (final entry in rotation.entries) {
      await _runStorageOperation(
        'write rotated secret "${entry.key}"',
        () => _encryptedSecretStorageForKey(
          entry.key,
        ).write(key: entry.key, value: entry.rotatedValue),
      );
    }
    await writePlain(_passwordVerifierSaltKey, rotation.newVerifierSalt);
    await writePlain(_passwordVerifierKey, rotation.newVerifier);
  }

  Future<void> _rollbackPasswordRotation(
    _PasswordRotationRollbackSnapshot rollback,
    String currentPassword,
  ) async {
    try {
      for (final entry in rollback.entries) {
        await _runStorageOperation(
          'restore secret "${entry.key}"',
          () => _encryptedSecretStorageForKey(
            entry.key,
          ).write(key: entry.key, value: entry.originalValue),
        );
      }
      if (rollback.oldVerifierSalt == null) {
        await delete(_passwordVerifierSaltKey);
      } else {
        await writePlain(_passwordVerifierSaltKey, rollback.oldVerifierSalt!);
      }
      if (rollback.oldVerifier == null) {
        await delete(_passwordVerifierKey);
      } else {
        await writePlain(_passwordVerifierKey, rollback.oldVerifier!);
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

  FlutterSecureStorage _encryptedSecretStorageForKey(String key) {
    return key.startsWith(_accountMnemonicKeyPrefix)
        ? _mnemonicStorage
        : _storage;
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

  Future<String> _getOrCreateSaltBase64() async {
    final encoded = await readPlain(_secureStoreSaltKey);
    if (encoded != null && encoded.isNotEmpty) {
      return encoded;
    }

    final salt = _randomBytes(16);
    final generated = base64Encode(salt);
    await writePlain(_secureStoreSaltKey, generated);
    return generated;
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

bool get _usesSeparateMacOsMnemonicStorage =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

bool get _usesMacOsLocalTestProfile =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

bool _isAccountMnemonicKey(String key) =>
    key.startsWith(_accountMnemonicKeyPrefix);

String _accountMnemonicKey(String accountUuid) =>
    '$_accountMnemonicKeyPrefix$accountUuid';

String _mnemonicSecureStoreServiceForNetwork(String networkName) {
  return '${_macOsSecureStoreServiceForNetwork(networkName)}.mnemonic';
}

String _macOsSecureStoreServiceForNetwork(String networkName) {
  final service = secureStoreServiceForNetwork(networkName);
  if (!_usesMacOsLocalTestProfile) return service;
  return applyLocalTestProfileToServiceName(service);
}

class _AccountMnemonicMigrationResult {
  const _AccountMnemonicMigrationResult({
    required this.mnemonicsAvailable,
    required this.legacyCleanupComplete,
  });

  static const complete = _AccountMnemonicMigrationResult(
    mnemonicsAvailable: true,
    legacyCleanupComplete: true,
  );

  final bool mnemonicsAvailable;
  final bool legacyCleanupComplete;
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
  const _PasswordRotationEntry({required this.key, required this.rotatedValue});

  final String key;
  final String rotatedValue;
}

class _PasswordRotationRollbackEntry {
  const _PasswordRotationRollbackEntry({
    required this.key,
    required this.originalValue,
  });

  final String key;
  final String originalValue;
}

class _PasswordRotationRollbackSnapshot {
  const _PasswordRotationRollbackSnapshot({
    required this.oldVerifierSalt,
    required this.oldVerifier,
    required this.entries,
  });

  final String? oldVerifierSalt;
  final String? oldVerifier;
  final List<_PasswordRotationRollbackEntry> entries;
}

class _PasswordRotationRecord {
  const _PasswordRotationRecord({
    required this.newVerifierSalt,
    required this.newVerifier,
    required this.entries,
  });

  final String newVerifierSalt;
  final String newVerifier;
  final List<_PasswordRotationEntry> entries;

  String serialize() {
    return jsonEncode({
      'v': 1,
      'newVerifierSalt': newVerifierSalt,
      'newVerifier': newVerifier,
      'entries': entries
          .map(
            (entry) => {'key': entry.key, 'rotatedValue': entry.rotatedValue},
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
      final newVerifierSalt = json['newVerifierSalt'];
      final newVerifier = json['newVerifier'];
      if (newVerifierSalt is! String || newVerifier is! String) return null;

      return _PasswordRotationRecord(
        newVerifierSalt: newVerifierSalt,
        newVerifier: newVerifier,
        entries: entriesJson.map((entry) {
          final entryJson = entry as Map<String, dynamic>;
          return _PasswordRotationEntry(
            key: entryJson['key'] as String,
            rotatedValue: entryJson['rotatedValue'] as String,
          );
        }).toList(),
      );
    } catch (_) {
      return null;
    }
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

bool _isEncryptedPayload(String raw) {
  try {
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) return false;
    if (json['v'] != 1) return false;

    final nonce = json['n'];
    final cipherText = json['c'];
    final mac = json['m'];
    if (nonce is! String || cipherText is! String || mac is! String) {
      return false;
    }

    base64Decode(nonce);
    base64Decode(cipherText);
    base64Decode(mac);
    return true;
  } catch (_) {
    return false;
  }
}
