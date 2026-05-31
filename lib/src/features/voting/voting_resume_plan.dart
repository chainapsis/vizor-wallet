import 'dart:collection';

import '../../rust/third_party/zcash_voting/wire.dart' as rust_wire;

/// Phase strings emitted by Rust voting recovery.
///
/// Keep these in sync with `WorkflowPhase::as_str` in
/// `zcash_voting::phases::WorkflowPhase`.
abstract final class VotingWorkflowPhase {
  static const prepared = 'prepared';
  static const signed = 'signed';
  static const submittedDelegation = 'submitted_delegation';
  static const submittedVote = 'submitted_vote';
  static const submittedShare = 'submitted_share';
  static const confirmed = 'confirmed';
}

bool hasBlockingRoundRecoveryWork({
  required rust_wire.RoundPlanView? roundPlan,
}) {
  return roundPlan?.blockingRecovery ?? false;
}

bool hasCompletedVoteForDisplay({required rust_wire.RoundPlanView? roundPlan}) {
  return roundPlan?.completedForDisplay ?? false;
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

/// Immutable summary of what the app should resume for a voting round.
///
/// The plan preserves the raw recovery state for details, but exposes sorted
/// indexes and maps for the UI/state machine so resume work happens in a stable
/// order after app restarts.
class VotingResumePlan {
  final rust_wire.RoundRecoveryStateView recoveryState;
  final UnmodifiableListView<int> pendingDelegationBundleIndexes;
  final UnmodifiableMapView<int, String> delegationPhasesByIndex;
  final UnmodifiableListView<int> submittedDelegationBundleIndexes;
  final UnmodifiableMapView<VotingVoteKey, rust_wire.VoteRecoveryView>
  votesByKey;
  final UnmodifiableMapView<VotingVoteKey, String> votePhasesByKey;
  final UnmodifiableMapView<VotingVoteKey, String> voteTxHashesByKey;
  final UnmodifiableMapView<
    VotingVoteKey,
    rust_wire.RecoverableCommitmentBundle
  >
  commitmentBundlesByKey;
  final UnmodifiableListView<VotingVoteKey> pendingVoteSubmissionKeys;
  final UnmodifiableListView<VotingVoteKey> submittedVoteConfirmationKeys;
  final UnmodifiableListView<VotingVoteKey> incompleteVoteRecoveryKeys;
  final UnmodifiableListView<rust_wire.ShareDelegationRecordView>
  shareDelegations;
  final UnmodifiableListView<rust_wire.ShareDelegationRecordView>
  unconfirmedShareDelegations;

  VotingResumePlan({
    required this.recoveryState,
    required List<int> pendingDelegationBundleIndexes,
    required Map<int, String> delegationPhasesByIndex,
    required List<int> submittedDelegationBundleIndexes,
    required Map<VotingVoteKey, rust_wire.VoteRecoveryView> votesByKey,
    required Map<VotingVoteKey, String> votePhasesByKey,
    required Map<VotingVoteKey, String> voteTxHashesByKey,
    required Map<VotingVoteKey, rust_wire.RecoverableCommitmentBundle>
    commitmentBundlesByKey,
    required List<VotingVoteKey> pendingVoteSubmissionKeys,
    required List<VotingVoteKey> submittedVoteConfirmationKeys,
    required List<VotingVoteKey> incompleteVoteRecoveryKeys,
    required List<rust_wire.ShareDelegationRecordView> shareDelegations,
    required List<rust_wire.ShareDelegationRecordView>
    unconfirmedShareDelegations,
  }) : pendingDelegationBundleIndexes = UnmodifiableListView(
         pendingDelegationBundleIndexes,
       ),
       delegationPhasesByIndex = UnmodifiableMapView(delegationPhasesByIndex),
       submittedDelegationBundleIndexes = UnmodifiableListView(
         submittedDelegationBundleIndexes,
       ),
       votesByKey = UnmodifiableMapView(votesByKey),
       votePhasesByKey = UnmodifiableMapView(votePhasesByKey),
       voteTxHashesByKey = UnmodifiableMapView(voteTxHashesByKey),
       commitmentBundlesByKey = UnmodifiableMapView(commitmentBundlesByKey),
       pendingVoteSubmissionKeys = UnmodifiableListView(
         pendingVoteSubmissionKeys,
       ),
       submittedVoteConfirmationKeys = UnmodifiableListView(
         submittedVoteConfirmationKeys,
       ),
       incompleteVoteRecoveryKeys = UnmodifiableListView(
         incompleteVoteRecoveryKeys,
       ),
       shareDelegations = UnmodifiableListView(shareDelegations),
       unconfirmedShareDelegations = UnmodifiableListView(
         unconfirmedShareDelegations,
       );

  String get roundId => recoveryState.roundId;

  int get bundleCount => recoveryState.bundleCount;

  rust_wire.RecoverableCommitmentBundle? commitmentBundleFor(
    VotingVoteKey key,
  ) => commitmentBundlesByKey[key];
}
