import 'dart:ui' show CheckedState, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_slippage_modal.dart';

import '../../figma_compare/figma_compare_font_loader.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

Widget _modal({
  int slippageBps = 200,
  bool paymentMode = false,
  double textScale = 1,
  AppThemeData theme = AppThemeData.dark,
}) {
  return MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
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
            paymentMode: paymentMode,
            onSubmitted: (_, _) {},
            onCancel: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(loadFigmaCompareFonts);

  testWidgets('shows no explanation or warning under the Slippage heading', (
    tester,
  ) async {
    final warningIcon = find.byWidgetPredicate(
      (widget) => widget is AppIcon && widget.name == AppIcons.warning,
    );
    for (final paymentMode in [false, true]) {
      await tester.pumpWidget(_modal(paymentMode: paymentMode));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('swap_slippage_100bps')));
      await tester.pump();
      expect(find.text('Slippage'), findsOneWidget);
      expect(warningIcon, findsNothing);
    }
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
