import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/sync_short_catch_up_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

// After an app-lock unlock, the resume's tip check can start the catch-up
// before the unlock screen's refresh restores the completed state the lock
// cleared. That sync must still start as a catch-up of a synced wallet.

const _accountUuid = 'account-1';
const _completedHeight = 3000000;

class _Api extends RustLibApi {
  final syncs = <StreamController<rust_sync.ApiSyncProgressEvent>>[];

  /// What a progress event's own balance read returns.
  rust_sync.WalletBalance progressBalance = _walletBalance(orchard: 5);

  /// When set, a progress event's balance read waits for it.
  Completer<void>? progressHold;

  @override
  Future<rust_sync.WalletBalance> crateApiSyncGetBalance({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async {
    await progressHold?.future;
    return progressBalance;
  }

  @override
  Future<List<rust_sync.TransactionInfo>> crateApiSyncGetTransactionHistory({
    required String dbPath,
    required String network,
    int? limit,
    required String accountUuid,
  }) async => const [];

  @override
  bool crateApiSyncIsSyncRunning() => false;

  @override
  bool crateApiSyncIsSyncCancelRequested() => false;

  @override
  bool crateApiSyncIsMempoolObserverRunning() => false;

  @override
  void crateApiSyncSetActiveSyncAccount({String? accountUuid}) {}

  @override
  void crateApiSyncSetSyncMode({required int mode}) {}

  @override
  void crateApiSyncCancelFullSync() {}

  @override
  void crateApiSyncStopMempoolObserver() {}

  @override
  Stream<rust_sync.ApiMempoolTxEvent> crateApiSyncStartMempoolObserver({
    required String dbPath,
    required String network,
    required String lightwalletdUrl,
  }) => const Stream.empty();

  @override
  Stream<rust_sync.ApiSyncProgressEvent> crateApiSyncStartFullSync({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required int mode,
  }) {
    final controller = StreamController<rust_sync.ApiSyncProgressEvent>();
    syncs.add(controller);
    return controller.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Account extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [AccountInfo(uuid: _accountUuid, name: 'Account 1', order: 0)],
    activeAccountUuid: _accountUuid,
  );
}

/// Four blocks past the height the wallet completed at.
class _Tip extends RpcEndpointFailoverNotifier {
  @override
  RpcEndpointFailoverState build() => RpcEndpointFailoverState(
    primary: defaultRpcEndpointConfig('main'),
    current: defaultRpcEndpointConfig('main'),
    fallbackCandidates: const [],
  );

  /// When set, the tip request fails, as one cut off in the background does.
  static bool fail = false;

  @override
  Future<BigInt> getLatestBlockHeight() async {
    if (fail) throw StateError('connection reset');
    return BigInt.from(_completedHeight + 4);
  }
}

class _Upgrade extends ChainUpgradeStatusNotifier {
  @override
  Future<ChainUpgradeStatusState> build() async =>
      ChainUpgradeStatusState.cachedActive(defaultRpcEndpointConfig('main'));

  @override
  Future<void> refreshAtTip(BigInt tipHeight) async {}
}

class _NoPrivateQueries extends EnhancePirNotifier {
  @override
  bool build() => false;
}

/// A synced wallet whose stored status says its last sync completed. The
/// balance read can be held open, as a slow wallet summary does.
class _Sync extends SyncNotifier {
  _Sync({this.initial})
    : super(
        walletDbPathResolver: () async => 'wallet.db',
        excludeCompanionsFromBackup: (_) async {},
      );

  final SyncState? initial;
  int statusReads = 0;
  int balanceReads = 0;
  rust_sync.WalletBalance balance = _balance;
  final balanceRead = Completer<void>();
  final balanceReadStarted = Completer<void>();

  @override
  Future<SyncState> build() async =>
      initial ??
      SyncState(
        accountUuid: _accountUuid,
        hasAccountScopedData: true,
        isSyncComplete: true,
        percentage: 1,
        scannedHeight: _completedHeight,
        chainTipHeight: _completedHeight,
      );

  @override
  Future<rust_sync.SyncProgress> readSyncStatus({
    required String dbPath,
    required String network,
  }) async {
    statusReads++;
    return storedStatus;
  }

  /// The stored status: the last sync completed, unless a test says not.
  rust_sync.SyncProgress storedStatus = _completedStatus;

  /// Progress events in flight. Their balance reads go to the fake API
  /// ([_Api.progressBalance]), so a test can tell them from refreshes.
  int _progressEvents = 0;

  @override
  Future<void> handleSyncProgressForTesting(SyncProgressEvent event) async {
    _progressEvents++;
    try {
      await super.handleSyncProgressForTesting(event);
    } finally {
      _progressEvents--;
    }
  }

  @override
  Future<rust_sync.WalletBalance> readWalletBalance({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async {
    if (_progressEvents > 0) {
      return super.readWalletBalance(
        dbPath: dbPath,
        network: network,
        accountUuid: accountUuid,
      );
    }
    balanceReads++;
    final result = balance;
    if (!balanceReadStarted.isCompleted) balanceReadStarted.complete();
    await balanceRead.future;
    return result;
  }

  @override
  Future<List<rust_sync.TransactionInfo>> readTransactionHistory({
    required String dbPath,
    required String network,
    int? limit,
    required String accountUuid,
  }) async => const [];
}

final _balance = _walletBalance(orchard: 1);

final _completedStatus = rust_sync.SyncProgress(
  scannedHeight: BigInt.from(_completedHeight),
  chainTipHeight: BigInt.from(_completedHeight),
  isSyncing: false,
  isComplete: true,
  syncJobId: '',
  syncJobFraction: 0,
  syncJobFromCompletedSync: false,
);

/// The production build, whose stored status says the last sync completed.
class _LiveSync extends SyncNotifier {
  _LiveSync([this.status])
    : super(
        walletDbPathResolver: () async => 'wallet.db',
        excludeCompanionsFromBackup: (_) async {},
      );

  /// The stored status; the last sync completed when null.
  final rust_sync.SyncProgress? status;

  @override
  Future<rust_sync.SyncProgress> readSyncStatus({
    required String dbPath,
    required String network,
  }) async => status ?? _completedStatus;

  @override
  Future<List<rust_sync.TransactionInfo>> readTransactionHistory({
    required String dbPath,
    required String network,
    int? limit,
    required String accountUuid,
  }) async => const [];
}

rust_sync.WalletBalance _walletBalance({
  required int orchard,
  int transparent = 0,
  bool transparentPrivate = false,
}) => rust_sync.WalletBalance(
  availability: rust_sync.WalletBalanceAvailability.available,
  transparentAuthority: rust_sync.TransparentBalanceAuthority.current,
  transparentPrivate: transparentPrivate,
  transparent: BigInt.from(transparent),
  sapling: BigInt.zero,
  orchard: BigInt.from(orchard),
  ironwood: BigInt.zero,
  transparentLocked: BigInt.zero,
  saplingLocked: BigInt.zero,
  orchardLocked: BigInt.zero,
  ironwoodLocked: BigInt.zero,
  transparentPending: BigInt.zero,
  saplingPending: BigInt.zero,
  orchardPending: BigInt.zero,
  ironwoodPending: BigInt.zero,
  changePendingConfirmation: BigInt.zero,
  valuePendingSpendability: BigInt.zero,
  uneconomicValue: BigInt.zero,
  spendable: BigInt.from(orchard),
  locked: BigInt.zero,
  total: BigInt.from(orchard + transparent),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  setUp(() {
    api.syncs.clear();
    api.progressHold = null;
  });

  Future<(ProviderContainer, _Sync)> mounted({SyncState? initial}) async {
    final sync = _Sync(initial: initial);
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_Account.new),
        rpcEndpointFailoverProvider.overrideWith(_Tip.new),
        chainUpgradeStatusProvider.overrideWith(_Upgrade.new),
        enhancePirProvider.overrideWith(_NoPrivateQueries.new),
        syncProvider.overrideWith(() => sync),
      ],
    );
    addTearDown(() {
      // Ends a start's preflight still in flight before the container goes.
      sync.stopSync();
      if (!sync.balanceRead.isCompleted) sync.balanceRead.complete();
      container.dispose();
    });
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);
    return (container, sync);
  }

  /// A synced wallet that was locked (its state cleared) and is unlocked
  /// again, before the unlock screen has refreshed anything.
  Future<(ProviderContainer, _Sync)> unlockedAfterLock() async {
    final (container, sync) = await mounted();
    await sync.clearSensitiveStateForLock();
    final cleared = container.read(syncProvider).requireValue;
    expect(cleared.isSyncComplete, isFalse);
    expect(cleared.chainTipHeight, 0);
    return (container, sync);
  }

  void expectCatchUp(SyncState started) {
    expect(started.isSyncing, isTrue);
    expect(started.startedFromCompletedSync, isTrue);
    expect(started.scannedHeight, _completedHeight);
    expect(isShortSyncCatchUp(started, now: DateTime.now()), isTrue);
  }

  test(
    'a tip check that runs before the unlock refresh starts a catch-up',
    () async {
      final (container, sync) = await unlockedAfterLock();

      // The resume's tip check, then the unlock screen's refresh.
      final check = sync.checkTipForTesting();
      final unlock = sync.refreshAfterUnlock();
      await check;

      expectCatchUp(container.read(syncProvider).requireValue);
      expect(sync.statusReads, 1);
      sync.balanceRead.complete();
      await unlock;
    },
  );

  test('a tip check during the unlock refresh starts a catch-up', () async {
    final (container, sync) = await unlockedAfterLock();

    final unlock = sync.refreshAfterUnlock();
    // The resume's tip check runs while the unlock still reads, and shares
    // its stored-status read.
    await sync.checkTipForTesting();

    expectCatchUp(container.read(syncProvider).requireValue);
    expect(sync.statusReads, 1);
    await unlock;
  });

  group('a balance read in flight', () {
    SyncProgressEvent newNotes() => const SyncProgressEvent(
      scannedHeight: _completedHeight + 2,
      chainTipHeight: _completedHeight,
      percentage: 0.5,
      displayTargetPercentage: 0.5,
      displayTargetBlocks: 0,
      isSyncing: true,
      isComplete: false,
      hasNewTx: true,
      phase: 'scan',
    );

    test('is dropped once a later read has committed', () async {
      final (container, sync) = await mounted();

      final refresh = sync.refreshAfterSend();
      await sync.balanceReadStarted.future;
      // The sync's own read of new notes lands first, with newer data.
      await sync.handleSyncProgressForTesting(newNotes());
      expect(
        container.read(syncProvider).requireValue.orchardBalance,
        BigInt.from(5),
      );

      sync.balanceRead.complete();
      await refresh;

      expect(
        container.read(syncProvider).requireValue.orchardBalance,
        BigInt.from(5),
      );
      expect(sync.balanceReads, 1);
    });

    test('is used when it lands before a later read that is still in '
        'flight, which then replaces it', () async {
      final (container, sync) = await mounted();
      api.progressHold = Completer<void>();

      final refresh = sync.refreshAfterSend();
      await sync.balanceReadStarted.future;
      // The sync's read of new notes starts later and is slower.
      final progress = sync.handleSyncProgressForTesting(newNotes());
      await pumpEventQueue();

      sync.balanceRead.complete();
      await refresh;
      expect(
        container.read(syncProvider).requireValue.orchardBalance,
        BigInt.one,
      );

      api.progressHold!.complete();
      await progress;
      expect(
        container.read(syncProvider).requireValue.orchardBalance,
        BigInt.from(5),
      );
      expect(sync.balanceReads, 1);
    });

    test('is dropped after an account switch', () async {
      final (container, sync) = await mounted();
      sync.balance = _walletBalance(orchard: 7);

      final refresh = sync.refreshAfterSend();
      await sync.balanceReadStarted.future;
      sync.handleAccountSwitchForTesting(_accountUuid);
      sync.balanceRead.complete();
      await refresh;

      expect(
        container.read(syncProvider).requireValue.orchardBalance,
        isNot(BigInt.from(7)),
      );
    });

    test('is dropped after a lock', () async {
      final (container, sync) = await mounted();
      sync.balance = _walletBalance(orchard: 7);

      final refresh = sync.refreshAfterSend();
      await sync.balanceReadStarted.future;
      await sync.clearSensitiveStateForLock();
      sync.balanceRead.complete();
      await refresh;

      final state = container.read(syncProvider).requireValue;
      expect(state.hasBalanceData, isFalse);
      expect(state.orchardBalance, BigInt.zero);
    });

    test('that spans a sync start is carried like the start: a private '
        'current transparent amount becomes last known', () async {
      final (container, sync) = await mounted(
        initial: SyncState(
          accountUuid: _accountUuid,
          hasAccountScopedData: true,
          isSyncComplete: true,
          percentage: 1,
          scannedHeight: _completedHeight,
          chainTipHeight: _completedHeight,
          transparentBalance: BigInt.from(5),
          totalBalance: BigInt.from(6),
          transparentPrivate: true,
          canShieldTransparentBalance: true,
        ),
      );
      sync.balance = _walletBalance(
        orchard: 1,
        transparent: 5,
        transparentPrivate: true,
      );

      final refresh = sync.refreshAfterSend();
      await sync.balanceReadStarted.future;
      sync.startSync(latestTipHeight: _completedHeight + 4);
      sync.balanceRead.complete();
      await refresh;

      final state = container.read(syncProvider).requireValue;
      expect(state.orchardBalance, BigInt.one);
      expect(
        state.transparentAuthority,
        rust_sync.TransparentBalanceAuthority.lastKnown,
      );
      expect(state.transparentBalance, BigInt.zero);
      expect(state.transparentLastKnownBalance, BigInt.from(5));
      expect(sync.balanceReads, 1);
    });
  });

  group('a catch-up interrupted', () {
    Future<(ProviderContainer, _Sync)> catchingUp() async {
      final (container, sync) = await mounted();
      sync.startSync(latestTipHeight: _completedHeight + 4);
      expectCatchUp(container.read(syncProvider).requireValue);
      return (container, sync);
    }

    test('by a failure continues as a catch-up when it retries', () async {
      _Tip.fail = true;
      addTearDown(() => _Tip.fail = false);
      final (container, sync) = await catchingUp();

      // Its preflight fails, as it does when the app is cut off.
      await pumpEventQueue();
      final failed = container.read(syncProvider).requireValue;
      expect(failed.failure, isNotNull);
      expect(failed.isSyncing, isFalse);
      expect(failed.startedFromCompletedSync, isTrue);
      sync.stopTipChecksForTesting();

      _Tip.fail = false;
      sync.startSync(latestTipHeight: _completedHeight + 4);
      expectCatchUp(container.read(syncProvider).requireValue);
    });

    test('by a stop continues as a catch-up when it starts again', () async {
      final (container, sync) = await catchingUp();

      sync.stopSync();
      expect(
        container.read(syncProvider).requireValue.startedFromCompletedSync,
        isTrue,
      );

      sync.startSync(latestTipHeight: _completedHeight + 4);
      expectCatchUp(container.read(syncProvider).requireValue);
    });

    test('by a lock continues as a catch-up after the unlock', () async {
      final (container, sync) = await catchingUp();
      // The lock cancels it with its job unfinished.
      sync.storedStatus = rust_sync.SyncProgress(
        scannedHeight: BigInt.from(_completedHeight),
        chainTipHeight: BigInt.from(_completedHeight + 4),
        isSyncing: false,
        isComplete: false,
        syncJobId: 'job-2',
        syncJobFraction: 0.5,
        syncJobFromCompletedSync: false,
      );
      await sync.clearSensitiveStateForLock();

      sync.balanceRead.complete();
      await sync.refreshAfterUnlock();
      sync.startSync();

      final resumed = container.read(syncProvider).requireValue;
      expectCatchUp(resumed);
      expect(resumed.syncJobId, 'job-2');
      expect(resumed.percentage, 0.5);
    });

    test('but a restore the lock interrupted stays a restore', () async {
      final (container, sync) = await mounted(
        initial: SyncState(
          accountUuid: _accountUuid,
          isSyncing: true,
          percentage: 0.3,
          syncJobId: 'restore',
          scannedHeight: _completedHeight,
          chainTipHeight: _completedHeight,
        ),
      );
      sync.storedStatus = rust_sync.SyncProgress(
        scannedHeight: BigInt.from(419200),
        chainTipHeight: BigInt.from(_completedHeight),
        isSyncing: false,
        isComplete: false,
        syncJobId: 'restore',
        syncJobFraction: 0.3,
        syncJobFromCompletedSync: false,
      );
      await sync.clearSensitiveStateForLock();

      sync.balanceRead.complete();
      await sync.refreshAfterUnlock();
      sync.startSync();

      final resumed = container.read(syncProvider).requireValue;
      expect(resumed.isSyncing, isTrue);
      expect(resumed.startedFromCompletedSync, isFalse);
      expect(isShortSyncCatchUp(resumed, now: DateTime.now()), isFalse);
    });
  });

  test(
    'a sync after an account is added scans its history, not a catch-up',
    () async {
      final (container, sync) = await mounted();

      sync.handleAccountAddedForTesting();

      final rescan = container.read(syncProvider).requireValue;
      expect(rescan.isSyncing, isTrue);
      expect(rescan.startedFromCompletedSync, isFalse);
      expect(isShortSyncCatchUp(rescan, now: DateTime.now()), isFalse);
    },
  );

  /// A launch of the production build: [bootstrap]'s snapshot, or none (a
  /// locked launch), and the initial sync the build schedules.
  Future<SyncState> launched(
    _LiveSync sync, {
    AppBootstrapState? bootstrap,
  }) async {
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          bootstrap ?? AppBootstrapState.empty,
        ),
        accountProvider.overrideWith(_Account.new),
        rpcEndpointFailoverProvider.overrideWith(_Tip.new),
        chainUpgradeStatusProvider.overrideWith(_Upgrade.new),
        enhancePirProvider.overrideWith(_NoPrivateQueries.new),
        syncProvider.overrideWith(() => sync),
      ],
    );
    addTearDown(() {
      sync.stopSync();
      container.dispose();
    });
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);
    await pumpEventQueue();
    return container.read(syncProvider).requireValue;
  }

  /// A job the last session left at 0%, a catch-up when [catchUp].
  rust_sync.SyncProgress storedJob({required bool catchUp}) =>
      rust_sync.SyncProgress(
        scannedHeight: BigInt.from(_completedHeight),
        chainTipHeight: BigInt.from(_completedHeight + 4),
        isSyncing: false,
        isComplete: false,
        syncJobId: 'job-1',
        syncJobFraction: 0,
        syncJobFromCompletedSync: catchUp,
      );

  group('a catch-up the app was killed during', () {
    test('continues as one after a launch', () async {
      final snapshot = AppSyncSnapshot(
        accountUuid: _accountUuid,
        hasAccountScopedData: true,
        scannedHeight: _completedHeight,
        chainTipHeight: _completedHeight + 4,
        percentage: 0,
        syncJobId: 'job-1',
        startedFromCompletedSync: true,
        transparentBalance: BigInt.zero,
        saplingBalance: BigInt.zero,
        orchardBalance: BigInt.one,
        ironwoodBalance: BigInt.zero,
        orchardLockedBalance: BigInt.zero,
        transparentPendingBalance: BigInt.zero,
        saplingPendingBalance: BigInt.zero,
        orchardPendingBalance: BigInt.zero,
        ironwoodPendingBalance: BigInt.zero,
        canShieldTransparentBalance: false,
        shieldTransparentFee: BigInt.zero,
        shieldTransparentAmount: BigInt.zero,
        spendableBalance: BigInt.one,
        totalBalance: BigInt.one,
        recentTransactions: const [],
      );
      final bootstrap = AppBootstrapState(
        initialLocation: '/home',
        initialAccountState: AccountState(),
        initialSyncSnapshot: snapshot,
        network: kZcashDefaultNetworkName,
        rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
        themeMode: ThemeMode.system,
        privacyModeEnabled: false,
        isPasswordConfigured: false,
        isUnlocked: false,
        passwordRotationRecoveryFailed: false,
      );

      final started = await launched(
        _LiveSync(storedJob(catchUp: true)),
        bootstrap: bootstrap,
      );
      expectCatchUp(started);
      expect(started.syncJobId, 'job-1');
    });

    test('continues as one after a locked launch', () async {
      final started = await launched(_LiveSync(storedJob(catchUp: true)));
      expectCatchUp(started);
      expect(started.syncJobId, 'job-1');
    });

    test('but a stored job that was no catch-up is not one', () async {
      final started = await launched(_LiveSync(storedJob(catchUp: false)));
      expect(started.isSyncing, isTrue);
      expect(started.startedFromCompletedSync, isFalse);
      expect(isShortSyncCatchUp(started, now: DateTime.now()), isFalse);
    });
  });

  test('a launch with no snapshot starts from the stored status', () async {
    final sync = _LiveSync();
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_Account.new),
        rpcEndpointFailoverProvider.overrideWith(_Tip.new),
        chainUpgradeStatusProvider.overrideWith(_Upgrade.new),
        enhancePirProvider.overrideWith(_NoPrivateQueries.new),
        syncProvider.overrideWith(() => sync),
      ],
    );
    addTearDown(() {
      sync.stopSync();
      container.dispose();
    });
    container.listen(syncProvider, (_, _) {});
    final initial = await container.read(syncProvider.future);
    expect(initial.chainTipHeight, 0);

    // The build schedules the initial sync; let it run.
    await pumpEventQueue();

    final started = container.read(syncProvider).requireValue;
    expectCatchUp(started);
  });
}
