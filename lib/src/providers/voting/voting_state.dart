import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../../core/formatting/date_format.dart';
import '../../features/voting/voting_resume_plan.dart';
import '../../rust/third_party/zcash_voting/config.dart' as rust_config;
import '../../rust/third_party/zcash_voting/delegate.dart' as rust_delegate;
import '../../rust/third_party/zcash_voting/wire.dart' as rust_wire;
import '../../services/voting/pir_snapshot_resolver.dart';
import '../../services/voting/voting_models.dart';

/// Poll-list row consumed by the upcoming voting screens.
class VotingRoundView {
  final String roundId;
  final String title;
  final String status;
  final bool voted;
  final bool inProgress;
  final bool recoveryError;
  final Map<String, dynamic> rawJson;

  const VotingRoundView({
    required this.roundId,
    required this.title,
    required this.status,
    this.voted = false,
    this.inProgress = false,
    this.recoveryError = false,
    this.rawJson = const {},
  });

  factory VotingRoundView.fromSummary(
    VotingRoundSummary summary, {
    bool voted = false,
    bool inProgress = false,
    bool recoveryError = false,
  }) {
    return VotingRoundView(
      roundId: summary.roundId,
      title: summary.title,
      status: summary.status,
      voted: voted,
      inProgress: inProgress,
      recoveryError: recoveryError,
      rawJson: summary.rawJson,
    );
  }

  VotingRoundView copyWith({
    bool? voted,
    bool? inProgress,
    bool? recoveryError,
  }) {
    return VotingRoundView(
      roundId: roundId,
      title: title,
      status: status,
      voted: voted ?? this.voted,
      inProgress: inProgress ?? this.inProgress,
      recoveryError: recoveryError ?? this.recoveryError,
      rawJson: rawJson,
    );
  }
}

/// High-level UI phase for one round's voting session.
///
/// The enum mirrors the ZCA-392 state machine and is intentionally broader than
/// individual Rust stream phases so screens can render stable sections while
/// lower-level proof progress changes.
enum VotingSessionPhase {
  idle,
  waitingForWalletSync,
  resolvingPir,
  loadingWitnesses,
  readyToDelegate,
  keystoneSigning,
  delegating,
  delegated,
  readyToVote,
  syncingVoteTree,
  castingVotes,
  submittingShares,
  done,
  error,
}

/// Last known progress event for a bundle or bundle/proposal key.
class VotingSessionProgress {
  final String phase;
  final int? bundleIndex;
  final int? proposalId;
  final double? proofProgress;
  final String? message;

  const VotingSessionProgress({
    required this.phase,
    this.bundleIndex,
    this.proposalId,
    this.proofProgress,
    this.message,
  });
}

/// Error details surfaced by [VotingSessionState].
///
/// PIR diagnostics are carried separately because those failures are expected
/// user-facing cases: an endpoint can be behind, ahead, malformed, or down.
class VotingSessionError {
  final String message;
  final Object? cause;
  final List<PirSnapshotEndpointDiagnostic> pirDiagnostics;

  /// True when the account cannot vote in this round (no spendable notes or
  /// too little eligible weight). Such errors are not retryable and switch
  /// the UI to its ineligible presentation.
  final bool isEligibilityFailure;

  const VotingSessionError({
    required this.message,
    this.cause,
    this.pirDiagnostics = const [],
    this.isEligibilityFailure = false,
  });
}

/// Chain round payload after parsing fields needed by Rust voting APIs.
///
/// Dynamic config authenticates round metadata, while the vote server returns
/// the chain-bound round details such as snapshot height and tree roots.
class VotingRoundDetails {
  final String roundId;
  final String title;
  final String status;
  final int snapshotHeight;
  final Uint8List eaPk;
  final Uint8List ncRoot;
  final Uint8List nullifierImtRoot;
  final Map<String, dynamic> rawJson;

  const VotingRoundDetails({
    required this.roundId,
    required this.title,
    required this.status,
    required this.snapshotHeight,
    required this.eaPk,
    required this.ncRoot,
    required this.nullifierImtRoot,
    required this.rawJson,
  });

  factory VotingRoundDetails.fromStatus(VotingRoundStatus status) {
    final json = status.rawJson;
    return VotingRoundDetails(
      roundId: status.roundId,
      title: _optionalStringFromJson(json, const ['title']) ?? '',
      status: status.status,
      snapshotHeight: _intFromJson(json, const ['snapshot_height']),
      eaPk: _fixedBytesFromJson(json, const ['ea_pk'], 32),
      ncRoot: _fixedBytesFromJson(json, const ['nc_root'], 32),
      nullifierImtRoot: _fixedBytesFromJson(json, const [
        'nullifier_imt_root',
      ], 32),
      rawJson: json,
    );
  }

  String get sessionJson => jsonEncode(rawJson);

  DateTime? get voteEndTime => _dateFromJson(rawJson, 'vote_end_time');

  DateTime? get ceremonyStart => _dateFromJson(rawJson, 'ceremony_phase_start');
}

DateTime? votingSessionVoteEndTime(String? sessionJson) {
  if (sessionJson == null) return null;
  try {
    final decoded = jsonDecode(sessionJson);
    if (decoded is! Map<String, dynamic>) return null;
    return _dateFromJson(decoded, 'vote_end_time');
  } on FormatException {
    return null;
  }
}

/// One compact Keystone signature correlated to a pending voting bundle.
class VotingKeystoneBatchSignature {
  final int bundleIndex;

  /// PCZT value-pool tag. `0` is Orchard and `1` is Ironwood.
  final int pool;
  final int actionIndex;
  final List<int> signature;

  const VotingKeystoneBatchSignature({
    required this.bundleIndex,
    required this.pool,
    required this.actionIndex,
    required this.signature,
  });
}

/// Immutable state for a single `votingSessionProvider(roundId)` instance.
///
/// State keeps bundle-indexed delegation progress and bundle/proposal-indexed
/// vote progress separate so multi-bundle recovery does not collapse into a
/// single ambiguous "current vote" marker.
class VotingSessionState {
  final String roundId;

  /// Account UUID pinned to this session's Rust recovery and proof work.
  ///
  /// UI state such as vote drafts must use this value, not the live active
  /// account, so an account switch cannot submit choices for the wrong wallet.
  final String? accountUuid;

  final VotingSessionPhase phase;
  final rust_config.ResolvedVotingConfig? config;
  final VotingRoundDetails? round;

  /// Crate planner's derived resume plan for this round.
  ///
  /// Null before the crate planner has loaded for this session. Its projection
  /// fields drive foreground recovery, completed vote display, and next action
  /// selection.
  final rust_wire.RoundPlanView? roundPlan;
  final Uri? pirEndpoint;
  final BigInt? eligibleWeightZatoshi;

  /// Raw note value the privacy trim withholds from this round.
  ///
  /// Null until a Rust call reports it; zero means nothing was withheld. The
  /// eligibility preview fills it before delegation and the authoritative
  /// bundle layout replaces it once setup has run.
  final BigInt? privacyTrimDroppedValueZatoshi;
  final int? walletScannedHeight;
  final int? walletSnapshotHeight;
  final int? walletChainTipHeight;
  final bool isHardwareAccount;
  final UnmodifiableListView<PirSnapshotEndpointDiagnostic> pirDiagnostics;
  final UnmodifiableMapView<int, VotingSessionProgress> delegationProgress;
  final UnmodifiableMapView<VotingVoteKey, VotingSessionProgress> voteProgress;
  final UnmodifiableMapView<int, rust_wire.KeystoneSignatureRecord>
  keystoneSignatures;
  final UnmodifiableListView<rust_delegate.KeystoneSigningRequest>
  keystoneSigningRequests;
  final String? keystoneScanError;
  final int? currentBundleIndex;
  final VotingVoteKey? currentVoteKey;
  final int voteSubmissionCompletedCount;
  final int voteSubmissionTotalCount;
  final double? voteSubmissionProgress;
  final VotingSessionError? error;

  VotingSessionState({
    required this.roundId,
    this.accountUuid,
    this.phase = VotingSessionPhase.idle,
    this.config,
    this.round,
    this.roundPlan,
    this.pirEndpoint,
    this.eligibleWeightZatoshi,
    this.privacyTrimDroppedValueZatoshi,
    this.walletScannedHeight,
    this.walletSnapshotHeight,
    this.walletChainTipHeight,
    this.isHardwareAccount = false,
    List<PirSnapshotEndpointDiagnostic> pirDiagnostics = const [],
    Map<int, VotingSessionProgress> delegationProgress = const {},
    Map<VotingVoteKey, VotingSessionProgress> voteProgress = const {},
    Map<int, rust_wire.KeystoneSignatureRecord> keystoneSignatures = const {},
    List<rust_delegate.KeystoneSigningRequest> keystoneSigningRequests =
        const [],
    this.keystoneScanError,
    this.currentBundleIndex,
    this.currentVoteKey,
    this.voteSubmissionCompletedCount = 0,
    this.voteSubmissionTotalCount = 0,
    this.voteSubmissionProgress,
    this.error,
  }) : pirDiagnostics = UnmodifiableListView(
         List<PirSnapshotEndpointDiagnostic>.of(pirDiagnostics),
       ),
       delegationProgress = UnmodifiableMapView(
         Map<int, VotingSessionProgress>.of(delegationProgress),
       ),
       voteProgress = UnmodifiableMapView(
         Map<VotingVoteKey, VotingSessionProgress>.of(voteProgress),
       ),
       keystoneSignatures = UnmodifiableMapView(
         Map<int, rust_wire.KeystoneSignatureRecord>.of(keystoneSignatures),
       ),
       keystoneSigningRequests = UnmodifiableListView(
         List<rust_delegate.KeystoneSigningRequest>.of(keystoneSigningRequests),
       );

  bool get hasError => phase == VotingSessionPhase.error;

  bool get hasConfirmedVotingEligibility =>
      eligibleWeightZatoshi != null &&
      eligibleWeightZatoshi! > BigInt.zero &&
      error == null &&
      phase != VotingSessionPhase.error;

  int get keystoneResolvedBundlePrefixCount =>
      resolvedKeystoneBundlePrefixCount(
        roundPlan: roundPlan,
        signatures: keystoneSignatures,
      );

  rust_delegate.KeystoneSigningRequest? get keystoneSigningRequest =>
      keystoneSigningRequests.isEmpty ? null : keystoneSigningRequests.first;

  bool get canSkipRemainingKeystoneBundles {
    final request = keystoneSigningRequest;
    if (!isHardwareAccount ||
        phase != VotingSessionPhase.keystoneSigning ||
        request == null ||
        request.bundleCount <= 1) {
      return false;
    }
    final prefix = keystoneResolvedBundlePrefixCount;
    return prefix > 0 && prefix < request.bundleCount;
  }

  VotingSessionState copyWith({
    String? accountUuid,
    VotingSessionPhase? phase,
    rust_config.ResolvedVotingConfig? config,
    VotingRoundDetails? round,
    rust_wire.RoundPlanView? roundPlan,
    bool clearRoundPlan = false,
    Uri? pirEndpoint,
    BigInt? eligibleWeightZatoshi,
    BigInt? privacyTrimDroppedValueZatoshi,
    int? walletScannedHeight,
    int? walletSnapshotHeight,
    int? walletChainTipHeight,
    bool clearWalletSyncReadiness = false,
    bool? isHardwareAccount,
    List<PirSnapshotEndpointDiagnostic>? pirDiagnostics,
    Map<int, VotingSessionProgress>? delegationProgress,
    Map<VotingVoteKey, VotingSessionProgress>? voteProgress,
    Map<int, rust_wire.KeystoneSignatureRecord>? keystoneSignatures,
    List<rust_delegate.KeystoneSigningRequest>? keystoneSigningRequests,
    bool clearKeystoneSigningRequest = false,
    String? keystoneScanError,
    bool clearKeystoneScanError = false,
    int? currentBundleIndex,
    bool clearCurrentBundleIndex = false,
    VotingVoteKey? currentVoteKey,
    bool clearCurrentVoteKey = false,
    int? voteSubmissionCompletedCount,
    int? voteSubmissionTotalCount,
    double? voteSubmissionProgress,
    bool clearVoteSubmissionProgress = false,
    VotingSessionError? error,
    bool clearError = false,
  }) {
    return VotingSessionState(
      roundId: roundId,
      accountUuid: accountUuid ?? this.accountUuid,
      phase: phase ?? this.phase,
      config: config ?? this.config,
      round: round ?? this.round,
      roundPlan: clearRoundPlan ? null : roundPlan ?? this.roundPlan,
      pirEndpoint: pirEndpoint ?? this.pirEndpoint,
      eligibleWeightZatoshi:
          eligibleWeightZatoshi ?? this.eligibleWeightZatoshi,
      privacyTrimDroppedValueZatoshi:
          privacyTrimDroppedValueZatoshi ?? this.privacyTrimDroppedValueZatoshi,
      walletScannedHeight: clearWalletSyncReadiness
          ? null
          : walletScannedHeight ?? this.walletScannedHeight,
      walletSnapshotHeight: clearWalletSyncReadiness
          ? null
          : walletSnapshotHeight ?? this.walletSnapshotHeight,
      walletChainTipHeight: clearWalletSyncReadiness
          ? null
          : walletChainTipHeight ?? this.walletChainTipHeight,
      isHardwareAccount: isHardwareAccount ?? this.isHardwareAccount,
      pirDiagnostics: pirDiagnostics ?? this.pirDiagnostics,
      delegationProgress: delegationProgress ?? this.delegationProgress,
      voteProgress: voteProgress ?? this.voteProgress,
      keystoneSignatures: keystoneSignatures ?? this.keystoneSignatures,
      keystoneSigningRequests: clearKeystoneSigningRequest
          ? const []
          : keystoneSigningRequests ?? this.keystoneSigningRequests,
      keystoneScanError: clearKeystoneScanError
          ? null
          : keystoneScanError ?? this.keystoneScanError,
      currentBundleIndex: clearCurrentBundleIndex
          ? null
          : currentBundleIndex ?? this.currentBundleIndex,
      currentVoteKey: clearCurrentVoteKey
          ? null
          : currentVoteKey ?? this.currentVoteKey,
      voteSubmissionCompletedCount: clearVoteSubmissionProgress
          ? 0
          : voteSubmissionCompletedCount ?? this.voteSubmissionCompletedCount,
      voteSubmissionTotalCount: clearVoteSubmissionProgress
          ? 0
          : voteSubmissionTotalCount ?? this.voteSubmissionTotalCount,
      voteSubmissionProgress: clearVoteSubmissionProgress
          ? null
          : voteSubmissionProgress ?? this.voteSubmissionProgress,
      error: clearError ? null : error ?? this.error,
    );
  }
}

int resolvedKeystoneBundlePrefixCount({
  required rust_wire.RoundPlanView? roundPlan,
  required Map<int, rust_wire.KeystoneSignatureRecord> signatures,
}) {
  final bundleCount = roundPlanBundleCount(roundPlan);
  if (bundleCount <= 0) return 0;

  final resolved = <int>{};
  for (final bundleIndex in signatures.keys) {
    if (bundleIndex >= 0 && bundleIndex < bundleCount) {
      resolved.add(bundleIndex);
    }
  }
  for (final status
      in roundPlan?.delegationStatuses ??
          const <rust_wire.DelegationStatusView>[]) {
    if (status.bundleIndex >= 0 &&
        status.bundleIndex < bundleCount &&
        _isResolvedKeystoneDelegationPhase(status.phase)) {
      resolved.add(status.bundleIndex);
    }
  }

  var count = 0;
  while (count < bundleCount && resolved.contains(count)) {
    count += 1;
  }
  return count;
}

bool _isResolvedKeystoneDelegationPhase(rust_wire.WorkflowPhaseView phase) {
  return phase == rust_wire.WorkflowPhaseView.submittedDelegation ||
      phase == rust_wire.WorkflowPhaseView.confirmed;
}

String _stringFromJson(Map<String, dynamic> json, List<String> keys) {
  final value = _optionalStringFromJson(json, keys);
  if (value == null || value.isEmpty) {
    throw FormatException('Missing required string: ${keys.first}');
  }
  return value;
}

String? _optionalStringFromJson(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    return value.toString();
  }
  return null;
}

int _intFromJson(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is int) return value;
    if (value is num) {
      if (value.isFinite && value == value.truncateToDouble()) {
        return value.toInt();
      }
      throw FormatException('$key must be an integer');
    }
    return int.parse(value.toString());
  }
  throw FormatException('Missing required int: ${keys.first}');
}

Uint8List _bytesFromJson(Map<String, dynamic> json, List<String> keys) {
  final value = _stringFromJson(json, keys);
  try {
    return Uint8List.fromList(base64Decode(value));
  } on FormatException catch (error) {
    throw FormatException('${keys.first} must be base64: ${error.message}');
  }
}

Uint8List _fixedBytesFromJson(
  Map<String, dynamic> json,
  List<String> keys,
  int expectedLength,
) {
  final bytes = _bytesFromJson(json, keys);
  if (bytes.length != expectedLength) {
    throw FormatException('${keys.first} must decode to $expectedLength bytes');
  }
  return bytes;
}

DateTime? _dateFromJson(Map<String, dynamic> json, String key) {
  return parseFlexibleDate(_valueFromJson(json, key))?.toUtc();
}

Object? _valueFromJson(Object? value, String key) {
  if (value is! Map) return null;
  if (value.containsKey(key)) return value[key];
  for (final entry in value.entries) {
    if (entry.key.toString() == key) return entry.value;
  }
  for (final entry in value.entries) {
    final nested = entry.value;
    if (nested is Map) {
      final match = _valueFromJson(nested, key);
      if (match != null) return match;
    }
  }
  return null;
}
