import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/activity/swap_activity_row_items_provider.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_deposit_broadcast_result.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';

void main() {
  test('exposes persisted swap records as activity row items', () async {
    final createdAt = DateTime.utc(2026, 5, 7, 10);
    final updatedAt = DateTime.utc(2026, 5, 7, 10, 30);
    final store = _FakeSwapActivityStore({
      'account-1': [
        SwapIntentRecord(
          id: 'swap-record',
          providerLabel: 'NEAR Intents',
          pairText: 'ZEC -> USDC',
          sellAmountText: '0.0030 ZEC',
          receiveEstimateText: '0.21 USDC',
          status: SwapIntentStatus.processing,
          nextAction: 'Swap is processing',
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          depositTxHash: 'zec-deposit-txid',
          createdAt: createdAt,
          updatedAt: updatedAt,
        ),
      ],
    });
    final container = ProviderContainer(
      overrides: [swapActivityStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    final items = await container.read(
      swapActivityRowItemsProvider('account-1').future,
    );

    expect(items, hasLength(1));
    expect(items.single.intentId, 'swap-record');
    expect(items.single.providerLabel, 'NEAR Intents');
    expect(items.single.sellAmountText, '0.0030 ZEC');
    expect(items.single.receiveEstimateText, '0.21 USDC');
    expect(items.single.status, SwapIntentStatus.processing);
    expect(items.single.direction, SwapDirection.zecToExternal);
    expect(items.single.externalAsset, SwapAsset.usdc);
    expect(items.single.depositTxHash, 'zec-deposit-txid');
    expect(items.single.activityTimestamp, createdAt);
  });

  test(
    'pending-swap gate counts only non-terminal swaps with confirmed deposit evidence',
    () async {
      final past = DateTime.utc(2020, 1, 1);
      final future = DateTime.utc(2100, 1, 1);
      final store = _FakeSwapActivityStore({
        'account-1': [
          // Nothing sent, deadline passed -> resolves to expired -> not counted.
          _pendingCountRecord(id: 'no-evidence', depositDeadline: past),
          // Nothing sent yet, still within deadline -> non-terminal but no
          // confirmed evidence -> not counted (don't over-block before a
          // deposit exists).
          _pendingCountRecord(id: 'awaiting-not-sent', depositDeadline: future),
          // Local ZEC deposit created but never broadcast (pendingBroadcast):
          // not confirmed evidence, so it expires past the deadline -> not
          // counted (this was the permanent-deadlock case).
          _pendingCountRecord(
            id: 'pending-broadcast',
            depositDeadline: past,
            depositTxHash: 'local-only-txid',
            broadcastStatus: SwapDepositBroadcastStatus.pendingBroadcast,
          ),
          // Same pending_broadcast but still within deadline: still not
          // confirmed evidence -> not counted.
          _pendingCountRecord(
            id: 'pending-broadcast-future',
            depositDeadline: future,
            depositTxHash: 'local-only-txid',
            broadcastStatus: SwapDepositBroadcastStatus.pendingBroadcast,
          ),
          // Clean ZEC deposit broadcast (no notice) -> confirmed -> counted.
          _pendingCountRecord(
            id: 'clean-broadcast',
            depositDeadline: future,
            depositTxHash: 'zec-deposit-txid',
          ),
          // ZEC deposit broadcast but local storage failed: tx DID reach the
          // network -> confirmed evidence -> counted, even though a
          // broadcastNotice UI message was set.
          _pendingCountRecord(
            id: 'storage-failed-broadcast',
            depositDeadline: future,
            depositTxHash: 'storage-failed-txid',
            broadcastStatus: SwapDepositBroadcastStatus.broadcastedStorageFailed,
          ),
          // Provider observed the source-chain deposit -> confirmed -> counted.
          _pendingCountRecord(
            id: 'deposit-observed',
            status: SwapIntentStatus.depositObserved,
            originChainTxHash: 'origin-txid',
          ),
          // Provider progress states prove that a deposit exists even when
          // the status payload omits transaction hashes.
          _pendingCountRecord(
            id: 'processing-without-hash',
            status: SwapIntentStatus.processing,
          ),
          _pendingCountRecord(
            id: 'incomplete-without-hash',
            status: SwapIntentStatus.incompleteDeposit,
          ),
          // A positive provider-reported amount must also prevent the local
          // deadline resolver from expiring and unblocking the account.
          _pendingCountRecord(
            id: 'amount-only-deposit',
            depositDeadline: past,
            depositedAmountText: '0.0025 ZEC',
          ),
          // User claimed the deposit (pressed "I've deposited"), still within
          // deadline -> ZEC may be incoming -> counted.
          _pendingCountRecord(
            id: 'claimed',
            depositDeadline: future,
            depositClaimedAt: DateTime.utc(2026, 5, 29),
          ),
          // Terminal -> not counted.
          _pendingCountRecord(id: 'done', status: SwapIntentStatus.complete),
        ],
      });
      final container = ProviderContainer(
        overrides: [swapActivityStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      final count = await container.read(
        swapPendingIntentCountProvider('account-1').future,
      );

      // Broadcast evidence, provider status/amount evidence, and the claimed
      // deposit all represent funds that could strand at the account address.
      expect(count, 7);
    },
  );

  test('row items use resolved status so the list agrees with the panel', () async {
    final past = DateTime.utc(2020, 1, 1);
    final store = _FakeSwapActivityStore({
      'account-1': [
        // Past deadline, no on-chain evidence -> the row must show the resolved
        // `expired` (Swap failed), not the raw `awaitingDeposit` ("Swapping...").
        _pendingCountRecord(id: 'no-evidence', depositDeadline: past),
        // Past deadline but a deposit tx exists -> carve-out keeps awaitingDeposit.
        _pendingCountRecord(
          id: 'with-evidence',
          depositDeadline: past,
          depositTxHash: 'zec-deposit-txid',
        ),
      ],
    });
    final container = ProviderContainer(
      overrides: [swapActivityStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    final items = await container.read(
      swapActivityRowItemsProvider('account-1').future,
    );
    final byId = {for (final item in items) item.intentId: item};

    expect(byId['no-evidence']!.status, SwapIntentStatus.expired);
    expect(byId['with-evidence']!.status, SwapIntentStatus.awaitingDeposit);
  });
}

SwapIntentRecord _pendingCountRecord({
  required String id,
  SwapIntentStatus status = SwapIntentStatus.awaitingDeposit,
  DateTime? depositDeadline,
  String? depositTxHash,
  String? originChainTxHash,
  String? depositedAmountText,
  String? broadcastStatus,
  DateTime? depositClaimedAt,
}) {
  final createdAt = DateTime.utc(2020, 1, 1);
  return SwapIntentRecord(
    id: id,
    providerLabel: 'NEAR Intents',
    pairText: 'ZEC -> USDC',
    sellAmountText: '0.0030 ZEC',
    receiveEstimateText: '0.21 USDC',
    status: status,
    nextAction: 'Swap',
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositDeadline: depositDeadline,
    depositTxHash: depositTxHash,
    originChainTxHash: originChainTxHash,
    providerRefundInfo: depositedAmountText == null
        ? null
        : SwapProviderRefundInfo(depositedAmountText: depositedAmountText),
    broadcastStatus: broadcastStatus,
    depositClaimedAt: depositClaimedAt,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

class _FakeSwapActivityStore implements SwapActivityStore {
  const _FakeSwapActivityStore(this.recordsByAccount);

  final Map<String, List<SwapIntentRecord>> recordsByAccount;

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async {
    return recordsByAccount[accountUuid] ?? const [];
  }

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {
    throw UnsupportedError('saveRecords is not used by this test');
  }

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {
    throw UnsupportedError('deleteForAccount is not used by this test');
  }
}
