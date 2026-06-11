import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/formatting/date_format.dart';

void main() {
  test('formatDayMonthTime renders the Figma send status format', () {
    expect(formatDayMonthTime(DateTime(2026, 5, 25, 13, 30)), '25 May, 13:30');
  });

  test('formatDayMonthTime zero-pads hours and minutes', () {
    expect(formatDayMonthTime(DateTime(2026, 1, 5, 9, 7)), '5 Jan, 09:07');
  });

  test('formatDayMonthTime abbreviates long month names', () {
    expect(formatDayMonthTime(DateTime(2026, 12, 31, 23, 59)), '31 Dec, 23:59');
  });
}
