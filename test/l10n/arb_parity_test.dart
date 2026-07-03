import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the localization contract: every user-facing key added to the
/// English template must ship with a Korean translation in the same change.
///
/// Missing Korean entries do not break the build — gen-l10n silently falls
/// back to the English text — so without this test a new feature can quietly
/// leave untranslated strings in the Korean UI.
void main() {
  Map<String, dynamic> readArb(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path is missing');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  Set<String> messageKeys(Map<String, dynamic> arb) {
    return arb.keys.where((k) => !k.startsWith('@')).toSet()..remove('@@locale');
  }

  test('every English message has a Korean translation (and vice versa)', () {
    final en = messageKeys(readArb('lib/l10n/app_en.arb'));
    final ko = messageKeys(readArb('lib/l10n/app_ko.arb'));

    expect(
      en.difference(ko),
      isEmpty,
      reason:
          'These keys exist in app_en.arb but are missing from app_ko.arb. '
          'Add the Korean translations (Korean users silently see English '
          'fallbacks otherwise).',
    );
    expect(
      ko.difference(en),
      isEmpty,
      reason:
          'These keys exist in app_ko.arb but not in the app_en.arb template. '
          'Remove them or add the English source string.',
    );
  });

  test('Korean values only use placeholders declared by the template', () {
    final enArb = readArb('lib/l10n/app_en.arb');
    final koArb = readArb('lib/l10n/app_ko.arb');
    final placeholderPattern = RegExp(r'\{(\w+)[},]');

    final problems = <String>[];
    for (final key in messageKeys(enArb)) {
      final meta = enArb['@$key'];
      final declared = meta is Map<String, dynamic>
          ? ((meta['placeholders'] as Map<String, dynamic>?)?.keys.toSet() ??
                const <String>{})
          : const <String>{};
      final koValue = koArb[key];
      if (koValue is! String) continue;
      for (final match in placeholderPattern.allMatches(koValue)) {
        final name = match.group(1)!;
        final enValue = enArb[key] as String? ?? '';
        if (!declared.contains(name) && !enValue.contains('{$name')) {
          problems.add('$key: ko uses undeclared placeholder {$name}');
        }
      }
    }
    expect(problems, isEmpty);
  });
}
