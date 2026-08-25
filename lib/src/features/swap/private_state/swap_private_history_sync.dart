import 'dart:async';
import 'dart:typed_data';

import '../../../core/private_state_sync/private_state_models.dart';
import '../../../core/private_state_sync/private_state_object_repository.dart';
import '../models/swap_models.dart';
import '../providers/swap_activity_replica.dart';
import 'swap_private_history_document.dart';
import 'swap_private_history_sync_metadata.dart';

const _archiveSlotPrefix = 'archive-v1:';

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

/// Maintains a cumulative archive of only complete and refunded activities.
///
/// Every generation is written to a newly derived create-only object. The
/// server therefore never sees a stable activity object identifier. A create
/// conflict means another device won that slot; its snapshot is read, merged,
/// and the combined snapshot is attempted at the following slot.
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
    return _serialize(scope, () => _synchronize(account: account, kind: kind));
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
    SwapPrivateHistoryDocument? remote;

    // Reload the latest known snapshot so a local-only deletion never removes
    // that record from a later cumulative remote generation.
    if (lastSlot > 0) {
      final known = await _readSlot(
        account: account,
        kind: kind,
        slot: lastSlot,
      );
      if (known == null) {
        lastSlot = 0;
      } else {
        remote = known;
      }
    }

    // Discover generations created by another installation. Contiguous,
    // create-only slots make the first absent object the end marker.
    while (true) {
      final next = await _readSlot(
        account: account,
        kind: kind,
        slot: lastSlot + 1,
      );
      if (next == null) break;
      remote = next;
      lastSlot++;
    }

    final hidden = metadata.hiddenRecordIds;
    if (remote != null && remote.records.isNotEmpty) {
      await _replica.reconcileRemoteRecords(
        accountUuid: account.accountUuid,
        remoteRecords: remote.records.where(
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
        remote?.records ?? const [],
        local,
        kind: kind,
      );
      var document = SwapPrivateHistoryDocument.compact(
        kind: kind,
        records: combined,
      );
      if (remote?.truncated == true && !document.truncated) {
        document = SwapPrivateHistoryDocument(
          kind: kind,
          records: document.records,
          truncated: true,
        );
      }
      final plaintext = document.encode();
      if (document.records.isEmpty && remote == null) {
        await _saveMetadata(
          account: account,
          kind: kind,
          lastSlot: lastSlot,
          hidden: hidden,
        );
        return FinalizedActivityArchiveSyncResult(
          records: local,
          kind: kind,
          lastSlot: lastSlot,
          remoteWritten: false,
          truncated: false,
        );
      }
      if (remote != null && _bytesEqual(remote.encode(), plaintext)) {
        await _saveMetadata(
          account: account,
          kind: kind,
          lastSlot: lastSlot,
          hidden: hidden,
        );
        return FinalizedActivityArchiveSyncResult(
          records: local,
          kind: kind,
          lastSlot: lastSlot,
          remoteWritten: false,
          truncated: document.truncated,
        );
      }

      final nextSlot = lastSlot + 1;
      final write = await _repository.create(
        account: account,
        key: _key(kind, nextSlot),
        plaintext: plaintext,
      );
      if (write is PrivateStateWriteStored) {
        await _saveMetadata(
          account: account,
          kind: kind,
          lastSlot: nextSlot,
          hidden: hidden,
        );
        return FinalizedActivityArchiveSyncResult(
          records: local,
          kind: kind,
          lastSlot: nextSlot,
          remoteWritten: true,
          truncated: document.truncated,
        );
      }

      final winner = await _readSlot(
        account: account,
        kind: kind,
        slot: nextSlot,
      );
      if (winner == null) continue;
      remote = winner;
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
  }) => _metadataStore.save(
    accountUuid: account.accountUuid,
    kind: kind,
    metadata: FinalizedActivityArchiveMetadata(
      lastSlot: lastSlot,
      hiddenRecordIds: hidden,
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
