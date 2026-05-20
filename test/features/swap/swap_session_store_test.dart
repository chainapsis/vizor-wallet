import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_prototype_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppSecureStore secureStore;
  late SwapSessionStore store;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    secureStore = AppSecureStore.instance;
    await secureStore.deleteAll();
    store = AppSecureStoreSwapSessionStore(secureStore);
  });

  tearDown(() async {
    await secureStore.deleteAll();
  });

  test('round-trips the swap session fields needed for recovery', () async {
    final intent = SwapPrototypeIntent(
      id: 't1deposit',
      title: 'ZEC to USDC',
      pair: 'ZEC -> USDC',
      sellAmount: '1.5000 ZEC',
      receiveEstimate: '105.25 USDC',
      provider: 'NEAR Intents',
      status: SwapIntentStatus.processing,
      nextAction: 'Swap is processing',
      steps: const [
        SwapPrototypeStep(
          label: 'Deposit observed',
          state: SwapPrototypeStepState.done,
          evidence: 'tx submitted',
        ),
      ],
      exposure: const [
        SwapPrototypeField(
          label: 'Third-party data',
          value: 'solver sees deposit tx and route',
        ),
      ],
      receipt: const [
        SwapPrototypeField(label: 'Swap id', value: 't1deposit'),
        SwapPrototypeField(label: 'Refund to', value: 'u1refund'),
      ],
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
      depositAddress: 't1deposit',
      depositMemo: 'memo-7',
      depositTxHash: 'zec-txid',
      providerQuoteId: 'quote-1',
      providerSignature: 'quote-signature',
      providerStatusRaw: 'PROCESSING',
      nearIntentHash: 'intent-hash-1',
      nearTransactionHash: 'near-tx-hash-1',
      originChainTxHash: 'origin-chain-tx-1',
      destinationChainTxHash: 'destination-chain-tx-1',
      providerRefundInfo: const SwapProviderRefundInfo(
        minimumDepositText: '1.485 ZEC',
        refundFeeText: '0.0001 ZEC',
        depositedAmountText: '1.5 ZEC',
        refundedAmountText: '0.01 ZEC',
        refundReason: 'UNUSED_INPUT',
      ),
      lastStatusCheckedAt: DateTime.utc(2026, 5, 7, 10, 30),
      statusError: 'temporary status refresh failure',
      oneClickRecipient: '0xrecipient',
      oneClickRefundTo: 'u1refund',
      depositDeadline: DateTime.utc(2026, 5, 7, 12),
      accountUuid: 'account-1',
    );

    await store.saveIntents(accountUuid: 'account-1', intents: [intent]);

    final restored = await store.loadIntents(accountUuid: 'account-1');

    expect(restored, hasLength(1));
    expect(restored.single.id, 't1deposit');
    expect(restored.single.accountUuid, 'account-1');
    expect(restored.single.direction, SwapDirection.zecToExternal);
    expect(restored.single.externalAsset, SwapAsset.usdc);
    expect(restored.single.depositAddress, 't1deposit');
    expect(restored.single.depositMemo, 'memo-7');
    expect(restored.single.depositTxHash, 'zec-txid');
    expect(restored.single.providerQuoteId, 'quote-1');
    expect(restored.single.providerSignature, 'quote-signature');
    expect(restored.single.providerStatusRaw, 'PROCESSING');
    expect(restored.single.nearIntentHash, 'intent-hash-1');
    expect(restored.single.nearTransactionHash, 'near-tx-hash-1');
    expect(restored.single.originChainTxHash, 'origin-chain-tx-1');
    expect(restored.single.destinationChainTxHash, 'destination-chain-tx-1');
    expect(restored.single.providerRefundInfo?.minimumDepositText, '1.485 ZEC');
    expect(restored.single.providerRefundInfo?.refundFeeText, '0.0001 ZEC');
    expect(restored.single.providerRefundInfo?.depositedAmountText, '1.5 ZEC');
    expect(restored.single.providerRefundInfo?.refundedAmountText, '0.01 ZEC');
    expect(restored.single.providerRefundInfo?.refundReason, 'UNUSED_INPUT');
    expect(
      restored.single.lastStatusCheckedAt,
      DateTime.utc(2026, 5, 7, 10, 30),
    );
    expect(restored.single.statusError, 'temporary status refresh failure');
    expect(restored.single.oneClickRecipient, '0xrecipient');
    expect(restored.single.oneClickRefundTo, 'u1refund');
    expect(restored.single.depositDeadline, DateTime.utc(2026, 5, 7, 12));
    expect(restored.single.status, SwapIntentStatus.processing);
    expect(restored.single.steps.single.label, 'Deposit observed');
    expect(restored.single.receipt.last.value, 'u1refund');
  });

  test('keeps persisted swap sessions scoped to their account', () async {
    final accountOneIntent = _minimalIntent(
      id: 'swap-account-1',
      accountUuid: 'account-1',
    );
    final accountTwoIntent = _minimalIntent(
      id: 'swap-account-2',
      accountUuid: 'account-2',
    );

    await store.saveIntents(
      accountUuid: 'account-1',
      intents: [accountOneIntent],
    );
    await store.saveIntents(
      accountUuid: 'account-2',
      intents: [accountTwoIntent],
    );

    final accountOne = await store.loadIntents(accountUuid: 'account-1');
    final accountTwo = await store.loadIntents(accountUuid: 'account-2');

    expect(accountOne.single.id, 'swap-account-1');
    expect(accountOne.single.accountUuid, 'account-1');
    expect(accountTwo.single.id, 'swap-account-2');
    expect(accountTwo.single.accountUuid, 'account-2');
  });

  test('round-trips only the last attempted swap pair', () async {
    const draft = SwapDraftSnapshot(
      direction: SwapDirection.externalToZec,
      externalAsset: SwapAsset.near,
      slippageBps: 125,
    );

    await store.saveDraft(draft);

    final restored = await store.loadDraft();

    expect(restored, isNotNull);
    expect(restored!.direction, SwapDirection.externalToZec);
    expect(restored.externalAsset, SwapAsset.near);
    expect(restored.slippageBps, 125);
  });

  test(
    'round-trips a live token-list asset as the last attempted pair',
    () async {
      final asset = SwapAsset.live(
        assetId: 'nep141:base-usdc.example',
        symbol: 'USDC',
        blockchain: 'base',
        decimals: 6,
      );
      final draft = SwapDraftSnapshot(
        direction: SwapDirection.zecToExternal,
        externalAsset: asset,
        slippageBps: 150,
      );

      await store.saveDraft(draft);

      final restored = await store.loadDraft();

      expect(restored, isNotNull);
      expect(restored!.direction, SwapDirection.zecToExternal);
      expect(restored.externalAsset, asset);
      expect(restored.externalAsset.assetId, 'nep141:base-usdc.example');
      expect(restored.externalAsset.chainTicker, 'base');
      expect(restored.slippageBps, 150);
    },
  );
}

SwapPrototypeIntent _minimalIntent({
  required String id,
  required String accountUuid,
}) {
  return SwapPrototypeIntent(
    id: id,
    title: 'ZEC to USDC',
    pair: 'ZEC -> USDC',
    sellAmount: '1.0000 ZEC',
    receiveEstimate: '100.00 USDC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.processing,
    nextAction: 'Processing',
    steps: const [],
    exposure: const [],
    receipt: const [],
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: id,
    providerQuoteId: 'quote-$id',
    accountUuid: accountUuid,
  );
}
