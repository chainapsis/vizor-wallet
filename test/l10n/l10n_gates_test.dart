// Translation quality gates. Run in the default test lane, so a translation
// that drops a placeholder, invents a URL or number, breaks the glossary, or a
// migrated directory that gains a hardcoded string fails `fvm flutter test`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

import '../../tool/l10n/korean_arb.dart';
import '../../tool/l10n/native_strings.dart';
import '../../tool/l10n/strings.dart';

/// The file translators edit: `lib/l10n/source/` when a locale has a
/// generated ARB (Korean), otherwise the ARB itself.
Map<String, Object?> _readArb(String tag) {
  final source = File('lib/l10n/source/app_$tag.arb');
  final file = source.existsSync() ? source : File('lib/l10n/app_$tag.arb');
  return (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
}

List<String> _messageKeys(Map<String, Object?> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toList();

/// Placeholder names used in [message], limited to [declared] so the text of
/// an ICU branch such as `=1{1hr}` is not read as a placeholder.
Set<String> _placeholders(String message, Set<String> declared) => RegExp(
  r'\{(\w+)\s*[,}]',
).allMatches(message).map((m) => m.group(1)!).toSet().intersection(declared);

Set<String> _declaredPlaceholders(Map<String, Object?> template, String key) {
  final meta = template['@$key'];
  final placeholders = meta is Map ? meta['placeholders'] : null;
  return placeholders is Map ? placeholders.keys.cast<String>().toSet() : {};
}

Set<String> _urls(String message) =>
    RegExp(r'https?://[^\s"}]+').allMatches(message).map((m) => m[0]!).toSet();

Set<String> _numbers(String message) => RegExp(r'\d+(?:[.,]\d+)?')
    .allMatches(message.replaceAll(RegExp(r'=\d+\s*\{'), '{'))
    .map((m) => m[0]!)
    .toSet();

bool _containsWord(String text, String word) => RegExp(
  '(^|[^A-Za-z])${RegExp.escape(word)}(\$|[^A-Za-z])',
  caseSensitive: false,
).hasMatch(text);

void main() {
  final template = _readArb('en');
  final keys = _messageKeys(template);
  final translations = {
    for (final language in AppLanguage.values)
      if (language != AppLanguage.en) language: _readArb(language.tag),
  };
  final glossary =
      (loadYaml(File('lib/l10n/glossary.yaml').readAsStringSync())
              as YamlMap)['terms']
          as YamlList;

  test('app_ko.arb is generated from its source', () {
    expect(
      File(koreanOutputPath).readAsStringSync(),
      buildKoreanArb(File(koreanSourcePath).readAsStringSync()),
      reason:
          'Edit $koreanSourcePath, then run '
          '`fvm dart run tool/l10n/korean_arb.dart`.',
    );
  });

  test('native string tables are generated from the ARB files', () {
    expect(nativeLanguageSources.keys, [
      for (final language in AppLanguage.values) language.tag,
    ], reason: 'Every app language needs a native string table.');
    for (final MapEntry(key: path, value: expected)
        in buildNativeStringFiles().entries) {
      expect(
        File(path).readAsStringSync(),
        expected,
        reason:
            'Edit the native* keys in lib/l10n, then run '
            '`fvm dart run tool/l10n/native_strings.dart`.',
      );
    }
  });

  test('message keys are sorted so parallel changes rarely conflict', () {
    expect(keys, [...keys]..sort());
    for (final arb in translations.values) {
      final translated = _messageKeys(arb);
      expect(translated, [...translated]..sort());
    }
  });

  for (final MapEntry(key: language, value: arb) in translations.entries) {
    group(language.tag, () {
      test('has no keys missing from the English template', () {
        expect(_messageKeys(arb).toSet().difference(keys.toSet()), isEmpty);
      });

      if (language.released) {
        test('a released language translates every message', () {
          expect(keys.toSet().difference(_messageKeys(arb).toSet()), isEmpty);
        });
      }

      test('keeps placeholders, URLs and numbers of the source', () {
        for (final key in _messageKeys(arb)) {
          final source = template[key]! as String;
          final message = arb[key]! as String;
          final declared = _declaredPlaceholders(template, key);
          expect(
            _placeholders(message, declared),
            _placeholders(source, declared),
            reason: '$key placeholders',
          );
          expect(_urls(message), _urls(source), reason: '$key URLs');
          expect(
            _numbers(source).containsAll(_numbers(message)),
            isTrue,
            reason: '$key adds a number the source does not have',
          );
        }
      });

      test('follows the glossary', () {
        for (final key in _messageKeys(arb)) {
          final source = template[key]! as String;
          final message = arb[key]! as String;
          for (final term in glossary.cast<YamlMap>()) {
            final en = term['en'] as String;
            if (term['dnt'] == true) {
              if (source.contains(en)) {
                expect(message, contains(en), reason: '$key keeps "$en"');
              }
              continue;
            }
            if (!_containsWord(source, en)) continue;
            final entry = term[language.tag] as YamlMap?;
            if (entry == null) continue;
            for (final forbidden in (entry['forbidden'] as YamlList?) ?? []) {
              expect(
                message,
                isNot(contains(forbidden)),
                reason: '$key uses forbidden "$forbidden" for "$en"',
              );
            }
            if (entry['status'] == 'confirmed') {
              expect(
                message,
                contains(entry['term']),
                reason: '$key translates "$en" as "${entry['term']}"',
              );
            }
          }
        }
      });
    });
  }

  test('migrated directories have no hardcoded user-facing strings', () {
    final findings = scan(migratedDirs());
    expect(
      findings.map((f) => '${f.file}:${f.line}: "${f.text}"'),
      isEmpty,
      reason:
          'Move these to lib/l10n, or add `// l10n-ignore: <reason>` when a '
          'literal is not user copy.',
    );
  });
}
