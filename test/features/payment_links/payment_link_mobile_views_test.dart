@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/mobile/payment_link_mobile_views.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

const _feeHelpText =
    'Includes the fee to fund the gift card and the fee reserved for '
    'the recipient to claim it.';

void main() {
  setUpAll(loadFigmaCompareFonts);

  testWidgets('review defaults describe review and card creation', (
    tester,
  ) async {
    await _pumpReview(tester);

    expect(find.text('Review a Card'), findsOneWidget);
    expect(
      find.text('Attach a short encrypted memo (optional).'),
      findsOneWidget,
    );
    expect(find.text('Approve & create'), findsOneWidget);
    expect(find.text('Enter a message'), findsNothing);
  });

  testWidgets('fee help tap shows its tooltip and forwards the callback', (
    tester,
  ) async {
    var helpCalls = 0;
    await _pumpReview(tester, onFeeHelp: () => helpCalls++);

    expect(find.text(_feeHelpText), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('payment_link_mobile_fee_help')),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(helpCalls, 1);
    expect(find.text(_feeHelpText), findsOneWidget);
  });

  testWidgets('wizard and review subtitles are centered', (tester) async {
    await _pumpAmount(tester);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('payment_link_mobile_step_subtitle')),
          )
          .textAlign,
      TextAlign.center,
    );

    await _pumpReview(tester);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('payment_link_mobile_review_subtitle')),
          )
          .textAlign,
      TextAlign.center,
    );
  });

  testWidgets('review summary preserves its surface styling', (tester) async {
    await _pumpReview(tester);

    final summary = find.byKey(
      const ValueKey('payment_link_mobile_review_summary'),
    );
    expect(tester.getSize(summary).width, 361);
    expect(tester.getTopLeft(summary).dx, 16);

    final container = tester.widget<Container>(summary);
    expect(
      container.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.base,
      ),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, AppThemeData.light.colors.background.ground);
    expect(decoration.borderRadius, BorderRadius.circular(AppRadii.large));
  });

  for (final size in [const Size(393, 773), const Size(320, 568)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('review contains wrapped content at $size, scale $scale', (
        tester,
      ) async {
        var continued = 0;
        await _pumpReview(
          tester,
          size: size,
          textScale: scale,
          onFeeHelp: _noop,
          onContinue: () => continued++,
          cardAmountText: '0.001 ZEC',
          cardFeeText: '0.0002 ZEC',
          totalAmountText: '0.0012 ZEC',
        );
        _expectSummaryTextFits(tester);
        final normalHeight = tester.getSize(_summary).height;

        // More digits must grow content, without hiding either column.
        await _pumpReview(
          tester,
          size: size,
          textScale: scale,
          onFeeHelp: _noop,
          onContinue: () => continued++,
          cardAmountText: '12345678.12345678 ZEC',
          cardFeeText: '0.00020001 ZEC',
          totalAmountText: '12345678.12365679 ZEC',
        );
        _expectSummaryTextFits(tester);
        expect(tester.getSize(_summary).height, greaterThan(normalHeight));

        final button = find.byKey(
          const ValueKey('payment_link_mobile_review_continue_button'),
        );
        await tester.scrollUntilVisible(button, 150);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(button).top - tester.getRect(_summary).bottom,
          greaterThanOrEqualTo(AppSpacing.md),
        );
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        final buttonLabel = tester.renderObject<RenderParagraph>(
          find.descendant(of: button, matching: find.byType(RichText)),
        );
        _expectParagraphFits(buttonLabel);
        expect(
          tester.getSize(button).height,
          greaterThanOrEqualTo(buttonLabel.size.height),
        );
        await tester.tap(button);
        await tester.pump();
        expect(continued, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('review keeps its action at the bottom when content fits', (
    tester,
  ) async {
    await _pumpReview(tester, onFeeHelp: _noop);
    final button = find.byKey(
      const ValueKey('payment_link_mobile_review_continue_button'),
    );
    expect(tester.getRect(button).bottom, 773 - 12);
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('payment_link_mobile_review_scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, 0);
  });

  testWidgets('amount selector strip uses the lowered mobile anchor', (
    tester,
  ) async {
    await _pumpAmount(tester);

    final selector = find.byKey(const ValueKey('mobile_selector_probe'));
    expect(tester.getTopLeft(selector).dy, closeTo(452.625, 0.01));
  });

  testWidgets('redeem states match paste, checking, and invalid surfaces', (
    tester,
  ) async {
    await _pumpRedeem(tester, PaymentLinkRedeemMobileState.paste);
    final pasteZone = find.byKey(
      const ValueKey('payment_link_mobile_redeem_drop_zone'),
    );
    expect(tester.getSize(pasteZone), const Size(361, 225.625));
    expect(tester.getTopLeft(pasteZone), const Offset(16, 218));
    expect(find.text('Paste card link'), findsOneWidget);

    await _pumpRedeem(tester, PaymentLinkRedeemMobileState.loading);
    final loadingCard = find.byKey(
      const ValueKey('payment_link_mobile_loading_card'),
    );
    expect(tester.getSize(loadingCard), const Size(320, 200));
    expect(tester.getTopLeft(loadingCard), const Offset(36.5, 218));
    expect(find.text('Checking ...'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payment_link_mobile_paste_button')),
      findsNothing,
    );

    await _pumpRedeem(tester, PaymentLinkRedeemMobileState.invalid);
    expect(tester.getTopLeft(pasteZone), const Offset(16, 218));
    expect(find.text('The link doesn’t look legit.'), findsOneWidget);
    expect(find.text('Clear clipboard'), findsOneWidget);
  });

  testWidgets('received waiting copy explains the six-confirmation gate', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 773));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, navigator) =>
            AppTheme(data: AppThemeData.light, child: navigator!),
        home: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 393,
            height: 773,
            child: PaymentLinkReadyMobileView(
              state: PaymentLinkReadyMobileState.soon,
              card: SizedBox(
                width: kPaymentLinkMobileCardWidth,
                height: kPaymentLinkMobileCardHeight,
              ),
              cardTop: kPaymentLinkMobileReceivedCardTop,
              onHome: _noop,
              waitingHeading: 'Your Gift Card\nis almost ready!',
              waitingDescription: 'Your gift will be ready to claim shortly.',
              waitingStatusLabel: 'Wait 5:00 to claim',
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('Your gift will be ready to claim shortly.'),
      findsOneWidget,
    );
    expect(find.text('Wait 5:00 to claim'), findsOneWidget);
    expect(find.text('Copy link'), findsNothing);
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('payment_link_mobile_card_slot')),
          )
          .dy,
      kPaymentLinkMobileReceivedCardTop,
    );
  });

  testWidgets('invalid QR keeps both input actions visible on a small phone', (
    tester,
  ) async {
    await _pumpRedeem(
      tester,
      PaymentLinkRedeemMobileState.invalid,
      fromQrCode: true,
      size: const Size(320, 568),
    );
    expect(find.text('Paste card link'), findsOneWidget);
    expect(find.text('Scan again'), findsOneWidget);
    expect(find.text('Clear clipboard'), findsNothing);
    expect(tester.takeException(), isNull);
    final surface = tester.getRect(
      find.byKey(const ValueKey('payment_link_mobile_redeem_drop_zone')),
    );
    final scan = tester.getRect(
      find.byKey(const ValueKey('payment_link_mobile_scan_button')),
    );
    expect(surface.contains(scan.bottomRight), isTrue);
  });

  testWidgets('received card exposes Figma claim copy and action', (
    tester,
  ) async {
    var claimCalls = 0;
    var closeCalls = 0;
    await _pumpReceived(
      tester,
      onClaim: () => claimCalls++,
      onClose: () => closeCalls++,
    );

    expect(find.text('You’ve received a gift!'), findsOneWidget);
    expect(find.text('Message attached.'), findsOneWidget);
    expect(find.text('Claim the gift'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Close'));
    expect(closeCalls, 1);

    await tester.tap(
      find.byKey(const ValueKey('payment_link_mobile_claim_button')),
    );
    expect(claimCalls, 1);
  });
}

Future<void> _pumpReview(
  WidgetTester tester, {
  VoidCallback? onFeeHelp,
  VoidCallback? onContinue,
  Size size = const Size(393, 773),
  double textScale = 1,
  String cardAmountText = '4.45 ZEC',
  String cardFeeText = '0.04 ZEC',
  String totalAmountText = '4.49 ZEC',
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, navigator) => AppTheme(
        data: AppThemeData.light,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: navigator!,
        ),
      ),
      home: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: PaymentLinkReviewMobileView(
            card: const SizedBox(width: 361, height: 225.625),
            onBack: _noop,
            cardAmountText: cardAmountText,
            cardFeeText: cardFeeText,
            totalAmountText: totalAmountText,
            onContinue: onContinue ?? _noop,
            onFeeHelp: onFeeHelp,
          ),
        ),
      ),
    ),
  );
}

final _summary = find.byKey(
  const ValueKey('payment_link_mobile_review_summary'),
);

void _expectSummaryTextFits(WidgetTester tester) {
  final summaryRect = tester.getRect(_summary);
  final divider = tester.getRect(
    find.byKey(const ValueKey('payment_link_mobile_review_divider')),
  );
  final texts = find.descendant(of: _summary, matching: find.byType(RichText));
  expect(texts, findsNWidgets(6));
  for (final label in [
    'Card amount',
    'Card fee (deposit + redeem)',
    'Total amount deducted',
  ]) {
    final labelRect = tester.getRect(find.text(label));
    final valueRect = tester.getRect(
      find.byKey(ValueKey('payment_link_mobile_review_value_$label')),
    );
    expect(
      valueRect.top,
      closeTo(labelRect.top, 0.01),
      reason: '$label and its value must start on the same line',
    );
    expect(valueRect.left, greaterThanOrEqualTo(labelRect.right));
  }
  for (final element in texts.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    _expectParagraphFits(paragraph);
    final rect = paragraph.localToGlobal(Offset.zero) & paragraph.size;
    expect(summaryRect.contains(rect.topLeft), isTrue);
    expect(summaryRect.contains(rect.bottomRight), isTrue);
    final total = paragraph.text.toPlainText().contains(
      'Total amount deducted',
    );
    if (total) {
      expect(rect.top, greaterThan(divider.bottom));
    } else if (paragraph.text.toPlainText().contains('Card fee')) {
      expect(rect.bottom, lessThan(divider.top));
    }
  }
  expect(tester.takeException(), isNull);
}

void _expectParagraphFits(RenderParagraph paragraph) {
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
  )..layout(maxWidth: paragraph.size.width);
  // Presence and absence of RenderFlex errors do not catch clipped glyphs.
  expect(paragraph.size.height, greaterThanOrEqualTo(painter.height - 0.01));
  painter.dispose();
}

void _noop() {}

Future<void> _pumpAmount(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(393, 773));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      builder: (_, navigator) =>
          AppTheme(data: AppThemeData.light, child: navigator!),
      home: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 393,
          height: 773,
          child: PaymentLinkAmountMobileView(
            card: const SizedBox(width: 361, height: 225.625),
            cardSelector: const SizedBox(
              key: ValueKey('mobile_selector_probe'),
              width: 361,
              height: 60,
            ),
            onBack: _noop,
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpRedeem(
  WidgetTester tester,
  PaymentLinkRedeemMobileState state, {
  bool fromQrCode = false,
  Size size = const Size(393, 773),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      builder: (_, navigator) =>
          AppTheme(data: AppThemeData.light, child: navigator!),
      home: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 393,
          height: 773,
          child: PaymentLinkRedeemMobileView(
            state: state,
            onBack: _noop,
            onPaste: _noop,
            onScan: _noop,
            fromQrCode: fromQrCode,
            onClearClipboard: _noop,
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpReceived(
  WidgetTester tester, {
  VoidCallback? onClaim,
  VoidCallback? onClose,
}) async {
  await tester.binding.setSurfaceSize(const Size(393, 773));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      builder: (_, navigator) =>
          AppTheme(data: AppThemeData.light, child: navigator!),
      home: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 393,
          height: 773,
          child: PaymentLinkReceivedMobileView(
            card: const SizedBox(
              width: kPaymentLinkMobileCardWidth,
              height: kPaymentLinkMobileCardHeight,
            ),
            hasMessage: true,
            onClose: onClose ?? _noop,
            onClaim: onClaim,
          ),
        ),
      ),
    ),
  );
}
