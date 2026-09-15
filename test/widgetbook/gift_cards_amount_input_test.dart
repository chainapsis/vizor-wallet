import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/widgetbook/gallery/gift_cards_gallery.dart';

import '../figma_compare/figma_compare_font_loader.dart';
import 'support/wb_gallery_harness.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);

  for (final focused in [true, false]) {
    testWidgets(
      'gift-card amount matches production editing focused=$focused',
      (tester) async {
        await pumpUseCase(
          tester,
          focused
              ? buildGiftCardsAmountGalleryCase
              : buildGiftCardsMobileBodyGalleryCase,
          knobs: focused
              ? {'Layout': 'Mobile', 'State': 'Focused'}
              : {'Page': 'Amount'},
        );
        await tester.pump();
        final field = find.byType(EditableText);
        expect(field, findsOneWidget);
        final controller = tester.widget<EditableText>(field).controller;
        for (final separator in ['.', ',']) {
          await tester.enterText(field, '');
          await tester.enterText(field, separator);
          await tester.pump();
          expect(controller.text, '0.');
          expect(controller.selection.baseOffset, 2);
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: '0.5',
              selection: TextSelection.collapsed(offset: 3),
            ),
          );
          await tester.pump();
          expect(controller.text, '0.5');
          expect(controller.selection.baseOffset, 3);
        }
        await tester.enterText(field, '0.12345678');
        await tester.pump();
        expect(controller.text, '0.12345678');
        for (final invalid in ['0.123456789', '1..2', '-1', 'abc']) {
          await tester.enterText(field, invalid);
          await tester.pump();
          expect(controller.text, '0.12345678');
        }
        expect(tester.takeException(), isNull);
        await disposeTree(tester);
      },
    );
  }
}
