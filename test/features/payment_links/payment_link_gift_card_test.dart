import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_card_flip.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_card_selector.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_card_selector_rail.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';

void main() {
  test('card artwork exposes every exported design', () {
    expect(PaymentLinkCardArtwork.values, hasLength(11));
    expect(
      PaymentLinkCardArtwork.values.map((artwork) => artwork.assetPath).toSet(),
      hasLength(11),
    );
  });

  testWidgets('gift card renders the fixed Figma size and front states', (
    tester,
  ) async {
    await _pump(
      tester,
      const PaymentLinkGiftCard(artwork: PaymentLinkCardArtwork.chestLava),
    );

    expect(
      tester.getSize(find.byType(PaymentLinkGiftCard)),
      const Size(PaymentLinkGiftCard.width, PaymentLinkGiftCard.height),
    );
    expect(find.text('Enter amount'), findsOneWidget);
    expect(find.textContaining('Use max:'), findsNothing);

    await _pump(
      tester,
      const PaymentLinkGiftCard(
        artwork: PaymentLinkCardArtwork.chestLava,
        amountText: '4.45',
        maxAmountText: '142.23',
      ),
    );

    expect(find.text('Use max: 142.23'), findsOneWidget);
    expect(find.text('4.45'), findsOneWidget);
    expect(find.text('ZEC'), findsOneWidget);
  });

  testWidgets('gift card back renders character count and delete callback', (
    tester,
  ) async {
    var deletionCount = 0;
    await _pump(
      tester,
      PaymentLinkGiftCard(
        artwork: PaymentLinkCardArtwork.gift,
        showBack: true,
        message: 'Hi',
        onDeleteMessage: () => deletionCount += 1,
      ),
    );

    expect(find.text('Hi'), findsOneWidget);
    expect(find.text('2/128'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Delete gift card message'));
    expect(deletionCount, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(deletionCount, 3);
  });

  testWidgets('card activation keeps its nested delete action reachable', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var cardActivations = 0;
    var deletionCount = 0;
    await _pump(
      tester,
      PaymentLinkGiftCard(
        artwork: PaymentLinkCardArtwork.gift,
        showBack: true,
        message: 'Hi',
        onTap: () => cardActivations += 1,
        onDeleteMessage: () => deletionCount += 1,
      ),
    );

    expect(find.bySemanticsLabel('Delete gift card message'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Delete gift card message'));
    expect(deletionCount, 1);
    expect(cardActivations, 0);
    semantics.dispose();
  });

  testWidgets('controlled card flip turns to the message and reverses', (
    tester,
  ) async {
    var showBack = false;
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return PaymentLinkCardFlip(
            showBack: showBack,
            front: const SizedBox(
              key: ValueKey('test_payment_link_front'),
              width: PaymentLinkGiftCard.width,
              height: PaymentLinkGiftCard.height,
            ),
            back: const SizedBox(
              key: ValueKey('test_payment_link_back'),
              width: PaymentLinkGiftCard.width,
              height: PaymentLinkGiftCard.height,
            ),
          );
        },
      ),
    );

    expect(
      find.byKey(const ValueKey('payment_link_flip_front')),
      findsOneWidget,
    );
    update(() => showBack = true);
    await tester.pump();
    await tester.pump(PaymentLinkCardFlip.duration ~/ 2);
    final halfway = tester.widget<Transform>(
      find.byKey(const ValueKey('payment_link_flip_transform')),
    );
    expect(halfway.transform.storage.first.abs(), lessThan(0.99));

    update(() => showBack = false);
    await tester.pump();
    await tester.pump(PaymentLinkCardFlip.duration);
    expect(
      find.byKey(const ValueKey('payment_link_flip_front')),
      findsOneWidget,
    );
  });

  testWidgets('reduced motion swaps card faces without scheduling a turn', (
    tester,
  ) async {
    var showBack = false;
    late StateSetter update;
    await _pump(
      tester,
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return PaymentLinkCardFlip(
              showBack: showBack,
              front: const Text('Front face'),
              back: const Text('Back face'),
            );
          },
        ),
      ),
    );

    update(() => showBack = true);
    await tester.pump();
    expect(find.text('Back face'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payment_link_flip_transform')),
      findsNothing,
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('selector transitions from default to hover and selected', (
    tester,
  ) async {
    var selected = false;
    await _pump(
      tester,
      PaymentLinkCardSelector(
        artwork: PaymentLinkCardArtwork.knight,
        selected: false,
        onSelected: () => selected = true,
      ),
    );

    AnimatedOpacity artwork() => tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('payment_link_card_artwork')),
    );

    expect(artwork().opacity, 0.5);
    expect(
      find.byKey(const ValueKey('payment_link_card_focus_ring')),
      findsNothing,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.byType(PaymentLinkCardSelector)));
    await tester.pumpAndSettle();

    expect(artwork().opacity, 1);
    await tester.tap(find.byType(PaymentLinkCardSelector));
    expect(selected, isTrue);

    await _pump(
      tester,
      PaymentLinkCardSelector(
        artwork: PaymentLinkCardArtwork.knight,
        selected: true,
        onSelected: () {},
      ),
    );
    expect(
      find.byKey(const ValueKey('payment_link_card_focus_ring')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('payment_link_card_check')),
      findsOneWidget,
    );
  });

  testWidgets('custom card targets activate from desktop keyboards', (
    tester,
  ) async {
    var selectorActivations = 0;
    await _pump(
      tester,
      PaymentLinkCardSelector(
        artwork: PaymentLinkCardArtwork.knight,
        selected: false,
        onSelected: () => selectorActivations += 1,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(selectorActivations, 2);

    var cardActivations = 0;
    await _pump(
      tester,
      PaymentLinkGiftCard(
        artwork: PaymentLinkCardArtwork.gift,
        onTap: () => cardActivations += 1,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    expect(cardActivations, 1);
  });

  testWidgets('selector rail exposes all designs and reports a selection', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    PaymentLinkCardArtwork? selected;
    await _pump(
      tester,
      PaymentLinkCardSelectorRail(
        artworks: PaymentLinkCardArtwork.values,
        selected: PaymentLinkCardArtwork.crystal,
        onSelected: (artwork) => selected = artwork,
      ),
    );

    final list = tester.widget<ListView>(
      find.byKey(const ValueKey('payment_link_card_selector_scroll')),
    );
    final rail = find.byKey(const ValueKey('payment_link_card_selector_rail'));
    expect(list.semanticChildCount, PaymentLinkCardArtwork.values.length);
    expect(
      find.descendant(of: rail, matching: find.byType(RawScrollbar)),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('payment_link_card_selector_edge_fade')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('payment_link_card_selector_diamond')),
    );
    expect(selected, PaymentLinkCardArtwork.diamond);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('selector rail recenters externally selected artwork', (
    tester,
  ) async {
    var selected = PaymentLinkCardArtwork.knight;
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return PaymentLinkCardSelectorRail(
            artworks: PaymentLinkCardArtwork.values,
            selected: selected,
            onSelected: (artwork) => setState(() => selected = artwork),
          );
        },
      ),
    );

    update(() => selected = PaymentLinkCardArtwork.gift);
    await tester.pumpAndSettle();

    final rail = find.byKey(const ValueKey('payment_link_card_selector_rail'));
    final selectedCard = find.byKey(
      const ValueKey('payment_link_card_selector_gift'),
    );
    expect(selectedCard, findsOneWidget);
    expect(
      tester.getCenter(selectedCard).dx,
      moreOrLessEquals(tester.getCenter(rail).dx, epsilon: 0.5),
    );
  });

  testWidgets('selector rail accepts mouse dragging', (tester) async {
    await _pump(
      tester,
      PaymentLinkCardSelectorRail(
        artworks: PaymentLinkCardArtwork.values,
        selected: PaymentLinkCardArtwork.knight,
        onSelected: (_) {},
      ),
    );

    final list = tester.widget<ListView>(
      find.byKey(const ValueKey('payment_link_card_selector_scroll')),
    );
    final controller = list.controller!;
    expect(controller.offset, 0);

    await tester.dragFrom(
      tester.getCenter(
        find.byKey(const ValueKey('payment_link_card_selector_rail')),
      ),
      const Offset(-140, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
  });
}

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      builder: (_, appChild) =>
          AppTheme(data: AppThemeData.dark, child: appChild!),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}
