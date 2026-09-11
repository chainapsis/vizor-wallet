import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/decimal_amount_input_formatter.dart';

void main() {
  const formatter = DecimalAmountInputFormatter(maxFractionDigits: 2);

  test('returns valid edits without changing selection or composing range', () {
    const oldValue = TextEditingValue(text: '12.34');
    const newValue = TextEditingValue(
      text: '129.34',
      selection: TextSelection(baseOffset: 2, extentOffset: 4),
      composing: TextRange(start: 1, end: 3),
    );

    expect(formatter.formatEditUpdate(oldValue, newValue), same(newValue));
  });

  test('allows empty and leading-decimal edits without rewriting them', () {
    const oldValue = TextEditingValue(text: '1');
    const emptyValue = TextEditingValue(
      selection: TextSelection.collapsed(offset: 0),
    );
    const leadingDecimalValue = TextEditingValue(
      text: '.5',
      selection: TextSelection.collapsed(offset: 2),
    );

    expect(formatter.formatEditUpdate(oldValue, emptyValue), same(emptyValue));
    expect(
      formatter.formatEditUpdate(oldValue, leadingDecimalValue),
      same(leadingDecimalValue),
    );
  });

  test('rejects invalid characters and a second decimal point', () {
    const oldValue = TextEditingValue(
      text: '12.3',
      selection: TextSelection.collapsed(offset: 2),
    );

    expect(
      formatter.formatEditUpdate(
        oldValue,
        const TextEditingValue(text: '12a.3'),
      ),
      same(oldValue),
    );
    expect(
      formatter.formatEditUpdate(
        oldValue,
        const TextEditingValue(text: '12..3'),
      ),
      same(oldValue),
    );
  });

  test('rejects edits beyond the configured fraction digits', () {
    const oldValue = TextEditingValue(text: '12.34');

    expect(
      formatter.formatEditUpdate(
        oldValue,
        const TextEditingValue(text: '12.345'),
      ),
      same(oldValue),
    );
  });

  test('enforces an optional total length without truncating the edit', () {
    const lengthFormatter = DecimalAmountInputFormatter(
      maxFractionDigits: 8,
      maxLength: 5,
    );
    const oldValue = TextEditingValue(
      text: '12.34',
      selection: TextSelection.collapsed(offset: 1),
    );

    expect(
      lengthFormatter.formatEditUpdate(
        oldValue,
        const TextEditingValue(text: '123.45'),
      ),
      same(oldValue),
    );
  });
}
