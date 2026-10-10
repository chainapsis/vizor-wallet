import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_card_selector_rail.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';

import '../fakes/fake_sync_notifier.dart';
import '../figma_compare/figma_compare_font_loader.dart';
import 'payment_links_screen_support.dart';

void registerGiftCardAmountCurrencyChecks({required bool mobile}) {
  setUpAll(loadFigmaCompareFonts);
  const output = String.fromEnvironment('GIFT_CURRENCY_CAPTURE_DIR');
  final editor = find.byKey(const ValueKey('payment_link_amount_editor'));
  final usd = find.byKey(const ValueKey('payment_link_amount_currency_usd'));
  final zec = find.byKey(const ValueKey('payment_link_amount_currency_zec'));
  final usdLoading = find.byKey(
    const ValueKey('payment_link_amount_usd_price_loading'),
  );
  final continueButton = find.byKey(
    ValueKey(
      mobile
          ? 'payment_link_mobile_amount_continue_button'
          : 'payment_link_amount_continue_button',
    ),
  );
  final confirmButton = mobile
      ? find.byKey(const ValueKey('payment_link_mobile_review_continue_button'))
      : find.text('Create card');

  String input(WidgetTester tester) =>
      tester.widget<EditableText>(editor).controller.text;
  bool canContinue(WidgetTester tester) =>
      tester.widget<AppButton>(continueButton).onPressed != null;

  Future<void> captureScreen(
    WidgetTester tester,
    GlobalKey? capture,
    String name,
  ) async {
    if (capture == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(capture),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$output/${mobile ? 'mobile' : 'desktop'}-$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> start(
    WidgetTester tester, {
    _PriceNotifier? price,
    _RecordingOperations? operations,
    GlobalKey? capture,
    SwitchablePaymentLinkAccountNotifier? accounts,
    FakeSyncNotifier? sync,
  }) async {
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      marketDataNotifier: price ?? _PriceNotifier(),
      logicalSize: mobile ? const Size(393, 852) : const Size(1080, 720),
      captureBoundaryKey: capture,
      accountNotifier: accounts,
      bootstrap: accounts == null ? null : twoAccountBootstrap,
      syncNotifier: sync,
    );
    await tester.tap(
      mobile
          ? find.byKey(const ValueKey('payment_links_mobile_create_button'))
          : find.text('Create new card'),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String text) async {
    await tester.enterText(editor, text);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  Future<void> review(WidgetTester tester) async {
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    await tester.tap(
      mobile
          ? find.byKey(
              const ValueKey('payment_link_mobile_message_continue_button'),
            )
          : find.text('Skip message'),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('USD is keyboard-accessible before typing and accepts cents', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await start(tester);
    expect(
      tester.getSemantics(usd).flagsCollection.isEnabled,
      ui.Tristate.isTrue,
    );
    expect(tester.getSize(usd).height, mobile ? 44 : 32);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('payment_link_amount_currency_visual')),
          )
          .height,
      32,
    );
    expect(canContinue(tester), isFalse);
    Focus.of(
      tester.element(find.descendant(of: usd, matching: find.text('USD'))),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Enter dollars'), findsOneWidget);
    await enter(tester, ',50');
    expect(input(tester), '0.50');
    await enter(tester, ',501');
    expect(input(tester), '0.50');
    expect(find.text('≈ 0.005 ZEC'), findsOneWidget);
    expect(canContinue(tester), isTrue);
    expect(
      find.text('The card holds ZEC. Its dollar value can change.'),
      findsNothing,
    );
    semantics.dispose();
  });

  testWidgets('unit switches preserve all zatoshi and the active editor', (
    tester,
  ) async {
    final operations = _RecordingOperations();
    await start(tester, operations: operations);
    await enter(tester, '0.12345678');
    final originalEditor = tester.element(editor);
    final focus = tester.widget<EditableText>(editor).focusNode;
    expect(focus.hasFocus, isTrue);
    await tester.tap(usd);
    await tester.pumpAndSettle();
    expect(input(tester), '12.35');
    expect(find.text('≈ 0.12345678 ZEC'), findsOneWidget);
    expect(tester.element(editor), same(originalEditor));
    expect(focus.hasFocus, isTrue);
    await tester.tap(zec);
    await tester.pumpAndSettle();
    expect(input(tester), '0.12345678');
    expect(operations.quotedAmounts, [BigInt.from(12345678)]);
    expect(canContinue(tester), isTrue);
  });

  testWidgets('rapid unit switches continue motion and typing does not fade', (
    tester,
  ) async {
    await start(tester);
    await enter(tester, '0.2');
    final indicator = find.byKey(
      const ValueKey('payment_link_amount_currency_indicator'),
    );
    final fade = find.byKey(
      const ValueKey('payment_link_amount_conversion_fade'),
    );
    double opacity() => tester.widget<FadeTransition>(fade).opacity.value;
    final initialLeft = tester.getTopLeft(indicator).dx;
    final originalEditor = tester.element(editor);
    final focus = tester.widget<EditableText>(editor).focusNode;
    await tester.tap(usd);
    await tester.pump();
    expect(input(tester), '20.00');
    expect(opacity(), closeTo(0.55, 0.001));
    await tester.pump(const Duration(milliseconds: 60));
    final movingLeft = tester.getTopLeft(indicator).dx;
    final movingOpacity = opacity();
    expect(movingLeft, inExclusiveRange(initialLeft, initialLeft + 60));
    await tester.tap(zec);
    await tester.pump();
    expect(tester.getTopLeft(indicator).dx, closeTo(movingLeft, 0.001));
    expect(opacity(), closeTo(movingOpacity, 0.001));
    expect(input(tester), '0.2');
    expect(tester.element(editor), same(originalEditor));
    expect(focus.hasFocus, isTrue);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(indicator).dx, initialLeft);
    expect(opacity(), 1);
    await enter(tester, '0.3');
    expect(opacity(), 1);
  });

  testWidgets('reduced motion settles an in-progress unit switch immediately', (
    tester,
  ) async {
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await start(tester);
    await enter(tester, '0.2');
    final indicator = find.byKey(
      const ValueKey('payment_link_amount_currency_indicator'),
    );
    final fade = find.byKey(
      const ValueKey('payment_link_amount_conversion_fade'),
    );
    final initialLeft = tester.getTopLeft(indicator).dx;
    await tester.tap(usd);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pump();
    expect(tester.getTopLeft(indicator).dx, initialLeft + 60);
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    await tester.tap(zec);
    await tester.pump();
    expect(tester.getTopLeft(indicator).dx, initialLeft);
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    expect(input(tester), '0.2');
  });

  testWidgets('USD cannot hide a positive amount that rounds to zero cents', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await start(tester);
    await enter(tester, '0.00000001');
    expect(
      tester.getSemantics(usd).flagsCollection.isEnabled,
      ui.Tristate.isFalse,
    );
    expect(input(tester), '0.00000001');
    expect(canContinue(tester), isTrue);
    await enter(tester, '1');
    expect(
      tester.getSemantics(usd).flagsCollection.isEnabled,
      ui.Tristate.isTrue,
    );
    semantics.dispose();
  });

  testWidgets('USD input reviews and funds the canonical ZEC amount', (
    tester,
  ) async {
    final capture = output.isEmpty ? null : GlobalKey();
    final operations = _RecordingOperations();
    await start(tester, operations: operations, capture: capture);
    if (capture != null) {
      tester
          .widget<PaymentLinkCardSelectorRail>(
            find.byType(PaymentLinkCardSelectorRail),
          )
          .onSelected(PaymentLinkCardArtwork.chestLava);
      await tester.pumpAndSettle();
    }
    await tester.tap(usd);
    await tester.pumpAndSettle();
    await enter(tester, '75');
    expect(operations.quotedAmounts.last, BigInt.from(75000000));
    expect(find.text('≈ 0.75 ZEC'), findsOneWidget);
    final card = tester.widget<PaymentLinkGiftCard>(
      find.byType(PaymentLinkGiftCard),
    );
    expect(card.currencySymbol, 'USD');
    await captureScreen(tester, capture, 'usd-amount');
    await review(tester);
    final reviewCard = tester.widget<PaymentLinkGiftCard>(
      find.byType(PaymentLinkGiftCard),
    );
    expect(reviewCard.amountText, '0.75');
    expect(reviewCard.currencySymbol, 'ZEC');
    expect(find.text('0.75 ZEC'), findsOneWidget);
    expect(usd, findsNothing);
    await captureScreen(tester, capture, 'usd-review');
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();
    expect(operations.createdAmounts, [BigInt.from(75000000)]);
    expect(operations.createdFiatSnapshots.single?.amount, 75);
    expect(tester.takeException(), isNull);
  });

  testWidgets('USD Max preserves the exact ZEC maximum across price changes', (
    tester,
  ) async {
    final price = _PriceNotifier();
    final operations = _RecordingOperations();
    await start(tester, price: price, operations: operations);
    await tester.tap(usd);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Use max:'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(input(tester), '14222.98');
    expect(find.text('≈ 142.2298 ZEC'), findsOneWidget);
    expect(operations.quotedAmounts, [BigInt.from(14222980000)]);
    price.setPrice(250);
    await tester.pumpAndSettle();
    expect(input(tester), '35557.45');
    expect(find.text('≈ 142.2298 ZEC'), findsOneWidget);
    expect(operations.quotedAmounts, [BigInt.from(14222980000)]);
    await enter(tester, '35558');
    expect(find.text('Above your maximum ZEC'), findsOneWidget);
    expect(canContinue(tester), isFalse);
    await enter(tester, '75');
    price.setPrice(200);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(input(tester), '75');
    expect(find.text('≈ 0.375 ZEC'), findsOneWidget);
    expect(operations.quotedAmounts.last, BigInt.from(37500000));
  });

  testWidgets('USD price changes invalidate an older in-flight funding quote', (
    tester,
  ) async {
    final price = _PriceNotifier();
    final oldQuote = Completer<void>();
    final operations = _RecordingOperations()..quoteGate = oldQuote;
    await start(tester, price: price, operations: operations);
    await tester.tap(usd);
    await tester.pumpAndSettle();
    await enter(tester, '50');
    expect(canContinue(tester), isFalse);
    expect(operations.quotedAmounts, [BigInt.from(50000000)]);
    operations.quoteGate = null;
    price.setPrice(200);
    await tester.pump();
    expect(canContinue(tester), isFalse);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(input(tester), '50');
    expect(find.text('≈ 0.25 ZEC'), findsOneWidget);
    expect(canContinue(tester), isTrue);
    oldQuote.complete();
    await tester.pumpAndSettle();
    await review(tester);
    expect(find.text('0.25 ZEC'), findsOneWidget);
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();
    expect(operations.createdAmounts, [BigInt.from(25000000)]);
  });

  testWidgets('a cached display price cannot enable USD entry', (tester) async {
    final semantics = tester.ensureSemantics();
    final price = _PriceNotifier(livePrice: null);
    await start(tester, price: price);
    expect(
      tester.getSemantics(usd).flagsCollection.isEnabled,
      ui.Tristate.isFalse,
    );
    await enter(tester, '2');
    expect(canContinue(tester), isTrue);
    price.setPrice(100);
    await tester.pumpAndSettle();
    await tester.tap(usd);
    await tester.pumpAndSettle();
    expect(input(tester), '200.00');
    price.setPrice(null);
    await tester.pumpAndSettle();
    expect(input(tester), '200.00');
    expect(canContinue(tester), isFalse);
    expect(
      find.text('USD price unavailable. Enter an amount in ZEC.'),
      findsNothing,
    );
    price.setPrice(100);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('≈ 2 ZEC'), findsOneWidget);
    expect(canContinue(tester), isTrue);
    semantics.dispose();
  });

  testWidgets('USD loading and failure keep ZEC usable before price recovery', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final price = _PriceNotifier(
      livePrice: null,
      displayPrice: null,
      loading: true,
    );
    final capture = output.isEmpty ? null : GlobalKey();
    await start(tester, price: price, capture: capture);
    if (capture != null) {
      tester
          .widget<PaymentLinkCardSelectorRail>(
            find.byType(PaymentLinkCardSelectorRail),
          )
          .onSelected(PaymentLinkCardArtwork.chestLava);
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(usdLoading, findsNothing);
    expect(find.text('Fetching USD price…'), findsNothing);
    expect(find.text('Fiat unavailable'), findsNothing);
    expect(tester.getSemantics(usd).label, contains('Fetching USD price'));
    expect(
      tester.getSemantics(usd).flagsCollection.isEnabled,
      ui.Tristate.isFalse,
    );
    expect(tester.getSize(usd).height, mobile ? 44 : 32);
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(of: usd, matching: find.byType(Tooltip)),
          )
          .message,
      'Fetching USD price…',
    );
    await tester.tap(usd);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Fetching USD price…'), findsOneWidget);
    expect(find.text('Enter dollars'), findsNothing);
    expect(input(tester), isEmpty);
    await tester.tap(zec);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Fetching USD price…'), findsNothing);
    await tester.enterText(editor, '2');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(canContinue(tester), isTrue);
    price.setPrice(null);
    await tester.pumpAndSettle();
    expect(usdLoading, findsNothing);
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(of: usd, matching: find.byType(Tooltip)),
          )
          .message,
      'USD price unavailable',
    );
    expect(input(tester), '2');
    expect(canContinue(tester), isTrue);
    expect(find.text('USD price unavailable'), findsNothing);
    expect(find.text('Fiat unavailable'), findsNothing);
    await captureScreen(tester, capture, 'price-unavailable');
    await tester.tap(usd);
    await tester.pumpAndSettle();
    expect(find.text('USD price unavailable'), findsOneWidget);
    expect(input(tester), '2');
    expect(find.text('Enter dollars'), findsNothing);
    await captureScreen(tester, capture, 'price-unavailable-tooltip');
    price.setPrice(100);
    await tester.pumpAndSettle();
    expect(find.text('USD price unavailable'), findsNothing);
    expect(
      tester.getSemantics(usd).flagsCollection.isEnabled,
      ui.Tristate.isTrue,
    );
    await tester.tap(usd);
    await tester.pumpAndSettle();
    expect(input(tester), '200.00');
    expect(canContinue(tester), isTrue);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  if (!mobile) {
    testWidgets('disabled USD explains itself on hover and mouse click', (
      tester,
    ) async {
      final price = _PriceNotifier(livePrice: null, displayPrice: null);
      await start(tester, price: price);
      await enter(tester, '2');
      expect(find.text('USD price unavailable'), findsNothing);
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(usd));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('USD price unavailable'), findsOneWidget);
      expect(input(tester), '2');
      expect(find.text('Enter dollars'), findsNothing);
      expect(canContinue(tester), isTrue);

      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(find.text('USD price unavailable'), findsNothing);
      // Click before the hover delay has elapsed.
      await mouse.moveTo(tester.getCenter(usd));
      await mouse.down(tester.getCenter(usd));
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('USD price unavailable'), findsOneWidget);
      expect(input(tester), '2');
      expect(find.text('Enter dollars'), findsNothing);
      expect(canContinue(tester), isTrue);
      await mouse.removePointer();
      price.setPrice(100);
      await tester.pumpAndSettle();
      expect(find.text('USD price unavailable'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a refresh keeps USD usable with the previous live price', (
    tester,
  ) async {
    final price = _PriceNotifier();
    final operations = _RecordingOperations();
    await start(tester, price: price, operations: operations);
    await tester.tap(usd);
    await tester.pumpAndSettle();
    await enter(tester, '75');
    price.setLoading(true);
    await tester.pump();
    expect(usdLoading, findsNothing);
    expect(input(tester), '75');
    expect(find.text('≈ 0.75 ZEC'), findsOneWidget);
    expect(canContinue(tester), isTrue);
    // A failed refresh leaves its previous usable price intact.
    price.setLoading(false);
    await tester.pumpAndSettle();
    expect(operations.quotedAmounts, [BigInt.from(75000000)]);
    expect(canContinue(tester), isTrue);
    price.setLoading(true);
    await tester.pump();
    price.setPrice(200);
    await tester.pump();
    expect(input(tester), '75');
    expect(canContinue(tester), isFalse);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('≈ 0.375 ZEC'), findsOneWidget);
    expect(operations.quotedAmounts.last, BigInt.from(37500000));
    expect(canContinue(tester), isTrue);
  });

  testWidgets(
    'USD entry survives expiry, loading, failure and price recovery',
    (tester) async {
      final price = _PriceNotifier();
      final operations = _RecordingOperations();
      await start(tester, price: price, operations: operations);
      await tester.tap(usd);
      await tester.pumpAndSettle();
      await enter(tester, '50');
      price.expirePrice();
      await tester.pumpAndSettle();
      expect(input(tester), '50');
      expect(canContinue(tester), isFalse);
      price.setLoading(true);
      await tester.pump();
      expect(usdLoading, findsNothing);
      expect(find.text('Fetching USD price…'), findsNothing);
      expect(input(tester), '50');
      expect(canContinue(tester), isFalse);
      price.setPrice(null);
      await tester.pumpAndSettle();
      expect(usdLoading, findsNothing);
      expect(
        find.text('USD price unavailable. Enter an amount in ZEC.'),
        findsNothing,
      );
      expect(input(tester), '50');
      expect(canContinue(tester), isFalse);
      price.setPrice(200);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(input(tester), '50');
      expect(find.text('≈ 0.25 ZEC'), findsOneWidget);
      expect(canContinue(tester), isTrue);
      expect(operations.quotedAmounts, [
        BigInt.from(50000000),
        BigInt.from(25000000),
      ]);
    },
  );

  for (final returnFromReview in [false, true]) {
    testWidgets('price expiry preserves exact ZEC when switching units from '
        '${returnFromReview ? 'review' : 'amount'}', (tester) async {
      final price = _PriceNotifier();
      final operations = _RecordingOperations();
      final capture = output.isEmpty || returnFromReview ? null : GlobalKey();
      await start(
        tester,
        price: price,
        operations: operations,
        capture: capture,
      );
      await enter(tester, '0.12345678');
      await tester.tap(usd);
      await tester.pumpAndSettle();
      expect(input(tester), '12.35');
      if (returnFromReview) await review(tester);

      price.expirePrice();
      await tester.pumpAndSettle();
      if (returnFromReview) {
        if (mobile) {
          await tester.tap(find.bySemanticsLabel('Back'));
          await tester.pumpAndSettle();
          await tester.tap(find.bySemanticsLabel('Back'));
        } else {
          await tester.tap(find.text('Create').first);
        }
        await tester.pumpAndSettle();
      }
      expect(input(tester), '12.35');
      expect(find.text('≈ 0.12345678 ZEC'), findsOneWidget);
      expect(canContinue(tester), isFalse);
      await captureScreen(tester, capture, 'price-expired-preserved');

      await tester.tap(zec);
      await tester.pumpAndSettle();
      expect(input(tester), '0.12345678');
      expect(canContinue(tester), isTrue);
      expect(operations.quotedAmounts, [BigInt.from(12345678)]);
      await captureScreen(tester, capture, 'price-expired-zec-recovery');
      await review(tester);
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();
      expect(operations.createdAmounts, [BigInt.from(12345678)]);
    });
  }

  testWidgets('editing USD without a live price invalidates preserved ZEC', (
    tester,
  ) async {
    final price = _PriceNotifier();
    final operations = _RecordingOperations();
    await start(tester, price: price, operations: operations);
    await tester.tap(usd);
    await tester.pumpAndSettle();
    await enter(tester, '50');
    price.expirePrice();
    await tester.pumpAndSettle();
    expect(find.text('≈ 0.5 ZEC'), findsOneWidget);

    await enter(tester, '75');
    expect(find.text('≈ 0.5 ZEC'), findsNothing);
    expect(canContinue(tester), isFalse);
    expect(operations.quotedAmounts, [BigInt.from(50000000)]);
    price.setPrice(200);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(input(tester), '75');
    expect(find.text('≈ 0.375 ZEC'), findsOneWidget);
    expect(canContinue(tester), isTrue);
    expect(operations.quotedAmounts.last, BigInt.from(37500000));

    price.expirePrice();
    await tester.pumpAndSettle();
    await enter(tester, '100');
    await tester.tap(zec);
    await tester.pumpAndSettle();
    expect(input(tester), isEmpty);
    expect(canContinue(tester), isFalse);
    expect(operations.createdAmounts, isEmpty);
  });

  testWidgets(
    'review freezes ZEC while returning to USD resumes current pricing',
    (tester) async {
      final price = _PriceNotifier();
      await start(tester, price: price);
      await tester.tap(usd);
      await tester.pumpAndSettle();
      await enter(tester, '50');
      await review(tester);
      price.setPrice(200);
      await tester.pumpAndSettle();
      expect(find.text('0.5 ZEC'), findsOneWidget);
      if (mobile) {
        await tester.tap(find.bySemanticsLabel('Back'));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Back'));
      } else {
        await tester.tap(find.text('Create').first);
      }
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(input(tester), '50');
      expect(find.text('≈ 0.25 ZEC'), findsOneWidget);
      expect(canContinue(tester), isTrue);
    },
  );

  testWidgets('changing accounts resumes USD entry at the latest price', (
    tester,
  ) async {
    SyncState accountBalance(String uuid) => SyncState(
      accountUuid: uuid,
      hasAccountScopedData: true,
      isSyncComplete: true,
      percentage: 1,
      displayTargetPercentage: 1,
      spendableBalance: BigInt.from(14223000000),
      displaySpendableBalance: BigInt.from(14223000000),
    );
    final accounts = SwitchablePaymentLinkAccountNotifier();
    final sync = FakeSyncNotifier(accountBalance('account-1'));
    final price = _PriceNotifier();
    final operations = _RecordingOperations();
    await start(
      tester,
      price: price,
      operations: operations,
      accounts: accounts,
      sync: sync,
    );
    await tester.tap(usd);
    await tester.pumpAndSettle();
    await enter(tester, '50');
    await review(tester);
    price.setPrice(200);
    await tester.pumpAndSettle();
    accounts.setActiveAccount('account-2');
    await tester.pump();
    sync.emit(accountBalance('account-2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(input(tester), '50');
    expect(find.text('≈ 0.25 ZEC'), findsOneWidget);
    expect(operations.quotedAmounts.last, BigInt.from(25000000));
    expect(canContinue(tester), isTrue);
    await review(tester);
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();
    expect(operations.createdAmounts, [BigInt.from(25000000)]);
    expect(operations.createdFromAccounts, ['account-2']);
  });
}

class _PriceNotifier extends ZecHomeMarketDataNotifier {
  _PriceNotifier({
    this.livePrice = 100,
    this.displayPrice = 100,
    this.loading = false,
  });
  final double? livePrice;
  final double? displayPrice;
  final bool loading;

  @override
  ZecHomeMarketDataState build() => ZecHomeMarketDataState(
    displayData: displayPrice == null
        ? null
        : ZecMarketData(usdPrice: displayPrice!),
    liveData: livePrice == null ? null : ZecMarketData(usdPrice: livePrice!),
    isLoading: loading,
  );

  void expirePrice() => state = const ZecHomeMarketDataState();

  void setLoading(bool loading) {
    state = ZecHomeMarketDataState(
      displayData: state.displayData,
      liveData: state.liveData,
      fetchedAt: state.fetchedAt,
      isLoading: loading,
    );
  }

  void setPrice(double? price) {
    state = ZecHomeMarketDataState(
      displayData: price == null
          ? state.displayData
          : ZecMarketData(usdPrice: price),
      liveData: price == null ? null : ZecMarketData(usdPrice: price),
    );
  }
}

class _RecordingOperations extends FakePaymentLinkOperations {
  final quotedAmounts = <BigInt>[];
  Completer<void>? quoteGate;

  @override
  Future<PaymentLinkFundingQuote> quoteFunding({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
  }) async {
    quotedAmounts.add(amountZatoshi);
    await quoteGate?.future;
    return super.quoteFunding(
      amountZatoshi: amountZatoshi,
      sourceAccountUuid: sourceAccountUuid,
    );
  }
}
