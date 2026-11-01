import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';

/// Activity kept in memory, whose saves wait for [hold] and whose reads of
/// [slowAccount] wait for [holdRead] when they are set.
class _MemoryStore implements SwapActivityStore {
  final records = <String, List<SwapIntentRecord>>{};
  Completer<void>? hold;
  Completer<void>? holdRead;
  String? slowAccount;

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async {
    if (accountUuid == slowAccount) await holdRead?.future;
    return records[accountUuid] ?? const [];
  }

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {
    await hold?.future;
    this.records[accountUuid] = records;
  }

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {
    records.remove(accountUuid);
  }
}

/// One saved swap.
const _record = SwapIntentRecord(
  id: 'swap',
  providerLabel: 'NEAR Intents',
  pairText: 'USDC -> ZEC',
  sellAmountText: '70 USDC',
  receiveEstimateText: '0.7 ZEC',
  status: SwapIntentStatus.awaitingExternalDeposit,
  nextAction: 'Send USDC',
);

void main() {
  test('deleting an account waits for a save under way', () async {
    final inner = _MemoryStore()..hold = Completer<void>();
    final store = DeletionSafeSwapActivityStore(inner);
    final save = store.saveRecords(accountUuid: 'a', records: [_record]);
    var deleted = false;
    final delete = store
        .deleteForAccount(accountUuid: 'a')
        .then((_) => deleted = true);
    await pumpEventQueue();
    expect(deleted, isFalse, reason: 'the held save is still writing');

    inner.hold!.complete();
    await save;
    await delete;
    expect(inner.records.containsKey('a'), isFalse, reason: 'deleted last');
  });

  test('a save for a deleted account writes nothing', () async {
    final inner = _MemoryStore();
    final store = DeletionSafeSwapActivityStore(inner);
    await store.saveRecords(accountUuid: 'b', records: [_record]);
    await store.deleteForAccount(accountUuid: 'a');

    // A save prepared before the deletion arrives after it.
    await store.saveRecords(accountUuid: 'a', records: [_record]);
    expect(inner.records.containsKey('a'), isFalse);
    // Other accounts save as before.
    await store.saveRecords(accountUuid: 'b', records: const []);
    expect(inner.records['b'], isEmpty);
  });

  test('a read waits for saves accepted before it', () async {
    final inner = _MemoryStore();
    final store = DeletionSafeSwapActivityStore(inner);
    await store.saveRecords(accountUuid: 'a', records: const []);
    inner.hold = Completer<void>();
    // A save is under way, and a new swap's save queues behind it.
    final pending = store.saveRecords(accountUuid: 'a', records: const []);
    final newSwap = store.saveRecords(accountUuid: 'a', records: [_record]);
    // A status refresh reads the list meanwhile, to merge and save it back.
    final refreshRead = store.loadRecords(accountUuid: 'a');
    inner.hold!.complete();
    await pending;
    await newSwap;
    expect(await refreshRead, [
      _record,
    ], reason: 'the refresh sees the new swap, so its save cannot drop it');
  });

  test('two merges queued together both keep their swaps', () async {
    final inner = _MemoryStore();
    final store = DeletionSafeSwapActivityStore(inner);
    await store.saveRecords(accountUuid: 'a', records: [_record]);
    inner.hold = Completer<void>();
    // A private swap's start and an older swap's status refresh both merge
    // into the same account's list, queued before either saves.
    final started = _record.copyWith(id: 'started');
    final refreshed = _record.copyWith(nextAction: 'Refreshed');
    final start = store.update(
      accountUuid: 'a',
      transform: (saved) => [started, ...saved],
    );
    final refresh = store.update(
      accountUuid: 'a',
      transform: (saved) => [
        for (final record in saved) record.id == 'swap' ? refreshed : record,
      ],
    );
    inner.hold!.complete();
    await start;
    await refresh;
    expect(inner.records['a']!.map((r) => (r.id, r.nextAction)), [
      ('started', 'Send USDC'),
      ('swap', 'Refreshed'),
    ], reason: 'the refresh did not overwrite the started swap');
  });

  test('a merge for a deleted account writes nothing', () async {
    final inner = _MemoryStore();
    final store = DeletionSafeSwapActivityStore(inner);
    await store.deleteForAccount(accountUuid: 'a');
    await store.update(accountUuid: 'a', transform: (_) => [_record]);
    expect(inner.records.containsKey('a'), isFalse);
  });

  test("one account's slow read does not hold up another's", () async {
    final inner = _MemoryStore()
      ..slowAccount = 'a'
      ..holdRead = Completer<void>();
    final store = DeletionSafeSwapActivityStore(inner);
    await store.saveRecords(accountUuid: 'b', records: [_record]);
    final slow = store.loadRecords(accountUuid: 'a');
    expect(await store.loadRecords(accountUuid: 'b'), [_record]);
    inner.holdRead!.complete();
    expect(await slow, isEmpty);
  });

  test('a replacement does not read what it replaces', () async {
    final inner = _MemoryStore()
      ..slowAccount = 'a'
      ..holdRead = Completer<void>();
    final store = DeletionSafeSwapActivityStore(inner);
    // A read would wait on the held read and never finish.
    await store.saveRecords(accountUuid: 'a', records: [_record]);
    expect(inner.records['a']!.map((r) => r.id), ['swap']);
  });
}
