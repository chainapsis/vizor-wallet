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

/// Bundles whose delegation still has work to drive.
///
/// Covers both bundles needing signature work and bundles already submitted
/// and awaiting confirmation, because both still need a delegation step.
/// Excludes bundles the SDK marks terminal: it plans no step for them, and a
/// hashless dispatch must never be retried.
List<int> delegationBundleIndexesNeedingWork(
  rust_wire.RoundPlanView? roundPlan,
) {
  final terminal = _terminalBundleIndexes(roundPlan);
  final indexes = <int>{
    for (final status
        in roundPlan?.delegationStatuses ??
            const <rust_wire.DelegationStatusView>[])
      if (!status.terminal &&
          status.phase != rust_wire.WorkflowPhaseView.confirmed)
        status.bundleIndex,
    for (final work
        in roundPlan?.recoveredDelegationWork ??
            const <rust_wire.DelegationRecoveryWorkView>[])
      if (!terminal.contains(work.bundleIndex)) work.bundleIndex,
  };
  return indexes.toList()..sort();
}

/// Bundles that still need delegation signing material.
///
/// Excludes bundles already submitted (their signature exists and only the
/// chain outcome is outstanding) and bundles the SDK marks terminal.
List<int> delegationBundleIndexesNeedingSigning(
  rust_wire.RoundPlanView? roundPlan,
) {
  final indexes = <int>[
    for (final status
        in roundPlan?.delegationStatuses ??
            const <rust_wire.DelegationStatusView>[])
      if (!status.terminal &&
          status.phase != rust_wire.WorkflowPhaseView.confirmed &&
          status.phase != rust_wire.WorkflowPhaseView.submittedDelegation)
        status.bundleIndex,
  ];
  return indexes..sort();
}

Set<int> _terminalBundleIndexes(rust_wire.RoundPlanView? roundPlan) => {
  for (final status
      in roundPlan?.delegationStatuses ??
          const <rust_wire.DelegationStatusView>[])
    if (status.terminal) status.bundleIndex,
};

/// Why a bundle's delegation ended without confirming, if one did.
///
/// A terminal delegation schedules no further work, so this is the only thing
/// the wallet can tell the user about it. A hashless dispatch may already be
/// on the chain, so the message must not read as an invitation to retry.
String? terminalDelegationMessage(rust_wire.RoundPlanView? roundPlan) {
  for (final status
      in roundPlan?.delegationStatuses ??
          const <rust_wire.DelegationStatusView>[]) {
    if (!status.terminal) continue;
    final diagnostic = status.submissionDiagnostic;
    final reason = diagnostic == null
        ? 'it ended without confirming'
        : diagnostic.message;
    return 'Delegation bundle ${status.bundleIndex + 1} cannot continue: '
        '$reason. Do not retry it; the transaction may already be on the '
        'chain.';
  }
  return null;
}
