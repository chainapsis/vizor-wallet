import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/voting_progress_presentation.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/features/voting/voting_resume_plan.dart';
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;

import 'round_plan_test_utils.dart';

/// A session mid-ballot.
///
/// [voteStepBundles] scripts the bundles the plan still owes a cast for, which
/// is how the plan names a bundle the run has not reached yet. It is separate
/// from [bundleCount] on purpose: an eligible bundle that never votes — a
/// terminal delegation — is in the round's bundle count and in no vote step.
VotingSessionState _ballotState({
  required Map<VotingVoteKey, VotingSessionProgress> voteProgress,
  int completed = 0,
  int total = 0,
  int? bundleCount,
  List<int> voteStepBundles = const [],
}) {
  return VotingSessionState(
    roundId: 'round',
    phase: VotingSessionPhase.castingVotes,
    voteProgress: voteProgress,
    voteSubmissionCompletedCount: completed,
    voteSubmissionTotalCount: total,
    roundPlan: bundleCount == null
        ? null
        : apiRoundPlan(
            roundId: 'round',
            pendingRecovery: true,
            nextSteps: [
              for (final bundleIndex in voteStepBundles)
                rust_wire.NextStepView(
                  kind: rust_wire.NextStepKind.castVote,
                  bundleIndex: bundleIndex,
                  proposalId: 7,
                  choice: 1,
                  shareIndex: 0,
                ),
            ],
            openProposals: Uint32List(0),
            allDecided: false,
            needsDraftSetup: false,
            bundleCount: bundleCount,
          ),
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

    test('a sibling bundle the run has not reached yet is unfinished', () {
      // Entries appear only as the driver reports on them, so a bundle selected
      // second is absent rather than pending. Judging the question on the
      // entries present would call it finished on the first bundle again — and
      // the ratcheted UI would advance to finalizing for good.
      final firstBundleOnly = votingBallotProgress(
        _ballotState(
          bundleCount: 2,
          voteStepBundles: const [0, 1],
          voteProgress: {
            const VotingVoteKey(
              bundleIndex: 0,
              proposalId: 7,
            ): const VotingSessionProgress(
              phase: VotingProgressPhase.completed,
              bundleIndex: 0,
              proposalId: 7,
              proofProgress: 1,
            ),
          },
          total: 1,
        ),
      );
      expect(firstBundleOnly.completedProposals, 0);
      expect(firstBundleOnly.stage, isNot(VotingBallotStage.complete));

      final bothBundles = votingBallotProgress(
        _ballotState(
          bundleCount: 2,
          voteStepBundles: const [0, 1],
          voteProgress: {
            const VotingVoteKey(
              bundleIndex: 0,
              proposalId: 7,
            ): const VotingSessionProgress(
              phase: VotingProgressPhase.completed,
              bundleIndex: 0,
              proposalId: 7,
              proofProgress: 1,
            ),
            const VotingVoteKey(
              bundleIndex: 1,
              proposalId: 7,
            ): const VotingSessionProgress(
              phase: VotingProgressPhase.completed,
              bundleIndex: 1,
              proposalId: 7,
              proofProgress: 1,
            ),
          },
          total: 1,
        ),
      );
      expect(bothBundles.completedProposals, 1);
      expect(bothBundles.stage, VotingBallotStage.complete);
    });

    test('an eligible bundle that never votes is not one to wait for', () {
      // Two eligible bundles, but the plan casts in one: the other's
      // delegation ended without confirming, so the planner plans no vote step
      // for it and no question can ever be delivered there. Dividing by the
      // round's bundle count instead of the bundles that carry the ballot made
      // every question permanently unfinished, so the delivered count sat at
      // zero for the whole delivery and only the SDK tally — which moves once,
      // at the end — ever advanced it.
      final delivered = votingBallotProgress(
        _ballotState(
          bundleCount: 2,
          voteStepBundles: const [0],
          voteProgress: {
            const VotingVoteKey(
              bundleIndex: 0,
              proposalId: 7,
            ): const VotingSessionProgress(
              phase: VotingProgressPhase.completed,
              bundleIndex: 0,
              proposalId: 7,
              proofProgress: 1,
            ),
          },
          total: 1,
        ),
      );
      expect(delivered.completedProposals, 1);
      expect(delivered.stage, VotingBallotStage.complete);
    });

    test('counts the delivered questions of the bundle being delivered', () {
      // Two questions in one bundle, one share batch landed: the line has to
      // move as each batch finishes rather than waiting for the step.
      final state = _ballotState(
        bundleCount: 1,
        voteStepBundles: const [0],
        voteProgress: {
          const VotingVoteKey(
            bundleIndex: 0,
            proposalId: 7,
          ): const VotingSessionProgress(
            phase: VotingProgressPhase.completed,
            bundleIndex: 0,
            proposalId: 7,
            proofProgress: 1,
          ),
          const VotingVoteKey(
            bundleIndex: 0,
            proposalId: 8,
          ): const VotingSessionProgress(
            phase: VotingProgressPhase.confirmed,
            bundleIndex: 0,
            proposalId: 8,
            proofProgress: 1,
          ),
        },
        total: 2,
      );
      expect(votingBallotCarryingBundleCount(state), 1);
      final delivering = votingBallotProgress(state);
      expect(delivering.stage, VotingBallotStage.delivering);
      expect(delivering.completedProposals, 1);
      expect(delivering.detail, 'Responses for 1 of 2 questions delivered');
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

      // The SDK makes each vote's helper plan durable before it broadcasts, so
      // this — the first per-vote event after proving — is the wallet waiting
      // out a whole chain episode. Reporting it as delivery left the delivered
      // count truthfully at zero for the entire wait and then jumping to done.
      final confirming = votingBallotProgress(
        _ballotState(
          voteProgress: {
            for (var proposalId = 1; proposalId <= 3; proposalId++)
              VotingVoteKey(
                bundleIndex: 0,
                proposalId: proposalId,
              ): VotingSessionProgress(
                phase: VotingProgressPhase.submitting,
                bundleIndex: 0,
                proposalId: proposalId,
                proofProgress: 1,
              ),
          },
          total: 3,
        ),
      );
      expect(confirming.stage, VotingBallotStage.confirming);
      expect(confirming.detail, 'Waiting for chain confirmation');

      // On the wire and still unconfirmed is the same wait.
      final onWire = votingBallotProgress(
        _ballotState(
          voteProgress: {
            for (var proposalId = 1; proposalId <= 3; proposalId++)
              VotingVoteKey(
                bundleIndex: 0,
                proposalId: proposalId,
              ): VotingSessionProgress(
                phase: VotingProgressPhase.submitted,
                bundleIndex: 0,
                proposalId: proposalId,
                proofProgress: 1,
              ),
          },
          total: 3,
        ),
      );
      expect(onWire.stage, VotingBallotStage.confirming);

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

  group('VotingBallotCountPacer', () {
    VotingBallotProgress delivering(int completed, {int total = 37}) {
      return VotingBallotProgress(
        stage: VotingBallotStage.delivering,
        provenProposals: total,
        completedProposals: completed,
        totalProposals: total,
        fraction: completed / total,
      );
    }

    /// Every count the pacer shows walking to [target], first frame included.
    List<int> walk(VotingBallotCountPacer pacer, int target) {
      final shown = <int>[pacer.pace(delivering(target)).completedProposals];
      var frames = 0;
      while (pacer.isCatchingUp && frames++ < 200) {
        shown.add(pacer.pace(delivering(target)).completedProposals);
      }
      return shown;
    }

    test('walks up to a wave instead of landing on it', () {
      // Shares go out 50 at a time, so a batch of questions finishes together
      // and the reported count steps by twenty at once.
      final shown = walk(VotingBallotCountPacer(), 20);
      expect(shown.first, greaterThan(0));
      expect(shown.first, lessThan(20));
      expect(shown.last, 20);
      // Enough frames to read as movement, few enough to keep up with a round
      // that is already finishing.
      expect(shown.length, inInclusiveRange(4, 16));
      expect(shown, orderedEquals(shown.toList()..sort()));
      expect(shown.every((count) => count <= 20), isTrue);
    });

    test('the line it yields reads from the count it is showing', () {
      final pacer = VotingBallotCountPacer();
      final first = pacer.pace(delivering(20));
      expect(
        first.detail,
        'Responses for ${first.completedProposals} of 37 questions delivered',
      );
      // The rest of the projection is untouched: only the count is paced.
      expect(first.stage, VotingBallotStage.delivering);
      expect(first.totalProposals, 37);
      expect(first.fraction, closeTo(20 / 37, 1e-9));
    });

    test('a settled count asks for no further frames', () {
      final pacer = VotingBallotCountPacer();
      walk(pacer, 5);
      expect(pacer.isCatchingUp, isFalse);
      expect(pacer.pace(delivering(5)).completedProposals, 5);
      expect(pacer.isCatchingUp, isFalse);
    });

    const finished = VotingBallotProgress(
      stage: VotingBallotStage.complete,
      provenProposals: 37,
      completedProposals: 37,
      totalProposals: 37,
      fraction: 1,
    );

    test('a ballot that finishes mid-walk keeps delivering until it lands', () {
      // The submission job completes the moment the last share is accepted, so
      // a fast delivery reported its whole count and completed within a frame
      // or two of each other. Dropping the line there is the flash: the voter
      // saw a count appear and vanish. The row ticks a few frames later.
      final pacer = VotingBallotCountPacer();
      pacer.pace(delivering(2));
      final held = pacer.pace(finished);
      expect(held.stage, VotingBallotStage.delivering);
      expect(held.completedProposals, lessThan(37));
      expect(pacer.isCatchingUp, isTrue);

      var frames = 0;
      var shown = held;
      final delivered = <int>[];
      while (pacer.isCatchingUp && frames++ < 60) {
        if (shown.stage == VotingBallotStage.delivering) {
          delivered.add(shown.completedProposals);
        }
        shown = pacer.pace(finished);
      }
      expect(shown.stage, VotingBallotStage.complete);
      expect(shown.completedProposals, 37);
      expect(frames, lessThan(pacer.maxCompletionHoldFrames));
      // The finished count stands for a few frames before the row ticks:
      // "37 of 37 delivered" is the one number worth reading, and ticking on
      // the frame it lands is the one frame that never draws it.
      expect(delivered.last, 37);
      expect(
        delivered.where((count) => count == 37).length,
        greaterThanOrEqualTo(pacer.landedDwellFrames),
      );
    });

    test('the completion hold is bounded', () {
      // Whatever the walk does, a caller that waits for it — the status screen
      // holds the confirmation hand-off — must not be made to wait forever.
      const manyFinished = VotingBallotProgress(
        stage: VotingBallotStage.complete,
        provenProposals: 1000,
        completedProposals: 1000,
        totalProposals: 1000,
        fraction: 1,
      );
      // A pacer that advances one question per frame cannot walk a thousand of
      // them in three, and the hold is what stops it trying.
      final pacer = VotingBallotCountPacer(
        catchUpFraction: 0,
        maxCompletionHoldFrames: 3,
      );
      pacer.pace(delivering(1000, total: 1000));
      var frames = 0;
      while (pacer.isCatchingUp && frames++ < 100) {
        pacer.pace(manyFinished);
      }
      expect(frames, lessThanOrEqualTo(4));
      expect(pacer.isCatchingUp, isFalse);
    });

    test('a round that arrives finished is not given a walk', () {
      // A resume or a revisit never watched a delivery, so animating one would
      // show this screen counting work it did not see.
      final pacer = VotingBallotCountPacer();
      final complete = pacer.pace(finished);
      expect(complete.stage, VotingBallotStage.complete);
      expect(complete.completedProposals, 37);
      expect(pacer.isCatchingUp, isFalse);
    });

    test('reset starts the next attempt from the count it is given', () {
      final pacer = VotingBallotCountPacer();
      walk(pacer, 20);
      pacer.reset();
      // A retry reports fewer done than the attempt that failed had shown; the
      // walk must not treat that as a count it has already passed.
      final resumed = pacer.pace(delivering(8));
      expect(resumed.completedProposals, lessThan(8));
      expect(pacer.isCatchingUp, isTrue);
      expect(walk(pacer, 8).last, 8);
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
