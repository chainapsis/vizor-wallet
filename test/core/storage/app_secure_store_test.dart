import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/security/password_policy.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';

const _oldPassword = 'Oldpass1!';
const _newPassword = 'Newpass1!';
const _wrongPassword = 'Wrongpass1!';
const _accountUuid = 'test-account';
const _mnemonicKey = 'zcash_account_mnemonic_test-account';
const _externalEncryptedKey = 'external_encrypted_key';
const _mnemonic = 'abandon abandon abandon abandon abandon abandon';

const _passwordVerifierKey = 'zcash_password_verifier';
const _passwordVerifierSaltKey = 'zcash_password_verifier_salt';
const _rotationInProgressKey = 'zcash_rotation_in_progress';
const _migrationCompleteKey = 'zcash_mnemonic_storage_migrated_v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppSecureStore store;
  TargetPlatform? previousTargetPlatform;

  setUp(() async {
    previousTargetPlatform = debugDefaultTargetPlatformOverride;
    FlutterSecureStorage.setMockInitialValues({});
    store = AppSecureStore.testing(storage: const FlutterSecureStorage());
    await store.deleteAll();
  });

  tearDown(() async {
    await store.deleteAll();
    debugDefaultTargetPlatformOverride = previousTargetPlatform;
  });

  test('changePassword rotates mnemonic payloads and verifier', () async {
    await store.configurePassword(_oldPassword);
    await store.writeAccountMnemonic(_accountUuid, _mnemonic);

    final didChange = await store.changePassword(
      currentPassword: _oldPassword,
      newPassword: _newPassword,
    );

    expect(didChange, isTrue);

    store.clearSessionPassword();
    expect(await store.verifyPasswordOnly(_oldPassword), isFalse);
    expect(await store.verifyPassword(_newPassword), isTrue);
    expect(await store.readAccountMnemonic(_accountUuid), _mnemonic);
  });

  test('changePassword journal stores only roll-forward data', () async {
    final blockingStorage = _BlockingDeleteStorage(
      blockKey: _rotationInProgressKey,
    );
    store = AppSecureStore.testing(storage: blockingStorage);
    await store.configurePassword(_oldPassword);
    await store.writeAccountMnemonic(_accountUuid, _mnemonic);
    final originalPayload = await store.readPlain(_mnemonicKey);
    final oldVerifier = await store.readPlain(_passwordVerifierKey);

    blockingStorage.blockNextDelete = true;
    final rotation = store.changePassword(
      currentPassword: _oldPassword,
      newPassword: _newPassword,
    );
    await blockingStorage.deleteStarted.future;

    final journal = await store.readPlain(_rotationInProgressKey);
    expect(journal, isNotNull);
    expect(journal, contains('"v":1'));
    expect(journal, contains('rotatedValue'));
    expect(journal, isNot(contains('originalValue')));
    expect(journal, isNot(contains('oldVerifier')));
    expect(journal, isNot(contains(originalPayload!)));
    expect(journal, isNot(contains(oldVerifier!)));

    blockingStorage.release();
    expect(await rotation, isTrue);
    expect(await store.readPlain(_rotationInProgressKey), isNull);
  });

  test(
    'changePassword keeps old cleanup policy with forward-only journal',
    () async {
      final failingStorage = _FailingDeleteStorage(
        failKey: _rotationInProgressKey,
      );
      store = AppSecureStore.testing(storage: failingStorage);
      await store.configurePassword(_oldPassword);
      await store.writeSecretString(_mnemonicKey, _mnemonic);
      final originalPayload = await store.readPlain(_mnemonicKey);
      final oldVerifier = await store.readPlain(_passwordVerifierKey);

      failingStorage.failNextMatchingDelete = true;

      final didChange = await store.changePassword(
        currentPassword: _oldPassword,
        newPassword: _newPassword,
      );

      expect(didChange, isTrue);

      final retainedJournal = await store.readPlain(_rotationInProgressKey);
      expect(retainedJournal, isNotNull);
      expect(retainedJournal, contains('rotatedValue'));
      expect(retainedJournal, isNot(contains('originalValue')));
      expect(retainedJournal, isNot(contains('oldVerifier')));
      expect(retainedJournal, isNot(contains(originalPayload!)));
      expect(retainedJournal, isNot(contains(oldVerifier!)));

      store.clearSessionPassword();
      expect(await store.verifyPasswordOnly(_oldPassword), isFalse);
      expect(await store.verifyPassword(_newPassword), isTrue);
      expect(await store.readAccountMnemonic(_accountUuid), _mnemonic);
    },
  );

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
      expect(await store.readAccountMnemonic(_accountUuid), _mnemonic);
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
    await store.writeAccountMnemonic(_accountUuid, _mnemonic);
    await store.writeSecretString(_externalEncryptedKey, 'external secret');
    final externalPayload = await store.readPlain(_externalEncryptedKey);

    final didChange = await store.changePassword(
      currentPassword: _oldPassword,
      newPassword: _newPassword,
    );

    expect(didChange, isTrue);
    expect(await store.readPlain(_externalEncryptedKey), externalPayload);
    expect(await store.readAccountMnemonic(_accountUuid), _mnemonic);
  });

  test('changePassword rejects unreadable mnemonic payloads', () async {
    await store.configurePassword(_oldPassword);
    await store.writeString(_mnemonicKey, 'not encrypted json');

    await expectLater(
      () => store.changePassword(
        currentPassword: _oldPassword,
        newPassword: _newPassword,
      ),
      throwsA(isA<StateError>()),
    );

    expect(await store.readPlain(_rotationInProgressKey), isNull);
    expect(await store.verifyPasswordOnly(_newPassword), isFalse);
    expect(await store.verifyPassword(_oldPassword), isTrue);
    expect(await store.readPlain(_mnemonicKey), 'not encrypted json');
  });

  test('changePassword rolls back if the verifier write fails', () async {
    final failingStorage = _FailingWriteStorage(failKey: _passwordVerifierKey);
    store = AppSecureStore.testing(storage: failingStorage);
    await store.configurePassword(_oldPassword);
    await store.writeAccountMnemonic(_accountUuid, _mnemonic);
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
    expect(await store.readAccountMnemonic(_accountUuid), _mnemonic);
  });

  test(
    'recoverInterruptedPasswordRotation rolls forward from journal',
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
          'newVerifierSalt': newVerifierSalt,
          'newVerifier': newVerifier,
          'entries': [
            {'key': _mnemonicKey, 'rotatedValue': rotatedPayload},
          ],
        }),
      );
      store.clearSessionPassword();

      await store.recoverInterruptedPasswordRotation();

      expect(await store.readPlain(_rotationInProgressKey), isNull);
      expect(await store.verifyPasswordOnly(_oldPassword), isFalse);
      expect(await store.verifyPassword(_newPassword), isTrue);
      expect(await store.readAccountMnemonic(_accountUuid), _mnemonic);
    },
  );

  test('changePassword waits for concurrent mnemonic writes', () async {
    const lateAccountUuid = 'late-account';
    const lateMnemonicKey = 'zcash_account_mnemonic_late-account';
    const lateMnemonic = 'legal winner thank year wave sausage worth useful';
    final blockingStorage = _BlockingWriteStorage(blockKey: lateMnemonicKey);
    store = AppSecureStore.testing(storage: blockingStorage);
    await store.configurePassword(_oldPassword);
    await store.writeAccountMnemonic(_accountUuid, _mnemonic);

    blockingStorage.blockNextWrite = true;
    final lateWrite = store.writeAccountMnemonic(lateAccountUuid, lateMnemonic);
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
    expect(await store.readAccountMnemonic(lateAccountUuid), lateMnemonic);
  });

  test(
    'rollback sentinel write failure does not roll forward on recovery',
    () async {
      final failingStorage = _CountingFailingWriteStorage();
      store = AppSecureStore.testing(storage: failingStorage);
      await store.configurePassword(_oldPassword);
      await store.writeSecretString(_mnemonicKey, _mnemonic);
      failingStorage
        ..failWriteNumberFor(_passwordVerifierKey, 2)
        ..failWriteNumberFor(_passwordVerifierKey, 3);

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
      await store.writeAccountMnemonic(_accountUuid, _mnemonic);

      blockingStorage.blockNextWrite = true;
      final rotation = store.changePassword(
        currentPassword: _oldPassword,
        newPassword: _newPassword,
      );
      await blockingStorage.writeStarted.future;

      final delete = store.deleteAccountMnemonic(_accountUuid);
      blockingStorage.release();
      await rotation;
      await delete;

      store.clearSessionPassword();
      expect(await store.verifyPassword(_newPassword), isTrue);
      expect(await store.readAccountMnemonic(_accountUuid), isNull);
    },
  );

  test('account mnemonic writes use mnemonic storage only', () async {
    final regularStorage = _MapStorage('regular');
    final mnemonicStorage = _MapStorage('mnemonic');
    store = AppSecureStore.testing(
      storage: regularStorage,
      mnemonicStorage: mnemonicStorage,
    );

    await store.configurePassword(_oldPassword);
    await store.writeAccountMnemonic(_accountUuid, _mnemonic);

    expect(regularStorage.valueFor(_mnemonicKey), isNull);
    expect(mnemonicStorage.valueFor(_mnemonicKey), isNotNull);
    expect(await store.readAccountMnemonic(_accountUuid), _mnemonic);
  });

  test(
    'macOS unlock migrates legacy mnemonic payloads write then delete',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final operations = <String>[];
      final regularStorage = _MapStorage('regular', operations: operations);
      final mnemonicStorage = _MapStorage('mnemonic', operations: operations);
      store = AppSecureStore.testing(
        storage: regularStorage,
        mnemonicStorage: mnemonicStorage,
      );

      await store.configurePassword(_oldPassword);
      await store.writeSecretString(_mnemonicKey, _mnemonic);
      store.clearSessionPassword();
      operations.clear();

      expect(await store.verifyPassword(_oldPassword), isTrue);

      expect(regularStorage.valueFor(_mnemonicKey), isNull);
      expect(mnemonicStorage.valueFor(_mnemonicKey), isNotNull);
      expect(await store.readAccountMnemonic(_accountUuid), _mnemonic);
      expect(
        operations,
        containsAllInOrder([
          'mnemonic.write $_mnemonicKey',
          'regular.delete $_mnemonicKey',
        ]),
      );
    },
  );

  test('macOS mnemonic migration flag skips repeated legacy scans', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final operations = <String>[];
    final regularStorage = _MapStorage('regular', operations: operations);
    final mnemonicStorage = _MapStorage('mnemonic', operations: operations);
    store = AppSecureStore.testing(
      storage: regularStorage,
      mnemonicStorage: mnemonicStorage,
    );

    await store.configurePassword(_oldPassword);
    await store.writeSecretString(_mnemonicKey, _mnemonic);
    store.clearSessionPassword();

    expect(await store.verifyPassword(_oldPassword), isTrue);
    expect(regularStorage.valueFor(_migrationCompleteKey), 'true');
    expect(operations, contains('regular.readAll'));

    operations.clear();
    store.clearSessionPassword();

    expect(await store.verifyPassword(_oldPassword), isTrue);
    expect(operations, isNot(contains('regular.readAll')));
  });

  test('macOS unlock fails if mnemonic copy migration fails', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final regularStorage = _MapStorage('regular');
    final mnemonicStorage = _FailingMapStorage('mnemonic');
    store = AppSecureStore.testing(
      storage: regularStorage,
      mnemonicStorage: mnemonicStorage,
    );

    await store.configurePassword(_oldPassword);
    await store.writeSecretString(_mnemonicKey, _mnemonic);
    store.clearSessionPassword();
    mnemonicStorage.failNextWriteFor(_mnemonicKey);

    expect(await store.verifyPassword(_oldPassword), isFalse);
    expect(store.hasSessionPassword, isFalse);
    expect(regularStorage.valueFor(_mnemonicKey), isNotNull);
    expect(mnemonicStorage.valueFor(_mnemonicKey), isNull);
    expect(regularStorage.valueFor(_migrationCompleteKey), isNull);
  });

  test(
    'macOS unlock allows legacy cleanup retry after delete failure',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final regularStorage = _FailingMapStorage('regular');
      final mnemonicStorage = _MapStorage('mnemonic');
      store = AppSecureStore.testing(
        storage: regularStorage,
        mnemonicStorage: mnemonicStorage,
      );

      await store.configurePassword(_oldPassword);
      await store.writeSecretString(_mnemonicKey, _mnemonic);
      store.clearSessionPassword();
      regularStorage.failNextDeleteFor(_mnemonicKey);

      expect(await store.verifyPassword(_oldPassword), isTrue);
      expect(await store.readAccountMnemonic(_accountUuid), _mnemonic);
      expect(regularStorage.valueFor(_mnemonicKey), isNotNull);
      expect(regularStorage.valueFor(_migrationCompleteKey), isNull);
    },
  );

  test(
    'macOS mnemonic reads do not fallback before unlock migration',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final regularStorage = _MapStorage('regular');
      final mnemonicStorage = _MapStorage('mnemonic');
      store = AppSecureStore.testing(
        storage: regularStorage,
        mnemonicStorage: mnemonicStorage,
      );

      await store.configurePassword(_oldPassword);
      await store.writeSecretString(_mnemonicKey, _mnemonic);

      expect(await store.readAccountMnemonic(_accountUuid), isNull);
    },
  );

  test('deleteAll waits for concurrent mnemonic writes', () async {
    const lateMnemonicKey = 'zcash_account_mnemonic_delete-all-account';
    const lateMnemonic = 'legal winner thank year wave sausage worth useful';
    final blockingStorage = _BlockingWriteStorage(blockKey: lateMnemonicKey);
    store = AppSecureStore.testing(storage: blockingStorage);
    await store.configurePassword(_oldPassword);

    blockingStorage.blockNextWrite = true;
    final lateWrite = store.writeSecretString(lateMnemonicKey, lateMnemonic);
    await blockingStorage.writeStarted.future;

    var deleteAllCompleted = false;
    final deleteAll = store.deleteAll().then((_) {
      deleteAllCompleted = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(deleteAllCompleted, isFalse);

    blockingStorage.release();
    await lateWrite;
    await deleteAll;

    expect(await store.readPlain(lateMnemonicKey), isNull);
    expect(store.hasSessionPassword, isFalse);
  });

  test(
    'clearPasswordConfiguration waits for concurrent mnemonic writes',
    () async {
      const lateMnemonicKey = 'zcash_account_mnemonic_clear-password-account';
      const lateMnemonic = 'legal winner thank year wave sausage worth useful';
      final blockingStorage = _BlockingWriteStorage(blockKey: lateMnemonicKey);
      store = AppSecureStore.testing(storage: blockingStorage);
      await store.configurePassword(_oldPassword);

      blockingStorage.blockNextWrite = true;
      final lateWrite = store.writeSecretString(lateMnemonicKey, lateMnemonic);
      await blockingStorage.writeStarted.future;

      var clearCompleted = false;
      final clear = store.clearPasswordConfiguration().then((_) {
        clearCompleted = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(clearCompleted, isFalse);

      blockingStorage.release();
      await lateWrite;
      await clear;

      expect(await store.readPlain(lateMnemonicKey), isNotNull);
      expect(store.hasSessionPassword, isFalse);
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

class _MapStorage extends FlutterSecureStorage {
  _MapStorage(this.name, {List<String>? operations})
    : operations = operations ?? <String>[];

  final String name;
  final List<String> operations;
  final _values = <String, String>{};

  String? valueFor(String key) => _values[key];

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    operations.add('$name.read $key');
    return _values[key];
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
    operations.add('$name.write $key');
    if (value == null) {
      _values.remove(key);
      return;
    }
    _values[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    operations.add('$name.delete $key');
    _values.remove(key);
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
    operations.add('$name.readAll');
    return Map<String, String>.from(_values);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    operations.add('$name.deleteAll');
    _values.clear();
  }
}

class _FailingMapStorage extends _MapStorage {
  _FailingMapStorage(super.name);

  final _failNextWrite = <String>{};
  final _failNextDelete = <String>{};

  void failNextWriteFor(String key) {
    _failNextWrite.add(key);
  }

  void failNextDeleteFor(String key) {
    _failNextDelete.add(key);
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
    if (_failNextWrite.remove(key)) {
      throw StateError('forced map write failure for $key');
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

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    if (_failNextDelete.remove(key)) {
      throw StateError('forced map delete failure for $key');
    }
    return super.delete(
      key: key,
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

class _BlockingDeleteStorage extends FlutterSecureStorage {
  _BlockingDeleteStorage({required this.blockKey});

  final String blockKey;
  var blockNextDelete = false;
  Completer<void> deleteStarted = Completer<void>();
  final Completer<void> _release = Completer<void>();

  void release() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (blockNextDelete && key == blockKey) {
      blockNextDelete = false;
      if (!deleteStarted.isCompleted) {
        deleteStarted.complete();
      }
      await _release.future;
    }
    return super.delete(
      key: key,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }
}

class _FailingDeleteStorage extends FlutterSecureStorage {
  _FailingDeleteStorage({required this.failKey});

  final String failKey;
  bool failNextMatchingDelete = false;

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    if (failNextMatchingDelete && key == failKey) {
      failNextMatchingDelete = false;
      throw StateError('forced delete failure');
    }
    return super.delete(
      key: key,
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
