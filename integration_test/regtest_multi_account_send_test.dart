import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

const _lightwalletdUrl = String.fromEnvironment(
  'ZCASH_E2E_LIGHTWALLETD_URL',
  defaultValue: 'http://127.0.0.1:9067',
);
const _zcashdRpcUrl = String.fromEnvironment(
  'ZCASH_E2E_ZCASHD_RPC_URL',
  defaultValue: 'http://127.0.0.1:18232',
);
const _zcashdRpcUser = 'zcash';
const _zcashdRpcPassword = 'zcash';
const _firstMnemonic =
    'winter shiver fetch refuse absurd mail pistol eight market lounge manual '
    'roast miracle ethics found child scare curve congress renew salute pig '
    'better used';
const _secondMnemonic =
    'return try reason flat civil wolf dwarf announce toddler uphold equip '
    'range neck proof gauge east rifle swim tray twin venue fossil will '
    'version';
const _password = 'Vizor123!';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'sends shielded funds between two imported regtest accounts',
    (tester) async {
      addTearDown(() async {
        await _cleanupE2eWalletState();
      });

      await _cleanupE2eWalletState();

      _log('pumping app');
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());

      await _importFirstWallet(tester);
      await _waitForBalance(
        tester,
        shielded: '1.25 zec',
        transparent: 'Transparent balance: 0.75 ZEC',
      );

      await _openAddAccountFlow(tester);
      await _importAdditionalWallet(tester);
      await _waitForHome(tester);

      _log('copying second account shielded address');
      final secondAddress = await _copyActiveShieldedAddress(tester);
      expect(secondAddress, startsWith('uregtest1'));
      _log('second account shielded address copied');

      await _openWallet(tester);
      await _switchAccount(tester, 0);
      await _waitForBalance(tester, shielded: '1.25 zec');

      await _sendToAddress(tester, secondAddress, '0.25');
      await _mineRegtestBlocks(10);

      await _openWallet(tester);
      await _switchAccount(tester, 1);
      await _waitForBalance(
        tester,
        shielded: '0.25 zec',
        timeout: const Duration(minutes: 4),
      );
      await _expectActivityRow(
        tester,
        const ValueKey('home_activity_row_1'),
        title: 'Received',
        amount: '+0.25 ZEC',
        status: 'Completed',
      );
      await _openActivity(tester);
      await _expectActivityRow(
        tester,
        const ValueKey('activity_screen_row_1'),
        title: 'Received',
        amount: '+0.25 ZEC',
        status: 'Completed',
      );
      _log('second account received shielded funds');

      await _openWallet(tester);
      await _switchAccount(tester, 0);
      await _expectActivityRow(
        tester,
        const ValueKey('home_activity_row_1'),
        title: 'Sent',
        amount: '-0.25 ZEC',
        status: 'Completed',
      );
      await _openActivity(tester);
      await _expectActivityRow(
        tester,
        const ValueKey('activity_screen_row_1'),
        title: 'Sent',
        amount: '-0.25 ZEC',
        status: 'Completed',
      );
      _log('first account sent activity matched');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Future<void> _importFirstWallet(WidgetTester tester) async {
  _log('importing first wallet');
  await _tapAppButton(tester, const ValueKey('welcome_import_wallet_button'));
  await _enterText(
    tester,
    const ValueKey('import_mnemonic_first_word_field'),
    _firstMnemonic,
  );
  await _tapAppButton(tester, const ValueKey('import_secret_submit_button'));
  await _tapAppButton(tester, const ValueKey('import_birthday_skip_button'));
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
  await _tapAppButton(tester, const ValueKey('set_password_submit_button'));
  await _waitForHome(tester);
  _log('first wallet imported');
}

Future<void> _importAdditionalWallet(WidgetTester tester) async {
  _log('importing second wallet');
  await _tapAppButton(tester, const ValueKey('welcome_import_wallet_button'));
  await _enterText(
    tester,
    const ValueKey('import_mnemonic_first_word_field'),
    _secondMnemonic,
  );
  await _tapAppButton(tester, const ValueKey('import_secret_submit_button'));
  await _tapAppButton(tester, const ValueKey('import_birthday_skip_button'));
  await _waitForHome(tester);
  _log('second wallet imported');
}

Future<void> _openAddAccountFlow(WidgetTester tester) async {
  _log('opening add-account flow');
  await _tapWidget(tester, const ValueKey('sidebar_account_selector_button'));
  await _tapAppButton(tester, const ValueKey('sidebar_add_account_button'));
  await _pumpUntil(
    tester,
    () =>
        tester.any(find.byKey(const ValueKey('welcome_import_wallet_button'))),
    description: 'add-account welcome import button',
  );
}

Future<String> _copyActiveShieldedAddress(WidgetTester tester) async {
  await _tapWidget(tester, const ValueKey('sidebar_receive_button'));
  await _pumpUntil(
    tester,
    () => tester.any(
      find.byKey(const ValueKey('receive_copy_shielded_address_button')),
    ),
    description: 'shielded receive copy button',
  );
  await _tapWidget(
    tester,
    const ValueKey('receive_copy_shielded_address_button'),
  );
  final data = await Clipboard.getData('text/plain');
  final address = data?.text?.trim() ?? '';
  if (address.isEmpty) {
    fail('Shielded address was not copied to the clipboard.');
  }
  return address;
}

Future<void> _sendToAddress(
  WidgetTester tester,
  String address,
  String amount,
) async {
  _log('sending $amount ZEC to second account');
  await _tapWidget(tester, const ValueKey('sidebar_send_button'));
  await _enterText(tester, const ValueKey('send_address_field'), address);
  await _enterText(tester, const ValueKey('send_amount_field'), amount);
  await _tapAppButton(
    tester,
    const ValueKey('send_review_button'),
    timeout: const Duration(minutes: 1),
  );
  await _tapAppButton(
    tester,
    const ValueKey('send_confirm_button'),
    timeout: const Duration(minutes: 1),
  );
  await _pumpUntil(
    tester,
    () => tester.any(find.byKey(const ValueKey('send_status_succeeded'))),
    description: 'send status to succeed',
    timeout: const Duration(minutes: 4),
  );
  _log('send succeeded');
}

Future<void> _mineRegtestBlocks(int blocks) async {
  _log('mining $blocks regtest blocks');

  final before = await _zcashdRpc<int>('getblockcount');
  await _zcashdRpc<List<Object?>>('generate', [blocks]);
  final targetHeight = before + blocks;
  final deadline = DateTime.now().add(const Duration(seconds: 30));

  while (DateTime.now().isBefore(deadline)) {
    final lightwalletdHeight = await rust_wallet.getLatestBlockHeight(
      lightwalletdUrl: _lightwalletdUrl,
    );
    if (lightwalletdHeight.toInt() >= targetHeight) {
      _log('lightwalletd reached mined height $targetHeight');
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  throw StateError('Timed out waiting for lightwalletd height $targetHeight.');
}

Future<T> _zcashdRpc<T>(
  String method, [
  List<Object?> params = const [],
]) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(_zcashdRpcUrl));
    final credentials = base64Encode(
      utf8.encode('$_zcashdRpcUser:$_zcashdRpcPassword'),
    );
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Basic $credentials')
      ..contentType = ContentType.json;
    request.write(
      jsonEncode({
        'jsonrpc': '1.0',
        'id': 'regtest-e2e',
        'method': method,
        'params': params,
      }),
    );

    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'zcashd RPC $method failed: HTTP ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(body) as Map<String, Object?>;
    final error = decoded['error'];
    if (error != null) {
      throw StateError('zcashd RPC $method failed: $error');
    }
    return decoded['result'] as T;
  } finally {
    client.close(force: true);
  }
}

Future<void> _openWallet(WidgetTester tester) async {
  await _tapWidget(tester, const ValueKey('sidebar_wallet_button'));
  await _waitForHome(tester);
}

Future<void> _openActivity(WidgetTester tester) async {
  await _tapWidget(tester, const ValueKey('sidebar_activity_button'));
  await _pumpUntil(
    tester,
    () => tester.any(find.byKey(const ValueKey('activity_screen_row_0'))),
    description: 'activity screen rows to render',
    timeout: const Duration(minutes: 1),
  );
}

Future<void> _switchAccount(WidgetTester tester, int accountOrder) async {
  _log('switching to account order $accountOrder');
  await _tapWidget(tester, const ValueKey('sidebar_account_selector_button'));
  await _tapWidget(tester, ValueKey('sidebar_account_row_$accountOrder'));
  await _waitForHome(tester);
}

Future<void> _waitForHome(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () => tester.any(find.byKey(const ValueKey('home_shielded_balance_text'))),
    description: 'home balance card to render',
    timeout: const Duration(minutes: 1),
  );
}

Future<void> _waitForBalance(
  WidgetTester tester, {
  String? shielded,
  String? transparent,
  Duration timeout = const Duration(minutes: 4),
}) async {
  if (shielded != null) {
    await _pumpUntil(
      tester,
      () => _keyedTextEquals(
        tester,
        const ValueKey('home_shielded_balance_text'),
        shielded,
      ),
      description: 'shielded balance to show $shielded',
      timeout: timeout,
    );
    _log('shielded balance matched: $shielded');
  }
  if (transparent != null) {
    await _pumpUntil(
      tester,
      () => _keyedTextEquals(
        tester,
        const ValueKey('home_transparent_balance_text'),
        transparent,
      ),
      description: 'transparent balance to show $transparent',
      timeout: timeout,
    );
    _log('transparent balance matched: $transparent');
  }
}

Future<void> _expectActivityRow(
  WidgetTester tester,
  Key key, {
  required String title,
  required String amount,
  required String status,
}) async {
  await _pumpUntil(
    tester,
    () {
      final texts = _textSetIn(tester, find.byKey(key));
      return texts.contains(title) &&
          texts.contains(amount) &&
          texts.contains(status);
    },
    description: '$key activity row to show $title $amount $status',
    timeout: const Duration(minutes: 2),
  );
  _log('activity row matched: $title $amount $status');
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

Future<void> _tapAppButton(
  WidgetTester tester,
  Key key, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final finder = find.byKey(key);
  await _pumpUntil(
    tester,
    () =>
        tester.any(finder) &&
        tester.widget<AppButton>(finder).onPressed != null,
    description: '$key button to be enabled',
    timeout: timeout,
  );
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 250));
  _log('tapped $key');
}

Future<void> _tapWidget(
  WidgetTester tester,
  Key key, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final finder = find.byKey(key);
  await _pumpUntil(
    tester,
    () => tester.any(finder),
    description: '$key widget to render',
    timeout: timeout,
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

Set<String> _textSetIn(WidgetTester tester, Finder finder) {
  if (!tester.any(finder)) return const {};
  final texts = find.descendant(of: finder, matching: find.byType(Text));
  return tester
      .widgetList<Text>(texts)
      .map((text) => text.data)
      .whereType<String>()
      .toSet();
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
  debugPrint('[regtest-multi-account-e2e] $message');
}
