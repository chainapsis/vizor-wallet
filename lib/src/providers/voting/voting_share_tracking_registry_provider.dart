import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_flow_models.dart';

typedef VotingShareTrackingDrain = Future<void> Function();

class VotingShareTrackingRegistry {
  final Map<VotingSessionKey, _VotingShareTrackingRegistration> _registrations =
      {};
  final Map<Completer<void>, String?> _backgroundWork = {};
  final Set<VoidCallback> _restoreRequestListeners = {};
  final Map<String, int> _accountQuiescenceDepths = {};
  int _globalQuiescenceDepth = 0;

  /// Starts drainable voting work before its first asynchronous operation.
  ///
  /// A null account scope may inspect every account. Account delete/reset block
  /// matching work and await the returned lease before mutating wallet state.
  VoidCallback? beginBackgroundWork({String? accountUuid}) {
    final blocked = accountUuid == null
        ? isAnyAccountQuiesced
        : isQuiesced(accountUuid);
    if (blocked) return null;

    final completion = Completer<void>();
    _backgroundWork[completion] = accountUuid;
    return () {
      if (!_backgroundWork.containsKey(completion)) return;
      _backgroundWork.remove(completion);
      completion.complete();
    };
  }

  /// Starts discovery before its first asynchronous operation.
  ///
  /// Destructive wallet operations block new discovery and await the returned
  /// lease, so sidecar reads cannot outlive the state they are inspecting.
  VoidCallback? beginDiscovery() => beginBackgroundWork();

  /// Counts destructive wipes of the wallet's durable data.
  ///
  /// Quiescence only holds work off while the wipe runs; once it resumes,
  /// background work that pinned state from before the wipe has no other way
  /// to tell that the wallet it was reading is gone. The account list is not
  /// that signal: a wipe that deletes the database and then fails a later
  /// cleanup step never publishes the empty account state, so a stale reader
  /// would go on to re-create what the reset just removed.
  int get walletDataGeneration => _walletDataGeneration;
  int _walletDataGeneration = 0;

  /// Called by wallet reset once the durable data is gone — including the
  /// failed-cleanup path, where the deletion has still committed.
  void notifyWalletDataDeleted() => _walletDataGeneration++;

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
    required VotingShareTrackingDrain stopAndDrain,
  }) {
    if (isQuiesced(key.accountUuid)) return false;
    _registrations[key] = _VotingShareTrackingRegistration(
      owner: owner,
      stopAndDrain: stopAndDrain,
    );
    return true;
  }

  void unregister({required VotingSessionKey key, required Object owner}) {
    if (identical(_registrations[key]?.owner, owner)) {
      _registrations.remove(key);
    }
  }

  bool isQuiesced(String accountUuid) {
    return _globalQuiescenceDepth > 0 ||
        (_accountQuiescenceDepths[accountUuid] ?? 0) > 0;
  }

  /// Whether any account is being mutated, regardless of which one.
  ///
  /// The companion of an unscoped [beginBackgroundWork] lease: work that reads
  /// wallet-wide state — the shared scan frontier, the wallet birthday — is
  /// invalidated by a mutation of *any* account, not only its own, so it has
  /// to test the same boundary its lease is taken against.
  bool get isAnyAccountQuiesced =>
      _globalQuiescenceDepth > 0 || _accountQuiescenceDepths.isNotEmpty;

  /// Blocks matching background work until paired with [resume].
  ///
  /// Global calls are reference counted so overlapping owners cannot release
  /// each other's destructive boundary.
  Future<void> quiesceAndDrain({String? accountUuid}) async {
    if (accountUuid == null) {
      _globalQuiescenceDepth++;
    } else {
      _accountQuiescenceDepths.update(
        accountUuid,
        (depth) => depth + 1,
        ifAbsent: () => 1,
      );
    }
    final sessions = [
      for (final entry in _registrations.entries)
        if (accountUuid == null || entry.key.accountUuid == accountUuid) entry,
    ];
    final backgroundWork = [
      for (final entry in _backgroundWork.entries)
        if (accountUuid == null ||
            entry.value == null ||
            entry.value == accountUuid)
          entry.key.future,
    ];
    try {
      await Future.wait([
        ...backgroundWork,
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
      if (_globalQuiescenceDepth > 0) _globalQuiescenceDepth--;
    } else {
      final depth = _accountQuiescenceDepths[accountUuid] ?? 0;
      if (depth <= 1) {
        _accountQuiescenceDepths.remove(accountUuid);
      } else {
        _accountQuiescenceDepths[accountUuid] = depth - 1;
      }
    }
  }

  @visibleForTesting
  Set<VotingSessionKey> get registeredKeys =>
      Set.unmodifiable(_registrations.keys);
}

class _VotingShareTrackingRegistration {
  const _VotingShareTrackingRegistration({
    required this.owner,
    required this.stopAndDrain,
  });

  final Object owner;
  final VotingShareTrackingDrain stopAndDrain;
}

final votingShareTrackingRegistryProvider = Provider((ref) {
  return VotingShareTrackingRegistry();
});
