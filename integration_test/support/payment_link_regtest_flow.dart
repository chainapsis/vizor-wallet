import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/navigation/vizor_deep_link.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_transaction_matching.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

import 'desktop_regtest_flow.dart';

const paymentLinkRegtestNetwork = 'regtest';
const paymentLinkRegtestLightwalletdUrl = String.fromEnvironment(
  'ZCASH_E2E_LIGHTWALLETD_URL',
  defaultValue: 'http://127.0.0.1:9067',
);
const paymentLinkRegtestZcashdRpcUrl = String.fromEnvironment(
  'ZCASH_E2E_ZCASHD_RPC_URL',
  defaultValue: 'http://127.0.0.1:18232',
);
const paymentLinkRegtestZcashdRpcUser = 'zcash';
const paymentLinkRegtestZcashdRpcPassword = 'zcash';
const paymentLinkRegtestProxyUrl = 'http://127.0.0.1:19068';
const paymentLinkRestartManifestName =
    'payment_link_restart_regtest_manifest.json';

class PaymentLinkRestartManifest {
  const PaymentLinkRestartManifest({
    required this.receiverAccountUuid,
    required this.receiverStartingTotal,
    required this.claims,
  });

  final String receiverAccountUuid;
  final BigInt receiverStartingTotal;
  final List<PaymentLinkRestartClaim> claims;

  Map<String, Object?> toJson() => {
    'receiverAccountUuid': receiverAccountUuid,
    'receiverStartingTotal': receiverStartingTotal.toString(),
    'claims': [for (final claim in claims) claim.toJson()],
  };

  factory PaymentLinkRestartManifest.fromJson(Map<String, Object?> json) {
    return PaymentLinkRestartManifest(
      receiverAccountUuid: json['receiverAccountUuid']! as String,
      receiverStartingTotal: BigInt.parse(
        json['receiverStartingTotal']! as String,
      ),
      claims: [
        for (final raw in json['claims']! as List<Object?>)
          PaymentLinkRestartClaim.fromJson(raw! as Map<String, Object?>),
      ],
    );
  }
}

class PaymentLinkRestartClaim {
  const PaymentLinkRestartClaim({
    required this.address,
    required this.amountZatoshi,
    required this.directoryName,
  });

  factory PaymentLinkRestartClaim.fromLink(VizorPaymentLink link) {
    return PaymentLinkRestartClaim(
      address: link.address,
      amountZatoshi: link.amountZatoshi,
      directoryName: paymentLinkClaimWalletDirectoryName(link),
    );
  }

  factory PaymentLinkRestartClaim.fromJson(Map<String, Object?> json) {
    return PaymentLinkRestartClaim(
      address: json['address']! as String,
      amountZatoshi: BigInt.parse(json['amountZatoshi']! as String),
      directoryName: json['directoryName']! as String,
    );
  }

  final String address;
  final BigInt amountZatoshi;
  final String directoryName;

  Map<String, Object?> toJson() => {
    'address': address,
    'amountZatoshi': amountZatoshi.toString(),
    'directoryName': directoryName,
  };
}

Future<void> configurePaymentLinkRegtestProxyPrimary() async {
  final storage = AppSecureStore.instance;
  await storage.writePlain(kRpcEndpointUrlKey, paymentLinkRegtestProxyUrl);
  await storage.writePlain(
    kRpcEndpointPresetKey,
    kRegtestSlowRpcEndpointPresetId,
  );
}

Future<void> openPaymentLinksFromSettings(WidgetTester tester) async {
  await tapPaymentLinkText(tester, 'Settings');
  await tapAppWidget(tester, const ValueKey('settings_gift_cards_row'));
  await pumpUntil(
    tester,
    () =>
        tester.any(find.byKey(const ValueKey('payment_links_desktop_screen'))),
    description: 'payment-link desktop screen to render',
  );
}

Future<VizorPaymentLink> createPaymentLinkForRegtest(
  WidgetTester tester, {
  required String amountText,
  required String artworkId,
  required String message,
}) async {
  await tapAppButton(tester, const ValueKey('payment_link_create_card_button'));
  await enterAppText(
    tester,
    const ValueKey('payment_link_amount_editor'),
    amountText,
  );
  await tapAppWidget(tester, ValueKey('payment_link_card_selector_$artworkId'));
  await tapAppButton(
    tester,
    const ValueKey('payment_link_amount_continue_button'),
  );
  final startTyping = find.text('Start typing...');
  await pumpUntil(
    tester,
    () => tester.any(startTyping),
    description: 'payment-link message card action',
  );
  await tester.tap(startTyping);
  await tester.pumpAndSettle();
  await enterAppText(
    tester,
    const ValueKey('payment_link_message_editor'),
    message,
  );
  await tapAppButton(
    tester,
    const ValueKey('payment_link_message_continue_button'),
  );
  await tapAppButton(
    tester,
    const ValueKey('payment_link_confirm_create_button'),
  );
  final copyButton = find.byKey(
    const ValueKey('payment_link_copy_link_button'),
  );
  await pumpUntil(
    tester,
    () => tester.any(copyButton),
    description: 'payment-link copy action after broadcast acceptance',
    timeout: const Duration(minutes: 2),
  );
  await tapAppButton(tester, const ValueKey('payment_link_copy_link_button'));
  final rawLink = await readPaymentLinkFromClipboard();
  final link = VizorPaymentLink.parse(rawLink);
  expect(link.network, paymentLinkRegtestNetwork);
  expect(link.presentation?.artworkId, artworkId);
  expect(link.presentation?.message, message);
  await tapPaymentLinkText(tester, 'Return home');
  return link;
}

Future<void> claimPaymentLinkForRegtest(
  WidgetTester tester,
  VizorPaymentLink link, {
  bool waitUntilReceiving = true,
}) async {
  await Clipboard.setData(ClipboardData(text: link.toUri().toString()));
  await tapPaymentLinkText(tester, 'Redeem a card');
  await tapPaymentLinkText(tester, 'Paste card link');
  await pumpUntil(
    tester,
    () => tester.any(find.byKey(const ValueKey('payment_link_claim_button'))),
    description: 'confirmed Gift Card claim action',
    timeout: const Duration(minutes: 2),
  );
  await tapAppButton(tester, const ValueKey('payment_link_claim_button'));
  if (!waitUntilReceiving) return;
  await waitForReceivedRecords(
    tester,
    (records) => records.any(
      (record) =>
          record.address == link.address &&
          record.status == PaymentLinkReceivedStatus.receiving &&
          (record.claimTxids?.isNotEmpty ?? false),
    ),
    description: '${link.address} persisted as Receiving',
  );
}

Future<void> waitForForegroundSyncIdle(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ZcashWalletApp)),
  );
  await pumpUntil(
    tester,
    () => container.read(syncProvider).value?.isSyncing == false,
    description: 'foreground sync completion to finish applying',
    timeout: const Duration(minutes: 2),
  );
  await tester.pump(const Duration(milliseconds: 250));
}

Future<List<PaymentLinkReceivedRecord>> waitForReceivedRecords(
  WidgetTester tester,
  bool Function(List<PaymentLinkReceivedRecord> records) condition, {
  required String description,
  Duration timeout = const Duration(minutes: 3),
}) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ZcashWalletApp)),
  );
  final operations = container.read(paymentLinkOperationsProvider);
  List<PaymentLinkReceivedRecord> last = const [];
  Object? lastError;
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      last = await operations.loadReceivedLinkRecoveries();
      if (condition(last)) return last;
      lastError = null;
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail(
    'Timed out waiting for $description. '
    'Statuses: ${last.map((record) => '${record.address}:${record.status.name}').join(', ')}. '
    'Last error: $lastError',
  );
}

Future<rust_sync.TransactionInfo> waitForPaymentLinkHistoryTransaction(
  WidgetTester tester, {
  required String accountUuid,
  required String txKind,
  required BigInt amount,
  required bool pending,
  String? txid,
  Duration timeout = const Duration(minutes: 3),
}) async {
  final dbPath = await getWalletDbPath();
  final deadline = DateTime.now().add(timeout);
  List<rust_sync.TransactionInfo> last = const [];
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      last = await rust_sync.getTransactionHistory(
        dbPath: dbPath,
        network: paymentLinkRegtestNetwork,
        limit: 50,
        accountUuid: accountUuid,
      );
      for (final transaction in last) {
        if (transaction.txKind == txKind &&
            transaction.displayAmount == amount &&
            (transaction.minedHeight == BigInt.zero) == pending &&
            !transaction.expiredUnmined &&
            (txid == null || transaction.txidHex == txid)) {
          return transaction;
        }
      }
      lastError = null;
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  final history = last
      .map(
        (transaction) =>
            '${transaction.txidHex}:${transaction.txKind}:'
            '${transaction.displayAmount}:height=${transaction.minedHeight}',
      )
      .join(', ');
  fail(
    'Timed out waiting for $txKind amount=$amount pending=$pending. '
    'History: $history. Last error: $lastError',
  );
}

Future<rust_sync.WalletBalance> readPaymentLinkAccountBalance(
  String accountUuid,
) async {
  return rust_sync.getBalance(
    dbPath: await getWalletDbPath(),
    network: paymentLinkRegtestNetwork,
    accountUuid: accountUuid,
  );
}

Future<rust_sync.WalletBalance> waitForPaymentLinkAccountBalance(
  WidgetTester tester, {
  required String accountUuid,
  required BigInt total,
  BigInt? spendable,
  Duration timeout = const Duration(minutes: 3),
}) async {
  rust_sync.WalletBalance? last;
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      last = await readPaymentLinkAccountBalance(accountUuid);
      if (last.total == total &&
          (spendable == null || last.spendable == spendable)) {
        return last;
      }
    } catch (_) {
      // The foreground sync can briefly own the wallet connection.
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail(
    'Timed out waiting for account balance total=$total spendable=$spendable. '
    'Last balance: $last',
  );
}

Future<void> minePaymentLinkRegtestBlocks(int blocks) async {
  e2eLog('mining $blocks regtest block(s)');
  final before = await paymentLinkZcashdRpc<int>('getblockcount');
  await paymentLinkZcashdRpc<List<Object?>>('generate', [blocks]);
  final targetHeight = before + blocks;
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final lightwalletdHeight = await rust_wallet.getLatestBlockHeight(
      lightwalletdUrl: paymentLinkRegtestLightwalletdUrl,
    );
    if (lightwalletdHeight.toInt() >= targetHeight) return;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw StateError('Timed out waiting for lightwalletd height $targetHeight.');
}

Future<T> paymentLinkZcashdRpc<T>(
  String method, [
  List<Object?> params = const [],
]) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse(paymentLinkRegtestZcashdRpcUrl),
    );
    final credentials = base64Encode(
      utf8.encode(
        '$paymentLinkRegtestZcashdRpcUser:'
        '$paymentLinkRegtestZcashdRpcPassword',
      ),
    );
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Basic $credentials')
      ..contentType = ContentType.json;
    request.write(
      jsonEncode({
        'jsonrpc': '1.0',
        'id': 'payment-link-restart-regtest-e2e',
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
    if (decoded['error'] case final error?) {
      throw StateError('zcashd RPC $method failed: $error');
    }
    return decoded['result'] as T;
  } finally {
    client.close(force: true);
  }
}

Future<void> waitForPaymentLinkMempoolTxids(
  WidgetTester tester,
  Iterable<String> txids, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  final expected = txids.map(normalizePaymentLinkTxid).toSet();
  Set<String> last = const {};
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final raw = await paymentLinkZcashdRpc<List<Object?>>('getrawmempool');
    last = raw.map((txid) => normalizePaymentLinkTxid('$txid')).toSet();
    if (last.containsAll(expected)) return;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail(
    'Timed out waiting for claim txids in the regtest mempool. '
    'Expected: $expected. Observed: $last',
  );
}

Future<void> tapPaymentLinkText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await pumpUntil(
    tester,
    () => tester.any(finder),
    description: '$text action to render',
  );
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 250));
}

Future<String> readPaymentLinkFromClipboard() async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final rawLink = data?.text?.trim() ?? '';
  if (!rawLink.startsWith(
    'https://${VizorDeepLink.host}${VizorDeepLink.paymentLinkPath}#v1=',
  )) {
    fail('The clipboard did not contain a Vizor payment link.');
  }
  return rawLink;
}

Future<Directory> paymentLinkClaimWalletDirectory(VizorPaymentLink link) {
  return paymentLinkClaimWalletDirectoryByName(
    paymentLinkClaimWalletDirectoryName(link),
  );
}

Future<Directory> paymentLinkClaimWalletDirectoryByName(
  String directoryName,
) async {
  final support = await getWalletSupportDirectory();
  return Directory('${support.path}${Platform.pathSeparator}$directoryName');
}

Future<File> _paymentLinkRestartManifestFile() async {
  final support = await getWalletSupportDirectory();
  return File(
    '${support.path}${Platform.pathSeparator}$paymentLinkRestartManifestName',
  );
}

Future<void> writePaymentLinkRestartManifest(
  PaymentLinkRestartManifest manifest,
) async {
  final file = await _paymentLinkRestartManifestFile();
  await file.writeAsString(jsonEncode(manifest.toJson()), flush: true);
}

Future<PaymentLinkRestartManifest> readPaymentLinkRestartManifest() async {
  final file = await _paymentLinkRestartManifestFile();
  final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
  return PaymentLinkRestartManifest.fromJson(json);
}

Future<void> deletePaymentLinkRestartManifest() async {
  final file = await _paymentLinkRestartManifestFile();
  if (await file.exists()) await file.delete();
}
