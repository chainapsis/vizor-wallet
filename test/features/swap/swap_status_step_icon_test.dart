import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_status_page_content.dart';

/// The deposit confirmation step waits with an hourglass, so a step that has
/// not started never reads as done; once complete it shows a check.
void main() {
  const steps = [
    SwapStatusStepData(title: 'LTC sent', state: SwapStatusStepState.pending),
    SwapStatusStepData(
      title: 'Deposit confirmation',
      state: SwapStatusStepState.pending,
      kind: SwapStatusStepKind.depositConfirmation,
    ),
    SwapStatusStepData(
      title: 'Swap',
      state: SwapStatusStepState.pending,
      kind: SwapStatusStepKind.swap,
    ),
  ];

  Future<List<String>> iconsBeside(
    WidgetTester tester, {
    required int progressIndex,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: appSupportedLocales(),
        home: AppTheme(
          data: AppThemeData.light,
          child: Scaffold(
            body: SwapAnimatedProgressRoute(
              steps: steps,
              progressIndex: progressIndex,
              badgeKind: SwapStatusBadgeKind.liveQuote,
            ),
          ),
        ),
      ),
    );
    // The active step's loader keeps animating, so pump instead of settle.
    await tester.pump();
    final row = find.byKey(
      const ValueKey('swap_activity_route_step_1_title_row'),
    );
    final step = find.ancestor(of: row, matching: find.byType(Row)).last;
    return tester
        .widgetList<AppIcon>(
          find.descendant(of: step, matching: find.byType(AppIcon)),
        )
        .map((icon) => icon.name)
        .toList();
  }

  testWidgets('a pending deposit confirmation shows an hourglass', (
    tester,
  ) async {
    final icons = await iconsBeside(tester, progressIndex: 0);
    expect(icons, contains(AppIcons.time));
    expect(icons, isNot(contains(AppIcons.check)));
  });

  testWidgets('a completed deposit confirmation shows a check', (tester) async {
    final icons = await iconsBeside(tester, progressIndex: 2);
    expect(icons, contains(AppIcons.check));
    expect(icons, isNot(contains(AppIcons.time)));
  });
}
