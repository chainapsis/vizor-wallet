import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/payment_links/models/gift_card_usage.dart';
import 'package:zcash_wallet/src/rust/api/gift_card_tracking.dart' as tracking;
import 'support/desktop_regtest_flow.dart';
import 'support/payment_link_regtest_flow.dart';
import 'support/gift_card_tracking_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeZcashWalletRuntime);
  testWidgets(
    'reuses empty observer DB after restart and idle blocks',
    (tester) async {
      addTearDown(() async {
        await Clipboard.setData(const ClipboardData(text: ''));
        await cleanupTrackingE2e(tester);
      });
      final manifest = await loadTrackingManifest();
      final path = manifest['observerPath'] as String;
      expect(await File(path).exists(), isTrue);
      expect(await getGiftCardTrackingDbPath('regtest'), path);
      expect(await tracking.listGiftCardObservers(dbPath: path), isEmpty);
      expect(
        await paymentLinkZcashdRpc<int>('getblockcount'),
        greaterThanOrEqualTo((manifest['oldTip'] as int) + 200),
      );
      await pumpTrackingApp(tester);
      await unlockDesktopRegtestWallet(tester);
      await openPaymentLinksFromSettings(tester);
      final prior = await waitForTrackedUsage(
        tester,
        manifest['address'] as String,
        GiftCardUsageStatus.used,
        cleaned: true,
      );
      expect(prior.toJson(), manifest['usage']);
      await trackingScreenshot(tester, 'restart-used');
      final link = await createPaymentLinkForRegtest(
        tester,
        amountText: '0.1',
        artworkId: 'coin',
        message: 'Observer after idle gap',
      );
      expect(link.birthdayHeight, greaterThan(manifest['oldTip'] as int));
      expect(await getGiftCardTrackingDbPath('regtest'), path);
      await minePaymentLinkRegtestBlocks(6);
      await openPaymentLinksFromSettings(tester);
      await waitForTrackedUsage(
        tester,
        link.address,
        GiftCardUsageStatus.unused,
      );
      await trackingScreenshot(tester, 'second-unused');
      await consumeTrackedCard(
        tester,
        link,
        manifest['sender'] as String,
        manifest['receiver'] as String,
        'second',
      );
      final first = await waitForTrackedUsage(
        tester,
        manifest['address'] as String,
        GiftCardUsageStatus.used,
        cleaned: true,
      );
      expect(first.toJson(), manifest['usage']);
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
