import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_flow_models.dart';

/// Coordinates durable snapshot-bundle preparation across voting routes.
///
/// This provider is intentionally app-scoped rather than round-session-scoped.
/// A route can dispose its session notifier while Rust continues writing the
/// durable snapshot, and the next route will still join that operation.
final votingSnapshotPrecomputeCoordinatorProvider =
    Provider<VotingSnapshotPrecomputeCoordinator>((ref) {
      return VotingSnapshotPrecomputeCoordinator();
    });

class VotingSnapshotPrecomputeCoordinator {
  final Map<VotingSessionKey, Future<bool>> _inFlight = {};
  final Set<VotingSessionKey> _completed = {};

  /// Runs [operation] once until it succeeds for [key].
  ///
  /// Concurrent callers join the same future. A successful operation remains
  /// completed for the lifetime of the app provider container. Failures are
  /// deliberately not memoized, so a later route/session can retry.
  Future<bool> run(VotingSessionKey key, Future<bool> Function() operation) {
    if (_completed.contains(key)) return Future<bool>.value(true);

    final existing = _inFlight[key];
    if (existing != null) return existing;

    final completer = Completer<bool>();
    _inFlight[key] = completer.future;
    unawaited(_run(key, operation, completer));
    return completer.future;
  }

  Future<bool>? inFlight(VotingSessionKey key) => _inFlight[key];

  bool isCompleted(VotingSessionKey key) => _completed.contains(key);

  Future<void> _run(
    VotingSessionKey key,
    Future<bool> Function() operation,
    Completer<bool> completer,
  ) async {
    var succeeded = false;
    try {
      succeeded = await operation();
      if (succeeded) _completed.add(key);
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
