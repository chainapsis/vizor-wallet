import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_transaction_matching.dart';

import 'support/desktop_regtest_flow.dart';
import 'support/payment_link_regtest_flow.dart';
import 'support/regtest_lightwalletd_proxy.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'keeps a 50-card group whose accepted broadcast response was lost',
    (tester) async {
      var preparedForRestart = false;
      final proxy = RegtestLightwalletdProxy(log: e2eLog);
      await proxy.start();
      addTearDown(proxy.stop);
      addTearDown(() async {
        if (preparedForRestart) return;
        await cleanupDesktopRegtestWallet();
        await cleanupRegtestPaymentLinkClaimWallets();
        await deletePaymentLinkBatchRestartManifest();
      });

      await cleanupDesktopRegtestWallet();
      await cleanupRegtestPaymentLinkClaimWallets();
      await deletePaymentLinkBatchRestartManifest();
      await configurePaymentLinkRegtestProxyPrimary();

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await importDesktopRegtestWallet(tester);
      final accountUuid = await firstDesktopRegtestAccountUuid();
      await waitForForegroundSyncIdle(tester);
      await waitForPaymentLinkAccountBalance(
        tester,
        accountUuid: accountUuid,
        total: BigInt.from(125_000_000),
        spendable: BigInt.from(125_000_000),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ZcashWalletApp)),
      );
      final draft = await container
          .read(paymentLinkBatchOperationsProvider)
          .prepareBatch(
            count: 50,
            amountZatoshi: BigInt.from(1_000_000),
            sourceAccountUuid: accountUuid,
            presentation: const PaymentLinkPresentation(artworkId: 'ruby'),
          );

      // The node receives the transaction, but the app never learns it did.
      proxy.dropNextAcceptedSendResponse();
      final result = await container
          .read(paymentLinkBatchOperationsProvider)
          .fundBatch(draft);
      expect(proxy.droppedAcceptedResponseCount, 1);
      expect(result.broadcastAccepted, isFalse);
      expect(result.txids.split(','), hasLength(1));
      await _waitForMempoolTxid(tester, result.txids);

      final members =
          (await container
                  .read(paymentLinkOperationsProvider)
                  .loadCreatedLinkRecoveries())
              .where((record) => record.batchId == draft.id)
              .toList();
      expect(members, hasLength(50));
      expect(members.map((record) => record.fundingTxids).toSet(), {
        result.txids,
      });

      await openPaymentLinksFromSettings(tester);
      await pumpUntil(
        tester,
        () =>
            tester.any(find.byKey(ValueKey('payment_link_batch_${draft.id}'))),
        description: 'group row before restart',
      );

      await writePaymentLinkBatchRestartManifest(
        PaymentLinkBatchRestartManifest(
          senderAccountUuid: accountUuid,
          batchId: draft.id,
          fundingTxid: result.txids,
          addresses: [for (final link in draft.links) link.address],
        ),
      );
      preparedForRestart = true;
      e2eLog(
        'batch restart prepared: 50 cards, lost broadcast response, '
        'txid=${result.txids}',
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Future<void> _waitForMempoolTxid(WidgetTester tester, String txid) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  var mempool = const <String>[];
  while (DateTime.now().isBefore(deadline)) {
    mempool = [
      for (final entry in await paymentLinkZcashdRpc<List<Object?>>(
        'getrawmempool',
      ))
        '$entry',
    ];
    if (mempool.any((entry) => paymentLinkTxidsMatch(entry, txid))) return;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('The batch transaction $txid never reached the mempool: $mempool');
}
