import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/swap_models.dart';
import 'swap_activity_store.dart';

enum SwapActivityReplicaChangeSource {
  localMutation,
  providerRefresh,
  remoteReconcile,
  localAccountDeletion,
}

class SwapActivityReplicaChange {
  SwapActivityReplicaChange({
    required this.accountUuid,
    required this.source,
    required List<SwapIntentRecord> records,
    List<SwapIntentRecord> changedRecords = const [],
    List<SwapIntentRecord> removedRecords = const [],
  }) : records = List.unmodifiable(records),
       changedRecords = List.unmodifiable(changedRecords),
       removedRecords = List.unmodifiable(removedRecords);

  final String accountUuid;
  final SwapActivityReplicaChangeSource source;
  final List<SwapIntentRecord> records;
  final List<SwapIntentRecord> changedRecords;
  final List<SwapIntentRecord> removedRecords;
}

class SwapActivityReplicaChangeNotifier
    extends Notifier<SwapActivityReplicaChange?> {
  @override
  SwapActivityReplicaChange? build() => null;

  void publish(SwapActivityReplicaChange change) {
    state = change;
  }
}

final swapActivityReplicaChangeProvider =
    NotifierProvider<
      SwapActivityReplicaChangeNotifier,
      SwapActivityReplicaChange?
    >(SwapActivityReplicaChangeNotifier.new);

final swapActivityReplicaProvider = Provider<SwapActivityReplica>((ref) {
  return SwapActivityReplica(
    activityStore: ref.read(swapActivityStoreProvider),
    onChanged: (change) {
      ref.read(swapActivityRecordsRevisionProvider.notifier).bump();
      ref.read(swapActivityReplicaChangeProvider.notifier).publish(change);
    },
  );
});

typedef SwapActivityRecordMerger =
    SwapIntentRecord Function(
      SwapIntentRecord local,
      SwapIntentRecord incoming,
    );

/// Serializes all local history mutations for an account.
///
/// The durable store remains compatible with the legacy v1 envelope. This
/// layer changes mutation semantics from whole-list replacement to explicit
/// upsert, update-existing, remove, and remote reconciliation operations so a
/// stale caller cannot erase records learned from another source.
class SwapActivityReplica {
  SwapActivityReplica({
    required SwapActivityStore activityStore,
    void Function(SwapActivityReplicaChange change)? onChanged,
  }) : _activityStore = activityStore,
       _onChanged = onChanged;

  final SwapActivityStore _activityStore;
  final void Function(SwapActivityReplicaChange change)? _onChanged;
  final Map<String, Future<void>> _accountMutationTails = {};

  Future<List<SwapIntentRecord>> loadRecords({required String accountUuid}) {
    return _activityStore.loadRecords(accountUuid: accountUuid);
  }

  Future<List<SwapIntentRecord>> upsertRecords({
    required String accountUuid,
    required Iterable<SwapIntentRecord> records,
    SwapActivityReplicaChangeSource source =
        SwapActivityReplicaChangeSource.localMutation,
  }) {
    final incoming = List<SwapIntentRecord>.of(records);
    if (incoming.isEmpty) return loadRecords(accountUuid: accountUuid);
    return _mutate(accountUuid, source, incoming, (current) {
      final merged = List<SwapIntentRecord>.of(current);
      for (final record in incoming) {
        final scoped = record.copyWith(accountUuid: accountUuid);
        final index = merged.indexWhere((item) => item.id == scoped.id);
        if (index < 0) {
          merged.add(scoped);
        } else {
          merged[index] = scoped;
        }
      }
      return merged;
    });
  }

  /// Updates only records that still exist when the mutation queue is entered.
  /// This prevents a status request that started before a user deletion from
  /// resurrecting the deleted record when its response arrives later.
  Future<List<SwapIntentRecord>> updateExistingRecords({
    required String accountUuid,
    required Iterable<SwapIntentRecord> records,
    SwapActivityReplicaChangeSource source =
        SwapActivityReplicaChangeSource.providerRefresh,
  }) {
    final incoming = {for (final record in records) record.id: record};
    if (incoming.isEmpty) return loadRecords(accountUuid: accountUuid);
    return _mutate(accountUuid, source, incoming.values, (current) {
      return [
        for (final record in current)
          if (incoming[record.id] case final replacement?)
            replacement.copyWith(accountUuid: accountUuid)
          else
            record,
      ];
    });
  }

  Future<List<SwapIntentRecord>> removeRecord({
    required String accountUuid,
    required String intentId,
  }) {
    return _serialize(accountUuid, () async {
      final current = await _activityStore.loadRecords(
        accountUuid: accountUuid,
      );
      final removed = [
        for (final record in current)
          if (record.id == intentId) record,
      ];
      final updated = [
        for (final record in current)
          if (record.id != intentId) record,
      ];
      await _activityStore.saveRecords(
        accountUuid: accountUuid,
        records: updated,
      );
      _emit(
        accountUuid,
        SwapActivityReplicaChangeSource.localMutation,
        updated,
        changedRecords: removed,
        removedRecords: removed,
      );
      return List.unmodifiable(updated);
    });
  }

  /// Adds remote-only records and delegates same-ID conflicts to the feature
  /// merger. Absence from a remote snapshot never deletes a local record;
  /// deletion is installation-local and is filtered before reconciliation.
  Future<List<SwapIntentRecord>> reconcileRemoteRecords({
    required String accountUuid,
    required Iterable<SwapIntentRecord> remoteRecords,
    required SwapActivityRecordMerger mergeConflict,
  }) {
    final incoming = List<SwapIntentRecord>.of(remoteRecords);
    if (incoming.isEmpty) return loadRecords(accountUuid: accountUuid);
    return _mutate(
      accountUuid,
      SwapActivityReplicaChangeSource.remoteReconcile,
      incoming,
      (current) {
        final merged = List<SwapIntentRecord>.of(current);
        for (final remote in incoming) {
          final scopedRemote = remote.copyWith(accountUuid: accountUuid);
          final index = merged.indexWhere((item) => item.id == remote.id);
          if (index < 0) {
            merged.add(scopedRemote);
          } else {
            merged[index] = mergeConflict(
              merged[index],
              scopedRemote,
            ).copyWith(accountUuid: accountUuid);
          }
        }
        return merged;
      },
    );
  }

  Future<void> deleteLocalAccount({required String accountUuid}) async {
    await _serialize(accountUuid, () async {
      await _activityStore.deleteForAccount(accountUuid: accountUuid);
      _emit(
        accountUuid,
        SwapActivityReplicaChangeSource.localAccountDeletion,
        const [],
      );
    });
  }

  Future<List<SwapIntentRecord>> _mutate(
    String accountUuid,
    SwapActivityReplicaChangeSource source,
    Iterable<SwapIntentRecord> changedRecords,
    List<SwapIntentRecord> Function(List<SwapIntentRecord> current) transform,
  ) {
    return _serialize(accountUuid, () async {
      final current = await _activityStore.loadRecords(
        accountUuid: accountUuid,
      );
      final updated = transform(current);
      await _activityStore.saveRecords(
        accountUuid: accountUuid,
        records: updated,
      );
      _emit(
        accountUuid,
        source,
        updated,
        changedRecords: changedRecords.toList(growable: false),
      );
      return List.unmodifiable(updated);
    });
  }

  Future<T> _serialize<T>(
    String accountUuid,
    Future<T> Function() action,
  ) async {
    final previous = _accountMutationTails[accountUuid] ?? Future.value();
    final turn = Completer<void>();
    _accountMutationTails[accountUuid] = turn.future;
    try {
      try {
        await previous;
      } on Object {
        // A failed mutation must not permanently poison this account's queue.
      }
      return await action();
    } finally {
      turn.complete();
      if (identical(_accountMutationTails[accountUuid], turn.future)) {
        _accountMutationTails.remove(accountUuid);
      }
    }
  }

  void _emit(
    String accountUuid,
    SwapActivityReplicaChangeSource source,
    List<SwapIntentRecord> records, {
    List<SwapIntentRecord> changedRecords = const [],
    List<SwapIntentRecord> removedRecords = const [],
  }) {
    _onChanged?.call(
      SwapActivityReplicaChange(
        accountUuid: accountUuid,
        source: source,
        records: records,
        changedRecords: changedRecords,
        removedRecords: removedRecords,
      ),
    );
  }
}
