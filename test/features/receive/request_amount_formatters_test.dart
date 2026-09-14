import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_formatters.dart';

void main() {
  TextEditingValue edit(String text, {TextSelection? selection}) =>
      TextEditingValue(
        text: text,
        selection: selection ?? TextSelection.collapsed(offset: text.length),
      );

  TextEditingValue format(TextEditingValue next, {bool isUsd = false}) =>
      requestAmountInputFormatters(isUsd: isUsd).fold(
        next,
        (value, formatter) =>
            formatter.formatEditUpdate(TextEditingValue.empty, value),
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

  test('maps reversed selection through stripping and zero insertion', () {
    final input = edit(
      'x.5y6',
      selection: const TextSelection(
        baseOffset: 5,
        extentOffset: 2,
        affinity: TextAffinity.upstream,
        isDirectional: true,
      ),
    );
    expect(
      format(input),
      edit(
        '0.56',
        selection: const TextSelection(
          baseOffset: 4,
          extentOffset: 2,
          affinity: TextAffinity.upstream,
          isDirectional: true,
        ),
      ),
    );
    expect(
      format(
        edit('12..3', selection: const TextSelection.collapsed(offset: 4)),
      ),
      edit('12.3', selection: const TextSelection.collapsed(offset: 3)),
    );
  });

  test(
    'retains truncation rules and clamps selection to the retained text',
    () {
      expect(format(edit('1.123456789')), edit('1.12345678'));
      expect(format(edit('1.234'), isUsd: true), edit('1.23'));
      expect(format(edit('123456789012345678')), edit('12345678901234567'));
      expect(format(edit('1234567890123'), isUsd: true), edit('123456789012'));
      expect(
        format(
          edit('1.234', selection: const TextSelection.collapsed(offset: 2)),
          isUsd: true,
        ),
        edit('1.23', selection: const TextSelection.collapsed(offset: 2)),
      );
    },
  );

  test('does not rewrite active composition and sanitizes on commit', () {
    final composing = edit(
      'x.5',
    ).copyWith(composing: const TextRange(start: 0, end: 3));
    expect(format(composing), same(composing));
    expect(format(composing.copyWith(composing: TextRange.empty)), edit('0.5'));
  });

  test('keeps empty input and absent selection safe', () {
    final empty = edit('');
    expect(format(empty), same(empty));
    expect(format(edit('abc')), edit(''));
    expect(
      format(const TextEditingValue(text: '.5')),
      const TextEditingValue(text: '0.5'),
    );
  });
}
