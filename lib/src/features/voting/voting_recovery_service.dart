import '../../rust/third_party/zcash_voting/wire.dart' as rust_voting;
import 'voting_recovery_api.dart';
import 'voting_resume_plan.dart';

/// Converts persisted Rust recovery records into Dart actions for resuming UI.
///
/// Rust owns the durable voting database. This service keeps the Dart side
/// focused on orchestration: loading the crate planner, keying raw recovery
/// records by bundle/proposal/share, and clearing recovery records only at
/// explicit boundaries.
class VotingRecoveryService {
  final VotingRecoveryApi _api;

  const VotingRecoveryService({VotingRecoveryApi? api})
    : _api = api ?? const RustVotingRecoveryApi();

  /// Loads the crate planner's derived resume plan for a round.
  ///
  /// `proposalIds` must be the full set of proposal IDs for the round (as
  /// returned by [proposalsFromRound]). Errors propagate so voting cannot
  /// proceed without durable intent and recovery planning.
  Future<rust_voting.RoundPlanView> loadRoundPlan({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required List<int> proposalIds,
  }) {
    return _api.getRoundPlan(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
      proposalIds: proposalIds,
    );
  }

  /// Persists the voter's ballot intent for one proposal before casting.
  Future<void> setBallotIntent({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int proposalId,
    required int numOptions,
    required bool skipped,
    int? choice,
  }) {
    return _api.setBallotIntent(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
      proposalId: proposalId,
      numOptions: numOptions,
      skipped: skipped,
      choice: choice,
    );
  }

  /// Loads the raw round recovery state and indexes records for exact retries.
  Future<VotingResumePlan> loadResumePlan({
    required String dbPath,
    required String accountUuid,
    required String roundId,
  }) async {
    final state = await _api.getRoundRecoveryState(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
    );

    return buildResumePlan(state);
  }

  /// Builds a deterministic keyed view of delegation, vote, and share records.
  ///
  /// Bundle/proposal pairs are keyed together because voting is bundle-indexed:
  /// one proposal can have independent state for each note bundle.
  VotingResumePlan buildResumePlan(rust_voting.RoundRecoveryStateView state) {
    final delegationPhasesByIndex = <int, String>{
      for (final record in state.delegation) record.bundleIndex: record.phase,
    };
    final submittedDelegationBundleIndexes =
        state.delegation
            .where(
              (record) =>
                  record.phase == VotingWorkflowPhase.submittedDelegation,
            )
            .map((record) => record.bundleIndex)
            .toList()
          ..sort();
    final delegatedBundleIndexes = state.delegation
        .where((record) => record.phase == VotingWorkflowPhase.confirmed)
        .map((record) => record.bundleIndex)
        .toSet();
    final pendingDelegationBundleIndexes = [
      for (var index = 0; index < state.bundleCount; index++)
        if (!delegatedBundleIndexes.contains(index) &&
            !submittedDelegationBundleIndexes.contains(index))
          index,
    ];

    final votesByKey = <VotingVoteKey, rust_voting.VoteRecoveryView>{
      for (final vote in state.votes)
        VotingVoteKey(
          bundleIndex: vote.bundleIndex,
          proposalId: vote.proposalId,
        ): vote,
    };
    final voteTxHashesByKey = <VotingVoteKey, String>{
      for (final record in state.votes)
        if (record.txHash != null)
          VotingVoteKey(
            bundleIndex: record.bundleIndex,
            proposalId: record.proposalId,
          ): record.txHash!,
    };
    final votePhasesByKey = <VotingVoteKey, String>{
      for (final record in state.votes)
        VotingVoteKey(
          bundleIndex: record.bundleIndex,
          proposalId: record.proposalId,
        ): record.phase,
    };
    final commitmentBundlesByKey =
        <VotingVoteKey, rust_voting.RecoverableCommitmentBundle>{
          for (final record in state.commitmentBundles)
            VotingVoteKey(
              bundleIndex: record.bundleIndex,
              proposalId: record.proposalId,
            ): record,
        };

    final voteKeys = votesByKey.keys.toList()..sort(_compareVoteKeys);
    final submittedVoteConfirmationKeys =
        votePhasesByKey.entries
            .where((entry) => entry.value == VotingWorkflowPhase.submittedVote)
            .map((entry) => entry.key)
            .toList()
          ..sort(_compareVoteKeys);
    final pendingVoteSubmissionKeys = voteKeys
        .where(
          (key) =>
              !voteTxHashesByKey.containsKey(key) &&
              votePhasesByKey[key] != VotingWorkflowPhase.submittedVote &&
              votePhasesByKey[key] != VotingWorkflowPhase.confirmed,
        )
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
      delegationPhasesByIndex: delegationPhasesByIndex,
      submittedDelegationBundleIndexes: submittedDelegationBundleIndexes,
      votesByKey: votesByKey,
      votePhasesByKey: votePhasesByKey,
      voteTxHashesByKey: voteTxHashesByKey,
      commitmentBundlesByKey: commitmentBundlesByKey,
      pendingVoteSubmissionKeys: pendingVoteSubmissionKeys,
      submittedVoteConfirmationKeys: submittedVoteConfirmationKeys,
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
    required String accountUuid,
    required rust_voting.ShareDelegationRecordView share,
    required List<String> newUrls,
  }) {
    return _api.addSentServers(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: share.roundId,
      bundleIndex: share.bundleIndex,
      proposalId: share.proposalId,
      shareIndex: share.shareIndex,
      newUrls: newUrls,
    );
  }

  static int _compareVoteKeys(VotingVoteKey a, VotingVoteKey b) {
    final bundleCompare = a.bundleIndex.compareTo(b.bundleIndex);
    if (bundleCompare != 0) return bundleCompare;
    return a.proposalId.compareTo(b.proposalId);
  }

  static int _compareShareDelegations(
    rust_voting.ShareDelegationRecordView a,
    rust_voting.ShareDelegationRecordView b,
  ) {
    final bundleCompare = a.bundleIndex.compareTo(b.bundleIndex);
    if (bundleCompare != 0) return bundleCompare;
    final proposalCompare = a.proposalId.compareTo(b.proposalId);
    if (proposalCompare != 0) return proposalCompare;
    return a.shareIndex.compareTo(b.shareIndex);
  }
}
