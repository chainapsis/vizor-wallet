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
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

// End-to-end regtest coverage for the ZIP-321 payment-URI feature: opening a
// `zcash:<address>?amount=...` link must prefill the send screen and produce a
// real, mineable shielded transaction. The native deep-link delivery is
// simulated by pushing an `onUris` call over the `com.zcash.wallet/payment_uri`
// MethodChannel (the same contract the macOS/Windows/Linux/Android/iOS runners
// implement), so this exercises the Dart consumer + ZIP-321 parser + send flow
// against the live regtest network with funds actually moving.

const _network = String.fromEnvironment(
  'ZCASH_E2E_NETWORK',
  defaultValue: 'regtest',
);
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
const _accountsKey = 'zcash_accounts';
const _paymentUriChannel = 'com.zcash.wallet/payment_uri';
const _firstMnemonic =
    'winter shiver fetch refuse absurd mail pistol eight market lounge manual '
    'roast miracle ethics found child scare curve congress renew salute pig '
    'better used';
const _secondMnemonic =
    'return try reason flat civil wolf dwarf announce toddler uphold equip '
    'range neck proof gauge east rifle swim tray twin venue fossil will '
    'version';
const _password = 'Vizor123!';
final _currencyTicker = kZcashDefaultCurrencyTicker;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'opening a zcash: payment URI prefills and sends shielded funds',
    (tester) async {
      addTearDown(() async {
        await _cleanupE2eWalletState();
      });

      await _cleanupE2eWalletState();

      _log('pumping app');
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());

      await _importFirstWallet(tester);
      await _waitForBalance(tester, shielded: '1.25');

      await _openAddAccountFlow(tester);
      await _importAdditionalWallet(tester);
      await _waitForHome(tester);

      _log('copying second account shielded address');
      final secondAddress = await _copyActiveShieldedAddress(tester);
      expect(secondAddress, startsWith('uregtest1'));
      final secondAccountUuid = await _accountUuidAtOrder(1);

      await _openWallet(tester);
      await _switchAccount(tester, 0);
      await _waitForBalance(tester, shielded: '1.25');
      await _waitForMempoolObserver();

      // The heart of this test: a zcash: URI must drive the send screen, not a
      // manually typed address/amount.
      await _sendViaPaymentUri(tester, secondAddress, '0.25');

      await _openWallet(tester);
      await _switchAccount(tester, 1);
      await _waitForHistoryEntry(
        tester,
        accountUuid: secondAccountUuid,
        txKind: 'receiving',
        displayAmount: BigInt.from(25_000_000),
        pending: true,
      );
      _log('second account observed the incoming payment-URI transaction');

      await _mineRegtestBlocks(10);

      await _openWallet(tester);
      await _waitForBalance(
        tester,
        shielded: '0.25',
        timeout: const Duration(minutes: 4),
      );
      _log('second account received the payment-URI funds');

      await _openWallet(tester);
      await _switchAccount(tester, 0);
      await _expectActivityRow(
        tester,
        const ValueKey('home_desktop_activity_row_0'),
        title: 'Sent',
        amount: '-0.25 $_currencyTicker',
        status: 'Completed',
      );
      _log('first account sent activity matched');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

/// Simulates the native side delivering a `zcash:` deep link, then asserts the
/// send screen is prefilled from it and drives the send to completion.
Future<void> _sendViaPaymentUri(
  WidgetTester tester,
  String address,
  String amount,
) async {
  final uri = 'zcash:$address?amount=$amount';
  _log('injecting payment URI: $uri');

  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    _paymentUriChannel,
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('onUris', <String>[uri]),
    ),
    (_) {},
  );

  // The URI is parsed and drained to /send with the address + amount prefilled.
  await _pumpUntil(
    tester,
    () =>
        _editableTextEquals(
          tester,
          const ValueKey('send_address_field'),
          address,
        ) &&
        _editableTextEquals(
          tester,
          const ValueKey('send_amount_field'),
          amount,
        ),
    description: 'payment URI to prefill the send address + amount',
    timeout: const Duration(minutes: 1),
  );
  _log('send screen prefilled from payment URI');

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
    () => tester.any(find.byKey(const ValueKey('send_status_completed'))),
    description: 'send status to succeed',
    timeout: const Duration(minutes: 4),
  );
  _log('payment-URI send succeeded');
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
  await _tapAppButton(
    tester,
    const ValueKey('unknown_birthday_confirm_button'),
  );
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
  await _tapAppButton(
    tester,
    const ValueKey('unknown_birthday_confirm_button'),
  );
  await _waitForHome(tester);
  _log('second wallet imported');
}

Future<void> _openAddAccountFlow(WidgetTester tester) async {
  _log('opening add-account flow');
  await _tapWidget(tester, const ValueKey('sidebar_accounts_button'));
  await _tapWidget(tester, const ValueKey('sidebar_accounts_add'));
  await _pumpUntil(
    tester,
    () =>
        tester.any(find.byKey(const ValueKey('welcome_import_wallet_button'))),
    description: 'add-account welcome import button',
  );
}

Future<String> _copyActiveShieldedAddress(WidgetTester tester) async {
  await _tapReceiveButton(tester);
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
      throw StateError('zcashd RPC $method failed: HTTP ${response.statusCode}');
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
  await _tapWidget(tester, const ValueKey('sidebar_home_button'));
  await _waitForHome(tester);
}

Future<void> _switchAccount(WidgetTester tester, int accountOrder) async {
  _log('switching to account order $accountOrder');
  final accountUuid = await _accountUuidAtOrder(accountOrder);
  await _tapWidget(tester, const ValueKey('sidebar_accounts_button'));
  await _tapWidget(tester, ValueKey('sidebar_account_popover_row_$accountUuid'));
  await _waitForHome(tester);
}

Future<void> _waitForHome(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () => tester.any(
      find.byKey(const ValueKey('home_desktop_balance_amount_text')),
    ),
    description: 'home balance card to render',
    timeout: const Duration(minutes: 1),
  );
}

Future<void> _waitForMempoolObserver() async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    if (rust_sync.isMempoolObserverRunning()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for mempool observer to run.');
}

Future<String> _accountUuidAtOrder(int order) async {
  final rawAccounts = await AppSecureStore.instance.readString(_accountsKey);
  if (rawAccounts == null || rawAccounts.trim().isEmpty) {
    fail('Expected stored accounts before reading account order $order.');
  }

  final decoded = jsonDecode(rawAccounts);
  if (decoded is! List) {
    fail('Expected stored accounts to be a JSON list.');
  }

  final accounts = <AccountInfo>[];
  for (final entry in decoded) {
    if (entry is! Map) {
      fail('Expected stored account entry to be a JSON object.');
    }
    accounts.add(AccountInfo.fromJson(Map<String, dynamic>.from(entry)));
  }
  accounts.sort((a, b) => a.order.compareTo(b.order));

  if (order >= accounts.length) {
    fail('Expected account order $order, got ${accounts.length} accounts.');
  }
  return accounts[order].uuid;
}

Future<void> _waitForHistoryEntry(
  WidgetTester tester, {
  required String accountUuid,
  required String txKind,
  required BigInt displayAmount,
  required bool pending,
}) async {
  final dbPath = await getWalletDbPath();
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  Object? lastError;
  var lastHistorySummary = '<not read>';

  while (DateTime.now().isBefore(deadline)) {
    try {
      final history = await rust_sync.getTransactionHistory(
        dbPath: dbPath,
        network: _network,
        limit: 20,
        accountUuid: accountUuid,
      );
      lastHistorySummary = history
          .map(
            (tx) =>
                '${tx.txidHex}:${tx.txKind}:${tx.displayAmount}:'
                'mined=${tx.minedHeight}:expired=${tx.expiredUnmined}',
          )
          .join(', ');
      if (history.any(
        (tx) =>
            tx.txKind == txKind &&
            tx.displayAmount == displayAmount &&
            (tx.minedHeight == BigInt.zero) == pending &&
            !tx.expiredUnmined,
      )) {
        _log('history matched $txKind tx amount=$displayAmount');
        return;
      }
    } catch (e) {
      lastError = e;
    }

    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  final error = lastError == null ? '' : ' Last error: $lastError';
  fail(
    'Timed out waiting for history $txKind amount=$displayAmount '
    'pending=$pending. Observed history: $lastHistorySummary.$error',
  );
}

Future<void> _waitForBalance(
  WidgetTester tester, {
  String? shielded,
  Duration timeout = const Duration(minutes: 4),
}) async {
  if (shielded != null) {
    await _pumpUntil(
      tester,
      () => _keyedTextEquals(
        tester,
        const ValueKey('home_desktop_balance_amount_text'),
        shielded,
      ),
      description: 'shielded balance to show $shielded',
      timeout: timeout,
    );
    _log('shielded balance matched: $shielded');
  }
}

bool _activityRowMatches(
  Set<String> texts,
  String title,
  String amount,
  String status,
) {
  if (!texts.contains(amount)) return false;
  final titleOk = texts.contains(title) || texts.contains('$title ...');
  if (!titleOk) return false;
  const knownStatuses = {'In progress', 'Completed', 'Failed', 'Refunded'};
  final rendered = texts.where(knownStatuses.contains);
  return rendered.isEmpty || rendered.contains(status);
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
    () => _activityRowMatches(
      _textSetIn(tester, find.byKey(key)),
      title,
      amount,
      status,
    ),
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

Future<void> _tapReceiveButton(WidgetTester tester) async {
  const regular = ValueKey('home_desktop_receive_button');
  const first = ValueKey('home_desktop_receive_first_button');
  await _pumpUntil(
    tester,
    () => tester.any(find.byKey(regular)) || tester.any(find.byKey(first)),
    description: 'a home receive button to render',
  );
  await _tapWidget(
    tester,
    tester.any(find.byKey(regular)) ? regular : first,
  );
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
  final finder = find.byKey(key);
  if (!tester.any(finder)) return false;
  return tester.widget<Text>(finder).data == expected;
}

bool _editableTextEquals(WidgetTester tester, Key key, String expected) {
  final editable = find.descendant(
    of: find.byKey(key),
    matching: find.byType(EditableText),
  );
  if (!tester.any(editable)) return false;
  return tester.widget<EditableText>(editable).controller.text == expected;
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
  debugPrint('[regtest-payment-uri-e2e] $message');
}
