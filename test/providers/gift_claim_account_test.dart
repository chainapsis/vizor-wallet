import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/security/software_wallet_secret.dart';
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
  'giftIsCreatedAtProvisional': incomingLink.isCreatedAtProvisional,
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
    SharedPreferences.setMockInitialValues({});
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

  for (final key in ['zcash_account_mnemonic_uuid-1', 'zcash_accounts']) {
    test(
      'Wallet Link preserves its credential and recovers after $key fails',
      () async {
        final security = container.read(appSecurityProvider.notifier);
        await security.preparePasswordSetup(_passcode);
        storage.failNextWriteFor(key);
        const entries = [
          LinkedWalletAccountImport(
            name: _name,
            birthdayHeight: 3000000,
            zip32AccountIndex: 0,
            isHardware: false,
            isSeedAnchor: true,
            mnemonic: _mnemonic,
            bip39Passphrase: 'linked passphrase',
            profilePictureId: _profile,
            sourceAccountUuid: 'source-1',
          ),
        ];
        await expectLater(
          accounts().importLinkedWalletAccounts(
            network: kZcashDefaultNetworkName,
            accountsToImport: entries,
          ),
          throwsA(isA<WalletAccountSetupInterruptedException>()),
        );
        expect(_rust.listedAccounts, hasLength(1));
        await security.finishPasswordSetupAfterFailure(accountMayExist: true);
        expect(await store.verifyPassword(_passcode), isTrue);
        expect(jsonDecode((await pending())!)['kind'], 'linked');
        final restarted = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(_bootstrappedGiftAccount()),
            accountProvider.overrideWith(
              () => AccountNotifier.testing(store: store),
            ),
            appSecurityProvider.overrideWith(
              () => AppSecurityNotifier.testing(store: store),
            ),
          ],
        );
        addTearDown(restarted.dispose);
        await restarted.read(accountProvider.future);
        await restarted.read(accountProvider.notifier).restoreAfterUnlock();
        expect(_rust.importCalls, 1);
        final secret = await store.readAccountSoftwareWalletSecret('uuid-1');
        expect(secret!.mnemonic, _mnemonic);
        expect(secret.bip39Passphrase, 'linked passphrase');
        final account = restarted.read(accountProvider).value!.activeAccount!;
        expect(account.name, _name);
        expect(account.profilePictureId, normalizeProfilePictureId(_profile));
        expect(account.walletLinkSourceAccountUuid, 'source-1');
        expect(await pending(), isNull);
      },
    );
  }

  for (final scenario in ['added', 'deleted original', 'unsaved']) {
    test('stale hardware setup journal with $scenario account', () async {
      storage.failNextDeleteFor(kPendingAccountMnemonicStorageKey);
      await accounts().importKeystoneAccount(
        name: 'Keystone',
        ufvk: 'hardware-ufvk',
        seedFingerprint: List.filled(32, 1),
        zip32Index: 0,
        birthdayHeight: 3000000,
      );
      expect(await pending(), isNotNull);
      await accounts().createAccountFromMnemonic(
        mnemonic: _mnemonic,
        name: 'Added account',
        profilePictureId: _profile,
      );
      final current = container
          .read(accountProvider)
          .requireValue
          .accounts
          .where((a) => scenario != 'deleted original' || a.uuid != 'hardware')
          .toList();
      // Model the persisted account list and Rust bootstrap after restart.
      await store.writeString(
        'zcash_accounts',
        jsonEncode([
          for (final account in current)
            if (scenario != 'unsaved' || account.uuid == 'hardware')
              account.toJson(),
        ]),
      );
      _rust.listedAccounts = _rust.listedAccounts
          .where((a) => current.any((saved) => saved.uuid == a.uuid))
          .toList();
      final restarted = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(
            _bootstrappedGiftAccount(accounts: current),
          ),
          accountProvider.overrideWith(
            () => AccountNotifier.testing(store: store),
          ),
          appSecurityProvider.overrideWith(
            () => AppSecurityNotifier.testing(store: store),
          ),
        ],
      );
      addTearDown(restarted.dispose);
      await restarted.read(accountProvider.future);
      final restore = restarted
          .read(accountProvider.notifier)
          .restoreAfterUnlock();
      if (scenario == 'unsaved') {
        await expectLater(restore, throwsStateError);
        expect(restarted.read(appSecurityProvider).requiresUnlock, isTrue);
        expect(
          await store.readPlain(kPendingAccountMnemonicStorageKey),
          isNotNull,
        );
      } else {
        await restore;
        expect(restarted.read(appSecurityProvider).requiresUnlock, isFalse);
        expect(await pending(), isNull);
        final restored = restarted.read(accountProvider).requireValue.accounts;
        expect(restored.map((a) => a.toJson()), current.map((a) => a.toJson()));
        expect(await store.readAccountMnemonic('uuid-1'), _mnemonic);
        expect(_rust.hardwareImportCalls, 1);
        expect(_rust.addCalls, 1);
      }
    });
  }

  for (final signer in [
    HardwareSignerKind.keystone,
    HardwareSignerKind.ledger,
  ]) {
    for (final mixed in [false, true]) {
      test(
        'Wallet Link restores $signer metadata after interrupted mixed=$mixed import',
        () async {
          final security = container.read(appSecurityProvider.notifier);
          await security.preparePasswordSetup(_passcode);
          storage.failNextWriteFor('zcash_accounts');
          final hardware = LinkedWalletAccountImport(
            name: 'Hardware wallet',
            birthdayHeight: 3000000,
            zip32AccountIndex: 3,
            isHardware: true,
            isSeedAnchor: false,
            hardwareSignerKind: signer,
            ufvk: 'hardware-ufvk',
            seedFingerprint: List.filled(32, 1),
            profilePictureId: _profile,
            sourceAccountUuid: 'desktop-hardware-uuid',
          );
          await expectLater(
            accounts().importLinkedWalletAccounts(
              network: kZcashDefaultNetworkName,
              accountsToImport: [
                if (mixed)
                  const LinkedWalletAccountImport(
                    name: 'Software wallet',
                    birthdayHeight: 3000000,
                    zip32AccountIndex: 0,
                    isHardware: false,
                    isSeedAnchor: true,
                    mnemonic: _mnemonic,
                  ),
                hardware,
              ],
            ),
            throwsA(isA<WalletAccountSetupInterruptedException>()),
          );
          await security.finishPasswordSetupAfterFailure(accountMayExist: true);
          final restarted = ProviderContainer(
            overrides: [
              appBootstrapProvider.overrideWithValue(
                _bootstrappedGiftAccount(
                  accounts: [
                    if (mixed)
                      const AccountInfo(
                        uuid: 'uuid-1',
                        name: 'Software',
                        order: 0,
                      ),
                    AccountInfo(
                      uuid: 'hardware',
                      name: 'Hardware',
                      order: mixed ? 1 : 0,
                      isHardware: true,
                      hardwareSignerKind: signer,
                    ),
                  ],
                ),
              ),
              accountProvider.overrideWith(
                () => AccountNotifier.testing(store: store),
              ),
              appSecurityProvider.overrideWith(
                () => AppSecurityNotifier.testing(store: store),
              ),
            ],
          );
          addTearDown(restarted.dispose);
          await restarted.read(accountProvider.future);
          final recovered = restarted.read(accountProvider.notifier);
          await recovered.restoreAfterUnlock();
          final account = restarted
              .read(accountProvider)
              .value!
              .accounts
              .singleWhere((account) => account.uuid == 'hardware');
          expect(account.name, 'Hardware wallet');
          expect(account.profilePictureId, normalizeProfilePictureId(_profile));
          expect(account.walletLinkSourceAccountUuid, 'desktop-hardware-uuid');
          expect(account.hardwareSignerKind, signer);
          expect(
            await recovered.alreadyImportedWalletLinkSourceAccountUuids(
              network: kZcashDefaultNetworkName,
              accountsToCheck: [hardware],
            ),
            {'desktop-hardware-uuid'},
          );
          expect(
            await store.readAccountSoftwareWalletSecret('hardware'),
            isNull,
          );
          expect(_rust.hardwareImportCalls, 1);
          expect(_rust.importCalls, mixed ? 1 : 0);
          expect(await pending(), isNull);
        },
      );
    }
  }

  test(
    'Wallet Link recovers every imported account, including a nonzero BIP39 index',
    () async {
      await container
          .read(appSecurityProvider.notifier)
          .preparePasswordSetup(_passcode);
      storage.failNextWriteFor('zcash_account_mnemonic_uuid-2');
      await expectLater(
        accounts().importLinkedWalletAccounts(
          network: kZcashDefaultNetworkName,
          accountsToImport: [
            for (var index = 0; index < 2; index++)
              LinkedWalletAccountImport(
                name: 'Linked $index',
                birthdayHeight: 3000000,
                zip32AccountIndex: index,
                isHardware: false,
                isSeedAnchor: index == 0,
                mnemonic: _mnemonic,
                bip39Passphrase: 'linked passphrase',
              ),
          ],
        ),
        throwsA(isA<WalletAccountSetupInterruptedException>()),
      );
      await container
          .read(appSecurityProvider.notifier)
          .finishPasswordSetupAfterFailure(accountMayExist: true);
      final restarted = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(
            _bootstrappedGiftAccount(
              accounts: const [
                AccountInfo(
                  uuid: 'uuid-1',
                  name: 'Account 1',
                  order: 0,
                  zip32AccountIndex: 0,
                  isSeedAnchor: true,
                ),
                AccountInfo(
                  uuid: 'uuid-2',
                  name: 'Account 2',
                  order: 1,
                  zip32AccountIndex: 1,
                ),
              ],
            ),
          ),
          accountProvider.overrideWith(
            () => AccountNotifier.testing(store: store),
          ),
          appSecurityProvider.overrideWith(
            () => AppSecurityNotifier.testing(store: store),
          ),
        ],
      );
      addTearDown(restarted.dispose);
      await restarted.read(accountProvider.future);
      await restarted.read(accountProvider.notifier).restoreAfterUnlock();
      expect(_rust.importCalls, 2);
      for (final uuid in ['uuid-1', 'uuid-2']) {
        expect(
          (await store.readAccountSoftwareWalletSecret(uuid))!.bip39Passphrase,
          'linked passphrase',
        );
      }
      expect(
        restarted.read(accountProvider).value!.accounts.map((a) => a.name),
        ['Linked 0', 'Linked 1'],
      );
      expect(await pending(), isNull);
    },
  );

  test(
    'failed rollback preserves the credential and blocks replacement until cleanup succeeds',
    () async {
      final security = container.read(appSecurityProvider.notifier);
      await security.preparePasswordSetup(_passcode);
      _rust.importError = StateError('pre-account failure');
      await expectLater(
        accounts().createGiftClaimAccount(
          name: _name,
          profilePictureId: _profile,
          link: incomingLink,
        ),
        throwsStateError,
      );
      storage.failNextDeleteFor(kPendingAccountMnemonicStorageKey);
      await expectLater(security.rollbackPasswordSetup(), throwsStateError);
      expect(await store.isPasswordConfigured(), isTrue);
      expect(
        await store.readPlain(kPendingAccountMnemonicStorageKey),
        isNotNull,
      );
      await expectLater(
        security.preparePasswordSetup('24680246'),
        throwsStateError,
      );
      await security.rollbackPasswordSetup();
      expect(await store.isPasswordConfigured(), isFalse);
      expect(await store.readPlain(kPendingAccountMnemonicStorageKey), isNull);
      await security.preparePasswordSetup('24680246');
      expect(await store.verifyPassword('24680246'), isTrue);
    },
  );

  for (final pendingRecovery in [false, true]) {
    test(
      'successful password commit clears only a completed setup marker: pending=$pendingRecovery',
      () async {
        final security = container.read(appSecurityProvider.notifier);
        await security.preparePasswordSetup(_passcode);
        if (pendingRecovery) {
          await store.writeSecretString(
            kPendingAccountMnemonicStorageKey,
            _pendingDraft(),
          );
        }
        await security.completePasswordSetup();
        expect(container.read(appSecurityProvider).isUnlocked, isTrue);
        expect(await store.verifyPassword(_passcode), isTrue);
        expect(
          await store.readPlain(kGiftWalletSetupStartedStorageKey),
          pendingRecovery ? isNotNull : isNull,
        );
        expect(await pending(), pendingRecovery ? isNotNull : isNull);
      },
    );
  }

  for (final key in [
    'zcash_account_mnemonic_uuid-1',
    'zcash_accounts',
    'zcash_active_account',
  ]) {
    test(
      'ordinary setup recovers the same account after a failed $key save',
      () async {
        final security = container.read(appSecurityProvider.notifier);
        await security.preparePasswordSetup(_passcode);
        storage.failNextWriteFor(key);
        Object? failure;
        try {
          await accounts().createAccountFromMnemonic(
            mnemonic: _mnemonic,
            name: _name,
            profilePictureId: _profile,
          );
        } catch (error) {
          failure = error;
        }
        expect(failure, isA<WalletAccountSetupInterruptedException>());
        expect(jsonDecode(_rust.pendingAtImport!)['kind'], 'software');
        await security.finishPasswordSetupAfterFailure(
          accountMayExist: failure is WalletAccountSetupInterruptedException,
        );
        expect(await store.verifyPassword(_passcode), isTrue);
        store.clearSessionPassword();
        final bootstrap = await loadAppBootstrap(secureStore: store);
        expect(bootstrap.hasBlockingFailure, isFalse);
        expect(bootstrap.initialLocation, '/unlock');
        expect(bootstrap.initialAccountState.activeAccountUuid, 'uuid-1');
        final restarted = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(bootstrap),
            accountProvider.overrideWith(
              () => AccountNotifier.testing(store: store),
            ),
            appSecurityProvider.overrideWith(
              () => AppSecurityNotifier.testing(store: store),
            ),
          ],
        );
        addTearDown(restarted.dispose);
        await restarted.read(accountProvider.future);
        expect(
          await restarted.read(appSecurityProvider.notifier).unlock(_passcode),
          isTrue,
        );
        await restarted.read(accountProvider.notifier).restoreAfterUnlock();
        expect(_rust.importCalls, 1);
        expect(await store.readAccountMnemonic('uuid-1'), _mnemonic);
        final recovered = restarted.read(accountProvider).value!.activeAccount!;
        expect(recovered.name, _name);
        expect(recovered.profilePictureId, normalizeProfilePictureId(_profile));
        expect(recovered.setupPending, isFalse);
        expect(recovered.giftEducationPending, isFalse);
        expect(await pending(), isNull);
        expect(restarted.read(appSecurityProvider).requiresUnlock, isFalse);
      },
    );
  }

  test(
    'interrupted first import restores BIP39 secrets for every discovered account',
    () async {
      const extraPassphrase = 'BIP39 fixture';
      await container
          .read(appSecurityProvider.notifier)
          .preparePasswordSetup(_passcode);
      storage.failNextWriteFor('zcash_account_mnemonic_uuid-2');
      await expectLater(
        accounts().importAccount(
          mnemonic: _mnemonic,
          bip39Passphrase: extraPassphrase,
          name: _name,
          profilePictureId: _profile,
          additionalAccountIndices: const [1],
        ),
        throwsA(isA<WalletAccountSetupInterruptedException>()),
      );
      await container
          .read(appSecurityProvider.notifier)
          .finishPasswordSetupAfterFailure(accountMayExist: true);
      final recoveredBootstrap = _bootstrappedGiftAccount(
        accounts: const [
          AccountInfo(
            uuid: 'uuid-1',
            name: 'Account 1',
            order: 0,
            zip32AccountIndex: 0,
            isSeedAnchor: true,
          ),
          AccountInfo(
            uuid: 'uuid-2',
            name: 'Account 2',
            order: 1,
            zip32AccountIndex: 1,
          ),
        ],
      );
      final restarted = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(recoveredBootstrap),
          accountProvider.overrideWith(
            () => AccountNotifier.testing(store: store),
          ),
          appSecurityProvider.overrideWith(
            () => AppSecurityNotifier.testing(store: store),
          ),
        ],
      );
      addTearDown(restarted.dispose);
      await restarted.read(accountProvider.future);
      await restarted.read(accountProvider.notifier).restoreAfterUnlock();
      for (final uuid in ['uuid-1', 'uuid-2']) {
        final secret = await store.readAccountSoftwareWalletSecret(uuid);
        expect(secret!.mnemonic, _mnemonic);
        expect(secret.bip39Passphrase, extraPassphrase);
      }
      expect(restarted.read(accountProvider).value!.accounts.first.name, _name);
      expect(restarted.read(accountSetupRecoveryGenerationProvider), 1);
      expect(_rust.importCalls, 1);
      expect(await pending(), isNull);
    },
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

  for (final failSave in [false, true]) {
    test(
      'Gift account addition preserves the original wallet: storage failure=$failSave',
      () async {
        _rust.walletExists = true;
        _rust.listedAccounts = [_listed('original')];
        final existing = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(
              _bootstrappedGiftAccount(
                account: const AccountInfo(
                  uuid: 'original',
                  name: 'Original',
                  order: 0,
                  isSeedAnchor: true,
                ),
              ),
            ),
            accountProvider.overrideWith(
              () => AccountNotifier.testing(store: store),
            ),
            appSecurityProvider.overrideWith(
              () => AppSecurityNotifier.testing(store: store),
            ),
            paymentLinkReceivedStoreProvider.overrideWithValue(cards),
            rpcEndpointFailoverLatestBlockHeightGetterProvider
                .overrideWithValue((_, _) async => BigInt.from(3000000)),
          ],
        );
        addTearDown(existing.dispose);
        await existing.read(accountProvider.future);
        if (failSave) storage.failNextWriteFor('zcash_account_mnemonic_uuid-1');
        final create = existing
            .read(accountProvider.notifier)
            .createGiftClaimAccount(
              name: _name,
              profilePictureId: _profile,
              link: incomingLink,
            );
        if (failSave) {
          await expectLater(
            create,
            throwsA(isA<GiftClaimAccountCreatedException>()),
          );
          await existing
              .read(accountProvider.notifier)
              .recoverPendingAccountMnemonic();
        } else {
          expect(await create, 'uuid-1');
        }
        expect(_rust.importCalls, 0);
        expect(_rust.addCalls, 1);
        expect(_rust.listedAccounts.map((a) => a.uuid), ['original', 'uuid-1']);
        final state = existing.read(accountProvider).value!;
        expect(state.accounts.map((a) => a.uuid), ['original', 'uuid-1']);
        expect(state.activeAccount!.isSeedAnchor, isFalse);
        expect(state.activeAccount!.setupPending, isTrue);
        expect(state.activeAccount!.giftEducationPending, isTrue);
        expect(await store.readAccountMnemonic('uuid-1'), _mnemonic);
        expect(await store.verifyPassword(_passcode), isTrue);
        expect(
          (await cards.find(incomingLink.address))?.setupAccountUuid,
          'uuid-1',
        );
      },
    );
  }

  for (final failRecoveryWrite in [false, true]) {
    test(
      'Gift recovery selects the added account after restart: retry=$failRecoveryWrite',
      () async {
        const original = AccountInfo(
          uuid: 'original',
          name: 'Original',
          order: 0,
          isSeedAnchor: true,
        );
        _rust.walletExists = true;
        _rust.listedAccounts = [_listed('original')];
        await store.writeString('zcash_active_account', 'original');
        final existing = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(
              _bootstrappedGiftAccount(account: original),
            ),
            accountProvider.overrideWith(
              () => AccountNotifier.testing(store: store),
            ),
            appSecurityProvider.overrideWith(
              () => AppSecurityNotifier.testing(store: store),
            ),
            paymentLinkReceivedStoreProvider.overrideWithValue(cards),
            rpcEndpointFailoverLatestBlockHeightGetterProvider
                .overrideWithValue((_, _) async => BigInt.from(3000000)),
          ],
        );
        addTearDown(existing.dispose);
        await existing.read(accountProvider.future);
        storage.failNextWriteFor('zcash_active_account');
        await expectLater(
          existing
              .read(accountProvider.notifier)
              .createGiftClaimAccount(
                name: _name,
                profilePictureId: _profile,
                link: incomingLink,
              ),
          throwsA(isA<GiftClaimAccountCreatedException>()),
        );
        final savedAccounts =
            (jsonDecode((await store.readString('zcash_accounts'))!) as List)
                .map((json) => AccountInfo.fromJson(json))
                .toList();
        expect(await store.readString('zcash_active_account'), 'original');

        // Bootstrap still selects the previously persisted, valid account.
        final restarted = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(
              _bootstrappedGiftAccount(accounts: savedAccounts),
            ),
            accountProvider.overrideWith(
              () => AccountNotifier.testing(store: store),
            ),
            paymentLinkReceivedStoreProvider.overrideWithValue(cards),
          ],
        );
        addTearDown(restarted.dispose);
        await restarted.read(accountProvider.future);
        final notifier = restarted.read(accountProvider.notifier);
        if (failRecoveryWrite) {
          storage.failNextWriteFor('zcash_active_account');
          await expectLater(
            notifier.recoverPendingAccountMnemonic(),
            throwsA(isA<StateError>()),
          );
          expect(await pending(), isNotNull);
          expect(await store.readString('zcash_active_account'), 'original');
          expect(restarted.read(accountSetupRecoveryGenerationProvider), 0);
        }
        await notifier.recoverPendingAccountMnemonic();
        expect(await store.readString('zcash_active_account'), 'uuid-1');
        final recovered = restarted.read(accountProvider).value!;
        expect(recovered.activeAccountUuid, 'uuid-1');
        expect(recovered.activeAddress, isNull);
        expect(recovered.accounts.map((a) => a.uuid), ['original', 'uuid-1']);
        expect((await cards.load()).single.setupAccountUuid, 'uuid-1');
        expect(await pending(), isNull);
        expect(restarted.read(accountSetupRecoveryGenerationProvider), 1);
        await notifier.restoreAfterUnlock();
        expect(
          restarted.read(accountProvider).value!.activeAddress,
          'u1uuid-1',
        );
        expect(_rust.addCalls, 1);
      },
    );
  }

  for (final ledger in [false, true]) {
    test(
      'first hardware account restores its metadata after save failure: ledger=$ledger',
      () async {
        final security = container.read(appSecurityProvider.notifier);
        await security.preparePasswordSetup(_passcode);
        storage.failNextWriteFor('zcash_accounts');
        final import = ledger
            ? accounts().importLedgerAccount(
                name: _name,
                ufvk: 'fixture',
                seedFingerprint: List.filled(32, 1),
                zip32Index: 0,
                birthdayHeight: 3000000,
                profilePictureId: _profile,
                connectionTransport: LedgerConnectionTransport.bluetooth,
                ledgerDeviceId: 'ledger-device-id',
                ledgerDeviceName: 'Ledger Flex',
                ledgerDeviceModel: 'flex',
              )
            : accounts().importKeystoneAccount(
                name: _name,
                ufvk: 'fixture',
                seedFingerprint: List.filled(32, 1),
                zip32Index: 0,
                birthdayHeight: 3000000,
                profilePictureId: _profile,
              );
        await expectLater(
          import,
          throwsA(isA<WalletAccountSetupInterruptedException>()),
        );
        await security.finishPasswordSetupAfterFailure(accountMayExist: true);
        expect(await store.verifyPassword(_passcode), isTrue);
        expect(_rust.listedAccounts.single.isHardware, isTrue);
        expect(jsonDecode((await pending())!)['kind'], 'linked');

        final restarted = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(
              _bootstrappedGiftAccount(
                account: AccountInfo(
                  uuid: 'hardware',
                  name: 'Hardware',
                  order: 0,
                  isHardware: true,
                  hardwareSignerKind: ledger
                      ? HardwareSignerKind.ledger
                      : HardwareSignerKind.keystone,
                ),
              ),
            ),
            accountProvider.overrideWith(
              () => AccountNotifier.testing(store: store),
            ),
            appSecurityProvider.overrideWith(
              () => AppSecurityNotifier.testing(store: store),
            ),
          ],
        );
        addTearDown(restarted.dispose);
        await restarted.read(accountProvider.future);
        await restarted.read(accountProvider.notifier).restoreAfterUnlock();

        final recovered = restarted.read(accountProvider).value!.activeAccount!;
        expect(recovered.name, _name);
        expect(recovered.profilePictureId, normalizeProfilePictureId(_profile));
        expect(
          recovered.hardwareSignerKind,
          ledger ? HardwareSignerKind.ledger : HardwareSignerKind.keystone,
        );
        expect(recovered.birthdayHeight, 3000000);
        expect(recovered.zip32AccountIndex, 0);
        expect(
          recovered.ledgerLastTransport,
          ledger ? LedgerConnectionTransport.bluetooth : null,
        );
        expect(recovered.ledgerDeviceId, ledger ? 'ledger-device-id' : null);
        expect(recovered.ledgerDeviceName, ledger ? 'Ledger Flex' : null);
        expect(recovered.ledgerDeviceModel, ledger ? 'flex' : null);
        expect(_rust.hardwareImportCalls, 1);
        expect(await pending(), isNull);
      },
    );
  }

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
    final card = (await cards.load()).single;
    expect(card.createdAt, incomingLink.createdAt);
    expect(card.isCreatedAtProvisional, isFalse);
  });

  test(
    'an account JSON failure restores backup markers and the provisional card date after restart',
    () async {
      final previewTime = DateTime.utc(2026, 9, 1);
      final link = incomingLink.withResolvedMetadata(
        createdAt: previewTime,
        isCreatedAtProvisional: true,
      );
      storage.failNextWriteFor('zcash_accounts');

      await expectLater(
        accounts().createGiftClaimAccount(
          name: _name,
          profilePictureId: _profile,
          link: link,
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
      final recovered = (await cards.load()).single;
      expect(recovered.setupAccountUuid, 'uuid-1');
      expect(recovered.createdAt, previewTime);
      expect(recovered.isCreatedAtProvisional, isTrue);
      expect(recovered.claimLink!.isCreatedAtProvisional, isTrue);
      expect(await pending(), isNull);

      // A later funding scan can replace the preview time after recovery.
      final fundingTime = previewTime.add(const Duration(days: 1));
      await cards.resolveProvisionalCreatedAt(
        address: link.address,
        createdAt: fundingTime,
      );
      final funded = (await cards.load()).single;
      expect(funded.createdAt, fundingTime);
      expect(funded.isCreatedAtProvisional, isFalse);
      expect(funded.claimLink!.createdAt, fundingTime);
      expect(funded.claimLink!.isCreatedAtProvisional, isFalse);
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

  for (final entry in <String, String?>{
    'account mnemonic': 'zcash_account_mnemonic_uuid-1',
    'account JSON': 'zcash_accounts',
    'active account': 'zcash_active_account',
    'card record': null,
  }.entries) {
    test(
      'a ${entry.key} save failure publishes and preserves the DB',
      () async {
        if (entry.value case final key?) {
          storage.failNextWriteFor(key);
        } else {
          receivedStorage.failNextWrite = true;
        }

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

        // The current unlocked setup session can finish storage immediately;
        // it does not need a restart or another account-creation attempt.
        await accounts().recoverPendingAccountMnemonic();
        expect(await store.readAccountMnemonic('uuid-1'), _mnemonic);
        expect(await store.readString('zcash_accounts'), isNotNull);
        expect((await cards.load()).single.setupAccountUuid, 'uuid-1');
        expect(await pending(), isNull);
        expect(_rust.importCalls, 1);
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

AppBootstrapState _bootstrappedGiftAccount({
  AccountInfo? account,
  List<AccountInfo>? accounts,
}) => AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: AccountState(
    accounts:
        accounts ??
        [
          account ??
              const AccountInfo(
                uuid: 'uuid-1',
                name: 'Account 1',
                order: 0,
                isSeedAnchor: true,
              ),
        ],
    activeAccountUuid: accounts?.first.uuid ?? account?.uuid ?? 'uuid-1',
    activeAddress: 'u1${accounts?.first.uuid ?? account?.uuid ?? 'uuid-1'}',
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
  String importedBip39Passphrase = '';
  bool importedAdditionalAccount = false;
  String? importedDbPath;
  int importCalls = 0;
  int addCalls = 0;
  int hardwareImportCalls = 0;
  final hardwareUfvks = <String, String>{};
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
    importedBip39Passphrase = '';
    importedAdditionalAccount = false;
    importedDbPath = null;
    importCalls = 0;
    addCalls = 0;
    hardwareImportCalls = 0;
    hardwareUfvks.clear();
    listCalls = 0;
  }

  @override
  Future<void> crateApiWalletEnsureWalletDbMigrated({
    required String dbPath,
    required String network,
  }) async {}

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
  Future<rust_wallet.AccountCreationResult> crateApiWalletAddAccount({
    required String dbPath,
    required String network,
    required String name,
    required String mnemonic,
    required String bip39Passphrase,
    BigInt? birthdayHeight,
  }) async {
    addCalls++;
    pendingAtImport = await store.readSecretStringWithOptions(
      kPendingAccountMnemonicStorageKey,
      requireUnlockedSession: true,
    );
    listedAccounts = [...listedAccounts, _listed('uuid-1')];
    accountForMnemonic = 'uuid-1';
    return const rust_wallet.AccountCreationResult(
      accountUuid: 'uuid-1',
      unifiedAddress: 'u1uuid-1',
    );
  }

  @override
  Future<rust_wallet.AccountCreationResult>
  crateApiWalletImportHardwareAccount({
    required String dbPath,
    required String network,
    required String name,
    required String ufvkString,
    required List<int> seedFingerprint,
    required int zip32Index,
    BigInt? birthdayHeight,
    required String hardwareSignerKind,
  }) async {
    walletExists = true;
    File(dbPath).writeAsStringSync('hardware account database');
    hardwareImportCalls++;
    hardwareUfvks['hardware'] = ufvkString;
    listedAccounts = [
      ...listedAccounts,
      rust_wallet.AccountInfo(
        uuid: 'hardware',
        name: _name,
        unifiedAddress: 'u1hardware',
        birthdayHeight: 3000000,
        isSeedAnchor: false,
        isHardware: true,
        hardwareSignerKind: hardwareSignerKind,
      ),
    ];
    return const rust_wallet.AccountCreationResult(
      accountUuid: 'hardware',
      unifiedAddress: 'u1hardware',
    );
  }

  @override
  Future<String> crateApiWalletGetAccountUfvk({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async => hardwareUfvks[accountUuid]!;

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
      if (importError == null) listedAccounts = [_listed('uuid-1')];
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
  Future<rust_wallet.SoftwareWalletImportAccount>
  crateApiWalletImportSoftwareAccountAtIndex({
    required String mnemonic,
    required String bip39Passphrase,
    BigInt? birthdayHeight,
    required String network,
    required String dbPath,
    required String name,
    required int zip32AccountIndex,
    required bool isFirstWalletAccount,
  }) async {
    importCalls++;
    importedDbPath = dbPath;
    pendingAtImport = await store.readSecretStringWithOptions(
      kPendingAccountMnemonicStorageKey,
      requireUnlockedSession: true,
    );
    File(dbPath).writeAsStringSync('linked account database');
    walletExists = true;
    importedBip39Passphrase = bip39Passphrase;
    accountForMnemonic = 'uuid-1';
    if (zip32AccountIndex == 1) importedAdditionalAccount = true;
    final uuid = 'uuid-${zip32AccountIndex + 1}';
    listedAccounts = [...listedAccounts, _listed(uuid)];
    return rust_wallet.SoftwareWalletImportAccount(
      accountUuid: uuid,
      unifiedAddress: 'u1$uuid',
      zip32AccountIndex: zip32AccountIndex,
      name: name,
      isSeedAnchor: isFirstWalletAccount,
    );
  }

  @override
  Future<rust_wallet.SoftwareWalletImportWithDiscoveryResult>
  crateApiWalletImportSoftwareWalletWithAccountDiscovery({
    required String mnemonic,
    required String bip39Passphrase,
    BigInt? birthdayHeight,
    required String network,
    required String dbPath,
    String? firstAccountName,
    required bool isFirstWalletAccount,
    required int nextAccountNumber,
    required List<int> additionalAccountIndices,
  }) async {
    await crateApiWalletImportWallet(
      mnemonic: mnemonic,
      bip39Passphrase: bip39Passphrase,
      network: network,
      dbPath: dbPath,
      accountName: firstAccountName,
    );
    importedBip39Passphrase = bip39Passphrase;
    importedAdditionalAccount = additionalAccountIndices.contains(1);
    if (importedAdditionalAccount) {
      listedAccounts = [_listed('uuid-1'), _listed('uuid-2')];
    }
    return rust_wallet.SoftwareWalletImportWithDiscoveryResult(
      didImportPrimaryAccount: true,
      accounts: [
        rust_wallet.SoftwareWalletImportAccount(
          accountUuid: 'uuid-1',
          unifiedAddress: 'u1uuid-1',
          zip32AccountIndex: 0,
          name: firstAccountName!,
          isSeedAnchor: true,
        ),
        if (importedAdditionalAccount)
          const rust_wallet.SoftwareWalletImportAccount(
            accountUuid: 'uuid-2',
            unifiedAddress: 'u1uuid-2',
            zip32AccountIndex: 1,
            name: 'Account 2',
            isSeedAnchor: false,
          ),
      ],
    );
  }

  @override
  Future<String> crateApiWalletGetUnifiedAddress({
    required String dbPath,
    required String network,
    String? accountUuid,
  }) async => 'u1$accountUuid';

  @override
  Future<String?> crateApiWalletFindSoftwareAccountForMnemonic({
    required String mnemonic,
    required String network,
    required String dbPath,
    required int zip32AccountIndex,
  }) async {
    final secret = SoftwareWalletSecret.decode(mnemonic);
    if (secret.mnemonic != _mnemonic ||
        secret.bip39Passphrase != importedBip39Passphrase) {
      return null;
    }
    return zip32AccountIndex == 1 && importedAdditionalAccount
        ? 'uuid-2'
        : accountForMnemonic;
  }

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
  bool failNextWrite = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('forced card record write failure');
    }
    value = next;
  }

  @override
  Future<void> delete() async => value = null;
}
