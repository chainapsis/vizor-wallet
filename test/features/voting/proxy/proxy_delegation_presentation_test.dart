import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_presentation.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';
import 'package:zcash_wallet/src/features/voting/voting_message.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';

import '../../../support/test_l10n.dart';
import 'support/mock_proxy_delegation_repository.dart';
import 'support/proxy_test_scenarios.dart';
import 'support/proxy_values.dart';

void main() {
  group('availability mapping (PD-1)', () {
    final cases = <ApiProxyAvailability, ProxyEntryKind>{
      const ApiProxyAvailability(
        kind: ApiProxyAvailabilityKind.available,
        usedElsewhere: false,
      ): ProxyEntryKind.available,
      const ApiProxyAvailability(
        kind: ApiProxyAvailabilityKind.unsupported,
        usedElsewhere: false,
      ): ProxyEntryKind.hidden,
      const ApiProxyAvailability(
        kind: ApiProxyAvailabilityKind.paused,
        usedElsewhere: false,
      ): ProxyEntryKind.paused,
      const ApiProxyAvailability(
        kind: ApiProxyAvailabilityKind.alreadyVoted,
        usedElsewhere: false,
      ): ProxyEntryKind.alreadyVoted,
      const ApiProxyAvailability(
        kind: ApiProxyAvailabilityKind.alreadyVoted,
        usedElsewhere: true,
      ): ProxyEntryKind.usedElsewhere,
      const ApiProxyAvailability(
        kind: ApiProxyAvailabilityKind.timingUnavailable,
        usedElsewhere: false,
      ): ProxyEntryKind.timingUnavailable,
      const ApiProxyAvailability(
        kind: ApiProxyAvailabilityKind.voteEnded,
        usedElsewhere: false,
      ): ProxyEntryKind.voteEnded,
    };

    test('maps every availability result to its own card state', () {
      for (final entry in cases.entries) {
        expect(
          proxyEntryKindFor(status: null, availability: entry.key),
          entry.value,
          reason: '${entry.key.kind}',
        );
      }
    });

    test('a committed allocation shows whatever availability says', () {
      final status = proxyStatus(proxyTestScenario(), ['alice_votes']);
      for (final availability in cases.keys) {
        expect(
          proxyEntryKindFor(status: status, availability: availability),
          ProxyEntryKind.locked,
        );
      }
    });

    test('every result except Available blocks a commit with copy', () {
      for (final availability in cases.keys) {
        final copy = proxyAvailabilityBlockCopy(testL10n, availability);
        if (availability.kind == ApiProxyAvailabilityKind.available) {
          expect(copy, isNull);
        } else {
          expect(copy, isNotEmpty, reason: '${availability.kind}');
        }
      }
      expect(
        proxyAvailabilityBlockCopy(
          testL10n,
          const ApiProxyAvailability(
            kind: ApiProxyAvailabilityKind.paused,
            usedElsewhere: false,
          ),
        ),
        testL10n.proxyPaused,
      );
    });
  });

  test('each repository failure kind has its own copy, other falls back', () {
    final copies = {
      for (final kind in ProxyDelegationErrorKind.values)
        kind: proxyErrorCopy(
          testL10n,
          ProxyDelegationError(kind: kind),
          fallback: testL10n.proxyCommitError,
        ),
    };
    expect(
      copies[ProxyDelegationErrorKind.alreadyVoted],
      testL10n.proxyAlreadyStartedVoting,
    );
    expect(
      copies[ProxyDelegationErrorKind.registrationUnusable],
      testL10n.proxyRegistrationUnusable,
    );
    expect(
      copies[ProxyDelegationErrorKind.keptShareUnanswered],
      testL10n.proxyKeptShareUnanswered,
    );
    expect(copies[ProxyDelegationErrorKind.other], testL10n.proxyCommitError);
    expect(
      proxyErrorCopy(testL10n, const ProxyReviewChangedException()),
      testL10n.proxyReviewChanged,
    );
    expect(
      {...copies.values, testL10n.proxyReviewChanged},
      hasLength(ProxyDelegationErrorKind.values.length + 1),
      reason: 'no two kinds share copy',
    );
  });

  group('PD-4 timing', () {
    final voteEnd = DateTime(2026, 10, 10, 12);

    test('tooLate fires only at vote_end, with no 10-minute block', () {
      for (final before in const [
        Duration(minutes: 10),
        Duration(minutes: 1),
        Duration(seconds: 1),
      ]) {
        expect(
          proxyDelegationWindowAt(
            now: voteEnd.subtract(before),
            voteEnd: voteEnd,
          ),
          ProxyDelegationWindow.closingSoon,
        );
      }
      expect(
        proxyDelegationWindowAt(now: voteEnd, voteEnd: voteEnd),
        ProxyDelegationWindow.closed,
      );
      expect(
        proxyDelegationWindowAt(
          now: voteEnd.add(const Duration(seconds: 1)),
          voteEnd: voteEnd,
        ),
        ProxyDelegationWindow.closed,
      );
    });

    test('the 24 h notice starts 24 h before vote_end', () {
      expect(
        proxyDelegationWindowAt(
          now: voteEnd.subtract(const Duration(hours: 24, seconds: 1)),
          voteEnd: voteEnd,
        ),
        ProxyDelegationWindow.open,
      );
      expect(
        proxyDelegationWindowAt(
          now: voteEnd.subtract(const Duration(hours: 24)),
          voteEnd: voteEnd,
        ),
        ProxyDelegationWindow.closingSoon,
      );
      expect(
        proxyTimeLeftCopy(
          testL10n,
          now: voteEnd.subtract(const Duration(hours: 8, minutes: 59)),
          voteEnd: voteEnd,
        ),
        '8 hours',
      );
      expect(
        proxyTimeLeftCopy(
          testL10n,
          now: voteEnd.subtract(const Duration(hours: 1)),
          voteEnd: voteEnd,
        ),
        '1 hour',
      );
      expect(
        proxyTimeLeftCopy(
          testL10n,
          now: voteEnd.subtract(const Duration(minutes: 14, seconds: 30)),
          voteEnd: voteEnd,
        ),
        '14 minutes',
      );
      expect(
        proxyTimeLeftCopy(
          testL10n,
          now: voteEnd.subtract(const Duration(seconds: 20)),
          voteEnd: voteEnd,
        ),
        '1 minute',
      );
    });
  });

  group('PD-6 outcome', () {
    final voteEnd = DateTime(2026, 10, 10, 12);
    final before = voteEnd.subtract(const Duration(minutes: 1));

    /// One delegation per entry of [stages].
    List<ApiProxyDelegationView> views(List<ProxyDelegationStage> stages) => [
      for (final (i, stage) in stages.indexed)
        proxyView(
          delegateIndex: i + 1,
          handle: 'd${i + 1}',
          ballots: BigInt.from(10),
          stage: stage,
          ballot: proxyBallot(ApiDelegateBallotKind.noBallotYet),
        ),
    ];

    /// The PD-6 outcome of [progress] at [now], by default one minute
    /// before the end.
    ProxyProgressOutcome outcome(
      ApiProxyDelegationProgress progress, {
      DateTime? now,
    }) => proxyProgressOutcome(progress, now: now ?? before, voteEnd: voteEnd);

    test('completes once sent', () {
      expect(
        outcome(
          proxyProgress(
            delegations: views([
              ProxyDelegationStage.handedOff,
              ProxyDelegationStage.handedOff,
            ]),
          ),
        ),
        isA<ProxyProgressComplete>(),
      );
      expect(
        outcome(
          proxyProgress(
            delegations: views([
              ProxyDelegationStage.handedOff,
              ProxyDelegationStage.included,
            ]),
          ),
        ),
        isA<ProxyProgressRunning>().having(
          (o) => o.step,
          'step',
          ProxyProgressStep.handingOff,
        ),
      );
    });

    test('runs on the earliest delegation stage', () {
      expect(
        outcome(
          proxyProgress(
            delegations: views([
              ProxyDelegationStage.included,
              ProxyDelegationStage.preparing,
            ]),
          ),
        ),
        isA<ProxyProgressRunning>().having(
          (o) => o.step,
          'step',
          ProxyProgressStep.preparing,
        ),
      );
      expect(
        outcome(
          proxyProgress(delegations: views([ProxyDelegationStage.submitting])),
        ),
        isA<ProxyProgressRunning>().having(
          (o) => o.step,
          'step',
          ProxyProgressStep.submitting,
        ),
      );
    });

    test('an immediate plan waits for the reveal of share 0', () {
      final handedOff = views([ProxyDelegationStage.handedOff]);
      expect(
        outcome(proxyProgress(delegations: handedOff, plannedImmediate: true)),
        isA<ProxyProgressRunning>(),
      );
      expect(
        outcome(
          proxyProgress(
            delegations: handedOff,
            plannedImmediate: true,
            immediateRevealConfirmed: true,
          ),
        ),
        isA<ProxyProgressComplete>(),
      );
    });

    test('at vote_end an unfinished job fails with the vote path message', () {
      for (final progress in [
        proxyProgress(delegations: views([ProxyDelegationStage.included])),
        proxyProgress(
          delegations: views([ProxyDelegationStage.handedOff]),
          plannedImmediate: true,
        ),
        proxyProgress(
          delegations: views([ProxyDelegationStage.submitting]),
          refusedByChain: true,
        ),
      ]) {
        final result = outcome(progress, now: voteEnd);
        expect(result, isA<ProxyProgressExpired>());
        expect(
          (result as ProxyProgressExpired).message,
          const VotingNotice(VotingNoticeKind.immediateShareExpired),
        );
      }
    });

    test('a hand-off that finished before vote_end stays complete', () {
      expect(
        outcome(
          proxyProgress(delegations: views([ProxyDelegationStage.handedOff])),
          now: voteEnd.add(const Duration(hours: 1)),
        ),
        isA<ProxyProgressComplete>(),
      );
    });

    test('after tallying a delegation that missed hand-off is not counted', () {
      expect(
        outcome(
          proxyProgress(
            delegations: views([
              ProxyDelegationStage.handedOff,
              ProxyDelegationStage.notCounted,
            ]),
          ),
          now: voteEnd.add(const Duration(hours: 1)),
        ),
        isA<ProxyProgressNotCounted>(),
      );
    });

    test('a batch the chain refuses shows as refused until voting ends', () {
      final refused = proxyProgress(
        delegations: views([ProxyDelegationStage.submitting]),
        refusedByChain: true,
      );
      expect(outcome(refused), isA<ProxyProgressRefused>());
      expect(outcome(refused, now: voteEnd), isA<ProxyProgressExpired>());
    });
  });

  group('round status lines', () {
    test('summarizes a delegation as the plan shows it', () {
      expect(
        proxyDelegationLine(
          testL10n,
          proxyView(
            delegateIndex: 1,
            handle: 'alice',
            ballots: BigInt.from(100),
            stage: ProxyDelegationStage.handedOff,
            ballot: proxyBallot(ApiDelegateBallotKind.noBallotYet),
          ),
        ),
        'Delegated 12.5 ZEC to @alice. Sent.',
      );
    });

    test('question lines go from not voted yet to counted or not counted', () {
      const proposal = VotingProposalView(
        id: 1,
        title: 'First',
        description: '',
        options: [
          VotingOptionView(index: 0, label: 'Yes'),
          VotingOptionView(index: 1, label: 'No'),
        ],
      );
      List<ProxyQuestionLine> lines(ApiDelegateBallotView ballot) =>
          proxyQuestionLines(
            testL10n,
            proposal: proposal,
            ownChoice: 1,
            status: ApiProxyAllocationStatus(
              delegations: [
                proxyView(
                  delegateIndex: 1,
                  handle: 'alice',
                  ballots: BigInt.from(100),
                  stage: ProxyDelegationStage.handedOff,
                  ballot: ballot,
                ),
              ],
              keptBallots: BigInt.from(8),
            ),
          );
      expect(lines(proxyBallot(ApiDelegateBallotKind.noBallotYet)), [
        (who: 'You', amount: '1 ZEC', answer: 'No'),
        (who: '@alice', amount: '12.5 ZEC', answer: "@alice hasn't voted yet"),
      ]);
      expect(
        lines(proxyBallot(ApiDelegateBallotKind.submitted, [0])).last.answer,
        'Yes',
      );
      expect(
        lines(proxyBallot(ApiDelegateBallotKind.counted, [0])).last.answer,
        'Yes · Counted',
      );
      expect(
        lines(proxyBallot(ApiDelegateBallotKind.notCounted)).last.answer,
        'No ballot. Not counted this round.',
      );
    });

    test('labels ballot choices with proposal titles and options', () {
      const proposals = [
        VotingProposalView(
          id: 1,
          title: 'First',
          description: '',
          options: [
            VotingOptionView(index: 0, label: 'Yes'),
            VotingOptionView(index: 1, label: 'No'),
          ],
        ),
        VotingProposalView(
          id: 2,
          title: 'Second',
          description: '',
          options: [VotingOptionView(index: 0, label: 'Fund')],
        ),
      ];
      expect(
        proxyBallotChoices(
          testL10n,
          proxyBallot(ApiDelegateBallotKind.submitted, [1, 0]),
          proposals,
        ),
        [
          (proposal: 'First', option: 'No'),
          (proposal: 'Second', option: 'Fund'),
        ],
      );
      expect(
        proxyBallotChoices(
          testL10n,
          proxyBallot(ApiDelegateBallotKind.noBallotYet),
          proposals,
        ),
        isEmpty,
      );
    });
  });

  group('PD-2 browse', () {
    final scenario = proxyTestScenario();

    test('the mock lists Vizor\'s rows in list order, a retired one '
        'blocked and not reviewed', () async {
      final browse = await MockProxyDelegationRepository(
        scenario,
      ).browse(kProxyTestRoundId);
      final listed = scenario.delegates
          .where((entry) => scenario.listed.contains(entry.index))
          .toList();
      expect(browse.listed, listed);
      final lena = proxyEntry(scenario, 'lena_old');
      expect(lena.status, DelegateEntryStatus.retired);
      expect(lena.blocked, isTrue);
      expect(lena.reviewed, isFalse);
      expect(
        listed.where((entry) => !entry.blocked).every((e) => e.reviewed),
        isTrue,
      );
    });

    test('a delegate is named by its handle, and its choice carries what '
        'the listing showed', () {
      final alice = proxyEntry(scenario, 'alice_votes');
      expect(proxyListingName(alice), '@alice_votes');
      expect(
        alice.choice(100),
        ProxyDelegateChoice(
          delegateIndex: alice.index,
          percentBps: 100,
          provider: ProxyDelegateProvider.x,
          handle: 'alice_votes',
          dk: alice.key.dk,
        ),
      );
    });
  });

  group('allocation draft', () {
    final entry = proxyEntry(proxyTestScenario(), 'alice_votes');

    test('percentages parse and format in basis points', () {
      expect(parseProxyPercent('33.33'), 3333);
      expect(parseProxyPercent('50'), 5000);
      expect(parseProxyPercent('12.5'), 1250);
      expect(parseProxyPercent(''), isNull);
      expect(parseProxyPercent('abc'), isNull);
      expect(formatProxyPercent(3333), '33.33%');
      expect(formatProxyPercent(5000), '50%');
      expect(formatProxyPercent(1250), '12.5%');
      expect(proxyEvenSplit(3), [3334, 3333, 3333]);
    });

    test('flags missing and excess shares, and keeps what is left', () {
      /// A draft of alice rows at [shares].
      ProxyAllocationDraft draft(List<int?> shares) => ProxyAllocationDraft(
        delegates: [
          for (final share in shares)
            ProxyDraftDelegate(entry: entry, percentBps: share),
        ],
      );
      expect(const ProxyAllocationDraft().issue, ProxyDraftIssue.noDelegates);
      expect(draft([null]).issue, ProxyDraftIssue.missingPercent);
      expect(draft([6000, 5000]).issue, ProxyDraftIssue.overAllocated);
      expect(draft([6000]).issue, isNull);
      expect(draft([6000]).keptBps, 4000);
      // Delegating everything is 100% of the shares.
      expect(draft([10000]).issue, isNull);
      expect(draft([10000]).keptBps, 0);
      expect(
        draft([10000]).toRequest('round').choices.single.percentBps,
        10000,
      );
    });
  });

  test('each pre-proving verdict but ok has its own line, and mismatch '
      'says the details did not match the chain', () {
    String? line(DelegateCheck check) =>
        proxyCheckBlockCopy(testL10n, '@alice', check);
    expect(line(DelegateCheck.ok), isNull);
    expect(
      line(DelegateCheck.cannotVerify),
      isNull,
      reason: 'the review reports it once for all delegates',
    );
    expect(
      line(DelegateCheck.suspended),
      "@alice is suspended, so you can't delegate to them.",
    );
    expect(line(DelegateCheck.retired), '@alice has retired as a delegate.');
    expect(
      line(DelegateCheck.notFound),
      "Vizor couldn't find @alice on the voting chain.",
    );
    expect(
      line(DelegateCheck.mismatch),
      "The details Vizor showed for @alice didn't match the voting chain, "
      "so you can't delegate to them.",
    );
  });

  test('a mock entry outside Vizor\'s list has no list content', () {
    final scenario = proxyTestScenario();
    for (final entry in scenario.delegates.where(
      (e) => !scenario.listed.contains(e.index),
    )) {
      expect(entry.displayName, isNull);
      expect(entry.statement, isNull);
    }
    expect(
      mockProxyDelegateKey('x').fingerprint,
      matches(RegExp(r'^[a-z0-9]{4}(-[a-z0-9]{4}){3}$')),
    );
  });
}
