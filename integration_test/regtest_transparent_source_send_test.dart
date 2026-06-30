import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/formatting/zec_amount.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

final _network = kZcashDefaultNetworkName;
const _driverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39068',
);
const _receiverAddress = String.fromEnvironment(
  'ZCASH_E2E_TRANSPARENT_SOURCE_RECIPIENT',
);
const _password = 'Vizor123!';
const _transparentFundingAmount = '0.75';
const _sendAmount = '0.25';
final _transparentFundingZatoshi = BigInt.from(75_000_000);
final _sendZatoshi = BigInt.from(25_000_000);
final _currencyTicker = kZcashDefaultCurrencyTicker;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'requires confirmations before a transparent-source send is available',
    (tester) async {
      if (_receiverAddress.isEmpty) {
        fail(
          'Set ZCASH_E2E_TRANSPARENT_SOURCE_RECIPIENT for the '
          'transparent-source send test.',
        );
      }

      addTearDown(() async {
        await _cleanupE2eWalletState();
      });

      await _cleanupE2eWalletState();

      _log('pumping app');
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());

      await _createFirstWallet(tester);
      final accountUuid = await _accountUuidAtOrder(0);
      final transparentAddress = await _transparentAddressForAccount(
        accountUuid,
      );
      expect(transparentAddress, startsWith('t'));
      _log('created account $accountUuid transparent=$transparentAddress');

      final fundingTxid = await _fundTransparent(
        transparentAddress,
        _transparentFundingAmount,
        confirmations: 1,
      );
      _log('external 1-conf transparent funding txid=$fundingTxid');

      await _waitForTransparentBalance(
        tester,
        accountUuid: accountUuid,
        spendable: BigInt.zero,
        pending: _transparentFundingZatoshi,
        timeout: const Duration(minutes: 5),
      );
      await _expectHomeTransparentBalanceHidden(tester);
      await _expectSendSourceTransparentBalance(
        tester,
        _formatSendBalance(BigInt.zero),
      );

      await _openWallet(tester);
      await _mineRegtestBlocks(9);
      await _waitForTransparentBalance(
        tester,
        accountUuid: accountUuid,
        spendable: _transparentFundingZatoshi,
        pending: BigInt.zero,
        timeout: const Duration(minutes: 5),
      );
      await _waitForHomeTransparentBalance(
        tester,
        'Transparent: ${_formatHomeBalance(_transparentFundingZatoshi)} '
        '$_currencyTicker',
        timeout: const Duration(minutes: 5),
      );

      await _sendTransparentSourceToAddress(
        tester,
        _receiverAddress,
        _sendAmount,
      );
      await _waitForHistoryEntry(
        tester,
        accountUuid: accountUuid,
        txKind: 'sent',
        displayAmount: _sendZatoshi,
        pending: true,
        timeout: const Duration(minutes: 4),
      );
      await _openWallet(tester);
      await _expectActivityRow(
        tester,
        const ValueKey('home_desktop_activity_row_0'),
        title: 'Sending',
        amount: '-$_sendAmount $_currencyTicker',
        status: 'In progress',
      );

      await _mineRegtestBlocks(10);
      await _waitForHistoryEntry(
        tester,
        accountUuid: accountUuid,
        txKind: 'sent',
        displayAmount: _sendZatoshi,
        pending: false,
        timeout: const Duration(minutes: 5),
      );
      await _expectActivityRow(
        tester,
        const ValueKey('home_desktop_activity_row_0'),
        title: 'Sent',
        amount: '-$_sendAmount $_currencyTicker',
        status: 'Completed',
        timeout: const Duration(minutes: 3),
      );
      _log('transparent-source send activity matched');
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Future<void> _createFirstWallet(WidgetTester tester) async {
  _log('creating first wallet');
  await _tapAppButton(tester, const ValueKey('welcome_create_wallet_button'));
  await _tapText(tester, 'I know how to use Zcash');
  await _tapAppButton(
    tester,
    const ValueKey('create_secret_phrase_primary_button'),
    timeout: const Duration(minutes: 1),
  );
  await _tapAppButton(
    tester,
    const ValueKey('create_secret_phrase_primary_button'),
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
  await _tapAppButton(
    tester,
    const ValueKey('set_password_submit_button'),
    timeout: const Duration(minutes: 4),
  );
  await _waitForHome(tester, timeout: const Duration(minutes: 4));
  _log('first wallet created');
}

Future<String> _transparentAddressForAccount(String accountUuid) async {
  final dbPath = await getWalletDbPath();
  return rust_wallet.getTransparentReceiveAddress(
    dbPath: dbPath,
    network: _network,
    accountUuid: accountUuid,
  );
}

Future<String> _fundTransparent(
  String address,
  String amount, {
  required int confirmations,
}) async {
  _log(
    'requesting transparent funding of $amount $_currencyTicker '
    'confirmations=$confirmations',
  );
  final response = await _postDriver('/fund-confirmed', {
    'address': address,
    'amount': amount,
    'confirmations': confirmations,
  }, timeout: const Duration(minutes: 10));
  final txid = response['txid'] as String? ?? '';
  if (txid.isEmpty) fail('E2E driver did not return a txid.');
  return txid;
}

Future<void> _mineRegtestBlocks(int blocks) async {
  _log('requesting external mining of $blocks regtest blocks');
  await _postDriver('/mine', {'blocks': blocks});
}

Future<Map<String, Object?>> _postDriver(
  String path,
  Map<String, Object?> payload, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  final client = HttpClient();
  try {
    final request = await client
        .postUrl(Uri.parse('$_driverUrl$path'))
        .timeout(timeout);
    final bodyBytes = utf8.encode(jsonEncode(payload));
    request.headers.contentType = ContentType.json;
    request.contentLength = bodyBytes.length;
    request.add(bodyBytes);

    final response = await request.close().timeout(timeout);
    final body = await utf8.decoder.bind(response).join().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'E2E driver $path failed: HTTP ${response.statusCode}\n$body',
      );
    }
    return jsonDecode(body) as Map<String, Object?>;
  } finally {
    client.close(force: true);
  }
}

Future<String> _accountUuidAtOrder(int order) async {
  final dbPath = await getWalletDbPath();
  final accounts = await rust_wallet.listAccounts(
    dbPath: dbPath,
    network: _network,
  );
  if (order >= accounts.length) {
    fail('Expected account order $order, got ${accounts.length} accounts.');
  }
  return accounts[order].uuid;
}

Future<void> _openWallet(WidgetTester tester) async {
  if (tester.any(
    find.byKey(const ValueKey('home_desktop_balance_amount_text')),
  )) {
    return;
  }
  await _tapWidget(tester, const ValueKey('sidebar_home_button'));
  await _waitForHome(tester);
}

Future<void> _waitForHome(
  WidgetTester tester, {
  Duration timeout = const Duration(minutes: 1),
}) async {
  await _pumpUntil(
    tester,
    () => tester.any(
      find.byKey(const ValueKey('home_desktop_balance_amount_text')),
    ),
    description: 'home balance card to render',
    timeout: timeout,
  );
}

Future<void> _waitForTransparentBalance(
  WidgetTester tester, {
  required String accountUuid,
  required BigInt spendable,
  required BigInt pending,
  Duration timeout = const Duration(minutes: 2),
}) async {
  final dbPath = await getWalletDbPath();
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  var lastBalance = '<not read>';

  while (DateTime.now().isBefore(deadline)) {
    try {
      final balance = await rust_sync.getBalance(
        dbPath: dbPath,
        network: _network,
        accountUuid: accountUuid,
      );
      lastBalance =
          'transparent=${balance.transparent}, '
          'transparentPending=${balance.transparentPending}';
      if (balance.transparent == spendable &&
          balance.transparentPending == pending) {
        _log('transparent balance matched: $lastBalance');
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
    'Timed out waiting for transparent balance spendable=$spendable '
    'pending=$pending. Last balance: $lastBalance.$error',
  );
}

Future<void> _expectHomeTransparentBalanceHidden(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () => !tester.any(
      find.byKey(const ValueKey('home_desktop_transparent_balance_strip')),
    ),
    description: 'home transparent balance strip to stay hidden',
    timeout: const Duration(minutes: 1),
  );
  _log('home transparent balance strip hidden');
}

Future<void> _waitForHomeTransparentBalance(
  WidgetTester tester,
  String expected, {
  Duration timeout = const Duration(minutes: 4),
}) async {
  await _pumpUntil(
    tester,
    () => _keyedTextEquals(
      tester,
      const ValueKey('home_transparent_balance_text'),
      expected,
    ),
    description: 'home transparent balance to show $expected',
    timeout: timeout,
  );
  _log('home transparent balance matched: $expected');
}

Future<void> _expectSendSourceTransparentBalance(
  WidgetTester tester,
  String expected,
) async {
  await _tapWidget(tester, const ValueKey('home_desktop_send_button'));
  await _openSourcePicker(tester);
  await _pumpUntil(
    tester,
    () => _textSetIn(
      tester,
      find.byKey(const ValueKey('send_source_option_transparent')),
    ).contains(expected),
    description: 'send transparent source row to show $expected',
    timeout: const Duration(minutes: 1),
  );
  _log('send transparent source row matched: $expected');
  await _dismissSourcePicker(tester);
}

Future<void> _sendTransparentSourceToAddress(
  WidgetTester tester,
  String address,
  String amount,
) async {
  _log('sending $amount $_currencyTicker from transparent source');
  await _tapWidget(tester, const ValueKey('home_desktop_send_button'));
  await _enterText(tester, const ValueKey('send_address_field'), address);
  await _openSourcePicker(tester);
  await _tapWidget(tester, const ValueKey('send_source_option_transparent'));
  await _enterText(tester, const ValueKey('send_amount_field'), amount);
  await _pumpUntil(
    tester,
    () => tester.any(
      find.text('Max: ${_formatSendBalance(_transparentFundingZatoshi)}'),
    ),
    description: 'transparent source max label',
    timeout: const Duration(minutes: 1),
  );
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
    description: 'transparent-source send status to succeed',
    timeout: const Duration(minutes: 4),
  );
  _log('transparent-source send succeeded');
}

Future<void> _openSourcePicker(WidgetTester tester) async {
  final picker = find.byKey(const ValueKey('send_source_picker'));
  if (tester.any(picker)) return;
  await _tapWidget(tester, const ValueKey('send_source_toggle_button'));
  await _pumpUntil(
    tester,
    () => tester.any(picker),
    description: 'send source picker to render',
    timeout: const Duration(minutes: 1),
  );
}

Future<void> _dismissSourcePicker(WidgetTester tester) async {
  if (!tester.any(find.byKey(const ValueKey('send_source_picker')))) return;
  await tester.tapAt(const Offset(8, 8));
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _waitForHistoryEntry(
  WidgetTester tester, {
  required String accountUuid,
  required String txKind,
  required BigInt displayAmount,
  required bool pending,
  Duration timeout = const Duration(minutes: 2),
}) async {
  final dbPath = await getWalletDbPath();
  final deadline = DateTime.now().add(timeout);
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

Future<void> _expectActivityRow(
  WidgetTester tester,
  Key key, {
  required String title,
  required String amount,
  required String status,
  Duration timeout = const Duration(minutes: 2),
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
    timeout: timeout,
  );
  _log('activity row matched: $title $amount $status');
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

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await _pumpUntil(
    tester,
    () => tester.any(finder),
    description: '$text text to render',
  );
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 250));
  _log('tapped text "$text"');
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

Set<String> _textSetIn(WidgetTester tester, Finder root) {
  if (!tester.any(root)) return const {};
  final texts = <String>{};
  for (final element
      in find.descendant(of: root, matching: find.byType(Text)).evaluate()) {
    final widget = element.widget;
    if (widget is Text) {
      final value = widget.data ?? widget.textSpan?.toPlainText();
      if (value != null) texts.add(value);
    }
  }
  return texts;
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

String _formatHomeBalance(BigInt zatoshi) {
  return ZecAmount.fromZatoshi(zatoshi).balance.amountText;
}

String _formatSendBalance(BigInt zatoshi) {
  return ZecAmount.fromZatoshi(
    zatoshi,
  ).pretty(denomStyle: ZecDenomStyle.upper).toString();
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

void _log(String message) {
  // ignore: avoid_print
  print('[regtest_transparent_source_send_test] $message');
}
