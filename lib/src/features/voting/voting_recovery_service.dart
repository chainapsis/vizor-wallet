import '../../rust/third_party/zcash_voting/wire.dart' as rust_voting;
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

  /// Loads the crate planner's derived resume plan for a round.
  ///
  /// `proposalIds` must be the full set of proposal IDs for the round (as
  /// returned by [proposalsFromRound]). Errors propagate so voting cannot
  /// proceed without durable intent and recovery planning.
  Future<rust_voting.RoundPlanView> loadRoundPlan({
    required String dbPath,
    required String walletId,
    required String roundId,
    required List<int> proposalIds,
  }) {
    return _api.getRoundPlan(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      proposalIds: proposalIds,
    );
  }

  /// Persists the voter's ballot intent for one proposal before casting.
  Future<void> setBallotIntent({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int proposalId,
    required int numOptions,
    required bool skipped,
    int? choice,
  }) {
    return _api.setBallotIntent(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      proposalId: proposalId,
      numOptions: numOptions,
      skipped: skipped,
      choice: choice,
    );
  }

  /// Loads the raw round recovery state and derives the next resume actions.
  Future<VotingResumePlan> loadResumePlan({
    required String dbPath,
    required String walletId,
    required String roundId,
    rust_voting.RoundPlanView? roundPlan,
    rust_voting.DelegationBundlePlanView? delegationPlan,
  }) async {
    final state = await _api.getRoundRecoveryState(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
    );
    final resolvedDelegationPlan =
        delegationPlan ??
        await _loadDelegationPlanIfInitialized(
          dbPath: dbPath,
          walletId: walletId,
          roundId: roundId,
          state: state,
          roundPlan: roundPlan,
        );

    return buildResumePlan(
      state,
      roundPlan: roundPlan,
      delegationPlan: resolvedDelegationPlan,
    );
  }

  Future<rust_voting.DelegationBundlePlanView?>
  _loadDelegationPlanIfInitialized({
    required String dbPath,
    required String walletId,
    required String roundId,
    required rust_voting.RoundRecoveryStateView state,
    rust_voting.RoundPlanView? roundPlan,
  }) {
    if (!_shouldLoadDelegationPlan(state, roundPlan)) {
      return Future.value();
    }
    return _api.getDelegationBundlePlan(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
    );
  }

  bool _shouldLoadDelegationPlan(
    rust_voting.RoundRecoveryStateView state,
    rust_voting.RoundPlanView? roundPlan,
  ) {
    if (roundPlanNeedsDraftSetup(roundPlan) && state.bundleCount == 0) {
      return false;
    }
    return state.bundleCount > 0 ||
        state.delegation.isNotEmpty ||
        state.votes.isNotEmpty ||
        state.commitmentBundles.isNotEmpty ||
        state.shares.isNotEmpty ||
        state.shareDelegations.isNotEmpty ||
        state.unconfirmedShareDelegations.isNotEmpty;
  }

  /// Builds a deterministic view of incomplete delegation, vote, and share work.
  ///
  /// Bundle/proposal pairs are keyed together because voting is bundle-indexed:
  /// one proposal can have independent state for each note bundle.
  VotingResumePlan buildResumePlan(
    rust_voting.RoundRecoveryStateView state, {
    rust_voting.RoundPlanView? roundPlan,
    rust_voting.DelegationBundlePlanView? delegationPlan,
  }) {
    final delegationPhasesByIndex = <int, String>{
      for (final record in state.delegation) record.bundleIndex: record.phase,
    };
    final submittedDelegationBundleIndexes = _submittedDelegationBundleIndexes(
      delegationPlan,
    )..sort();
    final pendingDelegationBundleIndexes = _pendingDelegationBundleIndexes(
      delegationPlan,
    )..sort();

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

    final submittedVoteConfirmationKeys = _voteKeysForSteps(roundPlan, {
      'poll_vote',
    })..sort(_compareVoteKeys);
    final pendingVoteSubmissionKeys = _voteKeysForSteps(roundPlan, {
      'cast_vote',
      'submit_vote',
    })..sort(_compareVoteKeys);
    final incompleteVoteRecoveryKeys = <VotingVoteKey>[];

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

  List<int> _pendingDelegationBundleIndexes(
    rust_voting.DelegationBundlePlanView? delegationPlan,
  ) {
    if (delegationPlan != null) {
      return delegationPlan.pendingBundleIndexes.toList();
    }

    return <int>[];
  }

  List<int> _submittedDelegationBundleIndexes(
    rust_voting.DelegationBundlePlanView? delegationPlan,
  ) {
    if (delegationPlan != null) {
      return delegationPlan.submittedBundleIndexes.toList();
    }

    return <int>[];
  }

  List<VotingVoteKey> _voteKeysForSteps(
    rust_voting.RoundPlanView? roundPlan,
    Set<String> stepKinds,
  ) {
    if (roundPlan == null) return <VotingVoteKey>[];
    return [
      for (final step in roundPlan.nextSteps)
        if (stepKinds.contains(step.kind))
          VotingVoteKey(
            bundleIndex: step.bundleIndex,
            proposalId: step.proposalId,
          ),
    ];
  }

  /// Records additional helper servers that accepted an already-created share.
  ///
  /// Recovery can retry failed helpers without regenerating shares; this appends
  /// only the newly successful URLs for the durable share key.
  Future<void> addSentServersForShare({
    required String dbPath,
    required String walletId,
    required rust_voting.ShareDelegationRecordView share,
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
