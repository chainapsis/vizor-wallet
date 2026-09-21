import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/models/gift_card_usage.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_desktop_views.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/mobile/payment_link_mobile_views.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';

import 'payment_links_screen_support.dart';
import '../figma_compare/figma_compare_font_loader.dart';

class _Privacy extends PrivacyModeNotifier {
  bool get isEnabled => state;

  @override
  bool build() => true;

  @override
  Future<void> set(bool enabled) async => state = enabled;
}

void registerGiftCardPrivacyChecks({required bool mobile}) {
  if (const String.fromEnvironment('GIFT_CARD_CAPTURE_DIR').isNotEmpty) {
    setUpAll(loadFigmaCompareFonts);
  }
  final size = mobile ? const Size(390, 844) : const Size(1080, 720);
  testWidgets('gift card lists mask amounts and react to privacy changes', (
    tester,
  ) async {
    final privacy = _Privacy();
    final boundary = GlobalKey();
    final records = [
      for (final entry in [
        (incomingLink, GiftCardUsageStatus.unknown),
        (secondIncomingLink, GiftCardUsageStatus.unused),
        (otherAccountLink, GiftCardUsageStatus.used),
      ])
        PaymentLinkRecoveryRecord(
          link: entry.$1,
          sourceAccountUuid: 'account-1',
          claimFeeReserveZatoshi: BigInt.from(10000),
          state: PaymentLinkRecoveryState.funded,
          updatedAt: DateTime.utc(2026, 9, 17),
          fundingTxids: 'funding-${entry.$1.address}',
          usage: GiftCardUsage(status: entry.$2),
        ),
    ];
    await pumpPaymentLinksScreen(
      tester,
      logicalSize: size,
      captureBoundaryKey: boundary,
      privacyNotifier: privacy,
      operations: FakePaymentLinkOperations(
        records: records,
        receivedRecords: [PaymentLinkReceivedRecord.fromLink(incomingLink)],
      ),
      giftCardUsages: {for (final r in records) r.link.address: r.usage},
    );
    await tester.pumpAndSettle();
    final sections = mobile
        ? tester
              .widget<PaymentLinkCardsMobileView>(
                find.byType(PaymentLinkCardsMobileView),
              )
              .sections
        : tester
              .widget<PaymentLinkCardsDesktopView>(
                find.byType(PaymentLinkCardsDesktopView),
              )
              .sections;
    expect(sections.map((s) => s.label), ['Pending', 'Unused', 'Used']);
    expect(sections.map((s) => s.cards.length), [1, 1, 1]);
    expect(find.text('Unused'), findsOneWidget);
    expect(find.text('Used'), findsOneWidget);
    expect(find.text('Unverified'), findsOneWidget);
    Iterable<String> amounts() => mobile
        ? tester
              .widgetList<PaymentLinkCardListMobileRow>(
                find.byType(PaymentLinkCardListMobileRow),
              )
              .map((r) => r.amountText)
        : tester
              .widgetList<PaymentLinkCardListRow>(
                find.byType(PaymentLinkCardListRow),
              )
              .map((r) => r.amountText);
    expect(amounts(), everyElement('****** ZEC'));
    expect(find.bySemanticsLabel('Turn off privacy mode'), findsOneWidget);
    const captureDir = String.fromEnvironment('GIFT_CARD_CAPTURE_DIR');
    if (captureDir.isNotEmpty) {
      await tester.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          await precacheImage((element.widget as Image).image, element);
        }
      });
      await tester.pumpAndSettle();
      final file = File(
        '$captureDir/${mobile ? 'mobile' : 'desktop'}-private-list.png',
      );
      file.parent.createSync(recursive: true);
      await expectLater(find.byKey(boundary), matchesGoldenFile(file.uri));
    }
    await tester.tap(find.byKey(const ValueKey('payment_link_privacy_button')));
    await tester.pumpAndSettle();
    expect(amounts(), everyElement(isNot(contains('*'))));
    expect(privacy.isEnabled, isFalse);
    expect(find.bySemanticsLabel('Turn on privacy mode'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('payment_link_privacy_button')));
    await tester.tap(find.text('Received').first);
    await tester.pumpAndSettle();
    expect(amounts(), ['****** ZEC']);
    await tester.tap(find.byKey(const ValueKey('payment_link_privacy_button')));
    await tester.pumpAndSettle();
    expect(amounts(), everyElement(isNot(contains('*'))));
    expect(privacy.isEnabled, isFalse);
    expect(find.bySemanticsLabel('Turn on privacy mode'), findsOneWidget);
  });

  testWidgets('privacy keeps gift creation and claim amounts visible', (
    tester,
  ) async {
    final claimLink = VizorPaymentLink(
      network: incomingLink.network,
      label: incomingLink.label,
      address: incomingLink.address,
      amountZatoshi: incomingLink.amountZatoshi,
      mnemonic: incomingLink.mnemonic,
      birthdayHeight: incomingLink.birthdayHeight,
      createdAt: incomingLink.createdAt,
      presentation: const PaymentLinkPresentation(
        artworkId: 'ruby',
        fiatSnapshot: PaymentLinkFiatSnapshot(amount: 445),
      ),
    );
    await pumpPaymentLinksScreen(
      tester,
      logicalSize: size,
      pricingEnabled: true,
      privacyNotifier: _Privacy(),
      clipboard: FakePaymentLinkClipboard(text: claimLink.toUri().toString()),
    );
    await tester.tap(
      mobile
          ? find.byKey(const ValueKey('payment_links_mobile_create_button'))
          : find.text('Create new card'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment_link_amount_editor')),
      '0.1',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey(
          mobile
              ? 'payment_link_mobile_amount_continue_button'
              : 'payment_link_amount_continue_button',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      mobile
          ? find.byKey(
              const ValueKey('payment_link_mobile_message_continue_button'),
            )
          : find.text('Skip message'),
    );
    await tester.pumpAndSettle();
    expect(find.text('0.1'), findsOneWidget);
    await tester.tap(
      mobile
          ? find.byKey(
              const ValueKey('payment_link_mobile_review_continue_button'),
            )
          : find.text('Create card'),
    );
    await tester.pumpAndSettle();
    expect(find.text('0.1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    await tester.tap(find.text(mobile ? 'Go home' : 'Return home'));
    await tester.pumpAndSettle();
    await tester.tap(
      mobile
          ? find.byKey(const ValueKey('payment_links_mobile_redeem_button'))
          : find.text('Redeem a card'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();
    final card = tester.widget<PaymentLinkGiftCard>(
      find.byType(PaymentLinkGiftCard).first,
    );
    expect(card.amountText, '4.45');
    expect(find.text(r'$445.00'), findsOneWidget);
    expect(card.amountText, isNot(contains('*')));
  });
}
