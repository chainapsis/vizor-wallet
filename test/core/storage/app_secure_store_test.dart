import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/security/password_policy.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';

const _oldPassword = 'Oldpass1!';
const _newPassword = 'Newpass1!';
const _wrongPassword = 'Wrongpass1!';
const _mnemonicKey = 'zcash_account_mnemonic_test-account';
const _externalEncryptedKey = 'external_encrypted_key';
const _mnemonic = 'abandon abandon abandon abandon abandon abandon';

const _passwordVerifierKey = 'zcash_password_verifier';
const _passwordVerifierSaltKey = 'zcash_password_verifier_salt';
const _rotationInProgressKey = 'zcash_rotation_in_progress';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppSecureStore store;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    store = AppSecureStore.instance;
    await store.deleteAll();
  });

  tearDown(() async {
    await store.deleteAll();
  });

  test('changePassword rotates mnemonic payloads and verifier', () async {
    await store.configurePassword(_oldPassword);
    await store.writeSecretString(_mnemonicKey, _mnemonic);

    final didChange = await store.changePassword(
      currentPassword: _oldPassword,
      newPassword: _newPassword,
    );

    expect(didChange, isTrue);

    store.clearSessionPassword();
    expect(await store.verifyPasswordOnly(_oldPassword), isFalse);
    expect(await store.verifyPassword(_newPassword), isTrue);
    expect(await store.readSecretStringWithOptions(_mnemonicKey), _mnemonic);
  });

  test(
    'changePassword rejects wrong current password without rotating',
    () async {
      await store.configurePassword(_oldPassword);
      await store.writeSecretString(_mnemonicKey, _mnemonic);
      final originalPayload = await store.readPlain(_mnemonicKey);

      final didChange = await store.changePassword(
        currentPassword: _wrongPassword,
        newPassword: _newPassword,
      );

      expect(didChange, isFalse);
      expect(await store.readPlain(_rotationInProgressKey), isNull);
      expect(await store.readPlain(_mnemonicKey), originalPayload);
      expect(await store.verifyPassword(_oldPassword), isTrue);
      expect(await store.readSecretStringWithOptions(_mnemonicKey), _mnemonic);
    },
  );

  test('changePassword rejects invalid or unchanged new passwords', () async {
    await store.configurePassword(_oldPassword);

    expect(
      () =>
          store.changePassword(currentPassword: _oldPassword, newPassword: ''),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => store.changePassword(
        currentPassword: _oldPassword,
        newPassword: _oldPassword,
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(validateRequiredWalletPassword(''), kWalletPasswordMinLengthMessage);
  });

  test('changePassword only rotates app-managed mnemonic payloads', () async {
    await store.configurePassword(_oldPassword);
    await store.writeSecretString(_mnemonicKey, _mnemonic);
    await store.writeSecretString(_externalEncryptedKey, 'external secret');
    final externalPayload = await store.readPlain(_externalEncryptedKey);

    final didChange = await store.changePassword(
      currentPassword: _oldPassword,
      newPassword: _newPassword,
    );

    expect(didChange, isTrue);
    expect(await store.readPlain(_externalEncryptedKey), externalPayload);
    expect(await store.readSecretStringWithOptions(_mnemonicKey), _mnemonic);
  });

  test('changePassword rolls back if the verifier write fails', () async {
    final failingStorage = _FailingWriteStorage(failKey: _passwordVerifierKey);
    store = AppSecureStore.testing(storage: failingStorage);
    await store.configurePassword(_oldPassword);
    await store.writeSecretString(_mnemonicKey, _mnemonic);
    final originalPayload = await store.readPlain(_mnemonicKey);

    failingStorage.failNextMatchingWrite = true;

    await expectLater(
      () => store.changePassword(
        currentPassword: _oldPassword,
        newPassword: _newPassword,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'forced write failure',
        ),
      ),
    );

    expect(await store.readPlain(_rotationInProgressKey), isNull);
    expect(await store.readPlain(_mnemonicKey), originalPayload);
    expect(await store.verifyPasswordOnly(_newPassword), isFalse);
    expect(await store.verifyPassword(_oldPassword), isTrue);
    expect(await store.readSecretStringWithOptions(_mnemonicKey), _mnemonic);
  });

  test(
    'recoverInterruptedPasswordRotation rolls forward from sentinel',
    () async {
      await store.configurePassword(_oldPassword);
      await store.writeSecretString(_mnemonicKey, _mnemonic);

      final oldVerifierSalt = await store.readPlain(_passwordVerifierSaltKey);
      final oldVerifier = await store.readPlain(_passwordVerifierKey);
      final originalPayload = await store.readPlain(_mnemonicKey);

      await store.changePassword(
        currentPassword: _oldPassword,
        newPassword: _newPassword,
      );
      final rotatedPayload = await store.readPlain(_mnemonicKey);
      final newVerifierSalt = await store.readPlain(_passwordVerifierSaltKey);
      final newVerifier = await store.readPlain(_passwordVerifierKey);

      await store.writePlain(_mnemonicKey, originalPayload!);
      await store.writePlain(_passwordVerifierSaltKey, oldVerifierSalt!);
      await store.writePlain(_passwordVerifierKey, oldVerifier!);
      await store.writePlain(
        _rotationInProgressKey,
        jsonEncode({
          'v': 1,
          'oldVerifierSalt': oldVerifierSalt,
          'oldVerifier': oldVerifier,
          'newVerifierSalt': newVerifierSalt,
          'newVerifier': newVerifier,
          'entries': [
            {
              'key': _mnemonicKey,
              'originalValue': originalPayload,
              'rotatedValue': rotatedPayload,
            },
          ],
        }),
      );
      store.clearSessionPassword();

      await store.recoverInterruptedPasswordRotation();

      expect(await store.readPlain(_rotationInProgressKey), isNull);
      expect(await store.verifyPasswordOnly(_oldPassword), isFalse);
      expect(await store.verifyPassword(_newPassword), isTrue);
      expect(await store.readSecretStringWithOptions(_mnemonicKey), _mnemonic);
    },
  );

  test('changePassword waits for concurrent mnemonic writes', () async {
    const lateMnemonicKey = 'zcash_account_mnemonic_late-account';
    const lateMnemonic = 'legal winner thank year wave sausage worth useful';
    final blockingStorage = _BlockingWriteStorage(blockKey: lateMnemonicKey);
    store = AppSecureStore.testing(storage: blockingStorage);
    await store.configurePassword(_oldPassword);
    await store.writeSecretString(_mnemonicKey, _mnemonic);

    blockingStorage.blockNextWrite = true;
    final lateWrite = store.writeSecretString(lateMnemonicKey, lateMnemonic);
    await blockingStorage.writeStarted.future;

    final rotation = store.changePassword(
      currentPassword: _oldPassword,
      newPassword: _newPassword,
    );
    final rotationReachedSnapshot = await Future.any([
      blockingStorage.readAllFinished.future.then((_) => true),
      Future<void>.delayed(const Duration(seconds: 6)).then((_) => false),
    ]);

    if (rotationReachedSnapshot) {
      await rotation;
    }
    blockingStorage.release();
    await lateWrite;
    if (!rotationReachedSnapshot) {
      await rotation;
    }

    store.clearSessionPassword();
    expect(await store.verifyPassword(_newPassword), isTrue);
    expect(
      await store.readSecretStringWithOptions(lateMnemonicKey),
      lateMnemonic,
    );
  });

  test(
    'rollback sentinel write failure does not roll forward on recovery',
    () async {
      final failingStorage = _CountingFailingWriteStorage();
      store = AppSecureStore.testing(storage: failingStorage);
      await store.configurePassword(_oldPassword);
      await store.writeSecretString(_mnemonicKey, _mnemonic);
      failingStorage
        ..failNextWriteFor(_passwordVerifierKey)
        ..failWriteNumberFor(_rotationInProgressKey, 2);

      await expectLater(
        () => store.changePassword(
          currentPassword: _oldPassword,
          newPassword: _newPassword,
        ),
        throwsA(isA<StateError>()),
      );

      final recoveryRecord = await store.readPlain(_rotationInProgressKey);
      expect(recoveryRecord, contains('rollbackFailed'));
      await expectLater(
        () => store.recoverInterruptedPasswordRotation(),
        throwsA(isA<PasswordRotationRecoveryFailedException>()),
      );
      await expectLater(
        () => store.changePassword(
          currentPassword: _oldPassword,
          newPassword: _newPassword,
        ),
        throwsA(isA<PasswordRotationRecoveryFailedException>()),
      );
    },
  );

  test(
    'delete waits for password rotation before deleting mnemonics',
    () async {
      final blockingStorage = _BlockingWriteStorage(
        blockKey: _rotationInProgressKey,
      );
      store = AppSecureStore.testing(storage: blockingStorage);
      await store.configurePassword(_oldPassword);
      await store.writeSecretString(_mnemonicKey, _mnemonic);

      blockingStorage.blockNextWrite = true;
      final rotation = store.changePassword(
        currentPassword: _oldPassword,
        newPassword: _newPassword,
      );
      await blockingStorage.writeStarted.future;

      final delete = store.delete(_mnemonicKey);
      blockingStorage.release();
      await rotation;
      await delete;

      store.clearSessionPassword();
      expect(await store.verifyPassword(_newPassword), isTrue);
      expect(await store.readPlain(_mnemonicKey), isNull);
    },
  );
}

class _FailingWriteStorage extends FlutterSecureStorage {
  _FailingWriteStorage({required this.failKey});

  final String failKey;
  bool failNextMatchingWrite = false;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    if (failNextMatchingWrite && key == failKey) {
      failNextMatchingWrite = false;
      throw StateError('forced write failure');
    }
    return super.write(
      key: key,
      value: value,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }
}

class _BlockingWriteStorage extends FlutterSecureStorage {
  _BlockingWriteStorage({required this.blockKey});

  final String blockKey;
  var blockNextWrite = false;
  Completer<void> writeStarted = Completer<void>();
  Completer<void> readAllFinished = Completer<void>();
  final Completer<void> _release = Completer<void>();

  void release() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final values = await super.readAll(
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
    if (!readAllFinished.isCompleted) {
      readAllFinished.complete();
    }
    return values;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (blockNextWrite && key == blockKey) {
      blockNextWrite = false;
      if (!writeStarted.isCompleted) {
        writeStarted.complete();
      }
      await _release.future;
    }
    return super.write(
      key: key,
      value: value,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }
}

class _CountingFailingWriteStorage extends FlutterSecureStorage {
  final _writeCounts = <String, int>{};
  final _failNext = <String>{};
  final _failWriteNumbers = <String, Set<int>>{};

  void failNextWriteFor(String key) {
    _failNext.add(key);
  }

  void failWriteNumberFor(String key, int writeNumber) {
    _failWriteNumbers.putIfAbsent(key, () => <int>{}).add(writeNumber);
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    final count = (_writeCounts[key] ?? 0) + 1;
    _writeCounts[key] = count;
    if (_failNext.remove(key) ||
        (_failWriteNumbers[key]?.remove(count) ?? false)) {
      throw StateError('forced write failure for $key');
    }
    return super.write(
      key: key,
      value: value,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }
}
