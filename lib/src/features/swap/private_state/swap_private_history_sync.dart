import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/private_state_sync/private_state_models.dart';
import '../../../core/private_state_sync/private_state_object_repository.dart';
import '../models/swap_models.dart';
import '../providers/swap_activity_replica.dart';
import 'swap_private_history_document.dart';
import 'swap_private_history_sync_metadata.dart';

const _archiveSlotPrefix = 'delta-v1:';

class FinalizedActivityArchiveSyncResult {
  FinalizedActivityArchiveSyncResult({
    required Iterable<SwapIntentRecord> records,
    required this.kind,
    required this.lastSlot,
    required this.remoteWritten,
    required this.truncated,
  }) : records = List.unmodifiable(records);

  final List<SwapIntentRecord> records;
  final SwapPrivateHistoryKind kind;
  final int lastSlot;
  final bool remoteWritten;
  final bool truncated;
}

class FinalizedActivityArchiveConflictException implements Exception {
  const FinalizedActivityArchiveConflictException(this.attempts);

  final int attempts;

  @override
  String toString() =>
      'Finalized activity archive did not converge after $attempts attempts.';
}

abstract interface class FinalizedActivityArchiveSynchronizer {
  Future<FinalizedActivityArchiveSyncResult> synchronize({
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
/// Each newly derived create-only object contains only records that are new or
/// have gained finalized evidence since the preceding local pass. Recovery
/// reads and merges every contiguous slot. A create conflict means another
/// device won that slot; its delta is applied before remaining local changes
/// are attempted at the following slot.
class FinalizedActivityArchiveSync
    implements FinalizedActivityArchiveSynchronizer {
  FinalizedActivityArchiveSync({
    required PrivateStateObjectRepository repository,
    required SwapActivityReplica replica,
    required FinalizedActivityArchiveMetadataStore metadataStore,
    this.maxCreateAttempts = 8,
  }) : _repository = repository,
       _replica = replica,
       _metadataStore = metadataStore {
    if (maxCreateAttempts < 1) {
      throw ArgumentError.value(maxCreateAttempts, 'maxCreateAttempts');
    }
  }

  final PrivateStateObjectRepository _repository;
  final SwapActivityReplica _replica;
  final FinalizedActivityArchiveMetadataStore _metadataStore;
  final int maxCreateAttempts;
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
  Future<FinalizedActivityArchiveSyncResult> synchronize({
    required PrivateStateAccount account,
    required SwapPrivateHistoryKind kind,
  }) {
    final scope = '${account.accountUuid}\u0000${kind.wireName}';
    return _serialize(scope, () async {
      debugPrint('[private-state] activity sync start kind=${kind.wireName}');
      return _synchronize(account: account, kind: kind);
    });
  }

  Future<FinalizedActivityArchiveSyncResult> _synchronize({
    required PrivateStateAccount account,
    required SwapPrivateHistoryKind kind,
  }) async {
    var metadata =
        await _metadataStore.load(
          accountUuid: account.accountUuid,
          kind: kind,
        ) ??
        const FinalizedActivityArchiveMetadata(lastSlot: 0);
    var lastSlot = metadata.lastSlot;
    var archive = _decodeArchiveState(
      metadata.archiveState,
      expectedKind: kind,
    );

    // A delta slot cannot reconstruct preceding slots. If local archive state
    // is missing or corrupt, discard only local progress and replay from one.
    if (lastSlot > 0 && archive == null) {
      lastSlot = 0;
    }

    // Discover deltas created by another installation. Contiguous,
    // create-only slots make the first absent object the end marker.
    while (true) {
      final next = await _readSlot(
        account: account,
        kind: kind,
        slot: lastSlot + 1,
      );
      if (next == null) break;
      archive = _mergeArchiveDocuments(archive, next, kind: kind);
      lastSlot++;
    }

    final hidden = metadata.hiddenRecordIds;
    if (archive != null && archive.records.isNotEmpty) {
      await _replica.reconcileRemoteRecords(
        accountUuid: account.accountUuid,
        remoteRecords: archive.records.where(
          (record) => !hidden.contains(record.id),
        ),
        mergeConflict: mergeSwapPrivateHistoryRecord,
      );
    }

    for (var attempt = 1; attempt <= maxCreateAttempts; attempt++) {
      final local = await _replica.loadRecords(
        accountUuid: account.accountUuid,
      );
      final combined = _mergeFinalizedRecords(
        archive?.records ?? const [],
        local.where((record) => !hidden.contains(record.id)),
        kind: kind,
      );
      var desired = SwapPrivateHistoryDocument.compact(
        kind: kind,
        records: combined,
      );
      if (archive?.truncated == true && !desired.truncated) {
        desired = SwapPrivateHistoryDocument(
          kind: kind,
          records: desired.records,
          truncated: true,
        );
      }
      final pending = _changedRecords(archive, desired, kind: kind);
      if (pending.isEmpty) {
        await _saveMetadata(
          account: account,
          kind: kind,
          lastSlot: lastSlot,
          hidden: hidden,
          archiveState: archive?.encode(),
        );
        return _complete(
          outcome: archive == null ? 'empty' : 'unchanged',
          archiveRecords: archive?.records.length ?? 0,
          result: FinalizedActivityArchiveSyncResult(
            records: local,
            kind: kind,
            lastSlot: lastSlot,
            remoteWritten: false,
            truncated: desired.truncated,
          ),
        );
      }

      final nextSlot = lastSlot + 1;
      final delta = SwapPrivateHistoryDocument(
        kind: kind,
        records: pending,
        truncated: desired.truncated,
      );
      final write = await _repository.create(
        account: account,
        key: _key(kind, nextSlot),
        plaintext: delta.encode(),
      );
      if (write is PrivateStateCreated) {
        archive = _mergeArchiveDocuments(archive, delta, kind: kind);
        await _saveMetadata(
          account: account,
          kind: kind,
          lastSlot: nextSlot,
          hidden: hidden,
          archiveState: archive.encode(),
        );
        return _complete(
          outcome: 'written',
          archiveRecords: archive.records.length,
          result: FinalizedActivityArchiveSyncResult(
            records: local,
            kind: kind,
            lastSlot: nextSlot,
            remoteWritten: true,
            truncated: archive.truncated,
          ),
        );
      }

      final winner = await _readSlot(
        account: account,
        kind: kind,
        slot: nextSlot,
      );
      if (winner == null) continue;
      archive = _mergeArchiveDocuments(archive, winner, kind: kind);
      lastSlot = nextSlot;
      await _replica.reconcileRemoteRecords(
        accountUuid: account.accountUuid,
        remoteRecords: winner.records.where(
          (record) => !hidden.contains(record.id),
        ),
        mergeConflict: mergeSwapPrivateHistoryRecord,
      );
    }
    throw FinalizedActivityArchiveConflictException(maxCreateAttempts);
  }

  FinalizedActivityArchiveSyncResult _complete({
    required String outcome,
    required int archiveRecords,
    required FinalizedActivityArchiveSyncResult result,
  }) {
    debugPrint(
      '[private-state] activity sync complete kind=${result.kind.wireName} '
      'outcome=$outcome slot=${result.lastSlot} '
      'records=$archiveRecords truncated=${result.truncated}',
    );
    return result;
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
    required Uint8List? archiveState,
  }) => _metadataStore.save(
    accountUuid: account.accountUuid,
    kind: kind,
    metadata: FinalizedActivityArchiveMetadata(
      lastSlot: lastSlot,
      hiddenRecordIds: hidden,
      archiveState: archiveState,
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

SwapPrivateHistoryDocument? _decodeArchiveState(
  Uint8List? state, {
  required SwapPrivateHistoryKind expectedKind,
}) {
  if (state == null) return null;
  try {
    return SwapPrivateHistoryDocument.decode(state, expectedKind: expectedKind);
  } on Object {
    return null;
  }
}

SwapPrivateHistoryDocument _mergeArchiveDocuments(
  SwapPrivateHistoryDocument? archive,
  SwapPrivateHistoryDocument delta, {
  required SwapPrivateHistoryKind kind,
}) {
  var merged = SwapPrivateHistoryDocument.compact(
    kind: kind,
    records: _mergeFinalizedRecords(
      archive?.records ?? const [],
      delta.records,
      kind: kind,
    ),
  );
  if ((archive?.truncated == true || delta.truncated) && !merged.truncated) {
    merged = SwapPrivateHistoryDocument(
      kind: kind,
      records: merged.records,
      truncated: true,
    );
  }
  return merged;
}

List<SwapIntentRecord> _changedRecords(
  SwapPrivateHistoryDocument? archive,
  SwapPrivateHistoryDocument desired, {
  required SwapPrivateHistoryKind kind,
}) {
  final archivedById = {
    for (final record in archive?.records ?? const <SwapIntentRecord>[])
      record.id: record,
  };
  final changed = <SwapIntentRecord>[];
  for (final record in desired.records) {
    final archived = archivedById[record.id];
    if (archived == null ||
        !_recordsHaveSameWireState(archived, record, kind: kind)) {
      changed.add(record);
    }
  }
  return changed;
}

bool _recordsHaveSameWireState(
  SwapIntentRecord left,
  SwapIntentRecord right, {
  required SwapPrivateHistoryKind kind,
}) => _bytesEqual(
  SwapPrivateHistoryDocument(kind: kind, records: [left]).encode(),
  SwapPrivateHistoryDocument(kind: kind, records: [right]).encode(),
);

List<SwapIntentRecord> _mergeFinalizedRecords(
  Iterable<SwapIntentRecord> remote,
  Iterable<SwapIntentRecord> local, {
  required SwapPrivateHistoryKind kind,
}) {
  final merged = <String, SwapIntentRecord>{};
  for (final record in [...remote, ...local]) {
    if (record.payMode != kind.payMode || !_isFinalized(record)) continue;
    final existing = merged[record.id];
    merged[record.id] = existing == null
        ? record
        : mergeSwapPrivateHistoryRecord(existing, record);
  }
  return merged.values.toList(growable: false);
}

bool _isFinalized(SwapIntentRecord record) =>
    record.status == SwapIntentStatus.complete ||
    record.status == SwapIntentStatus.refunded;

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
