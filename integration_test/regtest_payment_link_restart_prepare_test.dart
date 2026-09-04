import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';

import 'support/desktop_regtest_flow.dart';
import 'support/payment_link_regtest_flow.dart';

final _firstGiftAmount = BigInt.from(10_000_000);
final _secondGiftAmount = BigInt.from(20_000_000);
final _firstFundingAmount = BigInt.from(10_010_000);
final _secondFundingAmount = BigInt.from(20_010_000);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'persists two independent Gift Card claims before process restart',
    (tester) async {
      var preparedForRestart = false;
      addTearDown(() async {
        await Clipboard.setData(const ClipboardData(text: ''));
        if (preparedForRestart) return;
        await cleanupDesktopRegtestWallet();
        await cleanupRegtestPaymentLinkClaimWallets();
        await deletePaymentLinkRestartManifest();
      });

      await cleanupDesktopRegtestWallet();
      await cleanupRegtestPaymentLinkClaimWallets();
      await deletePaymentLinkRestartManifest();

      final firstSubmissionGate = Completer<void>();
      String? gatedClaimAddress;
      e2eLog('pumping app for multi-claim restart preparation');
      await tester.pumpWidget(
        await buildBootstrappedZcashWalletApp(
          overrides: [
            paymentLinkClaimSubmitterProvider.overrideWith((ref) {
              final operations = ref.watch(paymentLinkOperationsProvider);
              return (session) async {
                if (session.link.address == gatedClaimAddress) {
                  await firstSubmissionGate.future;
                }
                return operations.claimPreparedLink(session);
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
        message: 'First restart Gift Card',
      );
      gatedClaimAddress = firstLink.address;
      expect(firstLink.amountZatoshi, _firstGiftAmount);
      final firstPendingFunding = await waitForPaymentLinkHistoryTransaction(
        tester,
        accountUuid: senderAccountUuid,
        txKind: 'sent',
        amount: _firstFundingAmount,
        pending: true,
      );

      // Confirm the first funding spend deeply enough that its change can fund
      // a second Gift Card from the same sender account.
      await minePaymentLinkRegtestBlocks(10);
      await waitForPaymentLinkHistoryTransaction(
        tester,
        accountUuid: senderAccountUuid,
        txKind: 'sent',
        amount: _firstFundingAmount,
        pending: false,
        txid: firstPendingFunding.txidHex,
      );
      await waitForForegroundSyncIdle(tester);

      final secondLink = await createPaymentLinkForRegtest(
        tester,
        amountText: '0.2',
        artworkId: 'coin',
        message: 'Second restart Gift Card',
      );
      expect(secondLink.amountZatoshi, _secondGiftAmount);
      expect(secondLink.address, isNot(firstLink.address));
      final secondPendingFunding = await waitForPaymentLinkHistoryTransaction(
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
        txid: secondPendingFunding.txidHex,
      );

      await importAdditionalDesktopRegtestWallet(tester);
      final accounts = await desktopRegtestAccounts();
      final receiverAccountUuid = accounts
          .singleWhere((account) => account.uuid != senderAccountUuid)
          .uuid;
      await waitForForegroundSyncIdle(tester);
      final receiverStartingBalance = await readPaymentLinkAccountBalance(
        receiverAccountUuid,
      );

      await openPaymentLinksFromSettings(tester);
      await claimPaymentLinkForRegtest(
        tester,
        firstLink,
        waitUntilReceiving: false,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ZcashWalletApp)),
      );
      final coordinator = container.read(paymentLinkClaimCoordinatorProvider);
      expect(coordinator.isSubmitting(firstLink.address), isTrue);

      // Opening, syncing, and claiming the second link while the first
      // submission is still owned by the app-scoped coordinator is the
      // independent-work invariant this regression guards. The gate changes
      // scheduling only; the first claim still uses the real Rust broadcast
      // after the second claim has persisted.
      await claimPaymentLinkForRegtest(tester, secondLink);
      expect(coordinator.isSubmitting(firstLink.address), isTrue);
      firstSubmissionGate.complete();
      final receivingRecords = await waitForReceivedRecords(
        tester,
        (records) => [firstLink, secondLink].every(
          (link) => records.any(
            (record) =>
                record.address == link.address &&
                record.status == PaymentLinkReceivedStatus.receiving &&
                (record.claimTxids?.isNotEmpty ?? false),
          ),
        ),
        description: 'both Gift Cards persisted as Receiving',
      );
      expect(receivingRecords, hasLength(2));

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

      await waitForPaymentLinkHistoryTransaction(
        tester,
        accountUuid: receiverAccountUuid,
        txKind: 'receiving',
        amount: _firstGiftAmount,
        pending: true,
      );
      await waitForPaymentLinkHistoryTransaction(
        tester,
        accountUuid: receiverAccountUuid,
        txKind: 'receiving',
        amount: _secondGiftAmount,
        pending: true,
      );
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

      // Leave the persisted wallet, secure store, manifest, and both temporary
      // claim DBs intact. The shell ends this Flutter process and mines while
      // Vizor is stopped before launching the resume phase.
      preparedForRestart = true;
      e2eLog('two Receiving Gift Cards prepared for process restart');
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
