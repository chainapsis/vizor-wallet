@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/mobile/payment_link_mobile_views.dart';

const _feeHelpText =
    'Includes the fee to fund the Gift Card and the fee reserved for '
    'the recipient to claim it.';

void main() {
  testWidgets('review defaults describe review and card creation', (
    tester,
  ) async {
    await _pumpReview(tester);

    expect(find.text('Review Gift Card'), findsOneWidget);
    expect(find.text('Review amount and fees.'), findsOneWidget);
    expect(find.text('Create card'), findsOneWidget);
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

  testWidgets('review summary matches the mobile Figma surface geometry', (
    tester,
  ) async {
    await _pumpReview(tester);

    final summary = find.byKey(
      const ValueKey('payment_link_mobile_review_summary'),
    );
    expect(tester.getSize(summary), const Size(361, 193));
    expect(tester.getTopLeft(summary).dx, 16);
    expect(tester.getTopLeft(summary).dy, closeTo(456.625, 0.01));

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

  testWidgets('amount selector strip uses the lowered mobile anchor', (
    tester,
  ) async {
    await _pumpAmount(tester);

    final selector = find.byKey(const ValueKey('mobile_selector_probe'));
    expect(tester.getTopLeft(selector).dy, closeTo(466.625, 0.01));
  });

  testWidgets('redeem states match paste, checking, and invalid surfaces', (
    tester,
  ) async {
    await _pumpRedeem(tester, PaymentLinkRedeemMobileState.paste);
    expect(
      find.byKey(const ValueKey('payment_link_mobile_redeem_drop_zone')),
      findsOneWidget,
    );
    expect(find.text('Paste card link'), findsOneWidget);

    await _pumpRedeem(tester, PaymentLinkRedeemMobileState.loading);
    expect(
      find.byKey(const ValueKey('payment_link_mobile_loading_card')),
      findsOneWidget,
    );
    expect(find.text('Checking ...'), findsOneWidget);

    await _pumpRedeem(tester, PaymentLinkRedeemMobileState.invalid);
    expect(find.text('The link doesn’t look legit.'), findsOneWidget);
    expect(find.text('Clear clipboard'), findsOneWidget);
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

Future<void> _pumpReview(WidgetTester tester, {VoidCallback? onFeeHelp}) async {
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
          child: PaymentLinkReviewMobileView(
            card: const SizedBox(width: 361, height: 225.625),
            onBack: _noop,
            cardAmountText: '4.45 ZEC',
            cardFeeText: '0.04 ZEC',
            totalAmountText: '4.49 ZEC',
            onContinue: _noop,
            onFeeHelp: onFeeHelp,
          ),
        ),
      ),
    ),
  );
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
  PaymentLinkRedeemMobileState state,
) async {
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
          child: PaymentLinkRedeemMobileView(
            state: state,
            onBack: _noop,
            onPaste: _noop,
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
