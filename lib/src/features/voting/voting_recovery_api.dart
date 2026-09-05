import '../../rust/api/voting.dart' as rust_voting;
import '../../rust/third_party/zcash_voting/wire.dart' as rust_voting;

/// Injectable boundary around the Rust voting recovery API.
///
/// Keeping the FRB calls behind this interface lets Dart planning tests use
/// in-memory fakes while production code still delegates all durable state
/// reads and writes to Rust.
abstract interface class VotingRecoveryApi {
  Future<rust_voting.RoundPlanView> getRoundPlan({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required List<int> proposalIds,
  });

  Future<void> setBallotIntent({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int proposalId,
    required int numOptions,
    required bool skipped,
    int? choice,
  });
}

/// Production recovery API implementation backed by generated FRB bindings.
class RustVotingRecoveryApi implements VotingRecoveryApi {
  const RustVotingRecoveryApi();

  @override
  Future<rust_voting.RoundPlanView> getRoundPlan({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required List<int> proposalIds,
  }) {
    return rust_voting.getRoundPlan(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
      proposalIds: proposalIds,
    );
  }

  @override
  Future<void> setBallotIntent({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int proposalId,
    required int numOptions,
    required bool skipped,
    int? choice,
  }) {
    return rust_voting.setBallotIntent(
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
