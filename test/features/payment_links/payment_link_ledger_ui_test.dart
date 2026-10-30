import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_batch_limits.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/widgetbook/payment_link_use_cases.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);

  test('Ledger review budget leaves other signers unchanged', () {
    expect(paymentLinkBatchMaxCount(HardwareSignerKind.ledger), 4);
    expect(paymentLinkBatchMaxCount(HardwareSignerKind.keystone), 30);
    expect(paymentLinkBatchMaxCount(null), 50);
  });

  testWidgets(
    'Ledger stepper announces its range and respects limits with the keyboard',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, buildPaymentLinkLedgerBatchUseCase);
      final countField = find.byKey(const ValueKey('payment_link_bulk_count'));
      final increase = find.byKey(const ValueKey('payment_link_bulk_increase'));
      final decrease = find.byKey(const ValueKey('payment_link_bulk_decrease'));
      final initial = tester.getSemantics(countField).getSemanticsData();
      expect(initial.label, contains('Number of cards, 2 to 4'));
      expect(initial.value, '4');
      expect(initial.flagsCollection.isTextField, isTrue);
      expect(
        tester.getSemantics(increase).getSemanticsData().label,
        'Add a card',
      );
      expect(
        tester.getSemantics(decrease).getSemanticsData().label,
        'Remove a card',
      );
      expect(
        tester
            .getSemantics(increase)
            .getSemanticsData()
            .flagsCollection
            .isEnabled,
        Tristate.isFalse,
      );
      final target = tester.widget<TextField>(countField).focusNode!;
      for (var step = 0; step < 30 && !target.hasPrimaryFocus; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      }
      expect(target.hasPrimaryFocus, isTrue);
      final shell = tester.widget<AnimatedContainer>(
        find
            .ancestor(of: countField, matching: find.byType(AnimatedContainer))
            .first,
      );
      expect(
        (shell.decoration! as BoxDecoration).border!.top.color,
        AppColors.dark.background.inverse,
      );
      for (final count in [3, 2, 2]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(find.text('Review $count cards'), findsOneWidget);
      }
      expect(
        tester
            .getSemantics(decrease)
            .getSemanticsData()
            .flagsCollection
            .isEnabled,
        Tristate.isFalse,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Review 3 cards'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('Review 4 cards'), findsOneWidget);
      expect(tester.widget<TextField>(countField).controller!.text, '4');
      expect(tester.takeException(), isNull);
      handle.dispose();
    },
  );

  final states = <String, WidgetBuilder>{
    'empty': buildPaymentLinkLedgerBatchEmptyUseCase,
    'preparing': buildPaymentLinkLedgerBatchPreparingUseCase,
    'ready': buildPaymentLinkLedgerBatchUseCase,
    'error': buildPaymentLinkLedgerBatchErrorUseCase,
  };
  for (final theme in [AppThemeData.dark, AppThemeData.light]) {
    final appearance = theme == AppThemeData.dark ? 'dark' : 'light';
    for (final state in states.entries) {
      testWidgets(
        'Ledger ${state.key} remains usable in $appearance at 320px and 200%',
        (tester) async {
          await _pump(tester, state.value, theme: theme, width: 320, scale: 2);
          expect(
            find.text('Create up to 4 cards at once with Ledger.'),
            findsOneWidget,
          );
          for (final control in ['decrease', 'count', 'increase']) {
            final stepperPart = find.byKey(
              ValueKey('payment_link_bulk_$control'),
            );
            await Scrollable.ensureVisible(
              tester.element(stepperPart),
              alignment: 0.5,
            );
            await tester.pumpAndSettle();
            expect(stepperPart.hitTestable(), findsOneWidget);
            final rect = tester.getRect(stepperPart);
            expect(rect.width, greaterThanOrEqualTo(24));
            expect(rect.height, greaterThanOrEqualTo(24));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(320));
          }
          final action = find.byKey(
            const ValueKey('payment_link_bulk_primary_button'),
          );
          expect(action.hitTestable(), findsOneWidget);
          if (state.key == 'error') {
            final retry = find.text('Try again');
            await Scrollable.ensureVisible(
              tester.element(retry),
              alignment: 0.5,
            );
            await tester.pumpAndSettle();
            expect(retry.hitTestable(), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'Ledger entry hint survives narrow width and large text in $appearance',
      (tester) async {
        await _pump(
          tester,
          buildPaymentLinkLedgerEntryUseCase,
          theme: theme,
          width: 320,
          scale: 2,
        );
        final entry = find.byKey(
          const ValueKey('payment_link_create_batch_button'),
        );
        await Scrollable.ensureVisible(tester.element(entry), alignment: 0.5);
        await tester.pumpAndSettle();
        expect(entry.hitTestable(), findsOneWidget);
        final hint = find.text('Up to 4 with Ledger');
        expect(hint, findsOneWidget);
        expect(tester.getRect(hint).right, lessThanOrEqualTo(320));
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('Ledger hint, stepper and focus indicators use readable theme pairs', () {
    for (final appearance in ['dark', 'light']) {
      final colors = appearance == 'dark' ? AppColors.dark : AppColors.light;
      double contrast(Color a, Color b) {
        final luminances = [a.computeLuminance(), b.computeLuminance()]..sort();
        return (luminances.last + 0.05) / (luminances.first + 0.05);
      }

      final entrySurfaces = [
        for (var step = 0; step <= 100; step++)
          Color.lerp(
            colors.background.raised,
            colors.background.brandCrimsonSubtle,
            step / 100,
          )!,
      ];
      final hint = entrySurfaces
          .map((bg) => contrast(colors.text.secondary, bg))
          .reduce(math.min);
      final entryRing = entrySurfaces
          .map((bg) => contrast(colors.state.focusRing, bg))
          .reduce(math.min);
      final body = contrast(colors.text.secondary, colors.background.window);
      final input = contrast(colors.text.accent, colors.surface.input.primary);
      final ring = math.min(
        contrast(colors.background.inverse, colors.surface.input.primary),
        contrast(colors.background.inverse, colors.background.window),
      );
      expect(hint, greaterThanOrEqualTo(4.5));
      expect(body, greaterThanOrEqualTo(4.5));
      expect(input, greaterThanOrEqualTo(4.5));
      expect(entryRing, greaterThanOrEqualTo(3));
      expect(ring, greaterThanOrEqualTo(3));
      debugPrint(
        'Ledger UI contrast $appearance: hint=${hint.toStringAsFixed(2)}, '
        'body=${body.toStringAsFixed(2)}, input=${input.toStringAsFixed(2)}, '
        'entry focus=${entryRing.toStringAsFixed(2)}, input focus=${ring.toStringAsFixed(2)}',
      );
    }
  });
}

Future<void> _pump(
  WidgetTester tester,
  WidgetBuilder builder, {
  AppThemeData theme = AppThemeData.dark,
  double width = 808,
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => AppTheme(
        data: theme,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
      ),
      home: Scaffold(
        backgroundColor: theme.colors.background.window,
        body: Builder(builder: builder),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
