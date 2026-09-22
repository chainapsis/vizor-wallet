import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_proposal_detail_screen.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_metadata_widgets.dart';

import 'fixtures/navigation_proposals.dart';

void main() {
  late StateSetter update;
  late VotingDraftState draft;
  late bool eligible;
  late String account;
  late int reviews;
  late List<VotingProposalView> ballot;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(480, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppTheme(data: AppThemeData.dark, child: child!),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return VotingActivePollContent(
                key: ValueKey(account),
                showDesktopToolbar: false,
                roundId: 'round',
                title: 'Ballot',
                snapshotHeight: 100,
                description: 'A ballot',
                forumUri: null,
                endDate: null,
                votingPowerZatoshi: eligible ? BigInt.one : null,
                votingPowerPreparing: !eligible,
                votingEligibilityConfirmed: eligible,
                answersEditable: true,
                votingEligibilityMessage: null,
                votingEligibilityErrorMessage: null,
                onVotingEligibilityRetry: () {},
                proposals: ballot,
                draft: draft,
                onChoice: (id, choice) => update(() {
                  draft = choice == null
                      ? draft.clearChoice(id)
                      : draft.setChoice(id, choice);
                }),
                onReviewRequested: () => reviews++,
              );
            },
          ),
        ),
      ),
    );
    // Eligibility preparation intentionally has an indeterminate progress bar.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  AppButton reviewButton(WidgetTester tester) => tester.widget<AppButton>(
    find.ancestor(
      of: find.byKey(const ValueKey('sticky-review-action')),
      matching: find.byType(AppButton),
    ),
  );

  setUp(() {
    draft = const VotingDraftState();
    eligible = true;
    account = 'account-a';
    reviews = 0;
    ballot = proposals;
  });

  testWidgets('answers outside this ballot cannot enable review', (
    tester,
  ) async {
    draft = const VotingDraftState(choices: {999: 0});
    await pump(tester);
    expect(find.text('0 / 2 answered'), findsOneWidget);
    final action = tester.widget<AppButton>(
      find.descendant(
        of: find.byKey(const ValueKey('voting_review_answers_button')),
        matching: find.byType(AppButton),
      ),
    );
    expect(action.onPressed, isNull);
  });

  testWidgets('large ballot builds and reaches an offscreen proposal', (
    tester,
  ) async {
    ballot = [
      for (var i = 0; i < 200; i++)
        VotingProposalView(
          id: i * 3 + 7,
          title: 'Proposal $i',
          description: List.filled(
            10,
            'A long proposal description.',
          ).join(' '),
          options: const [VotingOptionView(index: 0, label: 'Accept')],
        ),
    ];
    draft = VotingDraftState(
      choices: {for (final p in ballot.take(199)) p.id: 0},
    );
    await pump(tester);
    expect(find.byType(VotingProposalCard), findsNWidgets(200));
    await tester.tap(find.byKey(const ValueKey('answer-progress')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proposal 199').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('jump-highlight-604')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'nonconsecutive IDs and zero choice determine unanswered targets',
    (tester) async {
      draft = const VotingDraftState(choices: {7: 0, 999: 0});
      await pump(tester);
      expect(find.text('1 / 2 answered'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('answer-progress')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('jump-highlight-91')), findsOneWidget);
      expect(find.byKey(const ValueKey('jump-highlight-7')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('completion cue cannot open review before its label appears', (
    tester,
  ) async {
    draft = const VotingDraftState(choices: {7: 0});
    await pump(tester);
    tester
        .widgetList<VotingProposalCard>(find.byType(VotingProposalCard))
        .last
        .onChoice!(0);
    await tester.pump();
    final progress = find.byKey(const ValueKey('answer-progress'));
    AppButton progressButton() => tester.widget<AppButton>(
      find.ancestor(of: progress, matching: find.byType(AppButton)),
    );
    expect(find.byKey(const ValueKey('completion-check')), findsOneWidget);
    expect(progressButton().onPressed, isNull);
    await tester.tap(progress);
    await tester.pump(const Duration(milliseconds: 699));
    expect(reviews, 0);
    expect(progressButton().onPressed, isNull);
    expect(find.byKey(const ValueKey('sticky-review-action')), findsNothing);
    await tester.tap(progress);
    expect(reviews, 0);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('completion-check')), findsNothing);
    expect(reviewButton(tester).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('sticky-review-action')));
    await tester.pump();
    expect(reviews, 1);
  });

  testWidgets(
    'hydrated complete draft has no cue and pending eligibility blocks review',
    (tester) async {
      eligible = false;
      await pump(tester);
      update(() => draft = const VotingDraftState(choices: {7: 0, 91: 0}));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('completion-check')), findsNothing);
      expect(reviewButton(tester).onPressed, isNull);
      update(() => eligible = true);
      await tester.pumpAndSettle();
      expect(reviewButton(tester).onPressed, isNotNull);
      reviewButton(tester).onPressed!();
      await tester.pump();
      expect(reviews, 1);
    },
  );

  testWidgets(
    'account replacement cancels completion and resets scroll and draft',
    (tester) async {
      draft = const VotingDraftState(choices: {7: 0});
      await pump(tester);
      final cards = tester.widgetList<VotingProposalCard>(
        find.byType(VotingProposalCard),
      );
      cards.last.onChoice!(0);
      await tester.pump();
      expect(find.byKey(const ValueKey('completion-check')), findsOneWidget);
      final scroll = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      update(() {
        account = 'account-b';
        draft = const VotingDraftState();
      });
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('0 / 2 answered'), findsOneWidget);
      expect(find.byKey(const ValueKey('completion-check')), findsNothing);
      expect(find.byKey(const ValueKey('sticky-review-action')), findsNothing);
      expect(
        tester
            .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
            .controller!
            .offset,
        0,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'eligibility lost during skipped confirmation cannot enter review',
    (tester) async {
      draft = const VotingDraftState(choices: {7: 0});
      await pump(tester);
      final action = find.byKey(const ValueKey('voting_review_answers_button'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('Skip unanswered questions?'), findsOneWidget);
      update(() => eligible = false);
      await tester.pump();
      await tester.tap(find.text('Continue to review'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(reviews, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
