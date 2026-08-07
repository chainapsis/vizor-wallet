import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/formatting/zec_amount.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

import 'support/desktop_regtest_flow.dart';

const _network = 'regtest';
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
const _giftAmountText = '0.1';
final _giftAmountZatoshi = BigInt.from(10_000_000);
final _fundingAmountZatoshi = BigInt.from(10_010_000);
const _giftMessage = 'Congrats from the payment link E2E!';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'creates, opens, and claims a payment link between two regtest accounts',
    (tester) async {
      addTearDown(() async {
        await Clipboard.setData(const ClipboardData(text: ''));
        await cleanupDesktopRegtestWallet();
        await deletePaymentLinkClaimWalletDirectories();
      });

      await cleanupDesktopRegtestWallet();
      await deletePaymentLinkClaimWalletDirectories();

      e2eLog('pumping app for payment-link round trip');
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());

      await importDesktopRegtestWallet(tester);
      final senderAccountUuid = await firstDesktopRegtestAccountUuid();
      await _waitForForegroundSyncIdle(tester);
      final senderStartingBalance = await _waitForAccountBalanceAtLeast(
        tester,
        accountUuid: senderAccountUuid,
        total: BigInt.from(125000000),
        spendable: BigInt.from(125000000),
      );
      await _waitForHomeBalance(
        tester,
        ZecAmount.fromZatoshi(senderStartingBalance.total).balance.amountText,
      );

      await _openPaymentLinksFromSidebar(tester);
      await tapAppButton(
        tester,
        const ValueKey('payment_link_create_card_button'),
      );
      await enterAppText(
        tester,
        const ValueKey('payment_link_amount_editor'),
        _giftAmountText,
      );
      await tapAppWidget(
        tester,
        const ValueKey('payment_link_card_selector_coin'),
      );
      await tapAppButton(
        tester,
        const ValueKey('payment_link_amount_continue_button'),
      );
      await tapAppWidget(
        tester,
        const ValueKey('payment_link_message_card_front'),
      );
      await enterAppText(
        tester,
        const ValueKey('payment_link_message_editor'),
        _giftMessage,
      );
      await tapAppButton(
        tester,
        const ValueKey('payment_link_message_continue_button'),
      );
      await tapAppButton(
        tester,
        const ValueKey('payment_link_confirm_create_button'),
      );
      await pumpUntil(
        tester,
        () => tester.any(find.text('Gift Card is\nalmost ready!')),
        description: 'payment-link funding to reach confirmation wait',
        timeout: const Duration(minutes: 2),
      );
      expect(find.text('Gift Card is\nalmost ready!'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('payment_link_copy_link_button')),
        findsNothing,
      );

      final pendingFunding = await _waitForHistoryTransaction(
        tester,
        accountUuid: senderAccountUuid,
        txKind: 'sent',
        amount: _fundingAmountZatoshi,
        pending: true,
      );
      await _mineRegtestBlocks(kPaymentLinkShareConfirmationTarget);
      final minedFunding = await _waitForHistoryTransaction(
        tester,
        accountUuid: senderAccountUuid,
        txKind: 'sent',
        amount: _fundingAmountZatoshi,
        pending: false,
        txid: pendingFunding.txidHex,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ZcashWalletApp)),
      );
      final operations = container.read(paymentLinkOperationsProvider);
      final senderRecoveries =
          (await operations.loadCreatedLinkRecoveries())
              .where((record) => record.sourceAccountUuid == senderAccountUuid)
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final fundingRecovery = senderRecoveries.first;
      final fundingProgress = await operations.inspectCreatedLinkFundings([
        fundingRecovery,
      ]);
      expect(
        fundingProgress[fundingRecovery.link.address]?.confirmationCount,
        kPaymentLinkShareConfirmationTarget,
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('payment_link_copy_link_button')),
        ),
        description: 'payment-link copy action after ten confirmations',
        timeout: const Duration(minutes: 2),
      );
      await tapAppButton(
        tester,
        const ValueKey('payment_link_copy_link_button'),
      );

      final rawLink = await _readPaymentLinkFromClipboard();
      final link = VizorPaymentLink.decode(rawLink);
      expect(link.network, _network);
      expect(link.amountZatoshi, _giftAmountZatoshi);
      expect(link.presentation?.artworkId, 'coin');
      expect(link.presentation?.message, _giftMessage);

      await importAdditionalDesktopRegtestWallet(tester);
      final accounts = await desktopRegtestAccounts();
      final receiverAccountUuid = accounts
          .singleWhere((account) => account.uuid != senderAccountUuid)
          .uuid;
      await _waitForForegroundSyncIdle(tester);
      final receiverStartingBalance = await _readAccountBalance(
        receiverAccountUuid,
      );
      await _openPaymentLink(rawLink);
      await pumpUntil(
        tester,
        () =>
            tester.any(find.byKey(const ValueKey('payment_link_claim_button'))),
        description: 'received payment-link card to render',
        timeout: const Duration(minutes: 1),
      );
      expect(find.text(_giftAmountText), findsOneWidget);
      expect(
        tester
            .widget<PaymentLinkGiftCard>(find.byType(PaymentLinkGiftCard))
            .artwork,
        PaymentLinkCardArtwork.coin,
      );
      await tapAppWidget(
        tester,
        const ValueKey('payment_link_reveal_message_action'),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(_giftMessage), findsOneWidget);

      await tapAppButton(tester, const ValueKey('payment_link_claim_button'));
      final pendingClaim = await _waitForHistoryTransaction(
        tester,
        accountUuid: receiverAccountUuid,
        txKind: 'receiving',
        amount: _giftAmountZatoshi,
        pending: true,
      );
      expect(pendingClaim.txidHex, isNot(minedFunding.txidHex));

      await _mineRegtestBlocks(1);
      final minedClaim = await _waitForHistoryTransaction(
        tester,
        accountUuid: receiverAccountUuid,
        txKind: 'received',
        amount: _giftAmountZatoshi,
        pending: false,
        txid: pendingClaim.txidHex,
      );
      expect(minedClaim.txidHex, isNot(minedFunding.txidHex));
      await _waitForAccountBalance(
        tester,
        accountUuid: receiverAccountUuid,
        total: receiverStartingBalance.total + _giftAmountZatoshi,
      );

      // The claim wallet can spend the funding note after one confirmation.
      // The receiver's ordinary wallet still requires ten confirmations before
      // that externally received value becomes spendable.
      await _mineRegtestBlocks(9);
      await _waitForAccountBalance(
        tester,
        accountUuid: receiverAccountUuid,
        total: receiverStartingBalance.total + _giftAmountZatoshi,
        spendable: receiverStartingBalance.spendable + _giftAmountZatoshi,
      );
      await tapAppWidget(tester, const ValueKey('sidebar_home_button'));
      await _waitForHomeBalance(
        tester,
        ZecAmount.fromZatoshi(
          receiverStartingBalance.total + _giftAmountZatoshi,
        ).balance.amountText,
      );
      e2eLog('payment-link round trip completed with two distinct txids');
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<void> _waitForForegroundSyncIdle(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ZcashWalletApp)),
  );
  await pumpUntil(
    tester,
    () => container.read(syncProvider).value?.isSyncing == false,
    description: 'foreground sync completion to finish applying',
    timeout: const Duration(minutes: 1),
  );
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _openPaymentLinksFromSidebar(WidgetTester tester) async {
  await tapAppWidget(tester, const ValueKey('sidebar_payment_links_button'));
  await pumpUntil(
    tester,
    () =>
        tester.any(find.byKey(const ValueKey('payment_links_desktop_screen'))),
    description: 'payment-link desktop screen to render',
  );
}

Future<String> _readPaymentLinkFromClipboard() async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final rawLink = data?.text?.trim() ?? '';
  if (rawLink.isEmpty) {
    fail('The payment link was not copied to the clipboard.');
  }
  if (!rawLink.startsWith('vizor://payment-link?')) {
    fail('The clipboard did not contain a Vizor payment link.');
  }
  return rawLink;
}

Future<void> _openPaymentLink(String rawLink) async {
  final result = await Process.run('/usr/bin/open', [
    '-a',
    _currentAppBundlePath(),
    rawLink,
  ]);
  if (result.exitCode != 0) {
    throw StateError('macOS could not open the payment link: ${result.stderr}');
  }
}

String _currentAppBundlePath() {
  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.path != directory.parent.path) {
    if (directory.path.endsWith('.app')) return directory.path;
    directory = directory.parent;
  }
  throw StateError(
    'Could not find the current app bundle from '
    '${Platform.resolvedExecutable}.',
  );
}

Future<void> _mineRegtestBlocks(int blocks) async {
  e2eLog('mining $blocks regtest block(s)');
  final before = await _zcashdRpc<int>('getblockcount');
  await _zcashdRpc<List<Object?>>('generate', [blocks]);
  final targetHeight = before + blocks;
  final deadline = DateTime.now().add(const Duration(seconds: 30));

  while (DateTime.now().isBefore(deadline)) {
    final lightwalletdHeight = await rust_wallet.getLatestBlockHeight(
      lightwalletdUrl: _lightwalletdUrl,
    );
    if (lightwalletdHeight.toInt() >= targetHeight) {
      e2eLog('lightwalletd reached mined height $targetHeight');
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
        'id': 'payment-link-regtest-e2e',
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

Future<rust_sync.TransactionInfo> _waitForHistoryTransaction(
  WidgetTester tester, {
  required String accountUuid,
  required String txKind,
  required BigInt amount,
  required bool pending,
  String? txid,
  Duration timeout = const Duration(minutes: 2),
}) async {
  final dbPath = await getWalletDbPath();
  final deadline = DateTime.now().add(timeout);
  List<rust_sync.TransactionInfo> last = const [];
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      last = await rust_sync.getTransactionHistory(
        dbPath: dbPath,
        network: _network,
        limit: 30,
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

Future<rust_sync.WalletBalance> _waitForAccountBalance(
  WidgetTester tester, {
  required String accountUuid,
  required BigInt total,
  BigInt? spendable,
  Duration timeout = const Duration(minutes: 4),
}) async {
  final dbPath = await getWalletDbPath();
  final deadline = DateTime.now().add(timeout);
  rust_sync.WalletBalance? last;
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      last = await rust_sync.getBalance(
        dbPath: dbPath,
        network: _network,
        accountUuid: accountUuid,
      );
      if (last.total == total &&
          (spendable == null || last.spendable == spendable)) {
        return last;
      }
      lastError = null;
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail(
    'Timed out waiting for account balance total=$total spendable=$spendable. '
    'Last total=${last?.total}, spendable=${last?.spendable}. '
    'Last error: $lastError',
  );
}

Future<rust_sync.WalletBalance> _waitForAccountBalanceAtLeast(
  WidgetTester tester, {
  required String accountUuid,
  required BigInt total,
  required BigInt spendable,
  Duration timeout = const Duration(minutes: 4),
}) async {
  final deadline = DateTime.now().add(timeout);
  rust_sync.WalletBalance? last;
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      last = await _readAccountBalance(accountUuid);
      if (last.total >= total && last.spendable >= spendable) return last;
      lastError = null;
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail(
    'Timed out waiting for account balance total>=$total '
    'spendable>=$spendable. Last total=${last?.total}, '
    'spendable=${last?.spendable}. Last error: $lastError',
  );
}

Future<rust_sync.WalletBalance> _readAccountBalance(String accountUuid) async {
  return rust_sync.getBalance(
    dbPath: await getWalletDbPath(),
    network: _network,
    accountUuid: accountUuid,
  );
}

Future<void> _waitForHomeBalance(
  WidgetTester tester,
  String expected, {
  Duration timeout = const Duration(minutes: 4),
}) {
  return pumpUntil(
    tester,
    () =>
        textForKey(
          tester,
          const ValueKey('home_desktop_balance_amount_text'),
        ) ==
        expected,
    description: 'home balance to show $expected',
    timeout: timeout,
  );
}
