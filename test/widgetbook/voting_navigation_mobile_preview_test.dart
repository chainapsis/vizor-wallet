@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_metadata_widgets.dart';
import 'package:zcash_wallet/widgetbook/fixtures/retroactive_q3_2026.dart';
import 'package:zcash_wallet/widgetbook/voting_navigation_preview.dart';

import 'voting_navigation_walkthrough.dart';

void main() {
  votingWalkthroughTests();
  for (final theme in [AppThemeData.dark, AppThemeData.light]) {
    testWidgets(
      'sheet uses shared header and stays usable at 320px with 200% text $theme',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => AppTheme(
              data: theme,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(2)),
                child: child!,
              ),
            ),
            home: const Scaffold(
              body: VotingNavigationPreview(
                proposals: retroactiveQ3Proposals,
                initialChoices: {0: 0},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(
          tester.element(find.byType(VotingProposalCard).first),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('answer-progress')));
        await tester.pumpAndSettle();
        expect(find.byType(MobileModalScaffold), findsOneWidget);
        expect(find.text('Close'), findsNothing);
        expect(find.bySemanticsLabel('Close').hitTestable(), findsOneWidget);
        expect(find.byKey(const ValueKey('menu-review-action')), findsNothing);
        final last = find.byKey(const ValueKey('mobile-unanswered-item-36'));
        await tester.ensureVisible(last);
        await tester.pumpAndSettle();
        expect(last.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.bySemanticsLabel('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(MobileModalScaffold), findsNothing);
      },
    );
  }
}
