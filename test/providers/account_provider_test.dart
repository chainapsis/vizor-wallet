import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_share_tracking_registry_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_guard_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

final _rustApi = _AccountMutationRustApiFake();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => RustLib.initMock(api: _rustApi));
  tearDownAll(RustLib.dispose);
  setUp(_rustApi.reset);

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
      var stoppedRecoveries = 0;
      shareTracking.addRestoreRequestListener(() => restoreRequests++);
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrapWithAccounts()),
          votingShareTrackingRegistryProvider.overrideWithValue(shareTracking),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);

      final removeRecoveryOwner = Object();
      expect(
        shareTracking.registerSyncRecovery(
          key: const VotingSessionKey(
            accountUuid: 'account-2',
            roundId: 'remove-recovery',
          ),
          owner: removeRecoveryOwner,
          stopAndDrain: () async => stoppedRecoveries++,
        ),
        isTrue,
      );
      const retainedRecoveryKey = VotingSessionKey(
        accountUuid: 'account-1',
        roundId: 'reset-recovery',
      );
      final retainedRecoveryOwner = Object();
      expect(
        shareTracking.registerSyncRecovery(
          key: retainedRecoveryKey,
          owner: retainedRecoveryOwner,
          stopAndDrain: () async => stoppedRecoveries++,
        ),
        isTrue,
      );

      await expectLater(
        container.read(accountProvider.notifier).removeAccount('account-2'),
        throwsA(isA<PlatformException>()),
      );
      expect(shareTracking.isQuiesced('account-2'), isFalse);
      expect(restoreRequests, 1);
      expect(stoppedRecoveries, 1);
      expect(
        shareTracking.registeredSyncRecoveryKeys,
        contains(retainedRecoveryKey),
      );

      await expectLater(
        container.read(accountProvider.notifier).resetWallet(),
        throwsA(isA<PlatformException>()),
      );
      expect(shareTracking.isQuiesced('account-1'), isFalse);
      expect(restoreRequests, 2);
      expect(stoppedRecoveries, 2);
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

class _AccountMutationRustApiFake implements RustLibApi {
  final deletedAccountUuids = <String>[];

  void reset() => deletedAccountUuids.clear();

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

Future<void> _expectAccountDeletionDrainsLiveShareTracking() async {
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

  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrapWithAccounts()),
      votingShareTrackingRegistryProvider.overrideWithValue(shareTracking),
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
