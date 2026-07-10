import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

void main() {
  testWidgets(
    'Pay tracks initial and refreshed pricing snapshots before exposing estimates',
    (tester) async {
      final provider = _ControlledPricingSwapProvider();
      final container = ProviderContainer(
        overrides: [
          accountProvider.overrideWith(_EmptyAccountNotifier.new),
          swapIntentProvider.overrideWithValue(provider),
          swapPriceRefreshIntervalProvider.overrideWithValue(
            const Duration(seconds: 1),
          ),
          swapStatusPollIntervalProvider.overrideWithValue(
            const Duration(days: 1),
          ),
        ],
      );

      final notifier = container.read(swapStateProvider.notifier);
      notifier.preparePayFromShieldedZec();
      notifier.updateReceiveAmount('25');

      expect(container.read(swapStateProvider).pricingLoading, isTrue);
      expect(
        container.read(swapStateProvider).amountText,
        isNotEmpty,
        reason: 'The fallback estimate exists but must stay behind loading UI.',
      );

      provider.initial.complete(_pricingSnapshot(externalPerZec: 100));
      await tester.pump();
      await tester.pump();

      var state = container.read(swapStateProvider);
      expect(state.pricingLoading, isFalse);
      expect(state.amountText, '0.2500');
      expect(state.receiveFiatText, '25');

      notifier.updateReceiveAmount('50');
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      state = container.read(swapStateProvider);
      expect(provider.pricingRequests, 2);
      expect(provider.sawForcedRefresh, isTrue);
      expect(state.pricingLoading, isTrue);
      expect(state.amountText, '0.5000');

      provider.refresh.complete(_pricingSnapshot(externalPerZec: 200));
      await tester.pump();
      await tester.pump();

      state = container.read(swapStateProvider);
      expect(state.pricingLoading, isFalse);
      expect(state.amountText, '0.2500');
      expect(state.receiveFiatText, '50');

      container.dispose();
      await tester.pump();
    },
  );
}

SwapPricingSnapshot _pricingSnapshot({required double externalPerZec}) {
  return SwapPricingSnapshot(
    usdPrices: {SwapAsset.zec: externalPerZec, SwapAsset.usdc: 1},
  );
}

class _EmptyAccountNotifier extends AccountNotifier {
  @override
  AccountState build() => const AccountState();
}

class _ControlledPricingSwapProvider
    implements SwapProvider, SwapPricingProvider {
  final initial = Completer<SwapPricingSnapshot>();
  final refresh = Completer<SwapPricingSnapshot>();
  var pricingRequests = 0;
  var sawForcedRefresh = false;

  @override
  String get providerLabel => 'Controlled pricing';

  @override
  Future<SwapPricingSnapshot> loadPricingSnapshot({bool forceRefresh = false}) {
    pricingRequests += 1;
    sawForcedRefresh = sawForcedRefresh || forceRefresh;
    return pricingRequests == 1 ? initial.future : refresh.future;
  }

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async => const [
    SwapAsset.usdc,
  ];

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) {
    throw UnimplementedError();
  }

  @override
  Future<SwapIntentSnapshot> getStatus(String intentId, {String? depositMemo}) {
    throw UnimplementedError();
  }

  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) {
    throw UnimplementedError();
  }
}
