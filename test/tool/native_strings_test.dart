import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/l10n/korean_arb.dart' show wordJoiner;
import '../../tool/l10n/native_strings.dart';

NativeStringTable parse({
  required Map<String, Object?> en,
  Map<String, Object?> ko = const {},
}) => parseNativeStrings({'en': jsonEncode(en), 'ko': jsonEncode(ko)});

void main() {
  test('reads native keys only, sorted, without Korean word joiners', () {
    final table = parse(
      en: {
        'nativeB': 'Second',
        'nativeA': 'First',
        'commonCancel': 'Cancel',
        'natives': 'Not a native key',
        '@nativeA': {'description': 'A.'},
      },
      ko: {'nativeA': '첫$wordJoiner번$wordJoiner째'},
    );
    expect(table.keys, ['nativeA', 'nativeB']);
    expect(table.messages['ko'], {'nativeA': '첫번째'});
  });

  test('rejects ICU plurals and undeclared placeholders', () {
    expect(
      () => parse(
        en: {
          'nativeCount':
              '{count, plural, =1{1 account} other{{count} accounts}}',
          '@nativeCount': {
            'placeholders': {'count': <String, Object?>{}},
          },
        },
      ),
      throwsFormatException,
    );
    expect(
      () => parse(en: {'nativeName': 'Hello {name}'}),
      throwsFormatException,
    );
  });

  test('escapes literals for Swift and Kotlin', () {
    final table = parse(
      en: {
        'nativeQuote': r'Say "hi" \ pay $5',
        'nativeArg': 'Failed: {reason}',
        '@nativeArg': {
          'placeholders': {'reason': <String, Object?>{}},
        },
      },
      ko: {'nativeQuote': '안녕'},
    );
    final swift = buildNativeSwift(table);
    expect(
      swift,
      contains(r'case .nativeQuote: return "Say \"hi\" \\ pay $5"'),
    );
    expect(swift, contains(r'case "ko": template = ko[key] ?? en(key)'));
    expect(swift, contains('.nativeQuote: "안녕",'));
    final kotlin = buildNativeKotlin(table);
    expect(
      kotlin,
      contains(r'NativeString.nativeQuote -> "Say \"hi\" \\ pay \$5"'),
    );
    expect(kotlin, contains('NativeString.nativeArg -> "Failed: {reason}"'));
    expect(kotlin, contains('"ko" -> ko[key]'));
  });
}
