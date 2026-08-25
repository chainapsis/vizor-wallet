import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_replica.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';

void main() {
  test('upsert preserves records omitted by a stale caller', () async {
    final store = _MemorySwapActivityStore([
      _record('legacy'),
      _record('remote-only'),
    ]);
    final replica = SwapActivityReplica(activityStore: store);

    final result = await replica.upsertRecords(
      accountUuid: 'account-1',
      records: [_record('legacy', status: SwapIntentStatus.processing)],
    );

    expect(result.map((record) => record.id), ['legacy', 'remote-only']);
    expect(result.first.status, SwapIntentStatus.processing);
  });

  test(
    'account mutations are serialized and preserve concurrent additions',
    () async {
      final firstSaveStarted = Completer<void>();
      final releaseFirstSave = Completer<void>();
      final store = _MemorySwapActivityStore([_record('legacy')])
        ..beforeSave = (saveCount) async {
          if (saveCount != 1) return;
          firstSaveStarted.complete();
          await releaseFirstSave.future;
        };
      final changes = <SwapActivityReplicaChange>[];
      final replica = SwapActivityReplica(
        activityStore: store,
        onChanged: changes.add,
      );

      final local = replica.upsertRecords(
        accountUuid: 'account-1',
        records: [_record('local')],
      );
      await firstSaveStarted.future;
      final remote = replica.reconcileRemoteRecords(
        accountUuid: 'account-1',
        remoteRecords: [_record('remote')],
        mergeConflict: (_, incoming) => incoming,
      );
      releaseFirstSave.complete();

      await Future.wait([local, remote]);

      expect(store.records.map((record) => record.id), [
        'legacy',
        'local',
        'remote',
      ]);
      expect(changes.map((change) => change.source), [
        SwapActivityReplicaChangeSource.localMutation,
        SwapActivityReplicaChangeSource.remoteReconcile,
      ]);
    },
  );

  test('late provider refresh does not resurrect a removed record', () async {
    final store = _MemorySwapActivityStore([_record('swap-a')]);
    final replica = SwapActivityReplica(activityStore: store);

    await replica.removeRecord(accountUuid: 'account-1', intentId: 'swap-a');
    await replica.updateExistingRecords(
      accountUuid: 'account-1',
      records: [_record('swap-a', status: SwapIntentStatus.complete)],
    );

    expect(store.records, isEmpty);
  });

  test('remote reconcile keeps local order and delegates conflicts', () async {
    final store = _MemorySwapActivityStore([
      _record('local'),
      _record('shared', status: SwapIntentStatus.processing),
    ]);
    final replica = SwapActivityReplica(activityStore: store);
    var conflictCount = 0;

    final result = await replica.reconcileRemoteRecords(
      accountUuid: 'account-1',
      remoteRecords: [
        _record('shared', status: SwapIntentStatus.complete),
        _record('remote'),
      ],
      mergeConflict: (local, remote) {
        conflictCount++;
        return remote;
      },
    );

    expect(conflictCount, 1);
    expect(result.map((record) => record.id), ['local', 'shared', 'remote']);
    expect(result[1].status, SwapIntentStatus.complete);
  });

  test('a failed mutation does not poison the account queue', () async {
    final store = _MemorySwapActivityStore([_record('legacy')])
      ..failNextSave = true;
    final replica = SwapActivityReplica(activityStore: store);

    await expectLater(
      replica.upsertRecords(
        accountUuid: 'account-1',
        records: [_record('failed')],
      ),
      throwsStateError,
    );
    await replica.upsertRecords(
      accountUuid: 'account-1',
      records: [_record('recovered')],
    );

    expect(store.records.map((record) => record.id), ['legacy', 'recovered']);
  });
}

SwapIntentRecord _record(
  String id, {
  SwapIntentStatus status = SwapIntentStatus.awaitingDeposit,
}) {
  return SwapIntentRecord.fromIntent(
    SwapIntent(
      id: id,
      pair: 'ZEC -> USDC',
      sellAmount: '1 ZEC',
      receiveEstimate: '70 USDC',
      provider: 'NEAR Intents',
      status: status,
      nextAction: 'Checking status',
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
      depositAddress: 'deposit-$id',
      providerQuoteId: 'quote-$id',
      accountUuid: 'account-1',
    ),
  );
}

class _MemorySwapActivityStore implements SwapActivityStore {
  _MemorySwapActivityStore(List<SwapIntentRecord> records)
    : records = List.of(records);

  List<SwapIntentRecord> records;
  int saveCount = 0;
  bool failNextSave = false;
  Future<void> Function(int saveCount)? beforeSave;

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async => List.of(records);

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {
    saveCount++;
    await beforeSave?.call(saveCount);
    if (failNextSave) {
      failNextSave = false;
      throw StateError('save failed');
    }
    this.records = List.of(records);
  }

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {
    records = const [];
  }
}
