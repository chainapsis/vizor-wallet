import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/receive/address_label_policy.dart';

void main() {
  test('trims and preserves a normal label', () {
    expect(normalizeAddressLabel('  Donations  '), 'Donations');
  });
  test('blank becomes null (clears the label)', () {
    expect(normalizeAddressLabel('   '), isNull);
    expect(normalizeAddressLabel(''), isNull);
  });
  test('truncates to max length', () {
    final long = 'x' * 100;
    expect(normalizeAddressLabel(long)!.length, kAddressLabelMaxLength);
  });
}
