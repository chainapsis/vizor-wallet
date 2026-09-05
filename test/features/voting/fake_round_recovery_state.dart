import 'dart:typed_data';

import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;

/// Durable round state as the SDK holds it, for tests that describe a wallet
/// mid-round.
///
/// Production Dart never sees these rows: the round plan is the wallet's whole
/// view of durable state, and the SDK reads the records behind it itself. Tests
/// still need to say "this account has a submitted delegation and two
/// unconfirmed shares", so they build this and let
/// `apiRoundPlanFromRecoveryState` derive the plan the SDK would return.
class FakeRoundRecoveryState {
  const FakeRoundRecoveryState({
    required this.roundId,
    required this.bundleCount,
    required this.delegation,
    required this.votes,
    required this.commitmentBundles,
    required this.shares,
    required this.shareDelegations,
    required this.unconfirmedShareDelegations,
  });

  final String roundId;
  final int bundleCount;
  final List<FakeDelegationRecovery> delegation;
  final List<FakeVoteRecovery> votes;
  final List<FakeCommitmentBundle> commitmentBundles;
  final List<FakeShareWorkflowRecovery> shares;
  final List<FakeShareDelegationRecord> shareDelegations;
  final List<FakeShareDelegationRecord> unconfirmedShareDelegations;
}

class FakeDelegationRecovery {
  const FakeDelegationRecovery({
    required this.bundleIndex,
    required this.phase,
    this.txHash,
    this.vanLeafPosition,
    this.terminal = false,
    this.submissionDiagnostic,
  });

  final int bundleIndex;
  final rust_wire.WorkflowPhaseView phase;
  final String? txHash;
  final BigInt? vanLeafPosition;

  /// The delegation ended and the SDK plans no further step for it.
  final bool terminal;
  final rust_wire.SubmissionDiagnosticView? submissionDiagnostic;
}

class FakeVoteRecovery {
  const FakeVoteRecovery({
    required this.bundleIndex,
    required this.proposalId,
    required this.choice,
    required this.phase,
    required this.hasCommitmentBundle,
    this.txHash,
    this.vcTreePosition,
  });

  final int bundleIndex;
  final int proposalId;
  final int choice;
  final rust_wire.WorkflowPhaseView phase;
  final bool hasCommitmentBundle;
  final String? txHash;
  final BigInt? vcTreePosition;
}

class FakeCommitmentBundle {
  const FakeCommitmentBundle({
    required this.bundleIndex,
    required this.proposalId,
    required this.commitmentBundleJson,
    required this.vcTreePosition,
  });

  final int bundleIndex;
  final int proposalId;
  final String commitmentBundleJson;
  final BigInt vcTreePosition;
}

class FakeShareWorkflowRecovery {
  const FakeShareWorkflowRecovery({
    required this.bundleIndex,
    required this.proposalId,
    required this.shareIndex,
    required this.phase,
  });

  final int bundleIndex;
  final int proposalId;
  final int shareIndex;
  final rust_wire.WorkflowPhaseView phase;
}

class FakeShareDelegationRecord {
  const FakeShareDelegationRecord({
    required this.roundId,
    required this.bundleIndex,
    required this.proposalId,
    required this.shareIndex,
    required this.sentToUrls,
    required this.ambiguousUrls,
    required this.targetCount,
    required this.nullifier,
    required this.phase,
    required this.confirmed,
    required this.submitAt,
    required this.createdAt,
  });

  final String roundId;
  final int bundleIndex;
  final int proposalId;
  final int shareIndex;
  final List<String> sentToUrls;
  final List<String> ambiguousUrls;
  final int targetCount;
  final Uint8List nullifier;
  final rust_wire.WorkflowPhaseView phase;
  final bool confirmed;
  final BigInt submitAt;
  final BigInt createdAt;
}
