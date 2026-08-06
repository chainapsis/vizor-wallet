import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/formatting/sync_status_label.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  test('a busy network only aborts a restart that changes the route', () {
    // Switching to Tor with a direct channel still up would leak.
    expect(
      shouldAbortRestartForBusyNetwork(
        quiescent: false,
        changesTransport: true,
      ),
      isTrue,
    );
    // An endpoint change or post-broadcast refresh keeps the same transport,
    // so a slow teardown must not cost the session its sync and polling.
    expect(
      shouldAbortRestartForBusyNetwork(
        quiescent: false,
        changesTransport: false,
      ),
      isFalse,
    );
    expect(
      shouldAbortRestartForBusyNetwork(quiescent: true, changesTransport: true),
      isFalse,
    );
  });

  test('migration entry restarts a sync from an older foreground epoch', () {
    expect(
      shouldRestartSyncForMigrationEntry(
        hasAttachedSync: true,
        activeSyncStartedInForeground: true,
        activeSyncForegroundEpoch: 2,
        currentForegroundEpoch: 3,
      ),
      isTrue,
    );
  });

  test('migration entry joins a sync started in the current foreground', () {
    expect(
      shouldRestartSyncForMigrationEntry(
        hasAttachedSync: true,
        activeSyncStartedInForeground: true,
        activeSyncForegroundEpoch: 3,
        currentForegroundEpoch: 3,
      ),
      isFalse,
    );
  });

  test('migration entry restarts a sync that began in background', () {
    expect(
      shouldRestartSyncForMigrationEntry(
        hasAttachedSync: true,
        activeSyncStartedInForeground: false,
        activeSyncForegroundEpoch: 3,
        currentForegroundEpoch: 3,
      ),
      isTrue,
    );
  });

  test(
    'clearCachedWalletDbPath forces the next DB path lookup to refresh',
    () async {
      final resolvedPaths = ['old-wallet.db', 'new-wallet.db'];
      var resolveCount = 0;
      final notifier = SyncNotifier(
        walletDbPathResolver: () async => resolvedPaths[resolveCount++],
      );

      expect(await notifier.resolveWalletDbPathForTesting(), 'old-wallet.db');
      expect(await notifier.resolveWalletDbPathForTesting(), 'old-wallet.db');
      expect(resolveCount, 1);

      notifier.clearCachedWalletDbPath();

      expect(await notifier.resolveWalletDbPathForTesting(), 'new-wallet.db');
      expect(resolveCount, 2);
    },
  );

  test('exclusive Rust sync operations are serialized and bracketed', () async {
    late _ExclusiveRustSyncTestNotifier notifier;
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        syncProvider.overrideWith(
          () => notifier = _ExclusiveRustSyncTestNotifier(),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);

    final firstRelease = Completer<void>();
    final firstStarted = Completer<void>();
    var secondStarted = false;
    final first = notifier.runWithExclusiveRustSync(() async {
      firstStarted.complete();
      await firstRelease.future;
      return 'first';
    });
    await firstStarted.future;
    final second = notifier.runWithExclusiveRustSync(() async {
      secondStarted = true;
      return 'second';
    });

    await Future<void>.delayed(Duration.zero);
    expect(secondStarted, isFalse);
    firstRelease.complete();

    expect(await Future.wait([first, second]), ['first', 'second']);
    expect(notifier.pauseCount, 2);
    expect(notifier.resumeCount, 2);
  });

  test('refreshAfterUnlock propagates DB path resolution failures', () async {
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_ExistingAccountNotifier.new),
        syncProvider.overrideWith(
          () => _BalanceRefreshTestSyncNotifier(
            () async => throw StateError('wallet path unavailable'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);

    await expectLater(
      container.read(syncProvider.notifier).refreshAfterUnlock(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'wallet path unavailable',
        ),
      ),
    );
  });

  test('successful queued refresh recovers an earlier pass failure', () async {
    final firstPathResolution = Completer<String>();
    var pathResolutionCount = 0;
    late _BalanceRefreshTestSyncNotifier notifier;
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_ExistingAccountNotifier.new),
        syncProvider.overrideWith(
          () => notifier = _BalanceRefreshTestSyncNotifier(() {
            pathResolutionCount++;
            if (pathResolutionCount == 1) return firstPathResolution.future;
            return Future.value('wallet.db');
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);

    final firstRefresh = notifier.refreshAfterUnlock();
    final queuedRefresh = notifier.refreshAfterUnlock();
    firstPathResolution.completeError(StateError('temporary path failure'));

    await expectLater(Future.wait([firstRefresh, queuedRefresh]), completes);
    expect(pathResolutionCount, 2);
    expect(notifier.balanceReadCount, 1);
  });

  test('in-flight progress exits quietly after notifier disposal', () async {
    final resolverStarted = Completer<void>();
    final dbPath = Completer<String>();
    late _LifecycleTestSyncNotifier notifier;
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        syncProvider.overrideWith(
          () => notifier = _LifecycleTestSyncNotifier(() async {
            resolverStarted.complete();
            return dbPath.future;
          }),
        ),
      ],
    );
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);

    final handling = notifier.handleSyncProgressForTesting(
      const SyncProgressEvent(
        scannedHeight: 10,
        chainTipHeight: 20,
        percentage: 0.5,
        displayTargetPercentage: 0.5,
        displayTargetBlocks: 0,
        isSyncing: true,
        isComplete: false,
        hasNewTx: false,
      ),
    );
    await resolverStarted.future;

    container.dispose();
    dbPath.complete('wallet.db');

    await expectLater(handling, completes);
  });

  test('in-flight progress cannot replace a newer sync failure', () async {
    final resolverStarted = Completer<void>();
    final dbPath = Completer<String>();
    late _LifecycleTestSyncNotifier notifier;
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_ExistingAccountNotifier.new),
        syncProvider.overrideWith(
          () => notifier = _LifecycleTestSyncNotifier(() async {
            resolverStarted.complete();
            return dbPath.future;
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);

    final handling = notifier.handleSyncProgressForTesting(
      const SyncProgressEvent(
        scannedHeight: 10,
        chainTipHeight: 100,
        percentage: 0,
        displayTargetPercentage: 0,
        displayTargetBlocks: 0,
        isSyncing: true,
        isComplete: false,
        hasNewTx: false,
      ),
    );
    await resolverStarted.future;

    final failure = classifySyncFailure(StateError('sync failed'));
    notifier.replaceState(
      SyncState(
        accountUuid: _accountUuid,
        failure: failure,
        error: failure.rawMessage,
        lastSyncFailedAt: DateTime.utc(2026, 7, 29),
      ),
    );
    dbPath.complete('wallet.db');
    await handling;

    final current = container.read(syncProvider).requireValue;
    expect(
      SyncStatusLabel.from(current).label,
      'Syncing failed. Unknown error...',
    );
    expect(current.failure, same(failure));
    expect(current.isSyncing, isFalse);
  });

  test(
    'unavailable switch balance clears balances but keeps fetched history',
    () async {
      final fetchedTx = _transaction('b' * 64);
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(
            () => _UnavailableSwitchBalanceNotifier(fetchedTx),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(syncProvider, (_, _) {});
      await container.read(syncProvider.future);

      await container.read(syncProvider.notifier).refreshAfterAccountSwitch();

      final current = container.read(syncProvider).requireValue;
      expect(current.accountUuid, _accountUuid);
      expect(current.hasBalanceData, isFalse);
      expect(current.displaySpendableBalance, BigInt.zero);
      expect(current.displayOrchardBalance, BigInt.zero);
      expect(current.displayTotalBalance, BigInt.zero);
      expect(current.hasRecentTransactionsData, isTrue);
      expect(current.recentTransactions, [fetchedTx]);
    },
  );

  test(
    'unavailable switch balance evicts the restored account snapshot',
    () async {
      late _BalanceRefreshTestSyncNotifier notifier;
      final initial = SyncState(
        accountUuid: _accountUuid,
        hasAccountScopedData: true,
        orchardBalance: BigInt.from(40),
        displayOrchardBalance: BigInt.from(40),
        spendableBalance: BigInt.from(40),
        displaySpendableBalance: BigInt.from(40),
        totalBalance: BigInt.from(40),
        displayTotalBalance: BigInt.from(40),
      );
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(
            () => notifier = _BalanceRefreshTestSyncNotifier(
              () async => 'wallet.db',
              initialState: initial,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(syncProvider, (_, _) {});
      await container.read(syncProvider.future);

      // Cache account 1, then switch back to restore that cached snapshot.
      notifier.handleAccountSwitchForTesting(_otherAccountUuid);
      notifier.handleAccountSwitchForTesting(_accountUuid);
      expect(
        container.read(syncProvider).requireValue.displaySpendableBalance,
        BigInt.from(40),
      );

      await notifier.refreshAfterAccountSwitch();
      expect(
        container.read(syncProvider).requireValue.displaySpendableBalance,
        BigInt.zero,
      );

      // The cleared, incomplete state cannot overwrite the cache when leaving.
      // Switching back must therefore remain blank rather than restoring 40.
      notifier.handleAccountSwitchForTesting(_otherAccountUuid);
      notifier.handleAccountSwitchForTesting(_accountUuid);

      final current = container.read(syncProvider).requireValue;
      expect(current.accountUuid, _accountUuid);
      expect(current.hasBalanceData, isFalse);
      expect(current.displaySpendableBalance, BigInt.zero);
      expect(current.displayOrchardBalance, BigInt.zero);
      expect(current.displayTotalBalance, BigInt.zero);
    },
  );

  test('concurrent refresh triggers coalesce into one trailing pass', () async {
    // The defect this pins: switch, unlock, resume, mempool and recovery
    // each called `_refreshBalance` directly, so overlapping triggers ran
    // concurrent passes contending on the wallet DB. Behaviour assertions
    // pass either way — only the read count catches a regression.
    late _BalanceRefreshTestSyncNotifier notifier;
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_ExistingAccountNotifier.new),
        syncProvider.overrideWith(
          () => notifier = _BalanceRefreshTestSyncNotifier(
            () async => 'wallet.db',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);
    notifier.gateFirstBalanceRead();

    final inFlight = notifier.refreshAfterUnlock();
    await notifier.firstBalanceReadStarted;

    // Three more triggers arrive while that pass is still reading.
    final queued = [
      notifier.refreshAfterSend(),
      notifier.refreshAfterUnlock(),
      notifier.refreshAfterSend(),
    ];
    notifier.releaseFirstBalanceRead();
    await Future.wait([inFlight, ...queued]);

    expect(
      notifier.balanceReadCount,
      2,
      reason:
          'the in-flight pass plus one trailing pass covering all three '
          'queued triggers; without coalescing this is 4',
    );
  });

  test(
    'a switch refresh queued mid-flight still clears the restored snapshot',
    () async {
      // Queued triggers are collapsed into one trailing pass, so that
      // pass must carry every requesting caller's flags. If the switch's
      // clear-on-unavailable request is dropped by the queue, the stale
      // restored balance stays pinned on screen.
      final fetchedTx = _transaction('c' * 64);
      late _BalanceRefreshTestSyncNotifier notifier;
      final restored = SyncState(
        accountUuid: _accountUuid,
        hasAccountScopedData: true,
        orchardBalance: BigInt.from(40),
        displayOrchardBalance: BigInt.from(40),
        spendableBalance: BigInt.from(40),
        displaySpendableBalance: BigInt.from(40),
        displaySpendableFreshness: SpendableBalanceFreshness.lastCompletedSync,
        totalBalance: BigInt.from(40),
        displayTotalBalance: BigInt.from(40),
        recentTransactions: [_transaction('a' * 64)],
      );
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(
            () => notifier = _BalanceRefreshTestSyncNotifier(
              () async => 'wallet.db',
              initialState: restored,
              history: [fetchedTx],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(syncProvider, (_, _) {});
      await container.read(syncProvider.future);
      notifier.gateFirstBalanceRead();

      // An unrelated refresh occupies the single-flight slot first.
      final inFlight = notifier.refreshAfterUnlock();
      await notifier.firstBalanceReadStarted;
      final switchRefresh = notifier.refreshAfterAccountSwitch();
      notifier.releaseFirstBalanceRead();
      await Future.wait([inFlight, switchRefresh]);

      final current = container.read(syncProvider).requireValue;
      expect(current.hasBalanceData, isFalse);
      expect(current.displaySpendableBalance, BigInt.zero);
      expect(current.displayOrchardBalance, BigInt.zero);
      expect(current.displayTotalBalance, BigInt.zero);
      expect(current.recentTransactions, [fetchedTx]);
    },
  );
}

class _LifecycleTestSyncNotifier extends SyncNotifier {
  _LifecycleTestSyncNotifier(Future<String> Function() walletDbPathResolver)
    : super(walletDbPathResolver: walletDbPathResolver);

  @override
  Future<SyncState> build() async => SyncState();

  void replaceState(SyncState next) {
    state = AsyncData(next);
  }
}

class _ExclusiveRustSyncTestNotifier extends SyncNotifier {
  _ExclusiveRustSyncTestNotifier()
    : super(walletDbPathResolver: () async => 'wallet.db');

  var pauseCount = 0;
  var resumeCount = 0;

  @override
  Future<SyncState> build() async => SyncState();

  @override
  Future<WalletMutationSyncPause> pauseForWalletMutation({
    FutureOr<void> Function()? onStoppingSync,
  }) async {
    pauseCount++;
    await onStoppingSync?.call();
    return const WalletMutationSyncPause(
      hadActiveSync: false,
      hadPolling: false,
      hadMempoolObserver: false,
    );
  }

  @override
  void resumeAfterWalletMutation(WalletMutationSyncPause pause) {
    resumeCount++;
  }
}

class _BalanceRefreshTestSyncNotifier extends SyncNotifier {
  _BalanceRefreshTestSyncNotifier(
    Future<String> Function() walletDbPathResolver, {
    this.initialState,
    this.history = const [],
  }) : super(walletDbPathResolver: walletDbPathResolver);

  final SyncState? initialState;
  final List<rust_sync.TransactionInfo> history;

  var balanceReadCount = 0;

  var _gateFirstBalanceRead = false;
  final _firstBalanceReadStarted = Completer<void>();
  final _firstBalanceReadReleased = Completer<void>();

  /// Hold the next balance read open so further refresh triggers arrive
  /// while a pass is genuinely in flight.
  void gateFirstBalanceRead() => _gateFirstBalanceRead = true;

  Future<void> get firstBalanceReadStarted => _firstBalanceReadStarted.future;

  void releaseFirstBalanceRead() => _firstBalanceReadReleased.complete();

  @override
  Future<SyncState> build() async => initialState ?? SyncState();

  @override
  Future<rust_sync.WalletBalance> readWalletBalance({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async {
    balanceReadCount++;
    if (_gateFirstBalanceRead && !_firstBalanceReadStarted.isCompleted) {
      _firstBalanceReadStarted.complete();
      await _firstBalanceReadReleased.future;
    }
    return _unavailableBalance;
  }

  @override
  Future<List<rust_sync.TransactionInfo>> readTransactionHistory({
    required String dbPath,
    required String network,
    int? limit,
    required String accountUuid,
  }) async => history;
}

class _UnavailableSwitchBalanceNotifier extends SyncNotifier {
  _UnavailableSwitchBalanceNotifier(this.fetchedTx)
    : super(walletDbPathResolver: () async => 'wallet.db');

  final rust_sync.TransactionInfo fetchedTx;

  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: _accountUuid,
    hasAccountScopedData: true,
    orchardBalance: BigInt.from(40),
    displayOrchardBalance: BigInt.from(40),
    spendableBalance: BigInt.from(40),
    displaySpendableBalance: BigInt.from(40),
    displaySpendableFreshness: SpendableBalanceFreshness.lastCompletedSync,
    totalBalance: BigInt.from(40),
    displayTotalBalance: BigInt.from(40),
    recentTransactions: [_transaction('a' * 64)],
  );

  @override
  Future<rust_sync.WalletBalance> readWalletBalance({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async => _unavailableBalance;

  @override
  Future<List<rust_sync.TransactionInfo>> readTransactionHistory({
    required String dbPath,
    required String network,
    int? limit,
    required String accountUuid,
  }) async => [fetchedTx];
}

const _accountUuid = 'account-1';
const _otherAccountUuid = 'account-2';

class _ExistingAccountNotifier extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [AccountInfo(uuid: _accountUuid, name: 'Account 1', order: 0)],
    activeAccountUuid: _accountUuid,
  );
}

final _unavailableBalance = rust_sync.WalletBalance(
  availability: rust_sync.WalletBalanceAvailability.summaryUnavailable,
  transparent: BigInt.zero,
  sapling: BigInt.zero,
  orchard: BigInt.zero,
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
  spendable: BigInt.zero,
  locked: BigInt.zero,
  total: BigInt.zero,
);

rust_sync.TransactionInfo _transaction(String txidHex) {
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: BigInt.one,
    expiredUnmined: false,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    blockTime: BigInt.from(1800000000),
    isTransparent: false,
    txKind: 'received',
    displayAmount: BigInt.one,
    displayPool: 'shielded',
    createdTime: BigInt.from(1800000000),
  );
}
