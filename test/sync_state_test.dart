import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  test('pendingBalance is the explicit pending pool sum', () {
    final state = SyncState(
      transparentBalance: BigInt.from(100),
      saplingBalance: BigInt.from(20),
      orchardBalance: BigInt.from(30),
      transparentPendingBalance: BigInt.from(3),
      saplingPendingBalance: BigInt.from(4),
      orchardPendingBalance: BigInt.from(5),
      spendableBalance: BigInt.from(50),
      totalBalance: BigInt.from(162),
    );

    expect(state.pendingBalance, BigInt.from(12));
  });

  test('display spendable defaults to the authoritative balance', () {
    final state = SyncState(spendableBalance: BigInt.from(50));

    expect(state.displaySpendableBalance, BigInt.from(50));
    expect(
      state.displaySpendableFreshness,
      SpendableBalanceFreshness.authoritative,
    );
    expect(state.isUsingCompletedSpendableSnapshot, isFalse);
  });

  test('only a completed account snapshot is eligible for preservation', () {
    final completed = SyncState(
      hasBalanceData: true,
      scannedHeight: 100,
      chainTipHeight: 100,
      spendableBalance: BigInt.from(50),
    );

    expect(
      SyncState.shouldPreserveCompletedSpendable(
        previous: completed,
        requested: true,
      ),
      isTrue,
    );
    expect(
      SyncState.shouldPreserveCompletedSpendable(
        previous: completed,
        requested: false,
      ),
      isFalse,
    );
    expect(
      SyncState.shouldPreserveCompletedSpendable(
        previous: completed.copyWith(scannedHeight: 99),
        requested: true,
      ),
      isFalse,
    );
    expect(
      SyncState.shouldPreserveCompletedSpendable(
        previous: completed.copyWith(hasBalanceData: false),
        requested: true,
      ),
      isFalse,
    );
    expect(
      SyncState.shouldPreserveCompletedSpendable(
        previous: completed.copyWith(
          scannedHeight: 99,
          displaySpendableFreshness:
              SpendableBalanceFreshness.lastCompletedSync,
        ),
        requested: true,
      ),
      isTrue,
    );
  });

  test('incremental sync keeps the last completed spendable display', () {
    final previous = SyncState(
      spendableBalance: BigInt.zero,
      displaySpendableBalance: BigInt.from(50),
      displaySpendableFreshness: SpendableBalanceFreshness.lastCompletedSync,
      orchardPendingBalance: BigInt.from(1000),
    );

    final resolved = SyncState.resolveSpendableDisplay(
      previous: previous,
      authoritativeSpendable: BigInt.zero,
      hasAuthoritativeBalance: true,
      syncComplete: false,
    );

    expect(resolved.balance, BigInt.from(50));
    expect(resolved.freshness, SpendableBalanceFreshness.lastCompletedSync);
  });

  test('completed sync replaces the snapshot with the Rust balance', () {
    final previous = SyncState(
      spendableBalance: BigInt.zero,
      displaySpendableBalance: BigInt.from(50),
      displaySpendableFreshness: SpendableBalanceFreshness.lastCompletedSync,
    );

    final spent = SyncState.resolveSpendableDisplay(
      previous: previous,
      authoritativeSpendable: BigInt.zero,
      hasAuthoritativeBalance: true,
      syncComplete: true,
    );
    final unchanged = SyncState.resolveSpendableDisplay(
      previous: previous,
      authoritativeSpendable: BigInt.from(50),
      hasAuthoritativeBalance: true,
      syncComplete: true,
    );

    expect(spent.balance, BigInt.zero);
    expect(spent.freshness, SpendableBalanceFreshness.authoritative);
    expect(unchanged.balance, BigInt.from(50));
    expect(unchanged.freshness, SpendableBalanceFreshness.authoritative);
  });

  test('failed completion read retains the last verified display', () {
    final previous = SyncState(
      spendableBalance: BigInt.zero,
      displaySpendableBalance: BigInt.from(50),
      displaySpendableFreshness: SpendableBalanceFreshness.lastCompletedSync,
    );

    final resolved = SyncState.resolveSpendableDisplay(
      previous: previous,
      authoritativeSpendable: BigInt.zero,
      hasAuthoritativeBalance: false,
      syncComplete: true,
    );

    expect(resolved.balance, BigInt.from(50));
    expect(resolved.freshness, SpendableBalanceFreshness.lastCompletedSync);
  });

  test('displayPercentage defaults to actual percentage', () {
    final state = SyncState(percentage: 0.25);

    expect(state.percentage, 0.25);
    expect(state.displayPercentage, 0.25);
  });

  test(
    'displayPercentage can advance independently from actual percentage',
    () {
      final state = SyncState(percentage: 0.25);
      final displayed = state.copyWith(displayPercentage: 0.30);

      expect(displayed.percentage, 0.25);
      expect(displayed.displayPercentage, 0.30);
    },
  );

  test('displayPercentage can be reset below a previous display value', () {
    final state = SyncState(percentage: 0.30, displayPercentage: 0.50);
    final reset = state.copyWith(percentage: 0.25, displayPercentage: 0.25);

    expect(reset.percentage, 0.25);
    expect(reset.displayPercentage, 0.25);
  });

  test('display target defaults to actual percentage', () {
    final state = SyncState(percentage: 0.25);

    expect(state.displayTargetPercentage, 0.25);
    expect(state.displayTargetBlocks, 0);
  });

  test('copyWith can update display target independently', () {
    final state = SyncState(percentage: 0.25);
    final next = state.copyWith(
      displayTargetPercentage: 0.40,
      displayTargetBlocks: 150,
    );

    expect(next.percentage, 0.25);
    expect(next.displayTargetPercentage, 0.40);
    expect(next.displayTargetBlocks, 150);
  });

  test('scopedToAccount preserves data for the owning account', () {
    final tx = _tx('a' * 64);
    final state = SyncState(
      accountUuid: 'account-a',
      hasAccountScopedData: true,
      percentage: 0.75,
      scannedHeight: 10,
      chainTipHeight: 20,
      totalBalance: BigInt.from(123),
      spendableBalance: BigInt.from(100),
      recentTransactions: [tx],
    );

    final scoped = state.scopedToAccount('account-a');

    expect(scoped.accountUuid, 'account-a');
    expect(scoped.hasDataForAccount('account-a'), isTrue);
    expect(scoped.hasBalanceData, isTrue);
    expect(scoped.hasRecentTransactionsData, isTrue);
    expect(scoped.totalBalance, BigInt.from(123));
    expect(scoped.spendableBalance, BigInt.from(100));
    expect(scoped.displaySpendableBalance, BigInt.from(100));
    expect(scoped.recentTransactions, [tx]);
    expect(scoped.percentage, 0.75);
  });

  test('scopedToAccount clears account data for a different account', () {
    final state = SyncState(
      accountUuid: 'account-a',
      hasAccountScopedData: true,
      isSyncing: true,
      percentage: 0.75,
      displayPercentage: 0.50,
      displayTargetPercentage: 0.80,
      displayTargetBlocks: 120,
      scannedHeight: 10,
      chainTipHeight: 20,
      totalBalance: BigInt.from(123),
      spendableBalance: BigInt.from(100),
      recentTransactions: [_tx('a' * 64)],
    );

    final scoped = state.scopedToAccount('account-b');

    expect(scoped.accountUuid, 'account-b');
    expect(scoped.belongsToAccount('account-b'), isTrue);
    expect(scoped.hasDataForAccount('account-b'), isFalse);
    expect(scoped.totalBalance, BigInt.zero);
    expect(scoped.spendableBalance, BigInt.zero);
    expect(scoped.displaySpendableBalance, BigInt.zero);
    expect(scoped.recentTransactions, isEmpty);
    expect(scoped.isSyncing, isTrue);
    expect(scoped.percentage, 0.75);
    expect(scoped.displayPercentage, 0.50);
    expect(scoped.displayTargetPercentage, 0.80);
    expect(scoped.displayTargetBlocks, 120);
    expect(scoped.scannedHeight, 10);
    expect(scoped.chainTipHeight, 20);
  });

  test('cleared account state is scoped but not renderable account data', () {
    final state = SyncState(
      accountUuid: 'account-a',
      hasAccountScopedData: true,
      totalBalance: BigInt.from(123),
      recentTransactions: [_tx('a' * 64)],
    );

    final cleared = state.withoutAccountScopedData(accountUuid: 'account-b');

    expect(cleared.belongsToAccount('account-b'), isTrue);
    expect(cleared.hasDataForAccount('account-b'), isFalse);
    expect(cleared.hasBalanceData, isFalse);
    expect(cleared.hasRecentTransactionsData, isFalse);
    expect(cleared.totalBalance, BigInt.zero);
    expect(cleared.recentTransactions, isEmpty);
  });

  test('partial account state preserves loaded pieces without rendering', () {
    final state = SyncState(
      accountUuid: 'account-a',
      hasBalanceData: true,
      totalBalance: BigInt.from(123),
    );

    expect(state.belongsToAccount('account-a'), isTrue);
    expect(state.hasDataForAccount('account-a'), isFalse);
    expect(state.hasBalanceData, isTrue);
    expect(state.hasRecentTransactionsData, isFalse);
    expect(state.totalBalance, BigInt.from(123));

    final completed = state.copyWith(
      hasRecentTransactionsData: true,
      recentTransactions: [_tx('b' * 64)],
    );

    expect(completed.hasDataForAccount('account-a'), isTrue);
    expect(completed.totalBalance, BigInt.from(123));
    expect(completed.recentTransactions, hasLength(1));
  });
}

rust_sync.TransactionInfo _tx(String txidHex) {
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
