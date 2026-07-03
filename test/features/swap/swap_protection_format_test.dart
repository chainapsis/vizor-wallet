import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_asset.dart';

void main() {
  group('formatSwapProtectionPercent', () {
    test('non-positive / non-finite values render 0.0%', () {
      expect(formatSwapProtectionPercent(0), '0.0%');
      expect(formatSwapProtectionPercent(-1), '0.0%');
      expect(formatSwapProtectionPercent(double.nan), '0.0%');
      expect(formatSwapProtectionPercent(double.infinity), '0.0%');
    });

    test('whole / >= 1 percentages keep one decimal', () {
      expect(formatSwapProtectionPercent(1), '1.0%');
      expect(formatSwapProtectionPercent(5), '5.0%');
      expect(formatSwapProtectionPercent(2.5), '2.5%');
    });

    test('sub-1 percentages trim trailing zeros without a dangling dot', () {
      expect(formatSwapProtectionPercent(0.5), '0.5%');
      expect(formatSwapProtectionPercent(0.45), '0.45%');
      expect(formatSwapProtectionPercent(0.05), '0.05%');
    });

    test('values that round up to 1.00 render 1.0%, never "1.%"', () {
      // Regression: 0.999 -> toStringAsFixed(2) == "1.00" used to be trimmed
      // to "1." and rendered as "(1.%)" on the review screen.
      expect(formatSwapProtectionPercent(0.999), '1.0%');
      expect(formatSwapProtectionPercent(0.9999), '1.0%');
      expect(formatSwapProtectionPercent(0.995), '1.0%');
      for (final value in [0.999, 0.9999, 0.995, 0.45, 0.5, 0.05, 1.0, 5.0]) {
        final out = formatSwapProtectionPercent(value);
        expect(out.endsWith('.%'), isFalse, reason: '"$out" has a dangling dot');
      }
    });
  });
}
