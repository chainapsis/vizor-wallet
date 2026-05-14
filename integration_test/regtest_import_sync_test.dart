import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

const _mnemonic =
    'winter shiver fetch refuse absurd mail pistol eight market lounge manual '
    'roast miracle ethics found child scare curve congress renew salute pig '
    'better used';
const _password = 'Vizor123!';
final _currencyTicker = kZcashDefaultCurrencyTicker;
final _currencyTickerLower = _currencyTicker.toLowerCase();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'imports a funded regtest wallet, syncs, and displays balances',
    (tester) async {
      addTearDown(() async {
        await _cleanupE2eWalletState();
      });

      await _cleanupE2eWalletState();

      _log('pumping app');
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());

      _log('opening import flow');
      await _tapButton(tester, const ValueKey('welcome_import_wallet_button'));

      _log('entering mnemonic');
      await _enterText(
        tester,
        const ValueKey('import_mnemonic_first_word_field'),
        _mnemonic,
      );
      await _tapButton(tester, const ValueKey('import_secret_submit_button'));

      _log('skipping birthday');
      await _tapButton(tester, const ValueKey('import_birthday_skip_button'));
      await _tapButton(
        tester,
        const ValueKey('unknown_birthday_confirm_button'),
      );

      _log('setting password');
      await _enterText(
        tester,
        const ValueKey('set_password_password_field'),
        _password,
      );
      await _enterText(
        tester,
        const ValueKey('set_password_confirm_field'),
        _password,
      );
      await _tapButton(tester, const ValueKey('set_password_submit_button'));

      await _pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('home_shielded_balance_text')),
        ),
        description: 'home balance card to render',
        timeout: const Duration(minutes: 1),
      );
      _log(
        'home rendered with shielded='
        '${_textForKey(tester, const ValueKey('home_shielded_balance_text'))}',
      );

      await _pumpUntil(
        tester,
        () => _keyedTextEquals(
          tester,
          const ValueKey('home_shielded_balance_text'),
          '1.25 $_currencyTickerLower',
        ),
        description: 'shielded balance to show 1.25 $_currencyTickerLower',
        timeout: const Duration(minutes: 4),
      );
      _log('shielded balance matched');

      await _pumpUntil(
        tester,
        () => _keyedTextEquals(
          tester,
          const ValueKey('home_transparent_balance_text'),
          'Transparent balance: 0.75 $_currencyTicker',
        ),
        description: 'transparent balance to show 0.75 $_currencyTicker',
        timeout: const Duration(minutes: 1),
      );
      _log('transparent balance matched');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _cleanupE2eWalletState() async {
  if (kZcashDefaultNetworkName != ZcashNetwork.regtest.name) {
    throw StateError(
      'Refusing to clean wallet state without ZCASH_DEFAULT_NETWORK=regtest.',
    );
  }

  final storage = AppSecureStore.instance;
  final dbName = await getWalletDbName();

  _log('cleaning regtest wallet state');
  await _stopRustWorkForCleanup();

  await storage.deleteAll();

  final supportDir = await getWalletSupportDirectory();
  if (!supportDir.existsSync()) return;

  for (final name in [dbName, '$dbName-shm', '$dbName-wal']) {
    final file = File('${supportDir.path}${Platform.pathSeparator}$name');
    if (file.existsSync()) file.deleteSync();
  }
}

Future<void> _stopRustWorkForCleanup() async {
  rust_sync.setSyncMode(mode: 0);
  rust_sync.cancelFullSync();
  rust_sync.stopMempoolObserver();

  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while ((rust_sync.isSyncRunning() || rust_sync.isMempoolObserverRunning()) &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  if (rust_sync.isSyncRunning() || rust_sync.isMempoolObserverRunning()) {
    _log(
      'timed out waiting for Rust work to stop; continuing E2E storage cleanup',
    );
  }
}

Future<void> _tapButton(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await _pumpUntil(
    tester,
    () =>
        tester.any(finder) &&
        tester.widget<AppButton>(finder).onPressed != null,
    description: '$key button to be enabled',
  );
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 250));
  _log('tapped $key');
}

Future<void> _enterText(WidgetTester tester, Key key, String text) async {
  final editable = find.descendant(
    of: find.byKey(key),
    matching: find.byType(EditableText),
  );
  await _pumpUntil(
    tester,
    () => tester.any(editable),
    description: '$key editable text field',
  );
  await tester.tap(editable);
  await tester.enterText(editable, text);
  await tester.pump(const Duration(milliseconds: 100));
  _log('entered text into $key');
}

bool _keyedTextEquals(WidgetTester tester, Key key, String expected) {
  return _textForKey(tester, key) == expected;
}

String? _textForKey(WidgetTester tester, Key key) {
  final finder = find.byKey(key);
  if (!tester.any(finder)) return null;
  final widget = tester.widget<Text>(finder);
  return widget.data;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  Object? lastError;
  var polls = 0;
  while (DateTime.now().isBefore(end)) {
    try {
      if (condition()) return;
    } catch (e) {
      lastError = e;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    polls++;
    if (polls % 25 == 0) {
      _log('still waiting for $description');
    }
  }

  final error = lastError == null ? '' : ' Last error: $lastError';
  fail('Timed out waiting for $description.$error');
}

void _log(String message) {
  debugPrint('[regtest-e2e] $message');
}
