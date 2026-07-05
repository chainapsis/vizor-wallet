import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_asset.dart';

void main() {
  group('SwapAsset.formatAmount ETH precision', () {
    test('sub-0.001 ETH keeps ~4 significant figures instead of rounding to '
        '0.0001', () {
      // 0.01 ZEC -> ~0.00014835 ETH must not collapse to "0.0001" (which no
      // longer matches the attested/delivered amount). Regression for the
      // preview/review/on-chain amount mismatch.
      expect(SwapAsset.eth.formatAmount(0.00014835), '0.0001484');
      expect(SwapAsset.eth.formatAmountDown(0.00014835), '0.0001483');
    });

    test('a clean sub-0.001 amount trims trailing zeros', () {
      expect(SwapAsset.eth.formatAmount(0.0001), '0.0001');
      expect(SwapAsset.eth.formatAmount(0.00012), '0.00012');
    });

    test('amounts >= 0.001 keep the clean 4-decimal display', () {
      expect(SwapAsset.eth.formatAmount(0.0025), '0.0025');
      expect(SwapAsset.eth.formatAmount(0.0014), '0.0014');
      expect(SwapAsset.eth.formatAmount(1.2345), '1.2345');
    });

    test('ZEC and BTC display widths are unchanged', () {
      expect(SwapAsset.zec.formatAmount(1.98576), '1.9858');
      expect(SwapAsset.btc.formatAmount(0.00014835), '0.00014835');
    });
  });
}
