import '../../rust/third_party/zcash_voting/wire.dart' as rust_wire;

bool hasBlockingRoundRecoveryWork(rust_wire.RoundPlanView? roundPlan) {
  return roundPlan?.blockingRecovery ?? false;
}

bool hasCompletedVoteForDisplay(rust_wire.RoundPlanView? roundPlan) {
  return roundPlan?.completedForDisplay ?? false;
}

/// Whether the round's designated immediate share has durable confirmation.
///
/// Delayed shares intentionally remain background work, but the submission
/// confirmation screen must not advance until this one round-level share has
/// been durably confirmed by the crate's configured-helper quorum.
bool hasConfirmedImmediateShare(rust_wire.RoundPlanView? roundPlan) {
  if (roundPlan?.immediateShareKey == null) return true;
  return roundPlan!.immediateShareConfirmed;
}

bool roundPlanNeedsDraftSetup(rust_wire.RoundPlanView? roundPlan) {
  return roundPlan?.needsDraftSetup ?? false;
}

/// Stable key for per-proposal vote state within one note bundle.
///
/// A round can split voting power across bundles, and every bundle/proposal pair
/// can independently have a stored vote, commitment bundle, or broadcast hash.
class VotingVoteKey {
  final int bundleIndex;
  final int proposalId;

  const VotingVoteKey({required this.bundleIndex, required this.proposalId});

  @override
  int get hashCode => Object.hash(bundleIndex, proposalId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VotingVoteKey &&
          runtimeType == other.runtimeType &&
          bundleIndex == other.bundleIndex &&
          proposalId == other.proposalId;

  @override
  String toString() =>
      'VotingVoteKey(bundleIndex: $bundleIndex, proposalId: $proposalId)';
}

/// Eligible bundles the round persisted. The SDK reports one delegation
/// status per bundle, so its length is the round's bundle count.
int roundPlanBundleCount(rust_wire.RoundPlanView? roundPlan) =>
    roundPlan?.delegationStatuses.length ?? 0;

/// Whether a planned step is one that casts a vote or delivers its shares.
///
/// Exhaustive on purpose: a new step kind must be classified here rather than
/// reading as "not a vote" in whichever caller happens to look at it first.
bool isVoteNextStepKind(rust_wire.NextStepKind kind) {
  return switch (kind) {
    rust_wire.NextStepKind.castVote ||
    rust_wire.NextStepKind.advanceVote ||
    rust_wire.NextStepKind.advanceVoteBatch ||
    rust_wire.NextStepKind.submitShares => true,
    rust_wire.NextStepKind.delegate ||
    rust_wire.NextStepKind.advanceDelegation ||
    rust_wire.NextStepKind.advanceImportedDelegation ||
    rust_wire.NextStepKind.confirmShare => false,
  };
}

/// Bundles this plan still casts the ballot in, ascending.
///
/// Not every eligible bundle carries votes: a bundle whose delegation ended
/// terminal never will, and the planner plans no vote step for it. So this is
/// narrower than [roundPlanBundleCount], and it is what a projection counting
/// "delivered in every bundle that carries this question" must divide by —
/// the round's bundle count makes such a question impossible to finish.
///
/// A bundle that has already finished its votes drops out of the plan, so a
/// caller tracking a run in progress unions in the bundles the run has itself
/// reported on.
List<int> voteCarryingBundleIndexes(rust_wire.RoundPlanView? roundPlan) {
  final indexes = <int>{
    for (final step in roundPlan?.nextSteps ?? const <rust_wire.NextStepView>[])
      if (isVoteNextStepKind(step.kind)) step.bundleIndex,
    for (final work
        in roundPlan?.recoveredVoteWork ??
            const <rust_wire.VoteRecoveryWorkView>[])
      work.bundleIndex,
  };
  return indexes.toList()..sort();
}

/// Bundles whose delegation still has work to drive.
///
/// The planner decides this: it plans a delegation step only for a bundle
/// that still owes one, and none for a bundle it marks terminal. Rebuilding
/// the answer here from `delegationStatuses` meant restating the planner's
/// rules and drifting from them whenever they changed.
List<int> delegationBundleIndexesNeedingWork(
  rust_wire.RoundPlanView? roundPlan,
) => roundPlan?.delegationBundlesNeedingWork ?? const [];

/// Bundles that still need delegation signing material.
///
/// A subset of [delegationBundleIndexesNeedingWork]: a bundle already
/// submitted and awaiting its chain outcome owes work but no signature.
List<int> delegationBundleIndexesNeedingSigning(
  rust_wire.RoundPlanView? roundPlan,
) => roundPlan?.delegationBundlesNeedingSigning ?? const [];

/// Why each bundle whose delegation ended without confirming did, if any did.
///
/// A terminal delegation schedules no further work, so this is the only thing
/// the wallet can tell the user about it. A hashless dispatch may already be
/// on the chain, so the message must not read as an invitation to retry.
///
/// Every terminal bundle is named: a round can end one bundle and still have
/// live work in another, and the live work finishing is not a reason to leave
/// the dead one unreported.
String? terminalDelegationMessage(rust_wire.RoundPlanView? roundPlan) {
  final reasons = <String>[];
  for (final status
      in roundPlan?.delegationStatuses ??
          const <rust_wire.DelegationStatusView>[]) {
    if (!status.terminal) continue;
    final diagnostic = status.submissionDiagnostic;
    final reason = diagnostic == null
        ? 'it ended without confirming'
        : diagnostic.message;
    reasons.add('bundle ${status.bundleIndex + 1} ($reason)');
  }
  if (reasons.isEmpty) return null;
  final subject = reasons.length == 1
      ? 'Delegation ${reasons.single}'
      : 'Delegation for ${reasons.join(', ')}';
  return '$subject cannot continue. Do not retry it; the transaction may '
      'already be on the chain.';
}
