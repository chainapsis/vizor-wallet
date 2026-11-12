import 'package:flutter/material.dart' show MaterialApp, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_confidential_ui.dart';
import 'package:zcash_wallet/widgetbook/pay_use_cases.dart';
import '../figma_compare/figma_compare_font_loader.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

const _mobile = kAppFormFactor == AppFormFactor.mobile;

final _route = find.byKey(const ValueKey('swap_confidential_route'));

final _settings = find.byKey(
  ValueKey(_mobile ? 'mobile_pay_slippage_button' : 'pay_slippage_button'),
);

/// Pay shows the mode only as the mark on its settings button.
bool _confidential(WidgetTester tester) => find
    .descendant(of: _settings, matching: find.byType(SwapConfidentialIcon))
    .evaluate()
    .isNotEmpty;

void main() {
  setUpAll(loadFigmaCompareFonts);

  testWidgets('pay settings set the mode and reprice the estimate', (
    tester,
  ) async {
    await _pump(tester, buildConfidentialPayAmountUseCase);
    expect(_confidential(tester), isFalse);
    expect(find.textContaining('2.251'), findsOneWidget);
    await tester.tap(_settings);
    await tester.pumpAndSettle();
    expect(find.text('Payment settings'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('swap_confidential_switch')));
    await tester.pump();
    // Update applies it with the slippage choice.
    await tester.tap(find.byKey(const ValueKey('swap_slippage_update_button')));
    await tester.pumpAndSettle();
    expect(find.text('Payment settings'), findsNothing);
    expect(_confidential(tester), isTrue);
    expect(find.textContaining('2.256'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no standard quote recovers into a confidential review', (
    tester,
  ) async {
    await _pump(tester, buildConfidentialPayLiquidityUseCase);
    expect(find.text('No quote for this amount'), findsOneWidget);
    final recovery = find.text('Get confidential quote');
    expect(recovery.hitTestable(), findsOneWidget);
    await tester.tap(recovery);
    await tester.pumpAndSettle();
    expect(find.text('Review Payment'), findsOneWidget);
    expect(_route, findsOneWidget);
    expect(find.textContaining('2.256'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standard payments carry no confidential mark', (tester) async {
    await _pump(tester, buildConfidentialPayAmountUseCase);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_mobile ? 'Continue' : 'Select recipient'));
    await tester.pumpAndSettle();
    expect(find.text('Review Payment'), findsOneWidget);
    expect(_route, findsNothing);
  });

  testWidgets('in-progress and completed payments show the hidden route', (
    tester,
  ) async {
    for (final builder in [
      buildConfidentialPayInProgressUseCase,
      buildConfidentialPayCompletedUseCase,
    ]) {
      await _pump(tester, builder);
      expect(_route, findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('every prototype state lays out in both themes', (tester) async {
    for (final theme in [AppThemeData.light, AppThemeData.dark]) {
      for (final builder in [
        buildConfidentialPayAmountUseCase,
        buildConfidentialPayAmountOnUseCase,
        buildConfidentialPayLiquidityUseCase,
        buildConfidentialPayReviewUseCase,
        buildConfidentialPayInProgressUseCase,
        buildConfidentialPayCompletedUseCase,
      ]) {
        await _pump(tester, builder, theme: theme);
        expect(tester.takeException(), isNull);
      }
    }
  });
}

Future<void> _pump(
  WidgetTester tester,
  WidgetBuilder builder, {
  AppThemeData? theme,
}) async {
  // Give each fixture a fresh local State, as Widgetbook does when changing cases.
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = _mobile
      ? const Size(393, 852)
      : const Size(1080, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      builder: (context, child) => AppTheme(
        data: theme ?? AppThemeData.dark,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
      home: Scaffold(body: Builder(builder: builder)),
    ),
  );
  await tester.pumpAndSettle();
}
