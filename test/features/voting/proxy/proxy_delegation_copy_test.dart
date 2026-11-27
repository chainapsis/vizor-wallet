import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_copy.dart';

import '../../../support/test_l10n.dart';

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

/// The texts [message] can show: each branch of an ICU plural, or the
/// message itself, with every placeholder read as `0`, so a sentence check
/// skips it.
List<String> _texts(String message) {
  final plural = RegExp(r'^\{\w+, plural, (.*)\}$').firstMatch(message);
  final branches = plural == null
      ? [message]
      : [
          for (final branch in RegExp(
            r'(?:=\d+|other)\{((?:[^{}]|\{\w+\})*)\}',
          ).allMatches(plural[1]!))
            branch[1]!,
        ];
  return [
    for (final branch in branches) branch.replaceAll(RegExp(r'\{\w+\}'), '0'),
  ];
}

void main() {
  test('every proxy message is sentence case with no dashes', () {
    // Proper nouns, plus status and button names copy refers to by name.
    const capitalized = {
      'ZEC',
      'Vizor',
      'X',
      'GitHub',
      'Tor',
      'Mac',
      'QR',
      'Sent',
      'Retire',
    };
    final messages = _proxyMessages();
    expect(messages.length, greaterThan(100));
    final problems = <String>[];
    for (final text in messages.expand(_texts)) {
      expect(text, isNot(contains('—')), reason: 'no em dashes: $text');
      expect(text, isNot(contains('–')), reason: 'no en dashes: $text');
      // Single words are labels; sentence case does not apply.
      if (!text.contains(' ')) continue;
      for (final sentence in text.trim().split(RegExp(r'(?<=[.?!])\s+'))) {
        final words = sentence.split(' ');
        if (RegExp('^[a-z]').hasMatch(words.first)) {
          problems.add('"$sentence" starts in lower case');
        }
        for (final word in words.skip(1)) {
          final bare = word.replaceAll(RegExp(r'^[^A-Za-z@]+|[^A-Za-z]+$'), '');
          if (!RegExp('^[A-Z]').hasMatch(bare)) continue;
          if (capitalized.contains(bare)) continue;
          problems.add('"$bare" in "$sentence" should be lower case');
        }
      }
    }
    expect(problems, isEmpty);
  });

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

  test('composed delegator copy fills in its names and amounts', () {
    expect(
      proxySplitToCopy(testL10n, amount: '4 ZEC', name: '@czarcas7ic'),
      '4 ZEC to @czarcas7ic',
    );
    expect(proxySplitToCopy(testL10n, amount: null, name: '#7'), '#7');
    expect(testL10n.proxyKeptToAnswer('4 ZEC'), '4 ZEC for you to answer');
    expect(testL10n.proxyHasNotVotedYet('@alice'), "@alice hasn't voted yet");
    expect(testL10n.proxyDelegatingStep('@alice'), 'Delegating to @alice');
    expect(
      testL10n.proxyAnswersForYou('@alice', 1),
      '@alice answers these for you',
    );
    expect(
      testL10n.proxyAnswersForYou('@alice and @bob', 2),
      '@alice and @bob answer these for you',
    );
  });
}
