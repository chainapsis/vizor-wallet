import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../../core/formatting/date_format.dart';
import '../../core/formatting/hex_codec.dart';
import '../../features/voting/voting_resume_plan.dart';
import '../../rust/api/voting.dart' as rust_voting;
import '../../services/voting/pir_snapshot_resolver.dart';
import '../../services/voting/voting_models.dart';

/// Poll-list row consumed by the upcoming voting screens.
///
/// Endorsement is deliberately modeled separately from round authenticity:
/// authenticated-but-not-endorsed rounds remain visible with [unverified] set.
class VotingRoundView {
  final String roundId;
  final String title;
  final String status;
  final bool endorsed;
  final bool unverified;
  final bool voted;
  final Map<String, dynamic> rawJson;

  const VotingRoundView({
    required this.roundId,
    required this.title,
    required this.status,
    this.endorsed = false,
    this.unverified = false,
    this.voted = false,
    this.rawJson = const {},
  });

  factory VotingRoundView.fromSummary(
    VotingRoundSummary summary, {
    required bool endorsed,
    bool voted = false,
  }) {
    return VotingRoundView(
      roundId: summary.roundId,
      title: summary.title,
      status: summary.status,
      endorsed: endorsed,
      unverified: !endorsed,
      voted: voted,
      rawJson: summary.rawJson,
    );
  }

  VotingRoundView copyWith({bool? endorsed, bool? unverified, bool? voted}) {
    return VotingRoundView(
      roundId: roundId,
      title: title,
      status: status,
      endorsed: endorsed ?? this.endorsed,
      unverified: unverified ?? this.unverified,
      voted: voted ?? this.voted,
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

  const VotingSessionError({
    required this.message,
    this.cause,
    this.pirDiagnostics = const [],
  });
}

/// Chain round payload after parsing fields needed by Rust voting APIs.
///
/// Dynamic config authenticates round metadata, while the vote server returns
/// the chain-bound round details such as snapshot height and tree roots.
class VotingRoundDetails {
  static const double _lastMomentBufferFraction = 0.4;
  static const Duration _lastMomentBufferMax = Duration(hours: 6);

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
      roundId: _roundIdFromJson(json),
      title: _optionalStringFromJson(json, const ['title', 'name']) ?? '',
      status: status.status,
      snapshotHeight: _intFromJson(json, const ['snapshot_height']),
      eaPk: _bytesFromJson(json, const ['ea_pk', 'eaPk']),
      ncRoot: _bytesFromJson(json, const ['nc_root', 'ncRoot']),
      nullifierImtRoot: _bytesFromJson(json, const [
        'nullifier_imt_root',
        'nullifierIMTRoot',
        'nullifierImtRoot',
      ]),
      rawJson: json,
    );
  }

  rust_voting.ApiVotingRoundParams toRoundParams() {
    return rust_voting.ApiVotingRoundParams(
      voteRoundId: roundId,
      snapshotHeight: BigInt.from(snapshotHeight),
      eaPk: eaPk,
      ncRoot: ncRoot,
      nullifierImtRoot: nullifierImtRoot,
    );
  }

  String get sessionJson => jsonEncode(rawJson);

  DateTime? get voteEndTime => _dateFromJson(rawJson, const [
    'vote_end_time',
    'voteEndTime',
    'end_time',
    'endTime',
    'ends_at',
    'endsAt',
    'deadline',
  ]);

  DateTime? get ceremonyStart => _dateFromJson(rawJson, const [
    'ceremony_phase_start',
    'ceremonyPhaseStart',
    'start_time',
    'startTime',
    'starts_at',
    'startsAt',
  ]);

  Duration? get lastMomentBuffer {
    final start = ceremonyStart;
    final end = voteEndTime;
    if (start == null || end == null) return null;
    final duration = end.difference(start);
    if (duration <= Duration.zero) return null;
    final buffer = Duration(
      milliseconds: (duration.inMilliseconds * _lastMomentBufferFraction)
          .round(),
    );
    return buffer < _lastMomentBufferMax ? buffer : _lastMomentBufferMax;
  }

  bool isLastMoment([DateTime? now]) {
    final end = voteEndTime;
    final buffer = lastMomentBuffer;
    if (end == null || buffer == null) return false;
    final threshold = end.subtract(buffer);
    final current = (now ?? DateTime.now()).toUtc();
    return current.isAfter(threshold) || current.isAtSameMomentAs(threshold);
  }
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
  final VotingConfig? config;
  final VotingRoundDetails? round;
  final VotingResumePlan? resumePlan;
  final Uri? pirEndpoint;
  final BigInt? eligibleWeightZatoshi;
  final int? walletScannedHeight;
  final int? walletSnapshotHeight;
  final int? walletChainTipHeight;
  final bool isHardwareAccount;
  final UnmodifiableListView<PirSnapshotEndpointDiagnostic> pirDiagnostics;
  final UnmodifiableMapView<int, VotingSessionProgress> delegationProgress;
  final UnmodifiableMapView<VotingVoteKey, VotingSessionProgress> voteProgress;
  final UnmodifiableMapView<int, rust_voting.ApiKeystoneSignatureRecord>
  keystoneSignatures;
  final rust_voting.ApiKeystoneDelegationRequest? keystoneSigningRequest;
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
    this.resumePlan,
    this.pirEndpoint,
    this.eligibleWeightZatoshi,
    this.walletScannedHeight,
    this.walletSnapshotHeight,
    this.walletChainTipHeight,
    this.isHardwareAccount = false,
    List<PirSnapshotEndpointDiagnostic> pirDiagnostics = const [],
    Map<int, VotingSessionProgress> delegationProgress = const {},
    Map<VotingVoteKey, VotingSessionProgress> voteProgress = const {},
    Map<int, rust_voting.ApiKeystoneSignatureRecord> keystoneSignatures =
        const {},
    this.keystoneSigningRequest,
    this.keystoneScanError,
    this.currentBundleIndex,
    this.currentVoteKey,
    this.voteSubmissionCompletedCount = 0,
    this.voteSubmissionTotalCount = 0,
    this.voteSubmissionProgress,
    this.error,
  }) : pirDiagnostics = UnmodifiableListView(pirDiagnostics),
       delegationProgress = UnmodifiableMapView(delegationProgress),
       voteProgress = UnmodifiableMapView(voteProgress),
       keystoneSignatures = UnmodifiableMapView(keystoneSignatures);

  bool get hasError => phase == VotingSessionPhase.error;

  int get keystoneResolvedBundlePrefixCount =>
      resolvedKeystoneBundlePrefixCount(
        plan: resumePlan,
        signatures: keystoneSignatures,
      );

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
    VotingConfig? config,
    VotingRoundDetails? round,
    VotingResumePlan? resumePlan,
    Uri? pirEndpoint,
    BigInt? eligibleWeightZatoshi,
    int? walletScannedHeight,
    int? walletSnapshotHeight,
    int? walletChainTipHeight,
    bool clearWalletSyncReadiness = false,
    bool? isHardwareAccount,
    List<PirSnapshotEndpointDiagnostic>? pirDiagnostics,
    Map<int, VotingSessionProgress>? delegationProgress,
    Map<VotingVoteKey, VotingSessionProgress>? voteProgress,
    Map<int, rust_voting.ApiKeystoneSignatureRecord>? keystoneSignatures,
    rust_voting.ApiKeystoneDelegationRequest? keystoneSigningRequest,
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
      resumePlan: resumePlan ?? this.resumePlan,
      pirEndpoint: pirEndpoint ?? this.pirEndpoint,
      eligibleWeightZatoshi:
          eligibleWeightZatoshi ?? this.eligibleWeightZatoshi,
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
      keystoneSigningRequest: clearKeystoneSigningRequest
          ? null
          : keystoneSigningRequest ?? this.keystoneSigningRequest,
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
  required VotingResumePlan? plan,
  required Map<int, rust_voting.ApiKeystoneSignatureRecord> signatures,
}) {
  final bundleCount = plan?.bundleCount ?? 0;
  if (bundleCount <= 0) return 0;

  final resolved = <int>{};
  for (final bundleIndex in signatures.keys) {
    if (bundleIndex >= 0 && bundleIndex < bundleCount) {
      resolved.add(bundleIndex);
    }
  }
  final phases = plan?.delegationPhasesByIndex ?? const <int, String>{};
  for (final entry in phases.entries) {
    if (entry.key >= 0 &&
        entry.key < bundleCount &&
        _isResolvedKeystoneDelegationPhase(entry.value)) {
      resolved.add(entry.key);
    }
  }

  var count = 0;
  while (count < bundleCount && resolved.contains(count)) {
    count += 1;
  }
  return count;
}

bool _isResolvedKeystoneDelegationPhase(String phase) {
  return phase == VotingWorkflowPhase.submittedDelegation ||
      phase == VotingWorkflowPhase.confirmed;
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

String _roundIdFromJson(Map<String, dynamic> json) {
  final voteRoundId = _optionalStringFromJson(json, const ['vote_round_id']);
  if (voteRoundId != null && voteRoundId.isNotEmpty) {
    return _normalizeRoundId(voteRoundId);
  }
  return _stringFromJson(json, const ['round_id', 'id']);
}

String _normalizeRoundId(String value) {
  final trimmed = value.trim();
  if (_isHexRoundId(trimmed)) return trimmed.toLowerCase();
  try {
    final bytes = base64Decode(trimmed);
    if (bytes.length == 32) return bytesToHex(bytes);
  } on FormatException {
    // Early fixtures used human-readable ids; keep those readable in tests.
  }
  return trimmed;
}

int _intFromJson(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.parse(value.toString());
  }
  throw FormatException('Missing required int: ${keys.first}');
}

Uint8List _bytesFromJson(Map<String, dynamic> json, List<String> keys) {
  final value = _stringFromJson(json, keys);
  final hex = value.startsWith('0x') ? value.substring(2) : value;
  if (hex.length.isEven && RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
    return hexToBytes(hex);
  }
  return Uint8List.fromList(base64Decode(value));
}

DateTime? _dateFromJson(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = _valueFromJson(json, key);
    final date = parseFlexibleDate(value);
    if (date != null) return date.toUtc();
  }
  return null;
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

bool _isHexRoundId(String value) {
  if (value.length != 64) return false;
  return RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
}
