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

const _verifierKey = 'zcash_password_verifier';
const _verifierSaltKey = 'zcash_password_verifier_salt';
const _journal = 'encrypted-gift-setup-journal';
const _dbName = 'gift-bootstrap-test.db';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final rust = _BootstrapRustApi();
  setUpAll(() => RustLib.initMock(api: rust));
  tearDownAll(RustLib.dispose);

  late Directory support;
  late File database;
  late _FailingStorage backend;
  late AppSecureStore storage;

  setUp(() async {
    rust.reset();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      kWalletDbNameKey: _dbName,
      _verifierKey: 'password-verifier',
      _verifierSaltKey: 'password-salt',
      kPendingAccountMnemonicStorageKey: _journal,
      kGiftWalletSetupStartedStorageKey: 'true',
      kThemeModeKey: 'dark',
    });
    AppSecureStore.instance.clearSessionPassword();
    backend = _FailingStorage();
    storage = AppSecureStore.testing(storage: backend);
    support = await Directory.systemTemp.createTemp('vizor-gift-bootstrap-');
    database = File('${support.path}/$_dbName');
    addTearDown(() => support.delete(recursive: true));
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => support.path);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null),
    );
  });

  Future<AppBootstrapState> bootstrap() =>
      loadAppBootstrap(secureStore: storage);

  Future<void> expectPreserved() async {
    expect(
      await storage.readPlain(kPendingAccountMnemonicStorageKey),
      _journal,
    );
    expect(await storage.readPlain(_verifierKey), 'password-verifier');
    expect(await storage.readPlain(_verifierSaltKey), 'password-salt');
    expect(await storage.readPlain(kGiftWalletSetupStartedStorageKey), 'true');
  }

  Future<void> expectCleared(AppBootstrapState result) async {
    expect(result.hasBlockingFailure, isFalse);
    expect(result.initialLocation, '/welcome');
    expect(result.hasWallet, isFalse);
    expect(result.isPasswordConfigured, isFalse);
    expect(result.isUnlocked, isFalse);
    expect(await storage.readPlain(kPendingAccountMnemonicStorageKey), isNull);
    expect(await storage.readPlain(_verifierKey), isNull);
    expect(await storage.readPlain(_verifierSaltKey), isNull);
    expect(await storage.readPlain(kGiftWalletSetupStartedStorageKey), isNull);
    expect(await storage.readPlain(kThemeModeKey), 'dark');
  }

  test('restart before DB creation clears only the incomplete setup', () async {
    await expectCleared(await bootstrap());
    expect(rust.listCalls, 0);
    // The next launch stays eligible for normal passcode setup.
    await expectCleared(await bootstrap());
  });

  test('a successfully inspected empty DB also allows cleanup', () async {
    await database.writeAsString('empty wallet DB');
    await expectCleared(await bootstrap());
    expect(rust.listCalls, 1);
    expect(await database.readAsString(), 'empty wallet DB');
  });

  test('a created DB account keeps the journal and routes to unlock', () async {
    await database.writeAsString('created wallet DB');
    rust.accounts = [
      rust_wallet.AccountInfo(
        uuid: 'created-account',
        name: 'Gift account',
        unifiedAddress: 'u1created-account',
        birthdayHeight: 3000000,
        zip32AccountIndex: 0,
        isHardware: false,
        isSeedAnchor: true,
      ),
    ];

    final result = await bootstrap();
    expect(result.hasBlockingFailure, isFalse);
    expect(result.initialLocation, '/unlock');
    expect(result.initialAccountState.activeAccountUuid, 'created-account');
    expect(result.initialAccountState.activeAddress, isNull);
    expect(result.isPasswordConfigured, isTrue);
    await expectPreserved();
  });

  test('saved account metadata prevents cleanup even without a DB', () async {
    await storage.writeString(
      'zcash_accounts',
      jsonEncode([
        const AccountInfo(
          uuid: 'saved-account',
          name: 'Saved',
          order: 0,
        ).toJson(),
      ]),
    );
    final result = await bootstrap();
    expect(result.initialLocation, '/unlock');
    await expectPreserved();
  });

  test(
    'DB inspection failure blocks startup without removing secrets',
    () async {
      await database.writeAsString('unreadable wallet DB');
      rust.listError = StateError('database read failed');
      final result = await bootstrap();
      expect(result.hasBlockingFailure, isTrue);
      expect(result.initialLocation, '/storage-unavailable');
      await expectPreserved();
    },
  );

  test('a false existence check cannot discard a present DB', () async {
    await database.writeAsString('wallet DB');
    rust.reportMissingDb = true;
    final result = await bootstrap();
    expect(result.hasBlockingFailure, isTrue);
    await expectPreserved();
    expect(await database.readAsString(), 'wallet DB');
  });

  test('malformed saved accounts are not proof of an empty wallet', () async {
    await storage.writeString('zcash_accounts', 'invalid account JSON');
    expect((await bootstrap()).hasBlockingFailure, isTrue);
    await expectPreserved();
  });

  test('credentials without Gift setup records are left unchanged', () async {
    await storage.delete(kPendingAccountMnemonicStorageKey);
    await storage.delete(kGiftWalletSetupStartedStorageKey);
    final result = await bootstrap();
    expect(result.initialLocation, '/welcome');
    expect(result.isPasswordConfigured, isTrue);
    expect(await storage.readPlain(_verifierKey), 'password-verifier');
    expect(await storage.readPlain(_verifierSaltKey), 'password-salt');
  });

  Future<void> seedImportHandoff() async {
    await storage.delete(kPendingAccountMnemonicStorageKey);
    await storage.delete(kGiftWalletSetupStartedStorageKey);
    await storage.writePlain(kGiftClaimImportHandoffStorageKey, _journal);
  }

  for (final emptyDatabaseExists in [false, true]) {
    test(
      'import interrupted before account creation resets passcode with DB=$emptyDatabaseExists',
      () async {
        await seedImportHandoff();
        if (emptyDatabaseExists) {
          await database.writeAsString('empty wallet DB');
        }

        await expectCleared(await bootstrap());
        // The unclaimed bearer still belongs to import recovery. Repeated
        // launches remain eligible to set a passcode before storing a mnemonic.
        expect(
          await storage.readPlain(kGiftClaimImportHandoffStorageKey),
          _journal,
        );
        await expectCleared(await bootstrap());
      },
    );
  }

  test('import handoff preserves credentials for a durable account', () async {
    await seedImportHandoff();
    await database.writeAsString('imported wallet DB');
    rust.accounts = [
      rust_wallet.AccountInfo(
        uuid: 'imported-account',
        name: 'Imported',
        unifiedAddress: 'u1imported-account',
        birthdayHeight: 3000000,
        zip32AccountIndex: 0,
        isHardware: false,
        isSeedAnchor: true,
      ),
    ];
    final result = await bootstrap();
    expect(result.initialLocation, '/unlock');
    expect(result.isPasswordConfigured, isTrue);
    expect(await storage.readPlain(_verifierKey), 'password-verifier');
    expect(
      await storage.readPlain(kGiftClaimImportHandoffStorageKey),
      _journal,
    );
  });

  test(
    'import DB inspection failure preserves credentials and blocks startup',
    () async {
      await seedImportHandoff();
      await database.writeAsString('unreadable imported wallet DB');
      rust.listError = StateError('database read failed');
      expect((await bootstrap()).hasBlockingFailure, isTrue);
      expect(await storage.readPlain(_verifierKey), 'password-verifier');
      expect(
        await storage.readPlain(kGiftClaimImportHandoffStorageKey),
        _journal,
      );
    },
  );

  test(
    'import handoff read failure preserves credentials and blocks startup',
    () async {
      await seedImportHandoff();
      backend.failNextReadFor = kGiftClaimImportHandoffStorageKey;
      expect((await bootstrap()).hasBlockingFailure, isTrue);
      expect(await storage.readPlain(_verifierKey), 'password-verifier');
      expect(
        await storage.readPlain(kGiftClaimImportHandoffStorageKey),
        _journal,
      );
    },
  );

  for (final key in [
    _verifierSaltKey,
    _verifierKey,
    kPendingAccountMnemonicStorageKey,
    kGiftWalletSetupStartedStorageKey,
  ]) {
    test(
      'cleanup interrupted at $key is repeated on the next launch',
      () async {
        backend.failNextDeleteFor = key;
        final interrupted = await bootstrap();
        expect(interrupted.hasBlockingFailure, isTrue);
        expect(
          await storage.readPlain(kGiftWalletSetupStartedStorageKey),
          'true',
        );
        expect(
          await storage.readPlain(_verifierSaltKey),
          key == _verifierSaltKey || key == kPendingAccountMnemonicStorageKey
              ? 'password-salt'
              : isNull,
        );
        await expectCleared(await bootstrap());
      },
    );
  }

  test('journal read failure blocks startup and preserves the setup', () async {
    backend.failNextReadFor = kPendingAccountMnemonicStorageKey;
    expect((await bootstrap()).hasBlockingFailure, isTrue);
    await expectPreserved();
  });

  for (final savedCredentialKeys in [
    <String>[],
    [_verifierSaltKey],
    [_verifierSaltKey, _verifierKey],
  ]) {
    test(
      'a start marker without a journal cleans interrupted password writes: $savedCredentialKeys',
      () async {
        await storage.delete(kPendingAccountMnemonicStorageKey);
        for (final key in [_verifierSaltKey, _verifierKey]) {
          if (!savedCredentialKeys.contains(key)) await storage.delete(key);
        }
        await expectCleared(await bootstrap());
        await expectCleared(await bootstrap());
      },
    );
  }

  test(
    'a start marker alone preserves credentials when DB inspection fails',
    () async {
      await storage.delete(kPendingAccountMnemonicStorageKey);
      await database.writeAsString('unreadable wallet DB');
      rust.listError = StateError('database read failed');
      final result = await bootstrap();
      expect(result.hasBlockingFailure, isTrue);
      expect(
        await storage.readPlain(kGiftWalletSetupStartedStorageKey),
        'true',
      );
      expect(await storage.readPlain(_verifierKey), 'password-verifier');
      expect(await storage.readPlain(_verifierSaltKey), 'password-salt');
      expect(await database.readAsString(), 'unreadable wallet DB');
    },
  );

  test(
    'a durable account with only the start marker keeps its credentials',
    () async {
      await storage.delete(kPendingAccountMnemonicStorageKey);
      await storage.writeString(
        'zcash_accounts',
        jsonEncode([
          const AccountInfo(
            uuid: 'saved-account',
            name: 'Saved',
            order: 0,
          ).toJson(),
        ]),
      );
      final result = await bootstrap();
      expect(result.initialLocation, '/unlock');
      expect(result.isPasswordConfigured, isTrue);
      expect(result.initialAccountState.activeAccountUuid, 'saved-account');
      expect(
        await storage.readPlain(kGiftWalletSetupStartedStorageKey),
        isNull,
      );
      expect(await storage.readPlain(_verifierKey), 'password-verifier');
      expect(await storage.readPlain(_verifierSaltKey), 'password-salt');
    },
  );

  test(
    'a start marker read failure preserves setup and blocks startup',
    () async {
      backend.failNextReadFor = kGiftWalletSetupStartedStorageKey;
      expect((await bootstrap()).hasBlockingFailure, isTrue);
      await expectPreserved();
    },
  );

  test(
    'failed completed-marker cleanup keeps the account usable and retries',
    () async {
      await storage.delete(kPendingAccountMnemonicStorageKey);
      await storage.writeString(
        'zcash_accounts',
        jsonEncode([
          const AccountInfo(
            uuid: 'saved-account',
            name: 'Saved',
            order: 0,
          ).toJson(),
        ]),
      );
      backend.failNextDeleteFor = kGiftWalletSetupStartedStorageKey;
      final result = await bootstrap();
      expect(result.hasBlockingFailure, isFalse);
      expect(result.initialLocation, '/unlock');
      expect(result.isPasswordConfigured, isTrue);
      expect(
        await storage.readPlain(kGiftWalletSetupStartedStorageKey),
        'true',
      );
      expect(await storage.readPlain(_verifierKey), 'password-verifier');
      expect(await storage.readPlain(_verifierSaltKey), 'password-salt');
      expect((await bootstrap()).initialLocation, '/unlock');
      expect(
        await storage.readPlain(kGiftWalletSetupStartedStorageKey),
        isNull,
      );
    },
  );
}

class _BootstrapRustApi implements RustLibApi {
  List<rust_wallet.AccountInfo> accounts = [];
  Object? listError;
  bool reportMissingDb = false;
  int listCalls = 0;

  void reset() {
    accounts = [];
    listError = null;
    reportMissingDb = false;
    listCalls = 0;
  }

  @override
  bool crateApiWalletWalletExists({required String dbPath}) =>
      !reportMissingDb && File(dbPath).existsSync();

  @override
  Future<void> crateApiWalletEnsureWalletDbMigrated({
    required String dbPath,
    required String network,
  }) async {}

  @override
  Future<List<rust_wallet.AccountInfo>> crateApiWalletListAccounts({
    required String dbPath,
    required String network,
  }) async {
    listCalls++;
    if (listError case final error?) throw error;
    return accounts;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingStorage extends FlutterSecureStorage {
  String? failNextDeleteFor;
  String? failNextReadFor;

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
    if (key == failNextDeleteFor) {
      failNextDeleteFor = null;
      throw StateError('interrupted credential cleanup');
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

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    if (key == failNextReadFor) {
      failNextReadFor = null;
      throw StateError('secure storage read failed');
    }
    return super.read(
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
