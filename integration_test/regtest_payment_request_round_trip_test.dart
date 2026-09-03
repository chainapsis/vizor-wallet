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
import 'support/desktop_onboarding_flow.dart';

// End-to-end regtest coverage for the full "Request ZEC" round trip: one
// account composes a ZIP-321 request in the receive pane, the other opens that
// exact link and pays it from the payment-request card. This is the only test
// where both halves of the feature meet — the link under test is the one the
// wallet itself produced, not a string the test wrote — so a change to either
// the request builder or the link parser that breaks the pair fails here.
//
// The link is handed over the way a real one arrives: copied out of the
// request modal, then pushed back in over the `com.zcash.wallet/payment_uri`
// MethodChannel, the same contract the platform runners implement.

/// Optional per-step pause (ms) so a screen recording of this flow is
/// watchable at human speed. Zero (the default) keeps CI runs fast.
const _stepDelayMs = int.fromEnvironment('VIZOR_E2E_STEP_DELAY_MS');

Future<void> _demoPause(WidgetTester tester) async {
  if (_stepDelayMs <= 0) return;
  final end = DateTime.now().add(Duration(milliseconds: _stepDelayMs));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

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
const _requestAmount = '0.25';
const _requestMessage = 'Table 4';
final _currencyTicker = kZcashDefaultCurrencyTicker;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'a request composed in the receive pane is paid from the card',
    (tester) async {
      addTearDown(() async {
        await _cleanupE2eWalletState();
      });

      await _cleanupE2eWalletState();

      _log('pumping app');
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());

      // Account 0 holds the faucet funds and will pay; account 1 asks.
      await _importFirstWallet(tester);
      await _waitForBalance(tester, shielded: '1.25');

      await _openAddAccountFlow(tester);
      await _importAdditionalWallet(tester);
      await _waitForHome(tester);

      final requesterUuid = await _accountUuidAtOrder(1);

      // Marker for screen-recording runners: everything before this line is
      // wallet setup, the round trip itself starts here.
      _log('demo recording start');

      // The requesting account composes the link the payer will open.
      final requestUri = await _composeRequestLink(tester);
      _log('composed request link: $requestUri');
      expect(requestUri, startsWith('zcash:uregtest1'));
      expect(requestUri, contains('amount=$_requestAmount'));
      expect(requestUri, contains('memo='));

      await _openWallet(tester);
      await _switchAccount(tester, 0);
      await _waitForBalance(tester, shielded: '1.25');
      await _waitForMempoolObserver();

      await _payRequestLink(tester, requestUri);

      await _openWallet(tester);
      await _switchAccount(tester, 1);
      await _waitForHistoryEntry(
        tester,
        accountUuid: requesterUuid,
        txKind: 'receiving',
        displayAmount: BigInt.from(25_000_000),
        pending: true,
      );
      _log('requesting account observed the incoming payment');

      await _mineRegtestBlocks(10);

      await _openWallet(tester);
      await _waitForBalance(
        tester,
        shielded: _requestAmount,
        timeout: const Duration(minutes: 4),
      );
      _log('requesting account received the requested amount');

      // The message typed into the request has to survive the whole round
      // trip: URI memo -> prefill -> proposal -> on-chain encrypted memo.
      await _expectReceivedMemo(
        tester,
        accountUuid: requesterUuid,
        displayAmount: BigInt.from(25_000_000),
        memo: _requestMessage,
      );
      _log('received memo matched the requested message');

      // Hold the final screen so a recording capped by duration ends on the
      // paid state instead of on the teardown.
      for (var i = 0; i < 25; i++) {
        await _demoPause(tester);
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

/// Composes a request on the active account's shielded address and returns the
/// `zcash:` link the modal put on the clipboard.
Future<String> _composeRequestLink(WidgetTester tester) async {
  await _tapReceiveButton(tester);
  await _pumpUntil(
    tester,
    () => tester.any(find.byKey(const ValueKey('receive_request_button'))),
    description: 'the receive pane request action',
  );
  await _tapWidget(tester, const ValueKey('receive_request_button'));
  await _pumpUntil(
    tester,
    () => tester.any(find.byKey(const ValueKey('request_amount_field'))),
    description: 'the request modal amount field',
  );

  await tester.enterText(
    find.byKey(const ValueKey('request_amount_field')),
    _requestAmount,
  );
  await tester.pump(const Duration(milliseconds: 100));

  await _tapWidget(tester, const ValueKey('request_add_message_card'));
  await _pumpUntil(
    tester,
    () => tester.any(find.byKey(const ValueKey('request_message_field'))),
    description: 'the request message field',
  );
  await tester.enterText(
    find.byKey(const ValueKey('request_message_field')),
    _requestMessage,
  );
  await tester.pump(const Duration(milliseconds: 100));

  await _tapAppButton(tester, const ValueKey('request_next_button'));
  await _pumpUntil(
    tester,
    () => tester.any(find.byKey(const ValueKey('request_copy_link_button'))),
    description: 'the request result step',
  );

  await _tapAppButton(tester, const ValueKey('request_copy_link_button'));
  final data = await Clipboard.getData('text/plain');
  final uri = data?.text?.trim() ?? '';
  if (uri.isEmpty) {
    fail('The request link was not copied to the clipboard.');
  }

  await _tapWidget(tester, const ValueKey('request_modal_close'));
  return uri;
}

/// Delivers [uri] the way the native side delivers a deep link, then answers
/// the payment-request card it raises and drives the send to completion.
Future<void> _payRequestLink(WidgetTester tester, String uri) async {
  _log('injecting request link');
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    _paymentUriChannel,
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('onUris', <String>[uri]),
    ),
    (_) {},
  );

  await _pumpUntil(
    tester,
    () =>
        tester.any(find.byKey(const ValueKey('payment_request_continue'))) &&
        _keyedTextEquals(
          tester,
          const ValueKey('payment_request_amount'),
          '$_requestAmount ${_currencyTicker.toUpperCase()}',
        ),
    description: 'the payment-request card to show the requested amount',
    timeout: const Duration(minutes: 1),
  );
  _log('payment-request card raised from the composed link');

  await _tapAppButton(
    tester,
    const ValueKey('payment_request_continue'),
    timeout: const Duration(minutes: 1),
  );
  await _pumpUntil(
    tester,
    () => tester.any(find.text('Review payment request')),
    description: 'the payment-request review screen',
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
  _log('request payment succeeded');
}

/// Asserts the received transaction carries [memo] as its encrypted memo.
Future<void> _expectReceivedMemo(
  WidgetTester tester, {
  required String accountUuid,
  required BigInt displayAmount,
  required String memo,
}) async {
  final dbPath = await getWalletDbPath();
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  var lastSeenMemo = '<not read>';
  var lastHistorySummary = '<not read>';

  while (DateTime.now().isBefore(deadline)) {
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
    final received = history
        .where(
          (tx) =>
              tx.txKind == 'receiving' &&
              tx.displayAmount == displayAmount &&
              !tx.expiredUnmined,
        )
        .toList();
    if (received.isNotEmpty) {
      final detail = await rust_sync.getTransactionDetail(
        dbPath: dbPath,
        network: _network,
        accountUuid: accountUuid,
        txidHex: received.first.txidHex,
        txKind: 'receiving',
      );
      lastSeenMemo = detail.memo ?? '<none>';
      if (detail.memo?.trim() == memo) return;
    }

    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  fail(
    'Timed out waiting for the received memo "$memo". Saw: $lastSeenMemo. '
    'Observed history: $lastHistorySummary.',
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
  await finishDesktopAccountCustomisation(tester);
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
  await finishDesktopAccountCustomisation(tester);
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
  await _tapWidget(tester, const ValueKey('sidebar_home_button'));
  await _waitForHome(tester);
}

Future<void> _switchAccount(WidgetTester tester, int accountOrder) async {
  _log('switching to account order $accountOrder');
  final accountUuid = await _accountUuidAtOrder(accountOrder);
  await _tapWidget(tester, const ValueKey('sidebar_accounts_button'));
  await _tapWidget(
    tester,
    ValueKey('sidebar_account_popover_row_$accountUuid'),
  );
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
  await _demoPause(tester);
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
  await _demoPause(tester);
}

Future<void> _tapReceiveButton(WidgetTester tester) async {
  const regular = ValueKey('home_desktop_receive_button');
  const first = ValueKey('home_desktop_receive_first_button');
  await _pumpUntil(
    tester,
    () => tester.any(find.byKey(regular)) || tester.any(find.byKey(first)),
    description: 'a home receive button to render',
  );
  await _tapWidget(tester, tester.any(find.byKey(regular)) ? regular : first);
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
  await _demoPause(tester);
}

bool _keyedTextEquals(WidgetTester tester, Key key, String expected) {
  final finder = find.byKey(key);
  if (!tester.any(finder)) return false;
  return tester.widget<Text>(finder).data == expected;
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
      if (condition()) {
        await _demoPause(tester);
        return;
      }
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
  debugPrint('[regtest-payment-request-round-trip-e2e] $message');
}
