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
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_confetti.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_desktop_views.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_skeleton.dart';
import 'package:zcash_wallet/widgetbook/payment_link_use_cases.dart';

void main() {
  setUpAll(_loadAppFonts);

  test('preview inventory covers all 17 Figma desktop states', () {
    expect(PaymentLinkPreviewState.values, hasLength(17));
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
        onConfirm: () {},
      ),
    );
    final reviewButton = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Confirm & create'),
    );
    expect(reviewButton.minWidth, 196);
    expect(
      reviewButton.leading,
      isA<AppIcon>()
          .having((icon) => icon.name, 'name', AppIcons.giftCard)
          .having((icon) => icon.size, 'size', AppIconSize.medium),
    );
    final reviewGiftIconFinder = find.descendant(
      of: find.widgetWithText(AppButton, 'Confirm & create'),
      matching: find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.giftCard,
      ),
    );
    expect(tester.getSize(reviewGiftIconFinder), const Size(16, 16));
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
    expect(giftCardSvg, contains('translate(1 2.21826)'));
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
    expect(tester.getSize(modal), const Size(312, 441));
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
      const Offset(16, 381),
    );

    final closeTextFinder = find.text('Close');
    final closeText = tester.widget<Text>(closeTextFinder);
    final closeTextStyle = DefaultTextStyle.of(
      tester.element(closeTextFinder),
    ).style.merge(closeText.style);
    expect(
      tester.getCenter(closeTextFinder) - modalTopLeft,
      const Offset(156, 399),
    );
    expect(closeTextStyle.fontFamily, 'Geist');
    expect(closeTextStyle.fontWeight, FontWeight.w500);
    expect(closeTextStyle.fontSize, 14);
    expect(closeTextStyle.height, 16 / 14);
    expect(closeTextStyle.letterSpacing, -0.06);
    expect(closeTextStyle.color, const Color(0xFFC2C3C3));

    expect(
      find.text(
        'Enter amount to gift, pick a design,\n'
        'add a message (optional) and create\n'
        'your Card with a single click.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'After the card created, you will get a uniquely generated Link. '
        'All data in the link is encrypted and safe to share. send this '
        'Link to the recipient.',
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
            .widget<TextField>(
              find.byKey(
                const ValueKey('payment_link_interactive_amount_editor'),
              ),
            )
            .controller
            ?.text,
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
            .widget<AppButton>(find.widgetWithText(AppButton, 'Create card'))
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
            .widget<AppButton>(find.widgetWithText(AppButton, 'Enter amount'))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('redeem loading uses the Figma skeleton color hierarchy', (
    tester,
  ) async {
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
    expect(decoration.borderRadius, BorderRadius.circular(AppRadii.xLarge));
    expect(
      tester.getSize(find.byKey(const ValueKey('payment_link_loading_label'))),
      const Size(60, 12),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('payment_link_loading_amount'))),
      const Size(130, 31),
    );
    for (final key in const [
      ValueKey('payment_link_loading_label'),
      ValueKey('payment_link_loading_amount'),
    ]) {
      final placeholder = tester.widget<PaymentLinkSkeletonBar>(
        find.byKey(key),
      );
      expect(placeholder.colors, const [Color(0x00858686), Color(0x80858686)]);
    }
    expect(
      find.byKey(const ValueKey('payment_link_loading_shimmer')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('payment_link_loading_label_shimmer')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('payment_link_loading_amount_shimmer')),
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

  test('confetti preserves all 165 Figma pieces', () {
    expect(PaymentLinkConfetti.pieceCount, 165);
  });

  testWidgets('confetti is static under reduced motion', (tester) async {
    await _pump(tester, const SizedBox.expand(child: PaymentLinkConfetti()));

    for (var layer = 0; layer < 3; layer += 1) {
      final opacity = tester.widget<Opacity>(
        find.byKey(ValueKey('payment_link_confetti_layer_$layer')),
      );
      expect(opacity.opacity, 1);
    }
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('confetti enters once and redeem shimmer moves', (tester) async {
    await _pump(
      tester,
      const SizedBox.expand(child: PaymentLinkConfetti()),
      disableAnimations: false,
    );
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('payment_link_confetti_layer_0')),
          )
          .opacity,
      0,
    );
    await tester.pump(const Duration(milliseconds: 180));
    final enteringOpacity = tester
        .widget<Opacity>(
          find.byKey(const ValueKey('payment_link_confetti_layer_0')),
        )
        .opacity;
    expect(enteringOpacity, inExclusiveRange(0, 1));
    await tester.pump(PaymentLinkConfetti.entranceDuration);
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('payment_link_confetti_layer_2')),
          )
          .opacity,
      1,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);

    await _pump(
      tester,
      const PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.redeemLoading,
      ),
      disableAnimations: false,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('payment_link_loading_label')),
        matching: find.byKey(
          const ValueKey('payment_link_loading_label_shimmer'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('payment_link_loading_amount')),
        matching: find.byKey(
          const ValueKey('payment_link_loading_amount_shimmer'),
        ),
      ),
      findsOneWidget,
    );
    Transform shimmer() => tester.widget<Transform>(
      find.byKey(const ValueKey('payment_link_loading_shimmer')),
    );
    Transform labelShimmer() => tester.widget<Transform>(
      find.byKey(const ValueKey('payment_link_loading_label_shimmer')),
    );
    Transform amountShimmer() => tester.widget<Transform>(
      find.byKey(const ValueKey('payment_link_loading_amount_shimmer')),
    );
    final firstX = shimmer().transform.getTranslation().x;
    final firstLabelX = labelShimmer().transform.getTranslation().x;
    final firstAmountX = amountShimmer().transform.getTranslation().x;
    await tester.pump(const Duration(milliseconds: 300));
    expect(shimmer().transform.getTranslation().x, isNot(firstX));
    expect(labelShimmer().transform.getTranslation().x, isNot(firstLabelX));
    expect(amountShimmer().transform.getTranslation().x, isNot(firstAmountX));
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
      const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.received),
      disableAnimations: false,
    );

    expect(
      find.byKey(const ValueKey('payment_link_flip_front')),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Reveal gift card message'));
    await tester.pump();
    await tester.pump(PaymentLinkCardFlip.duration);

    expect(
      find.byKey(const ValueKey('payment_link_flip_back')),
      findsOneWidget,
    );
    expect(find.textContaining('Welcome to the Shielded'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Show gift card artwork'));
    await tester.pump();
    await tester.pump(PaymentLinkCardFlip.duration);

    expect(
      find.byKey(const ValueKey('payment_link_flip_front')),
      findsOneWidget,
    );
  });

  testWidgets('flip hint includes the Figma share-arrow decoration', (
    tester,
  ) async {
    await _pump(
      tester,
      const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.readyFlip),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('payment_link_share_arrow'))),
      const Size(48, 48),
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
    expect(
      tester.getTopLeft(find.byType(PaymentLinkGiftCard)),
      const Offset(486, 245),
    );

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
    expect(tester.getCenter(find.text('Paste card link')).dy, closeTo(404, 3));

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
      closeTo(99, 1),
    );
    expect(
      tester.getTopLeft(find.byType(PaymentLinkGiftCard)).dy,
      closeTo(235, 1),
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

    expect(
      find.textContaining('Anyone with the link can redeem the gift'),
      findsOneWidget,
    );
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
      ),
    );

    final confirm = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Confirm & create'),
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
        pendingCards: const [],
        createdCards: const [],
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
        pendingCards: const [],
        createdCards: const [],
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

  test('flip-hint view requires an activation owner', () {
    expect(
      () => PaymentLinkReadyDesktopView(
        state: PaymentLinkReadyVisualState.flipHint,
        card: const SizedBox(),
        onBack: () {},
        onCopy: () {},
      ),
      throwsAssertionError,
    );
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
