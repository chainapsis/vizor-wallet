import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_back_link.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_metadata_widgets.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_proposal_list.dart';

import 'fixtures/navigation_proposals.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('ballot back link matches the shared toolbar at $scale text', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/vote',
        routes: [
          GoRoute(
            path: '/vote',
            builder: (_, _) =>
                const Scaffold(body: Column(children: [AppPaneToolbar()])),
            routes: [
              GoRoute(
                path: 'ballot',
                builder: (_, _) => Scaffold(
                  body: VotingProposalList(
                    proposals: proposals,
                    choices: const {},
                    summary: const Text('Voting'),
                    cardBuilder: (proposal, advancing) => VotingProposalCard(
                      proposal: proposal,
                      advancing: advancing,
                    ),
                    reviewAction: const Text('Review answers'),
                    onReview: null,
                    answerRevision: 0,
                    lastEditedProposalId: null,
                    showDesktopToolbar: true,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => AppTheme(
            data: AppThemeData.light,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final normalBack = tester.getRect(find.byType(AppBackLink));
      router.push('/vote/ballot');
      await tester.pumpAndSettle();
      final ballotBack = tester.getRect(find.byType(AppBackLink).last);
      expect(ballotBack.left, normalBack.left);
      expect(ballotBack.center.dy, normalBack.center.dy);
      expect(tester.getSize(find.byType(AppPaneToolbar).last).height, 48);
      final navigation = tester.getRect(
        find.byKey(const ValueKey('navigation-controls')),
      );
      final viewport = tester.getRect(find.byType(SingleChildScrollView).first);
      expect(navigation.bottom, lessThanOrEqualTo(viewport.top));
      if (scale == 1) expect(navigation.center.dy, ballotBack.center.dy);
      await tester.tap(find.byKey(const ValueKey('answer-progress')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('unanswered-item-0')), findsOneWidget);
      // Dismiss the menu, then verify the layered toolbar still accepts back taps.
      await tester.tapAt(const Offset(10, 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AppBackLink).last);
      await tester.pumpAndSettle();
      expect(find.byType(VotingProposalList), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
