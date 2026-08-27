@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/screens/mobile/mobile_voting_submission_progress_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/mobile/mobile_voting_submitted_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_status_screen.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_pane_scroll_area.dart';

void main() {
  testWidgets('places shared mobile voting scrollbars at the right edge', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        VotingPaneListView.separated(
          maxWidth: 240,
          itemCount: 24,
          itemBuilder: (context, index) =>
              SizedBox(height: 40, child: Text('Item $index')),
          separatorBuilder: (context, index) => const SizedBox(height: 8),
        ),
      ),
    );
    await tester.pump();

    final scrollbar = tester.widget<RawScrollbar>(find.byType(RawScrollbar));
    expect(scrollbar.scrollbarOrientation, ScrollbarOrientation.right);
    expect(scrollbar.crossAxisMargin, 2);
    expect(tester.getRect(find.byType(RawScrollbar)).right, 393);
  });

  testWidgets('submission progress does not show an edge scrollbar', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        const MobileVotingSubmissionProgressScreen(
          activeStep: VotingSubmissionProgressStep.castingVotes,
        ),
      ),
    );

    expect(find.byType(RawScrollbar), findsNothing);
    expect(
      tester
          .getRect(
            find.byKey(
              const ValueKey('mobile_voting_submission_progress_content'),
            ),
          )
          .left,
      16,
    );
  });

  testWidgets('Voted screen keeps padding inside the edge scrollbar', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    await tester.pumpWidget(_app(MobileVotingSubmittedScreen(onDone: () {})));

    const scrollbarKey = ValueKey('mobile_voting_submitted_scrollbar');
    _expectEdgeScrollbar(tester, scrollbarKey);
    expect(
      tester
          .getRect(
            find.byKey(const ValueKey('mobile_voting_submitted_content')),
          )
          .left,
      16,
    );
  });
}

void _expectEdgeScrollbar(WidgetTester tester, Key key) {
  final scrollbarFinder = find.byKey(key);
  final scrollbar = tester.widget<RawScrollbar>(scrollbarFinder);
  final scrollView = tester.widget<SingleChildScrollView>(
    find.descendant(
      of: scrollbarFinder,
      matching: find.byType(SingleChildScrollView),
    ),
  );
  expect(scrollbar.scrollbarOrientation, ScrollbarOrientation.right);
  expect(scrollbar.crossAxisMargin, 2);
  expect(scrollbar.controller, same(scrollView.controller));
  expect(tester.getRect(scrollbarFinder).right, 393);
}

Widget _app(Widget child) {
  return MaterialApp(
    home: AppTheme(data: AppThemeData.light, child: child),
  );
}

Future<void> _setMobileViewport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
