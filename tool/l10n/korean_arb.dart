// Builds lib/l10n/app_ko.arb from the translator-facing
// lib/l10n/source/app_ko.arb.
//
//   fvm dart run tool/l10n/korean_arb.dart          writes the generated file
//   fvm dart run tool/l10n/korean_arb.dart --check  fails if it is stale
//
// Flutter breaks Korean lines between any two syllables, splitting words.
// The generated file joins the characters of each word with U+2060 WORD
// JOINER, which renders as nothing and only removes the break opportunity,
// so lines break at spaces like CSS `word-break: keep-all`. Translators never
// see the joiners. A word longer than its line still wraps.
import 'dart:convert';
import 'dart:io';

import 'generated_output.dart';

const koreanSourcePath = 'lib/l10n/source/app_ko.arb';
const koreanOutputPath = 'lib/l10n/app_ko.arb';
const wordJoiner = '⁠';

bool _isHangul(int c) => c >= 0xAC00 && c <= 0xD7A3;

bool _isWordChar(int c) =>
    _isHangul(c) ||
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A);

bool _join(int a, int b) =>
    (_isWordChar(a) && _isWordChar(b) && (_isHangul(a) || _isHangul(b))) ||
    // A placeholder and the particle attached to it: `{name}님`, `총{count}`.
    (a == 0x7D && _isHangul(b)) ||
    (_isHangul(a) && b == 0x7B);

/// Joins the characters of each Korean word so lines break only at spaces.
String keepAll(String text) {
  final units = text.replaceAll(wordJoiner, '').codeUnits;
  final buffer = StringBuffer();
  for (var i = 0; i < units.length; i++) {
    buffer.writeCharCode(units[i]);
    if (i + 1 < units.length && _join(units[i], units[i + 1])) {
      buffer.write(wordJoiner);
    }
  }
  return buffer.toString();
}

String buildKoreanArb(String sourceJson) {
  final source = (jsonDecode(sourceJson) as Map).cast<String, Object?>();
  final output = {
    for (final MapEntry(:key, :value) in source.entries)
      key: key.startsWith('@') || value is! String ? value : keepAll(value),
  };
  return '${const JsonEncoder.withIndent('  ').convert(output)}\n';
}

void main(List<String> args) {
  final expected = buildKoreanArb(File(koreanSourcePath).readAsStringSync());
  if (!checkGeneratedOutputPath(koreanOutputPath)) return;
  final output = File(koreanOutputPath);
  if (args.contains('--check')) {
    if (!output.existsSync() || output.readAsStringSync() != expected) {
      stderr.writeln(
        '$koreanOutputPath is stale. Run '
        '`fvm dart run tool/l10n/korean_arb.dart`.',
      );
      exitCode = 1;
    }
    return;
  }
  output.writeAsStringSync(expected);
}
