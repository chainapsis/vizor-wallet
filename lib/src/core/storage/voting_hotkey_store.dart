/// Owns hotkey creation for one secure-storage namespace in this isolate.
/// Keep one instance with the underlying storage, independent of UI lifetimes.
/// Only pending operations are retained; storage is reread after completion.
class VotingHotkeyStore {
  VotingHotkeyStore({
    required Future<List<int>?> Function({
      required String accountUuid,
      required String roundId,
    })
    readHotkey,
    required Future<void> Function({
      required String accountUuid,
      required String roundId,
      required List<int> hotkey,
    })
    writeHotkey,
    required Future<void> Function({
      required String accountUuid,
      required String roundId,
    })
    deleteHotkey,
  }) : _readHotkey = readHotkey,
       _writeHotkey = writeHotkey,
       _deleteHotkey = deleteHotkey;

  final Future<List<int>?> Function({
    required String accountUuid,
    required String roundId,
  })
  _readHotkey;
  final Future<void> Function({
    required String accountUuid,
    required String roundId,
    required List<int> hotkey,
  })
  _writeHotkey;
  final Future<void> Function({
    required String accountUuid,
    required String roundId,
  })
  _deleteHotkey;
  final _pending = <(String, String), Future<List<int>>>{};

  /// Returns the persisted key without generating one or waiting for creation.
  Future<List<int>?> readHotkey({
    required String accountUuid,
    required String roundId,
  }) => _readHotkey(accountUuid: accountUuid, roundId: roundId);

  /// Returns a stored key or generates and persists one before returning it.
  /// Concurrent calls for one account and round share the first operation,
  /// including its error. A later call rereads storage and may retry a failure.
  /// Set [allowCreation] to false when durable voting state already binds a key:
  /// an existing operation may be joined, but a missing key is never replaced.
  Future<List<int>> getOrCreate({
    required String accountUuid,
    required String roundId,
    required Future<List<int>> Function() generate,
    required bool allowCreation,
  }) {
    final identity = (accountUuid, roundId);
    final pending = _pending[identity];
    if (pending != null) return pending;

    late final Future<List<int>> operation;
    operation =
        _readOrCreate(
          accountUuid: accountUuid,
          roundId: roundId,
          generate: generate,
          allowCreation: allowCreation,
        ).whenComplete(() {
          if (identical(_pending[identity], operation)) {
            _pending.remove(identity);
          }
        });
    _pending[identity] = operation;
    return operation;
  }

  Future<List<int>> _readOrCreate({
    required String accountUuid,
    required String roundId,
    required Future<List<int>> Function() generate,
    required bool allowCreation,
  }) async {
    final existing = await readHotkey(
      accountUuid: accountUuid,
      roundId: roundId,
    );
    if (existing != null && existing.isNotEmpty) return existing;
    if (!allowCreation) {
      throw const VotingHotkeyUnavailable('missing stored voting hotkey');
    }

    final hotkey = await generate();
    final storedAfterGeneration = await readHotkey(
      accountUuid: accountUuid,
      roundId: roundId,
    );
    if (storedAfterGeneration != null && storedAfterGeneration.isNotEmpty) {
      return storedAfterGeneration;
    }
    await _writeHotkey(
      accountUuid: accountUuid,
      roundId: roundId,
      hotkey: hotkey,
    );
    return hotkey;
  }

  /// Removes a persisted key. Callers must drain voting work before deletion.
  Future<void> deleteHotkey({
    required String accountUuid,
    required String roundId,
  }) => _deleteHotkey(accountUuid: accountUuid, roundId: roundId);
}

/// A required voting secret is unavailable; creating a replacement is unsafe.
class VotingHotkeyUnavailable implements Exception {
  const VotingHotkeyUnavailable(this.message);

  final String message;

  @override
  String toString() => 'VotingHotkeyUnavailable: $message';
}
