import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

const _network = String.fromEnvironment(
  'ZCASH_E2E_NETWORK',
  defaultValue: 'regtest',
);
const _driverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39067',
);
const _testMode = String.fromEnvironment(
  'ZCASH_E2E_MEMPOOL_TEST_MODE',
  defaultValue: 'steady',
);
const _firstMnemonic =
    'winter shiver fetch refuse absurd mail pistol eight market lounge manual '
    'roast miracle ethics found child scare curve congress renew salute pig '
    'better used';
const _password = 'Vizor123!';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  if (_testMode == 'steady') {
    testWidgets(
      'shows shielded receives from the mempool before mining',
      (tester) async {
        addTearDown(() async {
          await _cleanupE2eWalletState();
        });

        await _cleanupE2eWalletState();

        _log('pumping app');
        await tester.pumpWidget(await buildBootstrappedZcashWalletApp());

        await _importFirstWallet(tester);
        await _waitForMempoolObserver();

        _log('copying first account shielded address');
        final firstAddress = await _copyActiveShieldedAddress(tester);
        expect(firstAddress, startsWith('uregtest1'));
        final firstAccountUuid = await _accountUuidAtOrder(0);
        await _openWallet(tester);

        final txid = await _fundUnmined(firstAddress, '0.25');
        _log('external unmined funding txid=$txid');
        await _waitForHistoryTx(
          tester,
          accountUuid: firstAccountUuid,
          txidHex: txid,
          txKind: 'receiving',
          displayAmount: BigInt.from(25_000_000),
        );
        await _expectActivityRow(
          tester,
          const ValueKey('home_activity_row_1'),
          title: 'Receiving',
          amount: '+0.25 ZEC',
          status: 'In progress',
          timeout: const Duration(minutes: 4),
        );

        await _mineRegtestBlocks(10);
        await _expectActivityRow(
          tester,
          const ValueKey('home_activity_row_1'),
          title: 'Received',
          amount: '+0.25 ZEC',
          status: 'Completed',
          timeout: const Duration(minutes: 4),
        );
        _expectNoActivityRow(
          tester,
          rowKeyPrefix: 'home_activity',
          title: 'Receiving',
          amount: '+0.25 ZEC',
          status: 'In progress',
        );
        await _openActivity(tester);
        await _expectActivityRow(
          tester,
          const ValueKey('activity_screen_row_1'),
          title: 'Received',
          amount: '+0.25 ZEC',
          status: 'Completed',
          timeout: const Duration(minutes: 2),
        );
        _expectNoActivityRow(
          tester,
          rowKeyPrefix: 'activity_screen',
          title: 'Receiving',
          amount: '+0.25 ZEC',
          status: 'In progress',
        );
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }

  if (_testMode == 'during-sync') {
    testWidgets(
      'shows shielded receives from the mempool while sync is running',
      (tester) async {
        addTearDown(() async {
          await _cleanupE2eWalletState();
        });

        await _cleanupE2eWalletState();

        _log('pumping app');
        await tester.pumpWidget(await buildBootstrappedZcashWalletApp());

        await _importFirstWallet(tester);
        final firstAccountUuid = await _accountUuidAtOrder(0);
        final firstAddress = await _unifiedAddressForAccount(firstAccountUuid);
        expect(firstAddress, startsWith('uregtest1'));

        await _waitForActiveSyncAndMempool(tester);
        final beforeFunding = await _syncStatusSummary();
        _log('sync active before external funding: $beforeFunding');

        final txid = await _fundPreparedUnmined(firstAddress, '0.25');
        _log('external prepared unmined funding txid=$txid');
        await _expectForegroundSyncStillRunning();

        await _waitForHistoryTx(
          tester,
          accountUuid: firstAccountUuid,
          txidHex: txid,
          txKind: 'receiving',
          displayAmount: BigInt.from(25_000_000),
        );
        await _expectActivityRow(
          tester,
          const ValueKey('home_activity_row_1'),
          title: 'Receiving',
          amount: '+0.25 ZEC',
          status: 'In progress',
          timeout: const Duration(minutes: 4),
        );

        await _waitForForegroundSyncToFinish(tester);
        await _expectActivityRow(
          tester,
          const ValueKey('home_activity_row_1'),
          title: 'Receiving',
          amount: '+0.25 ZEC',
          status: 'In progress',
          timeout: const Duration(minutes: 1),
        );

        await _mineRegtestBlocks(10);
        await _expectActivityRow(
          tester,
          const ValueKey('home_activity_row_1'),
          title: 'Received',
          amount: '+0.25 ZEC',
          status: 'Completed',
          timeout: const Duration(minutes: 4),
        );
        _expectNoActivityRow(
          tester,
          rowKeyPrefix: 'home_activity',
          title: 'Receiving',
          amount: '+0.25 ZEC',
          status: 'In progress',
        );
      },
      timeout: const Timeout(Duration(minutes: 12)),
    );
  }
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

Future<String> _unifiedAddressForAccount(String accountUuid) async {
  final dbPath = await getWalletDbPath();
  return rust_wallet.getUnifiedAddress(
    dbPath: dbPath,
    network: _network,
    accountUuid: accountUuid,
  );
}

Future<String> _fundUnmined(String address, String amount) async {
  _log('requesting external unmined funding of $amount ZEC to $address');
  final response = await _postDriver('/fund-unmined', {
    'address': address,
    'amount': amount,
  }, timeout: const Duration(minutes: 5));
  final txid = response['txid'] as String? ?? '';
  if (txid.isEmpty) fail('E2E driver did not return a txid.');
  return txid;
}

Future<String> _fundPreparedUnmined(String address, String amount) async {
  _log(
    'requesting prepared external unmined funding of $amount ZEC to $address',
  );
  final response = await _postDriver('/fund-unmined-prepared', {
    'address': address,
    'amount': amount,
  }, timeout: const Duration(minutes: 2));
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
        'E2E driver $path failed: HTTP '
        '${response.statusCode}\n$body',
      );
    }
    final decoded = jsonDecode(body) as Map<String, Object?>;
    return decoded;
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

Future<void> _waitForHome(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () => tester.any(find.byKey(const ValueKey('home_shielded_balance_text'))),
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

Future<void> _waitForActiveSyncAndMempool(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  var lastStatus = '<not read>';

  while (DateTime.now().isBefore(deadline)) {
    try {
      lastStatus = await _syncStatusSummary();
      if (rust_sync.isSyncRunning() &&
          rust_sync.isMempoolObserverRunning() &&
          await _isBehindChainTip()) {
        return;
      }
    } catch (e) {
      lastStatus = 'error: $e';
    }

    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  fail(
    'Timed out waiting for active sync and mempool observer. '
    'Last status: $lastStatus, syncRunning=${rust_sync.isSyncRunning()}, '
    'mempoolRunning=${rust_sync.isMempoolObserverRunning()}',
  );
}

Future<void> _expectForegroundSyncStillRunning() async {
  if (rust_sync.isSyncRunning()) return;
  fail(
    'Expected foreground sync to still be running when prepared mempool tx '
    'was submitted. Last status: ${await _syncStatusSummary()}, '
    'mempoolRunning=${rust_sync.isMempoolObserverRunning()}',
  );
}

Future<void> _waitForForegroundSyncToFinish(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(minutes: 4));
  var lastStatus = '<not read>';

  while (DateTime.now().isBefore(deadline)) {
    lastStatus = await _syncStatusSummary();
    if (!rust_sync.isSyncRunning()) {
      _log('foreground sync finished: $lastStatus');
      return;
    }

    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  fail(
    'Timed out waiting for foreground sync to finish. Last status: $lastStatus',
  );
}

Future<bool> _isBehindChainTip() async {
  final dbPath = await getWalletDbPath();
  final status = await rust_sync.getSyncStatus(
    dbPath: dbPath,
    network: _network,
  );
  return status.scannedHeight < status.chainTipHeight;
}

Future<String> _syncStatusSummary() async {
  final dbPath = await getWalletDbPath();
  final status = await rust_sync.getSyncStatus(
    dbPath: dbPath,
    network: _network,
  );
  return 'scanned=${status.scannedHeight}, tip=${status.chainTipHeight}, '
      'isSyncing=${status.isSyncing}';
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

Future<void> _waitForHistoryTx(
  WidgetTester tester, {
  required String accountUuid,
  required String txidHex,
  required String txKind,
  required BigInt displayAmount,
}) async {
  final dbPath = await getWalletDbPath();
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  Object? lastError;
  var lastHistorySummary = '<not read>';
  final acceptedTxids = {txidHex, _reverseTxidHex(txidHex)};

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
            acceptedTxids.contains(tx.txidHex) &&
            tx.txKind == txKind &&
            tx.displayAmount == displayAmount &&
            tx.minedHeight == BigInt.zero &&
            !tx.expiredUnmined,
      )) {
        _log('history matched pending $txKind tx $txidHex');
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
    'Timed out waiting for pending history tx $txidHex. '
    'Observed history: $lastHistorySummary.$error',
  );
}

String _reverseTxidHex(String txidHex) {
  final pairs = <String>[];
  for (var i = 0; i + 1 < txidHex.length; i += 2) {
    pairs.add(txidHex.substring(i, i + 2));
  }
  return pairs.reversed.join();
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
    () {
      final texts = _textSetIn(tester, find.byKey(key));
      return texts.contains(title) &&
          texts.contains(amount) &&
          texts.contains(status);
    },
    description: '$key activity row to show $title $amount $status',
    timeout: timeout,
  );
  _log('activity row matched: $title $amount $status');
}

void _expectNoActivityRow(
  WidgetTester tester, {
  required String rowKeyPrefix,
  required String title,
  required String amount,
  required String status,
}) {
  for (var i = 0; i < 10; i++) {
    final key = ValueKey('${rowKeyPrefix}_row_$i');
    final texts = _textSetIn(tester, find.byKey(key));
    if (texts.contains(title) &&
        texts.contains(amount) &&
        texts.contains(status)) {
      fail('Unexpected stale activity row $key: $title $amount $status');
    }
  }
  _log('no stale activity row matched: $title $amount $status');
}

Future<void> _cleanupE2eWalletState() async {
  final storage = AppSecureStore.instance;
  if (!storage.isE2eStorage) {
    throw StateError(
      'Refusing to clean wallet state without ZCASH_USE_E2E_STORAGE.',
    );
  }

  _log('cleaning E2E wallet state');
  await _stopRustWorkForCleanup();

  await storage.deleteAll();

  final supportDir = await getWalletSupportDirectory();
  if (!supportDir.existsSync()) return;

  for (final name in [
    kE2eWalletDbName,
    '$kE2eWalletDbName-shm',
    '$kE2eWalletDbName-wal',
  ]) {
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
  debugPrint('[regtest-mempool-e2e] $message');
}
