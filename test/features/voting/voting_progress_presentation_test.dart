import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/voting_progress_presentation.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/features/voting/voting_resume_plan.dart';

VotingSessionState _ballotState({
  required Map<VotingVoteKey, VotingSessionProgress> voteProgress,
  int completed = 0,
  int total = 0,
}) {
  return VotingSessionState(
    roundId: 'round',
    phase: VotingSessionPhase.castingVotes,
    voteProgress: voteProgress,
    voteSubmissionCompletedCount: completed,
    voteSubmissionTotalCount: total,
  );
}

Map<VotingVoteKey, VotingSessionProgress> _proving({
  required int total,
  required int proven,
  double inFlight = 0,
}) {
  return {
    for (var proposalId = 1; proposalId <= total; proposalId++)
      VotingVoteKey(
        bundleIndex: 0,
        proposalId: proposalId,
      ): proposalId <= proven
          ? const VotingSessionProgress(
              phase: VotingProgressPhase.buildingSharePayloads,
              bundleIndex: 0,
              proofProgress: 1,
            )
          : VotingSessionProgress(
              phase: VotingProgressPhase.proofProgress,
              bundleIndex: 0,
              proposalId: proposalId,
              proofProgress: proposalId == proven + 1 ? inFlight : 0,
            ),
  };
}

void main() {
  group('votingBallotProgress', () {
    test('advances with each proof inside one atomic batch', () {
      // The batch is a single planner step covering every question, so the
      // round tally reports nothing finished for its whole duration. The
      // counter has to come from the per-proposal proof events instead, or it
      // reads "1 of 37" from the first proof to the last.
      final early = votingBallotProgress(
        _ballotState(voteProgress: _proving(total: 37, proven: 0), total: 37),
      );
      expect(early.stage, VotingBallotStage.proving);
      expect(early.provenProposals, 0);
      expect(early.totalProposals, 37);

      final midway = votingBallotProgress(
        _ballotState(voteProgress: _proving(total: 37, proven: 12), total: 37),
      );
      expect(midway.stage, VotingBallotStage.proving);
      expect(midway.provenProposals, 12);
      expect(midway.detail, 'Casting votes');
      expect(midway.fraction, greaterThan(early.fraction!));
    });

    test('a question is finished only when every bundle carrying it is', () {
      // One question, two bundles: the first bundle finishing is not the
      // question finishing. Counting it that way marked a one-question round
      // complete — the count is allowed to override the SDK tally — and the UI
      // advanced to finalizing while the sibling was still delivering.
      final halfDone = votingBallotProgress(
        _ballotState(
          voteProgress: {
            const VotingVoteKey(
              bundleIndex: 0,
              proposalId: 7,
            ): VotingSessionProgress(
              phase: VotingProgressPhase.completed,
              bundleIndex: 0,
              proposalId: 7,
              proofProgress: 1,
            ),
            const VotingVoteKey(
              bundleIndex: 1,
              proposalId: 7,
            ): VotingSessionProgress(
              phase: VotingProgressPhase.submitting,
              bundleIndex: 1,
              proposalId: 7,
            ),
          },
          total: 1,
        ),
      );
      expect(halfDone.completedProposals, 0);
      expect(halfDone.stage, isNot(VotingBallotStage.complete));

      final bothDone = votingBallotProgress(
        _ballotState(
          voteProgress: {
            const VotingVoteKey(
              bundleIndex: 0,
              proposalId: 7,
            ): VotingSessionProgress(
              phase: VotingProgressPhase.completed,
              bundleIndex: 0,
              proposalId: 7,
              proofProgress: 1,
            ),
            const VotingVoteKey(
              bundleIndex: 1,
              proposalId: 7,
            ): VotingSessionProgress(
              phase: VotingProgressPhase.completed,
              bundleIndex: 1,
              proposalId: 7,
              proofProgress: 1,
            ),
          },
          total: 1,
        ),
      );
      expect(bothDone.completedProposals, 1);
      expect(bothDone.stage, VotingBallotStage.complete);
    });

    test('uses concise casting copy while proving', () {
      final early = votingBallotProgress(
        _ballotState(
          voteProgress: _proving(total: 37, proven: 0, inFlight: 0.4),
          total: 37,
        ),
      );
      expect(early.detail, 'Casting votes');
      expect(early.fraction, greaterThan(0));

      final single = votingBallotProgress(
        _ballotState(voteProgress: _proving(total: 1, proven: 0), total: 1),
      );
      expect(single.detail, 'Casting votes');

      final submittingOne = votingBallotProgress(
        _ballotState(voteProgress: _proving(total: 1, proven: 1), total: 1),
      );
      expect(submittingOne.detail, isEmpty);
    });

    test('a proof in flight moves the ring between whole questions', () {
      final started = votingBallotProgress(
        _ballotState(voteProgress: _proving(total: 4, proven: 1), total: 4),
      );
      final halfway = votingBallotProgress(
        _ballotState(
          voteProgress: _proving(total: 4, proven: 1, inFlight: 0.5),
          total: 4,
        ),
      );
      expect(halfway.provenProposals, started.provenProposals);
      expect(halfway.fraction, greaterThan(started.fraction!));
    });

    test('reports nothing to count before the first vote event', () {
      final progress = votingBallotProgress(
        _ballotState(voteProgress: const {}, total: 37),
      );
      expect(progress.stage, VotingBallotStage.preparing);
      expect(progress.fraction, isNull);
      expect(progress.detail, 'Preparing your ballot');
    });

    test('names the chain and then the helpers once proving is done', () {
      final submitting = votingBallotProgress(
        _ballotState(voteProgress: _proving(total: 3, proven: 3), total: 3),
      );
      expect(submitting.stage, VotingBallotStage.submitting);
      expect(submitting.detail, isEmpty);

      final delivering = votingBallotProgress(
        _ballotState(
          voteProgress: {
            for (var proposalId = 1; proposalId <= 3; proposalId++)
              VotingVoteKey(
                bundleIndex: 0,
                proposalId: proposalId,
              ): VotingSessionProgress(
                phase: proposalId == 1
                    ? VotingProgressPhase.completed
                    : VotingProgressPhase.confirmed,
                bundleIndex: 0,
                proposalId: proposalId,
                proofProgress: 1,
              ),
          },
          total: 3,
        ),
      );
      expect(delivering.stage, VotingBallotStage.delivering);
      expect(delivering.detail, 'Responses for 1 of 3 questions delivered');
    });

    test('keeps a resumed run at the tally it inherited', () {
      // A resume never sees events for questions an earlier run finished, so
      // the tally stays the authority for how many are already done.
      final progress = votingBallotProgress(
        _ballotState(voteProgress: const {}, completed: 30, total: 37),
      );
      expect(progress.completedProposals, 30);
      expect(progress.fraction, closeTo(30 / 37, 1e-9));
    });

    test('a proposal is proven once the furthest bundle has proved it', () {
      // A proposal can be voted in several bundles, and the driver interleaves
      // them, so a bundle that starts late reports `proofStarting` for a
      // proposal another bundle already proved. Requiring every bundle to
      // agree let that late starter pull the proposal back out of the proven
      // set — the counter fell and the stage flipped from delivering back to
      // proving. The furthest bundle to report is what the counter reads.
      final progress = votingBallotProgress(
        _ballotState(
          voteProgress: {
            const VotingVoteKey(
              bundleIndex: 0,
              proposalId: 1,
            ): const VotingSessionProgress(
              phase: VotingProgressPhase.signing,
              bundleIndex: 0,
              proposalId: 1,
              proofProgress: 1,
            ),
            const VotingVoteKey(
              bundleIndex: 1,
              proposalId: 1,
            ): const VotingSessionProgress(
              phase: VotingProgressPhase.proofProgress,
              bundleIndex: 1,
              proposalId: 1,
              proofProgress: 0.4,
            ),
          },
          total: 1,
        ),
      );
      expect(progress.provenProposals, 1);
      expect(progress.stage, VotingBallotStage.submitting);
    });
  });

  group('votingAuthorityProgress', () {
    test('tracks the delegation proof, which is all this step does now', () {
      VotingSessionState state(double proofProgress) => VotingSessionState(
        roundId: 'round',
        phase: VotingSessionPhase.delegating,
        delegationProgress: {
          0: VotingSessionProgress(
            phase: VotingProgressPhase.proofProgress,
            bundleIndex: 0,
            proofProgress: proofProgress,
          ),
        },
      );

      expect(votingAuthorityProgress(state(0.2)).fraction, closeTo(0.18, 1e-9));
      expect(votingAuthorityProgress(state(0.9)).fraction, closeTo(0.81, 1e-9));
      // Nothing proved yet is nothing to count. The ring is the report.
      expect(votingAuthorityProgress(state(0.9)).detail, isNull);
      final proved = votingAuthorityProgress(state(1));
      expect(proved.provedBundles, 1);
      expect(proved.detail, 'Finalizing delegation — 1 of 1 bundles proved');
    });
  });

  group('VotingProgressRatchet', () {
    VotingBallotProgress ballot({
      VotingBallotStage stage = VotingBallotStage.proving,
      int proven = 0,
      int completed = 0,
      int total = 0,
      double? fraction,
    }) {
      return VotingBallotProgress(
        stage: stage,
        provenProposals: proven,
        completedProposals: completed,
        totalProposals: total,
        fraction: fraction,
      );
    }

    VotingAuthorityProgress authority({
      int proved = 0,
      int total = 0,
      double? fraction,
    }) {
      return VotingAuthorityProgress(
        provedBundles: proved,
        totalBundles: total,
        fraction: fraction,
      );
    }

    VotingProgressView advance(
      VotingProgressRatchet ratchet, {
      VotingSubmissionProgressStep step =
          VotingSubmissionProgressStep.castingVotes,
      VotingAuthorityProgress? authorityProgress,
      VotingBallotProgress? ballotProgress,
    }) {
      return ratchet.advance(
        step: step,
        authority: authorityProgress ?? authority(),
        ballot: ballotProgress ?? ballot(),
      );
    }

    test('holds the ballot denominator through a run-scoped tally', () {
      // The SDK tally measures one run against what that run started owing. A
      // round is driven by two runs, so the second owes less — "of 37" came
      // back as "of 12", and briefly as nothing at all.
      final ratchet = VotingProgressRatchet();
      advance(
        ratchet,
        ballotProgress: ballot(proven: 20, total: 37, fraction: 0.5),
      );
      final collapsed = advance(
        ratchet,
        ballotProgress: ballot(total: 0, fraction: null),
      );
      expect(collapsed.ballot.totalProposals, 37);
      expect(collapsed.ballot.provenProposals, 20);
      final shrunk = advance(
        ratchet,
        ballotProgress: ballot(proven: 5, total: 12, fraction: 0.4),
      );
      expect(shrunk.ballot.totalProposals, 37);
      expect(shrunk.ballot.provenProposals, 20);
      expect(shrunk.ballot.detail, 'Casting votes');
    });

    test('never sends the step list backwards', () {
      // A sibling bundle owing a signature, a plan refresh naming `delegate`,
      // a wallet-sync pause: all of them reported a pre-vote phase while a
      // vote was in flight.
      final ratchet = VotingProgressRatchet();
      advance(ratchet, step: VotingSubmissionProgressStep.castingVotes);
      final back = advance(
        ratchet,
        step: VotingSubmissionProgressStep.provingAuthority,
      );
      expect(back.step, VotingSubmissionProgressStep.castingVotes);
      final forward = advance(
        ratchet,
        step: VotingSubmissionProgressStep.finalizing,
      );
      expect(forward.step, VotingSubmissionProgressStep.finalizing);
    });

    test('never sends the ballot stage backwards', () {
      final ratchet = VotingProgressRatchet();
      advance(
        ratchet,
        ballotProgress: ballot(
          stage: VotingBallotStage.delivering,
          proven: 3,
          completed: 1,
          total: 3,
          fraction: 0.8,
        ),
      );
      final back = advance(
        ratchet,
        ballotProgress: ballot(
          stage: VotingBallotStage.proving,
          proven: 1,
          completed: 0,
          total: 3,
          fraction: 0.3,
        ),
      );
      expect(back.ballot.stage, VotingBallotStage.delivering);
      expect(back.ballot.detail, 'Responses for 1 of 3 questions delivered');
      expect(back.ballot.fraction, 0.8);
    });

    test('holds the ring, and keeps the ends indeterminate', () {
      final ratchet = VotingProgressRatchet();
      // Nothing measured yet: indeterminate is the honest answer.
      expect(
        advance(
          ratchet,
          ballotProgress: ballot(stage: VotingBallotStage.preparing),
        ).ballot.fraction,
        isNull,
      );
      advance(
        ratchet,
        ballotProgress: ballot(proven: 2, total: 4, fraction: 0.6),
      );
      // Mid-run, an indeterminate value is a regression, not a fresh start.
      expect(
        advance(
          ratchet,
          ballotProgress: ballot(proven: 2, total: 4, fraction: null),
        ).ballot.fraction,
        0.6,
      );
      expect(
        advance(
          ratchet,
          ballotProgress: ballot(proven: 1, total: 4, fraction: 0.3),
        ).ballot.fraction,
        0.6,
      );
    });

    test('lets the delegation ring go indeterminate once it is finalizing', () {
      // `votingAuthorityProgress` reports null to keep the ring animating
      // while the round driver finishes work it cannot measure. That is the
      // end of the step, not a regression.
      final ratchet = VotingProgressRatchet();
      advance(
        ratchet,
        authorityProgress: authority(proved: 1, total: 2, fraction: 0.9),
      );
      final finalizing = advance(
        ratchet,
        authorityProgress: authority(proved: 2, total: 2, fraction: null),
      );
      expect(finalizing.authority.fraction, isNull);
      expect(
        finalizing.authority.detail,
        'Finalizing delegation — 2 of 2 bundles proved',
      );
    });

    test('the ring resumes from its mark after an indeterminate frame', () {
      // `votingAuthorityProgress` reports null once every known bundle has
      // settled. If a later plan adds a bundle, the step is measurable again —
      // and it has to resume where the ring was, not from a spinner.
      final ratchet = VotingProgressRatchet();
      advance(
        ratchet,
        authorityProgress: authority(proved: 2, total: 2, fraction: 0.9),
      );
      expect(
        advance(
          ratchet,
          authorityProgress: authority(proved: 2, total: 2, fraction: null),
        ).authority.fraction,
        isNull,
      );
      final resumed = advance(
        ratchet,
        authorityProgress: authority(proved: 2, total: 3, fraction: 0.6),
      );
      expect(resumed.authority.fraction, 0.9);
      expect(resumed.authority.detail, '2 of 3 bundles proved');
    });

    test('clamps a latched count to the denominator it is shown against', () {
      final ratchet = VotingProgressRatchet();
      advance(
        ratchet,
        ballotProgress: ballot(proven: 9, completed: 9, total: 9),
      );
      final view = advance(
        ratchet,
        ballotProgress: ballot(proven: 2, completed: 1, total: 9),
      );
      expect(view.ballot.completedProposals, lessThanOrEqualTo(9));
      expect(view.ballot.provenProposals, 9);
    });

    test('held repeats the last mark, and reset forgets it', () {
      // The session provider refreshes through its loading state, so the
      // status screen gets frames with no projection to fold. It repeats this
      // rather than falling back to the first step.
      final ratchet = VotingProgressRatchet();
      expect(ratchet.held, isNull);
      final view = advance(
        ratchet,
        step: VotingSubmissionProgressStep.castingVotes,
        ballotProgress: ballot(
          proven: 3,
          completed: 1,
          total: 3,
          fraction: 0.7,
        ),
      );
      expect(ratchet.held?.step, view.step);
      expect(ratchet.held?.ballot.detail, view.ballot.detail);
      ratchet.reset();
      expect(ratchet.held, isNull);
    });

    test('reset starts the next attempt from nothing', () {
      final ratchet = VotingProgressRatchet();
      advance(
        ratchet,
        step: VotingSubmissionProgressStep.finalizing,
        ballotProgress: ballot(proven: 4, completed: 4, total: 4, fraction: 1),
      );
      ratchet.reset();
      final fresh = advance(
        ratchet,
        step: VotingSubmissionProgressStep.provingAuthority,
        ballotProgress: ballot(total: 0),
      );
      expect(fresh.step, VotingSubmissionProgressStep.provingAuthority);
      expect(fresh.ballot.totalProposals, 0);
      expect(fresh.ballot.completedProposals, 0);
    });
  });
}
