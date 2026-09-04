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

/// Bundles whose delegation is not yet confirmed on chain.
///
/// Covers both bundles still needing signature work and bundles already
/// submitted and awaiting confirmation, because both still need a delegation
/// step driven.
List<int> delegationBundleIndexesNeedingWork(
  rust_wire.RoundPlanView? roundPlan,
) {
  final indexes = <int>{
    for (final status
        in roundPlan?.delegationStatuses ??
            const <rust_wire.DelegationStatusView>[])
      if (status.phase != rust_wire.WorkflowPhaseView.confirmed)
        status.bundleIndex,
    for (final work
        in roundPlan?.recoveredDelegationWork ??
            const <rust_wire.DelegationRecoveryWorkView>[])
      work.bundleIndex,
  };
  return indexes.toList()..sort();
}

/// Bundles that still need delegation signing material.
///
/// Excludes bundles already submitted: their signature exists and only the
/// chain outcome is outstanding.
List<int> delegationBundleIndexesNeedingSigning(
  rust_wire.RoundPlanView? roundPlan,
) {
  final indexes = <int>[
    for (final status
        in roundPlan?.delegationStatuses ??
            const <rust_wire.DelegationStatusView>[])
      if (status.phase != rust_wire.WorkflowPhaseView.confirmed &&
          status.phase != rust_wire.WorkflowPhaseView.submittedDelegation)
        status.bundleIndex,
  ];
  return indexes..sort();
}
