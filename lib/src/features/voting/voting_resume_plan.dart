import '../../rust/third_party/zcash_voting/wire.dart' as rust_wire;
import 'voting_message.dart';

bool hasBlockingRoundRecoveryWork(rust_wire.RoundPlanView? roundPlan) {
  return roundPlan?.blockingRecovery ?? false;
}

/// Whether the plan owes recovery work a round label should show:
/// [rust_wire.RoundPlanView.pendingRecovery], unless its only steps are
/// handed-off DC shares awaiting their reveals. Background tracking finishes
/// those, so they leave the label as it would be without them, as a vote
/// share in tracking does.
bool roundPlanHasPendingRecovery(rust_wire.RoundPlanView? roundPlan) {
  if (roundPlan == null || !roundPlan.pendingRecovery) return false;
  final steps = roundPlan.nextSteps;
  final onlyDcTracking =
      steps.isNotEmpty &&
      steps.every(
        (step) =>
            step.kind == rust_wire.NextStepKind.confirmShare &&
            step.dcSlot != null,
      );
  return roundPlan.blockingRecovery || !onlyDcTracking;
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

/// Whether proxy delegations took the weight of every bundle in the round,
/// so the wallet has nothing left to vote: the plan offers no open
/// proposal, plans no cast and ignores recorded intents. Only a committed
/// proxy allocation can make this true.
bool roundPlanNothingLeftToVote(rust_wire.RoundPlanView? roundPlan) {
  return roundPlan?.nothingLeftToVote ?? false;
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
    rust_wire.NextStepKind.confirmShare ||
    // Proxy delegation steps hand weight to delegates; they cast no vote.
    rust_wire.NextStepKind.proxyDelegate ||
    rust_wire.NextStepKind.advanceProxyBatch => false,
  };
}

/// Whether [step] casts a vote or delivers a vote's shares: a vote step
/// kind that names no delegation commitment. A share step carrying a
/// `dcSlot` delivers a proxy DC's shares into its delegate's pool, which is
/// no vote.
bool isVoteNextStep(rust_wire.NextStepView step) =>
    isVoteNextStepKind(step.kind) && step.dcSlot == null;

/// Whether [step] is proxy delegation work: proving or submitting a proxy
/// batch, or delivering a DC's shares. Confirming a handed-off DC share is
/// background share tracking's work, as a vote share's is.
bool isProxyNextStep(rust_wire.NextStepView step) => switch (step.kind) {
  rust_wire.NextStepKind.proxyDelegate ||
  rust_wire.NextStepKind.advanceProxyBatch => true,
  rust_wire.NextStepKind.submitShares => step.dcSlot != null,
  _ => false,
};

/// Whether the plan still owes proxy delegation work. None is owed once
/// every proxy batch landed with every DC's shares handed off.
bool roundPlanHasProxyWork(rust_wire.RoundPlanView? roundPlan) =>
    roundPlan?.nextSteps.any(isProxyNextStep) ?? false;

/// Whether the ballot's answers are recorded, so no proposal is open, yet
/// not every one is confirmed in every bundle that votes. The casts are
/// still owed, including while an unlanded proxy batch withholds them and
/// the plan lists none.
bool roundPlanOwesBallotCasts(rust_wire.RoundPlanView? roundPlan) =>
    roundPlan != null &&
    !roundPlan.nothingLeftToVote &&
    roundPlan.openProposals.isEmpty &&
    !roundPlan.allDecided;

/// Whether a proxy batch has not landed yet: it is still proved
/// (`ProxyDelegate`) or still signed, sent and tracked (`AdvanceProxyBatch`),
/// including while the chain refuses it. Its bundle casts nothing until the
/// batch lands, and sending it can need the account's signer.
bool roundPlanHasUnlandedProxyBatch(rust_wire.RoundPlanView? roundPlan) =>
    roundPlan?.nextSteps.any(
      (step) => switch (step.kind) {
        rust_wire.NextStepKind.proxyDelegate ||
        rust_wire.NextStepKind.advanceProxyBatch => true,
        _ => false,
      },
    ) ??
    false;

/// Whether a proxy batch still has to prove its bundle's registration
/// (ZKP1), which reads the round's PIR snapshot: a `ProxyDelegate` step on a
/// bundle whose delegation is not confirmed.
bool roundPlanProxyNeedsRegistrationProof(rust_wire.RoundPlanView? roundPlan) {
  if (roundPlan == null) return false;
  final confirmed = {
    for (final status in roundPlan.delegationStatuses)
      if (status.phase == rust_wire.WorkflowPhaseView.confirmed)
        status.bundleIndex,
  };
  return roundPlan.nextSteps.any(
    (step) =>
        step.kind == rust_wire.NextStepKind.proxyDelegate &&
        !confirmed.contains(step.bundleIndex),
  );
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
      if (isVoteNextStep(step)) step.bundleIndex,
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

/// Bundles whose first own cast will sign the bundle's delegation once the
/// round's proxy batches resolve, ascending: bundles with weight left and no
/// proxy batch, whose delegation is not on the chain yet and not terminal.
///
/// The plan lists these only once the ballot's intents are recorded, which
/// waits for the batches to land, so a hardware Submit signs them together
/// with the batches' registrations (ERRATA 12). A batch bundle needs none:
/// its registration's signature is the delegation's.
List<int> keptBundlesSigningFirstCast(rust_wire.RoundPlanView? roundPlan) {
  if (roundPlan == null) return const [];
  final excluded = {
    ...roundPlan.fullyDelegatedBundles,
    for (final batch in roundPlan.proxyBatches) batch.bundleIndex,
    for (final step in roundPlan.nextSteps)
      if (isProxyNextStep(step)) step.bundleIndex,
  };
  return [
    for (final status in roundPlan.delegationStatuses)
      if (!status.terminal &&
          !excluded.contains(status.bundleIndex) &&
          (status.phase == rust_wire.WorkflowPhaseView.prepared ||
              status.phase == rust_wire.WorkflowPhaseView.signed))
        status.bundleIndex,
  ]..sort();
}

/// Why each bundle whose delegation ended without confirming did, if any did.
///
/// A terminal delegation schedules no further work, so this is the only thing
/// the wallet can tell the user about it. A hashless dispatch may already be
/// on the chain, so the message must not read as an invitation to retry.
///
/// Every terminal bundle is named: a round can end one bundle and still have
/// live work in another, and the live work finishing is not a reason to leave
/// the dead one unreported.
VotingTerminalDelegation? terminalDelegationNotice(
  rust_wire.RoundPlanView? roundPlan,
) {
  final bundles = [
    for (final status
        in roundPlan?.delegationStatuses ??
            const <rust_wire.DelegationStatusView>[])
      if (status.terminal)
        VotingTerminalBundle(
          bundleNumber: status.bundleIndex + 1,
          diagnostic: status.submissionDiagnostic?.message,
        ),
  ];
  return bundles.isEmpty ? null : VotingTerminalDelegation(bundles);
}
