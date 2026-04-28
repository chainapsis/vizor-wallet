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
