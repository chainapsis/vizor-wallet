// Characters produced by intl rather than ARB messages (dates, compact
// amounts, NaN/infinity, currency symbols). Regenerated before font subsetting.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'generated_output.dart';

const uiFormattingCharactersPath = 'tool/l10n/ui_font_characters.json';

Future<String> buildUiFormattingCharacters() async {
  await initializeDateFormatting();
  final version = RegExp(
    r'\n  intl:\n[\s\S]*?\n    version: "([^"]+)"',
  ).firstMatch(File('pubspec.lock').readAsStringSync())!.group(1)!;
  final locales = <String, String>{};
  for (final locale in ['ko', 'zh']) {
    final dateSymbols = DateFormat.yMMMMEEEEd(
      locale,
    ).dateSymbols.serializeToMap();
    final characters = jsonEncode(dateSymbols).runes.toSet();
    final decimal = NumberFormat.decimalPattern(locale);
    for (final special in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      characters.addAll(decimal.format(special).runes);
    }
    for (final format in [
      decimal,
      NumberFormat.percentPattern(locale),
      NumberFormat.currency(locale: locale),
      NumberFormat.compact(locale: locale),
      NumberFormat.compactLong(locale: locale),
    ]) {
      for (final value in [
        for (var power = 0; power <= 18; power++) math.pow(10, power),
        -1234.56,
      ]) {
        characters.addAll(format.format(value).runes);
      }
    }
    locales[locale] = String.fromCharCodes(characters.toList()..sort());
  }
  final result = {'intl_version': version, 'locales': locales};
  return '${const JsonEncoder.withIndent('  ').convert(result)}\n';
}

Future<void> writeUiFormattingCharacters() async {
  if (!checkGeneratedOutputPath(uiFormattingCharactersPath)) {
    throw StateError('Unsafe formatting character output path');
  }
  final expected = await buildUiFormattingCharacters();
  final file = File(uiFormattingCharactersPath);
  if (!file.existsSync() || file.readAsStringSync() != expected) {
    file.writeAsStringSync(expected);
  }
}
