import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../core/private_state_sync/private_state_models.dart';
import '../../../core/private_state_sync/private_state_object_repository.dart';
import '../models/swap_models.dart';
import '../providers/swap_activity_replica.dart';
import 'swap_private_history_document.dart';
import 'swap_private_history_sync_metadata.dart';

const _privateHistoryItemKey = 'history-v1';

class SwapPrivateHistorySyncResult {
  SwapPrivateHistorySyncResult({
    required Iterable<SwapIntentRecord> records,
    required this.kind,
    required this.remoteVersion,
    required this.remoteWritten,
    required this.truncated,
  }) : records = List.unmodifiable(records);

  final List<SwapIntentRecord> records;
  final SwapPrivateHistoryKind kind;
  final PrivateStateVersion? remoteVersion;
  final bool remoteWritten;
  final bool truncated;
}

class SwapPrivateHistoryConflictException implements Exception {
  const SwapPrivateHistoryConflictException(this.attempts);

  final int attempts;

  @override
  String toString() =>
      'Swap private history CAS did not converge after $attempts attempts.';
}

/// Reconciles the legacy local activity store with one encrypted remote object
/// per account and feature namespace. Correctness never depends on metadata:
/// every pass performs an authenticated remote read before deciding to write.
abstract interface class SwapPrivateHistorySynchronizer {
  Future<SwapPrivateHistorySyncResult> synchronize({
    required PrivateStateAccount account,
    required SwapPrivateHistoryKind kind,
  });

  Future<void> recordLocalDeletions({
    required String accountUuid,
    required Iterable<SwapIntentRecord> records,
  });
}

class SwapPrivateHistorySync implements SwapPrivateHistorySynchronizer {
  SwapPrivateHistorySync({
    required PrivateStateObjectRepository repository,
    required SwapActivityReplica replica,
    required SwapPrivateHistorySyncMetadataStore metadataStore,
    this.maxCasAttempts = 4,
    DateTime Function()? now,
  }) : _repository = repository,
       _replica = replica,
       _metadataStore = metadataStore,
       _now = now ?? DateTime.now {
    if (maxCasAttempts < 1) {
      throw ArgumentError.value(maxCasAttempts, 'maxCasAttempts');
    }
  }

  final PrivateStateObjectRepository _repository;
  final SwapActivityReplica _replica;
  final SwapPrivateHistorySyncMetadataStore _metadataStore;
  final int maxCasAttempts;
  final DateTime Function() _now;
  final Map<String, Future<void>> _syncTails = {};

  @override
  Future<void> recordLocalDeletions({
    required String accountUuid,
    required Iterable<SwapIntentRecord> records,
  }) async {
    final deletedAt = _now().toUtc();
    for (final kind in SwapPrivateHistoryKind.values) {
      final tombstones = {
        for (final record in records)
          if (record.payMode == kind.payMode) record.id: deletedAt,
      };
      await _metadataStore.addTombstones(
        accountUuid: accountUuid,
        kind: kind,
        tombstones: tombstones,
      );
    }
  }

  @override
  Future<SwapPrivateHistorySyncResult> synchronize({
    required PrivateStateAccount account,
    required SwapPrivateHistoryKind kind,
  }) {
    final scope = '${account.accountUuid}\u0000${kind.wireName}';
    return _serialize(scope, () => _synchronize(account: account, kind: kind));
  }

  Future<SwapPrivateHistorySyncResult> _synchronize({
    required PrivateStateAccount account,
    required SwapPrivateHistoryKind kind,
  }) async {
    var tombstones =
        (await _metadataStore.load(
          accountUuid: account.accountUuid,
          kind: kind,
        ))?.tombstones ??
        const <String, DateTime>{};
    for (var attempt = 1; attempt <= maxCasAttempts; attempt++) {
      final read = await _repository.read(account: account, key: _key(kind));
      final remoteDocument = switch (read) {
        PrivateStateReadAbsent() => null,
        PrivateStateReadFound(:final plaintext) =>
          SwapPrivateHistoryDocument.decode(plaintext, expectedKind: kind),
      };

      tombstones = _mergeHistoryTombstones(
        tombstones,
        remoteDocument?.tombstones ?? const {},
      );

      if (tombstones.isNotEmpty) {
        await _replica.applyRemoteTombstones(
          accountUuid: account.accountUuid,
          intentIds: tombstones.keys.toSet(),
          payMode: kind.payMode,
        );
      }

      if (remoteDocument != null && remoteDocument.records.isNotEmpty) {
        await _replica.reconcileRemoteRecords(
          accountUuid: account.accountUuid,
          remoteRecords: remoteDocument.records.where(
            (record) => !tombstones.containsKey(record.id),
          ),
          mergeConflict: mergeSwapPrivateHistoryRecord,
        );
      }

      // Reload after reconciliation so queued local mutations that completed
      // during the network read are included in this upload candidate.
      final allLocal = await _replica.loadRecords(
        accountUuid: account.accountUuid,
      );
      var document = SwapPrivateHistoryDocument.compact(
        kind: kind,
        records: allLocal.where((record) => !tombstones.containsKey(record.id)),
        tombstones: tombstones,
      );
      if (remoteDocument?.truncated == true && !document.truncated) {
        document = SwapPrivateHistoryDocument(
          kind: kind,
          records: document.records,
          tombstones: document.tombstones,
          truncated: true,
        );
      }
      final plaintext = document.encode();
      final currentVersion = switch (read) {
        PrivateStateReadFound(:final version) => version,
        PrivateStateReadAbsent() => null,
      };

      if (remoteDocument == null &&
          document.records.isEmpty &&
          document.tombstones.isEmpty) {
        await _saveMetadata(
          account: account,
          kind: kind,
          plaintext: plaintext,
          version: null,
          tombstones: tombstones,
        );
        return SwapPrivateHistorySyncResult(
          records: allLocal,
          kind: kind,
          remoteVersion: null,
          remoteWritten: false,
          truncated: false,
        );
      }

      if (remoteDocument != null &&
          _bytesEqual(remoteDocument.encode(), plaintext)) {
        await _saveMetadata(
          account: account,
          kind: kind,
          plaintext: plaintext,
          version: currentVersion,
          tombstones: tombstones,
        );
        return SwapPrivateHistorySyncResult(
          records: allLocal,
          kind: kind,
          remoteVersion: currentVersion,
          remoteWritten: false,
          truncated: document.truncated,
        );
      }

      final write = currentVersion == null
          ? await _repository.create(
              account: account,
              key: _key(kind),
              plaintext: plaintext,
            )
          : await _repository.compareAndSet(
              account: account,
              key: _key(kind),
              currentVersion: currentVersion,
              plaintext: plaintext,
            );
      if (write case PrivateStateWriteStored(:final version)) {
        await _saveMetadata(
          account: account,
          kind: kind,
          plaintext: plaintext,
          version: version,
          tombstones: tombstones,
        );
        return SwapPrivateHistorySyncResult(
          records: allLocal,
          kind: kind,
          remoteVersion: version,
          remoteWritten: true,
          truncated: document.truncated,
        );
      }
    }
    throw SwapPrivateHistoryConflictException(maxCasAttempts);
  }

  Future<void> _saveMetadata({
    required PrivateStateAccount account,
    required SwapPrivateHistoryKind kind,
    required Uint8List plaintext,
    required PrivateStateVersion? version,
    required Map<String, DateTime> tombstones,
  }) {
    final digest = sha256.convert(plaintext);
    return _metadataStore.save(
      accountUuid: account.accountUuid,
      kind: kind,
      metadata: SwapPrivateHistorySyncMetadata(
        plaintextHashBase64: base64UrlEncode(digest.bytes).replaceAll('=', ''),
        synchronizedAt: _now().toUtc(),
        remoteVersion: version,
        tombstones: tombstones,
      ),
    );
  }

  PrivateStateObjectKey _key(SwapPrivateHistoryKind kind) {
    return PrivateStateObjectKey(
      namespace: kind == SwapPrivateHistoryKind.swap
          ? PrivateStateNamespace.swapHistory
          : PrivateStateNamespace.payHistory,
      itemKey: _privateHistoryItemKey,
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

Map<String, DateTime> _mergeHistoryTombstones(
  Map<String, DateTime> left,
  Map<String, DateTime> right,
) {
  final merged = Map<String, DateTime>.of(left);
  for (final entry in right.entries) {
    final current = merged[entry.key];
    if (current == null || entry.value.isAfter(current)) {
      merged[entry.key] = entry.value.toUtc();
    }
  }
  return merged;
}

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
