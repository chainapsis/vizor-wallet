import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_flow_models.dart';

typedef VotingShareTrackingStopper = Future<void> Function();

class VotingShareTrackingRegistry {
  final Map<VotingSessionKey, _VotingShareTrackingRegistration> _sessions = {};
  final Set<String> _quiescedAccounts = {};
  bool _allQuiesced = false;

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
    await Future.wait(sessions.map((entry) => entry.value.stopAndDrain()));
    for (final entry in sessions) {
      unregister(key: entry.key, owner: entry.value.owner);
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
