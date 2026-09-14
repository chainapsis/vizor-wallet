import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/payment_links/models/gift_card_usage.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/gift_card_tracking_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/rust/api/gift_card_tracking.dart' as tracking;

import 'desktop_regtest_flow.dart';
import 'payment_link_regtest_flow.dart';

const trackingCaptureKey = ValueKey('tracking_e2e_capture');

ProviderContainer trackingContainer(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ZcashWalletApp)));

Future<File> trackingManifestFile() async => File(
  '${(await getWalletSupportDirectory()).path}/gift_card_tracking_regtest.json',
);

Future<void> pumpTrackingApp(WidgetTester tester) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: trackingCaptureKey,
      child: await buildBootstrappedZcashWalletApp(),
    ),
  );
}

Future<GiftCardUsage> waitForTrackedUsage(
  WidgetTester tester,
  String address,
  GiftCardUsageStatus status, {
  bool cleaned = false,
}) async {
  final container = trackingContainer(tester);
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  GiftCardUsage? last;
  while (DateTime.now().isBefore(deadline)) {
    final records = await container
        .read(paymentLinkRecoveryStoreProvider)
        .load();
    last = records.where((r) => r.link.address == address).firstOrNull?.usage;
    if (last?.status == status && last?.cleaned == cleaned) {
      final row = find.byKey(ValueKey('payment_link_recovery_$address'));
      await pumpUntil(
        tester,
        () => tester.any(
          find.descendant(of: row, matching: find.text(last!.label)),
        ),
        description: 'created card row ${status.name}',
      );
      final accounts = await tracking.listGiftCardObservers(
        dbPath: await getGiftCardTrackingDbPath('regtest'),
      );
      if (cleaned) {
        expect(last!.accountUuid, isNull);
        expect(last.cleanupPending, isFalse);
      } else {
        expect(last!.accountUuid, isNotNull);
        expect(accounts, contains(last.accountUuid));
      }
      return last;
    }
    // Let the production screen timer drive observation; no mocked state or
    // forced refresh that could hide a missing lifecycle trigger.
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail(
    'Usage did not reach ${status.name}, cleaned=$cleaned. '
    'Last=${last?.toJson()}, tracker=${container.read(giftCardTrackingStateProvider).failed}',
  );
}

Future<void> trackingScreenshot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 200));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(trackingCaptureKey),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final root =
        '${(await getWalletSupportDirectory()).path}/gift_card_tracking_e2e_screenshots';
    await Directory(root).create(recursive: true);
    final file = File('$root/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    // The host runner copies captures out of the sandbox after each phase.
    debugPrint('[gift-card-tracking-screenshot] ${file.path}', wrapWidth: 4096);
  } finally {
    image.dispose();
  }
}

/// Caller is on Created, with the sender active. Ends on Created as sender.
Future<GiftCardUsage> consumeTrackedCard(
  WidgetTester tester,
  VizorPaymentLink link,
  String sender,
  String receiver,
  String capturePrefix,
) async {
  await switchDesktopRegtestAccount(tester, receiver);
  await waitForForegroundSyncIdle(tester);
  await openPaymentLinksFromSettings(tester);
  await claimPaymentLinkForRegtest(tester, link);
  await minePaymentLinkRegtestBlocks(1);
  await switchDesktopRegtestAccount(tester, sender);
  await openPaymentLinksFromSettings(tester);
  final detected = await waitForTrackedUsage(
    tester,
    link.address,
    GiftCardUsageStatus.spendDetected,
  );
  expect(detected.cleaned, isFalse);
  expect(detected.spendingTxids, isNotEmpty);
  await trackingScreenshot(tester, '$capturePrefix-detected');
  await minePaymentLinkRegtestBlocks(5);
  final used = await waitForTrackedUsage(
    tester,
    link.address,
    GiftCardUsageStatus.used,
    cleaned: true,
  );
  expect(used.verifiedHeight, greaterThanOrEqualTo(used.spentHeight + 5));
  expect(used.spendingTxids, detected.spendingTxids);
  final path = await getGiftCardTrackingDbPath('regtest');
  expect(await tracking.listGiftCardObservers(dbPath: path), isEmpty);
  expect(await File(path).exists(), isTrue);
  await trackingScreenshot(tester, '$capturePrefix-used');
  return used;
}

Future<void> cleanupTrackingE2e(WidgetTester tester) async {
  await ensurePaymentLinkRegtestChain();
  final path = await getGiftCardTrackingDbPath('regtest');
  if (tester.any(find.byType(ZcashWalletApp))) {
    await trackingContainer(
      tester,
    ).read(giftCardTrackingServiceProvider).quiesceAndDrain();
    await tester.pumpWidget(const SizedBox.shrink());
  }
  await cleanupDesktopRegtestWallet();
  await cleanupRegtestPaymentLinkClaimWallets();
  final directory = File(path).parent;
  if (await directory.exists()) await directory.delete(recursive: true);
  final manifest = await trackingManifestFile();
  if (await manifest.exists()) await manifest.delete();
}

Future<void> saveTrackingManifest(Map<String, Object?> data) async =>
    (await trackingManifestFile()).writeAsString(jsonEncode(data));
Future<Map<String, dynamic>> loadTrackingManifest() async =>
    jsonDecode(await (await trackingManifestFile()).readAsString())
        as Map<String, dynamic>;
