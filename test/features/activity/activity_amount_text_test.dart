import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/activity/activity_amount_text.dart';

void main() {
  group('compactMobileActivityAmountText', () {
    test('compacts large amounts to a thousands marker within the budget', () {
      final compacted = compactMobileActivityAmountText('-12345.6789 ZEC');
      expect(compacted, '-12.345K ZEC');
      expect(
        compacted.length,
        lessThanOrEqualTo(mobileActivityAmountMaxCharacters),
      );
    });

    test('preserves tiny amounts at full precision', () {
      expect(
        compactMobileActivityAmountText('+0.00000001 ZEC'),
        '+0.00000001 ZEC',
      );
    });
  });
}
