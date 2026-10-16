import 'dart:ui' show CheckedState, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_modal_card.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_slippage_guidance.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_slippage_modal.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

const _warning = 'Price changes may cause a refund.';

Widget _modal({
  int slippageBps = 200,
  bool paymentMode = false,
  double textScale = 1,
  AppThemeData theme = AppThemeData.dark,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: AppTheme(
        data: theme,
        child: Center(
          child: SwapSlippageModal(
            slippageBps: slippageBps,
            confidential: false,
            onConfidentialChanged: (_) {},
            paymentMode: paymentMode,
            onSubmitted: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(loadFigmaCompareFonts);

  for (final (name, theme) in [
    ('dark', AppThemeData.dark),
    ('light', AppThemeData.light),
  ]) {
    testWidgets('$name warning icon has visible contrast', (tester) async {
      await tester.pumpWidget(_modal(slippageBps: 50, theme: theme));
      final icon = tester.widget<AppIcon>(
        find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.warning,
        ),
      );
      final surface = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AppModalCard),
              matching: find.byType(Container),
            )
            .first,
      );
      final background = switch (surface.decoration!) {
        BoxDecoration(:final color) => color!,
        ShapeDecoration(:final color) => color!,
        _ => throw StateError('Modal surface has no background color'),
      };
      final foregroundLuminance = icon.color!.computeLuminance();
      final backgroundLuminance = background.computeLuminance();
      final contrast = foregroundLuminance > backgroundLuminance
          ? (foregroundLuminance + 0.05) / (backgroundLuminance + 0.05)
          : (backgroundLuminance + 0.05) / (foregroundLuminance + 0.05);
      expect(contrast, greaterThanOrEqualTo(3));
    });
  }

  testWidgets('wrapped centered warning keeps its icon beside the first line', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.dark,
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Center(
              child: SizedBox(
                width: 256,
                child: SwapSlippageGuidance(
                  lowSlippage: true,
                  paymentMode: false,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final text = find.text(_warning);
    final paragraph = tester.renderObject<RenderParagraph>(text);
    final lines = paragraph.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: _warning.length),
    );
    expect(lines.length, greaterThan(1));
    final firstLineLeft = paragraph
        .localToGlobal(Offset(lines.first.left, 0))
        .dx;
    final icon = find.byWidgetPredicate(
      (widget) => widget is AppIcon && widget.name == AppIcons.warning,
    );
    expect(
      firstLineLeft - tester.getRect(icon).right,
      closeTo(AppSpacing.xs, 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the low slippage warning only below 2 percent', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final warningIcon = find.byWidgetPredicate(
      (widget) => widget is AppIcon && widget.name == AppIcons.warning,
    );
    await tester.pumpWidget(_modal());

    expect(
      find.byKey(const ValueKey('swap_slippage_low_warning')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_slippage_description')),
      findsOneWidget,
    );
    expect(warningIcon, findsNothing);

    await tester.tap(find.byKey(const ValueKey('swap_slippage_100bps')));
    await tester.pump();

    expect(find.text(_warning), findsOneWidget);
    expect(warningIcon, findsOneWidget);
    expect(find.text('Low slippage'), findsNothing);
    expect(find.bySemanticsLabel(_warning), findsOneWidget);
    expect(find.text("Maximum price movement you'll accept."), findsNothing);

    await tester.tap(find.byKey(const ValueKey('swap_slippage_200bps')));
    await tester.pump();

    expect(find.text(_warning), findsNothing);
    expect(warningIcon, findsNothing);
    expect(find.text("Maximum price movement you'll accept."), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('uses short Swap and Pay explanations', (tester) async {
    await tester.pumpWidget(_modal());
    expect(find.text("Maximum price movement you'll accept."), findsOneWidget);

    await tester.pumpWidget(_modal(paymentMode: true));
    await tester.pump();
    expect(find.text('Extra ZEC allowed for price movement.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('swap_slippage_100bps')));
    await tester.pump();
    expect(find.text(_warning), findsOneWidget);
    expect(find.text('Extra ZEC allowed for price movement.'), findsNothing);
  });

  for (final config in <({String name, bool paymentMode, double textScale})>[
    (name: 'Swap', paymentMode: false, textScale: 1),
    (name: 'Pay at 200 percent text', paymentMode: true, textScale: 2),
  ]) {
    testWidgets(
      '${config.name} keeps modal and actions stable as guidance changes',
      (tester) async {
        tester.view.physicalSize = const Size(420, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _modal(paymentMode: config.paymentMode, textScale: config.textScale),
        );
        await tester.pump();

        final modal = find.byKey(const ValueKey('swap_slippage_modal'));
        final actions = find.byKey(
          const ValueKey('swap_slippage_update_button'),
        );
        final initialModalRect = tester.getRect(modal);
        final initialActionsRect = tester.getRect(actions);

        await tester.tap(find.byKey(const ValueKey('swap_slippage_100bps')));
        await tester.pump();
        expect(tester.getRect(modal), initialModalRect);
        expect(tester.getRect(actions), initialActionsRect);

        await tester.tap(find.byKey(const ValueKey('swap_slippage_200bps')));
        await tester.pump();
        expect(tester.getRect(modal), initialModalRect);
        expect(tester.getRect(actions), initialActionsRect);
      },
    );
  }

  testWidgets(
    'keeps actions stable for valid, invalid, and empty custom values',
    (tester) async {
      tester.view.physicalSize = const Size(420, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_modal(textScale: 2));
      await tester.pump();

      final actions = find.byKey(const ValueKey('swap_slippage_update_button'));
      final input = find.byKey(const ValueKey('swap_slippage_custom_input'));
      final initialActionsRect = tester.getRect(actions);

      await tester.enterText(input, '1.5');
      await tester.pump();
      expect(tester.getRect(actions), initialActionsRect);
      expect(
        find.byKey(const ValueKey('swap_slippage_error_message')),
        findsNothing,
      );

      await tester.enterText(input, '9');
      await tester.pump();
      expect(tester.getRect(actions), initialActionsRect);
      expect(
        find.byKey(const ValueKey('swap_slippage_error_message')),
        findsOneWidget,
      );

      await tester.enterText(input, '');
      await tester.pump();
      expect(tester.getRect(actions), initialActionsRect);
      expect(
        find.byKey(const ValueKey('swap_slippage_error_message')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'preset choices support keyboard activation and radio semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_modal());
      final modal = find.byKey(const ValueKey('swap_slippage_modal'));
      final initialModalRect = tester.getRect(modal);

      // The confidential switch comes first, then the presets.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(tester.getRect(modal), initialModalRect);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(tester.getRect(modal), initialModalRect);
      expect(find.text(_warning), findsOneWidget);
      final selected = tester.getSemantics(
        find.bySemanticsLabel('0.5% slippage'),
      );
      expect(selected.flagsCollection.isChecked, CheckedState.isTrue);
      expect(
        selected.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(
        find.bySemanticsLabel(RegExp('Custom slippage tolerance, percent')),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets('desktop modal adapts its rows at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_modal(textScale: 2));
    await tester.pump();

    final preset = find.byKey(const ValueKey('swap_slippage_50bps'));
    final custom = find.byKey(const ValueKey('swap_slippage_custom_card'));
    final label = find.byKey(const ValueKey('swap_slippage_custom_label'));
    final input = find.byKey(const ValueKey('swap_slippage_custom_input'));
    final percent = find.byKey(const ValueKey('swap_slippage_custom_percent'));

    expect(tester.getSize(preset).height, greaterThan(40));
    expect(tester.getSize(custom).height, greaterThan(40));
    expect(
      tester.getRect(input).top,
      greaterThanOrEqualTo(tester.getRect(label).bottom),
    );
    expect(
      tester.getRect(percent).left,
      greaterThan(tester.getRect(input).right),
    );
    // The modal and its actions stay on screen; the body scrolls to the rest.
    final modal = find.byKey(const ValueKey('swap_slippage_modal'));
    final update = find.byKey(const ValueKey('swap_slippage_update_button'));
    expect(tester.getRect(modal).bottom, lessThanOrEqualTo(800));
    expect(tester.getRect(update).bottom, lessThanOrEqualTo(800));
    await tester.ensureVisible(custom);
    await tester.pump();
    expect(
      tester.getRect(custom).bottom,
      lessThanOrEqualTo(tester.getRect(update).top),
    );
    expect(tester.takeException(), isNull);
  });
}
