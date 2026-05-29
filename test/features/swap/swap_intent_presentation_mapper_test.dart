import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_intent_presentation_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';

void main() {
  test('builds presentation rows from raw swap intent records', () {
    final intent = _intentFromRecord(
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
        depositAddress: 't1deposit',
        depositTxHash: 'deposit-txid',
        providerQuoteId: 'quote-1',
        swapFeeText: 'Included in shown rate',
        totalFeesText: '0.00002 ZEC',
        realisedSlippageText: '0.000758 USDC (0.07%)',
        slippageToleranceText: '0.00003 ZEC (1.0%)',
        minimumReceiveText: '0.2079 USDC',
        providerStatusRaw: 'PROCESSING',
        providerRefundInfo: const SwapProviderRefundInfo(
          minimumDepositText: '0.0029 ZEC',
          refundFeeText: '0.0001 ZEC',
        ),
        broadcastNotice: 'local storage failed after broadcast',
        oneClickRecipient: '0xrecipient',
        oneClickRefundTo: 'u1refund',
      ),
    );

    expect(intent.swapFeeText, 'Included in shown rate');
    expect(intent.totalFeesText, '0.00002 ZEC');
    expect(intent.realisedSlippageText, '0.000758 USDC (0.07%)');
    expect(intent.slippageToleranceText, '0.00003 ZEC (1.0%)');
    expect(intent.minimumReceiveText, '0.2079 USDC');
  });

  test('updates raw lifecycle facts from provider status snapshots', () {
    final createdAt = DateTime.utc(2026, 5, 7, 10);
    final checkedAt = DateTime.utc(2026, 5, 7, 10, 30);
    final intent = _intentFromRecord(
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
        depositAddress: 't1deposit',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );

    final updated = updateSwapIntentFromSnapshot(
      intent,
      SwapIntentSnapshot(
        id: 'swap-record',
        providerLabel: 'NEAR Intents',
        pairText: 'ZEC -> USDC',
        sellAmountText: '0.0030 ZEC',
        receiveEstimateText: '0.21 USDC',
        status: SwapIntentStatus.complete,
        nextAction: 'Complete',
        depositInstruction: const SwapDepositInstruction(
          asset: SwapAsset.zec,
          address: 't1deposit',
          expiresInLabel: '2h',
          reuseWarning: 'Do not reuse',
        ),
        providerStatusRaw: 'SUCCESS',
        nearIntentHash: 'intent-hash',
        destinationChainTxHash: 'destination-txid',
        swapFeeText: 'Included in shown rate',
        totalFeesText: '0.00002 ZEC',
        realisedSlippageText: '0.000758 USDC (0.07%)',
        slippageToleranceText: '0.00003 ZEC (1.0%)',
        minimumReceiveText: '0.2079 USDC',
      ),
      updatedAt: checkedAt,
      lastStatusCheckedAt: checkedAt,
    );

    expect(updated.status, SwapIntentStatus.complete);
    expect(updated.providerStatusRaw, 'SUCCESS');
    expect(updated.nearIntentHash, 'intent-hash');
    expect(updated.destinationChainTxHash, 'destination-txid');
    expect(updated.swapFeeText, 'Included in shown rate');
    expect(updated.totalFeesText, '0.00002 ZEC');
    expect(updated.realisedSlippageText, '0.000758 USDC (0.07%)');
    expect(updated.slippageToleranceText, '0.00003 ZEC (1.0%)');
    expect(updated.minimumReceiveText, '0.2079 USDC');
    expect(updated.createdAt, createdAt);
    expect(updated.updatedAt, checkedAt);
    expect(updated.completedAt, checkedAt);
    expect(updated.lastStatusCheckedAt, checkedAt);
  });

  test(
    'creates expired intent only when a pending deposit has no evidence',
    () {
      final now = DateTime.utc(2026, 5, 7, 12, 1);
      final quote = _quoteWithDepositDeadline(DateTime.utc(2026, 5, 7, 12));

      final intent = swapIntentFromSnapshot(
        snapshot: _pendingDepositSnapshot(),
        quote: quote,
        addressPlan: const SwapAddressPlan(
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          userExternalAddress: '0xrecipient',
          walletZecAddress: 'u1refund',
          oneClickRecipient: '0xrecipient',
          oneClickRefundTo: 'u1refund',
        ),
        accountUuid: 'account-1',
        now: now,
      );

      expect(intent.status, SwapIntentStatus.expired);
      expect(intent.nextAction, 'Start a fresh quote');
      expect(intent.completedAt, now);
    },
  );

  test('expires restored pending deposit records without evidence', () {
    final now = DateTime.utc(2026, 5, 7, 12, 1);
    final intent = _intentFromRecord(
      SwapIntentRecord(
        id: 'swap-record',
        providerLabel: 'NEAR Intents',
        pairText: 'ZEC -> USDC',
        sellAmountText: '0.0030 ZEC',
        receiveEstimateText: '0.21 USDC',
        status: SwapIntentStatus.awaitingDeposit,
        nextAction: 'Deposit ZEC',
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        depositAddress: 't1deposit',
        depositDeadline: DateTime.utc(2026, 5, 7, 12),
        createdAt: DateTime.utc(2026, 5, 7, 10),
        updatedAt: DateTime.utc(2026, 5, 7, 10),
      ),
      now: now,
    );

    expect(intent.status, SwapIntentStatus.expired);
    expect(intent.nextAction, 'Start a fresh quote');
    expect(intent.completedAt, now);
  });

  test('keeps restored pending deposit records live with tx evidence', () {
    final intent = _intentFromRecord(
      SwapIntentRecord(
        id: 'swap-record',
        providerLabel: 'NEAR Intents',
        pairText: 'ZEC -> USDC',
        sellAmountText: '0.0030 ZEC',
        receiveEstimateText: '0.21 USDC',
        status: SwapIntentStatus.awaitingDeposit,
        nextAction: 'Deposit ZEC',
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        depositAddress: 't1deposit',
        depositTxHash: 'local-deposit-txid',
        depositDeadline: DateTime.utc(2026, 5, 7, 12),
        createdAt: DateTime.utc(2026, 5, 7, 10),
        updatedAt: DateTime.utc(2026, 5, 7, 10),
      ),
      now: DateTime.utc(2026, 5, 7, 12, 1),
    );

    expect(intent.status, SwapIntentStatus.awaitingDeposit);
    expect(intent.status.isTerminal, false);
    expect(intent.depositTxHash, 'local-deposit-txid');
  });

  test('keeps expired pending deposit non-terminal when a local tx exists', () {
    final createdAt = DateTime.utc(2026, 5, 7, 10);
    final checkedAt = DateTime.utc(2026, 5, 7, 12, 1);
    final intent = _intentFromRecord(
      SwapIntentRecord(
        id: 'swap-record',
        providerLabel: 'NEAR Intents',
        pairText: 'ZEC -> USDC',
        sellAmountText: '0.0030 ZEC',
        receiveEstimateText: '0.21 USDC',
        status: SwapIntentStatus.awaitingDeposit,
        nextAction: 'Deposit ZEC',
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        depositAddress: 't1deposit',
        depositTxHash: 'local-deposit-txid',
        depositDeadline: DateTime.utc(2026, 5, 7, 12),
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );

    final updated = updateSwapIntentFromSnapshot(
      intent,
      _pendingDepositSnapshot(),
      updatedAt: checkedAt,
      lastStatusCheckedAt: checkedAt,
    );

    expect(updated.status, SwapIntentStatus.awaitingDeposit);
    expect(updated.status.isTerminal, false);
    expect(updated.depositTxHash, 'local-deposit-txid');
    expect(updated.lastStatusCheckedAt, checkedAt);
  });

  test(
    'keeps expired pending deposit non-terminal when provider reports origin tx',
    () {
      final createdAt = DateTime.utc(2026, 5, 7, 10);
      final checkedAt = DateTime.utc(2026, 5, 7, 12, 1);
      final intent = _intentFromRecord(
        SwapIntentRecord(
          id: 'swap-record',
          providerLabel: 'NEAR Intents',
          pairText: 'ZEC -> USDC',
          sellAmountText: '0.0030 ZEC',
          receiveEstimateText: '0.21 USDC',
          status: SwapIntentStatus.awaitingDeposit,
          nextAction: 'Deposit ZEC',
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          depositAddress: 't1deposit',
          depositDeadline: DateTime.utc(2026, 5, 7, 12),
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );

      final updated = updateSwapIntentFromSnapshot(
        intent,
        _pendingDepositSnapshot(originChainTxHash: 'provider-origin-txid'),
        updatedAt: checkedAt,
        lastStatusCheckedAt: checkedAt,
      );

      expect(updated.status, SwapIntentStatus.awaitingDeposit);
      expect(updated.status.isTerminal, false);
      expect(updated.originChainTxHash, 'provider-origin-txid');
    },
  );

  test('deposit helpers preserve tx hash and broadcast notice', () {
    final createdAt = DateTime.utc(2026, 5, 7, 10);
    final checkpointedAt = DateTime.utc(2026, 5, 7, 10, 5);
    final completedAt = DateTime.utc(2026, 5, 7, 10, 30);
    final intent = _intentFromRecord(
      SwapIntentRecord(
        id: 'swap-record',
        providerLabel: 'NEAR Intents',
        pairText: 'ZEC -> USDC',
        sellAmountText: '0.0030 ZEC',
        receiveEstimateText: '0.21 USDC',
        status: SwapIntentStatus.awaitingDeposit,
        nextAction: 'Deposit ZEC',
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        depositAddress: 't1deposit',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );

    final checkpointed = swapIntentWithDepositCheckpoint(
      intent,
      txHash: 'deposit-txid',
      broadcastNotice: 'local storage failed after broadcast',
      clearStatusError: false,
      clearBroadcastNotice: false,
      updatedAt: checkpointedAt,
    );

    final updated = swapIntentWithDepositSnapshot(
      checkpointed,
      SwapIntentSnapshot(
        id: 'swap-record',
        providerLabel: 'NEAR Intents',
        pairText: 'ZEC -> USDC',
        sellAmountText: '0.0030 ZEC',
        receiveEstimateText: '0.21 USDC',
        status: SwapIntentStatus.complete,
        nextAction: 'Complete',
        depositInstruction: const SwapDepositInstruction(
          asset: SwapAsset.zec,
          address: 't1deposit',
          expiresInLabel: '2h',
          reuseWarning: 'Do not reuse',
        ),
        providerStatusRaw: 'SUCCESS',
      ),
      txHash: 'deposit-txid',
      updatedAt: completedAt,
    );

    expect(checkpointed.depositTxHash, 'deposit-txid');
    expect(checkpointed.statusError, 'local storage failed after broadcast');
    expect(
      checkpointed.broadcastNotice,
      'local storage failed after broadcast',
    );
    expect(updated.status, SwapIntentStatus.complete);
    expect(updated.depositTxHash, 'deposit-txid');
    expect(updated.statusError, 'local storage failed after broadcast');
    expect(updated.broadcastNotice, 'local storage failed after broadcast');
    expect(updated.createdAt, createdAt);
    expect(updated.updatedAt, completedAt);
    expect(updated.completedAt, completedAt);
  });

  test('persistence records force the scoped account uuid', () {
    final intent = _intentFromRecord(
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
        depositAddress: 't1deposit',
        providerQuoteId: 'quote-1',
        accountUuid: 'stale-account',
      ),
    );

    final record = swapIntentRecordForPersistence(
      intent,
      accountUuid: 'active-account',
    );

    expect(record.accountUuid, 'active-account');
  });
}

SwapIntent _intentFromRecord(SwapIntentRecord record, {DateTime? now}) {
  return swapIntentsFromRecords([record], now: now).single;
}

SwapQuote _quoteWithDepositDeadline(DateTime deadline) {
  return SwapQuote.estimate(
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    amount: 0.003,
    depositDeadline: deadline,
  );
}

SwapIntentSnapshot _pendingDepositSnapshot({String? originChainTxHash}) {
  return SwapIntentSnapshot(
    id: 'swap-record',
    providerLabel: 'NEAR Intents',
    pairText: 'ZEC -> USDC',
    sellAmountText: '0.0030 ZEC',
    receiveEstimateText: '0.21 USDC',
    status: SwapIntentStatus.awaitingDeposit,
    nextAction: 'Send ZEC to the one-time deposit address',
    depositInstruction: const SwapDepositInstruction(
      asset: SwapAsset.zec,
      address: 't1deposit',
      expiresInLabel: 'expired',
      reuseWarning: 'Do not reuse',
      deadline: null,
    ),
    providerStatusRaw: 'PENDING_DEPOSIT',
    originChainTxHash: originChainTxHash,
  );
}
