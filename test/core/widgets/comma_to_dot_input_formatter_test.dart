import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/comma_to_dot_input_formatter.dart';

void main() {
  const formatter = CommaToDotInputFormatter();

  TextEditingValue value(String text, [int? offset]) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: offset ?? text.length),
  );

  test('rewrites a typed comma to a period', () {
    final result = formatter.formatEditUpdate(value('1'), value('1,'));
    expect(result.text, '1.');
  });

  test('rewrites a comma mid-string and keeps the caret offset', () {
    final result = formatter.formatEditUpdate(value('15'), value('1,5', 2));
    expect(result.text, '1.5');
    expect(result.selection.baseOffset, 2);
  });

  test('leaves period-only input untouched', () {
    final next = value('1.5');
    final result = formatter.formatEditUpdate(value('1.'), next);
    expect(result, next);
  });

  test('leaves comma-free input untouched', () {
    final next = value('123');
    final result = formatter.formatEditUpdate(value('12'), next);
    expect(result, next);
  });
}
