import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _accountsKey = 'zcash_accounts';
const _dbName = 'zcash_wallet_0123456789abcdef01234567.db';
const _account = AccountInfo(
  uuid: '550e8400-e29b-41d4-a716-446655440000',
  name: 'Account "one"',
  order: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => RustLib.initMock(api: _BootstrapRustApi()));
  tearDownAll(RustLib.dispose);

  late AppSecureStore storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Values written by a build without the Linux keyring codec.
    FlutterSecureStorage.setMockInitialValues({
      kWalletDbNameKey: _dbName,
      _accountsKey: jsonEncode([_account.toJson()]),
      'zcash_password_verifier': 'password-verifier',
      'zcash_password_verifier_salt': 'password-salt',
    });
    AppSecureStore.instance.clearSessionPassword();
    storage = AppSecureStore.testing(
      storage: const FlutterSecureStorage(),
      encodeLinuxKeyringValues: true,
    );
    final support = await Directory.systemTemp.createTemp(
      'vizor-linux-keyring-bootstrap-',
    );
    addTearDown(() => support.delete(recursive: true));
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => support.path);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null),
    );
  });

  test('startup re-encodes legacy Linux keyring values', () async {
    final result = await loadAppBootstrap(secureStore: storage);

    expect(result.hasBlockingFailure, isFalse);
    expect(result.initialLocation, '/unlock');
    expect(result.initialAccountState.accounts.single.uuid, _account.uuid);
    expect(result.initialAccountState.accounts.single.name, _account.name);
    final raw = await const FlutterSecureStorage().readAll();
    expect(jsonEncode(raw), isNot(contains(r'\')));
    expect(raw[kWalletDbNameKey], _dbName);
  });
}

class _BootstrapRustApi implements RustLibApi {
  @override
  bool crateApiWalletWalletExists({required String dbPath}) =>
      File(dbPath).existsSync();

  @override
  Future<List<rust_wallet.AccountInfo>> crateApiWalletListAccounts({
    required String dbPath,
    required String network,
  }) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
