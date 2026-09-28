import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_transaction_matching.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/desktop_regtest_flow.dart';
import 'support/payment_link_regtest_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeZcashWalletRuntime);

  testWidgets('funds 2, 10 and 50 distinct gift cards, one transaction each', (
    tester,
  ) async {
    addTearDown(() async {
      await cleanupDesktopRegtestWallet();
      await cleanupRegtestPaymentLinkClaimWallets();
    });
    await cleanupDesktopRegtestWallet();
    await cleanupRegtestPaymentLinkClaimWallets();
    await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
    await importDesktopRegtestWallet(tester);
    final accountUuid = await firstDesktopRegtestAccountUuid();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ZcashWalletApp)),
    );
    await pumpUntil(
      tester,
      () {
        final sync = container.read(syncProvider).value;
        return sync?.isSyncComplete == true &&
            sync?.isSyncing == false &&
            sync!.spendableBalance >= BigInt.from(125000000);
      },
      description: 'sender spendable balance for 50-card batch',
      timeout: const Duration(minutes: 4),
    );

    final operations = container.read(paymentLinkBatchOperationsProvider);
    // Same process and chain for every size, so the numbers compare directly.
    // Max RSS is a process high-water mark, so sizes are funded smallest
    // first and before the larger QR batches below.
    for (final count in [2, 10, 50]) {
      await _fundAndMeasureBatch(
        tester,
        container: container,
        operations: operations,
        accountUuid: accountUuid,
        count: count,
      );
      // Confirm the change so the next step can spend it.
      await minePaymentLinkRegtestBlocks(10);
    }

    await _waitForSpendable(
      tester,
      container: container,
      accountUuid: accountUuid,
      needed: BigInt.from(50 * 1_010_000 + 1_000_000),
      purpose: 'the 50-card QR batch',
    );
    final signing = container.read(paymentLinkHardwareSigningServiceProvider);
    for (final qrCount in [2, 20, 30, 50]) {
      final qrBatch = await operations.prepareBatch(
        count: qrCount,
        amountZatoshi: BigInt.from(1_000_000),
        sourceAccountUuid: accountUuid,
        presentation: const PaymentLinkPresentation(artworkId: 'ruby'),
      );
      PaymentLinkHardwarePcztDraft? qrDraft;
      try {
        qrDraft = await signing.createBatchFundingPczt(qrBatch);
        final qrParts = await signing.encodeSigningUrParts(draft: qrDraft);
        expect(qrParts, isNotEmpty);
        e2eLog('batch=$qrCount keystone_qr_parts=${qrParts.length}');
      } finally {
        if (qrDraft case final draft?) {
          await signing.discardPcztDraft(draft: draft);
        } else {
          await operations.abandonUnsubmittedBatch(qrBatch.id);
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}

Future<void> _fundAndMeasureBatch(
  WidgetTester tester, {
  required ProviderContainer container,
  required PaymentLinkBatchOperations operations,
  required String accountUuid,
  required int count,
}) async {
  final cardsTotal = BigInt.from(count * 1_010_000);
  await _waitForSpendable(
    tester,
    container: container,
    accountUuid: accountUuid,
    needed: cardsTotal + BigInt.from(1_000_000),
    purpose: 'the $count-card batch',
  );

  final stopwatch = Stopwatch()..start();
  final draft = await operations.prepareBatch(
    count: count,
    amountZatoshi: BigInt.from(1_000_000),
    sourceAccountUuid: accountUuid,
    presentation: const PaymentLinkPresentation(artworkId: 'ruby'),
  );
  final quoteElapsed = stopwatch.elapsed;
  expect(draft.links.length, count);
  expect(draft.links.map((link) => link.address).toSet().length, count);
  expect(
    draft.quote.totalDeductedZatoshi,
    cardsTotal + draft.quote.fundingFeeZatoshi,
  );

  stopwatch.reset();
  final result = await operations.fundBatch(draft);
  final proofAndBroadcastElapsed = stopwatch.elapsed;
  stopwatch.stop();
  expect(result.txids.split(',').length, 1);
  expect(result.broadcastAccepted, isTrue);
  expect(result.fundingMetadataSaved, isTrue);
  final recoveries =
      (await container
              .read(paymentLinkOperationsProvider)
              .loadCreatedLinkRecoveries())
          .where((record) => record.batchId == draft.id)
          .toList();
  expect(recoveries.length, count);
  expect(recoveries.map((record) => record.fundingTxids).toSet(), {
    result.txids,
  });
  final raw = await paymentLinkZcashdRpc<Map<String, Object?>>(
    'getrawtransaction',
    [result.txids, 1],
  );
  final orchardActions =
      (raw['orchard'] as Map<String, Object?>)['actions'] as List<Object?>;
  final ironwoodActions =
      ((raw['ironwood'] as Map<String, Object?>?)?['actions']
          as List<Object?>?) ??
      const [];
  final transactionBytes = raw['size'] as int;
  expect(
    orchardActions.length + ironwoodActions.length,
    greaterThanOrEqualTo(count),
  );
  expect(transactionBytes, greaterThan(0));
  final metrics = {
    'fee': draft.quote.fundingFeeZatoshi.toInt(),
    'quote_ms': quoteElapsed.inMilliseconds,
    'proof_broadcast_ms': proofAndBroadcastElapsed.inMilliseconds,
    'tx_bytes': transactionBytes,
    'orchard_actions': orchardActions.length,
    'ironwood_actions': ironwoodActions.length,
    'rss_bytes': ProcessInfo.currentRss,
    'max_rss_bytes': ProcessInfo.maxRss,
  };
  e2eLog(
    'batch=$count '
    '${metrics.entries.map((entry) => '${entry.key}=${entry.value}').join(' ')}',
  );
  // `flutter drive` writes this to build/integration_response_data.json.
  (IntegrationTestWidgetsFlutterBinding.instance.reportData ??=
          {})['batch_$count'] =
      metrics;
  e2eLog('batch=$count funding txid=${result.txids}');
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  List<rust_sync.TransactionInfo> lastHistory = const [];
  while (DateTime.now().isBefore(deadline)) {
    lastHistory = await rust_sync.getTransactionHistory(
      dbPath: await getWalletDbPath(),
      network: 'regtest',
      accountUuid: accountUuid,
      limit: null,
    );
    final batchHistory = lastHistory.where(
      (tx) => paymentLinkTxidsMatch(tx.txidHex, result.txids),
    );
    if (batchHistory.isNotEmpty) {
      expect(batchHistory.single.txKind, 'sent');
      expect(batchHistory.single.displayAmount, cardsTotal);
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail(
    'The accepted $count-card transaction ${result.txids} did not reach '
    'sender history: ${lastHistory.map((tx) => '${tx.txidHex}:${tx.txKind}:'
        '${tx.displayAmount}:height=${tx.minedHeight}').join(', ')}',
  );
}

Future<void> _waitForSpendable(
  WidgetTester tester, {
  required ProviderContainer container,
  required String accountUuid,
  required BigInt needed,
  required String purpose,
}) async {
  // Read the wallet DB, not the cached sync state: right after mining, the
  // cached value can still predate the scan that makes change spendable.
  // Also wait for the scan of the mined blocks: until the previous funding is
  // seen mined, its sibling notes are not selectable even though the balance
  // already counts them as spendable.
  final chainTip = await paymentLinkZcashdRpc<int>('getblockcount');
  final deadline = DateTime.now().add(const Duration(minutes: 4));
  Object? lastBalance;
  while (true) {
    try {
      final balance = await readPaymentLinkAccountBalance(accountUuid);
      lastBalance = balance;
      final sync = container.read(syncProvider).value;
      if (balance.spendable >= needed &&
          sync?.isSyncing == false &&
          (sync?.scannedHeight ?? 0) >= chainTip) {
        return;
      }
    } catch (error) {
      // The foreground sync can briefly own the wallet connection.
      lastBalance = error;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'Spendable for $purpose never reached $needed at height $chainTip: '
        '$lastBalance',
      );
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
}
