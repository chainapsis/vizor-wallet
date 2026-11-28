import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every proxy and delegate-mode English message: the `proxy*` and
/// `delegate*` keys of the template ARB file.
List<String> _proxyMessages() {
  final arb =
      jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;
  return [
    for (final MapEntry(:key, :value) in arb.entries)
      if (key.startsWith('proxy') || key.startsWith('delegate'))
        value as String,
  ];
}

void main() {
  test('no copy says delegating, or a delegate ballot, is private', () {
    final copy = _proxyMessages().join('\n').toLowerCase();
    for (final claim in const [
      'same protection',
      'as private as',
      'same privacy',
      'just as private',
      'private ballot',
    ]) {
      expect(copy, isNot(contains(claim)));
    }
  });
}
