import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/activity/screens/activity_screen.dart';
import 'package:zcash_wallet/src/features/activity/swap_activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_intent_status.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  test(
    'pending transactions without timestamps sort before timestamped activity',
    () {
      final pending = activitySortKeyForTransaction(
        _transaction(
          txidHex: 'pending',
          minedHeight: BigInt.zero,
          blockTime: BigInt.zero,
          createdTime: BigInt.zero,
        ),
        sourceOrder: 0,
      );
      final confirmed = activitySortKeyForTransaction(
        _transaction(
          txidHex: 'confirmed',
          blockTime: BigInt.from(1800000000),
          createdTime: BigInt.from(1800000000),
        ),
        sourceOrder: 1,
      );

      final sorted = [confirmed, pending]..sort(compareActivityEntrySortKeys);

      expect(sorted.first, same(pending));
      expect(activitySectionTitleForSortKey(pending), 'This week');
    },
  );

  test('pending transactions with timestamps keep timestamp ordering', () {
    final olderPending = activitySortKeyForTransaction(
      _transaction(
        txidHex: 'older-pending',
        minedHeight: BigInt.zero,
        blockTime: BigInt.from(1780000000),
        createdTime: BigInt.from(1780000000),
      ),
      sourceOrder: 0,
    );
    final newerConfirmed = activitySortKeyForTransaction(
      _transaction(
        txidHex: 'newer-confirmed',
        blockTime: BigInt.from(1800000000),
        createdTime: BigInt.from(1800000000),
      ),
      sourceOrder: 1,
    );

    final sorted = [olderPending, newerConfirmed]
      ..sort(compareActivityEntrySortKeys);

    expect(olderPending.isPendingTransaction, isTrue);
    expect(sorted.first, same(newerConfirmed));
    expect(
      activitySectionTitleForSortKey(
        olderPending,
        now: DateTime.utc(2026, 6, 16),
      ),
      'May 2026',
    );
  });

  test('expired unmined transactions do not receive pending priority', () {
    final expired = activitySortKeyForTransaction(
      _transaction(
        txidHex: 'expired',
        minedHeight: BigInt.zero,
        expiredUnmined: true,
        blockTime: BigInt.zero,
        createdTime: BigInt.zero,
      ),
      sourceOrder: 0,
    );
    final confirmed = activitySortKeyForTransaction(
      _transaction(
        txidHex: 'confirmed',
        blockTime: BigInt.from(1800000000),
        createdTime: BigInt.from(1800000000),
      ),
      sourceOrder: 1,
    );

    final sorted = [expired, confirmed]..sort(compareActivityEntrySortKeys);

    expect(expired.isPendingTransaction, isFalse);
    expect(sorted.first, same(confirmed));
    expect(activitySectionTitleForSortKey(expired), 'Earlier');
  });

  test(
    'swap rows keep timestamp ordering regardless of in-progress status',
    () {
      final olderProcessing = activitySortKeyForSwapItem(
        _swapItem(
          status: SwapIntentStatus.processing,
          timestamp: DateTime.utc(2026, 6, 10, 12),
        ),
        sourceOrder: 0,
      );
      final newerCompleted = activitySortKeyForSwapItem(
        _swapItem(
          status: SwapIntentStatus.complete,
          timestamp: DateTime.utc(2026, 6, 12, 12),
        ),
        sourceOrder: 1,
      );

      final sorted = [olderProcessing, newerCompleted]
        ..sort(compareActivityEntrySortKeys);

      expect(olderProcessing.isPendingTransaction, isFalse);
      expect(sorted.first, same(newerCompleted));
    },
  );
}

rust_sync.TransactionInfo _transaction({
  required String txidHex,
  BigInt? minedHeight,
  bool expiredUnmined = false,
  BigInt? blockTime,
  BigInt? createdTime,
}) {
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: minedHeight ?? BigInt.from(2500000),
    expiredUnmined: expiredUnmined,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    blockTime: blockTime ?? BigInt.from(1800000000),
    isTransparent: false,
    txKind: expiredUnmined ? 'sent' : 'received',
    displayAmount: BigInt.from(120000000),
    displayPool: 'shielded',
    createdTime: createdTime ?? BigInt.from(1800000000),
  );
}

SwapActivityRowItem _swapItem({
  required SwapIntentStatus status,
  required DateTime timestamp,
}) {
  return SwapActivityRowItem(
    intentId: 'swap-${status.name}',
    providerLabel: 'NEAR Intents',
    sellAmountText: '1 ZEC',
    receiveEstimateText: '+10 USDC',
    status: status,
    activityTimestamp: timestamp,
  );
}
