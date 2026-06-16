@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_sheet.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';

/// Pins the adaptive `formBody` template's three height levels (AGENTS-spec):
/// 1. short content → min-height floor, content centred, actions pinned;
/// 2. medium content → sheet hugs the content, actions pinned;
/// 3. tall content → sheet caps below the top gap, body scrolls, actions
///    still pinned to the bottom.
void main() {
  const grabber = ValueKey('mobile_sheet_grabber');
  const content = ValueKey('form_content');
  const actions = ValueKey('form_actions');

  // Floor / cap constants mirrored from mobile_sheet.dart.
  const minContentHeight = 400.0;
  const topGapFraction = 0.15;
  const actionsHeight = 60.0;

  Future<double> openWithContentHeight(
    WidgetTester tester,
    double contentHeight,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: GestureDetector(
                onTap: () => showMobileSheet<void>(
                  context: context,
                  builder: (_) => MobileSheetScaffold(
                    title: 'Form',
                    formBody: true,
                    child: MobileSheetFormBody(
                      content: SizedBox(key: content, height: contentHeight),
                      actions: const SizedBox(
                        key: actions,
                        height: actionsHeight,
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return tester.view.physicalSize.height / tester.view.devicePixelRatio;
  }

  // The grabber sits AppSpacing.s below the rounded surface's top edge, so
  // back it out to get the true sheet top.
  double sheetTop(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(grabber)).dy - AppSpacing.s;

  double actionsBottom(WidgetTester tester) =>
      tester.getBottomLeft(find.byKey(actions)).dy;

  testWidgets('level 1: short content rests at the min-height floor', (
    tester,
  ) async {
    final screen = await openWithContentHeight(tester, 80);
    // Sheet height = screen - top → equals the floor for short content.
    expect(screen - sheetTop(tester), closeTo(minContentHeight, 1));
    // Actions are pinned at the very bottom (above the home-indicator inset,
    // which is zero in the test view).
    expect(actionsBottom(tester), closeTo(screen, 1));
  });

  testWidgets('level 2: medium content grows the sheet to hug it', (
    tester,
  ) async {
    // Tall enough to exceed the floor but still fit under the cap.
    final screen = await openWithContentHeight(tester, 360);
    final height = screen - sheetTop(tester);
    expect(height, greaterThan(minContentHeight + 1));
    expect(height, lessThan(screen * (1 - topGapFraction)));
    expect(actionsBottom(tester), closeTo(screen, 1));
  });

  testWidgets('level 3: tall content caps below the top gap and scrolls', (
    tester,
  ) async {
    final screen = await openWithContentHeight(tester, 5000);
    final top = sheetTop(tester);
    // Capped at the top-gap height, not pushed off-screen.
    expect(top, closeTo(screen * topGapFraction, 1));
    // Body scrolls; actions stay pinned at the bottom.
    expect(find.byType(Scrollable), findsWidgets);
    expect(actionsBottom(tester), closeTo(screen, 1));
  });
}
