@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/pay/widgets/mobile/mobile_pay_amount_step.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';

import '../../support/app_test_fonts.dart';

const _state = SwapState(
  direction: SwapDirection.zecToExternal,
  quoteMode: SwapQuoteMode.exactOutput,
  amountText: '2.251',
  receiveAmountText: '990',
  receiveFiatText: '990.00',
  destinationText: '',
  reviewVisible: false,
  intents: [],
  externalAsset: SwapAsset.usdc,
  payMode: true,
);

void main() {
  setUpAll(loadAppTestFonts);

  Future<void> pumpPay(
    WidgetTester tester, {
    required Size size,
    required ValueNotifier<double> scale,
    required TextEditingController controller,
    required FocusNode focus,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        builder: (context, child) => ValueListenableBuilder<double>(
          valueListenable: scale,
          builder: (context, value, _) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(value)),
            child: AppTheme(data: AppThemeData.dark, child: child!),
          ),
        ),
        home: Scaffold(
          body: MobilePayAmountStep(
            state: _state,
            controller: controller,
            focusNode: focus,
            zecAvailableZatoshi: BigInt.from(100000000000),
            onAmountChanged: (_) {},
            onFiatAmountChanged: (_) {},
            onToggleFiatInputMode: () {},
            onOpenAssetSelector: () {},
            slippageLabel: '0.5%',
            confidentialReveal: 0,
            onOpenSlippage: () {},
            onContinue: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(360, 800), const Size(320, 568)]) {
    for (final factor in [1.0, 1.5, 2.0]) {
      testWidgets('Pay fits at $factor on $size with keyboard and long input', (
        tester,
      ) async {
        final scale = ValueNotifier(factor);
        final controller = TextEditingController(text: '990');
        final focus = FocusNode();
        addTearDown(scale.dispose);
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        await pumpPay(
          tester,
          size: size,
          scale: scale,
          controller: controller,
          focus: focus,
        );
        expect(tester.takeException(), isNull);
        final editable = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        expect(
          editable.size.height,
          greaterThanOrEqualTo(editable.preferredLineHeight),
        );
        final action = find.byKey(
          const ValueKey('mobile_pay_amount_continue_button'),
        );
        final label = tester.renderObject<RenderParagraph>(
          find.text('Continue'),
        );
        final natural = TextPainter(
          text: label.text,
          textDirection: label.textDirection,
          textScaler: label.textScaler,
          maxLines: 1,
        )..layout();
        expect(label.size.width, greaterThanOrEqualTo(natural.width - 0.5));
        natural.dispose();
        await tester.enterText(
          find.byKey(const ValueKey('mobile_pay_amount_input')),
          '1234567.123456',
        );
        await tester.pump();
        expect(controller.text, '1234567.123456');
        tester.view.viewInsets = const FakeViewPadding(bottom: 256);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(action).bottom,
          lessThanOrEqualTo(size.height - 256),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('reflow preserves the focused amount field and selection', (
    tester,
  ) async {
    final scale = ValueNotifier(1.0);
    final controller = TextEditingController(text: '990');
    final focus = FocusNode();
    addTearDown(scale.dispose);
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await pumpPay(
      tester,
      size: const Size(360, 800),
      scale: scale,
      controller: controller,
      focus: focus,
    );
    focus.requestFocus();
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    final field = tester.state<EditableTextState>(find.byType(EditableText));
    scale.value = 2;
    await tester.pumpAndSettle();
    expect(
      tester.state<EditableTextState>(find.byType(EditableText)),
      same(field),
    );
    expect(focus.hasFocus, isTrue);
    expect(controller.text, '990');
    expect(controller.selection.baseOffset, 2);
    expect(tester.takeException(), isNull);
  });
}
