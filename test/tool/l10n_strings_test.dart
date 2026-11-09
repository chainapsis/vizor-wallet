import 'package:flutter_test/flutter_test.dart';

import '../../tool/l10n/strings.dart';

const _source = r'''
Widget build(BuildContext context) {
  log('Loaded settings screen');
  debugPrint('Sync finished');
  final key = ValueKey('settings_theme_row');
  if (error.toString().contains('Proposal not found')) {}
  final style = TextStyle(fontFamily: 'Young Serif');
  final tag = 'SendBroadcast(ledger-terminal)';
  final legal = 'Apache License 2.0'; // l10n-ignore: legal name
  showAppToast(context, 'Passcode updated');
  final note = 'Wallet data could not be read.';
  const cacheKey = 'zcash_wallet_cache';
  final helpKey = onHelp == null ? keySlot() : keySlot(label: 'Passcode help');
  return Column(children: [
    Text('Import wallet'),
    AppButton(label: 'Get started'),
    Text('$count accounts'),
  ]);
}
''';

void main() {
  final findings = scanSource('lib/src/fixture.dart', _source);
  String kindOf(String text) =>
      findings.where((f) => f.text == text).map((f) => f.kind.name).join();

  test('widget text slots are user-facing', () {
    expect(kindOf('Import wallet'), 'slot');
    expect(kindOf('Get started'), 'slot');
    expect(kindOf('Passcode updated'), 'slot');
    expect(kindOf('{} accounts'), 'slot');
    // A variable named like a key can still hold a widget with copy.
    expect(kindOf('Passcode help'), 'slot');
  });

  test('copy outside a slot is likely user-facing', () {
    expect(kindOf('Wallet data could not be read.'), 'likely');
  });

  test('logs, keys, matchers, fonts, tags and ignored lines are skipped', () {
    for (final text in [
      'Loaded settings screen',
      'Sync finished',
      'settings_theme_row',
      'zcash_wallet_cache',
      'Proposal not found',
      'Young Serif',
      'SendBroadcast(ledger-terminal)',
      'Apache License 2.0',
    ]) {
      expect(kindOf(text), isEmpty, reason: text);
    }
  });

  test('a file marked l10n-ignore-file is skipped', () {
    const body = "Widget build() => Text('Valiant Herald');";
    expect(scanSource('lib/src/fixture.dart', body), isNotEmpty);
    expect(
      scanSource(
        'lib/src/fixture.dart',
        '// l10n-ignore-file: persisted names\n$body',
      ),
      isEmpty,
    );
  });
}
