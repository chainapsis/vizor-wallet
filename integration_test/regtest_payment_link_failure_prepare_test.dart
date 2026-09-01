import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';

import 'support/desktop_regtest_flow.dart';
import 'support/payment_link_regtest_flow.dart';
import 'support/regtest_lightwalletd_proxy.dart';

final _firstFundingAmount = BigInt.from(10_010_000);
final _secondFundingAmount = BigInt.from(20_010_000);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'persists an uncertain claim without blocking a second Gift Card',
    (tester) async {
      var preparedForRestart = false;
      final proxy = RegtestLightwalletdProxy(log: e2eLog);
      await proxy.start();
      addTearDown(proxy.stop);
      addTearDown(() async {
        await Clipboard.setData(const ClipboardData(text: ''));
        if (preparedForRestart) return;
        await cleanupDesktopRegtestWallet();
        await deletePaymentLinkClaimWalletDirectories();
        await deletePaymentLinkRestartManifest();
      });

      await cleanupDesktopRegtestWallet();
      await deletePaymentLinkClaimWalletDirectories();
      await deletePaymentLinkRestartManifest();
      await configurePaymentLinkRegtestProxyPrimary();

      final claimStatuses = <String, PaymentLinkClaimBroadcastStatus>{};
      await tester.pumpWidget(
        await buildBootstrappedZcashWalletApp(
          overrides: [
            paymentLinkClaimSubmitterProvider.overrideWith((ref) {
              final operations = ref.watch(paymentLinkOperationsProvider);
              return (session) async {
                final result = await operations.claimPreparedLink(session);
                claimStatuses[session.link.address] = result.status;
                return result;
              };
            }),
          ],
        ),
      );
      await importDesktopRegtestWallet(tester);
      final senderAccountUuid = await firstDesktopRegtestAccountUuid();
      await waitForForegroundSyncIdle(tester);
      await waitForPaymentLinkAccountBalance(
        tester,
        accountUuid: senderAccountUuid,
        total: BigInt.from(125_000_000),
        spendable: BigInt.from(125_000_000),
      );

      await openPaymentLinksFromSettings(tester);
      final firstLink = await createPaymentLinkForRegtest(
        tester,
        amountText: '0.1',
        artworkId: 'coin',
        message: 'Uncertain restart Gift Card',
      );
      final firstFunding = await waitForPaymentLinkHistoryTransaction(
        tester,
        accountUuid: senderAccountUuid,
        txKind: 'sent',
        amount: _firstFundingAmount,
        pending: true,
      );
      await minePaymentLinkRegtestBlocks(10);
      await waitForPaymentLinkHistoryTransaction(
        tester,
        accountUuid: senderAccountUuid,
        txKind: 'sent',
        amount: _firstFundingAmount,
        pending: false,
        txid: firstFunding.txidHex,
      );
      await waitForForegroundSyncIdle(tester);

      final secondLink = await createPaymentLinkForRegtest(
        tester,
        amountText: '0.2',
        artworkId: 'coin',
        message: 'Independent restart Gift Card',
      );
      final secondFunding = await waitForPaymentLinkHistoryTransaction(
        tester,
        accountUuid: senderAccountUuid,
        txKind: 'sent',
        amount: _secondFundingAmount,
        pending: true,
      );
      await minePaymentLinkRegtestBlocks(kPaymentLinkClaimConfirmationTarget);
      await waitForPaymentLinkHistoryTransaction(
        tester,
        accountUuid: senderAccountUuid,
        txKind: 'sent',
        amount: _secondFundingAmount,
        pending: false,
        txid: secondFunding.txidHex,
      );

      await importAdditionalDesktopRegtestWallet(tester);
      final receiverAccountUuid = (await desktopRegtestAccounts())
          .singleWhere((account) => account.uuid != senderAccountUuid)
          .uuid;
      await waitForForegroundSyncIdle(tester);
      final receiverStartingBalance = await readPaymentLinkAccountBalance(
        receiverAccountUuid,
      );

      await openPaymentLinksFromSettings(tester);
      proxy.failNextSendTransactions(1);
      await claimPaymentLinkForRegtest(tester, firstLink);
      expect(proxy.failedSendTransactionCount, 1);
      expect(
        claimStatuses[firstLink.address],
        PaymentLinkClaimBroadcastStatus.pendingBroadcast,
      );

      await claimPaymentLinkForRegtest(tester, secondLink);
      expect(
        claimStatuses[secondLink.address],
        PaymentLinkClaimBroadcastStatus.broadcasted,
      );

      final receiving = await waitForReceivedRecords(
        tester,
        (records) => [firstLink, secondLink].every(
          (link) => records.any(
            (record) =>
                record.address == link.address &&
                record.status == PaymentLinkReceivedStatus.receiving &&
                (record.claimTxids?.isNotEmpty ?? false),
          ),
        ),
        description: 'uncertain and accepted claims to remain Receiving',
      );
      expect(receiving, hasLength(2));
      await waitForPaymentLinkMempoolTxids(
        tester,
        receiving.expand(
          (record) => record.claimTxids!.split(',').map((txid) => txid.trim()),
        ),
      );

      for (final link in [firstLink, secondLink]) {
        final directory = await paymentLinkClaimWalletDirectory(link);
        expect(await directory.exists(), isTrue);
        expect(
          await File(
            '${directory.path}${Platform.pathSeparator}zcash_wallet.db',
          ).exists(),
          isTrue,
        );
      }

      await writePaymentLinkRestartManifest(
        PaymentLinkRestartManifest(
          receiverAccountUuid: receiverAccountUuid,
          receiverStartingTotal: receiverStartingBalance.total,
          claims: [
            PaymentLinkRestartClaim.fromLink(firstLink),
            PaymentLinkRestartClaim.fromLink(secondLink),
          ],
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ZcashWalletApp)),
      );
      await container.read(paymentLinkClaimCoordinatorProvider).refresh();
      preparedForRestart = true;
      e2eLog('uncertain and accepted Gift Card claims prepared for restart');
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
