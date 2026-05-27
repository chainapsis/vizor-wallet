import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_prototype_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_composer_preferences_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppSecureStore secureStore;
  late SwapActivityStore activityStore;
  late SwapComposerPreferencesStore preferencesStore;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    secureStore = AppSecureStore.instance;
    await secureStore.deleteAll();
    activityStore = AppSecureStoreSwapActivityStore(secureStore);
    preferencesStore = AppSecureStoreSwapComposerPreferencesStore(secureStore);
  });

  tearDown(() async {
    await secureStore.deleteAll();
  });

  test('round-trips the swap activity fields needed for recovery', () async {
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
      swapFeeText: 'Included in shown rate',
      slippageToleranceText: '0.015 ZEC (1.0%)',
      priceProtectionText: '1.0525 USDC (1.0%)',
      minimumReceiveText: '104.1975 USDC',
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

    await activityStore.saveRecords(
      accountUuid: 'account-1',
      records: [SwapIntentRecord.fromIntent(intent)],
    );

    final restored = await activityStore.loadRecords(accountUuid: 'account-1');

    expect(restored, hasLength(1));
    expect(restored.single.id, 't1deposit');
    expect(restored.single.accountUuid, 'account-1');
    expect(restored.single.direction, SwapDirection.zecToExternal);
    expect(restored.single.externalAsset, SwapAsset.usdc);
    expect(restored.single.pairText, 'ZEC -> USDC');
    expect(restored.single.sellAmountText, '1.5000 ZEC');
    expect(restored.single.receiveEstimateText, '105.25 USDC');
    expect(restored.single.depositAddress, 't1deposit');
    expect(restored.single.depositMemo, 'memo-7');
    expect(restored.single.depositTxHash, 'zec-txid');
    expect(restored.single.providerQuoteId, 'quote-1');
    expect(restored.single.providerSignature, 'quote-signature');
    expect(restored.single.swapFeeText, 'Included in shown rate');
    expect(restored.single.slippageToleranceText, '0.015 ZEC (1.0%)');
    expect(restored.single.priceProtectionText, '1.0525 USDC (1.0%)');
    expect(restored.single.minimumReceiveText, '104.1975 USDC');
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
  });

  test('keeps persisted swap activity scoped to its account', () async {
    final accountOneIntent = _minimalIntent(
      id: 'swap-account-1',
      accountUuid: 'account-1',
    );
    final accountTwoIntent = _minimalIntent(
      id: 'swap-account-2',
      accountUuid: 'account-2',
    );

    await activityStore.saveRecords(
      accountUuid: 'account-1',
      records: [SwapIntentRecord.fromIntent(accountOneIntent)],
    );
    await activityStore.saveRecords(
      accountUuid: 'account-2',
      records: [SwapIntentRecord.fromIntent(accountTwoIntent)],
    );

    final accountOne = await activityStore.loadRecords(
      accountUuid: 'account-1',
    );
    final accountTwo = await activityStore.loadRecords(
      accountUuid: 'account-2',
    );

    expect(accountOne.single.id, 'swap-account-1');
    expect(accountOne.single.accountUuid, 'account-1');
    expect(accountTwo.single.id, 'swap-account-2');
    expect(accountTwo.single.accountUuid, 'account-2');
  });

  test('persists swap activity in account-scoped secure storage', () async {
    final intent = _minimalIntent(
      id: 'swap-raw-record',
      accountUuid: 'account-1',
    );

    await activityStore.saveRecords(
      accountUuid: 'account-1',
      records: [SwapIntentRecord.fromIntent(intent)],
    );

    final raw = await secureStore.readString(
      swapActivityStorageKeyForTest('account-1'),
    );
    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    final records = decoded['records'] as List<dynamic>;

    expect(decoded['version'], 1);
    expect(records, hasLength(1));
    expect(records.single, containsPair('id', 'swap-raw-record'));
    expect(
      records.single,
      containsPair('providerQuoteId', 'quote-swap-raw-record'),
    );
    expect(raw, isNot(contains('"title"')));
    expect(raw, isNot(contains('"steps"')));
    expect(raw, isNot(contains('"exposure"')));
    expect(raw, isNot(contains('"receipt"')));
  });

  test('loads raw-list swap activity records', () async {
    await secureStore.writeString(
      swapActivityStorageKeyForTest('account-1'),
      jsonEncode([
        {
          'id': 'legacy-swap',
          'provider': 'NEAR Intents',
          'pair': 'ZEC -> USDC',
          'sellAmount': '1.0000 ZEC',
          'receiveEstimate': '100.00 USDC',
          'status': 'processing',
          'nextAction': 'Processing',
          'direction': 'zecToExternal',
          'depositAddress': 'legacy-swap',
          'providerQuoteId': 'quote-legacy-swap',
          'accountUuid': 'stale-account-value',
        },
      ]),
    );

    final restored = await activityStore.loadRecords(accountUuid: 'account-1');

    expect(restored, hasLength(1));
    expect(restored.single.id, 'legacy-swap');
    expect(restored.single.providerLabel, 'NEAR Intents');
    expect(restored.single.accountUuid, 'account-1');
    expect(restored.single.direction, SwapDirection.zecToExternal);
    expect(
      await secureStore.readString(swapActivityStorageKeyForTest('account-1')),
      isNotNull,
    );
  });

  test('round-trips only the last attempted swap pair', () async {
    const preferences = SwapComposerPreferences(
      direction: SwapDirection.externalToZec,
      externalAsset: SwapAsset.near,
      slippageBps: 125,
    );

    await preferencesStore.savePreferences(
      accountUuid: 'account-1',
      preferences: preferences,
    );

    final restored = await preferencesStore.loadPreferences(
      accountUuid: 'account-1',
    );

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
      final preferences = SwapComposerPreferences(
        direction: SwapDirection.zecToExternal,
        externalAsset: asset,
        slippageBps: 150,
      );

      await preferencesStore.savePreferences(
        accountUuid: 'account-1',
        preferences: preferences,
      );

      final restored = await preferencesStore.loadPreferences(
        accountUuid: 'account-1',
      );

      expect(restored, isNotNull);
      expect(restored!.direction, SwapDirection.zecToExternal);
      expect(restored.externalAsset, asset);
      expect(restored.externalAsset.assetId, 'nep141:base-usdc.example');
      expect(restored.externalAsset.chainTicker, 'base');
      expect(restored.slippageBps, 150);
    },
  );

  test(
    'keeps persisted swap composer preferences scoped to their account',
    () async {
      const accountOnePreferences = SwapComposerPreferences(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.near,
        slippageBps: 125,
      );
      const accountTwoPreferences = SwapComposerPreferences(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        slippageBps: 200,
      );

      await preferencesStore.savePreferences(
        accountUuid: 'account-1',
        preferences: accountOnePreferences,
      );
      await preferencesStore.savePreferences(
        accountUuid: 'account-2',
        preferences: accountTwoPreferences,
      );

      final accountOne = await preferencesStore.loadPreferences(
        accountUuid: 'account-1',
      );
      final accountTwo = await preferencesStore.loadPreferences(
        accountUuid: 'account-2',
      );

      expect(accountOne!.direction, SwapDirection.externalToZec);
      expect(accountOne.externalAsset, SwapAsset.near);
      expect(accountOne.slippageBps, 125);
      expect(accountTwo!.direction, SwapDirection.zecToExternal);
      expect(accountTwo.externalAsset, SwapAsset.usdc);
      expect(accountTwo.slippageBps, 200);
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
