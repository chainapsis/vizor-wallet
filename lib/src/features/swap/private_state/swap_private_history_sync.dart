import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/private_state_sync/private_state_models.dart';
import '../../../core/private_state_sync/private_state_object_repository.dart';
import '../models/swap_models.dart';
import '../providers/swap_activity_replica.dart';
import 'swap_private_history_document.dart';
import 'swap_private_history_sync_metadata.dart';

const _archiveSlotPrefix = 'delta-v1:';

class FinalizedActivityArchiveConflictException implements Exception {
  const FinalizedActivityArchiveConflictException(this.attempts);

  final int attempts;

  @override
  String toString() =>
      'Finalized activity archive did not converge after $attempts attempts.';
}

abstract interface class FinalizedActivityArchiveSynchronizer {
  Future<void> synchronize({
    required PrivateStateAccount account,
    required SwapPrivateHistoryKind kind,
  });

  Future<void> recordLocalDeletions({
    required String accountUuid,
    required Iterable<SwapIntentRecord> records,
  });
}

/// Maintains an immutable delta archive of complete and refunded activities.
///
/// Each Activity ID is published at most once per namespace. Recovery consumes
/// every contiguous slot and adds remote-only IDs to the local replica. A
/// create conflict simply restarts discovery because another device advanced
/// the same immutable archive.
class FinalizedActivityArchiveSync
    implements FinalizedActivityArchiveSynchronizer {
  FinalizedActivityArchiveSync({
    required PrivateStateObjectRepository repository,
    required SwapActivityReplica replica,
    required FinalizedActivityArchiveMetadataStore metadataStore,
    this.maxConflictAttempts = 8,
  }) : _repository = repository,
       _replica = replica,
       _metadataStore = metadataStore {
    if (maxConflictAttempts < 1) {
      throw ArgumentError.value(maxConflictAttempts, 'maxConflictAttempts');
    }
  }

  final PrivateStateObjectRepository _repository;
  final SwapActivityReplica _replica;
  final FinalizedActivityArchiveMetadataStore _metadataStore;
  final int maxConflictAttempts;
  final Map<String, Future<void>> _syncTails = {};

  @override
  Future<void> recordLocalDeletions({
    required String accountUuid,
    required Iterable<SwapIntentRecord> records,
  }) async {
    final materialized = records.toList(growable: false);
    for (final kind in SwapPrivateHistoryKind.values) {
      await _metadataStore.hideRecords(
        accountUuid: accountUuid,
        kind: kind,
        recordIds: materialized
            .where((record) => record.payMode == kind.payMode)
            .map((record) => record.id),
      );
    }
  }

  @override
  Future<void> synchronize({
    required PrivateStateAccount account,
    required SwapPrivateHistoryKind kind,
  }) {
    final scope = '${account.accountUuid}\u0000${kind.wireName}';
    return _serialize(scope, () async {
      debugPrint('[private-state] activity sync start kind=${kind.wireName}');
      return _synchronize(account: account, kind: kind);
    });
  }

  Future<void> _synchronize({
    required PrivateStateAccount account,
    required SwapPrivateHistoryKind kind,
  }) async {
    final metadata =
        await _metadataStore.load(
          accountUuid: account.accountUuid,
          kind: kind,
        ) ??
        const FinalizedActivityArchiveMetadata(lastSlot: 0);
    var lastSlot = metadata.lastSlot;
    final archivedIds = {...metadata.archivedRecordIds};
    if (lastSlot > 0 && archivedIds.isEmpty) {
      lastSlot = 0;
    }
    final hidden = metadata.hiddenRecordIds;
    var conflictAttempts = 0;

    while (true) {
      // Consume the complete contiguous archive before deciding whether this
      // client has anything to publish. This is also the only conflict path.
      final discovered = <SwapIntentRecord>[];
      while (true) {
        final next = await _readSlot(
          account: account,
          kind: kind,
          slot: lastSlot + 1,
        );
        if (next == null) break;
        lastSlot++;
        for (final record in next.records) {
          if (archivedIds.add(record.id)) {
            discovered.add(record);
          }
        }
      }
      if (discovered.isNotEmpty) {
        await _replica.reconcileRemoteRecords(
          accountUuid: account.accountUuid,
          remoteRecords: discovered.where(
            (record) => !hidden.contains(record.id),
          ),
        );
      }

      final local = await _replica.loadRecords(
        accountUuid: account.accountUuid,
      );
      final pending = _missingFinalizedRecords(
        local,
        archivedIds: archivedIds,
        hiddenIds: hidden,
        kind: kind,
      );
      if (pending.isEmpty) {
        await _saveMetadata(
          account: account,
          kind: kind,
          lastSlot: lastSlot,
          hidden: hidden,
          archivedIds: archivedIds,
        );
        return _complete(
          kind: kind,
          outcome: archivedIds.isEmpty ? 'empty' : 'unchanged',
          slot: lastSlot,
          archiveRecords: archivedIds.length,
        );
      }

      final nextSlot = lastSlot + 1;
      final delta = SwapPrivateHistoryDocument.compact(
        kind: kind,
        records: pending,
      );
      if (delta.records.isEmpty) {
        throw const PrivateStateProtocolException(
          'Finalized activity delta cannot fit any pending Activity.',
        );
      }
      final write = await _repository.create(
        account: account,
        key: _key(kind, nextSlot),
        plaintext: delta.encode(),
      );
      if (write is PrivateStateCreated) {
        lastSlot = nextSlot;
        archivedIds.addAll(delta.records.map((record) => record.id));
        await _saveMetadata(
          account: account,
          kind: kind,
          lastSlot: nextSlot,
          hidden: hidden,
          archivedIds: archivedIds,
        );
        return _complete(
          kind: kind,
          outcome: 'written',
          slot: nextSlot,
          archiveRecords: archivedIds.length,
        );
      }

      conflictAttempts++;
      if (conflictAttempts >= maxConflictAttempts) {
        throw FinalizedActivityArchiveConflictException(maxConflictAttempts);
      }
      // The next loop reads the winner and every later contiguous slot before
      // deriving missing IDs from current local state again.
    }
  }

  void _complete({
    required SwapPrivateHistoryKind kind,
    required String outcome,
    required int slot,
    required int archiveRecords,
  }) {
    debugPrint(
      '[private-state] activity sync complete kind=${kind.wireName} '
      'outcome=$outcome slot=$slot records=$archiveRecords',
    );
  }

  Future<SwapPrivateHistoryDocument?> _readSlot({
    required PrivateStateAccount account,
    required SwapPrivateHistoryKind kind,
    required int slot,
  }) async {
    final read = await _repository.read(
      account: account,
      key: _key(kind, slot),
    );
    return switch (read) {
      PrivateStateReadAbsent() => null,
      PrivateStateReadFound(:final plaintext) =>
        SwapPrivateHistoryDocument.decode(plaintext, expectedKind: kind),
    };
  }

  Future<void> _saveMetadata({
    required PrivateStateAccount account,
    required SwapPrivateHistoryKind kind,
    required int lastSlot,
    required Set<String> hidden,
    required Set<String> archivedIds,
  }) => _metadataStore.save(
    accountUuid: account.accountUuid,
    kind: kind,
    metadata: FinalizedActivityArchiveMetadata(
      lastSlot: lastSlot,
      hiddenRecordIds: hidden,
      archivedRecordIds: archivedIds,
    ),
  );

  PrivateStateObjectKey _key(SwapPrivateHistoryKind kind, int slot) {
    if (slot < 1) {
      throw const PrivateStateProtocolException(
        'Finalized activity archive slot must be positive.',
      );
    }
    return PrivateStateObjectKey(
      namespace: kind == SwapPrivateHistoryKind.swap
          ? PrivateStateNamespace.swapHistory
          : PrivateStateNamespace.payHistory,
      itemKey: '$_archiveSlotPrefix$slot',
    );
  }

  Future<T> _serialize<T>(String scope, Future<T> Function() action) async {
    final previous = _syncTails[scope] ?? Future.value();
    final turn = Completer<void>();
    _syncTails[scope] = turn.future;
    try {
      try {
        await previous;
      } on Object {
        // A failed pass must not permanently poison this scope's queue.
      }
      return await action();
    } finally {
      turn.complete();
      if (identical(_syncTails[scope], turn.future)) {
        _syncTails.remove(scope);
      }
    }
  }
}

List<SwapIntentRecord> _missingFinalizedRecords(
  Iterable<SwapIntentRecord> local, {
  required Set<String> archivedIds,
  required Set<String> hiddenIds,
  required SwapPrivateHistoryKind kind,
}) {
  final missing = <String, SwapIntentRecord>{};
  for (final record in local) {
    if (record.payMode != kind.payMode ||
        !_isFinalized(record) ||
        hiddenIds.contains(record.id) ||
        archivedIds.contains(record.id)) {
      continue;
    }
    missing.putIfAbsent(record.id, () => record);
  }
  return missing.values.toList(growable: false);
}

bool _isFinalized(SwapIntentRecord record) =>
    record.status == SwapIntentStatus.complete ||
    record.status == SwapIntentStatus.refunded;
