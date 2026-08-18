import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_flow_models.dart';

typedef VotingShareTrackingStopper = Future<void> Function();

class VotingShareTrackingRegistry {
  final Map<VotingSessionKey, _VotingShareTrackingRegistration> _sessions = {};
  final Set<Completer<void>> _discoveries = {};
  final Set<VoidCallback> _restoreRequestListeners = {};
  final Set<String> _quiescedAccounts = {};
  bool _allQuiesced = false;

  /// Starts discovery before its first asynchronous operation.
  ///
  /// Destructive wallet operations block new discovery and await the returned
  /// lease, so sidecar reads cannot outlive the state they are inspecting.
  VoidCallback? beginDiscovery() {
    if (_allQuiesced || _quiescedAccounts.isNotEmpty) return null;
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

  bool isQuiesced(String accountUuid) {
    return _allQuiesced || _quiescedAccounts.contains(accountUuid);
  }

  Future<void> quiesceAndDrain({String? accountUuid}) async {
    if (accountUuid == null) {
      _allQuiesced = true;
    } else {
      _quiescedAccounts.add(accountUuid);
    }
    final sessions = [
      for (final entry in _sessions.entries)
        if (accountUuid == null || entry.key.accountUuid == accountUuid) entry,
    ];
    final discoveries = [
      for (final completion in _discoveries) completion.future,
    ];
    try {
      await Future.wait([
        ...discoveries,
        ...sessions.map((entry) => entry.value.stopAndDrain()),
      ]);
    } finally {
      for (final entry in sessions) {
        unregister(key: entry.key, owner: entry.value.owner);
      }
    }
  }

  void resume({String? accountUuid}) {
    if (accountUuid == null) {
      _allQuiesced = false;
    } else {
      _quiescedAccounts.remove(accountUuid);
    }
  }

  @visibleForTesting
  Set<VotingSessionKey> get registeredKeys => Set.unmodifiable(_sessions.keys);
}

class _VotingShareTrackingRegistration {
  const _VotingShareTrackingRegistration({
    required this.owner,
    required this.stopAndDrain,
  });

  final Object owner;
  final VotingShareTrackingStopper stopAndDrain;
}

final votingShareTrackingRegistryProvider = Provider((ref) {
  return VotingShareTrackingRegistry();
});
