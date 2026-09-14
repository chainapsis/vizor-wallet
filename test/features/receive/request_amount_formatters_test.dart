import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/decimal_amount_input_formatter.dart';
import 'package:zcash_wallet/src/core/zcash/zip321_payment_request_builder.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_formatters.dart';

void main() {
  TextEditingValue edit(String text, {TextSelection? selection}) =>
      TextEditingValue(
        text: text,
        selection: selection ?? TextSelection.collapsed(offset: text.length),
      );

  TextEditingValue format(
    TextEditingValue next, {
    bool isUsd = false,
    TextEditingValue oldValue = TextEditingValue.empty,
  }) => requestAmountInputFormatters(isUsd: isUsd).fold(
    next,
    (value, formatter) => formatter.formatEditUpdate(oldValue, value),
  );

  test('keeps valid middle edits and directional selections unchanged', () {
    final middle = edit(
      '1293.45',
      selection: const TextSelection.collapsed(offset: 3),
    );
    expect(format(middle), same(middle));
    final range = edit(
      '123.45',
      selection: const TextSelection(
        baseOffset: 5,
        extentOffset: 2,
        affinity: TextAffinity.upstream,
        isDirectional: true,
      ),
    );
    expect(format(range), same(range));
  });

  test('prefixes leading separators and preserves the shifted caret', () {
    for (final separator in ['.', ',']) {
      expect(format(edit(separator)), edit('0.'));
      expect(format(edit('${separator}5')), edit('0.5'));
      expect(
        format(
          edit(
            '${separator}5',
            selection: const TextSelection.collapsed(offset: 1),
          ),
        ),
        edit('0.5', selection: const TextSelection.collapsed(offset: 2)),
      );
    }
  });

  test('uses the shared formatter with the request limits', () {
    for (final isUsd in [false, true]) {
      final formatter = requestAmountInputFormatters(isUsd: isUsd).last;
      expect(formatter, isA<DecimalAmountInputFormatter>());
      final decimal = formatter as DecimalAmountInputFormatter;
      expect(decimal.maxFractionDigits, isUsd ? 2 : 8);
      expect(decimal.maxLength, isUsd ? 12 : 17);
    }
  });

  test('rejects invalid edits without changing the previous selection', () {
    final previous = edit(
      '12.34',
      selection: const TextSelection(
        baseOffset: 4,
        extentOffset: 1,
        affinity: TextAffinity.upstream,
        isDirectional: true,
      ),
    );
    for (final isUsd in [false, true]) {
      for (final text in ['.5 ZEC', 'x.5y6', '12..3', '12,,3', 'abc']) {
        expect(
          format(edit(text), isUsd: isUsd, oldValue: previous),
          same(previous),
        );
      }
    }
  });

  test('accepts limit values and rejects overlong or overprecise edits', () {
    final previous = edit(
      '12.34',
      selection: const TextSelection.collapsed(offset: 2),
    );
    for (final isUsd in [false, true]) {
      final validFraction = isUsd ? '1.23' : '1.12345678';
      final validWhole = isUsd ? '123456789012' : '12345678901234567';
      expect(format(edit(validFraction), isUsd: isUsd), edit(validFraction));
      expect(format(edit(validWhole), isUsd: isUsd), edit(validWhole));
      for (final text in ['${validFraction}9', '${validWhole}8']) {
        expect(
          format(edit(text), isUsd: isUsd, oldValue: previous),
          same(previous),
        );
        expect(format(edit(text), isUsd: isUsd), TextEditingValue.empty);
      }
    }
  });

  test('defers leading zero until valid composition is committed', () {
    final composing = edit(
      '.5',
    ).copyWith(composing: const TextRange(start: 0, end: 2));
    expect(format(composing), same(composing));
    final committed = format(
      composing.copyWith(composing: TextRange.empty),
      oldValue: composing,
    );
    expect(committed, edit('0.5'));
    expect(normalizeZip321Amount(committed.text), '0.5');
    // Invalid composing edits follow the same rejection rule as other fields.
    final invalid = edit(
      'x.5',
    ).copyWith(composing: const TextRange(start: 0, end: 3));
    expect(format(invalid, oldValue: edit('1')), edit('1'));
  });

  test('keeps empty input and absent selection safe', () {
    final empty = edit('');
    expect(format(empty), same(empty));
    expect(format(edit('abc')), TextEditingValue.empty);
    expect(
      format(const TextEditingValue(text: '.5')),
      const TextEditingValue(text: '0.5'),
    );
  });
}
