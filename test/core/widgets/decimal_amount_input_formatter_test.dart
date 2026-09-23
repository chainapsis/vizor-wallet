import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/comma_to_dot_input_formatter.dart';
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

  TextEditingValue edit(String text, {TextSelection? selection}) =>
      TextEditingValue(
        text: text,
        selection: selection ?? TextSelection.collapsed(offset: text.length),
      );

  TextEditingValue format(TextEditingValue oldValue, TextEditingValue next) =>
      formatter.formatEditUpdate(
        oldValue,
        const CommaToDotInputFormatter().formatEditUpdate(oldValue, next),
      );

  test('prefixes typed separators and pasted fractions through the chain', () {
    for (final separator in ['.', ',']) {
      final initial = format(TextEditingValue.empty, edit(separator));
      expect(initial, edit('0.'));
      expect(format(initial, edit('${initial.text}5')), edit('0.5'));
      expect(
        format(TextEditingValue.empty, edit('${separator}25')),
        edit('0.25'),
      );
    }
  });

  test('shifts reversed selections without losing direction or affinity', () {
    final result = format(
      edit('12.25'),
      edit(
        '.25',
        selection: const TextSelection(
          baseOffset: 3,
          extentOffset: 1,
          affinity: TextAffinity.upstream,
          isDirectional: true,
        ),
      ),
    );
    expect(result.text, '0.25');
    expect(
      result.selection,
      const TextSelection(
        baseOffset: 4,
        extentOffset: 2,
        affinity: TextAffinity.upstream,
        isDirectional: true,
      ),
    );
    expect(
      format(
        TextEditingValue.empty,
        const TextEditingValue(text: '.5'),
      ).selection,
      const TextSelection.collapsed(offset: -1),
    );
  });

  test('restores a removed leading zero and allows backspace and clear', () {
    expect(
      format(
        edit('0.5'),
        edit('.5', selection: const TextSelection.collapsed(offset: 0)),
      ),
      edit('0.5', selection: const TextSelection.collapsed(offset: 1)),
    );
    final initial = format(TextEditingValue.empty, edit('.'));
    final withoutPoint = format(initial, edit('0'));
    expect(withoutPoint, edit('0'));
    expect(format(withoutPoint, edit('')), edit(''));
    expect(format(edit('0.5'), edit('')), edit(''));
  });

  test('defers zero insertion until composing is committed', () {
    final composing = edit(
      '.5',
    ).copyWith(composing: const TextRange(start: 0, end: 2));
    expect(format(TextEditingValue.empty, composing), same(composing));
    expect(
      format(composing, composing.copyWith(composing: TextRange.empty)),
      edit('0.5'),
    );
  });

  test('checks the final length including the inserted zero', () {
    const limited = DecimalAmountInputFormatter(
      maxFractionDigits: 2,
      maxLength: 3,
    );
    expect(
      limited.formatEditUpdate(TextEditingValue.empty, edit('.5')),
      edit('0.5'),
    );
    final previous = edit('0.5');
    expect(limited.formatEditUpdate(previous, edit('.55')), same(previous));
  });

  test('does not sanitize invalid pasted fractions', () {
    final previous = edit('0.5');
    for (final text in ['.5a', '..5', '.555', ',,5', ',555']) {
      expect(format(previous, edit(text)), same(previous));
    }
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
