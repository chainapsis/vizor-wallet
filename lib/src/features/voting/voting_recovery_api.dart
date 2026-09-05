import '../../rust/api/voting.dart' as rust_voting;
import '../../rust/third_party/zcash_voting/wire.dart' as rust_voting;
import '../../services/voting/voting_rust_exception.dart';

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
    return _typed(
      () => rust_voting.getRoundPlan(
        dbPath: dbPath,
        accountUuid: accountUuid,
        roundId: roundId,
        proposalIds: proposalIds,
      ),
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
    return _typed(
      () => rust_voting.setBallotIntent(
        dbPath: dbPath,
        accountUuid: accountUuid,
        roundId: roundId,
        proposalId: proposalId,
        numOptions: numOptions,
        skipped: skipped,
        choice: choice,
      ),
    );
  }
}

/// Rethrows a bridge `VotingErrorView` as [VotingRustException] so recovery
/// failures carry their message and kind like every other bridge call.
Future<T> _typed<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on rust_voting.VotingErrorView catch (error) {
    throw VotingRustException(error);
  }
}
