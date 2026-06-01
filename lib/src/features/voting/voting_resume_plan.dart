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

bool hasBlockingRoundRecoveryWork(rust_wire.RoundPlanView? roundPlan) {
  return roundPlan?.blockingRecovery ?? false;
}

bool hasCompletedVoteForDisplay(rust_wire.RoundPlanView? roundPlan) {
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

/// Immutable keyed view of persisted recovery records for a voting round.
///
/// The crate `RoundPlanView` decides high-level recovery and display state. This
/// object preserves raw records in stable order so Dart can retry the exact
/// bundle/proposal/share work selected by that plan.
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

  /// Shares with no accepted helper server still need foreground retry work.
  ///
  /// High-level recovery and completed-vote display decisions come from
  /// [rust_wire.RoundPlanView]. This value is only the local share retry shape.
  bool get hasBlockingShareWork =>
      unconfirmedShareDelegations.any((record) => record.sentToUrls.isEmpty);

  rust_wire.RecoverableCommitmentBundle? commitmentBundleFor(
    VotingVoteKey key,
  ) => commitmentBundlesByKey[key];
}
