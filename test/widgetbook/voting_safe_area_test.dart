@Tags(['mobile'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'package:zcash_wallet/widgetbook/voting_use_cases.dart';

import '../figma_compare/figma_compare_font_loader.dart';
import 'support/wb_gallery_harness.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);

  testWidgets('active poll navigation starts below the phone status bar', (
    tester,
  ) async {
    await pumpUseCase(tester, buildMobileVotingEligibleUseCase);
    final nav = find.byType(MobileTopNav);
    expect(nav, findsOneWidget);
    final frame = tester.getRect(find.byType(WbPhoneBox));
    final topNav = tester.getRect(nav);
    expect(topNav.top - frame.top, kWbPhoneStatusBarInset);
    expect(MediaQuery.paddingOf(tester.element(nav)).top, 0);
    expect(tester.takeException(), isNull);
    await disposeTree(tester);
  });
}
