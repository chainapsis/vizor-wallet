import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/activity/address_display.dart';

void main() {
  test('truncates long address head...tail', () {
    final a = 'u1${'x' * 60}';
    final t = truncateAddress(a);
    expect(t.contains('...'), isTrue);
    expect(t.length, lessThan(a.length));
  });
  test('short address returned as-is', () {
    expect(truncateAddress('u1abc'), 'u1abc');
  });
}
