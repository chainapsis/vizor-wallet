@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_app.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_scenarios.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_shell.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav_account.dart';
import 'package:zcash_wallet/src/features/home/screens/mobile/mobile_home_screen.dart';

void main() {
  testWidgets(
    'responsive importing capture keeps content safe and background full bleed',
    (tester) async {
      const viewport = Size(430, 932);
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final scenario = figmaCompareScenarios.singleWhere(
        (scenario) => scenario.id == 'mobile-home-importing',
      );
      await tester.pumpWidget(
        FigmaCompareApp(
          scenario: scenario,
          themeMode: ThemeMode.light,
          captureBoundaryKey: GlobalKey(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final shellContext = tester.element(find.byType(AppMobileShell));
      expect(
        MediaQuery.paddingOf(shellContext),
        const EdgeInsets.only(top: 55, bottom: 24),
      );

      final homeContext = tester.element(find.byType(MobileHomeScreen));
      expect(MediaQuery.paddingOf(homeContext).top, 55);
      expect(
        tester.getSize(
          find.byKey(const ValueKey('mobile_home_importing_background')),
        ),
        viewport,
      );
      expect(
        tester.getTopLeft(find.byType(MobileTopNavAccount)).dy,
        greaterThanOrEqualTo(55),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
