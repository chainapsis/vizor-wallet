@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_card_selector_rail.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/mobile/payment_link_mobile_views.dart';

// An iPhone SE class viewport: the shortest phone the wizard has to stay
// usable on once the software keyboard takes its share of the body.
const _compactPhone = Size(375, 667);
const _keyboardInset = 300.0;

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('keeps the amount step usable while the keyboard is open', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    var continued = 0;

    await _pumpAmountStep(
      tester,
      controller: controller,
      focusNode: focusNode,
      keyboardInset: _keyboardInset,
      onContinue: () => continued++,
    );

    expect(tester.takeException(), isNull);

    final continueButton = find.byKey(
      const ValueKey('payment_link_mobile_amount_continue_button'),
    );
    final amountEditor = find.byKey(
      const ValueKey('payment_link_amount_editor'),
    );
    expect(continueButton, findsOneWidget);
    expect(amountEditor, findsOneWidget);

    await tester.ensureVisible(amountEditor);
    await tester.pumpAndSettle();
    await tester.enterText(amountEditor, '0.1');
    await tester.pumpAndSettle();
    expect(controller.text, '0.1');

    await tester.ensureVisible(continueButton);
    await tester.pumpAndSettle();
    await tester.tap(continueButton);
    await tester.pump();

    expect(continued, 1);
    expect(
      tester
          .getRect(find.byKey(const ValueKey('payment_link_mobile_card_slot')))
          .overlaps(tester.getRect(continueButton)),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the reference offsets when the keyboard is closed', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await _pumpAmountStep(
      tester,
      controller: controller,
      focusNode: focusNode,
      keyboardInset: 0,
    );

    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .physics,
      isA<NeverScrollableScrollPhysics>(),
    );

    final frame = tester.getRect(
      find.byKey(const ValueKey('payment_link_mobile_view')),
    );
    final cardSlot = tester.getRect(
      find.byKey(const ValueKey('payment_link_mobile_card_slot')),
    );
    expect(cardSlot.top - frame.top, 193);
  });
  testWidgets('keeps the focused amount field alive when the keyboard opens', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final keyboardInset = ValueNotifier<double>(0);
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(keyboardInset.dispose);

    await tester.binding.setSurfaceSize(_compactPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ValueListenableBuilder<double>(
          valueListenable: keyboardInset,
          builder: (context, inset, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              viewInsets: EdgeInsets.only(bottom: inset),
            ),
            child: AppTheme(data: AppThemeData.dark, child: child!),
          ),
        ),
        home: Scaffold(
          body: SafeArea(
            child: _amountStep(controller: controller, focusNode: focusNode),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final amountEditor = find.byKey(
      const ValueKey('payment_link_amount_editor'),
    );
    final editorStateBeforeKeyboard = tester.state(amountEditor);
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue);

    keyboardInset.value = _keyboardInset;
    await tester.pumpAndSettle();

    expect(tester.state(amountEditor), same(editorStateBeforeKeyboard));
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('keeps the review summary clear of its CTA on a short phone', (
    tester,
  ) async {
    await _pumpMobileView(
      tester,
      PaymentLinkReviewMobileView(
        card: const SizedBox.shrink(),
        onBack: () {},
        cardAmountText: '4.45 ZEC',
        cardFeeText: '0.0001 ZEC',
        totalAmountText: '4.4501 ZEC',
        onContinue: () {},
      ),
    );

    final summary = tester.getRect(
      find.byKey(const ValueKey('payment_link_mobile_review_summary')),
    );
    final action = tester.getRect(
      find.byKey(const ValueKey('payment_link_mobile_review_continue_button')),
    );
    expect(summary.overlaps(action), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the ready status clear of its CTA on a short phone', (
    tester,
  ) async {
    await _pumpMobileView(
      tester,
      PaymentLinkReadyMobileView(
        state: PaymentLinkReadyMobileState.waiting,
        card: const SizedBox.shrink(),
        onHome: () {},
        waitingStatusLabel: 'Wait 5:00 to claim',
      ),
    );

    final status = tester.getRect(find.text('Wait 5:00 to claim'));
    final action = tester.getRect(
      find.byKey(const ValueKey('payment_link_mobile_ready_home_button')),
    );
    expect(status.overlaps(action), isFalse);
    expect(tester.takeException(), isNull);
  });
}

Widget _amountStep({
  required TextEditingController controller,
  required FocusNode focusNode,
  VoidCallback? onContinue,
}) {
  return PaymentLinkAmountMobileView(
    card: PaymentLinkGiftCard(
      artwork: PaymentLinkCardArtwork.knight,
      cardWidth: kPaymentLinkMobileCardWidth,
      cardHeight: kPaymentLinkMobileCardHeight,
      amountController: controller,
      amountFocusNode: focusNode,
      amountEditorKey: const ValueKey('payment_link_amount_editor'),
      amountInputFormatters: const <TextInputFormatter>[],
      onAmountChanged: (_) {},
      showMaxButton: true,
      semanticLabel: 'Gift card amount input',
    ),
    cardSelector: PaymentLinkCardSelectorRail(
      artworks: PaymentLinkCardArtwork.values,
      selected: PaymentLinkCardArtwork.knight,
      width: 393,
      itemWidth: 80,
      itemHeight: 60,
      artworkWidth: 76,
      artworkHeight: 56,
      onSelected: (_) {},
    ),
    onBack: () {},
    onContinue: onContinue,
  );
}

Future<void> _pumpMobileView(WidgetTester tester, Widget view) async {
  await tester.binding.setSurfaceSize(_compactPhone);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: AppTheme(data: AppThemeData.dark, child: child!),
      ),
      home: Scaffold(body: SafeArea(child: view)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpAmountStep(
  WidgetTester tester, {
  required TextEditingController controller,
  required FocusNode focusNode,
  required double keyboardInset,
  VoidCallback? onContinue,
}) async {
  await tester.binding.setSurfaceSize(_compactPhone);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
        ),
        child: AppTheme(data: AppThemeData.dark, child: child!),
      ),
      home: Scaffold(
        body: SafeArea(
          child: _amountStep(
            controller: controller,
            focusNode: focusNode,
            onContinue: onContinue,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
