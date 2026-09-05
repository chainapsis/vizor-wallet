// Scripted-fake shapes for the voting tests.
//
// The production bridge no longer carries these types: the SDK round session
// owns chain episodes, helper delivery, proofs, and vote recovery, and reports
// them through `zcash_voting::wire` views. The scripted `VotingRustApi` fakes
// still describe chain and helper outcomes in these older shapes, and
// `FakeVotingRoundSession` converts them to wire views. Test files import this
// barrel as `rust_api` so the remaining production types stay reachable under
// the same prefix.

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'fake_rust_wire_shapes.dart';

export 'package:zcash_wallet/src/rust/api/voting.dart';

enum ApiChainRecoveryMode { statusOnly, exactTree }

enum ApiChainSubmissionOutcomeKind {
  confirmed,
  tracking,
  recovering,
  submittedWithoutHash,
  rejected,
  cancelled,
}

class ApiChainSubmissionCallResult {
  final ApiChainSubmissionOutcome? outcome;
  final ApiChainSubmissionFailure? failure;

  const ApiChainSubmissionCallResult({this.outcome, this.failure});

  @override
  int get hashCode => outcome.hashCode ^ failure.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiChainSubmissionCallResult &&
          runtimeType == other.runtimeType &&
          outcome == other.outcome &&
          failure == other.failure;
}

class ApiChainSubmissionOutcome {
  final ApiChainSubmissionOutcomeKind kind;
  final ApiChainConfirmationSource? confirmationSource;
  final String? transactionHash;
  final String? candidateTransactionHash;
  final BigInt? finalVanPosition;
  final Uint64List voteCommitmentPositions;
  final ApiChainDiagnostic? diagnostic;

  const ApiChainSubmissionOutcome({
    required this.kind,
    this.confirmationSource,
    this.transactionHash,
    this.candidateTransactionHash,
    this.finalVanPosition,
    required this.voteCommitmentPositions,
    this.diagnostic,
  });

  @override
  int get hashCode =>
      kind.hashCode ^
      confirmationSource.hashCode ^
      transactionHash.hashCode ^
      candidateTransactionHash.hashCode ^
      finalVanPosition.hashCode ^
      voteCommitmentPositions.hashCode ^
      diagnostic.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiChainSubmissionOutcome &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          confirmationSource == other.confirmationSource &&
          transactionHash == other.transactionHash &&
          candidateTransactionHash == other.candidateTransactionHash &&
          finalVanPosition == other.finalVanPosition &&
          voteCommitmentPositions == other.voteCommitmentPositions &&
          diagnostic == other.diagnostic;
}

enum ApiChainDiagnosticKind {
  ambiguousDispatch,
  ambiguousAttemptsExhausted,
  nullifierAlreadySpent,
  trackingWindowExpired,
  chainRejected,
  reconciliationPending,
  invalidProtocolResponse,
  recoveryUnavailable,
  storageFailure,
}

class ApiChainDiagnostic {
  final ApiChainDiagnosticKind kind;
  final String message;

  const ApiChainDiagnostic({required this.kind, required this.message});

  @override
  int get hashCode => kind.hashCode ^ message.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiChainDiagnostic &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          message == other.message;
}

enum ApiChainConfirmationSource { hash, tree, legacyImport, legacyProjection }

class ApiChainSubmissionFailure {
  final ApiChainSubmissionFailureKind kind;
  final ApiChainSubmissionFailureState? strongestState;
  final String message;

  const ApiChainSubmissionFailure({
    required this.kind,
    this.strongestState,
    required this.message,
  });

  @override
  int get hashCode =>
      kind.hashCode ^ strongestState.hashCode ^ message.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiChainSubmissionFailure &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          strongestState == other.strongestState &&
          message == other.message;
}

class ApiChainSubmissionFailureState {
  final ApiChainSubmissionState state;
  final ApiChainSubmissionStateEvidence evidence;

  const ApiChainSubmissionFailureState({
    required this.state,
    required this.evidence,
  });

  @override
  int get hashCode => state.hashCode ^ evidence.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiChainSubmissionFailureState &&
          runtimeType == other.runtimeType &&
          state == other.state &&
          evidence == other.evidence;
}

enum ApiChainSubmissionState {
  submitting,
  tracking,
  recovering,
  submittedWithoutHash,
  confirmed,
  legacyConfirmed,
  rejected,
}

enum ApiChainSubmissionStateEvidence { durable, knownPossiblyDispatched }

enum ApiChainSubmissionFailureKind {
  invalidInput,
  invariantViolation,
  storage,
  transport,
  protocol,
}

/// Progress event emitted while building, proving, and signing a delegation payload.
///
/// A terminal `"result"` event carries `signed_delegation_payload`; earlier
/// phase events only describe local preparation progress.
class ApiDelegationProofEvent {
  final String phase;
  final double? proofProgress;
  final SignedDelegationPayloadView? signedDelegationPayload;

  const ApiDelegationProofEvent({
    required this.phase,
    this.proofProgress,
    this.signedDelegationPayload,
  });

  @override
  int get hashCode =>
      phase.hashCode ^
      proofProgress.hashCode ^
      signedDelegationPayload.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiDelegationProofEvent &&
          runtimeType == other.runtimeType &&
          phase == other.phase &&
          proofProgress == other.proofProgress &&
          signedDelegationPayload == other.signedDelegationPayload;
}

/// Progress event emitted while building ZKP2 vote commitments.
///
/// A terminal `"result"` event carries the completed commitment set; earlier
/// phase events include the active `(proposal_id, bundle_index)` pair.
class ApiVoteCommitEvent {
  final String phase;
  final int? proposalId;
  final int? bundleIndex;
  final double? proofProgress;
  final ApiSignedVoteCommitments? commitments;

  const ApiVoteCommitEvent({
    required this.phase,
    this.proposalId,
    this.bundleIndex,
    this.proofProgress,
    this.commitments,
  });

  @override
  int get hashCode =>
      phase.hashCode ^
      proposalId.hashCode ^
      bundleIndex.hashCode ^
      proofProgress.hashCode ^
      commitments.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiVoteCommitEvent &&
          runtimeType == other.runtimeType &&
          phase == other.phase &&
          proposalId == other.proposalId &&
          bundleIndex == other.bundleIndex &&
          proofProgress == other.proofProgress &&
          commitments == other.commitments;
}

/// Prepared singleton or atomic-batch commitments without chain wire payloads.
///
/// `batch_digest` is present only when every commitment belongs to one atomic
/// batch. Chain submission reloads the canonical request body from durable SDK
/// state, so neither that body nor individual submission payloads cross FRB.
class ApiSignedVoteCommitments {
  final int bundleIndex;
  final List<SignedVoteCommitmentView> commitments;
  final Uint8List? batchDigest;

  const ApiSignedVoteCommitments({
    required this.bundleIndex,
    required this.commitments,
    this.batchDigest,
  });

  @override
  int get hashCode =>
      bundleIndex.hashCode ^ commitments.hashCode ^ batchDigest.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiSignedVoteCommitments &&
          runtimeType == other.runtimeType &&
          bundleIndex == other.bundleIndex &&
          commitments == other.commitments &&
          batchDigest == other.batchDigest;
}

/// Canonical helper fleet and readiness-ranked prefix for initial planning.
class ApiVotingHelperPreflight {
  /// Complete configured helper fleet in canonical caller order.
  final List<String> configuredHelperUrls;

  /// Ready helpers in the same relative order as the configured fleet.
  final List<String> readyHelperUrls;

  const ApiVotingHelperPreflight({
    required this.configuredHelperUrls,
    required this.readyHelperUrls,
  });

  @override
  int get hashCode => configuredHelperUrls.hashCode ^ readyHelperUrls.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiVotingHelperPreflight &&
          runtimeType == other.runtimeType &&
          configuredHelperUrls == other.configuredHelperUrls &&
          readyHelperUrls == other.readyHelperUrls;
}

/// Definite and outcome-unknown results from one initial helper fan-out.
class ApiShareSubmissionReport {
  /// Helpers that definitively accepted the share.
  final List<String> acceptedUrls;

  /// Helpers that may have accepted the share before the response failed.
  final List<String> ambiguousUrls;

  /// Desired number of definite helper placements.
  final int targetCount;

  const ApiShareSubmissionReport({
    required this.acceptedUrls,
    required this.ambiguousUrls,
    required this.targetCount,
  });

  @override
  int get hashCode =>
      acceptedUrls.hashCode ^ ambiguousUrls.hashCode ^ targetCount.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiShareSubmissionReport &&
          runtimeType == other.runtimeType &&
          acceptedUrls == other.acceptedUrls &&
          ambiguousUrls == other.ambiguousUrls &&
          targetCount == other.targetCount;
}

/// One share processed by commitment-wide initial delivery.
class ApiShareDeliveryOutcome {
  final int shareIndex;
  final ApiShareSubmissionReport submission;

  const ApiShareDeliveryOutcome({
    required this.shareIndex,
    required this.submission,
  });

  @override
  int get hashCode => shareIndex.hashCode ^ submission.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiShareDeliveryOutcome &&
          runtimeType == other.runtimeType &&
          shareIndex == other.shareIndex &&
          submission == other.submission;
}

/// Commitment-wide helper delivery result.
class ApiShareBatchDeliveryReport {
  final List<ApiShareDeliveryOutcome> deliveries;
  final Uint32List pendingShareIndices;
  final bool cancelled;
  final bool legacyBestEffort;

  const ApiShareBatchDeliveryReport({
    required this.deliveries,
    required this.pendingShareIndices,
    required this.cancelled,
    required this.legacyBestEffort,
  });

  @override
  int get hashCode =>
      deliveries.hashCode ^
      pendingShareIndices.hashCode ^
      cancelled.hashCode ^
      legacyBestEffort.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiShareBatchDeliveryReport &&
          runtimeType == other.runtimeType &&
          deliveries == other.deliveries &&
          pendingShareIndices == other.pendingShareIndices &&
          cancelled == other.cancelled &&
          legacyBestEffort == other.legacyBestEffort;
}
