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

  test(
    'transparentSpendableBalance aliases ordinary-send transparent balance',
    () {
      final state = SyncState(
        transparentBalance: BigInt.from(100),
        transparentPendingBalance: BigInt.from(300),
      );

      expect(state.transparentSpendableBalance, BigInt.from(100));
      expect(state.pendingBalance, BigInt.from(300));
    },
  );

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
    expect(scoped.recentTransactions, isEmpty);
    expect(scoped.isSyncing, isTrue);
    expect(scoped.percentage, 0.75);
    expect(scoped.displayPercentage, 0.50);
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
