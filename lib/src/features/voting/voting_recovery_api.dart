import '../../rust/api/voting.dart' as rust_voting;
import '../../rust/third_party/zcash_voting/wire.dart' as rust_wire;

/// Injectable boundary around the Rust voting recovery API.
///
/// Keeping the FRB calls behind this interface lets Dart resume-planning tests
/// use in-memory fakes while production code still delegates all durable state
/// reads and writes to Rust.
abstract interface class VotingRecoveryApi {
  Future<rust_wire.RoundRecoveryStateView> getRoundRecoveryState({
    required String dbPath,
    required String walletId,
    required String roundId,
  });

  Future<rust_voting.ApiRoundPlan> getRoundPlan({
    required String dbPath,
    required String walletId,
    required String roundId,
    required List<int> proposalIds,
  });

  Future<void> setBallotIntent({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int proposalId,
    required int numOptions,
    required bool skipped,
    int? choice,
  });

  Future<void> addSentServers({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required List<String> newUrls,
  });

  Future<void> clearRecoveryState({
    required String dbPath,
    required String walletId,
    required String roundId,
  });
}

/// Production recovery API implementation backed by generated FRB bindings.
class RustVotingRecoveryApi implements VotingRecoveryApi {
  const RustVotingRecoveryApi();

  @override
  Future<rust_wire.RoundRecoveryStateView> getRoundRecoveryState({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) {
    return rust_voting.getRoundRecoveryState(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
    );
  }

  @override
  Future<rust_voting.ApiRoundPlan> getRoundPlan({
    required String dbPath,
    required String walletId,
    required String roundId,
    required List<int> proposalIds,
  }) {
    return rust_voting.getRoundPlan(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      proposalIds: proposalIds,
    );
  }

  @override
  Future<void> setBallotIntent({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int proposalId,
    required int numOptions,
    required bool skipped,
    int? choice,
  }) {
    return rust_voting.setBallotIntent(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      proposalId: proposalId,
      numOptions: numOptions,
      skipped: skipped,
      choice: choice,
    );
  }

  @override
  Future<void> addSentServers({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required List<String> newUrls,
  }) {
    return rust_voting.addSentServers(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      shareIndex: shareIndex,
      newUrls: newUrls,
    );
  }

  @override
  Future<void> clearRecoveryState({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) {
    return rust_voting.clearRecoveryState(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
    );
  }
}
