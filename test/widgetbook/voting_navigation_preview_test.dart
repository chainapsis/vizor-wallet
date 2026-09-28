import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_metadata_widgets.dart';
import 'package:zcash_wallet/widgetbook/fixtures/retroactive_q3_2026.dart';
import 'package:zcash_wallet/widgetbook/voting_navigation_preview.dart';

import 'voting_navigation_walkthrough.dart';

void main() {
  testWidgets(
    'completion cue precedes review and cancels when an answer is removed',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.dark,
            child: Scaffold(
              body: VotingNavigationPreview(
                initialChoices: {for (var i = 0; i < 11; i++) i: 1},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final choose = tester
          .widgetList<VotingProposalCard>(find.byType(VotingProposalCard))
          .last
          .onChoice!;
      choose(1);
      await tester.pump();
      expect(find.byKey(const ValueKey('completion-check')), findsOneWidget);
      expect(find.text('12 / 12 answered'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('sticky-review-action')), findsNothing);
      choose(null);
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('completion-check')), findsNothing);
      expect(find.text('11 / 12 answered'), findsOneWidget);
      expect(find.byKey(const ValueKey('sticky-review-action')), findsNothing);
      choose(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('completion-check')), findsNothing);
      expect(
        find.byKey(const ValueKey('sticky-review-action')).hitTestable(),
        findsOneWidget,
      );
    },
  );
  votingWalkthroughTests();
  for (final theme in [AppThemeData.dark, AppThemeData.light]) {
    testWidgets(
      'narrow RTL menu supports enlarged text, scrolling and keyboard $theme',
      (tester) async {
        tester.view.physicalSize = const Size(420, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.macOS),
            home: AppTheme(
              data: theme,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: MediaQuery(
                  data: const MediaQueryData(
                    size: Size(420, 600),
                    textScaler: TextScaler.linear(2),
                    disableAnimations: true,
                  ),
                  child: const Scaffold(
                    body: VotingNavigationPreview(
                      proposals: retroactiveQ3Proposals,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final progress = find.byKey(const ValueKey('answer-progress'));
        await tester.tap(progress);
        await tester.pumpAndSettle();
        final bar = tester.widget<Scrollbar>(find.byType(Scrollbar).last);
        expect(
          tester.getSize(find.byType(Scrollbar).last).height,
          lessThanOrEqualTo(330),
        );
        bar.controller!.jumpTo(bar.controller!.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final last = find.byKey(const ValueKey('unanswered-item-36'));
        expect(last.hitTestable(), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(last, findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.text('Unanswered · 37'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('completed action hides at bottom and returns above', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.dark,
          child: Scaffold(
            body: VotingNavigationPreview(
              initialChoices: {for (var i = 0; i < 12; i++) i: 1},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final review = find.byKey(const ValueKey('sticky-review-action'));
    expect(review.hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('answer-progress')), findsNothing);
    final scroll = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(review.hitTestable(), findsNothing);
    expect(
      find.byKey(const ValueKey('voting_review_answers_button')).hitTestable(),
      findsOneWidget,
    );
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(review.hitTestable(), findsOneWidget);
    await tester.tap(review);
    await tester.pumpAndSettle();
    expect(find.text('Review your answers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
