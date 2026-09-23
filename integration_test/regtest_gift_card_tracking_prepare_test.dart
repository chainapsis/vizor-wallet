import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/payment_links/models/gift_card_usage.dart';
import 'support/desktop_regtest_flow.dart';
import 'support/payment_link_regtest_flow.dart';
import 'support/gift_card_tracking_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeZcashWalletRuntime);
  testWidgets(
    'tracks first card through automatic cleanup before restart',
    (tester) async {
      var prepared = false;
      addTearDown(() async {
        await Clipboard.setData(const ClipboardData(text: ''));
        if (!prepared) await cleanupTrackingE2e(tester);
      });
      await cleanupTrackingE2e(tester);
      await pumpTrackingApp(tester);
      await importDesktopRegtestWallet(tester);
      final sender = await firstDesktopRegtestAccountUuid();
      await waitForForegroundSyncIdle(tester);
      await waitForPaymentLinkAccountBalance(
        tester,
        accountUuid: sender,
        total: BigInt.from(125000000),
        spendable: BigInt.from(125000000),
      );
      await openPaymentLinksFromSettings(tester);
      final link = await createPaymentLinkForRegtest(
        tester,
        amountText: '0.1',
        artworkId: 'coin',
        message: 'Observer before idle gap',
      );
      await openPaymentLinksFromSettings(tester);
      await waitForTrackedUsage(
        tester,
        link.address,
        GiftCardUsageStatus.unknown,
        reason: GiftCardUsageReason.awaitingConfirmation,
      );
      await trackingScreenshot(tester, 'first-awaiting-confirmation');
      await minePaymentLinkRegtestBlocks(6);
      await openPaymentLinksFromSettings(tester);
      await waitForTrackedUsage(
        tester,
        link.address,
        GiftCardUsageStatus.unused,
      );
      await trackingScreenshot(tester, 'first-unused');
      await importAdditionalDesktopRegtestWallet(tester);
      final receiver = (await desktopRegtestAccounts())
          .singleWhere((a) => a.uuid != sender)
          .uuid;
      await switchDesktopRegtestAccount(tester, sender);
      await openPaymentLinksFromSettings(tester);
      final used = await consumeTrackedCard(
        tester,
        link,
        sender,
        receiver,
        'first',
      );
      await saveTrackingManifest({
        'sender': sender,
        'receiver': receiver,
        'address': link.address,
        'observerPath': await getGiftCardTrackingDbPath('regtest'),
        'usage': used.toJson(),
        'oldTip': await paymentLinkZcashdRpc<int>('getblockcount'),
      });
      prepared = true;
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
