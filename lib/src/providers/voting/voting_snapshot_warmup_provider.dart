import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final votingSnapshotWarmupRetryDelaysProvider = Provider<List<Duration>>((ref) {
  return const [
    Duration(seconds: 5),
    Duration(seconds: 30),
    Duration(minutes: 2),
  ];
});

enum VotingSnapshotWarmupDisposition {
  ready,
  retryableMiss,
  terminalMiss,
  stale,
}

@immutable
class VotingSnapshotWarmupResult {
  const VotingSnapshotWarmupResult._(
    this.disposition, {
    this.reason,
    this.error,
    this.bundleCount,
    this.pirEndpoint,
  });

  const VotingSnapshotWarmupResult.ready({
    String? reason,
    int? bundleCount,
    Uri? pirEndpoint,
  }) : this._(
         VotingSnapshotWarmupDisposition.ready,
         reason: reason,
         bundleCount: bundleCount,
         pirEndpoint: pirEndpoint,
       );

  const VotingSnapshotWarmupResult.retryableMiss({
    required String reason,
    Object? error,
  }) : this._(
         VotingSnapshotWarmupDisposition.retryableMiss,
         reason: reason,
         error: error,
       );

  const VotingSnapshotWarmupResult.terminalMiss({
    required String reason,
    Object? error,
  }) : this._(
         VotingSnapshotWarmupDisposition.terminalMiss,
         reason: reason,
         error: error,
       );

  const VotingSnapshotWarmupResult.stale({String? reason})
    : this._(VotingSnapshotWarmupDisposition.stale, reason: reason);

  final VotingSnapshotWarmupDisposition disposition;
  final String? reason;
  final Object? error;
  final int? bundleCount;
  final Uri? pirEndpoint;

  bool get isReady => disposition == VotingSnapshotWarmupDisposition.ready;
  bool get shouldRearm =>
      disposition == VotingSnapshotWarmupDisposition.retryableMiss ||
      disposition == VotingSnapshotWarmupDisposition.stale;
}

/// Host-side single-flight for snapshot bundle preparation.
///
/// Proof generation is deliberately not tracked here. The voting SDK owns
/// per-bundle proof locking, persistence, and reuse; this coordinator only
/// lets review and submission share the prerequisite snapshot/PIR work.
class VotingSnapshotWarmupCoordinator {
  final Map<String, Future<VotingSnapshotWarmupResult>> _inFlight = {};
  final Map<String, VotingSnapshotWarmupResult> _completed = {};
  final Map<String, Completer<void>> _foregroundRequests = {};

  Future<VotingSnapshotWarmupResult> runOrJoin({
    required String key,
    required Future<VotingSnapshotWarmupResult> Function() operation,
  }) {
    final completed = _completed[key];
    if (completed != null) return Future.value(completed);
    final existing = _inFlight[key];
    if (existing != null) return existing;

    _foregroundRequests[key] = Completer<void>();
    late final Future<VotingSnapshotWarmupResult> tracked;
    tracked = Future<VotingSnapshotWarmupResult>.sync(operation)
        .then((result) {
          if (result.isReady) _completed[key] = result;
          return result;
        })
        .whenComplete(() {
          if (identical(_inFlight[key], tracked)) _inFlight.remove(key);
          _foregroundRequests.remove(key);
        });
    _inFlight[key] = tracked;
    return tracked;
  }

  /// The shared prerequisite a foreground caller should join, if any.
  Future<VotingSnapshotWarmupResult>? joinForForeground(String key) {
    final current = _inFlight[key];
    if (current != null) {
      final request = _foregroundRequests[key];
      if (request != null && !request.isCompleted) request.complete();
      return current;
    }
    return null;
  }

  Future<void> foregroundRequested(String key) =>
      _foregroundRequests[key]?.future ?? Future<void>.value();

  bool isForegroundRequested(String key) =>
      _foregroundRequests[key]?.isCompleted ?? false;

  @visibleForTesting
  int get inFlightCount => _inFlight.length;
}

final votingSnapshotWarmupProvider = Provider((ref) {
  return VotingSnapshotWarmupCoordinator();
});
