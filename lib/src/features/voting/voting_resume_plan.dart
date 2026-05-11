import 'dart:collection';

import '../../rust/api/voting.dart' as rust_voting;

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
  final rust_voting.ApiRoundRecoveryState recoveryState;
  final UnmodifiableListView<int> pendingDelegationBundleIndexes;
  final UnmodifiableMapView<VotingVoteKey, rust_voting.ApiVoteRecord>
  votesByKey;
  final UnmodifiableMapView<VotingVoteKey, String> voteTxHashesByKey;
  final UnmodifiableMapView<
    VotingVoteKey,
    rust_voting.ApiCommitmentBundleRecovery
  >
  commitmentBundlesByKey;
  final UnmodifiableListView<VotingVoteKey> pendingVoteSubmissionKeys;
  final UnmodifiableListView<VotingVoteKey> incompleteVoteRecoveryKeys;
  final UnmodifiableListView<rust_voting.ApiShareDelegationRecord>
  shareDelegations;
  final UnmodifiableListView<rust_voting.ApiShareDelegationRecord>
  unconfirmedShareDelegations;

  VotingResumePlan({
    required this.recoveryState,
    required List<int> pendingDelegationBundleIndexes,
    required Map<VotingVoteKey, rust_voting.ApiVoteRecord> votesByKey,
    required Map<VotingVoteKey, String> voteTxHashesByKey,
    required Map<VotingVoteKey, rust_voting.ApiCommitmentBundleRecovery>
    commitmentBundlesByKey,
    required List<VotingVoteKey> pendingVoteSubmissionKeys,
    required List<VotingVoteKey> incompleteVoteRecoveryKeys,
    required List<rust_voting.ApiShareDelegationRecord> shareDelegations,
    required List<rust_voting.ApiShareDelegationRecord>
    unconfirmedShareDelegations,
  }) : pendingDelegationBundleIndexes = UnmodifiableListView(
         pendingDelegationBundleIndexes,
       ),
       votesByKey = UnmodifiableMapView(votesByKey),
       voteTxHashesByKey = UnmodifiableMapView(voteTxHashesByKey),
       commitmentBundlesByKey = UnmodifiableMapView(commitmentBundlesByKey),
       pendingVoteSubmissionKeys = UnmodifiableListView(
         pendingVoteSubmissionKeys,
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

  /// True when there is still user-visible network or confirmation work.
  bool get hasPendingWork =>
      pendingDelegationBundleIndexes.isNotEmpty ||
      pendingVoteSubmissionKeys.isNotEmpty ||
      unconfirmedShareDelegations.isNotEmpty;

  rust_voting.ApiCommitmentBundleRecovery? commitmentBundleFor(
    VotingVoteKey key,
  ) => commitmentBundlesByKey[key];

  String? voteTxHashFor(VotingVoteKey key) => voteTxHashesByKey[key];
}
