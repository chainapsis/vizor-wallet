import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_flow_models.dart';
import 'voting_service_providers.dart';

/// Shared by review and submission sessions for the lifetime of the app scope.
/// Closing a screen must not allow a second writer while storage is pending.
final votingHotkeyCoordinatorProvider = Provider<VotingHotkeyCoordinator>((
  ref,
) {
  return VotingHotkeyCoordinator(
    store: ref.watch(votingHotkeyStoreProvider),
    generateHotkey: ref.watch(votingRustApiProvider).generateVotingHotkey,
  );
});

/// Creates at most one hotkey per account and round at a time, retaining only
/// pending operations. Secure storage remains the authority after completion.
class VotingHotkeyCoordinator {
  VotingHotkeyCoordinator({
    required VotingHotkeyStore store,
    required Future<List<int>> Function({required String network})
    generateHotkey,
  }) : _store = store,
       _generateHotkey = generateHotkey;

  final VotingHotkeyStore _store;
  final Future<List<int>> Function({required String network}) _generateHotkey;
  final Map<VotingSessionKey, Future<List<int>>> _pending = {};

  /// Returns the stored key or creates and persists one before returning it.
  /// A bound round without a stored key fails instead of replacing its key.
  /// Concurrent callers for the same identity share completion, including any
  /// error; a subsequent call rereads storage and may retry a failed operation.
  Future<List<int>> ensureHotkey({
    required VotingSessionKey key,
    required String network,
    required bool alreadyBound,
  }) {
    final pending = _pending[key];
    if (pending != null) return pending;

    late final Future<List<int>> operation;
    operation = _readOrCreate(key, network, alreadyBound).whenComplete(() {
      if (identical(_pending[key], operation)) _pending.remove(key);
    });
    _pending[key] = operation;
    return operation;
  }

  Future<List<int>> _readOrCreate(
    VotingSessionKey key,
    String network,
    bool alreadyBound,
  ) async {
    final existing = await _store.readHotkey(
      accountUuid: key.accountUuid,
      roundId: key.roundId,
    );
    if (existing != null && existing.isNotEmpty) return existing;
    if (alreadyBound) {
      throw const VotingHotkeyUnavailable('missing stored voting hotkey');
    }

    final hotkey = await _generateHotkey(network: network);
    final storedAfterGeneration = await _store.readHotkey(
      accountUuid: key.accountUuid,
      roundId: key.roundId,
    );
    if (storedAfterGeneration != null && storedAfterGeneration.isNotEmpty) {
      return storedAfterGeneration;
    }
    await _store.writeHotkey(
      accountUuid: key.accountUuid,
      roundId: key.roundId,
      hotkey: hotkey,
    );
    return hotkey;
  }
}
