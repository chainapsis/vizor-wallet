import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_app.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_scenarios.dart';

import '../../support/app_test_fonts.dart';

// The pay activity summary keeps the Figma height with the app's fonts: the
// recipient address and its full-address action share one line.
void main() {
  setUpAll(loadAppTestFonts);

  testWidgets('the pay progress summary keeps its Figma size', (tester) async {
    tester.view.physicalSize = const Size(1080, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FigmaCompareApp(
        scenario: figmaCompareScenarios.firstWhere(
          (s) => s.id == 'pay-in-progress',
        ),
        themeMode: ThemeMode.light,
        captureBoundaryKey: GlobalKey(),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('pay_status_review_info'))),
      const Size(396, 204),
    );
  });
}
