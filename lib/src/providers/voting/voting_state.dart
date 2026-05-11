import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

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
  final Map<String, dynamic> rawJson;

  const VotingRoundView({
    required this.roundId,
    required this.title,
    required this.status,
    this.endorsed = false,
    this.unverified = false,
    this.rawJson = const {},
  });

  factory VotingRoundView.fromSummary(
    VotingRoundSummary summary, {
    required bool endorsed,
  }) {
    return VotingRoundView(
      roundId: summary.roundId,
      title: summary.title,
      status: summary.status,
      endorsed: endorsed,
      unverified: !endorsed,
      rawJson: summary.rawJson,
    );
  }

  VotingRoundView copyWith({bool? endorsed, bool? unverified}) {
    return VotingRoundView(
      roundId: roundId,
      title: title,
      status: status,
      endorsed: endorsed ?? this.endorsed,
      unverified: unverified ?? this.unverified,
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
  resolvingPir,
  loadingWitnesses,
  readyToDelegate,
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
  final String? message;

  const VotingSessionProgress({
    required this.phase,
    this.bundleIndex,
    this.proposalId,
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
      roundId: _stringFromJson(json, const ['vote_round_id', 'round_id', 'id']),
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
}

/// Immutable state for a single `votingSessionProvider(roundId)` instance.
///
/// State keeps bundle-indexed delegation progress and bundle/proposal-indexed
/// vote progress separate so multi-bundle recovery does not collapse into a
/// single ambiguous "current vote" marker.
class VotingSessionState {
  final String roundId;
  final VotingSessionPhase phase;
  final VotingConfig? config;
  final VotingRoundDetails? round;
  final VotingResumePlan? resumePlan;
  final Uri? pirEndpoint;
  final UnmodifiableListView<PirSnapshotEndpointDiagnostic> pirDiagnostics;
  final UnmodifiableMapView<int, VotingSessionProgress> delegationProgress;
  final UnmodifiableMapView<VotingVoteKey, VotingSessionProgress> voteProgress;
  final int? currentBundleIndex;
  final VotingVoteKey? currentVoteKey;
  final VotingSessionError? error;

  VotingSessionState({
    required this.roundId,
    this.phase = VotingSessionPhase.idle,
    this.config,
    this.round,
    this.resumePlan,
    this.pirEndpoint,
    List<PirSnapshotEndpointDiagnostic> pirDiagnostics = const [],
    Map<int, VotingSessionProgress> delegationProgress = const {},
    Map<VotingVoteKey, VotingSessionProgress> voteProgress = const {},
    this.currentBundleIndex,
    this.currentVoteKey,
    this.error,
  }) : pirDiagnostics = UnmodifiableListView(pirDiagnostics),
       delegationProgress = UnmodifiableMapView(delegationProgress),
       voteProgress = UnmodifiableMapView(voteProgress);

  bool get hasError => phase == VotingSessionPhase.error;

  VotingSessionState copyWith({
    VotingSessionPhase? phase,
    VotingConfig? config,
    VotingRoundDetails? round,
    VotingResumePlan? resumePlan,
    Uri? pirEndpoint,
    List<PirSnapshotEndpointDiagnostic>? pirDiagnostics,
    Map<int, VotingSessionProgress>? delegationProgress,
    Map<VotingVoteKey, VotingSessionProgress>? voteProgress,
    int? currentBundleIndex,
    bool clearCurrentBundleIndex = false,
    VotingVoteKey? currentVoteKey,
    bool clearCurrentVoteKey = false,
    VotingSessionError? error,
    bool clearError = false,
  }) {
    return VotingSessionState(
      roundId: roundId,
      phase: phase ?? this.phase,
      config: config ?? this.config,
      round: round ?? this.round,
      resumePlan: resumePlan ?? this.resumePlan,
      pirEndpoint: pirEndpoint ?? this.pirEndpoint,
      pirDiagnostics: pirDiagnostics ?? this.pirDiagnostics,
      delegationProgress: delegationProgress ?? this.delegationProgress,
      voteProgress: voteProgress ?? this.voteProgress,
      currentBundleIndex: clearCurrentBundleIndex
          ? null
          : currentBundleIndex ?? this.currentBundleIndex,
      currentVoteKey: clearCurrentVoteKey
          ? null
          : currentVoteKey ?? this.currentVoteKey,
      error: clearError ? null : error ?? this.error,
    );
  }
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
    if (value is num) return value.toInt();
    return int.parse(value.toString());
  }
  throw FormatException('Missing required int: ${keys.first}');
}

Uint8List _bytesFromJson(Map<String, dynamic> json, List<String> keys) {
  final value = _stringFromJson(json, keys);
  final hex = value.startsWith('0x') ? value.substring(2) : value;
  if (hex.length.isEven && RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }
  return Uint8List.fromList(base64Decode(value));
}
