import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_confetti.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_desktop_views.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
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
        illustration: const SizedBox(width: 261, height: 174),
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

  testWidgets('home and review CTAs use the Figma gift-card icon', (
    tester,
  ) async {
    await _pump(
      tester,
      PaymentLinksHomeDesktopView(
        illustration: const SizedBox(width: 261, height: 174),
        onBack: () {},
        onShowHelp: () {},
        onCreate: () {},
        onRedeem: () {},
      ),
    );

    final homeButton = find.widgetWithText(AppButton, 'Create new card');
    expect(
      find.descendant(
        of: homeButton,
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.giftCard,
        ),
      ),
      findsOneWidget,
    );

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
          .having((icon) => icon.size, 'size', 20),
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
    for (final copy in const [create, share, redeem]) {
      expect(
        tester.widget<Text>(find.text(copy)).style?.color,
        viewContext.colors.text.accent,
      );
    }
  });

  testWidgets('payment-link Back link supports desktop keyboard activation', (
    tester,
  ) async {
    var backActivations = 0;
    await _pump(
      tester,
      PaymentLinksHomeDesktopView(
        illustration: const SizedBox(width: 261, height: 174),
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
      final placeholder = tester.widget<Container>(find.byKey(key));
      final placeholderDecoration = placeholder.decoration! as BoxDecoration;
      final placeholderGradient =
          placeholderDecoration.gradient! as LinearGradient;
      expect(placeholderGradient.colors, const [
        Color(0x00858686),
        Color(0x80858686),
      ]);
    }
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
    final fade = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('payment_link_card_artwork_fade')),
    );
    final fadeDecoration = fade.decoration as BoxDecoration;
    final gradient = fadeDecoration.gradient! as LinearGradient;
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
    Transform shimmer() => tester.widget<Transform>(
      find.byKey(const ValueKey('payment_link_loading_shimmer')),
    );
    final firstX = shimmer().transform.getTranslation().x;
    await tester.pump(const Duration(milliseconds: 300));
    expect(shimmer().transform.getTranslation().x, isNot(firstX));
    await tester.pumpWidget(const SizedBox.shrink());
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
    expect(illustrationTopLeft.dx, closeTo(542, 0.6));
    expect(illustrationTopLeft.dy, closeTo(191, 0.6));

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
