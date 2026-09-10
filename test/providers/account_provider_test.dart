// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_lifecycle_registry_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_share_tracking_registry_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_guard_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

final _rustApi = _AccountMutationRustApiFake();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => RustLib.initMock(api: _rustApi));
  tearDownAll(RustLib.dispose);
  setUp(_rustApi.reset);

  group('account switch locking', () {
    late ProviderContainer container;
    late AccountNotifier accounts;
    late Directory supportDirectory;
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      supportDirectory = await Directory.systemTemp.createTemp(
        'vizor-switch-lock-',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            pathProvider,
            (_) async => supportDirectory.path,
          );
      container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrapWithAccounts()),
          appSecurityProvider.overrideWith(_SwitchTestSecurityNotifier.new),
        ],
      );
      await container.read(accountProvider.future);
      accounts = container.read(accountProvider.notifier);
    });

    tearDown(() async {
      container.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null);
      await supportDirectory.delete(recursive: true);
    });

    test('an already locked wallet does not start an account switch', () async {
      container.read(appSecurityProvider.notifier).lock();
      await accounts.switchAccount('account-2');
      expect(_rustApi.requestedAccounts, isEmpty);
      expect(
        container.read(accountProvider).value!.activeAccountUuid,
        'account-1',
      );
      expect(
        await const FlutterSecureStorage().read(key: 'zcash_active_account'),
        isNull,
      );
    });

    test('an unlocked switch resolves the selected account address', () async {
      await accounts.switchAccount('account-2');
      expect(
        container.read(accountProvider).value!.activeAccountUuid,
        'account-2',
      );
      expect(
        container.read(accountProvider).value!.activeAddress,
        'u1account-2-address',
      );
    });

    for (final lookupFails in [false, true]) {
      test(
        'locking during lookup keeps the selected account without an address (failure: $lookupFails)',
        () async {
          _rustApi.lookupGate = Completer<String>();
          final switching = accounts.switchAccount('account-2');
          await _rustApi.lookupStarted.future;
          container.read(appSecurityProvider.notifier).lock();
          accounts.clearSensitiveStateForLock();
          if (lookupFails) {
            _rustApi.lookupGate!.completeError(
              StateError('address lookup failed'),
            );
          } else {
            _rustApi.lookupGate!.complete('u1account-2-address');
          }
          await switching;
          final state = container.read(accountProvider).value!;
          expect(container.read(appSecurityProvider).requiresUnlock, isTrue);
          expect(state.activeAddress, isNull);
          expect(state.activeAccountUuid, 'account-2');
          expect(state.accounts, hasLength(2));
          expect(
            await const FlutterSecureStorage().read(
              key: 'zcash_active_account',
            ),
            'account-2',
          );
          _rustApi.lookupGate = null;
          (container.read(appSecurityProvider.notifier)
                  as _SwitchTestSecurityNotifier)
              .unlockForTest();
          await accounts.restoreAfterUnlock();
          expect(_rustApi.requestedAccounts, ['account-2', 'account-2']);
          expect(
            container.read(accountProvider).value!.activeAddress,
            'u1account-2-address',
          );
        },
      );
    }
  });

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

  test(
    'wallet reset cleanup removes only payment-link claim directories',
    () async {
      final supportDirectory = Directory.systemTemp.createTempSync(
        'vizor-payment-link-reset',
      );
      addTearDown(() {
        if (supportDirectory.existsSync()) {
          supportDirectory.deleteSync(recursive: true);
        }
      });
      final mainName = paymentLinkClaimWalletDirectoryNameFor(
        network: 'main',
        identityHash: List.filled(64, 'a').join(),
      );
      final regtestName = paymentLinkClaimWalletDirectoryNameFor(
        network: 'regtest',
        identityHash: List.filled(64, 'b').join(),
      );
      final mainClaimDirectory = Directory(
        '${supportDirectory.path}${Platform.pathSeparator}$mainName',
      )..createSync();
      final regtestClaimDirectory = Directory(
        '${supportDirectory.path}${Platform.pathSeparator}$regtestName',
      )..createSync();
      final unrelatedDirectory = Directory(
        '${supportDirectory.path}${Platform.pathSeparator}'
        '${kPaymentLinkClaimWalletDirectoryPrefix}draft',
      )..createSync();

      await deletePaymentLinkClaimWalletDirectories(
        resolveSupportDirectory: () async => supportDirectory,
      );

      expect(mainClaimDirectory.existsSync(), isFalse);
      expect(regtestClaimDirectory.existsSync(), isFalse);
      expect(unrelatedDirectory.existsSync(), isTrue);
    },
  );

  test('claim cleanup filtered by network spares other networks', () async {
    final supportDirectory = Directory.systemTemp.createTempSync(
      'vizor-payment-link-reset-network',
    );
    addTearDown(() {
      if (supportDirectory.existsSync()) {
        supportDirectory.deleteSync(recursive: true);
      }
    });
    final mainName = paymentLinkClaimWalletDirectoryNameFor(
      network: 'main',
      identityHash: List.filled(64, 'a').join(),
    );
    final regtestName = paymentLinkClaimWalletDirectoryNameFor(
      network: 'regtest',
      identityHash: List.filled(64, 'b').join(),
    );
    final mainClaimDirectory = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}$mainName',
    )..createSync();
    final regtestClaimDirectory = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}$regtestName',
    )..createSync();

    await deletePaymentLinkClaimWalletDirectories(
      network: ZcashNetwork.regtest.name,
      resolveSupportDirectory: () async => supportDirectory,
    );

    expect(regtestClaimDirectory.existsSync(), isFalse);
    expect(mainClaimDirectory.existsSync(), isTrue);
  });

  test('wallet reset surfaces payment-link claim cleanup failure', () async {
    await expectLater(
      clearPaymentLinkClaimWalletsForReset(
        deleteDirectories: () async {
          throw StateError('claim cleanup failed');
        },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'claim cleanup failed',
        ),
      ),
    );
  });

  test('wallet reset attempts every matching claim directory', () async {
    final supportDirectory = Directory.systemTemp.createTempSync(
      'vizor-payment-link-reset-failures',
    );
    addTearDown(() {
      if (supportDirectory.existsSync()) {
        supportDirectory.deleteSync(recursive: true);
      }
    });
    final firstName = paymentLinkClaimWalletDirectoryNameFor(
      network: 'main',
      identityHash: List.filled(64, 'a').join(),
    );
    final secondName = paymentLinkClaimWalletDirectoryNameFor(
      network: 'main',
      identityHash: List.filled(64, 'b').join(),
    );
    Directory(
      '${supportDirectory.path}${Platform.pathSeparator}$firstName',
    ).createSync();
    Directory(
      '${supportDirectory.path}${Platform.pathSeparator}$secondName',
    ).createSync();
    final attempted = <String>[];

    await expectLater(
      deletePaymentLinkClaimWalletDirectories(
        resolveSupportDirectory: () async => supportDirectory,
        deleteDirectory: (directory) async {
          final name = directory.path.split(Platform.pathSeparator).last;
          attempted.add(name);
          if (name == firstName) throw StateError('first delete failed');
          await directory.delete(recursive: true);
        },
      ),
      throwsStateError,
    );

    expect(attempted, containsAll([firstName, secondName]));
    expect(
      Directory(
        '${supportDirectory.path}${Platform.pathSeparator}$secondName',
      ).existsSync(),
      isFalse,
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
    'Ledger import removes the Rust account when Dart persistence fails',
    () async {
      FlutterSecureStoragePlatform.instance = _FailingAccountsWriteStorage();
      addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
      final supportDirectory = Directory.systemTemp.createTempSync(
        'vizor-ledger-import-rollback',
      );
      addTearDown(() => supportDirectory.deleteSync(recursive: true));
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            pathProvider,
            (_) async => supportDirectory.path,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProvider, null),
      );
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
            .importLedgerAccount(
              name: 'Ledger',
              ufvk: 'uview1ledger',
              seedFingerprint: List.filled(32, 1),
              zip32Index: 0,
              birthdayHeight: 3000000,
              ledgerWalletFingerprint: 'ab' * 32,
            ),
        throwsA(anything),
      );

      expect(_rustApi.importedHardwareKinds, ['ledger']);
      expect(_rustApi.deletedAccountUuids, ['imported-0']);
      expect(container.read(accountProvider).value?.accounts, isEmpty);
    },
  );

  test(
    'wallet link preserves Ledger identity and recovery metadata without pairing',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final supportDirectory = Directory.systemTemp.createTempSync(
        'vizor-wallet-link-import',
      );
      addTearDown(() => supportDirectory.deleteSync(recursive: true));
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            pathProvider,
            (_) async => supportDirectory.path,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProvider, null),
      );
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrapWithAccounts()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      const fingerprint =
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      LinkedWalletAccountImport linked(int index, String name) =>
          LinkedWalletAccountImport(
            sourceAccountUuid: 'desktop-$index',
            name: 'Ledger $index',
            birthdayHeight: 3000000 + index,
            zip32AccountIndex: index,
            isHardware: true,
            isSeedAnchor: false,
            hardwareSignerKind: HardwareSignerKind.ledger,
            ufvk: 'uview1ledger$index',
            seedFingerprint: List.filled(32, index),
            ledgerWalletFingerprint: fingerprint,
            ledgerWalletName: name,
            ledgerDeviceModel: 'Ledger Nano S Plus',
          );
      final result = await container
          .read(accountProvider.notifier)
          .importLinkedWalletAccounts(
            network: 'main',
            accountsToImport: [
              linked(2, '  Travel Ledger  '),
              linked(7, 'Other name'),
            ],
          );
      expect(result.importedCount, 2);
      final accounts = container
          .read(accountProvider)
          .requireValue
          .accounts
          .where((account) => account.isLedger)
          .toList();
      expect(accounts.map((account) => account.zip32AccountIndex), [2, 7]);
      expect(accounts.map((account) => account.birthdayHeight), [
        3000002,
        3000007,
      ]);
      for (final account in accounts) {
        expect(account.ledgerWalletFingerprint, fingerprint.toLowerCase());
        expect(account.ledgerWalletName, 'Travel Ledger');
        expect(account.ledgerDeviceModel, 'Ledger Nano S Plus');
        expect(account.ledgerDeviceId, isNull);
        expect(account.ledgerLastTransport, isNull);
        final restored = AccountInfo.fromJson(account.toJson());
        expect(restored.ledgerWalletName, account.ledgerWalletName);
        expect(restored.ledgerDeviceModel, account.ledgerDeviceModel);
        expect(
          restored.ledgerWalletFingerprint,
          account.ledgerWalletFingerprint,
        );
        expect(restored.zip32AccountIndex, account.zip32AccountIndex);
        expect(restored.birthdayHeight, account.birthdayHeight);
      }
      await container
          .read(accountProvider.notifier)
          .renameLedgerWallet(accounts.first.uuid, 'Local name');
      await container
          .read(accountProvider.notifier)
          .importLinkedWalletAccounts(
            network: 'main',
            accountsToImport: [linked(8, 'Desktop name')],
          );
      expect(
        container
            .read(accountProvider)
            .requireValue
            .accounts
            .last
            .ledgerWalletName,
        'Local name',
      );
      expect(_rustApi.importedHardwareKinds, ['ledger', 'ledger', 'ledger']);
    },
  );

  test(
    'wallet link rejects a Ledger without identity before importing any account',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrapWithAccounts()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      await expectLater(
        container
            .read(accountProvider.notifier)
            .importLinkedWalletAccounts(
              network: 'main',
              accountsToImport: const [
                LinkedWalletAccountImport(
                  name: 'Ledger',
                  birthdayHeight: 3000000,
                  zip32AccountIndex: 0,
                  isHardware: true,
                  isSeedAnchor: false,
                  hardwareSignerKind: HardwareSignerKind.ledger,
                ),
              ],
            ),
        throwsArgumentError,
      );
      expect(_rustApi.importedHardwareKinds, isEmpty);
    },
  );

  test('renames every account in the same Ledger wallet', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const fingerprint =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const ledgers = [
      AccountInfo(
        uuid: 'ledger-1',
        name: 'Ledger 1',
        order: 0,
        isHardware: true,
        hardwareSignerKind: HardwareSignerKind.ledger,
        zip32AccountIndex: 0,
        ledgerWalletFingerprint: fingerprint,
      ),
      AccountInfo(
        uuid: 'ledger-2',
        name: 'Ledger 2',
        order: 1,
        isHardware: true,
        hardwareSignerKind: HardwareSignerKind.ledger,
        zip32AccountIndex: 1,
        ledgerWalletFingerprint: fingerprint,
      ),
    ];
    final bootstrap = AppBootstrapState(
      initialLocation: '/home',
      initialAccountState: const AccountState(
        accounts: ledgers,
        activeAccountUuid: 'ledger-1',
      ),
      initialSyncSnapshot: AppSyncSnapshot.emptyForAccount('ledger-1'),
      network: kZcashDefaultNetworkName,
      rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
      themeMode: ThemeMode.system,
      privacyModeEnabled: false,
      isPasswordConfigured: true,
      isUnlocked: true,
      passwordRotationRecoveryFailed: false,
    );
    final container = ProviderContainer(
      overrides: [appBootstrapProvider.overrideWithValue(bootstrap)],
    );
    addTearDown(container.dispose);
    await container.read(accountProvider.future);

    await container
        .read(accountProvider.notifier)
        .renameLedgerWallet('ledger-1', 'Cold storage');

    expect(
      container
          .read(accountProvider)
          .value!
          .accounts
          .map((account) => account.ledgerWalletName),
      everyElement('Cold storage'),
    );
  });

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
    'failed destructive account mutations request share restoration',
    () async {
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, (call) async {
            throw PlatformException(code: 'db-path-unavailable');
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProvider, null);
      });

      final shareTracking = VotingShareTrackingRegistry();
      var restoreRequests = 0;
      shareTracking.addRestoreRequestListener(() => restoreRequests++);
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrapWithAccounts()),
          votingShareTrackingRegistryProvider.overrideWithValue(shareTracking),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);

      await expectLater(
        container.read(accountProvider.notifier).removeAccount('account-2'),
        throwsA(isA<PlatformException>()),
      );
      expect(shareTracking.isQuiesced('account-2'), isFalse);
      expect(restoreRequests, 1);

      await expectLater(
        container.read(accountProvider.notifier).resetWallet(),
        throwsA(isA<PlatformException>()),
      );
      expect(shareTracking.isQuiesced('account-1'), isFalse);
      expect(restoreRequests, 2);
    },
  );

  test('successful account removal requests share restoration', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final supportDirectory = Directory.systemTemp.createTempSync(
      'vizor-account-removal',
    );
    addTearDown(() {
      if (supportDirectory.existsSync()) {
        supportDirectory.deleteSync(recursive: true);
      }
    });
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return supportDirectory.path;
          }
          throw MissingPluginException('Unexpected path provider call.');
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null);
    });

    final shareTracking = VotingShareTrackingRegistry();
    var restoreRequests = 0;
    shareTracking.addRestoreRequestListener(() => restoreRequests++);
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrapWithAccounts()),
        votingShareTrackingRegistryProvider.overrideWithValue(shareTracking),
      ],
    );
    addTearDown(container.dispose);
    await container.read(accountProvider.future);

    await container.read(accountProvider.notifier).removeAccount('account-2');

    expect(shareTracking.isQuiesced('account-2'), isFalse);
    expect(restoreRequests, 1);
    expect(_rustApi.deletedAccountUuids, ['account-2']);
    expect(
      container
          .read(accountProvider)
          .value!
          .accounts
          .map((account) => account.uuid),
      ['account-1'],
    );
  });

  test(
    'a redeemed Gift Card allows account deletion with recovery still retained',
    () => _expectAccountDeletionDrainsLiveShareTracking(redeemedCard: true),
  );

  test(
    'account deletion drains live share tracking before the wallet mutation',
    () => _expectAccountDeletionDrainsLiveShareTracking(),
  );

  test(
    'mobile account deletion drains live share tracking before the wallet mutation',
    () => _expectAccountDeletionDrainsLiveShareTracking(),
    tags: ['mobile'],
  );

  test('drain failures resume tracking after destructive mutations', () async {
    final shareTracking = VotingShareTrackingRegistry();
    var restoreRequests = 0;
    shareTracking.addRestoreRequestListener(() => restoreRequests++);
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrapWithAccounts()),
        votingShareTrackingRegistryProvider.overrideWithValue(shareTracking),
      ],
    );
    addTearDown(container.dispose);
    await container.read(accountProvider.future);

    final deleteOwner = Object();
    expect(
      shareTracking.register(
        key: const VotingSessionKey(
          accountUuid: 'account-2',
          roundId: 'round-delete',
        ),
        owner: deleteOwner,
        stopAndDrain: () async => throw StateError('delete drain failed'),
      ),
      isTrue,
    );

    await expectLater(
      container.read(accountProvider.notifier).removeAccount('account-2'),
      throwsA(isA<StateError>()),
    );
    expect(shareTracking.isQuiesced('account-2'), isFalse);
    expect(restoreRequests, 1);

    final resetOwner = Object();
    expect(
      shareTracking.register(
        key: const VotingSessionKey(
          accountUuid: 'account-1',
          roundId: 'round-reset',
        ),
        owner: resetOwner,
        stopAndDrain: () async => throw StateError('reset drain failed'),
      ),
      isTrue,
    );

    await expectLater(
      container.read(accountProvider.notifier).resetWallet(),
      throwsA(isA<StateError>()),
    );
    expect(shareTracking.isQuiesced('account-1'), isFalse);
    expect(restoreRequests, 2);
  });

  test(
    'wallet reset drains Gift Card claims before resolving the DB',
    () async {
      final lifecycle = PaymentLinkClaimLifecycleRegistry();
      final drainStarted = Completer<void>();
      final drainGate = Completer<void>();
      var resumeCalls = 0;
      lifecycle.register(
        owner: Object(),
        quiesceAndDrain: () async {
          drainStarted.complete();
          await drainGate.future;
        },
        resume: () => resumeCalls++,
      );
      final pathRequested = Completer<void>();
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, (call) async {
            if (!pathRequested.isCompleted) pathRequested.complete();
            throw PlatformException(code: 'db-path-unavailable');
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProvider, null);
      });
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrapWithAccounts()),
          paymentLinkClaimLifecycleRegistryProvider.overrideWithValue(
            lifecycle,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);

      final reset = container.read(accountProvider.notifier).resetWallet();
      await drainStarted.future;

      expect(pathRequested.isCompleted, isFalse);
      drainGate.complete();
      await expectLater(reset, throwsA(isA<PlatformException>()));
      expect(pathRequested.isCompleted, isTrue);
      expect(resumeCalls, 1);
    },
  );

  test('account removal drains Gift Card claims before counting the in-flight '
      'ones', () async {
    final receivedStorage = _AccountTestPaymentLinkReceivedStorage();
    final receivedStore = PaymentLinkReceivedStore(receivedStorage);
    final link = VizorPaymentLink(
      network: 'main',
      address: 'u1accountremovaldrainpaymentlink',
      amountZatoshi: BigInt.from(100000),
      mnemonic: List.filled(24, 'abandon').join(' '),
      birthdayHeight: 3_456_789,
      label: 'Payment link',
      createdAt: DateTime.utc(2026, 9, 3),
    );
    await receivedStore.saveReady(link);

    // A claim into account-2 that was already submitting when the deletion
    // started: it finishes while the drain waits, so the record turns
    // `receiving` only after the count would have read zero.
    final lifecycle = PaymentLinkClaimLifecycleRegistry();
    var resumeCalls = 0;
    lifecycle.register(
      owner: Object(),
      quiesceAndDrain: () async {
        await receivedStore.markReceiving(
          claimSubmittedAt: DateTime.utc(2026, 8, 28),
          address: link.address,
          destinationAccountUuid: 'account-2',
          claimTxids: 'claim-txid',
        );
      },
      resume: () => resumeCalls++,
    );
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrapWithAccounts()),
        paymentLinkReceivedStoreProvider.overrideWithValue(receivedStore),
        paymentLinkClaimLifecycleRegistryProvider.overrideWithValue(lifecycle),
      ],
    );
    addTearDown(container.dispose);
    await container.read(accountProvider.future);

    await expectLater(
      container.read(accountProvider.notifier).removeAccount('account-2'),
      throwsA(
        isA<PaymentLinkInFlightClaimsException>().having(
          (error) => error.count,
          'count',
          1,
        ),
      ),
    );
    expect(container.read(accountProvider).value!.accounts, hasLength(2));
    expect(
      _rustApi.deletedAccountUuids,
      isEmpty,
      reason: 'the account a finished claim paid into must not be deleted',
    );
    expect(resumeCalls, 1);
  });

  test(
    'account removal is rejected while it owns an unshared Gift Card',
    () async {
      final recoveryStorage = _AccountTestPaymentLinkRecoveryStorage();
      final recoveryStore = PaymentLinkRecoveryStore(recoveryStorage);
      final link = VizorPaymentLink(
        network: 'main',
        address: 'u1accountremovalpaymentlink',
        amountZatoshi: BigInt.from(100000),
        mnemonic: List.filled(24, 'abandon').join(' '),
        birthdayHeight: 3_456_789,
        label: 'Payment link',
        createdAt: DateTime.utc(2026, 8, 7),
      );
      await recoveryStore.saveDraft(
        claimFeeReserveZatoshi: BigInt.from(10000),
        link: link,
        sourceAccountUuid: 'account-2',
      );
      await recoveryStore.markFunded(
        address: link.address,
        fundingTxids: 'funding-txid',
      );
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrapWithAccounts()),
          paymentLinkRecoveryStoreProvider.overrideWithValue(recoveryStore),
        ],
      );
      addTearDown(container.dispose);

      await container.read(accountProvider.future);

      await expectLater(
        container.read(accountProvider.notifier).removeAccount('account-2'),
        throwsA(
          isA<PaymentLinkUnsharedGiftCardsException>()
              .having((error) => error.count, 'count', 1)
              .having(
                (error) => error.sourceAccountUuid,
                'sourceAccountUuid',
                'account-2',
              ),
        ),
      );
      expect(container.read(accountProvider).value!.accounts, hasLength(2));
    },
  );

  test('account removal is rejected while it receives a Gift Card', () async {
    final receivedStorage = _AccountTestPaymentLinkReceivedStorage();
    final receivedStore = PaymentLinkReceivedStore(receivedStorage);
    final link = VizorPaymentLink(
      network: 'main',
      address: 'u1accountremovalreceivedpaymentlink',
      amountZatoshi: BigInt.from(100000),
      mnemonic: List.filled(24, 'abandon').join(' '),
      birthdayHeight: 3_456_789,
      label: 'Payment link',
      createdAt: DateTime.utc(2026, 9, 1),
    );
    await receivedStore.saveReady(link);
    await receivedStore.markReceiving(
      claimSubmittedAt: DateTime.utc(2026, 8, 28),
      address: link.address,
      destinationAccountUuid: 'account-2',
      claimTxids: 'claim-txid',
    );
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrapWithAccounts()),
        paymentLinkReceivedStoreProvider.overrideWithValue(receivedStore),
      ],
    );
    addTearDown(container.dispose);

    await container.read(accountProvider.future);

    await expectLater(
      container.read(accountProvider.notifier).removeAccount('account-2'),
      throwsA(
        isA<PaymentLinkInFlightClaimsException>()
            .having((error) => error.count, 'count', 1)
            .having(
              (error) => error.destinationAccountUuid,
              'destinationAccountUuid',
              'account-2',
            ),
      ),
    );
    expect(container.read(accountProvider).value!.accounts, hasLength(2));
  });

  test(
    'wallet reset is rejected while a Gift Card is being received',
    () async {
      final receivedStorage = _AccountTestPaymentLinkReceivedStorage();
      final receivedStore = PaymentLinkReceivedStore(receivedStorage);
      final link = VizorPaymentLink(
        network: 'main',
        address: 'u1walletresetreceivedpaymentlink',
        amountZatoshi: BigInt.from(100000),
        mnemonic: List.filled(24, 'abandon').join(' '),
        birthdayHeight: 3_456_789,
        label: 'Payment link',
        createdAt: DateTime.utc(2026, 9, 3),
      );
      await receivedStore.saveReady(link);
      await receivedStore.markReceiving(
        claimSubmittedAt: DateTime.utc(2026, 8, 28),
        address: link.address,
        destinationAccountUuid: 'account-2',
        claimTxids: 'claim-txid',
      );

      final lifecycle = PaymentLinkClaimLifecycleRegistry();
      var resumeCalls = 0;
      lifecycle.register(
        owner: Object(),
        quiesceAndDrain: () async {},
        resume: () => resumeCalls++,
      );
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrapWithAccounts()),
          paymentLinkReceivedStoreProvider.overrideWithValue(receivedStore),
          paymentLinkClaimLifecycleRegistryProvider.overrideWithValue(
            lifecycle,
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(accountProvider.future);

      await expectLater(
        container.read(accountProvider.notifier).resetWallet(),
        throwsA(
          isA<WalletResetInFlightGiftCardClaimsException>().having(
            (error) => error.count,
            'count',
            1,
          ),
        ),
      );
      // The refusal lands before anything is resolved or deleted, and the claim
      // lifecycle is handed back so the claim can finish.
      expect(container.read(accountProvider).value!.accounts, hasLength(2));
      expect(_rustApi.deletedAccountUuids, isEmpty);
      expect(resumeCalls, 1);
    },
  );

  test('a locked wallet resets despite an in-flight Gift Card claim', () async {
    // A claim cannot advance while locked, so refusing here would never lift
    // and would trap a user whose only way back in is this reset. The DB path
    // is the very next step after the skipped check, so its failure is the
    // proof that the claim check did not stop the reset.
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
          throw PlatformException(code: 'db-path-unavailable');
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null);
    });

    final receivedStorage = _AccountTestPaymentLinkReceivedStorage();
    final receivedStore = PaymentLinkReceivedStore(receivedStorage);
    final link = VizorPaymentLink(
      network: 'main',
      address: 'u1lockedwalletresetpaymentlink',
      amountZatoshi: BigInt.from(100000),
      mnemonic: List.filled(24, 'abandon').join(' '),
      birthdayHeight: 3_456_789,
      label: 'Payment link',
      createdAt: DateTime.utc(2026, 9, 3),
    );
    await receivedStore.saveReady(link);
    await receivedStore.markReceiving(
      claimSubmittedAt: DateTime.utc(2026, 8, 28),
      address: link.address,
      destinationAccountUuid: 'account-2',
      claimTxids: 'claim-txid',
    );

    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          _bootstrapWithAccounts(isUnlocked: false),
        ),
        paymentLinkReceivedStoreProvider.overrideWithValue(receivedStore),
      ],
    );
    addTearDown(container.dispose);

    await container.read(accountProvider.future);

    await expectLater(
      container.read(accountProvider.notifier).resetWallet(),
      throwsA(isA<PlatformException>()),
    );
  });

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

/// Secure storage whose account-list write fails after the Rust row exists.
class _FailingAccountsWriteStorage extends TestFlutterSecureStoragePlatform {
  _FailingAccountsWriteStorage() : super({});

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (key.contains('accounts')) {
      throw PlatformException(code: 'write_failed', message: 'disk full');
    }
    await super.write(key: key, value: value, options: options);
  }
}

class _SwitchTestSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);

  void unlockForTest() => state = state.copyWith(isUnlocked: true);
}

class _AccountMutationRustApiFake implements RustLibApi {
  final deletedAccountUuids = <String>[];
  final importedHardwareKinds = <String>[];
  final requestedAccounts = <String>[];
  var lookupStarted = Completer<void>();
  Completer<String>? lookupGate;

  void reset() {
    deletedAccountUuids.clear();
    importedHardwareKinds.clear();
    requestedAccounts.clear();
    lookupStarted = Completer<void>();
    lookupGate = null;
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
    importedHardwareKinds.add(hardwareSignerKind);
    return rust_wallet.AccountCreationResult(
      accountUuid: 'imported-$zip32Index',
      unifiedAddress: 'u1imported$zip32Index',
    );
  }

  @override
  Future<String> crateApiWalletGetUnifiedAddress({
    required String dbPath,
    required String network,
    String? accountUuid,
  }) async {
    requestedAccounts.add(accountUuid!);
    if (!lookupStarted.isCompleted) lookupStarted.complete();
    return lookupGate?.future ?? Future.value('u1$accountUuid-address');
  }

  @override
  Future<void> crateApiWalletDeleteAccount({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async {
    deletedAccountUuids.add(accountUuid);
  }

  @override
  Future<void> crateApiVotingResetVotingSessionState({
    required String dbPath,
    required String accountUuid,
    String? roundId,
  }) async {}

  @override
  Future<int> crateApiVotingDeleteVotingAccountState({
    required String dbPath,
    required String accountUuid,
  }) async => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _expectAccountDeletionDrainsLiveShareTracking({
  bool redeemedCard = false,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final supportDirectory = Directory.systemTemp.createTempSync(
    'vizor-account-share-drain',
  );
  addTearDown(() {
    if (supportDirectory.existsSync()) {
      supportDirectory.deleteSync(recursive: true);
    }
  });
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProvider, (call) async {
        if (call.method == 'getApplicationSupportDirectory') {
          return supportDirectory.path;
        }
        throw MissingPluginException('Unexpected path provider call.');
      });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
  });

  final shareTracking = VotingShareTrackingRegistry();
  final drainStarted = Completer<void>();
  final drainGate = Completer<void>();
  expect(
    shareTracking.register(
      key: const VotingSessionKey(
        accountUuid: 'account-2',
        roundId: 'round-delete',
      ),
      owner: Object(),
      stopAndDrain: () async {
        if (!drainStarted.isCompleted) drainStarted.complete();
        await drainGate.future;
      },
    ),
    isTrue,
  );

  final receivedStore = PaymentLinkReceivedStore(
    _AccountTestPaymentLinkReceivedStorage(),
  );
  if (redeemedCard) {
    final link = VizorPaymentLink(
      network: 'main',
      address: 'u1redeemed-account',
      amountZatoshi: BigInt.from(100000),
      mnemonic: List.filled(24, 'abandon').join(' '),
      birthdayHeight: 3456789,
      label: 'Payment link',
      createdAt: DateTime.utc(2026, 9, 7),
    );
    await receivedStore.saveReady(link);
    await receivedStore.markClaimStarted(
      address: link.address,
      destinationAccountUuid: 'account-2',
    );
    await receivedStore.markReceiving(
      address: link.address,
      destinationAccountUuid: 'account-2',
      claimTxids: 'claim-tx',
    );
    await receivedStore.markReceived(address: link.address);
    expect((await receivedStore.load()).single.needsClaimRecovery, isTrue);
  }
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrapWithAccounts()),
      votingShareTrackingRegistryProvider.overrideWithValue(shareTracking),
      paymentLinkReceivedStoreProvider.overrideWithValue(receivedStore),
    ],
  );
  addTearDown(container.dispose);
  await container.read(accountProvider.future);

  final removal = container
      .read(accountProvider.notifier)
      .removeAccount('account-2');
  await drainStarted.future;
  expect(_rustApi.deletedAccountUuids, isEmpty);
  expect(shareTracking.isQuiesced('account-2'), isTrue);

  drainGate.complete();
  await removal;

  expect(_rustApi.deletedAccountUuids, ['account-2']);
  expect(shareTracking.isQuiesced('account-2'), isFalse);
}

class _AccountTestPaymentLinkRecoveryStorage
    implements PaymentLinkRecoveryStorage {
  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String nextValue) async => value = nextValue;
}

class _AccountTestPaymentLinkReceivedStorage
    implements PaymentLinkReceivedStorage {
  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String nextValue) async => value = nextValue;
}

AppBootstrapState _bootstrapWithAccounts({bool isUnlocked = true}) {
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
    isUnlocked: isUnlocked,
    passwordRotationRecoveryFailed: false,
  );
}
