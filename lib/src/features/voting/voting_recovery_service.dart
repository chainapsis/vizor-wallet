import '../../rust/api/voting.dart' as rust_voting;
import 'voting_recovery_api.dart';
import 'voting_resume_plan.dart';

/// Converts persisted Rust recovery records into Dart actions for resuming UI.
///
/// Rust owns the durable voting database. This service keeps the Dart side
/// focused on orchestration: deciding which bundle/proposal/share steps still
/// need network work and clearing recovery records only at explicit boundaries.
class VotingRecoveryService {
  final VotingRecoveryApi _api;

  const VotingRecoveryService({VotingRecoveryApi? api})
    : _api = api ?? const RustVotingRecoveryApi();

  /// Loads the raw round recovery state and derives the next resume actions.
  Future<VotingResumePlan> loadResumePlan({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) async {
    final state = await _api.getRoundRecoveryState(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
    );

    return buildResumePlan(state);
  }

  /// Builds a deterministic view of incomplete delegation, vote, and share work.
  ///
  /// Bundle/proposal pairs are keyed together because voting is bundle-indexed:
  /// one proposal can have independent state for each note bundle.
  VotingResumePlan buildResumePlan(rust_voting.ApiRoundRecoveryState state) {
    final delegatedBundleIndexes = state.delegationTxHashes
        .map((record) => record.bundleIndex)
        .toSet();
    final pendingDelegationBundleIndexes = [
      for (var index = 0; index < state.bundleCount; index++)
        if (!delegatedBundleIndexes.contains(index)) index,
    ];

    final votesByKey = <VotingVoteKey, rust_voting.ApiVoteRecord>{
      for (final vote in state.votes)
        VotingVoteKey(
          bundleIndex: vote.bundleIndex,
          proposalId: vote.proposalId,
        ): vote,
    };
    final voteTxHashesByKey = <VotingVoteKey, String>{
      for (final record in state.voteTxHashes)
        VotingVoteKey(
          bundleIndex: record.bundleIndex,
          proposalId: record.proposalId,
        ): record.txHash,
    };
    final commitmentBundlesByKey =
        <VotingVoteKey, rust_voting.ApiCommitmentBundleRecovery>{
          for (final record in state.commitmentBundles)
            VotingVoteKey(
              bundleIndex: record.bundleIndex,
              proposalId: record.proposalId,
            ): record,
        };

    final voteKeys = votesByKey.keys.toList()..sort(_compareVoteKeys);
    final pendingVoteSubmissionKeys = voteKeys
        .where((key) => !voteTxHashesByKey.containsKey(key))
        .toList();
    final incompleteVoteRecoveryKeys = voteKeys
        .where(
          (key) =>
              !voteTxHashesByKey.containsKey(key) ||
              !commitmentBundlesByKey.containsKey(key),
        )
        .toList();

    final shareDelegations = state.shareDelegations.toList()
      ..sort(_compareShareDelegations);
    final unconfirmedShareDelegations =
        state.unconfirmedShareDelegations
            .where((record) => !record.confirmed)
            .toList()
          ..sort(_compareShareDelegations);

    return VotingResumePlan(
      recoveryState: state,
      pendingDelegationBundleIndexes: pendingDelegationBundleIndexes,
      votesByKey: votesByKey,
      voteTxHashesByKey: voteTxHashesByKey,
      commitmentBundlesByKey: commitmentBundlesByKey,
      pendingVoteSubmissionKeys: pendingVoteSubmissionKeys,
      incompleteVoteRecoveryKeys: incompleteVoteRecoveryKeys,
      shareDelegations: shareDelegations,
      unconfirmedShareDelegations: unconfirmedShareDelegations,
    );
  }

  /// Records additional helper servers that accepted an already-created share.
  ///
  /// Recovery can retry failed helpers without regenerating shares; this appends
  /// only the newly successful URLs for the durable share key.
  Future<void> addSentServersForShare({
    required String dbPath,
    required String walletId,
    required rust_voting.ApiShareDelegationRecord share,
    required List<String> newUrls,
  }) {
    return _api.addSentServers(
      dbPath: dbPath,
      walletId: walletId,
      roundId: share.roundId,
      bundleIndex: share.bundleIndex,
      proposalId: share.proposalId,
      shareIndex: share.shareIndex,
      newUrls: newUrls,
    );
  }

  /// Clears recovery data after a round has finished successfully.
  Future<void> finalizeRound({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) {
    return _clearRoundRecoveryState(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
    );
  }

  /// Clears recovery data when the user intentionally stops participating.
  Future<void> abandonRound({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) {
    return _clearRoundRecoveryState(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
    );
  }

  Future<void> _clearRoundRecoveryState({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) {
    return _api.clearRecoveryState(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
    );
  }

  static int _compareVoteKeys(VotingVoteKey a, VotingVoteKey b) {
    final bundleCompare = a.bundleIndex.compareTo(b.bundleIndex);
    if (bundleCompare != 0) return bundleCompare;
    return a.proposalId.compareTo(b.proposalId);
  }

  static int _compareShareDelegations(
    rust_voting.ApiShareDelegationRecord a,
    rust_voting.ApiShareDelegationRecord b,
  ) {
    final bundleCompare = a.bundleIndex.compareTo(b.bundleIndex);
    if (bundleCompare != 0) return bundleCompare;
    final proposalCompare = a.proposalId.compareTo(b.proposalId);
    if (proposalCompare != 0) return proposalCompare;
    return a.shareIndex.compareTo(b.shareIndex);
  }
}
