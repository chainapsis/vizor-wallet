@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_app.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_scenarios.dart';

import 'figma_compare_font_loader.dart';

/// Mobile scenarios that cannot render inside [FigmaCompareApp] today.
///
/// Each of these is a Widgetbook use case that reads `GoRouter.of(context)`
/// while building, which the comparison app does not provide, so
/// `scripts/figma-compare.sh widget --form-factor mobile --scenario <id>`
/// throws `No GoRouter found in context` instead of writing a PNG. The
/// breakage predates the smoke loop below — it is exactly what having no
/// mobile loop hid — and fixing it means changing the scenarios, not the test.
///
/// The list is pinned rather than filtered so it cannot silently grow: adding
/// an id here is a deliberate edit, and a stale id fails the guard below.
const _scenariosThatNeedARouter = {
  'mobile-ironwood-migration-intro',
  'mobile-ironwood-migration-how-it-works',
  'mobile-ironwood-migration-options',
  'mobile-ironwood-migration-android-options',
  'mobile-ironwood-migration-fast-review',
};

// The desktop loop in figma_compare_test.dart smokes every `desktop: true`
// scenario; the mobile half had no equivalent, so a scenario registered with a
// missing provider override or a stale fixture constructor stayed green in
// both lanes and only failed weeks later, by hand, mid design review.
void main() {
  setUpAll(loadFigmaCompareFonts);

  final mobileScenarios = figmaCompareScenarios
      .where((scenario) => scenario.mobile)
      .toList();

  test('the mobile lane has scenarios to smoke', () {
    expect(mobileScenarios, isNotEmpty);
  });

  test('every known-broken id is still a registered mobile scenario', () {
    final mobileIds = mobileScenarios.map((scenario) => scenario.id).toSet();

    expect(
      _scenariosThatNeedARouter.difference(mobileIds),
      isEmpty,
      reason:
          'a scenario in the exclusion list was renamed or removed — drop it '
          'from the list rather than leaving a dead exemption behind',
    );
  });

  for (final scenario in mobileScenarios) {
    if (_scenariosThatNeedARouter.contains(scenario.id)) continue;

    testWidgets('${scenario.id} renders at the mobile comparison viewport', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        FigmaCompareApp(
          scenario: scenario,
          themeMode: ThemeMode.dark,
          captureBoundaryKey: boundaryKey,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(boundaryKey.currentContext, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }
}
