import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_flow_models.dart';

typedef VotingShareTrackingStopper = Future<void> Function();
typedef VotingSyncRecoveryStopper = Future<void> Function();

/// Coordinates background voting work with destructive account mutations.
///
/// Share tracking and stalled-sync recovery both retain account-scoped DB
/// access after the foreground submission guard is released. Account removal
/// and reset quiesce this registry before deleting durable wallet state.
class VotingShareTrackingRegistry {
  final Map<VotingSessionKey, _VotingShareTrackingRegistration> _sessions = {};
  final Map<VotingSessionKey, _VotingSyncRecoveryRegistration> _recoveries = {};
  final Set<Completer<void>> _discoveries = {};
  final Set<VoidCallback> _restoreRequestListeners = {};
  final Set<String> _quiescedAccounts = {};
  int _globalQuiescenceDepth = 0;

  /// Starts discovery before its first asynchronous operation.
  ///
  /// Destructive wallet operations block new discovery and await the returned
  /// lease, so sidecar reads cannot outlive the state they are inspecting.
  VoidCallback? beginDiscovery() {
    if (_globalQuiescenceDepth > 0 || _quiescedAccounts.isNotEmpty) {
      return null;
    }
    final completion = Completer<void>();
    _discoveries.add(completion);
    return () {
      if (_discoveries.remove(completion)) completion.complete();
    };
  }

  void addRestoreRequestListener(VoidCallback listener) {
    _restoreRequestListeners.add(listener);
  }

  void removeRestoreRequestListener(VoidCallback listener) {
    _restoreRequestListeners.remove(listener);
  }

  void requestRestore() {
    for (final listener in List<VoidCallback>.of(_restoreRequestListeners)) {
      listener();
    }
  }

  bool register({
    required VotingSessionKey key,
    required Object owner,
    required VotingShareTrackingStopper stopAndDrain,
  }) {
    if (isQuiesced(key.accountUuid)) return false;
    _sessions[key] = _VotingShareTrackingRegistration(
      owner: owner,
      stopAndDrain: stopAndDrain,
    );
    return true;
  }

  void unregister({required VotingSessionKey key, required Object owner}) {
    if (identical(_sessions[key]?.owner, owner)) _sessions.remove(key);
  }

  bool registerSyncRecovery({
    required VotingSessionKey key,
    required Object owner,
    required VotingSyncRecoveryStopper stopAndDrain,
  }) {
    if (isQuiesced(key.accountUuid)) return false;
    _recoveries[key] = _VotingSyncRecoveryRegistration(
      owner: owner,
      stopAndDrain: stopAndDrain,
    );
    return true;
  }

  void unregisterSyncRecovery({
    required VotingSessionKey key,
    required Object owner,
  }) {
    if (identical(_recoveries[key]?.owner, owner)) _recoveries.remove(key);
  }

  bool isQuiesced(String accountUuid) {
    return _globalQuiescenceDepth > 0 ||
        _quiescedAccounts.contains(accountUuid);
  }

  /// Blocks matching discovery until paired with [resume].
  ///
  /// Global calls are reference counted so overlapping owners cannot release
  /// each other's destructive boundary.
  Future<void> quiesceAndDrain({String? accountUuid}) async {
    if (accountUuid == null) {
      _globalQuiescenceDepth++;
    } else {
      _quiescedAccounts.add(accountUuid);
    }
    final sessions = [
      for (final entry in _sessions.entries)
        if (accountUuid == null || entry.key.accountUuid == accountUuid) entry,
    ];
    final recoveries = [
      for (final entry in _recoveries.entries)
        if (accountUuid == null || entry.key.accountUuid == accountUuid) entry,
    ];
    final discoveries = [
      for (final completion in _discoveries) completion.future,
    ];
    try {
      await Future.wait([
        ...discoveries,
        ...sessions.map((entry) => entry.value.stopAndDrain()),
        ...recoveries.map((entry) => entry.value.stopAndDrain()),
      ]);
    } finally {
      for (final entry in sessions) {
        unregister(key: entry.key, owner: entry.value.owner);
      }
      for (final entry in recoveries) {
        unregisterSyncRecovery(key: entry.key, owner: entry.value.owner);
      }
    }
  }

  void resume({String? accountUuid}) {
    if (accountUuid == null) {
      if (_globalQuiescenceDepth > 0) _globalQuiescenceDepth--;
    } else {
      _quiescedAccounts.remove(accountUuid);
    }
  }

  @visibleForTesting
  Set<VotingSessionKey> get registeredKeys => Set.unmodifiable(_sessions.keys);

  @visibleForTesting
  Set<VotingSessionKey> get registeredSyncRecoveryKeys =>
      Set.unmodifiable(_recoveries.keys);
}

class _VotingShareTrackingRegistration {
  const _VotingShareTrackingRegistration({
    required this.owner,
    required this.stopAndDrain,
  });

  final Object owner;
  final VotingShareTrackingStopper stopAndDrain;
}

class _VotingSyncRecoveryRegistration {
  const _VotingSyncRecoveryRegistration({
    required this.owner,
    required this.stopAndDrain,
  });

  final Object owner;
  final VotingSyncRecoveryStopper stopAndDrain;
}

final votingShareTrackingRegistryProvider = Provider((ref) {
  return VotingShareTrackingRegistry();
});
