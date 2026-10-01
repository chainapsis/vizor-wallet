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
  testWidgets('removes a losing card after process restart', (tester) async {
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
    expect(before.archived, isFalse);
    expect(before.availability, PaymentLinkAvailability.claimedElsewhere);
    expect(before.claimLink, isNotNull);
    final directory = await paymentLinkClaimWalletDirectoryByName(
      manifest.claims.single.directoryName,
    );
    expect(await directory.exists(), isTrue);
    await openPaymentLinksFromSettings(tester);
    await openReceivedTab(tester);
    await expectOutcomeText(tester, 'Claimed elsewhere');
    expect(find.text('View card'), findsNothing);
    await tapPaymentLinkText(tester, 'Remove');
    // Removal is confirmed before anything is deleted.
    await tapPaymentLinkText(tester, 'Remove card');
    await pumpUntil(
      tester,
      () => !tester.any(find.text('Claimed elsewhere')),
      description: 'removed card to leave the Received list',
    );
    expect(
      await giftOutcomeContainer(
        tester,
      ).read(paymentLinkReceivedStoreProvider).load(),
      isEmpty,
    );
    expect(await directory.exists(), isFalse);
    expect(proxy.sendTransactionCount, 0);
    e2eLog('SCENARIO 3 PASS: losing card removed after process restart');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
