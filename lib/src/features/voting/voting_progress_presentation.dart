import 'package:flutter/foundation.dart';

import '../../providers/voting/voting_state.dart';
import 'voting_resume_plan.dart';

/// Progress projections for the submission status screens.
///
/// The SDK now runs a fresh round as two long pieces of work: a delegation
/// proof on its own, then one combined envelope that reuses that proof, proves
/// every chosen vote, submits them together, and delivers their shares. Both
/// pieces are a single planner step, so the round tally cannot move inside
/// either one — it counts finished obligations, and there is exactly one.
///
/// These projections read the per-bundle and per-proposal events the SDK does
/// emit inside a step, so the two long stages report what they are actually
/// doing instead of sitting at zero until they land.
///
/// A projection alone is not enough to show a voter, because the state it
/// reads legitimately moves backwards: the SDK tally is scoped to one run and
/// recomputed from scratch on every refresh, bundles are driven concurrently
/// and interleave, and a step re-dispatched after a repoll reports from the
/// beginning again. [VotingProgressRatchet] holds the high-water mark so none
/// of that reaches the screen.

/// The three rows of the submission progress screens, in order.
///
/// Lives here rather than with the screens because the ratchet compares them
/// by index, and both the desktop and mobile screens read the result.
enum VotingSubmissionProgressStep { provingAuthority, castingVotes, finalizing }

/// How far the delegation proof for this round has come.
class VotingAuthorityProgress {
  const VotingAuthorityProgress({
    required this.provedBundles,
    required this.totalBundles,
    required this.fraction,
    this.reusingProof = false,
    this.awaitingChain = false,
  });

  /// Bundles whose delegation proof has finished.
  final int provedBundles;

  final int totalBundles;

  /// Value for the step's progress ring, or null to keep it indeterminate
  /// while work the projection cannot measure finishes.
  final double? fraction;

  /// A bundle is riding along on a proof another run already started.
  final bool reusingProof;

  /// A bundle has left the wallet and is waiting on the chain.
  final bool awaitingChain;

  /// The line under the step label.
  ///
  /// Derived from the counts rather than stored, so a ratcheted copy of this
  /// projection describes the counts it actually shows.
  String? get detail {
    if (totalBundles <= 0) return null;
    // Same rule as the ballot line: the count appears once it has left zero.
    // A bundle only counts as proved when its whole proof lands, so until the
    // first one does there is nothing to report but a zero, and a round with
    // one bundle — the common one — would sit on `0 of 1 bundles proved` for
    // the entire proof. The ring carries that proof's progress meanwhile.
    final count = provedBundles > 0
        ? '$provedBundles of $totalBundles bundles proved'
        : null;
    final suffix = count == null ? '' : ' — $count';
    if (provedBundles >= totalBundles) {
      // A finished proof still owes signing and, on the recovery paths that
      // still submit separately, a chain episode. Keep the ring animating.
      return awaitingChain
          ? 'Waiting for submission and confirmation$suffix'
          : 'Finalizing delegation$suffix';
    }
    if (reusingProof) return 'Reusing an in-progress proof$suffix';
    if (awaitingChain) return 'Waiting for submission and confirmation$suffix';
    return count;
  }
}

/// What the combined cast-and-submit envelope is doing right now.
///
/// Declared in forward order: the ratchet compares these by index, so a new
/// stage has to be inserted at the point of the pipeline it describes.
enum VotingBallotStage {
  /// The run has not reported anything about an individual vote yet.
  preparing,

  /// Vote proofs are being built. This is the long one.
  proving,

  /// Every proof is built; the envelope is going to the chain.
  submitting,

  /// The chain has the votes; helper shares are going out.
  delivering,

  complete,
}

/// How far the ballot has come, measured per proposal.
class VotingBallotProgress {
  const VotingBallotProgress({
    required this.stage,
    required this.provenProposals,
    required this.completedProposals,
    required this.totalProposals,
    required this.fraction,
  });

  final VotingBallotStage stage;

  /// Proposals whose vote proof has finished in the furthest bundle to report
  /// one.
  final int provenProposals;

  /// Proposals whose whole pipeline, shares included, has finished.
  final int completedProposals;

  final int totalProposals;

  final double? fraction;

  /// The line under the step label.
  ///
  /// Proving uses concise copy while the progress ring communicates movement.
  /// Delivery reports completed questions because that count advances as
  /// shares finish.
  String? get detail {
    if (totalProposals <= 0) return null;
    return switch (stage) {
      VotingBallotStage.preparing => 'Preparing your ballot',
      VotingBallotStage.proving => 'Casting votes',
      VotingBallotStage.submitting => '',
      VotingBallotStage.delivering =>
        'Responses for $completedProposals of $totalProposals questions delivered',
      VotingBallotStage.complete => null,
    };
  }
}

/// Bundle indexes this round still owes delegation work for.
///
/// Restricted to the bundles the live plan knows about. `delegationProgress`
/// is never cleared, so a superseded bundle layout would otherwise leave keys
/// behind that permanently inflate the denominator.
List<int> votingAuthorityBundleIndexes(VotingSessionState state) {
  final bundleCount = roundPlanBundleCount(state.roundPlan);
  final indexes = <int>{
    ...delegationBundleIndexesNeedingWork(state.roundPlan),
    ...state.delegationProgress.keys,
    ?state.currentBundleIndex,
  };
  final known = bundleCount > 0
      ? indexes.where((index) => index >= 0 && index < bundleCount)
      : indexes;
  return known.toList()..sort();
}

/// Projects the delegation step from its per-bundle progress events.
VotingAuthorityProgress votingAuthorityProgress(VotingSessionState state) {
  final bundleIndexes = votingAuthorityBundleIndexes(state);
  if (bundleIndexes.isEmpty) {
    return const VotingAuthorityProgress(
      provedBundles: 0,
      totalBundles: 0,
      fraction: null,
    );
  }

  var fractionSum = 0.0;
  var proved = 0;
  var settled = 0;
  var waiting = false;
  var awaitingChain = false;
  for (final bundleIndex in bundleIndexes) {
    final progress = state.delegationProgress[bundleIndex];
    final fraction = _authorityBundleFraction(progress);
    fractionSum += fraction;
    if (fraction >= 1) settled += 1;
    if (_authorityBundleProved(progress)) proved += 1;
    if (progress?.phase == VotingProgressPhase.waitingForExistingProof) {
      waiting = true;
    }
    if (progress?.phase == VotingProgressPhase.payloadReady ||
        progress?.phase == VotingProgressPhase.submitted) {
      awaitingChain = true;
    }
  }

  final total = bundleIndexes.length;
  return VotingAuthorityProgress(
    provedBundles: proved,
    totalBundles: total,
    // Only a bundle that has nothing left to report reaches the end of the
    // ring. Once every one has, keep animating while the round driver
    // finishes and refreshes its plan.
    fraction: settled == total ? null : (fractionSum / total).clamp(0.0, 1.0),
    reusingProof: waiting,
    awaitingChain: awaitingChain,
  );
}

/// Projects the ballot step from the SDK tally and its per-proposal events.
///
/// The tally is the authority for how many questions the run owes and how many
/// it has fully finished; it cannot see inside the combined envelope, so the
/// per-proposal vote events carry everything that happens between those two
/// numbers.
///
/// A proposal can be voted in several bundles at once, and the driver
/// interleaves them, so each proposal is described by the *furthest* bundle to
/// report on it. Requiring every bundle to agree would let a late-starting
/// sibling drag a proposal back out of the proven set.
VotingBallotProgress votingBallotProgress(
  VotingSessionState state, {
  bool completedSubmission = false,
}) {
  final byProposal = <int, VotingSessionProgress>{};
  final fractionByProposal = <int, double>{};
  for (final entry in state.voteProgress.entries) {
    final proposalId = entry.key.proposalId;
    final furthest = byProposal[proposalId];
    if (furthest == null ||
        voteProgressPhaseRank(entry.value.phase) >
            voteProgressPhaseRank(furthest.phase)) {
      byProposal[proposalId] = entry.value;
    }
    final fraction = _voteEntryFraction(entry.value);
    final storedFraction = fractionByProposal[proposalId];
    if (storedFraction == null || fraction > storedFraction) {
      fractionByProposal[proposalId] = fraction;
    }
  }

  final tallyTotal = state.voteSubmissionTotalCount;
  final total = tallyTotal > 0 ? tallyTotal : byProposal.length;
  final tallyCompleted = state.voteSubmissionCompletedCount.clamp(0, total);

  if (completedSubmission) {
    return VotingBallotProgress(
      stage: VotingBallotStage.complete,
      provenProposals: total,
      completedProposals: total,
      totalProposals: total,
      fraction: 1,
    );
  }

  var proven = 0;
  var finished = 0;
  var dispatched = false;
  var fractionSum = 0.0;
  for (final entry in byProposal.entries) {
    final progress = entry.value;
    if (_voteEntryProven(progress)) proven += 1;
    if (progress.phase == VotingProgressPhase.completed) finished += 1;
    if (_voteEntryDispatched(progress)) dispatched = true;
    fractionSum += fractionByProposal[entry.key] ?? 0;
  }

  if (total <= 0) {
    return const VotingBallotProgress(
      stage: VotingBallotStage.preparing,
      provenProposals: 0,
      completedProposals: 0,
      totalProposals: 0,
      fraction: null,
    );
  }

  // A resumed run inherits questions this run never saw an event for, so the
  // tally can be ahead of what the per-proposal map knows. The map can also be
  // ahead of the tally, because it is never cleared and carries keys from an
  // earlier attempt — so the count is clamped to what this round actually
  // owes, or a stale key would report the ballot finished early.
  final completed = (finished > tallyCompleted ? finished : tallyCompleted)
      .clamp(0, total);
  proven = proven.clamp(0, total);

  final VotingBallotStage stage;
  if (completed >= total) {
    stage = VotingBallotStage.complete;
  } else if (byProposal.isEmpty && completed == 0) {
    stage = VotingBallotStage.preparing;
  } else if (proven < total) {
    stage = VotingBallotStage.proving;
  } else if (dispatched) {
    stage = VotingBallotStage.delivering;
  } else {
    stage = VotingBallotStage.submitting;
  }

  final measured =
      (fractionSum + (completed - finished).clamp(0, total)) / total;
  final tallyFraction = completed / total;
  final fraction = (measured > tallyFraction ? measured : tallyFraction).clamp(
    0.0,
    1.0,
  );

  return VotingBallotProgress(
    stage: stage,
    provenProposals: proven,
    completedProposals: completed,
    totalProposals: total,
    fraction: stage == VotingBallotStage.preparing ? null : fraction,
  );
}

/// One frame of submission progress, after the ratchet has held it forward.
class VotingProgressView {
  const VotingProgressView({
    required this.step,
    required this.authority,
    required this.ballot,
  });

  final VotingSubmissionProgressStep step;
  final VotingAuthorityProgress authority;
  final VotingBallotProgress ballot;

  /// Whether the ballot row is finished, so the screens can tick it and stop
  /// drawing its ring.
  bool get ballotComplete => ballot.stage == VotingBallotStage.complete;

  /// The delegation row's projection, or null before it has anything to say.
  VotingAuthorityProgress? get authorityOrNull =>
      authority.totalBundles > 0 ? authority : null;
}

/// Holds the furthest point a round's submission has reached.
///
/// The session state is the machine's truth and it legitimately moves
/// backwards. The SDK tally is scoped to one run and recomputed from scratch,
/// so its numerator can fall mid-run and its denominator shrinks when a second
/// run starts owing less than the first. Bundles are driven concurrently, so
/// events for one proposal arrive out of order across them. A step
/// re-dispatched after a repoll reports from the beginning. And several
/// unrelated writers move the session phase back to a pre-vote value while a
/// vote is in flight — a sibling bundle still owing a signature, a plan
/// refresh, a wallet-sync pause, background share tracking.
///
/// None of that is progress the voter lost, so the UI shows the high-water
/// mark instead. One ratchet covers one round: call [reset] when the round or
/// account changes, or when the voter retries.
class VotingProgressRatchet {
  VotingSubmissionProgressStep? _step;

  int _provedBundles = 0;
  int _totalBundles = 0;

  /// Largest ring value the delegation step has reported, or null while it has
  /// reported none. Kept even across a frame that shows an indeterminate ring,
  /// so a later determinate frame resumes from it.
  double? _authorityFractionMax;

  VotingBallotStage? _stage;
  int _provenProposals = 0;
  int _completedProposals = 0;
  int _totalProposals = 0;
  double? _ballotFractionMax;

  /// Regressions reported by the previous [advance], so one that persists
  /// across many rebuilds is logged once rather than every frame. A regression
  /// that stops and returns is logged again, which is worth knowing.
  Set<String> _loggedRegressions = const {};
  Set<String> _frameRegressions = {};

  VotingProgressView? _held;

  /// The mark as it stands, or null before the first [advance].
  ///
  /// For frames that have no projection to fold — the session provider
  /// refreshing, so the screen is momentarily back to `loading` — showing this
  /// is what keeps the step list still instead of snapping to the first row.
  VotingProgressView? get held => _held;

  /// Forgets everything. The next [advance] starts a fresh high-water mark.
  void reset() {
    _step = null;
    _provedBundles = 0;
    _totalBundles = 0;
    _authorityFractionMax = null;
    _stage = null;
    _provenProposals = 0;
    _completedProposals = 0;
    _totalProposals = 0;
    _ballotFractionMax = null;
    _loggedRegressions = const {};
    _frameRegressions = {};
    _held = null;
  }

  /// Folds this frame's projections into the high-water mark and returns it.
  VotingProgressView advance({
    required VotingSubmissionProgressStep step,
    required VotingAuthorityProgress authority,
    required VotingBallotProgress ballot,
  }) {
    _frameRegressions = <String>{};
    final storedStep = _step;
    if (storedStep == null || step.index > storedStep.index) {
      _step = step;
    } else if (step.index < storedStep.index) {
      _logRegression('step', step.name, storedStep.name);
    }
    final view = VotingProgressView(
      step: _step ?? step,
      authority: _advanceAuthority(authority),
      ballot: _advanceBallot(ballot),
    );
    _loggedRegressions = _frameRegressions;
    return _held = view;
  }

  VotingAuthorityProgress _advanceAuthority(VotingAuthorityProgress authority) {
    _totalBundles = _advanceTotal(
      stored: _totalBundles,
      incoming: authority.totalBundles,
      label: 'authority total',
    );
    _provedBundles = _advanceCount(
      stored: _provedBundles,
      incoming: authority.provedBundles,
      total: _totalBundles,
      label: 'bundles proved',
    );
    _authorityFractionMax = _advanceFraction(
      stored: _authorityFractionMax,
      incoming: authority.fraction,
      label: 'authority ring',
    );
    return VotingAuthorityProgress(
      provedBundles: _provedBundles,
      totalBundles: _totalBundles,
      // Every bundle proved and nothing measurable left is the step finishing
      // work the projection cannot see, not a ring that fell over.
      fraction: _ringFor(
        _authorityFractionMax,
        incoming: authority.fraction,
        indeterminateAllowed:
            _totalBundles > 0 && _provedBundles >= _totalBundles,
      ),
      reusingProof: authority.reusingProof,
      awaitingChain: authority.awaitingChain,
    );
  }

  VotingBallotProgress _advanceBallot(VotingBallotProgress ballot) {
    _totalProposals = _advanceTotal(
      stored: _totalProposals,
      incoming: ballot.totalProposals,
      label: 'ballot total',
    );
    _provenProposals = _advanceCount(
      stored: _provenProposals,
      incoming: ballot.provenProposals,
      total: _totalProposals,
      label: 'votes proven',
    );
    _completedProposals = _advanceCount(
      stored: _completedProposals,
      incoming: ballot.completedProposals,
      total: _totalProposals,
      label: 'votes completed',
    );
    final storedStage = _stage;
    if (storedStage == null || ballot.stage.index > storedStage.index) {
      _stage = ballot.stage;
    } else if (ballot.stage.index < storedStage.index) {
      _logRegression('ballot stage', ballot.stage.name, storedStage.name);
    }
    _ballotFractionMax = _advanceFraction(
      stored: _ballotFractionMax,
      incoming: ballot.fraction,
      label: 'ballot ring',
    );
    final stage = _stage ?? ballot.stage;
    final complete = stage == VotingBallotStage.complete;
    return VotingBallotProgress(
      stage: stage,
      provenProposals: complete ? _totalProposals : _provenProposals,
      completedProposals: complete ? _totalProposals : _completedProposals,
      totalProposals: _totalProposals,
      fraction: complete
          ? 1
          : _ringFor(
              _ballotFractionMax,
              incoming: ballot.fraction,
              // Nothing has been reported per proposal yet, so there is
              // genuinely nothing to measure.
              indeterminateAllowed: stage == VotingBallotStage.preparing,
            ),
    );
  }

  /// Holds a denominator forward.
  ///
  /// A total that collapses to zero is a run that has not reported its
  /// baseline yet, not a round that stopped owing anything. A total that
  /// merely shrinks is a second run measuring itself rather than the round.
  int _advanceTotal({
    required int stored,
    required int incoming,
    required String label,
  }) {
    if (incoming > stored) return incoming;
    if (incoming > 0 && incoming < stored) {
      _logRegression(label, '$incoming', '$stored');
    }
    return stored;
  }

  int _advanceCount({
    required int stored,
    required int incoming,
    required int total,
    required String label,
  }) {
    if (incoming < stored) _logRegression(label, '$incoming', '$stored');
    final held = incoming > stored ? incoming : stored;
    return total > 0 ? held.clamp(0, total) : held;
  }

  /// The largest ring value this step has reported.
  ///
  /// Kept whatever the frame shows, so a determinate frame after an
  /// indeterminate one resumes where the ring was rather than from nothing.
  double? _advanceFraction({
    required double? stored,
    required double? incoming,
    required String label,
  }) {
    if (incoming == null) return stored;
    if (stored == null || incoming > stored) return incoming;
    if (incoming < stored) {
      _logRegression(
        label,
        incoming.toStringAsFixed(3),
        stored.toStringAsFixed(3),
      );
    }
    return stored;
  }

  /// What to draw for a ring whose high-water mark is [max].
  ///
  /// An indeterminate ring means two different things depending on where the
  /// step is: "nothing measurable yet" at the start, and "finishing work this
  /// projection cannot measure" at the end. Both are honest and pass through.
  /// An indeterminate value anywhere in between is a regression, and the ring
  /// holds its mark instead of resetting to a spinner.
  double? _ringFor(
    double? max, {
    required double? incoming,
    required bool indeterminateAllowed,
  }) {
    if (incoming == null && indeterminateAllowed) return null;
    return max;
  }

  /// Reports one suppressed regression, at most once while it persists.
  ///
  /// This runs inside build, and a regression usually stands for many frames,
  /// so repeating it would bury the rest of the log. Every distinct regression
  /// in a frame is still reported — several can happen at once.
  void _logRegression(String what, String incoming, String held) {
    final message =
        '[zcash] Voting: progress regression suppressed '
        '$what incoming=$incoming held=$held';
    _frameRegressions.add(message);
    if (_loggedRegressions.contains(message)) return;
    debugPrint(message);
  }
}

double _authorityBundleFraction(VotingSessionProgress? progress) {
  if (progress == null) return 0;
  return switch (progress.phase) {
    VotingProgressPhase.confirmed || VotingProgressPhase.completed => 1,
    VotingProgressPhase.submitted ||
    VotingProgressPhase.payloadReady ||
    VotingProgressPhase.signingPayload => 0.95,
    VotingProgressPhase.failed => 0,
    // Proving is nearly all of the wall-clock time here, so it owns nearly all
    // of the ring.
    _ => (progress.proofProgress ?? 0).clamp(0.0, 1.0) * 0.9,
  };
}

bool _authorityBundleProved(VotingSessionProgress? progress) {
  if (progress == null) return false;
  return switch (progress.phase) {
    VotingProgressPhase.signingPayload ||
    VotingProgressPhase.payloadReady ||
    VotingProgressPhase.submitted ||
    VotingProgressPhase.confirmed ||
    VotingProgressPhase.completed => true,
    // `proofComplete` arrives as a proof-progress event at 1.
    VotingProgressPhase.proofProgress => (progress.proofProgress ?? 0) >= 1,
    _ => false,
  };
}

/// How far along the vote pipeline a reported phase is.
///
/// Used to pick the furthest bundle to report on a proposal. `failed` ranks
/// below everything so a failure in one bundle never hides another bundle's
/// real progress; the failure itself is surfaced separately.
int voteProgressPhaseRank(VotingProgressPhase phase) {
  return switch (phase) {
    VotingProgressPhase.failed => -1,
    VotingProgressPhase.selectingNotes => 0,
    VotingProgressPhase.buildingPczt => 1,
    VotingProgressPhase.waitingForExistingProof => 2,
    VotingProgressPhase.buildingProof => 3,
    VotingProgressPhase.proofProgress => 4,
    VotingProgressPhase.buildingSharePayloads => 5,
    VotingProgressPhase.signingPayload => 6,
    VotingProgressPhase.signing => 7,
    VotingProgressPhase.payloadReady => 8,
    VotingProgressPhase.submitting => 9,
    VotingProgressPhase.submitted => 10,
    VotingProgressPhase.confirmed => 11,
    VotingProgressPhase.completed => 12,
  };
}

bool _voteEntryProven(VotingSessionProgress progress) {
  return switch (progress.phase) {
    VotingProgressPhase.buildingSharePayloads ||
    VotingProgressPhase.signing ||
    VotingProgressPhase.submitting ||
    VotingProgressPhase.submitted ||
    VotingProgressPhase.confirmed ||
    VotingProgressPhase.completed => true,
    _ => false,
  };
}

/// True once this vote has left the wallet for the chain or the helpers.
bool _voteEntryDispatched(VotingSessionProgress progress) {
  return switch (progress.phase) {
    VotingProgressPhase.submitting ||
    VotingProgressPhase.submitted ||
    VotingProgressPhase.confirmed ||
    VotingProgressPhase.completed => true,
    _ => false,
  };
}

/// This vote's share of the ballot ring.
///
/// The ladder follows the order the SDK reports these in — helper plans
/// prepared (`submitting`), then the chain episode (`submitted`, `confirmed`),
/// then delivery (`completed`) — so a vote's own contribution climbs rather
/// than dipping as it advances.
double _voteEntryFraction(VotingSessionProgress progress) {
  return switch (progress.phase) {
    VotingProgressPhase.completed => 1,
    VotingProgressPhase.confirmed => 0.95,
    VotingProgressPhase.submitted => 0.9,
    VotingProgressPhase.submitting => 0.85,
    VotingProgressPhase.buildingSharePayloads ||
    VotingProgressPhase.signing => 0.8,
    VotingProgressPhase.failed => 0,
    _ => (progress.proofProgress ?? 0).clamp(0.0, 1.0) * 0.8,
  };
}
