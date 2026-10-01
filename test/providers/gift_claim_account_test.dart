import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import '../support/payment_links_screen_support.dart' show incomingLink;
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _passcode = '13579086';
const _mnemonic = 'gift wallet mnemonic fixture';
const _name = 'My gift wallet';
const _profile = 'pfp-11';
String _pendingDraft() => jsonEncode({
  'mnemonic': _mnemonic,
  'network': incomingLink.network,
  'name': _name,
  'profilePictureId': _profile,
  'giftLink': incomingLink.toRecoveryUri().toString(),
  'giftAddress': incomingLink.address,
  'giftCreatedAt': incomingLink.createdAt.toIso8601String(),
});

final _rust = _GiftAccountRustApi();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => RustLib.initMock(api: _rust));
  tearDownAll(RustLib.dispose);

  late ProviderContainer container;
  late _FailingStorage storage;
  late AppSecureStore store;
  late PaymentLinkReceivedStore cards;
  late _GiftReceivedStorage receivedStorage;

  setUp(() async {
    _rust.reset();
    FlutterSecureStorage.setMockInitialValues({});
    storage = _FailingStorage();
    store = AppSecureStore.testing(
      storage: storage,
      mnemonicStorage: storage,
      enforceSessionGeneration: false,
    );
    _rust.store = store;
    receivedStorage = _GiftReceivedStorage();
    cards = PaymentLinkReceivedStore(receivedStorage);
    final support = await Directory.systemTemp.createTemp('vizor-gift-acct-');
    addTearDown(() => support.delete(recursive: true));
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async => support.path);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null),
    );
    await store.configurePassword(_passcode);
    container = ProviderContainer(
      overrides: [
        paymentLinkReceivedStoreProvider.overrideWithValue(cards),
        appBootstrapProvider.overrideWithValue(_noWalletBootstrap),
        accountProvider.overrideWith(
          () => AccountNotifier.testing(store: store),
        ),
        appSecurityProvider.overrideWith(
          () => AppSecurityNotifier.testing(store: store),
        ),
        rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue(
          (_, _) async => BigInt.from(3000000),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(accountProvider.future);
  });

  AccountNotifier accounts() => container.read(accountProvider.notifier);

  Future<String?> pending() => store.readSecretStringWithOptions(
    kPendingAccountMnemonicStorageKey,
    requireUnlockedSession: true,
  );

  test('the passphrase is pending before the account exists', () async {
    await store.writePlain(kGiftWalletSetupStartedStorageKey, 'true');
    final uuid = await accounts().createGiftClaimAccount(
      name: _name,
      profilePictureId: _profile,
      link: incomingLink,
    );

    expect(
      jsonDecode(_rust.pendingAtImport!),
      containsPair('mnemonic', _mnemonic),
    );
    expect(await store.readAccountMnemonic(uuid), _mnemonic);
    await accounts().clearPendingGiftAccountSetup(accountUuid: 'uuid-1');
    expect(await pending(), isNull);
    expect(await store.readPlain(kGiftWalletSetupStartedStorageKey), isNull);
    final account = container.read(accountProvider).value!.activeAccount!;
    expect(account.uuid, uuid);
    expect(account.name, _name);
    expect(account.profilePictureId, normalizeProfilePictureId(_profile));
    expect(account.setupPending, isTrue);
    expect(account.giftEducationPending, isTrue);
    expect(_rust.listCalls, 0);
    final saved = jsonDecode((await store.readString('zcash_accounts'))!);
    expect((saved as List).single['setupPending'], isTrue);
    expect(saved.single['giftEducationPending'], isTrue);
  });

  test('a confirmed empty DB can be replaced', () async {
    _rust.walletExists = true;

    final uuid = await accounts().createGiftClaimAccount(
      name: _name,
      profilePictureId: _profile,
      link: incomingLink,
    );

    expect(uuid, 'uuid-1');
    expect(_rust.listCalls, 1);
    expect(_rust.importCalls, 1);
  });

  test('an existing account blocks first-wallet replacement', () async {
    _rust
      ..walletExists = true
      ..listedAccounts = [_listed('other-account')];

    await expectLater(
      accounts().createGiftClaimAccount(
        name: _name,
        profilePictureId: _profile,
        link: incomingLink,
      ),
      throwsA(isA<WalletAccountStateUncertainException>()),
    );

    expect(_rust.listCalls, 1);
    expect(_rust.importCalls, 0);
    expect(await pending(), isNull);
  });

  test('a create that left no account can be rolled back', () async {
    _rust.importError = StateError('network');

    await expectLater(
      accounts().createGiftClaimAccount(
        name: _name,
        profilePictureId: _profile,
        link: incomingLink,
      ),
      throwsA(isNot(isA<GiftClaimAccountCreatedException>())),
    );
    expect(container.read(accountProvider).value!.accounts, isEmpty);
  });

  test('a create whose outcome is unknown keeps the password', () async {
    _rust
      ..importError = StateError('interrupted')
      ..createDbBeforeImportError = true
      ..listedAccounts = [_listed('uuid-1')];

    await expectLater(
      accounts().createGiftClaimAccount(
        name: _name,
        profilePictureId: _profile,
        link: incomingLink,
      ),
      throwsA(
        isA<GiftClaimAccountCreatedException>().having(
          (error) => error.accountUuid,
          'accountUuid',
          'uuid-1',
        ),
      ),
    );
    expect(container.read(accountProvider).value!.activeAccountUuid, 'uuid-1');
  });

  test(
    'an ambiguous create never selects an unrelated database account',
    () async {
      _rust
        ..importError = StateError('interrupted')
        ..createDbBeforeImportError = true
        ..listedAccounts = [_listed('unrelated-account')];
      await expectLater(
        accounts().createGiftClaimAccount(
          name: _name,
          profilePictureId: _profile,
          link: incomingLink,
        ),
        throwsA(
          isA<GiftClaimAccountCreatedException>().having(
            (error) => error.accountUuid,
            'accountUuid',
            isNull,
          ),
        ),
      );
      expect(container.read(accountProvider).value!.accounts, isEmpty);
      expect(await pending(), isNotNull);
    },
  );

  test('a save failure after the account exists publishes it', () async {
    await store.writePlain(kGiftWalletSetupStartedStorageKey, 'true');
    _rust.lockAfterImport = true;

    await expectLater(
      accounts().createGiftClaimAccount(
        name: _name,
        profilePictureId: _profile,
        link: incomingLink,
      ),
      throwsA(isA<GiftClaimAccountCreatedException>()),
    );
    final state = container.read(accountProvider).value!;
    expect(state.activeAccount!.uuid, 'uuid-1');
    expect(state.activeAccount!.setupPending, isTrue);
    expect(state.activeAccount!.giftEducationPending, isTrue);

    // The next unlock attaches the pending passphrase to that account.
    expect(await store.verifyPassword(_passcode), isTrue);
    _rust.accountForMnemonic = 'uuid-1';
    await accounts().recoverPendingAccountMnemonic();

    expect(await store.readAccountMnemonic('uuid-1'), _mnemonic);
    expect(await pending(), isNull);
    expect(await store.readPlain(kGiftWalletSetupStartedStorageKey), isNull);
  });

  test(
    'an account JSON failure restores backup-required state after restart',
    () async {
      storage.failNextWriteFor('zcash_accounts');

      await expectLater(
        accounts().createGiftClaimAccount(
          name: _name,
          profilePictureId: _profile,
          link: incomingLink,
        ),
        throwsA(isA<GiftClaimAccountCreatedException>()),
      );
      expect(await store.readAccountMnemonic('uuid-1'), _mnemonic);
      expect(
        jsonDecode((await pending())!),
        containsPair('mnemonic', _mnemonic),
      );
      expect(await store.readString('zcash_accounts'), isNull);

      // Bootstrap reconstructs the Rust account without the UI-only
      // setupPending metadata when account JSON never reached storage.
      final restarted = ProviderContainer(
        overrides: [
          paymentLinkReceivedStoreProvider.overrideWithValue(cards),
          appBootstrapProvider.overrideWithValue(_bootstrappedGiftAccount()),
          accountProvider.overrideWith(
            () => AccountNotifier.testing(store: store),
          ),
          rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue(
            (_, _) async => BigInt.from(3000000),
          ),
        ],
      );
      addTearDown(restarted.dispose);
      await restarted.read(accountProvider.future);
      expect(
        restarted.read(accountProvider).value!.activeAccount!.setupPending,
        isFalse,
      );
      expect(
        restarted
            .read(accountProvider)
            .value!
            .activeAccount!
            .giftEducationPending,
        isFalse,
      );

      _rust.accountForMnemonic = 'uuid-1';
      await restarted
          .read(accountProvider.notifier)
          .recoverPendingAccountMnemonic();

      expect(
        restarted.read(accountProvider).value!.activeAccount!.setupPending,
        isTrue,
      );
      expect(
        restarted
            .read(accountProvider)
            .value!
            .activeAccount!
            .giftEducationPending,
        isTrue,
      );
      final saved = jsonDecode((await store.readString('zcash_accounts'))!);
      expect((saved as List).single['setupPending'], isTrue);
      expect(saved.single['giftEducationPending'], isTrue);
      expect(saved.single['name'], _name);
      expect(saved.single['profilePictureId'], _profile);
      expect(
        (await cards.find(incomingLink.address))?.setupAccountUuid,
        'uuid-1',
      );
      expect(await pending(), isNull);
    },
  );

  test(
    'recovery preserves the pending passphrase when metadata save fails',
    () async {
      await store.writeSecretString(
        kPendingAccountMnemonicStorageKey,
        _pendingDraft(),
      );
      await store.writeAccountMnemonic('uuid-1', _mnemonic);
      _rust.accountForMnemonic = 'uuid-1';
      storage.failNextWriteFor('zcash_accounts');

      final restarted = ProviderContainer(
        overrides: [
          paymentLinkReceivedStoreProvider.overrideWithValue(cards),
          appBootstrapProvider.overrideWithValue(_bootstrappedGiftAccount()),
          accountProvider.overrideWith(
            () => AccountNotifier.testing(store: store),
          ),
        ],
      );
      addTearDown(restarted.dispose);
      await restarted.read(accountProvider.future);

      await expectLater(
        restarted
            .read(accountProvider.notifier)
            .recoverPendingAccountMnemonic(),
        throwsA(isA<StateError>()),
      );

      expect(
        jsonDecode((await pending())!),
        containsPair('mnemonic', _mnemonic),
      );
      expect(
        restarted.read(accountProvider).value!.activeAccount!.setupPending,
        isFalse,
      );
    },
  );

  test('a pending passphrase no account derives from is dropped', () async {
    await store.writeSecretString(
      kPendingAccountMnemonicStorageKey,
      _pendingDraft(),
    );

    await accounts().recoverPendingAccountMnemonic();

    expect(await pending(), isNull);
  });

  test('the network is saved before any account can be created', () async {
    storage.failNextWriteFor('zcash_wallet_network');
    await expectLater(
      accounts().createGiftClaimAccount(
        name: _name,
        profilePictureId: _profile,
        link: incomingLink,
      ),
      throwsA(isNot(isA<GiftClaimAccountCreatedException>())),
    );
    expect(_rust.importCalls, 0);
    expect(await pending(), isNull);
  });

  test(
    'recovery preserves conflicting account secrets and the journal',
    () async {
      final uuid = await accounts().createGiftClaimAccount(
        name: _name,
        profilePictureId: _profile,
        link: incomingLink,
      );
      await store.writeAccountMnemonic(uuid, 'another account secret');
      _rust.accountForMnemonic = uuid;
      await expectLater(
        accounts().recoverPendingAccountMnemonic(),
        throwsStateError,
      );
      expect(await store.readAccountMnemonic(uuid), 'another account secret');
      expect(await pending(), isNotNull);
    },
  );

  test('recovery retains a card bound to a different setup account', () async {
    final uuid = await accounts().createGiftClaimAccount(
      name: _name,
      profilePictureId: _profile,
      link: incomingLink,
    );
    // Model inconsistent persisted data; saveReady now rejects reassignment.
    final payload = jsonDecode(receivedStorage.value!) as Map<String, dynamic>;
    (payload['records'] as List).single['setupAccountUuid'] = 'other';
    receivedStorage.value = jsonEncode(payload);
    _rust.accountForMnemonic = uuid;
    await expectLater(
      accounts().recoverPendingAccountMnemonic(),
      throwsStateError,
    );
    expect((await cards.find(incomingLink.address))?.setupAccountUuid, 'other');
    expect(await pending(), isNotNull);
  });

  test(
    'failed unlock recovery stays locked and retains the journal for retry',
    () async {
      await store.writeSecretString(
        kPendingAccountMnemonicStorageKey,
        _pendingDraft(),
      );
      await store.writeAccountMnemonic('uuid-1', 'conflicting account secret');
      _rust.accountForMnemonic = 'uuid-1';
      final restarted = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrappedGiftAccount()),
          accountProvider.overrideWith(
            () => AccountNotifier.testing(store: store),
          ),
          appSecurityProvider.overrideWith(
            () => AppSecurityNotifier.testing(store: store),
          ),
          paymentLinkReceivedStoreProvider.overrideWithValue(cards),
        ],
      );
      addTearDown(restarted.dispose);
      await restarted.read(accountProvider.future);
      await expectLater(
        restarted.read(accountProvider.notifier).restoreAfterUnlock(),
        throwsStateError,
      );
      expect(restarted.read(appSecurityProvider).requiresUnlock, isTrue);
      expect(restarted.read(accountProvider).value!.activeAddress, isNull);
      expect(store.hasSessionPassword, isFalse);
      expect(await store.verifyPassword(_passcode), isTrue);
      expect(await pending(), isNotNull);
    },
  );

  test('a pending passphrase write failure never creates an account', () async {
    storage.failNextWriteFor(kPendingAccountMnemonicStorageKey);

    await expectLater(
      accounts().createGiftClaimAccount(
        name: _name,
        profilePictureId: _profile,
        link: incomingLink,
      ),
      throwsA(isNot(isA<GiftClaimAccountCreatedException>())),
    );

    expect(_rust.importCalls, 0);
    expect(container.read(accountProvider).value!.accounts, isEmpty);
    expect(await store.verifyPassword(_passcode), isTrue);
  });

  test(
    'an import exception after DB creation publishes and preserves it',
    () async {
      _rust
        ..importError = StateError('interrupted')
        ..createDbBeforeImportError = true
        ..listedAccounts = [_listed('uuid-1')];

      await expectLater(
        accounts().createGiftClaimAccount(
          name: _name,
          profilePictureId: _profile,
          link: incomingLink,
        ),
        throwsA(isA<GiftClaimAccountCreatedException>()),
      );

      expect(File(_rust.importedDbPath!).existsSync(), isTrue);
      expect(
        container.read(accountProvider).value!.activeAccountUuid,
        'uuid-1',
      );
      expect(
        jsonDecode((await pending())!),
        containsPair('mnemonic', _mnemonic),
      );
      await expectLater(
        accounts().createGiftClaimAccount(
          name: _name,
          profilePictureId: _profile,
          link: incomingLink,
        ),
        throwsA(isA<StateError>()),
      );
      expect(_rust.importCalls, 1);
      expect(await store.verifyPassword(_passcode), isTrue);
    },
  );

  test(
    'an unlistable created DB blocks every first-wallet entry point',
    () async {
      await container
          .read(appSecurityProvider.notifier)
          .preparePasswordSetup(_passcode);
      _rust
        ..importError = StateError('interrupted')
        ..createDbBeforeImportError = true
        ..listError = StateError('listing unavailable');

      await expectLater(
        accounts().createGiftClaimAccount(
          name: _name,
          profilePictureId: _profile,
          link: incomingLink,
        ),
        throwsA(
          isA<GiftClaimAccountCreatedException>().having(
            (error) => error.accountUuid,
            'accountUuid',
            isNull,
          ),
        ),
      );

      final dbPath = _rust.importedDbPath!;
      expect(File(dbPath).readAsStringSync(), 'gift account database');
      expect(
        jsonDecode((await pending())!),
        containsPair('mnemonic', _mnemonic),
      );
      expect(container.read(accountProvider).value!.accounts, isEmpty);

      final firstWalletEntries =
          <({String name, Future<Object?> Function() invoke})>[
            (name: 'create account', invoke: () => accounts().createAccount()),
            (
              name: 'create account from mnemonic',
              invoke: () => accounts().createAccountFromMnemonic(
                mnemonic: 'replacement mnemonic',
              ),
            ),
            (
              name: 'import account',
              invoke: () =>
                  accounts().importAccount(mnemonic: 'replacement mnemonic'),
            ),
            (
              name: 'linked import',
              invoke: () => accounts().importLinkedWalletAccounts(
                network: kZcashDefaultNetworkName,
                accountsToImport: const [
                  LinkedWalletAccountImport(
                    name: 'Linked account',
                    birthdayHeight: 3000000,
                    zip32AccountIndex: 0,
                    isHardware: false,
                    isSeedAnchor: true,
                    mnemonic: 'replacement mnemonic',
                  ),
                ],
              ),
            ),
            (
              name: 'Gift Card create retry',
              invoke: () => accounts().createGiftClaimAccount(
                name: _name,
                profilePictureId: _profile,
                link: incomingLink,
              ),
            ),
            (
              name: 'Keystone import',
              invoke: () => accounts().importKeystoneAccount(
                name: 'Keystone',
                ufvk: 'ufvk',
                seedFingerprint: const [1, 2, 3, 4],
                zip32Index: 0,
                birthdayHeight: 3000000,
              ),
            ),
            (
              name: 'Ledger import',
              invoke: () => accounts().importLedgerAccount(
                name: 'Ledger',
                ufvk: 'ufvk',
                seedFingerprint: const [1, 2, 3, 4],
                zip32Index: 0,
                birthdayHeight: 3000000,
              ),
            ),
          ];

      for (final entry in firstWalletEntries) {
        await expectLater(
          entry.invoke(),
          throwsA(isA<WalletAccountStateUncertainException>()),
          reason: entry.name,
        );
        expect(
          File(dbPath).readAsStringSync(),
          'gift account database',
          reason: entry.name,
        );
        expect(
          jsonDecode((await pending())!),
          containsPair('mnemonic', _mnemonic),
          reason: entry.name,
        );
        expect(_rust.importCalls, 1, reason: entry.name);
      }
    },
  );

  test('the unlistable DB guard survives a notifier restart', () async {
    _rust
      ..importError = StateError('interrupted')
      ..createDbBeforeImportError = true
      ..listError = StateError('listing unavailable');

    await expectLater(
      accounts().createGiftClaimAccount(
        name: _name,
        profilePictureId: _profile,
        link: incomingLink,
      ),
      throwsA(isA<GiftClaimAccountCreatedException>()),
    );
    final dbPath = _rust.importedDbPath!;

    final restarted = ProviderContainer(
      overrides: [
        paymentLinkReceivedStoreProvider.overrideWithValue(cards),
        appBootstrapProvider.overrideWithValue(_noWalletBootstrap),
        accountProvider.overrideWith(
          () => AccountNotifier.testing(store: store),
        ),
        rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue(
          (_, _) async => BigInt.from(3000000),
        ),
      ],
    );
    addTearDown(restarted.dispose);
    await restarted.read(accountProvider.future);

    await expectLater(
      restarted
          .read(accountProvider.notifier)
          .createAccountFromMnemonic(mnemonic: 'replacement mnemonic'),
      throwsA(isA<WalletAccountStateUncertainException>()),
    );
    expect(File(dbPath).readAsStringSync(), 'gift account database');
    expect(jsonDecode((await pending())!), containsPair('mnemonic', _mnemonic));
    expect(_rust.importCalls, 1);
  });

  for (final entry in <String, String>{
    'account mnemonic': 'zcash_account_mnemonic_uuid-1',
    'account JSON': 'zcash_accounts',
    'active account': 'zcash_active_account',
  }.entries) {
    test(
      'a ${entry.key} save failure publishes and preserves the DB',
      () async {
        storage.failNextWriteFor(entry.value);

        await expectLater(
          accounts().createGiftClaimAccount(
            name: _name,
            profilePictureId: _profile,
            link: incomingLink,
          ),
          throwsA(isA<GiftClaimAccountCreatedException>()),
        );

        expect(File(_rust.importedDbPath!).existsSync(), isTrue);
        final state = container.read(accountProvider).value!;
        expect(state.activeAccountUuid, 'uuid-1');
        expect(state.activeAccount!.setupPending, isTrue);
        expect(
          jsonDecode((await pending())!),
          containsPair('mnemonic', _mnemonic),
        );
        await expectLater(
          accounts().createGiftClaimAccount(
            name: _name,
            profilePictureId: _profile,
            link: incomingLink,
          ),
          throwsA(isA<StateError>()),
        );
        expect(_rust.importCalls, 1);
        expect(await store.verifyPassword(_passcode), isTrue);
      },
    );
  }

  test(
    'a pending passphrase cleanup failure keeps the usable account',
    () async {
      storage.failNextDeleteFor(kPendingAccountMnemonicStorageKey);

      final uuid = await accounts().createGiftClaimAccount(
        name: _name,
        profilePictureId: _profile,
        link: incomingLink,
      );

      expect(uuid, 'uuid-1');
      await expectLater(
        accounts().clearPendingGiftAccountSetup(accountUuid: 'uuid-1'),
        throwsA(isA<StateError>()),
      );
      expect(File(_rust.importedDbPath!).existsSync(), isTrue);
      expect(container.read(accountProvider).value!.activeAccountUuid, uuid);
      expect(
        jsonDecode((await pending())!),
        containsPair('mnemonic', _mnemonic),
      );
      expect(await store.readAccountMnemonic(uuid), _mnemonic);
      expect(await store.verifyPassword(_passcode), isTrue);
    },
  );
}

rust_wallet.AccountInfo _listed(String uuid) => rust_wallet.AccountInfo(
  uuid: uuid,
  name: 'Account 1',
  unifiedAddress: 'u1$uuid',
  birthdayHeight: 3000000,
  isSeedAnchor: true,
  isHardware: false,
);

final _noWalletBootstrap = AppBootstrapState(
  initialLocation: '/welcome',
  initialAccountState: const AccountState(),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: kZcashDefaultNetworkName,
  rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: false,
  isUnlocked: false,
  passwordRotationRecoveryFailed: false,
);

AppBootstrapState _bootstrappedGiftAccount() => AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'uuid-1',
        name: 'Account 1',
        order: 0,
        isSeedAnchor: true,
      ),
    ],
    activeAccountUuid: 'uuid-1',
    activeAddress: 'u1uuid-1',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: kZcashDefaultNetworkName,
  rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _GiftAccountRustApi implements RustLibApi {
  late AppSecureStore store;
  Object? importError;
  Object? listError;
  bool createDbBeforeImportError = false;
  bool lockAfterImport = false;
  bool walletExists = false;
  List<rust_wallet.AccountInfo> listedAccounts = const [];
  String? accountForMnemonic;
  String? pendingAtImport;
  String? importedDbPath;
  int importCalls = 0;
  int listCalls = 0;

  void reset() {
    importError = null;
    listError = null;
    createDbBeforeImportError = false;
    lockAfterImport = false;
    walletExists = false;
    listedAccounts = const [];
    accountForMnemonic = null;
    pendingAtImport = null;
    importedDbPath = null;
    importCalls = 0;
    listCalls = 0;
  }

  @override
  String crateApiWalletGenerateMnemonic() => _mnemonic;

  @override
  bool crateApiWalletWalletExists({required String dbPath}) => walletExists;

  @override
  Future<List<rust_wallet.AccountInfo>> crateApiWalletListAccounts({
    required String dbPath,
    required String network,
  }) async {
    listCalls++;
    if (listError case final error?) throw error;
    return listedAccounts;
  }

  @override
  Future<rust_wallet.WalletImportResult> crateApiWalletImportWallet({
    required String mnemonic,
    required String bip39Passphrase,
    BigInt? birthdayHeight,
    required String network,
    required String dbPath,
    String? accountName,
  }) async {
    importCalls++;
    importedDbPath = dbPath;
    pendingAtImport = await store.readSecretStringWithOptions(
      kPendingAccountMnemonicStorageKey,
      requireUnlockedSession: true,
    );
    if (importError == null || createDbBeforeImportError) {
      File(dbPath).writeAsStringSync('gift account database');
      walletExists = true;
      accountForMnemonic = 'uuid-1';
    }
    if (importError case final error?) throw error;
    // Without a session the passphrase write that follows fails.
    if (lockAfterImport) store.clearSessionPassword();
    return const rust_wallet.WalletImportResult(
      unifiedAddress: 'u1uuid-1',
      accountUuid: 'uuid-1',
    );
  }

  @override
  Future<String?> crateApiWalletFindSoftwareAccountForMnemonic({
    required String mnemonic,
    required String network,
    required String dbPath,
    required int zip32AccountIndex,
  }) async => mnemonic == _mnemonic ? accountForMnemonic : null;

  @override
  Future<String> crateApiSecretDeriveSecretPasswordVerifier({
    required String password,
    required String saltBase64,
  }) async => base64Encode(utf8.encode('$saltBase64:$password'));

  @override
  Future<String> crateApiSecretEncryptSecretPayload({
    required List<int> plainBytes,
    required String password,
    required String saltBase64,
  }) async => jsonEncode({
    'v': 1,
    'n': base64Encode(utf8.encode('nonce')),
    'c': base64Encode(plainBytes),
    'm': base64Encode(utf8.encode('$password:$saltBase64')),
  });

  @override
  Future<Uint8List> crateApiSecretDecryptSecretPayload({
    required String payloadJson,
    required String password,
    required String saltBase64,
  }) async {
    final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
    if (payload['m'] != base64Encode(utf8.encode('$password:$saltBase64'))) {
      throw StateError('Failed to decrypt secure-storage payload');
    }
    return Uint8List.fromList(base64Decode(payload['c'] as String));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingStorage extends FlutterSecureStorage {
  final _failWrites = <String>{};
  final _failDeletes = <String>{};

  void failNextWriteFor(String key) => _failWrites.add(key);

  void failNextDeleteFor(String key) => _failDeletes.add(key);

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
    if (_failWrites.remove(key)) {
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
    if (_failDeletes.remove(key)) {
      throw StateError('forced delete failure for $key');
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

class _GiftReceivedStorage implements PaymentLinkReceivedStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
  @override
  Future<void> delete() async => value = null;
}
