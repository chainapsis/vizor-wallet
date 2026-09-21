@Tags(['mobile', 'figma-capture'])
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/payment_links_screen_support.dart';
import '../../figma_compare/figma_compare_font_loader.dart';

void main() {
  const output = String.fromEnvironment('GIFT_CARD_CAPTURE_DIR');
  if (output.isEmpty) return;
  setUpAll(loadFigmaCompareFonts);
  testWidgets(
    'capture actual mobile gift card flow',
    (tester) async {
      final boundary = GlobalKey();
      await pumpPaymentLinksScreen(
        tester,
        logicalSize: const Size(393, 852),
        captureBoundaryKey: boundary,
        clipboard: FakePaymentLinkClipboard(
          text: incomingLink.toUri().toString(),
        ),
      );
      Future<void> capture(String name) async {
        await tester.pump(const Duration(milliseconds: 500));
        final outputFile = File('$output/flow/$name.png');
        outputFile.parent.createSync(recursive: true);
        await expectLater(
          find.byKey(boundary),
          matchesGoldenFile(outputFile.uri),
        );
      }

      Future<void> tapKey(String name) async {
        await tester.tap(find.byKey(ValueKey(name)));
        await tester.pumpAndSettle();
      }

      await capture('home');
      await tapKey('payment_links_mobile_create_button');
      await capture('amount-empty');
      await tester.enterText(
        find.byKey(const ValueKey('payment_link_amount_editor')),
        '0.1',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await capture('amount-filled');
      await tapKey('payment_link_mobile_amount_continue_button');
      await capture('message-empty');
      await tester.enterText(
        find.byKey(const ValueKey('payment_link_message_editor')),
        'A gift for you',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await capture('message-filled');
      await tapKey('payment_link_mobile_message_continue_button');
      await capture('review');
      await tapKey('payment_link_mobile_review_continue_button');
      await capture('ready');
      await tester.tap(find.text('Go home'));
      await tester.pumpAndSettle();
      await capture('cards');
      await tapKey('payment_links_mobile_redeem_button');
      await capture('redeem');
      await tester.tap(find.text('Paste card link'));
      await tester.pumpAndSettle();
      await capture('received');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
