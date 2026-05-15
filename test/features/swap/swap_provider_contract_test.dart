import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/static_near_intents_swap_provider.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';

void main() {
  test('provider contract quotes ZEC into an external asset', () async {
    const provider = StaticNearIntentsSwapProvider();

    final quote = await provider.quote(
      const SwapQuoteRequest(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        sellAmount: 1.5,
        destination: '0xabc123',
      ),
    );

    expect(quote.providerLabel, 'NEAR Intents');
    expect(quote.sellAsset, SwapAsset.zec);
    expect(quote.receiveAsset, SwapAsset.usdc);
    expect(quote.pairText, 'ZEC -> USDC');
    expect(quote.receiveEstimateText, '~105.26 USDC');
    expect(quote.rateText, '1 ZEC = 70.17 USDC');
    expect(quote.depositInstruction.asset, SwapAsset.zec);
    expect(quote.depositInstruction.reuseWarning, 'Do not reuse this address');
  });

  test(
    'provider contract quotes an external asset into shielded ZEC',
    () async {
      const provider = StaticNearIntentsSwapProvider();

      final quote = await provider.quote(
        const SwapQuoteRequest(
          direction: SwapDirection.externalToZec,
          externalAsset: SwapAsset.usdc,
          sellAmount: 140.35,
          destination: 'u1shielded-zec-destination',
        ),
      );

      expect(quote.sellAsset, SwapAsset.usdc);
      expect(quote.receiveAsset, SwapAsset.zec);
      expect(quote.pairText, 'USDC -> ZEC');
      expect(quote.receiveEstimateText, '~2.0000 ZEC');
      expect(quote.rateText, '1 USDC = 0.0143 ZEC');
      expect(quote.depositInstruction.asset, SwapAsset.usdc);
    },
  );

  test('startSwap returns direction-specific initial intent status', () async {
    const provider = StaticNearIntentsSwapProvider();
    final quote = await provider.quote(
      const SwapQuoteRequest(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        sellAmount: 140.35,
        destination: 'u1shielded-zec-destination',
      ),
    );

    final intent = await provider.startSwap(quote);

    expect(intent.id, 'swap-new');
    expect(intent.status, SwapIntentStatus.awaitingExternalDeposit);
    expect(intent.nextAction, 'Send USDC to the one-time deposit address');
    expect(intent.pairText, 'USDC -> ZEC');
  });
}
