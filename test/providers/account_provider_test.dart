import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_account_material_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_pending_session_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_guard_provider.dart';

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

  test('mnemonic access is limited to software accounts', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrapWithAccountKinds()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(accountProvider.future);
    final notifier = container.read(accountProvider.notifier);

    expect(notifier.accountHasLocalMnemonic('software-account'), isTrue);
    expect(notifier.accountHasLocalMnemonic('hardware-account'), isFalse);
    expect(notifier.accountHasLocalMnemonic('multisig-account'), isFalse);
    expect(notifier.isSoftwareAccount('multisig-account'), isFalse);
    expect(notifier.isMultisigAccount('multisig-account'), isTrue);
    expect(await notifier.getMnemonicForAccount('multisig-account'), isNull);
    expect(
      await notifier.getMnemonicBytesForAccount('multisig-account'),
      isNull,
    );
  });

  test(
    'finalized multisig setup cleanup requires matching account metadata',
    () async {
      final session = _pendingSession();
      final pendingStore = _FakePendingSessionStore()
        ..put(session)
        ..summaries[session.storageId] =
            MultisigPendingSessionSummary.fromSession(session)
        ..createStates[session.storageId] = '{"round":1}';
      final materialStore = _FakeAccountMaterialStore()
        ..put(_accountMaterial(accountUuid: 'multisig-account'));
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrapWithAccountKinds()),
          multisigPendingSessionStoreProvider.overrideWithValue(pendingStore),
          multisigAccountMaterialStoreProvider.overrideWithValue(materialStore),
        ],
      );
      addTearDown(container.dispose);

      await container.read(accountProvider.future);
      await _pumpEventQueue();

      expect(pendingStore.sessions.containsKey(session.storageId), isFalse);
      expect(pendingStore.summaries.containsKey(session.storageId), isFalse);
      expect(pendingStore.createStates.containsKey(session.storageId), isFalse);
    },
  );

  test(
    'multisig setup cleanup preserves material without account metadata',
    () async {
      final session = _pendingSession();
      final pendingStore = _FakePendingSessionStore()
        ..put(session)
        ..summaries[session.storageId] =
            MultisigPendingSessionSummary.fromSession(session)
        ..createStates[session.storageId] = '{"round":1}';
      final materialStore = _FakeAccountMaterialStore()
        ..put(_accountMaterial(accountUuid: 'orphan-account'));
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrapWithAccountKinds()),
          multisigPendingSessionStoreProvider.overrideWithValue(pendingStore),
          multisigAccountMaterialStoreProvider.overrideWithValue(materialStore),
        ],
      );
      addTearDown(container.dispose);

      await container.read(accountProvider.future);
      await _pumpEventQueue();

      expect(pendingStore.sessions.containsKey(session.storageId), isTrue);
      expect(pendingStore.summaries.containsKey(session.storageId), isTrue);
      expect(pendingStore.createStates.containsKey(session.storageId), isTrue);
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

Future<void> _pumpEventQueue() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

AppBootstrapState _bootstrapWithAccountKinds() {
  const accountState = AccountState(
    accounts: [
      AccountInfo(uuid: 'software-account', name: 'Software', order: 0),
      AccountInfo(
        uuid: 'hardware-account',
        name: 'Keystone',
        order: 1,
        kind: AccountKind.hardware,
      ),
      AccountInfo(
        uuid: 'multisig-account',
        name: 'Family vault',
        order: 2,
        kind: AccountKind.multisig,
      ),
    ],
    activeAccountUuid: 'software-account',
  );
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: accountState,
    initialSyncSnapshot: AppSyncSnapshot.emptyForAccount('software-account'),
    network: kZcashDefaultNetworkName,
    rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
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

const _identity = MultisigParticipantIdentity(
  admissionSecretKey: 'admission-secret',
  admissionPublicKey: 'admission-public',
  deliverySecretKey: 'delivery-secret',
  deliveryPublicKey: 'delivery-public',
);

MultisigPendingSession _pendingSession() {
  return const MultisigPendingSession(
    sessionId: 'session-1',
    participantId: 'participant-1',
    role: MultisigPendingRole.creator,
    coordinatorUrl: 'https://coordinator.example',
    label: 'Family vault',
    state: 'ready',
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    identity: _identity,
    inviteSecret: 'invite-secret',
    accessTokenExpiresAt: 2000,
    refreshTokenExpiresAt: 3000,
    participantCount: 3,
    threshold: 2,
    participants: [],
    createdAt: 1,
    updatedAt: 2,
    createdLocallyAt: 3,
    updatedLocallyAt: 4,
  );
}

MultisigAccountMaterial _accountMaterial({required String accountUuid}) {
  return MultisigAccountMaterial(
    accountUuid: accountUuid,
    sessionId: 'session-1',
    participantId: 'participant-1',
    coordinatorUrl: 'https://coordinator.example',
    network: 'regtest',
    rosterHash: 'roster',
    groupPublicPackageHash: 'group',
    threshold: 2,
    participantCount: 3,
    identity: _identity,
    keyPackageB64: 'key-package',
    groupPublicPackageJson: '{"group":true}',
    vaultAddress: 'uregtest1example',
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    accessTokenExpiresAt: 2000,
    refreshTokenExpiresAt: 3000,
  );
}

class _FakePendingSessionStore implements MultisigPendingSessionStore {
  final sessions = <String, MultisigPendingSession>{};
  final summaries = <String, MultisigPendingSessionSummary>{};
  final createStates = <String, String>{};

  void put(MultisigPendingSession session) {
    sessions[session.storageId] = session;
  }

  @override
  Future<MultisigPendingSession?> read(
    String storageId, {
    bool requireUnlockedSession = true,
  }) async {
    return sessions[storageId];
  }

  @override
  Future<List<MultisigPendingSession>> readAll({
    bool requireUnlockedSession = true,
  }) async {
    return sessions.values.toList(growable: false);
  }

  @override
  Future<void> write(MultisigPendingSession session) async {
    sessions[session.storageId] = session;
  }

  @override
  Future<List<MultisigPendingSessionSummary>> readAllSummaries() async {
    return summaries.values.toList(growable: false);
  }

  @override
  Future<void> writeSummary(MultisigPendingSession session) async {
    summaries[session.storageId] = MultisigPendingSessionSummary.fromSession(
      session,
    );
  }

  @override
  Future<void> rebuildSummaries(
    Iterable<MultisigPendingSession> sessions,
  ) async {
    summaries.clear();
    for (final session in sessions) {
      await writeSummary(session);
    }
  }

  @override
  Future<void> delete(MultisigPendingSession session) async {
    sessions.remove(session.storageId);
  }

  @override
  Future<void> deleteByStorageId(String storageId) async {
    sessions.remove(storageId);
  }

  @override
  Future<void> deleteSummary(String storageId) async {
    summaries.remove(storageId);
  }

  @override
  Future<void> deleteAllSummaries() async {
    summaries.clear();
  }

  @override
  Future<String?> readCreateState(MultisigPendingSession session) async {
    return createStates[session.storageId];
  }

  @override
  Future<void> writeCreateState(
    MultisigPendingSession session,
    String localStateJson,
  ) async {
    createStates[session.storageId] = localStateJson;
  }

  @override
  Future<void> deleteCreateState(MultisigPendingSession session) async {
    createStates.remove(session.storageId);
  }
}

class _FakeAccountMaterialStore implements MultisigAccountMaterialStore {
  final materials = <String, MultisigAccountMaterial>{};

  void put(MultisigAccountMaterial material) {
    materials[material.accountUuid] = material;
  }

  @override
  Future<MultisigAccountMaterial?> read(
    String accountUuid, {
    bool requireUnlockedSession = true,
  }) async {
    return materials[accountUuid];
  }

  @override
  Future<List<MultisigAccountMaterial>> readAll({
    bool requireUnlockedSession = true,
  }) async {
    return materials.values.toList(growable: false);
  }

  @override
  Future<void> write(MultisigAccountMaterial material) async {
    materials[material.accountUuid] = material;
  }

  @override
  Future<void> delete(String accountUuid) async {
    materials.remove(accountUuid);
  }
}
