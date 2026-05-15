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
      receiveEstimate: '~105.25 USDC',
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
        SwapPrototypeField(label: 'Refund to', value: 't1refund'),
      ],
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
      depositAddress: 't1deposit',
      depositMemo: 'memo-7',
      depositTxHash: 'zec-txid',
      shieldTxHash: 'shield-txid',
      providerQuoteId: 'quote-1',
      providerSignature: 'quote-signature',
      providerStatusRaw: 'PROCESSING',
      lastStatusCheckedAt: DateTime.utc(2026, 5, 7, 10, 30),
      statusError: 'temporary status refresh failure',
      oneClickRecipient: '0xrecipient',
      oneClickRefundTo: 't1refund',
      depositDeadline: DateTime.utc(2026, 5, 7, 12),
    );

    await store.saveIntents([intent]);

    final restored = await store.loadIntents();

    expect(restored, hasLength(1));
    expect(restored.single.id, 't1deposit');
    expect(restored.single.direction, SwapDirection.zecToExternal);
    expect(restored.single.externalAsset, SwapAsset.usdc);
    expect(restored.single.depositAddress, 't1deposit');
    expect(restored.single.depositMemo, 'memo-7');
    expect(restored.single.depositTxHash, 'zec-txid');
    expect(restored.single.shieldTxHash, 'shield-txid');
    expect(restored.single.providerQuoteId, 'quote-1');
    expect(restored.single.providerSignature, 'quote-signature');
    expect(restored.single.providerStatusRaw, 'PROCESSING');
    expect(
      restored.single.lastStatusCheckedAt,
      DateTime.utc(2026, 5, 7, 10, 30),
    );
    expect(restored.single.statusError, 'temporary status refresh failure');
    expect(restored.single.oneClickRecipient, '0xrecipient');
    expect(restored.single.oneClickRefundTo, 't1refund');
    expect(restored.single.depositDeadline, DateTime.utc(2026, 5, 7, 12));
    expect(restored.single.status, SwapIntentStatus.processing);
    expect(restored.single.steps.single.label, 'Deposit observed');
    expect(restored.single.receipt.last.value, 't1refund');
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

  test('round-trips shielding failure recovery state', () async {
    const intent = SwapPrototypeIntent(
      id: '0xshieldfail',
      title: 'USDC to ZEC',
      pair: 'USDC -> ZEC',
      sellAmount: '140.350000 USDC',
      receiveEstimate: '~2.0000 ZEC',
      provider: 'NEAR Intents',
      status: SwapIntentStatus.shieldingFailed,
      nextAction: 'Retry shielding from the staging address',
      steps: [
        SwapPrototypeStep(
          label: 'Shielding failed',
          state: SwapPrototypeStepState.warning,
          evidence: 'Retry wallet shielding',
        ),
      ],
      exposure: [
        SwapPrototypeField(
          label: 'Recovery',
          value: 'retry shield; do not resend external deposit',
        ),
      ],
      receipt: [
        SwapPrototypeField(label: 'Receive address', value: 't1staging'),
      ],
      direction: SwapDirection.externalToZec,
      externalAsset: SwapAsset.usdc,
      depositAddress: '0xshieldfail',
      depositMemo: 'memo-7',
      providerQuoteId: 'quote-1',
      providerSignature: 'quote-signature',
      oneClickRecipient: 't1staging',
      oneClickRefundTo: '0xrefund',
    );

    await store.saveIntents([intent]);

    final restored = await store.loadIntents();

    expect(restored.single.status, SwapIntentStatus.shieldingFailed);
    expect(restored.single.oneClickRecipient, 't1staging');
    expect(restored.single.oneClickRefundTo, '0xrefund');
    expect(restored.single.steps.single.label, 'Shielding failed');
  });

  test('round-trips shield confirmation tracking state', () async {
    const intent = SwapPrototypeIntent(
      id: '0xshieldconfirm',
      title: 'USDC to ZEC',
      pair: 'USDC -> ZEC',
      sellAmount: '140.350000 USDC',
      receiveEstimate: '~2.0000 ZEC',
      provider: 'NEAR Intents',
      status: SwapIntentStatus.shieldingConfirming,
      nextAction: 'Waiting for shield transaction confirmation.',
      steps: [
        SwapPrototypeStep(
          label: 'Shielding confirming',
          state: SwapPrototypeStepState.active,
          evidence: 'Waiting for shield transaction confirmation.',
        ),
      ],
      exposure: [
        SwapPrototypeField(label: 'ZEC destination', value: 't1staging'),
      ],
      receipt: [SwapPrototypeField(label: 'Shield tx', value: 'shield-txid')],
      direction: SwapDirection.externalToZec,
      externalAsset: SwapAsset.usdc,
      depositAddress: '0xshieldconfirm',
      depositMemo: 'memo-7',
      shieldTxHash: 'shield-txid',
      providerQuoteId: 'quote-1',
      providerSignature: 'quote-signature',
      oneClickRecipient: 't1staging',
      oneClickRefundTo: '0xrefund',
    );

    await store.saveIntents([intent]);

    final restored = await store.loadIntents();

    expect(restored.single.status, SwapIntentStatus.shieldingConfirming);
    expect(restored.single.shieldTxHash, 'shield-txid');
    expect(restored.single.receipt.single.value, 'shield-txid');
  });
}
