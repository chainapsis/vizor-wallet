import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_flow_models.dart';

/// Coordinates durable delegation snapshot preparation across voting routes.
///
/// This provider is intentionally app-scoped rather than round-session-scoped.
/// A route can dispose its session notifier while Rust continues writing the
/// durable snapshot, and the next route will still join that operation.
final votingSnapshotPreparationCoordinatorProvider =
    Provider<VotingSnapshotPreparationCoordinator>((ref) {
      return VotingSnapshotPreparationCoordinator();
    });

class VotingSnapshotPreparationCoordinator {
  final Map<VotingSessionKey, Future<bool>> _inFlight = {};

  /// Runs at most one active [operation] for [key].
  ///
  /// Concurrent callers join the same future. Completion is deliberately not
  /// memoized here: durable Rust status is the source of truth, including after
  /// route replacement, failed returns, and process restart.
  Future<bool> run(VotingSessionKey key, Future<bool> Function() operation) {
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final completer = Completer<bool>();
    _inFlight[key] = completer.future;
    unawaited(_run(key, operation, completer));
    return completer.future;
  }

  Future<bool>? inFlight(VotingSessionKey key) => _inFlight[key];

  Future<void> _run(
    VotingSessionKey key,
    Future<bool> Function() operation,
    Completer<bool> completer,
  ) async {
    var succeeded = false;
    try {
      succeeded = await operation();
    } catch (_) {
      // Snapshot preparation is speculative. Keep the failure retryable and
      // let the operation log its useful context.
    } finally {
      if (identical(_inFlight[key], completer.future)) {
        _inFlight.remove(key);
      }
      completer.complete(succeeded);
    }
  }
}
