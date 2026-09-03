import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_modal_card.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_card_flip.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_card_selector_rail.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_confetti.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_desktop_views.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_qr_share_card.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
import 'package:zcash_wallet/widgetbook/payment_link_use_cases.dart';

void main() {
  setUpAll(_loadAppFonts);

  test('preview inventory covers all 27 desktop states', () {
    expect(PaymentLinkPreviewState.values, hasLength(27));
  });

  for (final state in PaymentLinkPreviewState.values) {
    testWidgets('renders the ${state.name} desktop fixture', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pump(tester, PaymentLinkDesktopPreview(state: state));

      expect(tester.takeException(), isNull);
      expect(find.byType(PaymentLinkDesktopPreview), findsOneWidget);
    });
  }

  testWidgets('long sync warning explains the wait and available choices', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.redeemLongSyncWarning,
      ),
    );

    expect(find.text('This Gift Card may take a while'), findsOneWidget);
    expect(find.text('Check Gift Card'), findsOneWidget);
    expect(find.text('Go back'), findsOneWidget);
    expect(find.textContaining('100000'), findsNothing);
  });

  testWidgets('home actions forward their callbacks', (tester) async {
    var helpPressed = false;
    var createPressed = false;
    var redeemPressed = false;

    await _pump(
      tester,
      PaymentLinksHomeDesktopView(
        illustration: const SizedBox(width: 243, height: 162),
        onBack: () {},
        onShowHelp: () => helpPressed = true,
        onCreate: () => createPressed = true,
        onRedeem: () => redeemPressed = true,
      ),
    );

    await tester.tap(find.text('How Gift Cards work'));
    await tester.tap(find.text('Create new card'));
    await tester.tap(find.text('Redeem a card'));

    expect(helpPressed, isTrue);
    expect(createPressed, isTrue);
    expect(redeemPressed, isTrue);
  });

  testWidgets('hover feedback keeps the keyboard focus ring fully visible', (
    tester,
  ) async {
    await _pump(
      tester,
      PaymentLinksHomeDesktopView(
        illustration: const SizedBox(width: 243, height: 162),
        onBack: () {},
        onShowHelp: () {},
        onCreate: () {},
        onRedeem: () {},
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final focusRing = find.byKey(
      const ValueKey('payment_link_text_action_focus_ring_How Gift Cards work'),
    );
    final hoverFeedback = find.byKey(
      const ValueKey('payment_link_text_action_hover_How Gift Cards work'),
    );
    final focusedBorder = find.descendant(
      of: focusRing,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).border != null,
      ),
    );
    expect(focusedBorder, findsOneWidget);
    expect(
      find.descendant(of: focusRing, matching: hoverFeedback),
      findsOneWidget,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.text('How Gift Cards work')));
    await tester.pump(const Duration(milliseconds: 120));

    expect(tester.widget<AnimatedOpacity>(hoverFeedback).opacity, lessThan(1));
    expect(focusedBorder, findsOneWidget);
    final border =
        tester.widget<DecoratedBox>(focusedBorder).decoration as BoxDecoration;
    expect(
      border.border?.top.color,
      tester.element(focusRing).colors.state.focusRing,
    );
  });

  testWidgets('gift-card editor reacts to programmatic controller updates', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await _pump(
      tester,
      PaymentLinkGiftCard(
        artwork: PaymentLinkCardArtwork.chestLava,
        amountController: controller,
        amountFocusNode: focusNode,
        semanticLabel: 'Gift card amount input',
      ),
    );
    expect(find.text('ZEC'), findsNothing);

    controller.text = '2.5';
    await tester.pump();

    expect(find.text('2.5'), findsOneWidget);
    expect(find.text('ZEC'), findsOneWidget);
  });

  testWidgets('home and review CTAs use the Figma gift-card icon', (
    tester,
  ) async {
    await _pump(
      tester,
      PaymentLinksHomeDesktopView(
        illustration: const SizedBox(width: 243, height: 162),
        onBack: () {},
        onShowHelp: () {},
        onCreate: () {},
        onRedeem: () {},
      ),
    );

    final homeButton = find.widgetWithText(AppButton, 'Create new card');
    final homeGiftIconFinder = find.descendant(
      of: homeButton,
      matching: find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.giftCard,
      ),
    );
    final homeGiftIcon = tester.widget<AppIcon>(homeGiftIconFinder);
    expect(homeGiftIcon.size, AppIconSize.medium);
    expect(tester.getSize(homeGiftIconFinder), const Size(16, 16));

    await _pump(
      tester,
      PaymentLinkReviewDesktopView(
        card: const SizedBox(
          width: PaymentLinkGiftCard.width,
          height: PaymentLinkGiftCard.height,
        ),
        onBack: () {},
        cardAmountText: '1 ZEC',
        cardFeeText: '0.0002 ZEC',
        totalAmountText: '1.0002 ZEC',
        onConfirm: () {},
      ),
    );
    final reviewButton = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Create card'),
    );
    expect(reviewButton.minWidth, 196);
    expect(reviewButton.leading, isA<Center>());
    final reviewGiftIconFinder = find.descendant(
      of: find.widgetWithText(AppButton, 'Create card'),
      matching: find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.giftCard,
      ),
    );
    expect(tester.getSize(reviewGiftIconFinder), const Size(16, 16));
  });

  testWidgets('review preview flips between the amount and message sides', (
    tester,
  ) async {
    await _pump(
      tester,
      const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.review),
    );

    expect(
      tester
          .widget<PaymentLinkCardFlip>(find.byType(PaymentLinkCardFlip))
          .showBack,
      isFalse,
    );

    await tester.tap(find.bySemanticsLabel('Reveal gift card message'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Welcome to the Shielded'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Show gift card front'));
    await tester.pumpAndSettle();
    expect(find.text('4.45'), findsOneWidget);
  });

  testWidgets('empty actions keep the Figma help-to-CTA spacing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
      tester,
      const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.empty),
    );

    final help = find.text('How Gift Cards work');
    final create = find.widgetWithText(AppButton, 'Create new card');
    final gap = tester.getTopLeft(create).dy - tester.getBottomRight(help).dy;
    expect(gap, greaterThanOrEqualTo(30));
  });

  testWidgets('review exposes the total tooltip without a divider', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
      tester,
      const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.review),
    );

    final totalHelp = find.bySemanticsLabel('About the total Gift Card amount');
    expect(totalHelp, findsOneWidget);
    final helpIcon = find.descendant(
      of: totalHelp,
      matching: find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.help,
      ),
    );
    expect(tester.getSize(helpIcon), const Size(16, 16));

    expect(
      find.byKey(const ValueKey('payment_link_review_divider')),
      findsNothing,
    );
    final feeRow = find.byKey(
      const ValueKey('payment_link_review_row_Card fee (deposit + redeem)'),
    );
    final totalRow = find.byKey(
      const ValueKey('payment_link_review_row_Total amount deducted'),
    );
    expect(
      tester.getTopLeft(totalRow).dy - tester.getBottomRight(feeRow).dy,
      AppSpacing.sm,
    );

    final create = find.widgetWithText(AppButton, 'Create card');
    expect(tester.getSize(create), const Size(196, 44));
    expect(tester.widget<AppButton>(create).size, AppButtonSize.large);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(totalHelp));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text(
        'Includes the fee to fund the Gift Card and the fee reserved for the '
        'recipient to claim it.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('how-it-works steps use the exact icon set and accent color', (
    tester,
  ) async {
    const create = 'Create description';
    const share = 'Share description';
    const redeem = 'Redeem description';
    await _pump(
      tester,
      PaymentLinkHowItWorksDesktopView(
        background: const SizedBox.expand(),
        onClose: () {},
        createDescription: create,
        shareDescription: share,
        redeemDescription: redeem,
      ),
    );

    final viewContext = tester.element(
      find.byType(PaymentLinkHowItWorksDesktopView),
    );
    final icons = tester
        .widgetList<AppIcon>(find.byType(AppIcon))
        .where(
          (icon) => const {
            AppIcons.giftCard,
            AppIcons.link,
            AppIcons.arrowDownCircle,
          }.contains(icon.name),
        )
        .toList();
    expect(icons.map((icon) => icon.name), [
      AppIcons.giftCard,
      AppIcons.link,
      AppIcons.arrowDownCircle,
    ]);
    expect(icons.map((icon) => icon.color).toSet(), {
      viewContext.colors.icon.accent,
    });
    expect(icons.map((icon) => icon.size).toSet(), {16});
    final giftCardSvg = await rootBundle.loadString(
      'assets/icons/gift_card.svg',
    );
    expect(giftCardSvg, contains('viewBox="0 0 24 24"'));
    expect(
      giftCardSvg,
      contains('transform="translate(1.5 4.125) scale(1.2)"'),
    );
    for (final icon in const [
      AppIcons.giftCard,
      AppIcons.link,
      AppIcons.arrowDownCircle,
    ]) {
      final slot = find.byKey(ValueKey('payment_link_help_icon_slot_$icon'));
      final iconFrame = find.descendant(
        of: slot,
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == icon,
        ),
      );
      expect(tester.getSize(slot).width, 32);
      expect(tester.getSize(iconFrame), const Size(16, 16));
      expect(tester.getTopLeft(iconFrame).dx, tester.getTopLeft(slot).dx + 8);
      expect(tester.getTopLeft(iconFrame).dy, tester.getTopLeft(slot).dy + 4);
    }
    for (final copy in const [create, share, redeem]) {
      expect(
        tester.widget<Text>(find.text(copy)).style?.color,
        viewContext.colors.text.accent,
      );
    }
  });

  testWidgets('how-it-works modal matches the Figma chrome and close action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
      tester,
      const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.help),
    );

    final modal = find.byType(AppModalCard);
    expect(tester.getSize(modal), const Size(312, 420));
    final innerHighlight = find.byKey(
      const ValueKey('app_modal_inner_highlight'),
    );
    expect(innerHighlight, findsOneWidget);
    expect(
      tester.widget<CustomPaint>(innerHighlight).foregroundPainter,
      isNotNull,
    );

    final closeButtonFinder = find.widgetWithText(AppButton, 'Close');
    final closeButton = tester.widget<AppButton>(closeButtonFinder);
    expect(closeButton.variant, AppButtonVariant.ghost);
    expect(closeButton.size, AppButtonSize.mediumLarge);
    expect(closeButton.expand, isTrue);
    expect(tester.getSize(closeButtonFinder), const Size(280, 36));
    final modalTopLeft = tester.getTopLeft(modal);
    expect(
      tester.getTopLeft(closeButtonFinder) - modalTopLeft,
      const Offset(16, 360),
    );

    final closeTextFinder = find.text('Close');
    final closeText = tester.widget<Text>(closeTextFinder);
    final closeTextStyle = DefaultTextStyle.of(
      tester.element(closeTextFinder),
    ).style.merge(closeText.style);
    expect(
      tester.getCenter(closeTextFinder) - modalTopLeft,
      const Offset(156, 378),
    );
    expect(closeTextStyle.fontFamily, 'Geist');
    expect(closeTextStyle.fontWeight, FontWeight.w500);
    expect(closeTextStyle.fontSize, 14);
    expect(closeTextStyle.height, 16 / 14);
    expect(closeTextStyle.letterSpacing, -0.06);
    expect(closeTextStyle.color, const Color(0xFFC2C3C3));

    expect(
      find.text(
        'Enter amount to gift, pick a design, add a message (optional) and create '
        'your Card with a single click.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'After the card is created, you will get a unique Link containing its '
        'claim secret. Send it only to the intended recipient.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('payment-link Back link supports desktop keyboard activation', (
    tester,
  ) async {
    var backActivations = 0;
    await _pump(
      tester,
      PaymentLinksHomeDesktopView(
        illustration: const SizedBox(width: 243, height: 162),
        onBack: () => backActivations += 1,
        onShowHelp: () {},
        onCreate: () {},
        onRedeem: () {},
      ),
    );

    await tester.tap(find.bySemanticsLabel('Back to Home'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);

    expect(backActivations, 4);
  });

  testWidgets('selected artwork stays visible in the design rail', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.createAmount,
      ),
    );

    expect(
      find.byKey(const ValueKey('payment_link_card_check')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('Widgetbook amount fixtures update the selected card artwork', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.createAmount,
      ),
    );

    expect(
      tester
          .widget<PaymentLinkGiftCard>(find.byType(PaymentLinkGiftCard))
          .artwork,
      PaymentLinkCardArtwork.chestLava,
    );
    await tester.tap(
      find.byKey(const ValueKey('payment_link_card_selector_chestCave')),
    );
    await tester.pump();

    expect(
      tester
          .widget<PaymentLinkGiftCard>(find.byType(PaymentLinkGiftCard))
          .artwork,
      PaymentLinkCardArtwork.chestCave,
    );
  });

  testWidgets(
    'interactive Widgetbook preview accepts amount, card, and fiat changes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        const PaymentLinkInteractiveDesktopPreview(),
        disableAnimations: false,
      );

      await tester.tap(
        find.byKey(const ValueKey('payment_link_interactive_amount_editor')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('payment_link_interactive_amount_editor')),
        '2.5',
      );
      await tester.pump();

      expect(
        tester
            .widget<EditableText>(
              find.byKey(
                const ValueKey('payment_link_interactive_amount_editor'),
              ),
            )
            .controller
            .text,
        '2.5',
      );
      expect(
        find.byKey(const ValueKey('payment_link_fiat_loading_placeholder')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('payment_link_fiat_loading_shimmer')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(
        find.byKey(const ValueKey('payment_link_card_selector_coin')),
      );
      await tester.pump();
      expect(
        tester
            .widget<PaymentLinkGiftCard>(find.byType(PaymentLinkGiftCard))
            .artwork,
        PaymentLinkCardArtwork.coin,
      );

      await tester.pump(kPaymentLinkPreviewFiatDelay);
      await tester.pump();

      expect(find.text(r'$680.00'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('payment_link_fiat_loading_placeholder')),
        findsNothing,
      );
      expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, 'Continue'))
            .onPressed,
        isNotNull,
      );

      await tester.enterText(
        find.byKey(const ValueKey('payment_link_interactive_amount_editor')),
        '',
      );
      await tester.pump();
      expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, 'Continue'))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('focused amount preview renders the real editor with ZEC', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
      tester,
      const PaymentLinkInteractiveDesktopPreview(
        initialAmount: '1',
        focusAmount: true,
      ),
      disableAnimations: false,
    );

    final editor = find.byKey(
      const ValueKey('payment_link_interactive_amount_editor'),
    );
    expect(tester.widget<EditableText>(editor).controller.text, '1');
    expect(tester.widget<EditableText>(editor).focusNode.hasFocus, isTrue);
    expect(find.text('ZEC'), findsOneWidget);
  });

  testWidgets(
    'interactive Widgetbook message preview accepts and clears text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester, const PaymentLinkInteractiveMessageDesktopPreview());

      final editor = find.byKey(
        const ValueKey('payment_link_interactive_message_editor'),
      );
      expect(editor, findsNothing);
      expect(find.text('Start typing...'), findsOneWidget);

      await tester.tap(find.text('Start typing...'));
      await tester.pump();
      expect(
        tester
            .widget<PaymentLinkCardFlip>(find.byType(PaymentLinkCardFlip))
            .showBack,
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(editor, findsOneWidget);
      expect(tester.widget<TextField>(editor).focusNode?.hasFocus, isTrue);

      await tester.enterText(editor, 'A real message');
      await tester.pump();

      expect(
        tester.widget<TextField>(editor).controller?.text,
        'A real message',
      );
      expect(find.text('114/128'), findsOneWidget);
      expect(
        tester
            .widget<AppButton>(
              find.widgetWithText(AppButton, 'Confirm & review'),
            )
            .onPressed,
        isNotNull,
      );

      await tester.enterText(editor, List.filled(25, '👨‍👩‍👧‍👦').join());
      await tester.pump();
      expect(
        find.text('This message is too large. Try using fewer complex emoji.'),
        findsOneWidget,
      );
      final messageError = find.byKey(
        const ValueKey('payment_link_message_error_text'),
      );
      final cardRect = tester.getRect(find.byType(PaymentLinkCardFlip));
      final errorRect = tester.getRect(messageError);
      final skipRect = tester.getRect(find.text('Skip message'));
      expect(errorRect.top, cardRect.bottom + AppSpacing.xs);
      expect(errorRect.bottom, lessThan(skipRect.top));
      expect(
        tester
            .widget<AppButton>(
              find.widgetWithText(AppButton, 'Confirm & review'),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.bySemanticsLabel('Delete gift card message'));
      await tester.pump();
      expect(tester.widget<TextField>(editor).controller?.text, isEmpty);
      expect(find.text('128/128'), findsOneWidget);
      expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, 'Continue'))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('redeem loading uses the Figma card placeholder', (tester) async {
    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.redeemLoading,
      ),
    );

    final card = tester.widget<Container>(
      find.byKey(const ValueKey('payment_link_loading_card')),
    );
    final decoration = card.decoration! as BoxDecoration;
    expect(
      decoration.color,
      tester
          .element(find.byKey(const ValueKey('payment_link_loading_card')))
          .colors
          .background
          .ground,
    );
    final gradientBox = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('payment_link_loading_card_gradient')),
    );
    final gradientDecoration = gradientBox.decoration as BoxDecoration;
    final gradient = gradientDecoration.gradient! as LinearGradient;
    expect(gradient.colors, const [
      Color(0x0D141818),
      Color(0x594D5252),
      Color(0x0D141818),
    ]);
    expect(decoration.borderRadius, BorderRadius.circular(AppRadii.large));
    expect(
      tester.getSize(find.byKey(const ValueKey('payment_link_loading_card'))),
      const Size(360, 225),
    );
    expect(
      find.byKey(const ValueKey('payment_link_loading_shimmer')),
      findsNothing,
    );
  });

  testWidgets('fiat loading uses the Figma pill instead of ellipsis copy', (
    tester,
  ) async {
    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.createFiatLoading,
      ),
    );

    expect(find.text(r'$1,20…'), findsNothing);
    expect(find.text(r'$'), findsOneWidget);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('payment_link_fiat_loading_placeholder')),
      ),
      const Size(48, 12),
    );
    expect(
      find.byKey(const ValueKey('payment_link_fiat_loading_shimmer')),
      findsNothing,
    );
    final fade = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('payment_link_card_artwork_fade')),
    );
    final fadeDecoration = fade.decoration as BoxDecoration;
    final gradient = fadeDecoration.gradient! as LinearGradient;
    expect(gradient.begin, Alignment.topCenter);
    expect(gradient.end, Alignment.bottomCenter);
    expect(gradient.stops, const [0.48024, 0.73518]);
    expect(gradient.colors.last, const Color(0xB3000000));
  });

  testWidgets('invalid redeem copy uses the destructive semantic color', (
    tester,
  ) async {
    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.redeemInvalid,
      ),
    );
    final context = tester.element(find.byType(PaymentLinkRedeemDesktopView));
    expect(
      tester
          .widget<Text>(find.text('The link doesn’t look legit.'))
          .style
          ?.color,
      context.colors.text.destructive,
    );
  });

  test('confetti preserves all 72 deterministic handoff pieces', () {
    expect(PaymentLinkConfetti.pieceCount, 72);
  });

  testWidgets('confetti is static under reduced motion', (tester) async {
    await _pump(tester, const SizedBox.expand(child: PaymentLinkConfetti()));

    expect(
      find.byKey(const ValueKey('payment_link_confetti_burst')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('confetti bursts once and redeem card shimmer moves', (
    tester,
  ) async {
    await _pump(
      tester,
      const SizedBox.expand(child: PaymentLinkConfetti()),
      disableAnimations: false,
    );
    expect(
      find.byKey(const ValueKey('payment_link_confetti_burst')),
      findsOneWidget,
    );
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(PaymentLinkConfetti.burstDuration);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);

    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.redeemLoading,
      ),
      disableAnimations: false,
    );
    Transform shimmer() => tester.widget<Transform>(
      find.byKey(const ValueKey('payment_link_loading_shimmer')),
    );
    final firstX = shimmer().transform.getTranslation().x;
    await tester.pump(const Duration(milliseconds: 300));
    expect(shimmer().transform.getTranslation().x, isNot(firstX));
    await tester.pumpWidget(const SizedBox.shrink());

    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.createFiatLoading,
      ),
      disableAnimations: false,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('payment_link_fiat_loading_placeholder')),
        matching: find.byKey(
          const ValueKey('payment_link_fiat_loading_shimmer'),
        ),
      ),
      findsOneWidget,
    );
    Transform fiatShimmer() => tester.widget<Transform>(
      find.byKey(const ValueKey('payment_link_fiat_loading_shimmer')),
    );
    final firstFiatX = fiatShimmer().transform.getTranslation().x;
    await tester.pump(const Duration(milliseconds: 300));
    expect(fiatShimmer().transform.getTranslation().x, isNot(firstFiatX));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('received Widgetbook card flips to its message and back', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.receivedMessage,
      ),
      disableAnimations: false,
    );

    expect(
      find.byKey(const ValueKey('payment_link_flip_front')),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Reveal gift card message'));
    await tester.pump();
    await tester.pump(PaymentLinkCardFlip.settleDuration);

    expect(
      find.byKey(const ValueKey('payment_link_flip_back')),
      findsOneWidget,
    );
    expect(find.textContaining('Welcome to the Shielded'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Show gift card artwork'));
    await tester.pump();
    await tester.pump(PaymentLinkCardFlip.settleDuration);

    expect(
      find.byKey(const ValueKey('payment_link_flip_front')),
      findsOneWidget,
    );
  });

  testWidgets('received celebration does not depend on an attached message', (
    tester,
  ) async {
    await _pump(
      tester,
      const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.received),
    );

    expect(find.byType(PaymentLinkConfetti), findsOneWidget);
    expect(find.byType(PaymentLinkCardFlip), findsNothing);
    expect(find.bySemanticsLabel('Reveal gift card message'), findsNothing);
  });

  testWidgets(
    'received message block follows the Figma icon and text metrics',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        const PaymentLinkDesktopPreview(
          state: PaymentLinkPreviewState.receivedMessage,
        ),
      );

      final block = find.byKey(
        const ValueKey('payment_link_received_message_block'),
      );
      final icon = find.byKey(
        const ValueKey('payment_link_received_message_icon'),
      );
      final title = find.text('Message attached.');
      final hint = find.text('Click on the card to reveal');

      expect(tester.getSize(block).width, 165);
      expect(tester.getSize(icon).width, moreOrLessEquals(20, epsilon: 0.001));
      expect(tester.getSize(icon).height, moreOrLessEquals(16, epsilon: 0.001));
      expect(tester.getTopLeft(title).dy - tester.getTopLeft(block).dy, 32);
      expect(tester.getTopLeft(hint).dy - tester.getBottomLeft(title).dy, 8);

      final titleText = tester.widget<Text>(title);
      final hintText = tester.widget<Text>(hint);
      expect(
        titleText.style?.fontSize,
        AppTypography.bodyMediumStrong.fontSize,
      );
      expect(titleText.style?.height, AppTypography.bodyMediumStrong.height);
      expect(hintText.style?.fontSize, AppTypography.bodyMedium.fontSize);
      expect(hintText.style?.height, AppTypography.bodyMedium.height);
    },
  );

  testWidgets('card flip keeps a visible edge at the face swap', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.receivedMessage,
      ),
      disableAnimations: false,
    );

    await tester.tap(find.bySemanticsLabel('Reveal gift card message'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 190));

    final transform = tester.widget<Transform>(
      find.byKey(const ValueKey('payment_link_flip_transform')),
    );
    expect(
      transform.transform.entry(0, 0).abs(),
      greaterThanOrEqualTo(math.sin(PaymentLinkCardFlip.edgeBand) - 1e-6),
    );
  });

  testWidgets('ready state exposes an interruptible card action', (
    tester,
  ) async {
    await _pump(
      tester,
      const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.ready),
      disableAnimations: false,
    );
    expect(find.bySemanticsLabel('Flip gift card'), findsOneWidget);
    expect(find.text('Click on the card to flip it.'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Flip gift card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.bySemanticsLabel('Flip gift card'));
    await tester.pump();
    await tester.pump(PaymentLinkCardFlip.settleDuration);

    expect(
      find.byKey(const ValueKey('payment_link_flip_front')),
      findsOneWidget,
    );
  });

  testWidgets('waiting fixtures expose the estimated wait status', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.readyWaiting,
      ),
    );
    expect(find.text('Wait 1:15 to get the link'), findsOneWidget);
    expect(find.byType(PaymentLinkConfetti), findsOneWidget);
    final initialPill = find.ancestor(
      of: find.text('Wait 1:15 to get the link'),
      matching: find.byType(CustomPaint),
    );
    expect(tester.getSize(initialPill.first).height, 36);

    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.receivedWaiting,
      ),
    );
    expect(find.text('Wait 5:00 to claim'), findsOneWidget);
    expect(find.byType(PaymentLinkConfetti), findsNothing);
    expect(find.text('Waiting for 6 confirmations.'), findsOneWidget);
  });

  testWidgets('cards list fades only where more content exists', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
      tester,
      const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.cardsList),
    );
    await tester.pump();

    final bottomFade = find.byKey(const ValueKey('app_pane_floating_bar_fade'));
    expect(tester.widget<AnimatedOpacity>(bottomFade).opacity, 1);
    expect(
      find.byKey(const ValueKey('payment_link_list_top_fade')),
      findsNothing,
    );

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('app_pane_scroll_view')),
    );
    final controller = scrollView.controller!;
    expect(controller.position.maxScrollExtent, greaterThan(0));

    controller.jumpTo(controller.position.maxScrollExtent / 2);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('payment_link_list_top_fade')),
      findsOneWidget,
    );
    expect(tester.widget<AnimatedOpacity>(bottomFade).opacity, 1);

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('payment_link_list_top_fade')),
      findsOneWidget,
    );
    expect(tester.widget<AnimatedOpacity>(bottomFade).opacity, 0);
  });

  testWidgets('created cards expose pending copy and QR actions only', (
    tester,
  ) async {
    await _pump(
      tester,
      const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.cardsList),
    );

    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Redeemed'), findsNothing);
    expect(find.bySemanticsLabel('Copy Gift Card link'), findsNWidgets(6));
    expect(find.bySemanticsLabel('Show Gift Card QR code'), findsNWidgets(6));
  });

  testWidgets('QR export keeps the selected artwork and measured geometry', (
    tester,
  ) async {
    var saved = false;
    var copied = false;
    await _pump(
      tester,
      PaymentLinkShareQrDesktopView(
        artwork: PaymentLinkCardArtwork.diamond,
        qrData: 'https://link.vizor.cash/payment-links/open#v1=test',
        onBack: () {},
        onSaveQr: () => saved = true,
        onCopyLink: () => copied = true,
      ),
    );

    expect(find.text('Share Gift Card'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('payment_link_qr_share_card'))),
      PaymentLinkQrShareCard.size,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('payment_link_qr_code'))),
      const Size(184, 184),
    );
    final brandBadge = tester.widget<Image>(
      find.byKey(const ValueKey('payment_link_share_brand_badge')),
    );
    expect(
      (brandBadge.image as AssetImage).assetName,
      PaymentLinkQrShareCard.brandBadgeAssetPath,
    );
    final artwork = tester.widget<Image>(find.byType(Image).first);
    expect(
      (artwork.image as AssetImage).assetName,
      PaymentLinkCardArtwork.diamond.assetPath,
    );

    await tester.tap(find.text('Save QR code'));
    await tester.tap(find.text('Copy link'));
    expect(saved, isTrue);
    expect(copied, isTrue);
  });

  testWidgets('received-list fixtures distinguish pending and mined claims', (
    tester,
  ) async {
    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.cardsReceiving,
      ),
    );

    var receivedRows = find.byType(PaymentLinkCardListRow);
    expect(
      find.descendant(of: receivedRows, matching: find.text('Receiving...')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: receivedRows, matching: find.text('Received')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: receivedRows,
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.loader,
        ),
      ),
      findsOneWidget,
    );

    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.cardsReceived,
      ),
    );

    receivedRows = find.byType(PaymentLinkCardListRow);
    expect(
      find.descendant(of: receivedRows, matching: find.text('Receiving...')),
      findsNothing,
    );
    expect(
      find.descendant(of: receivedRows, matching: find.text('Received')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: receivedRows,
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.loader,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('key desktop fixtures keep the measured Figma geometry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.createAmount,
      ),
    );
    final amountCard = find.byType(PaymentLinkGiftCard);
    expect(tester.getTopLeft(amountCard), const Offset(492, 251));
    expect(tester.getSize(amountCard), const Size(360, 225));
    final amountSelector = find.byType(PaymentLinkCardSelectorRail);
    expect(tester.getTopLeft(amountSelector), const Offset(474, 524));
    expect(tester.getSize(amountSelector), const Size(396, 50));
    expect(
      tester.getTopLeft(amountSelector).dy -
          tester.getBottomLeft(amountCard).dy,
      AppSpacing.lg,
    );

    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.messageFilled,
      ),
    );
    expect(
      tester.getTopLeft(find.byType(PaymentLinkGiftCard)),
      const Offset(492, 251),
    );

    await _pump(
      tester,
      const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.review),
    );
    expect(
      tester.getTopLeft(find.byType(PaymentLinkGiftCard)),
      const Offset(492, 251),
    );
    final reviewSummary = find.byKey(
      const ValueKey('payment_link_review_summary'),
    );
    expect(tester.getTopLeft(reviewSummary), const Offset(512, 492));
    expect(tester.getSize(reviewSummary), const Size(320, 136));

    await _pump(
      tester,
      const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.cardsList),
    );
    expect(tester.getTopLeft(find.text('Gift Cards')).dy, closeTo(72, 2));

    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.redeemPaste,
      ),
    );
    final redeemDropZone = find.byKey(
      const ValueKey('payment_link_redeem_drop_zone'),
    );
    expect(tester.getTopLeft(find.text('Redeem the Card')).dy, closeTo(166, 1));
    expect(tester.getTopLeft(redeemDropZone), const Offset(492, 251));
    expect(tester.getSize(redeemDropZone), const Size(360, 225));
    expect(
      tester.getCenter(
        find.byKey(const ValueKey('payment_link_redeem_paste_button')),
      ),
      tester.getCenter(redeemDropZone),
    );
    expect(
      tester
          .getTopLeft(
            find.text(
              'Copy the card link you’ve received, and paste it below.',
            ),
          )
          .dy,
      closeTo(534, 1),
    );

    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.redeemLoading,
      ),
    );
    expect(tester.getTopLeft(find.text('Checking ...')).dy, closeTo(166, 1));
    expect(
      tester.getTopLeft(
        find.byKey(const ValueKey('payment_link_loading_card')),
      ),
      const Offset(492, 251),
    );
    expect(redeemDropZone, findsNothing);
    expect(
      find.byKey(const ValueKey('payment_link_redeem_paste_button')),
      findsNothing,
    );

    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.redeemInvalid,
      ),
    );
    expect(redeemDropZone, findsOneWidget);
    expect(
      find.descendant(
        of: redeemDropZone,
        matching: find.text('The link doesn’t look legit.'),
      ),
      findsOneWidget,
    );
    expect(tester.getTopLeft(find.text('Clear clipboard')).dy, closeTo(621, 1));

    await _pump(
      tester,
      const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.empty),
    );
    final emptyIllustration = find.byWidgetPredicate(
      (widget) => widget is Image && widget.semanticLabel == 'Gift box',
    );
    final illustrationTopLeft = tester.getTopLeft(emptyIllustration);
    expect(tester.getSize(emptyIllustration), const Size(243, 162));
    expect(illustrationTopLeft.dx, closeTo(551, 0.6));
    expect(illustrationTopLeft.dy, closeTo(197, 0.6));

    await _pump(
      tester,
      const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.ready),
    );
    expect(
      tester.getTopLeft(find.text('Your Gift Card\nis ready!')).dy,
      closeTo(114.5, 1),
    );
    expect(
      tester.getTopLeft(find.byType(PaymentLinkGiftCard)).dy,
      closeTo(258.5, 1),
    );
  });

  testWidgets('default help copy describes the bearer-secret boundary', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pump(
      tester,
      PaymentLinkHowItWorksDesktopView(
        background: const SizedBox.expand(),
        onClose: () {},
      ),
    );

    expect(find.textContaining('containing its claim secret'), findsOneWidget);
    expect(find.textContaining('encrypted and safe to share'), findsNothing);
  });

  testWidgets('unwired review is visibly non-transactional by default', (
    tester,
  ) async {
    await _pump(
      tester,
      PaymentLinkReviewDesktopView(
        card: const SizedBox(
          width: PaymentLinkGiftCard.width,
          height: PaymentLinkGiftCard.height,
        ),
        onBack: () {},
        cardAmountText: '1 ZEC',
        cardFeeText: '0.0002 ZEC',
        totalAmountText: '1.0002 ZEC',
      ),
    );

    final confirm = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Create card'),
    );
    expect(confirm.onPressed, isNull);
    expect(find.textContaining('Creating fee'), findsNothing);
  });

  testWidgets('fixture dates do not leak into the reusable cards view', (
    tester,
  ) async {
    await _pump(
      tester,
      PaymentLinkCardsDesktopView(
        sections: const [],
        onBack: () {},
        onCreate: () {},
        onRedeem: () {},
      ),
    );

    expect(find.text('July 2026'), findsNothing);
  });

  testWidgets('cards navigation exposes tab roles and selected state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      PaymentLinkCardsDesktopView(
        sections: const [],
        onBack: () {},
        onCreate: () {},
        onRedeem: () {},
        onTabSelected: (_) {},
      ),
    );

    final tabs = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.role == SemanticsRole.tab,
    );
    expect(tabs, findsNWidgets(2));
    final created = tester.getSemantics(tabs.at(0)).getSemanticsData();
    final received = tester.getSemantics(tabs.at(1)).getSemanticsData();
    expect(created.role, SemanticsRole.tab);
    expect(created.flagsCollection.isSelected, Tristate.isTrue);
    expect(received.role, SemanticsRole.tab);
    expect(received.flagsCollection.isSelected, Tristate.isFalse);
    semantics.dispose();
  });

  testWidgets('received view owns reveal activation over an interactive card', (
    tester,
  ) async {
    var cardActivations = 0;
    var revealActivations = 0;
    await _pump(
      tester,
      PaymentLinkReceivedDesktopView(
        card: PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.gift,
          onTap: () => cardActivations += 1,
        ),
        onBack: () {},
        onClaim: () {},
        onRevealMessage: () => revealActivations += 1,
      ),
    );

    await tester.tap(find.bySemanticsLabel('Reveal gift card message'));
    expect(revealActivations, 1);
    expect(cardActivations, 0);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool disableAnimations = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      builder: (context, appChild) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: AppTheme(data: AppThemeData.dark, child: appChild!),
      ),
      home: Scaffold(body: child),
    ),
  );
}

Future<void> _loadAppFonts() async {
  const fonts = <String, List<String>>{
    'Geist': [
      'assets/fonts/Geist-Regular.ttf',
      'assets/fonts/Geist-Medium.ttf',
      'assets/fonts/Geist-SemiBold.ttf',
    ],
    'Young Serif': ['assets/fonts/YoungSerif-Regular.ttf'],
  };

  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key);
    for (final asset in entry.value) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }
}
