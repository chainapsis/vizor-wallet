import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';

void main() {
  group('formatSwapRateAmount', () {
    test('keeps four significant digits and two decimals below 10,000', () {
      expect(formatSwapRateAmount(0.012910742), '0.01291');
      expect(formatSwapRateAmount(0.45951202), '0.4595');
      expect(formatSwapRateAmount(1.41831427), '1.418');
      expect(formatSwapRateAmount(11.04549868), '11.05');
      expect(formatSwapRateAmount(100), '100.00');
      expect(formatSwapRateAmount(796.73051), '796.73');
      expect(formatSwapRateAmount(1125), '1,125.00');
      expect(formatSwapRateAmount(1194.13035), '1,194.13');
      expect(formatSwapRateAmount(9999.99), '9,999.99');
    });

    test('compacts from 10,000 with K, M and B, truncating', () {
      expect(formatSwapRateAmount(10000), '10K');
      expect(formatSwapRateAmount(14270.83893), '14.27K');
      expect(formatSwapRateAmount(262799.9), '262.7K');
      expect(formatSwapRateAmount(1000000), '1M');
      expect(formatSwapRateAmount(1417708.22), '1.417M');
      expect(formatSwapRateAmount(229472622.48), '229.4M');
      expect(formatSwapRateAmount(166062565172.05), '166B');
      expect(formatSwapRateAmount(1.66e12), '1660B');
    });

    test('moves to K when rounding reaches 10,000', () {
      expect(formatSwapRateAmount(999.996), '1,000.00');
      expect(formatSwapRateAmount(9999.996), '10K');
    });

    test('shows a placeholder for a missing rate', () {
      expect(formatSwapRateAmount(0), '--');
      expect(formatSwapRateAmount(-1), '--');
      expect(formatSwapRateAmount(double.nan), '--');
      expect(formatSwapRateAmount(double.infinity), '--');
    });
  });

  test('swapZecRateText prices the external asset per ZEC', () {
    expect(swapZecRateText(SwapAsset.usdc, 796.73), '1 ZEC = 796.73 USDC');
    expect(swapZecRateText(SwapAsset.btc, 0.012910742), '1 ZEC = 0.01291 BTC');
    expect(swapZecRateText(SwapAsset.doge, 14270.84), '1 ZEC = 14.27K DOGE');
  });

  test('an estimate quotes ZEC first in both directions', () {
    for (final direction in SwapDirection.values) {
      final quote = SwapQuote.estimate(
        direction: direction,
        externalAsset: SwapAsset.usdc,
        amount: 10,
        externalPerZec: 796.73,
      );
      expect(quote.rateText, '1 ZEC = 796.73 USDC');
    }
  });
}
