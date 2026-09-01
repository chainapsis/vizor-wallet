import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/private_state_sync/private_state_models.dart';
import '../../../core/private_state_sync/private_state_object_repository.dart';
import '../models/swap_models.dart';
import '../providers/swap_activity_replica.dart';
import 'swap_private_history_document.dart';
import 'swap_private_history_sync_metadata.dart';

const _archiveSlotPrefix = 'delta-v1:';

abstract interface class FinalizedActivityArchiveSynchronizer {
  Future<void> synchronize({
    required PrivateStateAccount account,
    required SwapPrivateHistoryKind kind,
  });

  Future<void> publishPending({
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
/// every contiguous slot and adds remote-only IDs to the local replica. Local
/// publication tries the next slot without a preceding read; a create conflict
/// reads only the winning slot before advancing.
class FinalizedActivityArchiveSync
    implements FinalizedActivityArchiveSynchronizer {
  FinalizedActivityArchiveSync({
    required PrivateStateObjectRepository repository,
    required SwapActivityReplica replica,
    required FinalizedActivityArchiveMetadataStore metadataStore,
  }) : _repository = repository,
       _replica = replica,
       _metadataStore = metadataStore;

  final PrivateStateObjectRepository _repository;
  final SwapActivityReplica _replica;
  final FinalizedActivityArchiveMetadataStore _metadataStore;
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
      return _run(account: account, kind: kind, discoverRemote: true);
    });
  }

  @override
  Future<void> publishPending({
    required PrivateStateAccount account,
    required SwapPrivateHistoryKind kind,
  }) {
    final scope = '${account.accountUuid}\u0000${kind.wireName}';
    return _serialize(scope, () async {
      debugPrint(
        '[private-state] activity publish start kind=${kind.wireName}',
      );
      return _run(account: account, kind: kind, discoverRemote: false);
    });
  }

  Future<void> _run({
    required PrivateStateAccount account,
    required SwapPrivateHistoryKind kind,
    required bool discoverRemote,
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
    var needsDiscovery = discoverRemote;
    var wroteAny = false;

    Future<void> reconcileDiscovered(Iterable<SwapIntentRecord> records) async {
      final discovered = <SwapIntentRecord>[];
      for (final record in records) {
        if (archivedIds.add(record.id)) {
          discovered.add(record);
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
    }

    while (true) {
      if (needsDiscovery) {
        // A recovery pass consumes the complete contiguous archive once before
        // deciding whether this client also has anything to publish.
        final discovered = <SwapIntentRecord>[];
        while (true) {
          final next = await _readSlot(
            account: account,
            kind: kind,
            slot: lastSlot + 1,
          );
          if (next == null) break;
          lastSlot++;
          discovered.addAll(next.records);
        }
        await reconcileDiscovered(discovered);
        needsDiscovery = false;
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
          outcome: wroteAny
              ? 'written'
              : archivedIds.isEmpty
              ? 'empty'
              : 'unchanged',
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
        wroteAny = true;
        lastSlot = nextSlot;
        archivedIds.addAll(delta.records.map((record) => record.id));
        await _saveMetadata(
          account: account,
          kind: kind,
          lastSlot: nextSlot,
          hidden: hidden,
          archivedIds: archivedIds,
        );
        continue;
      }

      final winner = await _readSlot(
        account: account,
        kind: kind,
        slot: nextSlot,
      );
      if (winner == null) {
        throw const PrivateStateProtocolException(
          'Conflicting finalized activity slot is absent.',
        );
      }
      lastSlot = nextSlot;
      await reconcileDiscovered(winner.records);
      await _saveMetadata(
        account: account,
        kind: kind,
        lastSlot: lastSlot,
        hidden: hidden,
        archivedIds: archivedIds,
      );
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
