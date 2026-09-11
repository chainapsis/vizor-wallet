import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';

import 'support/desktop_regtest_flow.dart';
import 'support/gift_card_outcomes_flow.dart';
import 'support/payment_link_regtest_flow.dart';
import 'support/regtest_lightwalletd_proxy.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeZcashWalletRuntime);
  testWidgets(
    'checks without retransmission and recovers a lost response after restart',
    (tester) async {
      final proxy = RegtestLightwalletdProxy(log: e2eLog);
      await proxy.start();
      final automaticRecovery = Completer<void>();
      addTearDown(() async {
        if (!automaticRecovery.isCompleted) automaticRecovery.complete();
        await proxy.stop();
        await cleanupGiftOutcomes();
      });
      final manifest = await readPaymentLinkRestartManifest();
      await tester.pumpWidget(
        await buildBootstrappedZcashWalletApp(
          overrides: [
            // Hold automatic retries while measuring the manual UI action. Once
            // released, the production recovery operation runs without alteration.
            paymentLinkClaimRecoveryRunnerProvider.overrideWith((ref) {
              final operations = ref.watch(paymentLinkOperationsProvider);
              return () async {
                await automaticRecovery.future;
                return operations.inspectReceivedLinkClaims(
                  await operations.loadReceivedLinkRecoveries(),
                );
              };
            }),
          ],
        ),
      );
      await unlockDesktopRegtestWallet(tester);
      final before = await outcomeRecord(tester);
      expect(before.status, PaymentLinkReceivedStatus.receiving);
      expect(before.availability, PaymentLinkAvailability.checking);
      expect(before.claimTxids, isNotEmpty);
      await openPaymentLinksFromSettings(tester);
      await openOutcome(tester);
      final sends = proxy.sendTransactionCount;
      await checkOutcome(tester);
      expect(proxy.sendTransactionCount, sends);
      expect((await outcomeRecord(tester)).claimTxids, before.claimTxids);
      expect((await outcomeRecord(tester)).isClaimInFlight, isTrue);
      expect(find.text('Hide card'), findsNothing);
      await minePaymentLinkRegtestBlocks(6);
      automaticRecovery.complete();
      final records = await waitForReceivedRecords(
        tester,
        (records) =>
            records.single.status == PaymentLinkReceivedStatus.received &&
            !records.single.needsClaimRecovery,
        description: 'lost-response claim finalized after restart',
      );
      expect(records.single.claimTxids, before.claimTxids);
      expect(records.single.claimLink, isNull);
      expect(proxy.sendTransactionCount, sends);
      await waitForPaymentLinkAccountBalance(
        tester,
        accountUuid: manifest.receiverAccountUuid,
        total: manifest.receiverStartingTotal + giftOutcomeAmount,
      );
      expect(
        await (await paymentLinkClaimWalletDirectoryByName(
          manifest.claims.single.directoryName,
        )).exists(),
        isFalse,
      );
      e2eLog(
        'SCENARIO 2 PASS: same transaction recovered; status check sent nothing',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
