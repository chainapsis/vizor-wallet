import '../../rust/third_party/zcash_voting/wire.dart' as rust_voting;
import 'voting_recovery_api.dart';

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
}
