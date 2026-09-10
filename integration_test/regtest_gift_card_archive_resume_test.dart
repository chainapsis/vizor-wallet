import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';

import 'support/desktop_regtest_flow.dart';
import 'support/gift_card_outcomes_flow.dart';
import 'support/payment_link_regtest_flow.dart';
import 'support/regtest_lightwalletd_proxy.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeZcashWalletRuntime);
  testWidgets(
    'restores an archived losing card after process restart',
    (tester) async {
      final proxy = RegtestLightwalletdProxy(log: e2eLog);
      await proxy.start();
      addTearDown(() async {
        await proxy.stop();
        await cleanupGiftOutcomes();
      });
      final manifest = await readPaymentLinkRestartManifest();
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await unlockDesktopRegtestWallet(tester);
      final before = await outcomeRecord(tester);
      expect(before.address, manifest.claims.single.address);
      expect(before.archived, isTrue);
      expect(before.availability, PaymentLinkAvailability.claimedElsewhere);
      expect(before.claimLink, isNotNull);
      await openPaymentLinksFromSettings(tester);
      await openReceivedTab(tester);
      expect(find.text('View card'), findsNothing);
      await tapPaymentLinkText(tester, 'Archived (1)');
      await tapPaymentLinkText(tester, 'View card');
      await expectOutcomeText(tester, 'Already claimed');
      await tapPaymentLinkText(tester, 'Restore card');
      final restored = await outcomeRecord(tester);
      expect(restored.archived, isFalse);
      expect(restored.availability, before.availability);
      expect(restored.claimLink!.toUri(), before.claimLink!.toUri());
      await tapPaymentLinkText(tester, 'View card');
      await expectOutcomeText(tester, 'Already claimed');
      expect(proxy.sendTransactionCount, 0);
      expect(
        await (await paymentLinkClaimWalletDirectoryByName(
          manifest.claims.single.directoryName,
        )).exists(),
        isTrue,
      );
      e2eLog('SCENARIO 3 PASS: archived card restored after process restart');
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
