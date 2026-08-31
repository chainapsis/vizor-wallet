import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_models.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_object_repository.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/private_state/swap_private_history_document.dart';
import 'package:zcash_wallet/src/features/swap/private_state/swap_private_history_sync.dart';
import 'package:zcash_wallet/src/features/swap/private_state/swap_private_history_sync_metadata.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_replica.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';

void main() {
  const account = PrivateStateAccount(
    dbPath: '/wallet.db',
    network: 'main',
    accountUuid: 'account-a',
  );

  test('metadata round-trips the merged archive state', () {
    final archiveState = _document(['remote']);
    final encoded = FinalizedActivityArchiveMetadata(
      lastSlot: 1,
      hiddenRecordIds: const {'hidden'},
      archiveState: archiveState,
    ).toJson();
    final decoded = FinalizedActivityArchiveMetadata.fromJson(
      jsonDecode(jsonEncode(encoded)),
    );

    expect(encoded['schema'], 1);
    expect(decoded?.lastSlot, 1);
    expect(decoded?.hiddenRecordIds, {'hidden'});
    expect(decoded?.archiveState, archiveState);
  });

  test('metadata rejects cumulative snapshot schema', () {
    final decoded = FinalizedActivityArchiveMetadata.fromJson({
      'schema': 2,
      'last_slot': 3,
      'hidden_record_ids': ['hidden'],
    });

    expect(decoded, isNull);
  });

  test('backfills only complete and refunded activity into slot one', () async {
    final repository = _MemoryRepository();
    final store = _MemoryActivityStore([
      _record('complete', SwapIntentStatus.complete),
      _record('refunded', SwapIntentStatus.refunded),
      _record('failed', SwapIntentStatus.failed),
      _record('expired', SwapIntentStatus.expired),
      _record('processing', SwapIntentStatus.processing),
    ]);
    final sync = _sync(repository: repository, store: store);

    await sync.synchronize(account: account, kind: SwapPrivateHistoryKind.swap);

    expect(repository.createdKeys.single.itemKey, 'delta-v1:1');
    final document = SwapPrivateHistoryDocument.decode(
      repository.objects['delta-v1:1']!,
      expectedKind: SwapPrivateHistoryKind.swap,
    );
    expect(document.records.map((record) => record.id).toSet(), {
      'complete',
      'refunded',
    });
  });

  test('uses the pay namespace and excludes finalized swap records', () async {
    final repository = _MemoryRepository();
    final store = _MemoryActivityStore([
      _record('swap', SwapIntentStatus.complete),
      _record('pay', SwapIntentStatus.refunded, payMode: true),
    ]);
    final sync = _sync(repository: repository, store: store);

    await sync.synchronize(account: account, kind: SwapPrivateHistoryKind.pay);

    expect(
      repository.createdKeys.single.namespace,
      PrivateStateNamespace.payHistory,
    );
    final document = SwapPrivateHistoryDocument.decode(
      repository.objects['delta-v1:1']!,
      expectedKind: SwapPrivateHistoryKind.pay,
    );
    expect(document.records.map((record) => record.id), ['pay']);
  });

  test('later slots contain only new finalized records', () async {
    final repository = _MemoryRepository();
    final store = _MemoryActivityStore([
      _record('first', SwapIntentStatus.complete),
    ]);
    final sync = _sync(repository: repository, store: store);

    await sync.synchronize(account: account, kind: SwapPrivateHistoryKind.swap);
    store.records.add(_record('second', SwapIntentStatus.refunded));
    await sync.synchronize(account: account, kind: SwapPrivateHistoryKind.swap);

    expect(repository.createdKeys.map((key) => key.itemKey), [
      'delta-v1:1',
      'delta-v1:2',
    ]);
    final first = SwapPrivateHistoryDocument.decode(
      repository.objects['delta-v1:1']!,
      expectedKind: SwapPrivateHistoryKind.swap,
    );
    final second = SwapPrivateHistoryDocument.decode(
      repository.objects['delta-v1:2']!,
      expectedKind: SwapPrivateHistoryKind.swap,
    );
    expect(first.records.map((record) => record.id), ['first']);
    expect(second.records.map((record) => record.id), ['second']);
  });

  test(
    'does not reveal an account with no complete or refunded history',
    () async {
      final repository = _MemoryRepository();
      final sync = _sync(
        repository: repository,
        store: _MemoryActivityStore([
          _record('failed', SwapIntentStatus.failed),
          _record('expired', SwapIntentStatus.expired),
        ]),
      );

      await sync.synchronize(
        account: account,
        kind: SwapPrivateHistoryKind.swap,
      );

      expect(repository.createdKeys, isEmpty);
    },
  );

  test('fresh installation merges every contiguous delta', () async {
    final repository = _MemoryRepository()
      ..objects['delta-v1:1'] = _document(['remote-a'])
      ..objects['delta-v1:2'] = _document(['remote-b']);
    final store = _MemoryActivityStore(const []);
    final metadata = _MemoryMetadataStore();
    final sync = _sync(
      repository: repository,
      store: store,
      metadata: metadata,
    );

    await sync.synchronize(account: account, kind: SwapPrivateHistoryKind.swap);

    expect(store.records.map((record) => record.id).toSet(), {
      'remote-a',
      'remote-b',
    });
    expect(metadata.value?.lastSlot, 2);
  });

  test('pay recovery merges every contiguous delta', () async {
    Uint8List payDocument(String id) => SwapPrivateHistoryDocument(
      kind: SwapPrivateHistoryKind.pay,
      records: [_record(id, SwapIntentStatus.complete, payMode: true)],
    ).encode();

    final repository = _MemoryRepository()
      ..objects['delta-v1:1'] = payDocument('pay-a')
      ..objects['delta-v1:2'] = payDocument('pay-b');
    final store = _MemoryActivityStore(const []);
    final metadata = _MemoryMetadataStore();

    await _sync(
      repository: repository,
      store: store,
      metadata: metadata,
    ).synchronize(account: account, kind: SwapPrivateHistoryKind.pay);

    expect(store.records.map((record) => record.id).toSet(), {
      'pay-a',
      'pay-b',
    });
    expect(metadata.value?.lastSlot, 2);
  });

  test(
    'later evidence for the same record is merged during recovery',
    () async {
      final initial = _record('remote', SwapIntentStatus.complete);
      final enriched = initial.copyWith(
        destinationChainTxHash: 'destination-hash',
        updatedAt: DateTime.utc(2026, 8, 26),
      );
      final repository = _MemoryRepository()
        ..objects['delta-v1:1'] = SwapPrivateHistoryDocument(
          kind: SwapPrivateHistoryKind.swap,
          records: [initial],
        ).encode()
        ..objects['delta-v1:2'] = SwapPrivateHistoryDocument(
          kind: SwapPrivateHistoryKind.swap,
          records: [enriched],
        ).encode();
      final store = _MemoryActivityStore(const []);

      await _sync(
        repository: repository,
        store: store,
      ).synchronize(account: account, kind: SwapPrivateHistoryKind.swap);

      expect(store.records, hasLength(1));
      expect(store.records.single.destinationChainTxHash, 'destination-hash');
    },
  );

  test('cached merged state reads only the following slot', () async {
    final archiveState = _document(['remote']);
    final repository = _MemoryRepository()
      ..objects['delta-v1:1'] = archiveState;
    final store = _MemoryActivityStore([
      _record('remote', SwapIntentStatus.complete),
    ]);
    final metadata = _MemoryMetadataStore(
      value: FinalizedActivityArchiveMetadata(
        lastSlot: 1,
        archiveState: archiveState,
      ),
    );

    await _sync(
      repository: repository,
      store: store,
      metadata: metadata,
    ).synchronize(account: account, kind: SwapPrivateHistoryKind.swap);

    expect(repository.readKeys.map((key) => key.itemKey), ['delta-v1:2']);
    expect(repository.createdKeys, isEmpty);
  });

  test('cached merged state restores a missing local replica', () async {
    final archiveState = _document(['remote']);
    final repository = _MemoryRepository()
      ..objects['delta-v1:1'] = archiveState;
    final store = _MemoryActivityStore(const []);
    final metadata = _MemoryMetadataStore(
      value: FinalizedActivityArchiveMetadata(
        lastSlot: 1,
        archiveState: archiveState,
      ),
    );

    await _sync(
      repository: repository,
      store: store,
      metadata: metadata,
    ).synchronize(account: account, kind: SwapPrivateHistoryKind.swap);

    expect(store.records.map((record) => record.id), ['remote']);
    expect(repository.readKeys.map((key) => key.itemKey), ['delta-v1:2']);
  });

  test('missing merged state replays deltas from slot one', () async {
    final delta = _document(['remote']);
    final repository = _MemoryRepository()..objects['delta-v1:1'] = delta;
    final metadata = _MemoryMetadataStore(
      value: const FinalizedActivityArchiveMetadata(lastSlot: 1),
    );
    final sync = _sync(
      repository: repository,
      store: _MemoryActivityStore(const []),
      metadata: metadata,
    );

    await sync.synchronize(account: account, kind: SwapPrivateHistoryKind.swap);
    repository.readKeys.clear();
    await sync.synchronize(account: account, kind: SwapPrivateHistoryKind.swap);

    expect(repository.readKeys.map((key) => key.itemKey), ['delta-v1:2']);
    expect(metadata.value?.archiveState, delta);
  });

  test(
    'create collision merges winner and advances to the next slot',
    () async {
      final repository = _MemoryRepository()
        ..conflictSlot = 1
        ..conflictWinner = _document(['concurrent']);
      final store = _MemoryActivityStore([
        _record('local', SwapIntentStatus.complete),
      ]);
      final sync = _sync(repository: repository, store: store);

      await sync.synchronize(
        account: account,
        kind: SwapPrivateHistoryKind.swap,
      );

      expect(repository.createdKeys.map((key) => key.itemKey), [
        'delta-v1:1',
        'delta-v1:2',
      ]);
      final latest = SwapPrivateHistoryDocument.decode(
        repository.objects['delta-v1:2']!,
        expectedKind: SwapPrivateHistoryKind.swap,
      );
      expect(latest.records.map((record) => record.id), ['local']);
    },
  );

  test(
    'local deletion stays hidden without modifying remote archive',
    () async {
      final remoteRecord = _record('remote', SwapIntentStatus.complete);
      final repository = _MemoryRepository()
        ..objects['delta-v1:1'] = SwapPrivateHistoryDocument(
          kind: SwapPrivateHistoryKind.swap,
          records: [remoteRecord],
        ).encode();
      final store = _MemoryActivityStore([remoteRecord]);
      final metadata = _MemoryMetadataStore(
        value: const FinalizedActivityArchiveMetadata(lastSlot: 1),
      );
      final sync = _sync(
        repository: repository,
        store: store,
        metadata: metadata,
      );
      await sync.recordLocalDeletions(
        accountUuid: account.accountUuid,
        records: [remoteRecord],
      );
      store.records = const [];

      await sync.synchronize(
        account: account,
        kind: SwapPrivateHistoryKind.swap,
      );

      expect(store.records, isEmpty);
      expect(repository.objects.keys, ['delta-v1:1']);
      expect(metadata.value?.hiddenRecordIds, {'remote'});
    },
  );
}

FinalizedActivityArchiveSync _sync({
  required _MemoryRepository repository,
  required _MemoryActivityStore store,
  _MemoryMetadataStore? metadata,
}) => FinalizedActivityArchiveSync(
  repository: repository,
  replica: SwapActivityReplica(activityStore: store),
  metadataStore: metadata ?? _MemoryMetadataStore(),
);

Uint8List _document(List<String> ids) => SwapPrivateHistoryDocument(
  kind: SwapPrivateHistoryKind.swap,
  records: [for (final id in ids) _record(id, SwapIntentStatus.complete)],
).encode();

SwapIntentRecord _record(
  String id,
  SwapIntentStatus status, {
  bool payMode = false,
}) => SwapIntentRecord(
  id: id,
  providerLabel: 'NEAR Intents',
  pairText: 'ZEC -> USDC',
  sellAmountText: '1 ZEC',
  receiveEstimateText: '70 USDC',
  status: status,
  nextAction: status.label,
  sellAmountBaseUnits: BigInt.one,
  direction: SwapDirection.zecToExternal,
  externalAsset: SwapAsset.usdc,
  payMode: payMode,
  depositAddress: 'deposit-$id',
  providerQuoteId: 'quote-$id',
  createdAt: DateTime.utc(2026, 8, 25),
  updatedAt: DateTime.utc(2026, 8, 25),
);

class _MemoryRepository implements PrivateStateObjectRepository {
  final Map<String, Uint8List> objects = {};
  final List<PrivateStateObjectKey> readKeys = [];
  final List<PrivateStateObjectKey> createdKeys = [];
  int? conflictSlot;
  Uint8List? conflictWinner;

  @override
  Future<PrivateStateReadResult> read({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  }) async {
    readKeys.add(key);
    final plaintext = objects[key.itemKey];
    return plaintext == null
        ? const PrivateStateReadAbsent()
        : PrivateStateReadFound(plaintext: plaintext);
  }

  @override
  Future<PrivateStateCreateResult> create({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required Uint8List plaintext,
  }) async {
    createdKeys.add(key);
    final slot = int.parse(key.itemKey.split(':').last);
    if (slot == conflictSlot) {
      objects[key.itemKey] = conflictWinner!;
      conflictSlot = null;
      return const PrivateStateCreateConflict();
    }
    if (objects.containsKey(key.itemKey)) {
      return const PrivateStateCreateConflict();
    }
    objects[key.itemKey] = plaintext;
    return const PrivateStateCreated();
  }
}

class _MemoryActivityStore implements SwapActivityStore {
  _MemoryActivityStore(List<SwapIntentRecord> records)
    : records = List.of(records);

  List<SwapIntentRecord> records;

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async => List.of(records);

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {
    this.records = List.of(records);
  }

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {
    records = const [];
  }
}

class _MemoryMetadataStore implements FinalizedActivityArchiveMetadataStore {
  _MemoryMetadataStore({this.value});

  FinalizedActivityArchiveMetadata? value;

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {
    value = null;
  }

  @override
  Future<void> hideRecords({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
    required Iterable<String> recordIds,
  }) async {
    value = FinalizedActivityArchiveMetadata(
      lastSlot: value?.lastSlot ?? 0,
      hiddenRecordIds: {...?value?.hiddenRecordIds, ...recordIds},
      archiveState: value?.archiveState,
    );
  }

  @override
  Future<FinalizedActivityArchiveMetadata?> load({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
  }) async => value;

  @override
  Future<void> save({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
    required FinalizedActivityArchiveMetadata metadata,
  }) async {
    value = FinalizedActivityArchiveMetadata(
      lastSlot: metadata.lastSlot,
      hiddenRecordIds: {
        ...?value?.hiddenRecordIds,
        ...metadata.hiddenRecordIds,
      },
      archiveState: metadata.archiveState,
    );
  }
}
