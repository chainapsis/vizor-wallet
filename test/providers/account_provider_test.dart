import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_guard_provider.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('wallet db cleanup paths include main db and voting sidecar files', () {
    const dbPath = '/tmp/zcash_wallet.db';

    final cleanupPaths = walletDbCleanupPaths(dbPath);

    expect(cleanupPaths, [
      '/tmp/zcash_wallet.db',
      '/tmp/zcash_wallet.db-journal',
      '/tmp/zcash_wallet.db-wal',
      '/tmp/zcash_wallet.db-shm',
      '/tmp/zcash_wallet.db.voting',
      '/tmp/zcash_wallet.db.voting-journal',
      '/tmp/zcash_wallet.db.voting-wal',
      '/tmp/zcash_wallet.db.voting-shm',
      '/tmp/zcash_wallet.db.receive.redb',
    ]);
  });

  test('wallet db cleanup paths are stable for empty db path', () {
    final cleanupPaths = walletDbCleanupPaths('');

    expect(cleanupPaths, [
      '',
      '-journal',
      '-wal',
      '-shm',
      '.voting',
      '.voting-journal',
      '.voting-wal',
      '.voting-shm',
      '.receive.redb',
    ]);
  });

  group('defaultDeriveSourceAccountUuid', () {
    AccountInfo account(String uuid, int order, {bool isHardware = false}) =>
        AccountInfo(
          uuid: uuid,
          name: 'A$order',
          order: order,
          isHardware: isHardware,
          isSeedAnchor: order == 0 && !isHardware,
        );

    test('prefers the active account when it is a software account', () {
      final state = AccountState(
        accounts: [account('a', 0), account('b', 1)],
        activeAccountUuid: 'b',
      );

      expect(defaultDeriveSourceAccountUuid(state), 'b');
    });

    test(
      'falls back to the first software account when active is hardware',
      () {
        final state = AccountState(
          accounts: [account('hw', 0, isHardware: true), account('sw', 1)],
          activeAccountUuid: 'hw',
        );

        expect(defaultDeriveSourceAccountUuid(state), 'sw');
      },
    );

    test('returns null for hardware-only wallets', () {
      final state = AccountState(
        accounts: [account('hw', 0, isHardware: true)],
        activeAccountUuid: 'hw',
      );

      expect(defaultDeriveSourceAccountUuid(state), isNull);
    });

    test('returns null for empty wallets', () {
      expect(defaultDeriveSourceAccountUuid(const AccountState()), isNull);
    });
  });

  test(
    'renameAccountGroup updates and persists every account in the family',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const accountState = AccountState(
        accounts: [
          AccountInfo(
            uuid: 'account-1',
            name: 'Primary',
            order: 0,
            seedFamilyId: 'seed-a',
          ),
          AccountInfo(
            uuid: 'account-2',
            name: 'Savings',
            order: 1,
            seedFamilyId: 'seed-a',
          ),
          AccountInfo(
            uuid: 'account-3',
            name: 'Travel',
            order: 2,
            seedFamilyId: 'seed-b',
          ),
        ],
        activeAccountUuid: 'account-1',
      );
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(
            AppBootstrapState(
              initialLocation: '/accounts',
              initialAccountState: accountState,
              initialSyncSnapshot: AppSyncSnapshot.empty,
              network: 'main',
              rpcEndpointConfig: defaultRpcEndpointConfig('main'),
              themeMode: ThemeMode.system,
              privacyModeEnabled: false,
              isPasswordConfigured: true,
              isUnlocked: true,
              passwordRotationRecoveryFailed: false,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);

      await container
          .read(accountProvider.notifier)
          .renameAccountGroup('account-1', '  Everyday wallet  ');

      final accounts = container.read(accountProvider).requireValue.accounts;
      expect(accounts[0].accountGroupName, 'Everyday wallet');
      expect(accounts[1].accountGroupName, 'Everyday wallet');
      expect(accounts[2].accountGroupName, isNull);

      final raw = await const FlutterSecureStorage().read(
        key: 'zcash_accounts',
      );
      final stored = (jsonDecode(raw!) as List).cast<Map<String, dynamic>>();
      expect(stored[0]['accountGroupName'], 'Everyday wallet');
      expect(stored[1]['accountGroupName'], 'Everyday wallet');
      expect(stored[2]['accountGroupName'], isNull);

      final inheritedName = existingAccountGroupNameForSeedFamily(
        accounts,
        'seed-a',
      );
      final replacement = AccountInfo(
        uuid: 'account-4',
        name: 'Later import',
        order: 3,
        seedFamilyId: 'seed-a',
        accountGroupName: inheritedName,
      );
      expect(
        groupAccountsBySeedFamily([replacement], replacement.uuid).single.name,
        'Everyday wallet',
      );
    },
  );

  test(
    'hardware account group rename and inheritance ignore matching software fingerprint',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const accountState = AccountState(
        accounts: [
          AccountInfo(
            uuid: 'software',
            name: 'Software',
            order: 0,
            seedFamilyId: 'shared-fingerprint',
          ),
          AccountInfo(
            uuid: 'hardware',
            name: 'Keystone',
            order: 1,
            isHardware: true,
            seedFamilyId: 'shared-fingerprint',
            accountGroupName: 'Hardware wallet',
          ),
        ],
        activeAccountUuid: 'software',
      );
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(
            AppBootstrapState(
              initialLocation: '/accounts',
              initialAccountState: accountState,
              initialSyncSnapshot: AppSyncSnapshot.empty,
              network: 'main',
              rpcEndpointConfig: defaultRpcEndpointConfig('main'),
              themeMode: ThemeMode.system,
              privacyModeEnabled: false,
              isPasswordConfigured: true,
              isUnlocked: true,
              passwordRotationRecoveryFailed: false,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);

      await container
          .read(accountProvider.notifier)
          .renameAccountGroup('hardware', '  Renamed hardware  ');

      final accounts = container.read(accountProvider).requireValue.accounts;
      expect(accounts[0].accountGroupName, isNull);
      expect(accounts[1].accountGroupName, 'Renamed hardware');
      expect(
        existingAccountGroupNameForSeedFamily(accounts, 'shared-fingerprint'),
        isNull,
      );
    },
  );

  group('derived account durable commit', () {
    const source = AccountInfo(
      uuid: 'source',
      name: 'Source',
      order: 0,
      isSeedAnchor: true,
      seedFamilyId: 'software-family',
    );
    final rust = _DerivationRustApiFake();
    late FlutterSecureStoragePlatform previousStoragePlatform;
    late _FaultInjectingSecureStorage storage;

    setUpAll(() {
      RustLib.initMock(api: rust);
    });

    tearDownAll(RustLib.dispose);

    setUp(() async {
      previousStoragePlatform = FlutterSecureStoragePlatform.instance;
      storage = _FaultInjectingSecureStorage();
      FlutterSecureStoragePlatform.instance = storage;
      rust.reset();
      await AppSecureStore.instance.deleteAll();
      AppSecureStore.instance.setSessionPassword('Testpass1!');
      await AppSecureStore.instance.writeAccountMnemonic(
        source.uuid,
        'source recovery phrase',
      );
      await AppSecureStore.instance.writeString(
        'zcash_accounts',
        jsonEncode([source.toJson()]),
      );
      await AppSecureStore.instance.writeString(
        'zcash_active_account',
        source.uuid,
      );
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, (call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return '/private/tmp/vizor-account-provider-test';
            }
            return null;
          });
    });

    tearDown(() async {
      AppSecureStore.instance.clearSessionPassword();
      FlutterSecureStoragePlatform.instance = previousStoragePlatform;
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null);
    });

    for (final boundary in _DerivedAccountWriteBoundary.values) {
      for (final mode in _DerivedAccountWriteFailureMode.values) {
        test(
          'compensates ${mode.name} ${boundary.name} write failure without consuming an account index',
          () async {
            mode.inject(storage, boundary.storageKey);
            final container = _deriveAccountContainer(source);
            addTearDown(container.dispose);
            await container.read(accountProvider.future);

            await expectLater(
              container
                  .read(accountProvider.notifier)
                  .deriveAccountFromExistingSeed(
                    sourceAccountUuid: source.uuid,
                  ),
              throwsA(isA<SecureStorageUnavailableException>()),
            );

            expect(rust.liveAccountIndices, isEmpty);
            expect(
              await container
                  .read(accountProvider.notifier)
                  .getSoftwareWalletSecretForAccount('derived-1'),
              isNull,
            );
            expect(
              jsonDecode(storage.values['zcash_accounts']!) as List,
              hasLength(1),
            );
            expect(storage.values['zcash_active_account'], source.uuid);
            final stateAfterFailure = container
                .read(accountProvider)
                .requireValue;
            expect(stateAfterFailure.accounts, hasLength(1));
            expect(stateAfterFailure.accounts.single.uuid, source.uuid);
            expect(stateAfterFailure.activeAccountUuid, source.uuid);

            await container
                .read(accountProvider.notifier)
                .deriveAccountFromExistingSeed(sourceAccountUuid: source.uuid);

            expect(rust.allocatedIndices, [1, 1]);
            expect(rust.liveAccountIndices, {1});
            final persistedSecret = await container
                .read(accountProvider.notifier)
                .getSoftwareWalletSecretForAccount('derived-1');
            expect(persistedSecret?.mnemonic, 'source recovery phrase');
            expect(persistedSecret?.bip39Passphrase, isEmpty);
            expect(
              container.read(accountProvider).requireValue.accounts,
              hasLength(2),
            );
          },
        );
      }
    }

    for (final mode in _DerivedAccountWriteFailureMode.values) {
      test(
        'requires a durable ${mode.name} fence before Rust derivation',
        () async {
          mode.inject(storage, 'zcash_derived_account_recovery');
          final container = _deriveAccountContainer(source);
          addTearDown(container.dispose);
          await container.read(accountProvider.future);

          await expectLater(
            container
                .read(accountProvider.notifier)
                .deriveAccountFromExistingSeed(sourceAccountUuid: source.uuid),
            throwsA(isA<SecureStorageUnavailableException>()),
          );

          expect(rust.allocatedIndices, isEmpty);
          expect(rust.liveAccountIndices, isEmpty);
          expect(
            jsonDecode(storage.values['zcash_accounts']!) as List,
            hasLength(1),
          );

          if (mode == _DerivedAccountWriteFailureMode.persistThenThrow) {
            expect(storage.values['zcash_derived_account_recovery'], isNotNull);
            await container
                .read(accountProvider.notifier)
                .deriveAccountFromExistingSeed(sourceAccountUuid: source.uuid);
            expect(rust.allocatedIndices, [1]);
          }
        },
      );
    }

    test(
      'persists a bootstrapped source seed family before native allocation',
      () async {
        const legacySource = AccountInfo(
          uuid: 'source',
          name: 'Source',
          order: 0,
          isSeedAnchor: true,
        );
        await AppSecureStore.instance.writeString(
          'zcash_accounts',
          jsonEncode([legacySource.toJson()]),
        );
        rust.pauseDerivation();
        final container = _deriveAccountContainer(source);
        addTearDown(container.dispose);
        await container.read(accountProvider.future);

        final derive = container
            .read(accountProvider.notifier)
            .deriveAccountFromExistingSeed(sourceAccountUuid: source.uuid);
        await rust.waitForDerivationStart();
        try {
          final stored =
              (jsonDecode(storage.values['zcash_accounts']!) as List).single
                  as Map<String, dynamic>;
          expect(stored['seedFamilyId'], 'software-family');
          expect(rust.allocatedIndices, isEmpty);
        } finally {
          rust.resumeDerivation();
        }
        await derive;
      },
    );

    test(
      'fences concurrent derive calls before another Rust index is selected',
      () async {
        rust.pauseDerivation();
        final firstContainer = _deriveAccountContainer(source);
        final secondContainer = _deriveAccountContainer(source);
        addTearDown(firstContainer.dispose);
        addTearDown(secondContainer.dispose);
        await firstContainer.read(accountProvider.future);
        await secondContainer.read(accountProvider.future);

        final first = firstContainer
            .read(accountProvider.notifier)
            .deriveAccountFromExistingSeed(sourceAccountUuid: source.uuid);
        await rust.waitForDerivationStart();

        try {
          await expectLater(
            secondContainer
                .read(accountProvider.notifier)
                .deriveAccountFromExistingSeed(sourceAccountUuid: source.uuid),
            throwsA(
              predicate<Object>(
                (error) => error.toString().contains('already in progress'),
                'the process-wide derivation fence',
              ),
            ),
          );
          expect(rust.allocatedIndices, isEmpty);
        } finally {
          rust.resumeDerivation();
        }
        await first;
        expect(rust.allocatedIndices, [1]);
      },
    );

    test('blocks source removal while a derivation fence is live', () async {
      rust.pauseDerivation();
      final firstContainer = _deriveAccountContainer(source);
      final secondContainer = _deriveAccountContainer(source);
      addTearDown(firstContainer.dispose);
      addTearDown(secondContainer.dispose);
      await firstContainer.read(accountProvider.future);
      await secondContainer.read(accountProvider.future);

      final first = firstContainer
          .read(accountProvider.notifier)
          .deriveAccountFromExistingSeed(sourceAccountUuid: source.uuid);
      await rust.waitForDerivationStart();
      try {
        await expectLater(
          secondContainer
              .read(accountProvider.notifier)
              .removeAccount(source.uuid),
          throwsA(
            predicate<Object>(
              (error) => error.toString().contains('in-progress software'),
              'a live native derivation lease blocks destructive removal',
            ),
          ),
        );
        expect(storage.values['zcash_derived_account_recovery'], isNotNull);
        expect(
          secondContainer
              .read(accountProvider)
              .requireValue
              .accounts
              .single
              .uuid,
          source.uuid,
        );
      } finally {
        rust.resumeDerivation();
      }
      await first;
    });

    test('blocks full reset while a derivation lease is live', () async {
      rust.pauseDerivation();
      final firstContainer = _deriveAccountContainer(source);
      final secondContainer = _deriveAccountContainer(source);
      addTearDown(firstContainer.dispose);
      addTearDown(secondContainer.dispose);
      await firstContainer.read(accountProvider.future);
      await secondContainer.read(accountProvider.future);

      final first = firstContainer
          .read(accountProvider.notifier)
          .deriveAccountFromExistingSeed(sourceAccountUuid: source.uuid);
      await rust.waitForDerivationStart();
      try {
        await expectLater(
          secondContainer.read(accountProvider.notifier).resetWallet(),
          throwsA(
            predicate<Object>(
              (error) => error.toString().contains('already in progress'),
              'a live native derivation lease blocks full reset',
            ),
          ),
        );
        expect(storage.values['zcash_accounts'], isNotNull);
        expect(storage.values['zcash_derived_account_recovery'], isNotNull);
      } finally {
        rust.resumeDerivation();
      }
      await first;
    });

    test(
      'blocks source removal when a crashed derivation left a fence',
      () async {
        await AppSecureStore.instance.writeString(
          'zcash_derived_account_recovery',
          _v3RecoveryFenceJson(
            sourceAccountUuid: source.uuid,
            operationToken: 'recovery-token',
            name: 'Recovered',
            profilePictureId: 'pfp-01',
            accountGroupName: null,
          ),
        );
        final container = _deriveAccountContainer(source);
        addTearDown(container.dispose);
        await container.read(accountProvider.future);

        await expectLater(
          container.read(accountProvider.notifier).removeAccount(source.uuid),
          throwsA(
            predicate<Object>(
              (error) => error.toString().contains(
                'pending software account recovery',
              ),
              'the persisted fence protects source secret and metadata',
            ),
          ),
        );
        expect(storage.values['zcash_derived_account_recovery'], isNotNull);
        expect(
          container.read(accountProvider).requireValue.accounts.single.uuid,
          source.uuid,
        );
      },
    );

    test(
      'legacy v2 recovery fence remains a barrier after native resume',
      () async {
        final rawFence = _recoveryFenceJson(sourceAccountUuid: source.uuid);
        await AppSecureStore.instance.writeString(
          'zcash_derived_account_recovery',
          rawFence,
        );

        // Each iteration models a crash immediately after native resume: the
        // OS lock is released but neither the durable Dart fence nor native
        // pending record is resolved. They must retain one shared token.
        for (var restart = 1; restart <= 2; restart++) {
          final resumed = await rust
              .crateApiWalletResumeSoftwareAccountDerivationLease(
                dbPath: '/private/tmp/vizor-account-provider-test/wallet.db',
                previousOperationToken: 'recovery-token',
              );
          expect(
            resumed.operationToken,
            'recovery-token',
            reason: 'restart $restart must not rotate the persisted token',
          );
          await rust.crateApiWalletFinishSoftwareAccountDerivationLease(
            operationToken: resumed.operationToken,
          );
          expect(storage.values['zcash_derived_account_recovery'], rawFence);
        }

        final container = _deriveAccountContainer(source);
        addTearDown(container.dispose);
        await container.read(accountProvider.future);

        await expectLater(
          container
              .read(accountProvider.notifier)
              .deriveAccountFromExistingSeed(sourceAccountUuid: source.uuid),
          throwsA(
            predicate<Object>(
              (error) => error.toString().contains('cannot prove its exact'),
              'older fences do not authenticate nullable presentation intent',
            ),
          ),
        );

        expect(rust.allocatedIndices, isEmpty);
        expect(storage.values['zcash_derived_account_recovery'], rawFence);
      },
    );

    test(
      'restart claims a native pending operation that crashed before its first Dart fence',
      () async {
        final lease = await rust
            .crateApiWalletBeginSoftwareAccountDerivationLease(
              dbPath: '/private/tmp/vizor-account-provider-test/wallet.db',
              network: 'main',
              sourceAccountUuid: source.uuid,
              recoveryName: 'Exact crash intent',
              recoveryProfilePictureId: 'pfp-02',
              recoveryAccountGroupName: 'Exact group',
            );
        // Model process death immediately after native begin: no secure-store
        // fence exists and the OS lease is released.
        await rust.crateApiWalletFinishSoftwareAccountDerivationLease(
          operationToken: lease.operationToken,
        );
        expect(storage.values['zcash_derived_account_recovery'], isNull);

        final container = _deriveAccountContainer(source);
        addTearDown(container.dispose);
        await container.read(accountProvider.future);
        await container
            .read(accountProvider.notifier)
            .deriveAccountFromExistingSeed(
              sourceAccountUuid: source.uuid,
              name: 'Untrusted retry name',
              profilePictureId: 'pfp-03',
            );

        final state = container.read(accountProvider).requireValue;
        expect(state.accounts, hasLength(2));
        expect(state.accounts.last.name, 'Exact crash intent');
        expect(state.accounts.last.profilePictureId, 'pfp-02');
        expect(state.accounts.last.accountGroupName, 'Exact group');
        expect(storage.values['zcash_derived_account_recovery'], isNull);
        expect(rust.allocatedIndices, [1]);
      },
    );

    test(
      'fails closed when a pending fence sees a foreign seed-family delta',
      () async {
        const foreign = AccountInfo(
          uuid: 'foreign-1',
          name: 'Foreign',
          order: 1,
          isSeedAnchor: false,
          seedFamilyId: 'foreign-family',
        );
        await AppSecureStore.instance.writeString(
          'zcash_derived_account_recovery',
          _v3RecoveryFenceJson(
            sourceAccountUuid: source.uuid,
            operationToken: 'recovery-token',
            name: 'Recovered',
            profilePictureId: 'pfp-01',
            accountGroupName: null,
          ),
        );
        rust.addListedAccount(foreign);
        final container = _deriveAccountContainer(source);
        addTearDown(container.dispose);
        await container.read(accountProvider.future);

        await expectLater(
          container
              .read(accountProvider.notifier)
              .deriveAccountFromExistingSeed(sourceAccountUuid: source.uuid),
          throwsA(isA<StateError>()),
        );
        expect(rust.allocatedIndices, isEmpty);
        expect(storage.values['zcash_derived_account_recovery'], isNotNull);
      },
    );

    test(
      'fails closed when a pending fence sees multiple Rust deltas',
      () async {
        const first = AccountInfo(
          uuid: 'derived-1',
          name: 'One',
          order: 1,
          isSeedAnchor: true,
          seedFamilyId: 'software-family',
        );
        const second = AccountInfo(
          uuid: 'derived-2',
          name: 'Two',
          order: 2,
          isSeedAnchor: true,
          seedFamilyId: 'software-family',
        );
        await AppSecureStore.instance.writeString(
          'zcash_derived_account_recovery',
          _v3RecoveryFenceJson(
            sourceAccountUuid: source.uuid,
            operationToken: 'recovery-token',
            name: 'Recovered',
            profilePictureId: 'pfp-01',
            accountGroupName: null,
          ),
        );
        rust
          ..addListedAccount(first)
          ..addListedAccount(second);
        final container = _deriveAccountContainer(source);
        addTearDown(container.dispose);
        await container.read(accountProvider.future);

        await expectLater(
          container
              .read(accountProvider.notifier)
              .deriveAccountFromExistingSeed(sourceAccountUuid: source.uuid),
          throwsA(isA<StateError>()),
        );
        expect(rust.allocatedIndices, isEmpty);
        expect(storage.values['zcash_derived_account_recovery'], isNotNull);
      },
    );

    test(
      'acknowledgement requires durable metadata after bootstrap restores state',
      () async {
        const derived = AccountInfo(
          uuid: 'derived-1',
          name: 'Recovered',
          order: 1,
          isSeedAnchor: true,
          seedFamilyId: 'software-family',
        );
        await AppSecureStore.instance.writeAccountMnemonic(
          derived.uuid,
          'source recovery phrase',
        );
        await AppSecureStore.instance.writeString(
          'zcash_derived_account_recovery',
          derived.uuid,
        );
        final container = _deriveAccountContainer(
          source,
          bootstrapAccounts: [source, derived],
        );
        addTearDown(container.dispose);
        await container.read(accountProvider.future);

        await expectLater(
          container
              .read(accountProvider.notifier)
              .acknowledgeDerivedAccountRecovery(),
          throwsA(isA<StateError>()),
        );
        expect(storage.values['zcash_derived_account_recovery'], isNotNull);
      },
    );

    test(
      'acknowledgement rejects a tampered v3 presentation fence before reconciliation',
      () async {
        final lease = await rust
            .crateApiWalletBeginSoftwareAccountDerivationLease(
              dbPath: '/private/tmp/vizor-account-provider-test/wallet.db',
              network: 'main',
              sourceAccountUuid: source.uuid,
              recoveryName: 'Native name',
              recoveryProfilePictureId: 'pfp-02',
              recoveryAccountGroupName: 'Native group',
            );
        await rust.crateApiWalletFinishSoftwareAccountDerivationLease(
          operationToken: lease.operationToken,
        );
        final rawFence = _v3RecoveryFenceJson(
          sourceAccountUuid: source.uuid,
          operationToken: lease.operationToken,
          name: 'Tampered name',
          profilePictureId: 'pfp-02',
          accountGroupName: 'Native group',
        );
        await AppSecureStore.instance.writeString(
          'zcash_derived_account_recovery',
          rawFence,
        );
        final container = _deriveAccountContainer(source);
        addTearDown(container.dispose);
        await container.read(accountProvider.future);

        await expectLater(
          container
              .read(accountProvider.notifier)
              .acknowledgeDerivedAccountRecovery(),
          throwsA(
            predicate<Object>(
              (error) =>
                  error.toString().contains('presentation does not match'),
              'the exact native-vs-Dart intent assertion',
            ),
          ),
        );
        expect(storage.values['zcash_derived_account_recovery'], rawFence);
        expect(rust.allocatedIndices, isEmpty);
      },
    );

    test(
      'v3 null account group cannot be forged as a non-null wildcard',
      () async {
        final lease = await rust
            .crateApiWalletBeginSoftwareAccountDerivationLease(
              dbPath: '/private/tmp/vizor-account-provider-test/wallet.db',
              network: 'main',
              sourceAccountUuid: source.uuid,
              recoveryName: 'Native name',
              recoveryProfilePictureId: 'pfp-02',
              recoveryAccountGroupName: null,
            );
        await rust.crateApiWalletFinishSoftwareAccountDerivationLease(
          operationToken: lease.operationToken,
        );
        final rawFence = _v3RecoveryFenceJson(
          sourceAccountUuid: source.uuid,
          operationToken: lease.operationToken,
          name: 'Native name',
          profilePictureId: 'pfp-02',
          accountGroupName: 'Forged group',
        );
        await AppSecureStore.instance.writeString(
          'zcash_derived_account_recovery',
          rawFence,
        );
        final container = _deriveAccountContainer(source);
        addTearDown(container.dispose);
        await container.read(accountProvider.future);

        await expectLater(
          container
              .read(accountProvider.notifier)
              .acknowledgeDerivedAccountRecovery(),
          throwsA(isA<StateError>()),
        );
        expect(storage.values['zcash_derived_account_recovery'], rawFence);
      },
    );

    test(
      'v2 native-null group cannot be forged as a non-null wildcard',
      () async {
        final lease = await rust
            .crateApiWalletBeginSoftwareAccountDerivationLease(
              dbPath: '/private/tmp/vizor-account-provider-test/wallet.db',
              network: 'main',
              sourceAccountUuid: source.uuid,
              recoveryName: 'Native name',
              recoveryProfilePictureId: 'pfp-02',
              recoveryAccountGroupName: null,
            );
        await rust.crateApiWalletFinishSoftwareAccountDerivationLease(
          operationToken: lease.operationToken,
        );
        final rawFence = jsonEncode({
          'version': 2,
          'sourceAccountUuid': source.uuid,
          'name': 'Native name',
          'profilePictureId': 'pfp-02',
          'accountGroupName': 'Forged group',
          'baselineAccountUuids': [source.uuid],
          'operationToken': lease.operationToken,
        });
        await AppSecureStore.instance.writeString(
          'zcash_derived_account_recovery',
          rawFence,
        );
        final container = _deriveAccountContainer(source);
        addTearDown(container.dispose);
        await container.read(accountProvider.future);

        await expectLater(
          container
              .read(accountProvider.notifier)
              .acknowledgeDerivedAccountRecovery(),
          throwsA(
            predicate<Object>(
              (error) => error.toString().contains('cannot prove its exact'),
              'a v2 fence cannot authenticate a nullable group name',
            ),
          ),
        );
        expect(storage.values['zcash_derived_account_recovery'], rawFence);
        expect(rust.allocatedIndices, isEmpty);
      },
    );

    test(
      'hardware derive source never begins a native lease or writes a fence',
      () async {
        const hardware = AccountInfo(
          uuid: 'hardware-source',
          name: 'Keystone',
          order: 0,
          isHardware: true,
        );
        final container = _deriveAccountContainer(hardware);
        addTearDown(container.dispose);
        await container.read(accountProvider.future);

        await expectLater(
          container
              .read(accountProvider.notifier)
              .deriveAccountFromExistingSeed(sourceAccountUuid: hardware.uuid),
          throwsA(isA<ArgumentError>()),
        );
        expect(rust.beginCalls, 0);
        expect(storage.values['zcash_derived_account_recovery'], isNull);
        expect(rust.allocatedIndices, isEmpty);
      },
    );

    test(
      'restart acknowledgement clears a resolved no-delta v3 fence and later derive progresses',
      () async {
        final lease = await rust
            .crateApiWalletBeginSoftwareAccountDerivationLease(
              dbPath: '/private/tmp/vizor-account-provider-test/wallet.db',
              network: 'main',
              sourceAccountUuid: source.uuid,
              recoveryName: 'No delta',
              recoveryProfilePictureId: 'pfp-02',
              recoveryAccountGroupName: null,
            );
        final rawFence = _v3RecoveryFenceJson(
          sourceAccountUuid: source.uuid,
          operationToken: lease.operationToken,
          name: 'No delta',
          profilePictureId: 'pfp-02',
          accountGroupName: null,
        );
        await AppSecureStore.instance.writeString(
          'zcash_derived_account_recovery',
          rawFence,
        );
        // Model a crash after native resolution proves the baseline still has
        // no delta, but before Dart can remove its matching fence.
        await rust.crateApiWalletResolveSoftwareAccountDerivationLease(
          operationToken: lease.operationToken,
        );
        await rust.crateApiWalletFinishSoftwareAccountDerivationLease(
          operationToken: lease.operationToken,
        );

        final container = _deriveAccountContainer(source);
        addTearDown(container.dispose);
        await container.read(accountProvider.future);
        await container
            .read(accountProvider.notifier)
            .acknowledgeDerivedAccountRecovery();

        expect(storage.values['zcash_derived_account_recovery'], isNull);
        await container
            .read(accountProvider.notifier)
            .deriveAccountFromExistingSeed(sourceAccountUuid: source.uuid);
        expect(rust.allocatedIndices, [1]);
      },
    );

    test(
      'legacy raw UUID fence never publishes or clears without provenance',
      () async {
        const derived = AccountInfo(
          uuid: 'derived-1',
          name: 'Legacy candidate',
          order: 1,
          isSeedAnchor: true,
          seedFamilyId: 'software-family',
        );
        await AppSecureStore.instance.writeAccountMnemonic(
          derived.uuid,
          'source recovery phrase',
        );
        await AppSecureStore.instance.writeString(
          'zcash_accounts',
          jsonEncode([source.toJson(), derived.toJson()]),
        );
        await AppSecureStore.instance.writeString(
          'zcash_active_account',
          source.uuid,
        );
        await AppSecureStore.instance.writeString(
          'zcash_derived_account_recovery',
          derived.uuid,
        );
        rust.addListedAccount(derived);
        final container = _deriveAccountContainer(source);
        addTearDown(container.dispose);
        await container.read(accountProvider.future);

        await expectLater(
          container
              .read(accountProvider.notifier)
              .acknowledgeDerivedAccountRecovery(),
          throwsA(
            predicate<Object>(
              (error) => error.toString().contains('cannot prove its origin'),
              'legacy recovery remains fail-closed',
            ),
          ),
        );
        expect(storage.values['zcash_derived_account_recovery'], derived.uuid);
        expect(
          container.read(accountProvider).requireValue.activeAccountUuid,
          source.uuid,
        );
      },
    );

    test(
      'derive retry reconciles a durable fence before allocating another index',
      () async {
        const derived = AccountInfo(
          uuid: 'derived-1',
          name: 'Recovered',
          order: 1,
          isSeedAnchor: true,
          seedFamilyId: 'software-family',
        );
        await AppSecureStore.instance.writeAccountMnemonic(
          derived.uuid,
          'source recovery phrase',
        );
        await AppSecureStore.instance.writeString(
          'zcash_accounts',
          jsonEncode([source.toJson(), derived.toJson()]),
        );
        await AppSecureStore.instance.writeString(
          'zcash_active_account',
          derived.uuid,
        );
        await AppSecureStore.instance.writeString(
          'zcash_derived_account_recovery',
          _v3RecoveryFenceJson(
            sourceAccountUuid: source.uuid,
            operationToken: 'recovery-token',
            name: 'Recovered',
            profilePictureId: 'pfp-01',
            accountGroupName: null,
          ),
        );
        rust.addListedAccount(derived);
        final container = _deriveAccountContainer(source);
        addTearDown(container.dispose);
        await container.read(accountProvider.future);

        await container
            .read(accountProvider.notifier)
            .deriveAccountFromExistingSeed(sourceAccountUuid: source.uuid);

        expect(rust.allocatedIndices, isEmpty);
        expect(storage.values['zcash_derived_account_recovery'], isNull);
        final stateAfterRecovery = container.read(accountProvider).requireValue;
        expect(stateAfterRecovery.accounts, hasLength(2));
        expect(stateAfterRecovery.activeAccountUuid, derived.uuid);
      },
    );

    test(
      'surfaces original and cleanup failures when recovery reconciliation fails',
      () async {
        storage.failWrites(
          _DerivedAccountWriteBoundary.accounts.storageKey,
          count: 2,
        );
        rust.failNextDelete = true;
        final container = _deriveAccountContainer(source);
        addTearDown(container.dispose);
        await container.read(accountProvider.future);

        await expectLater(
          container
              .read(accountProvider.notifier)
              .deriveAccountFromExistingSeed(sourceAccountUuid: source.uuid),
          throwsA(
            predicate<Object>(
              (error) =>
                  error.toString().contains('Derived account compensation') &&
                  error.toString().contains('zcash_accounts') &&
                  error.toString().contains('forced Rust delete failure'),
              'an error reporting both original and cleanup failures',
            ),
          ),
        );
        final stateAfterFailure = container.read(accountProvider).requireValue;
        expect(stateAfterFailure.accounts, hasLength(1));
        expect(stateAfterFailure.accounts.single.uuid, source.uuid);
        expect(stateAfterFailure.activeAccountUuid, source.uuid);
        expect(
          storage.values['zcash_derived_account_recovery'],
          contains('"baselineAccountUuids"'),
        );
        expect(rust.liveAccountIndices, {1});
        final retainedSecret = await container
            .read(accountProvider.notifier)
            .getSoftwareWalletSecretForAccount('derived-1');
        expect(retainedSecret?.mnemonic, 'source recovery phrase');

        await container
            .read(accountProvider.notifier)
            .deriveAccountFromExistingSeed(sourceAccountUuid: source.uuid);
        expect(storage.values['zcash_derived_account_recovery'], isNull);
        expect(
          container.read(accountProvider).requireValue.accounts,
          hasLength(2),
        );
        expect(rust.allocatedIndices, [1]);
      },
    );

    test(
      'retains a complete recovered account and blocks blind retry when Rust deletion fails',
      () async {
        storage.persistThenThrowNextWriteFor =
            _DerivedAccountWriteBoundary.accounts.storageKey;
        rust.failNextDelete = true;
        final container = _deriveAccountContainer(source);
        addTearDown(container.dispose);
        await container.read(accountProvider.future);

        await expectLater(
          container
              .read(accountProvider.notifier)
              .deriveAccountFromExistingSeed(sourceAccountUuid: source.uuid),
          throwsA(
            predicate<Object>(
              (error) =>
                  error.toString().contains('Derived account recovered') &&
                  error.toString().contains('zcash_accounts') &&
                  error.toString().contains('forced Rust delete failure'),
              'a recovery error retaining the original and Rust-delete causes',
            ),
          ),
        );

        expect(rust.liveAccountIndices, {1});
        final persistedSecret = await container
            .read(accountProvider.notifier)
            .getSoftwareWalletSecretForAccount('derived-1');
        expect(persistedSecret?.mnemonic, 'source recovery phrase');
        expect(persistedSecret?.bip39Passphrase, isEmpty);
        expect(
          jsonDecode(storage.values['zcash_accounts']!) as List,
          hasLength(2),
        );
        expect(storage.values['zcash_active_account'], 'derived-1');
        expect(
          storage.values['zcash_derived_account_recovery'],
          contains('"baselineAccountUuids"'),
        );
        final stateAfterRecovery = container.read(accountProvider).requireValue;
        expect(stateAfterRecovery.accounts, hasLength(2));
        expect(stateAfterRecovery.activeAccountUuid, 'derived-1');

        await container
            .read(accountProvider.notifier)
            .deriveAccountFromExistingSeed(sourceAccountUuid: source.uuid);
        expect(rust.allocatedIndices, [1]);
        expect(storage.values['zcash_derived_account_recovery'], isNull);

        await container
            .read(accountProvider.notifier)
            .acknowledgeDerivedAccountRecovery();

        await container
            .read(accountProvider.notifier)
            .deriveAccountFromExistingSeed(sourceAccountUuid: source.uuid);
        expect(rust.allocatedIndices, [1, 2]);
        expect(rust.liveAccountIndices, {1, 2});
      },
    );
  });

  test(
    'wallet reset clears the tor data directory and route preference',
    () async {
      SharedPreferences.setMockInitialValues({kTorEnabledPreferenceKey: true});
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      final torDirectory = Directory.systemTemp.createTempSync(
        'vizor-tor-reset',
      );
      addTearDown(() {
        if (torDirectory.existsSync()) torDirectory.deleteSync(recursive: true);
      });
      File(
        '${torDirectory.path}${Platform.pathSeparator}state.json',
      ).writeAsStringSync('{}');
      var directoryExistedWhenRouteSwitched = false;

      await clearTorPrivacyStateForReset(
        switchRouteToDirect: () async {
          directoryExistedWhenRouteSwitched = torDirectory.existsSync();
        },
        resolveTorDirectory: () async => torDirectory.path,
      );

      expect(directoryExistedWhenRouteSwitched, isTrue);
      expect(torDirectory.existsSync(), isFalse);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool(kTorEnabledPreferenceKey), isNull);
    },
  );

  test(
    'wallet reset keeps the tor directory when the route stays on tor',
    () async {
      SharedPreferences.setMockInitialValues({kTorEnabledPreferenceKey: true});
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      final torDirectory = Directory.systemTemp.createTempSync(
        'vizor-tor-reset',
      );
      addTearDown(() {
        if (torDirectory.existsSync()) torDirectory.deleteSync(recursive: true);
      });

      await clearTorPrivacyStateForReset(
        switchRouteToDirect: () async => throw StateError('tor still running'),
        resolveTorDirectory: () async => torDirectory.path,
      );

      expect(torDirectory.existsSync(), isTrue);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool(kTorEnabledPreferenceKey), isNull);
    },
  );

  test('wallet reset survives tor cleanup failures', () async {
    final torDirectory = Directory.systemTemp.createTempSync('vizor-tor-reset');
    addTearDown(() {
      if (torDirectory.existsSync()) torDirectory.deleteSync(recursive: true);
    });

    await clearTorPrivacyStateForReset(
      switchRouteToDirect: () async {},
      resolveTorDirectory: () async => torDirectory.path,
      openPreferences: () async => throw StateError('preferences unavailable'),
    );

    expect(torDirectory.existsSync(), isFalse);
  });

  test('wallet link duplicate import errors are recognized', () {
    expect(
      isWalletLinkDuplicateImportError(
        Exception('This account is already in your wallet.'),
      ),
      isTrue,
    );
    expect(
      isWalletLinkDuplicateImportError(
        const _FakeAnyhowException(
          'This Keystone account is already in your wallet.',
        ),
      ),
      isTrue,
    );
    expect(
      isWalletLinkDuplicateImportError(
        const _FakeAnyhowException(
          'Failed to import account: An account corresponding to the data '
          'provided already exists in the wallet with UUID '
          '00000000-0000-0000-0000-000000000000.',
        ),
      ),
      isTrue,
    );
    expect(
      isWalletLinkDuplicateImportError(Exception('Failed to parse UFVK.')),
      isFalse,
    );
  });

  test(
    'wallet link import rejects cross-network links before fresh wallet import',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        ],
      );
      addTearDown(container.dispose);

      await container.read(accountProvider.future);

      await expectLater(
        container
            .read(accountProvider.notifier)
            .importLinkedWalletAccounts(
              network: 'test',
              accountsToImport: const [
                LinkedWalletAccountImport(
                  name: 'Testnet account',
                  birthdayHeight: 280000,
                  zip32AccountIndex: 0,
                  isHardware: false,
                  isSeedAnchor: true,
                  mnemonic: 'abandon abandon abandon abandon abandon abandon',
                ),
              ],
            ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Linked wallet network does not match the current app network.',
          ),
        ),
      );

      expect(container.read(accountProvider).value?.accounts, isEmpty);
    },
  );

  test(
    'next active account stays unchanged when removing a non-active account',
    () {
      const accounts = [
        AccountInfo(uuid: 'account-1', name: 'Primary', order: 0),
        AccountInfo(uuid: 'account-2', name: 'Savings', order: 1),
        AccountInfo(uuid: 'account-3', name: 'Travel', order: 2),
      ];
      const previous = AccountState(
        accounts: accounts,
        activeAccountUuid: 'account-1',
      );

      final next = resolveNextActiveAccountUuidAfterRemoval(
        previousState: previous,
        removedAccount: accounts[1],
        remainingAccounts: [accounts[0], accounts[2].copyWith(order: 1)],
      );

      expect(next, 'account-1');
    },
  );

  test(
    'next active account clamps removed active index into remaining list',
    () {
      const removed = AccountInfo(uuid: 'account-3', name: 'Travel', order: 99);
      const remaining = [
        AccountInfo(uuid: 'account-1', name: 'Primary', order: 0),
        AccountInfo(uuid: 'account-2', name: 'Savings', order: 1),
      ];
      const previous = AccountState(
        accounts: [...remaining, removed],
        activeAccountUuid: 'account-3',
      );

      final next = resolveNextActiveAccountUuidAfterRemoval(
        previousState: previous,
        removedAccount: removed,
        remainingAccounts: remaining,
      );

      expect(next, 'account-2');
    },
  );

  test(
    'destructive account mutations are rejected while voting submission is guarded',
    () async {
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrapWithAccounts()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(accountProvider.future);
      final guard = container
          .read(votingSubmissionGuardProvider.notifier)
          .acquire(accountUuid: 'account-1', roundId: 'round-1');

      await expectLater(
        container.read(accountProvider.notifier).removeAccount('account-2'),
        throwsA(isA<VotingSubmissionInProgressException>()),
      );
      await expectLater(
        container.read(accountProvider.notifier).resetWallet(),
        throwsA(isA<VotingSubmissionInProgressException>()),
      );

      final state = container.read(accountProvider).value!;
      expect(state.activeAccountUuid, 'account-1');
      expect(state.accounts, hasLength(2));

      container.read(votingSubmissionGuardProvider.notifier).release(guard);
    },
  );

  test(
    'account switching is allowed while voting submission is guarded',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrapWithAccounts()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(accountProvider.future);
      final guard = container
          .read(votingSubmissionGuardProvider.notifier)
          .acquire(accountUuid: 'account-1', roundId: 'round-1');

      await container.read(accountProvider.notifier).switchAccount('account-2');

      final state = container.read(accountProvider).value!;
      expect(state.activeAccountUuid, 'account-2');
      expect(state.accounts, hasLength(2));

      container.read(votingSubmissionGuardProvider.notifier).release(guard);
    },
  );

  test('voting submission guard tracks multiple active jobs', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(votingSubmissionGuardProvider.notifier);
    final first = notifier.acquire(
      accountUuid: 'account-1',
      roundId: 'round-1',
    );
    final second = notifier.acquire(
      accountUuid: 'account-2',
      roundId: 'round-2',
    );

    expect(container.read(votingSubmissionGuardProvider), [first, second]);
    expect(notifier.guardForAccount('account-2'), same(second));
  });

  test('voting submission guard keeps nested acquisitions active', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(votingSubmissionGuardProvider.notifier);
    final first = notifier.acquire(
      accountUuid: 'account-1',
      roundId: 'round-1',
    );
    final second = notifier.acquire(
      accountUuid: 'account-1',
      roundId: 'round-1',
    );

    expect(first.token, isNot(second.token));
    expect(container.read(votingSubmissionGuardProvider), [first, second]);

    notifier.release(first);

    expect(
      notifier.isGuarded(accountUuid: 'account-1', roundId: 'round-1'),
      isTrue,
    );
    expect(container.read(votingSubmissionGuardProvider), [second]);

    notifier.release(second);

    expect(
      notifier.isGuarded(accountUuid: 'account-1', roundId: 'round-1'),
      isFalse,
    );
    expect(container.read(votingSubmissionGuardProvider), isEmpty);
  });
}

class _FakeAnyhowException implements Exception {
  const _FakeAnyhowException(this.message);

  final String message;

  @override
  String toString() => 'AnyhowException($message)';
}

AppBootstrapState _bootstrapWithAccounts() {
  const accountState = AccountState(
    accounts: [
      AccountInfo(uuid: 'account-1', name: 'Primary', order: 0),
      AccountInfo(uuid: 'account-2', name: 'Keystone', order: 1),
    ],
    activeAccountUuid: 'account-1',
  );
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: accountState,
    initialSyncSnapshot: AppSyncSnapshot.emptyForAccount('account-1'),
    network: kZcashDefaultNetworkName,
    rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}

ProviderContainer _deriveAccountContainer(
  AccountInfo source, {
  List<AccountInfo>? bootstrapAccounts,
}) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        AppBootstrapState(
          initialLocation: '/accounts',
          initialAccountState: AccountState(
            accounts: bootstrapAccounts ?? [source],
            activeAccountUuid: source.uuid,
          ),
          initialSyncSnapshot: AppSyncSnapshot.empty,
          network: 'main',
          rpcEndpointConfig: defaultRpcEndpointConfig('main'),
          themeMode: ThemeMode.system,
          privacyModeEnabled: false,
          isPasswordConfigured: true,
          isUnlocked: true,
          passwordRotationRecoveryFailed: false,
        ),
      ),
      rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue(
        (_) async => BigInt.from(100),
      ),
    ],
  );
}

String _recoveryFenceJson({required String sourceAccountUuid}) => jsonEncode({
  'version': 2,
  'sourceAccountUuid': sourceAccountUuid,
  'name': 'Recovered',
  'profilePictureId': 'pfp-01',
  'baselineAccountUuids': [sourceAccountUuid],
  'operationToken': 'recovery-token',
});

String _v3RecoveryFenceJson({
  required String sourceAccountUuid,
  required String operationToken,
  required String name,
  required String profilePictureId,
  required String? accountGroupName,
}) => jsonEncode({
  'version': 3,
  'sourceAccountUuid': sourceAccountUuid,
  'name': name,
  'profilePictureId': profilePictureId,
  'accountGroupName': accountGroupName,
  'baselineAccountUuids': [sourceAccountUuid],
  'operationToken': operationToken,
});

enum _DerivedAccountWriteBoundary {
  mnemonic('zcash_account_mnemonic_derived-1'),
  accounts('zcash_accounts'),
  activeAccount('zcash_active_account');

  const _DerivedAccountWriteBoundary(this.storageKey);

  final String storageKey;
}

enum _DerivedAccountWriteFailureMode {
  beforePersist,
  persistThenThrow;

  void inject(_FaultInjectingSecureStorage storage, String key) {
    switch (this) {
      case _DerivedAccountWriteFailureMode.beforePersist:
        storage.failNextWriteFor = key;
      case _DerivedAccountWriteFailureMode.persistThenThrow:
        storage.persistThenThrowNextWriteFor = key;
    }
  }
}

class _FaultInjectingSecureStorage extends FlutterSecureStoragePlatform {
  final values = <String, String>{};
  String? failNextWriteFor;
  String? persistThenThrowNextWriteFor;
  final _remainingWriteFailures = <String, int>{};

  void failWrites(String key, {required int count}) {
    _remainingWriteFailures[key] = count;
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => values.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    values.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    values.clear();
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => values[key];

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map<String, String>.from(values);

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    final remainingFailures = _remainingWriteFailures[key] ?? 0;
    if (remainingFailures > 0) {
      _remainingWriteFailures[key] = remainingFailures - 1;
      throw PlatformException(code: 'fault', message: 'forced $key write');
    }
    if (key == failNextWriteFor) {
      failNextWriteFor = null;
      throw PlatformException(code: 'fault', message: 'forced $key write');
    }
    values[key] = value;
    if (key == persistThenThrowNextWriteFor) {
      persistThenThrowNextWriteFor = null;
      throw PlatformException(
        code: 'fault',
        message: 'persisted then forced $key write failure',
      );
    }
  }
}

class _DerivationRustApiFake implements RustLibApi {
  final _occupiedIndices = <int>{0};
  final allocatedIndices = <int>[];
  final _listedAccountsByUuid = <String, rust_wallet.AccountInfo>{};
  Completer<void>? _derivationGate;
  Completer<void>? _derivationStarted;
  bool failNextDelete = false;
  String? _activeLeaseToken;
  String? _activeResetLeaseToken;
  String? _persistentLeaseToken;
  bool _persistentLeaseIsPending = false;
  String? _persistentRecoveryName;
  String? _persistentRecoveryProfilePictureId;
  String? _persistentRecoveryAccountGroupName;
  int _nextLease = 0;

  int get beginCalls => _nextLease;

  Set<int> get liveAccountIndices => {
    for (final index in _occupiedIndices)
      if (index != 0) index,
  };

  void reset() {
    _occupiedIndices
      ..clear()
      ..add(0);
    allocatedIndices.clear();
    _derivationGate = null;
    _derivationStarted = null;
    _activeLeaseToken = null;
    _activeResetLeaseToken = null;
    _persistentLeaseToken = null;
    _persistentLeaseIsPending = false;
    _persistentRecoveryName = null;
    _persistentRecoveryProfilePictureId = null;
    _persistentRecoveryAccountGroupName = null;
    _nextLease = 0;
    _listedAccountsByUuid
      ..clear()
      ..['source'] = const rust_wallet.AccountInfo(
        uuid: 'source',
        name: 'Source',
        unifiedAddress: 'u-source',
        isSeedAnchor: true,
        isHardware: false,
        seedFamilyId: 'software-family',
      );
    failNextDelete = false;
  }

  @override
  Future<rust_wallet.SoftwareAccountDerivationLease>
  crateApiWalletBeginSoftwareAccountDerivationLease({
    required String dbPath,
    required String network,
    required String sourceAccountUuid,
    required String recoveryName,
    required String recoveryProfilePictureId,
    String? recoveryAccountGroupName,
  }) async {
    if (_activeLeaseToken != null || _activeResetLeaseToken != null) {
      throw StateError('A software account derivation is already in progress.');
    }
    if (_persistentLeaseIsPending) {
      throw StateError(
        'A previous software account derivation needs recovery.',
      );
    }
    final token = _activeLeaseToken = 'lease-${++_nextLease}';
    _persistentLeaseToken = token;
    _persistentLeaseIsPending = true;
    _persistentRecoveryName = recoveryName;
    _persistentRecoveryProfilePictureId = recoveryProfilePictureId;
    _persistentRecoveryAccountGroupName = recoveryAccountGroupName;
    return rust_wallet.SoftwareAccountDerivationLease(
      operationToken: token,
      sourceAccountUuid: sourceAccountUuid,
      baselineAccountUuids: _listedAccountsByUuid.keys.toList(),
      recoveryName: recoveryName,
      recoveryProfilePictureId: recoveryProfilePictureId,
      recoveryAccountGroupName: recoveryAccountGroupName,
      isPending: true,
    );
  }

  @override
  Future<rust_wallet.SoftwareAccountDerivationLease>
  crateApiWalletResumeSoftwareAccountDerivationLease({
    required String dbPath,
    required String previousOperationToken,
  }) async {
    if (_activeLeaseToken != null || _activeResetLeaseToken != null) {
      throw StateError('A software account derivation is already in progress.');
    }
    // Existing round-three fixtures have only Dart state; materialize the
    // matching native record so provider tests can focus on Dart recovery.
    if (_persistentLeaseToken == null) {
      _persistentLeaseToken = previousOperationToken;
      _persistentLeaseIsPending = true;
      _persistentRecoveryName = 'Recovered';
      _persistentRecoveryProfilePictureId = 'pfp-01';
      _persistentRecoveryAccountGroupName = null;
    }
    if (_persistentLeaseToken != previousOperationToken) {
      throw StateError('native derivation recovery record cannot authenticate');
    }
    final pending = _persistentLeaseIsPending;
    // The SQLite-backed token identifies the durable operation across process
    // crashes. Reacquiring the OS lease must not rotate it because Dart's
    // fence lives in a different durable store.
    final token = previousOperationToken;
    _activeLeaseToken = token;
    return rust_wallet.SoftwareAccountDerivationLease(
      operationToken: token,
      sourceAccountUuid: 'source',
      baselineAccountUuids: const ['source'],
      recoveryName: _persistentRecoveryName,
      recoveryProfilePictureId: _persistentRecoveryProfilePictureId,
      recoveryAccountGroupName: _persistentRecoveryAccountGroupName,
      isPending: pending,
    );
  }

  @override
  Future<rust_wallet.SoftwareAccountDerivationLease?>
  crateApiWalletClaimPendingSoftwareAccountDerivationLease({
    required String dbPath,
  }) async {
    if (_activeLeaseToken != null || _activeResetLeaseToken != null) {
      throw StateError('A software account derivation is already in progress.');
    }
    if (!_persistentLeaseIsPending || _persistentLeaseToken == null) {
      return null;
    }
    _activeLeaseToken = _persistentLeaseToken;
    return rust_wallet.SoftwareAccountDerivationLease(
      operationToken: _persistentLeaseToken!,
      sourceAccountUuid: 'source',
      baselineAccountUuids: const ['source'],
      recoveryName: _persistentRecoveryName,
      recoveryProfilePictureId: _persistentRecoveryProfilePictureId,
      recoveryAccountGroupName: _persistentRecoveryAccountGroupName,
      isPending: true,
    );
  }

  @override
  Future<void> crateApiWalletResolveSoftwareAccountDerivationLease({
    required String operationToken,
    String? accountUuid,
  }) async {
    if (_activeLeaseToken != operationToken ||
        _persistentLeaseToken != operationToken) {
      throw StateError('native derivation recovery record cannot authenticate');
    }
    _persistentLeaseIsPending = false;
  }

  @override
  Future<void> crateApiWalletFinishSoftwareAccountDerivationLease({
    required String operationToken,
  }) async {
    if (_activeLeaseToken != operationToken) {
      throw StateError(
        'Software account derivation operation is no longer owned.',
      );
    }
    _activeLeaseToken = null;
  }

  @override
  Future<bool> crateApiWalletIsSoftwareAccountDerivationLocked({
    required String dbPath,
  }) async => _activeLeaseToken != null || _activeResetLeaseToken != null;

  @override
  Future<String> crateApiWalletBeginWalletResetLease({
    required String dbPath,
  }) async {
    if (_activeLeaseToken != null || _activeResetLeaseToken != null) {
      throw StateError('A software account derivation is already in progress.');
    }
    return _activeResetLeaseToken = 'reset-lease';
  }

  @override
  Future<void> crateApiWalletFinishWalletResetLease({
    required String operationToken,
  }) async {
    if (_activeResetLeaseToken != operationToken) {
      throw StateError('Wallet reset operation is no longer owned.');
    }
    _activeResetLeaseToken = null;
  }

  void pauseDerivation() {
    _derivationGate = Completer<void>();
    _derivationStarted = Completer<void>();
  }

  Future<void> waitForDerivationStart() => _derivationStarted!.future;

  void resumeDerivation() => _derivationGate?.complete();

  void addListedAccount(AccountInfo account) {
    _listedAccountsByUuid[account.uuid] = rust_wallet.AccountInfo(
      uuid: account.uuid,
      name: account.name,
      unifiedAddress: 'u-${account.uuid}',
      isSeedAnchor: account.isSeedAnchor,
      isHardware: account.isHardware,
      seedFamilyId: account.seedFamilyId,
    );
  }

  @override
  Future<rust_wallet.SoftwareWalletImportAccount>
  crateApiWalletDeriveNextSoftwareAccount({
    required String mnemonic,
    required String bip39Passphrase,
    BigInt? birthdayHeight,
    required String network,
    required String dbPath,
    required String name,
    required String operationToken,
  }) async {
    if (_activeLeaseToken != operationToken) {
      throw StateError(
        'Software account derivation operation is no longer owned.',
      );
    }
    _derivationStarted?.complete();
    await _derivationGate?.future;
    final index = Iterable<int>.generate(
      1 << 16,
    ).firstWhere((candidate) => !_occupiedIndices.contains(candidate));
    _occupiedIndices.add(index);
    allocatedIndices.add(index);
    final result = rust_wallet.SoftwareWalletImportAccount(
      accountUuid: 'derived-$index',
      unifiedAddress: 'u-derived-$index',
      zip32AccountIndex: index,
      name: name,
      isSeedAnchor: true,
      seedFamilyId: 'software-family',
    );
    _listedAccountsByUuid[result.accountUuid] = rust_wallet.AccountInfo(
      uuid: result.accountUuid,
      name: result.name,
      unifiedAddress: result.unifiedAddress,
      isSeedAnchor: result.isSeedAnchor,
      isHardware: false,
      seedFamilyId: result.seedFamilyId,
    );
    return result;
  }

  @override
  Future<List<rust_wallet.AccountInfo>> crateApiWalletListAccounts({
    required String dbPath,
    required String network,
  }) async => _listedAccountsByUuid.values.toList();

  @override
  Future<void> crateApiWalletDeleteAccount({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async {
    if (_activeLeaseToken != null) {
      throw StateError(
        'Finish the in-progress software account creation before removing an account.',
      );
    }
    await _deleteAccount(accountUuid);
  }

  @override
  Future<void> crateApiWalletDeleteAccountUnderSoftwareAccountDerivationLease({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String operationToken,
  }) async {
    if (_activeLeaseToken != operationToken) {
      throw StateError(
        'Software account derivation operation is no longer owned.',
      );
    }
    await _deleteAccount(accountUuid);
  }

  Future<void> _deleteAccount(String accountUuid) async {
    if (failNextDelete) {
      failNextDelete = false;
      throw StateError('forced Rust delete failure');
    }
    final index = int.tryParse(accountUuid.replaceFirst('derived-', ''));
    if (index != null) _occupiedIndices.remove(index);
    _listedAccountsByUuid.remove(accountUuid);
  }

  @override
  Future<Uint8List> crateApiSecretDecryptSecretPayload({
    required String payloadJson,
    required String password,
    required String saltBase64,
  }) async {
    final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
    return Uint8List.fromList(base64Decode(payload['c'] as String));
  }

  @override
  Future<String> crateApiSecretEncryptSecretPayload({
    required List<int> plainBytes,
    required String password,
    required String saltBase64,
  }) async => jsonEncode({
    'v': 1,
    'n': base64Encode([0]),
    'c': base64Encode(plainBytes),
    'm': base64Encode([0]),
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
