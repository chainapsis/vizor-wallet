// Shared app-layer checks for the transparent history qualification suite
// (scripts/e2e/transparent-history-cases.sh). Expectations come from the
// independent oracle (scripts/e2e/transparent_history_oracle.py, public
// profile) through the TH_EXPECTED_UI define; this file never derives an
// expected value from the activity mapper.

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/core/widgets/review_list_row.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

const thA0Mnemonic = String.fromEnvironment('TH_A0_MNEMONIC');
const thA1Mnemonic = String.fromEnvironment('TH_A1_MNEMONIC');
const _expectedUi = String.fromEnvironment('TH_EXPECTED_UI');

class ThUiRow {
  ThUiRow(Map<String, Object?> json)
    : caseId = json['case']! as String,
      intent = json['intent'] as String? ?? '',
      account = json['account']! as String,
      txid = json['txid']! as String,
      role = json['role'] as String?,
      optional = json['optional'] as bool? ?? false,
      title = json['title'] as String?,
      pending = json['pending'] as bool? ?? false,
      failed = json['failed'] as bool? ?? false,
      amountZats = (json['amount_zats'] as num?)?.toInt(),
      sign = json['sign'] as String? ?? '',
      poolLabel = json['pool_label'] as String?,
      poolLabels = [
        for (final v in (json['pool_labels'] as List<Object?>? ?? const []))
          v! as String,
      ],
      status = json['status'] as String?,
      blockTime = (json['block_time'] as num?)?.toInt() ?? 0,
      feeKnown = (json['fee_known'] as num?)?.toInt(),
      feeValues = [
        for (final v in (json['fee_values'] as List<Object?>? ?? const []))
          (v! as num).toInt(),
      ];

  final String caseId;

  /// Authored case intent (e.g. `swap_deposit`).
  final String intent;
  final String account;

  /// Wallet (internal) byte order, as used in activity row keys.
  final String txid;

  /// Row role in the key `tx:<txid>:<role>`; null when only presence is
  /// specified (constraint-only expectations).
  final String? role;
  final bool optional;
  final String? title;
  final bool pending;
  final bool failed;
  final int? amountZats;
  final String sign;
  final String? poolLabel;

  /// Every pool label the spec accepts (e.g. Transparent or Mixed).
  final List<String> poolLabels;
  final String? status;
  final int blockTime;
  final int? feeKnown;

  /// Every known fee the spec accepts for this row (a grouped TEX operation
  /// may show its combined fee).
  final List<int> feeValues;

  bool acceptsFee(int? fee) =>
      fee != null && (fee == feeKnown || feeValues.contains(fee));

  String get label => '$caseId $account ${txid.substring(0, 12)}:$role';
}

/// UUID of the account imported in position `order` (0 = A0's seed, 1 = A1's).
/// The wallet DB's account listing is not in import order; the app's stored
/// account list carries it.
Future<String> thAccountUuidAtOrder(int order) async {
  final raw = await AppSecureStore.instance.readString('zcash_accounts');
  if (raw == null || raw.trim().isEmpty) fail('no stored accounts');
  final accounts = [
    for (final entry in jsonDecode(raw) as List<Object?>)
      AccountInfo.fromJson(Map<String, dynamic>.from(entry! as Map)),
  ]..sort((a, b) => a.order.compareTo(b.order));
  if (order >= accounts.length) fail('expected account order $order');
  return accounts[order].uuid;
}

List<ThUiRow> thExpectedUiRows() {
  if (_expectedUi.isEmpty) {
    fail(
      'TH_EXPECTED_UI is empty; run scripts/e2e/transparent-history-cases.sh '
      '--flutter desktop|mobile',
    );
  }
  if (thA0Mnemonic.isEmpty || thA1Mnemonic.isEmpty) {
    fail('TH_A0_MNEMONIC / TH_A1_MNEMONIC must come from the runner.');
  }
  final decoded =
      jsonDecode(utf8.decode(base64Decode(_expectedUi)))
          as Map<String, Object?>;
  return [
    for (final row in decoded['rows']! as List<Object?>)
      ThUiRow(Map<String, Object?>.from(row! as Map)),
  ];
}

/// Activity-row amount format as specified for the product: up to four
/// decimals (eight below 0.01), truncated, trailing zeros trimmed.
String thActivityAmount(int zats, String sign, String ticker) {
  final whole = zats ~/ 100000000;
  final fraction = zats % 100000000;
  final digits = whole == 0 && fraction > 0 && fraction < 1000000 ? 8 : 4;
  var text = fraction.toString().padLeft(8, '0').substring(0, digits);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  final number = text.isEmpty ? '$whole' : '$whole.$text';
  return '$sign$number $ticker';
}

/// Parses an amount like `0.0001 TAZ` / `-1.25 TAZ` to zatoshis.
int? thParseAmount(String text, String ticker) {
  final match = RegExp(
    r'^[+-]?(\d+)(?:\.(\d{1,8}))? ' + RegExp.escape(ticker) + r'$',
  ).firstMatch(text.trim());
  if (match == null) return null;
  final fraction = (match.group(2) ?? '').padRight(8, '0');
  return int.parse(match.group(1)!) * 100000000 + int.parse(fraction);
}

String _hhmm(int epochSeconds) {
  final time = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}';
}

/// Waits until the app's own history (fresh restore) holds every required
/// expected transaction for the account.
///
/// The harness chain is quiet after the handoff, so no new block triggers the
/// app's next sync. Discovery past the initial address gap needs that next
/// pass, so the wait asks the app's own sync notifier to sync again every 20s:
/// the same path a new block takes in production.
Future<void> thWaitForHistory(
  WidgetTester tester, {
  required String accountUuid,
  required List<ThUiRow> rows,
  Duration timeout = const Duration(minutes: 4),
}) async {
  final dbPath = await getWalletDbPath();
  final wanted = rows.where((r) => !r.optional).map((r) => r.txid).toSet();
  final deadline = DateTime.now().add(timeout);
  var missing = wanted;
  var nextSync = DateTime.now().add(const Duration(seconds: 20));
  var syncs = 0;
  while (DateTime.now().isBefore(deadline)) {
    try {
      final history = await rust_sync.getTransactionHistory(
        dbPath: dbPath,
        network: 'regtest',
        limit: 500,
        accountUuid: accountUuid,
      );
      final seen = history.map((t) => t.txidHex).toSet();
      missing = wanted.difference(seen);
      if (missing.isEmpty) {
        debugPrint('[th-e2e] history complete after $syncs extra syncs');
        return;
      }
    } catch (_) {}
    if (DateTime.now().isAfter(nextSync) && !rust_sync.isSyncRunning()) {
      ProviderScope.containerOf(
        tester.element(find.byType(WidgetsApp).first),
      ).read(syncProvider.notifier).startSync();
      syncs++;
      nextSync = DateTime.now().add(const Duration(seconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  // Leave the per-row checks to report the gap precisely.
  debugPrint(
    '[th-e2e] history still missing ${missing.length} txs after $syncs extra syncs',
  );
}

Set<String> _textsIn(WidgetTester tester, Finder finder) {
  if (!tester.any(finder)) return const {};
  return tester
      .widgetList<Text>(
        find.descendant(of: finder, matching: find.byType(Text)),
      )
      .map((t) => t.data)
      .whereType<String>()
      .toSet();
}

Finder _rowFinder(ThUiRow row) {
  if (row.role != null) {
    return find.byKey(ValueKey('tx:${row.txid}:${row.role}'));
  }
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith('tx:${row.txid}:');
  });
}

/// Brings a lazily built row into view by dragging the feed from the top.
Future<bool> _reveal(WidgetTester tester, Finder finder, Offset dragAt) async {
  for (var i = 0; i < 12 && !tester.any(finder); i++) {
    await tester.dragFrom(dragAt, const Offset(0, 600));
    await tester.pump(const Duration(milliseconds: 150));
  }
  for (var i = 0; i < 80 && !tester.any(finder); i++) {
    await tester.dragFrom(dragAt, const Offset(0, -250));
    await tester.pump(const Duration(milliseconds: 150));
  }
  if (!tester.any(finder)) return false;
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 200));
  return true;
}

Finder _swapRows() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith('swap:');
});

/// H11 app records. Without a retained swap record the deposit is a plain
/// send and no swap grouping may be manufactured; with the record (as the
/// reference wallet keeps it) the activity shows the swap operation instead.
/// Requires the app to be pumped with the swap feature enabled.
Future<List<String>> thVerifySwapRecord(
  WidgetTester tester, {
  required List<ThUiRow> rows,
  required String accountUuid,
  required Offset dragAt,
  required Future<void> Function() reopenActivity,
}) async {
  final failures = <String>[];
  final deposit = rows.where((r) => r.intent == 'swap_deposit').toList();
  if (deposit.isEmpty) return ['H11: no swap deposit expectation'];
  final row = deposit.first;
  await _reveal(tester, find.byKey(ValueKey('tx:${row.txid}:sent')), dragAt);
  if (tester.any(_swapRows())) {
    failures.add('H11 without records: a swap row was manufactured');
  }
  final displayTxid = _reverseHex(row.txid);
  final container = ProviderScope.containerOf(
    tester.element(find.byType(WidgetsApp).first),
  );
  final now = DateTime.now().toUtc();
  await container
      .read(swapActivityStoreProvider)
      .saveRecords(
        accountUuid: accountUuid,
        records: [
          SwapIntentRecord(
            id: 'th-h11-swap',
            providerLabel: 'NEAR Intents',
            pairText: 'ZEC -> USDC',
            sellAmountText: '0.35 ZEC',
            receiveEstimateText: '10 USDC',
            status: SwapIntentStatus.complete,
            nextAction: 'Complete',
            direction: SwapDirection.zecToExternal,
            externalAsset: SwapAsset.usdc,
            depositAddress: 'harness-deposit',
            depositTxHash: displayTxid,
            accountUuid: accountUuid,
            createdAt: now,
            updatedAt: now,
            completedAt: now,
          ),
        ],
      );
  container.read(swapActivityRecordsRevisionProvider.notifier).bump();
  await reopenActivity();
  final swapRow = find.byKey(const ValueKey('swap:th-h11-swap'));
  if (!await _reveal(tester, swapRow, dragAt)) {
    failures.add('H11 with records: the retained swap operation is not shown');
  }
  if (await _reveal(
    tester,
    find.byKey(ValueKey('tx:${row.txid}:sent')),
    dragAt,
  )) {
    failures.add(
      'H11 with records: the deposit still shows as a separate send',
    );
  }
  await container
      .read(swapActivityStoreProvider)
      .saveRecords(accountUuid: accountUuid, records: const []);
  container.read(swapActivityRecordsRevisionProvider.notifier).bump();
  return failures;
}

String _reverseHex(String hex) {
  final bytes = <String>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(hex.substring(i, i + 2));
  }
  return bytes.reversed.join();
}

/// Verifies every expected row of `account` on the open activity screen and
/// its detail screen. Returns the failures (the caller fails the test once
/// with all of them, so one run reports every spec gap).
Future<List<String>> thVerifyActivity(
  WidgetTester tester, {
  required String account,
  required List<ThUiRow> rows,
  required String ticker,
  required bool mobile,
  required Offset dragAt,
  required Future<void> Function() returnToActivity,
}) async {
  final failures = <String>[];
  for (final row in rows.where((r) => r.account == account)) {
    final finder = _rowFinder(row);
    if (!await _reveal(tester, finder, dragAt)) {
      if (!row.optional) failures.add('${row.label}: no activity row');
      continue;
    }
    final texts = _textsIn(tester, finder.first);
    if (row.role != null && row.amountZats != null) {
      final title = row.failed && row.role == 'sent'
          ? 'Send failed'
          : row.pending
          ? (mobile ? '${row.title}...' : '${row.title} ...')
          : row.title!;
      if (!texts.contains(title)) {
        failures.add('${row.label}: title "$title" not in $texts');
      }
      final amount = thActivityAmount(
        row.amountZats!,
        row.failed ? '' : row.sign,
        ticker,
      );
      if (!texts.any((t) => t == amount || t.startsWith(amount))) {
        failures.add('${row.label}: amount "$amount" not in $texts');
      }
      if (row.poolLabel != null &&
          !texts.contains(row.poolLabel) &&
          !row.poolLabels.any(texts.contains)) {
        failures.add('${row.label}: pool "${row.poolLabel}" not in $texts');
      }
      if (row.failed && row.amountZats! > 0 && !texts.contains('Refunded')) {
        failures.add('${row.label}: failed row without "Refunded" in $texts');
      }
      if (row.blockTime > 0 &&
          !texts.any((t) => t.contains(_hhmm(row.blockTime)))) {
        failures.add(
          '${row.label}: timestamp is not the block time '
          '${_hhmm(row.blockTime)}: $texts',
        );
      }
    }
    // Tappable: the row opens its detail screen.
    await tester.tap(finder.first);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    final detailTexts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toSet();
    final reviewRows = {
      for (final r in tester.widgetList<ReviewListRow>(
        find.byType(ReviewListRow),
      ))
        r.label: r.value,
    };
    if (row.status != null) {
      final status = mobile && row.status == 'Failed'
          ? 'Failed, funds returned'
          : row.status!;
      final shown = reviewRows['Status'] ?? '';
      if (shown != status && !detailTexts.contains(status)) {
        failures.add('${row.label}: detail status "$status" not shown');
      }
    }
    final feeText = reviewRows['Tx fee'];
    if (feeText != null) {
      final fee = thParseAmount(feeText, ticker);
      if (row.feeKnown != null && row.feeKnown! > 0 && !row.acceptsFee(fee)) {
        failures.add('${row.label}: fee "$feeText" != ${row.feeKnown}');
      }
      if (row.feeKnown == null && fee == 0) {
        failures.add('${row.label}: unknown fee rendered as "$feeText"');
      }
      if (row.feeKnown == null &&
          fee != null &&
          fee > 0 &&
          !row.feeValues.contains(fee)) {
        failures.add(
          '${row.label}: fee "$feeText" is not a fee the spec accepts '
          '${row.feeValues}',
        );
      }
    } else if (detailTexts.contains('Tx fee')) {
      // Mobile renders the fee in its own row widget: match by value.
      if (row.feeKnown != null &&
          row.feeKnown! > 0 &&
          !detailTexts.any((t) => row.acceptsFee(thParseAmount(t, ticker)))) {
        failures.add('${row.label}: known fee ${row.feeKnown} not shown');
      }
    } else if (row.feeKnown != null &&
        row.feeKnown! > 0 &&
        row.role == 'sent') {
      failures.add('${row.label}: known fee ${row.feeKnown} not shown');
    }
    if (detailTexts.any(
          (t) => RegExp(r'^0(\.0+)? ' + ticker + r'$').hasMatch(t),
        ) &&
        (row.amountZats ?? 1) > 0) {
      failures.add('${row.label}: detail shows a zero amount or fee');
    }
    await returnToActivity();
  }
  return failures;
}
