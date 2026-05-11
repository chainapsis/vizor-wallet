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
const _password = 'Vizor123!';
const _transparentFundingAmount = '0.75';
final _transparentFundingZatoshi = BigInt.from(75_000_000);
final _currencyTicker = kZcashDefaultCurrencyTicker;
final _currencyTickerLower = _currencyTicker.toLowerCase();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'creates a wallet, detects transparent funds, shields them, and shows history',
    (tester) async {
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

      final fundingTxid = await _fundConfirmed(
        transparentAddress,
        _transparentFundingAmount,
      );
      _log('external confirmed transparent funding txid=$fundingTxid');

      await _waitForBalance(
        tester,
        transparent:
            'Transparent balance: ${_formatBalance(_transparentFundingZatoshi)} '
            '$_currencyTicker',
        timeout: const Duration(minutes: 5),
      );
      await _waitForShieldBalanceUi(tester);

      final dbPath = await getWalletDbPath();
      final shieldStatus = await rust_sync.getShieldTransparentStatus(
        dbPath: dbPath,
        network: _network,
        accountUuid: accountUuid,
      );
      expect(shieldStatus.canShield, isTrue);
      expect(shieldStatus.shieldedZatoshi, greaterThan(BigInt.zero));
      final expectedShielded = shieldStatus.shieldedZatoshi;
      _log(
        'shield status fee=${shieldStatus.feeZatoshi} '
        'shielded=$expectedShielded',
      );

      await _tapWidget(tester, const ValueKey('home_shield_balance_button'));
      await tester.pump(const Duration(milliseconds: 100));
      if (tester.any(find.text('Shielding...'))) {
        _log('shielding loading state observed');
      }

      await _waitForHistoryEntry(
        tester,
        accountUuid: accountUuid,
        txKind: 'shielded',
        displayAmount: expectedShielded,
        pending: true,
        timeout: const Duration(minutes: 4),
      );
      await _expectAnyActivityRow(
        tester,
        rowKeyPrefix: 'home_activity',
        title: 'Shielded',
        amount: _formatActivity(expectedShielded),
        status: 'In progress',
        timeout: const Duration(minutes: 2),
      );

      await _mineRegtestBlocks(10);
      await _waitForHistoryEntry(
        tester,
        accountUuid: accountUuid,
        txKind: 'shielded',
        displayAmount: expectedShielded,
        pending: false,
        timeout: const Duration(minutes: 5),
      );
      await _waitForBalance(
        tester,
        shielded: '${_formatBalance(expectedShielded)} $_currencyTickerLower',
        timeout: const Duration(minutes: 5),
      );
      await _waitForTransparentBalanceCleared(tester);

      await _expectAnyActivityRow(
        tester,
        rowKeyPrefix: 'home_activity',
        title: 'Shielded',
        amount: _formatActivity(expectedShielded),
        status: 'Completed',
        timeout: const Duration(minutes: 2),
      );
      await _openActivity(tester);
      await _expectAnyActivityRow(
        tester,
        rowKeyPrefix: 'activity_screen',
        title: 'Shielded',
        amount: _formatActivity(expectedShielded),
        status: 'Completed',
        timeout: const Duration(minutes: 2),
      );
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
  return rust_wallet.getTransparentAddress(
    dbPath: dbPath,
    network: _network,
    accountUuid: accountUuid,
  );
}

Future<String> _fundConfirmed(String address, String amount) async {
  _log('requesting confirmed transparent funding of $amount $_currencyTicker');
  final response = await _postDriver('/fund-confirmed', {
    'address': address,
    'amount': amount,
    'confirmations': 10,
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

Future<void> _openActivity(WidgetTester tester) async {
  await _tapWidget(tester, const ValueKey('sidebar_activity_button'));
  await _pumpUntil(
    tester,
    () => tester.any(find.byKey(const ValueKey('activity_screen_row_0'))),
    description: 'activity screen rows to render',
    timeout: const Duration(minutes: 1),
  );
}

Future<void> _waitForHome(
  WidgetTester tester, {
  Duration timeout = const Duration(minutes: 1),
}) async {
  await _pumpUntil(
    tester,
    () => tester.any(find.byKey(const ValueKey('home_shielded_balance_text'))),
    description: 'home balance card to render',
    timeout: timeout,
  );
}

Future<void> _waitForShieldBalanceUi(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () {
      final button = find.byKey(const ValueKey('home_shield_balance_button'));
      return tester.any(button) &&
          tester.any(
            find.descendant(of: button, matching: find.text('Shield Balance')),
          );
    },
    description: 'shield balance action to render',
    timeout: const Duration(minutes: 2),
  );
}

Future<void> _waitForTransparentBalanceCleared(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () =>
        !tester.any(find.byKey(const ValueKey('transparent-balance-strip'))) ||
        _keyedTextEquals(
          tester,
          const ValueKey('home_transparent_balance_text'),
          'Transparent balance: 0.00 $_currencyTicker',
        ),
    description: 'transparent balance to clear after shielding',
    timeout: const Duration(minutes: 5),
  );
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

Future<void> _expectAnyActivityRow(
  WidgetTester tester, {
  required String rowKeyPrefix,
  required String title,
  required String amount,
  required String status,
  Duration timeout = const Duration(minutes: 2),
}) async {
  await _pumpUntil(
    tester,
    () {
      for (var i = 0; i < 10; i++) {
        final texts = _textSetIn(
          tester,
          find.byKey(ValueKey('${rowKeyPrefix}_row_$i')),
        );
        if (texts.contains(title) &&
            texts.contains(amount) &&
            texts.contains(status)) {
          return true;
        }
      }
      return false;
    },
    description: '$rowKeyPrefix row to show $title $amount $status',
    timeout: timeout,
  );
  _log('activity row matched: $title $amount $status');
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

Future<void> _tapWidget(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await _pumpUntil(
    tester,
    () => tester.any(finder),
    description: '$key widget to render',
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

String _formatBalance(BigInt zatoshi) {
  return ZecAmount.fromZatoshi(zatoshi).balance.amountText;
}

String _formatActivity(BigInt zatoshi) {
  return ZecAmount.fromZatoshi(zatoshi).activity.toString();
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
  print('[regtest_shield_transparent_test] $message');
}
