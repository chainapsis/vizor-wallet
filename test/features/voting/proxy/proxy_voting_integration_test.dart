import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/screens/proxy_round_delegation.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_proposal_detail_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_results_screen.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';

import '../../../support/test_l10n.dart';
import 'support/proxy_test_harness.dart';
import 'support/proxy_values.dart';

void main() {
  /// Pumps the round's questions with the delegation line, as the round
  /// screen builds them for [delegatesAnswering] and [delegationDrafted].
  Future<void> pumpActive(
    WidgetTester tester, {
    List<String>? delegatesAnswering,
    bool delegationDrafted = false,
  }) async {
    final scenario = proxyTestScenario();
    await pumpProxyRoute(
      tester,
      '/detail',
      scenario: scenario,
      extraRoutes: [
        GoRoute(
          path: '/detail',
          builder: (_, _) => Scaffold(
            body: VotingActivePollContent(
              showDesktopToolbar: false,
              roundId: kProxyTestRoundId,
              title: 'Round',
              snapshotHeight: 100,
              description: '',
              forumUri: null,
              endDate: null,
              votingPowerZatoshi: BigInt.from(5000000000),
              votingPowerPreparing: false,
              votingEligibilityConfirmed: true,
              answersEditable: true,
              votingEligibilityMessage: null,
              votingEligibilityErrorMessage: null,
              onVotingEligibilityRetry: () {},
              proposals: scenario.round.proposals,
              draft: const VotingDraftState(),
              onChoice: (_, _) {},
              delegationEntry: const ProxyVotingPowerLine(
                roundId: kProxyTestRoundId,
              ),
              delegatesAnswering: delegatesAnswering,
              delegationDrafted: delegationDrafted,
            ),
          ),
        ),
      ],
    );
  }

  /// The review button's enabled state.
  bool reviewEnabled(WidgetTester tester) =>
      tester
          .widget<AppButton>(
            find.descendant(
              of: find.byKey(const ValueKey('voting_review_answers_button')),
              matching: find.byType(AppButton),
            ),
          )
          .onPressed !=
      null;

  testWidgets('everything delegated: each question says who answers it and '
      'needs no answer', (tester) async {
    await pumpActive(
      tester,
      delegatesAnswering: ['@alice_votes', '@bjorn_dev'],
      delegationDrafted: true,
    );
    expect(
      find.text('@alice_votes and @bjorn_dev answer these for you'),
      findsWidgets,
    );
    expect(reviewEnabled(tester), isTrue);
  });

  group('the round status', () {
    /// Pumps the voted round with a committed delegation to Alice and
    /// Bjorn, whose ballots read [ballot].
    Future<void> pumpVoted(
      WidgetTester tester, {
      ApiDelegateBallotView? ballot,
      Map<int, int?> ownChoices = const {1: 0, 2: 1, 3: 0},
    }) async {
      final scenario = proxyTestScenario(
        availability: const ApiProxyAvailability(
          kind: ApiProxyAvailabilityKind.alreadyVoted,
          usedElsewhere: false,
        ),
      );
      final status = proxyStatus(scenario, [
        'alice_votes',
        'bjorn_dev',
      ], ballot: ballot);
      scenario.status = status;
      await pumpProxyRoute(
        tester,
        '/voted',
        scenario: scenario,
        extraRoutes: [
          GoRoute(
            path: '/voted',
            builder: (_, _) => Scaffold(
              body: VotingVotedPollContent(
                showDesktopToolbar: false,
                roundTitle: 'Round',
                snapshotHeight: 100,
                description: '',
                forumUri: null,
                votingPowerZatoshi: BigInt.from(5000000000),
                votingPowerPreparing: false,
                votedAt: kProxyTestNow,
                proposals: scenario.round.proposals,
                choicesByProposalId: ownChoices,
                delegationEntry: ProxyDelegationSummary(
                  status: status,
                  roundActive: true,
                ),
                proposalFooterBuilder: (proposal) => ProxyQuestionStatus(
                  proposal: proposal,
                  ownChoice: ownChoices[proposal.id],
                  status: status,
                ),
              ),
            ),
          ),
        ],
      );
    }

    /// The lines under question [id].
    List<String> linesOf(WidgetTester tester, int id) => [
      for (final text in tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(ValueKey('proxy_question_status_$id')),
          matching: find.byType(Text),
        ),
      ))
        text.data!,
    ];

    testWidgets('shows the wallet\'s own answer and each delegate\'s, with '
        'amounts', (tester) async {
      await pumpVoted(
        tester,
        ballot: proxyBallot(ApiDelegateBallotKind.submitted, [1, 0, 1]),
      );
      final scenario = proxyTestScenario();
      final first = scenario.round.proposals.first;
      expect(linesOf(tester, first.id), [
        'You · 12.5 ZEC',
        first.options[0].label,
        '@alice_votes · 12.5 ZEC',
        first.options[1].label,
        '@bjorn_dev · 12.5 ZEC',
        first.options[1].label,
      ]);
      expect(find.byKey(const ValueKey('proxy_delegation_summary')), findsOne);
      expect(find.text(testL10n.proxyCountsOnlyWithBallot), findsOne);
      expect(find.text('Skipped'), findsNothing);
    });
  });

  group('PD-8 results', () {
    /// Pumps the results content with the PD-8 note, for a wallet that
    /// delegated.
    Future<ProxyTestHarness> pumpResults(WidgetTester tester) async {
      final scenario = proxyTestScenario();
      scenario.status = proxyStatus(scenario, [
        'alice_votes',
        'bjorn_dev',
      ], ballot: proxyBallot(ApiDelegateBallotKind.counted, [0, 2, 1]));
      return pumpProxyRoute(
        tester,
        '/results',
        scenario: scenario,
        extraRoutes: [
          GoRoute(
            path: '/results',
            builder: (_, _) => Scaffold(
              body: VotingResultsContent(
                title: 'Round',
                snapshotHeight: 100,
                description: '',
                forumUri: null,
                proposals: scenario.round.proposals,
                tallies: const {
                  1: {0: 240, 1: 160},
                  2: {0: 100, 1: 100, 2: 200},
                  3: {0: 320, 1: 80},
                },
                footer: const ProxyResultsDelegationNote(
                  roundId: kProxyTestRoundId,
                ),
              ),
            ),
          ),
        ],
      );
    }

    testWidgets('shows totals with no delegate names, no split and no '
        'separate destination', (tester) async {
      final harness = await pumpResults(tester);
      expect(find.byKey(const ValueKey('voting-result-card-1')), findsOne);
      expect(
        find.byKey(const ValueKey('proxy_results_delegation_note')),
        findsOne,
      );
      final texts = renderedTexts(tester).join('\n');
      for (final entry in harness.repository.scenario.delegates) {
        expect(texts, isNot(contains(entry.handle)));
        if (entry.displayName case final name?) {
          expect(texts, isNot(contains(name)));
        }
      }
      expect(texts, isNot(contains('@')));
      expect(texts.toLowerCase(), isNot(contains('direct')));
      expectNoProxyCountsOrTotals(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('proxy_results_delegation_note')),
          matching: find.byType(AppButton),
        ),
        findsNothing,
      );
    });
  });
}
