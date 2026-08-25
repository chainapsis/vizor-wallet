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

    final result = await sync.synchronize(
      account: account,
      kind: SwapPrivateHistoryKind.swap,
    );

    expect(result.remoteWritten, isTrue);
    expect(result.lastSlot, 1);
    expect(repository.createdKeys.single.itemKey, 'archive-v1:1');
    final document = SwapPrivateHistoryDocument.decode(
      repository.objects['archive-v1:1']!,
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
      repository.objects['archive-v1:1']!,
      expectedKind: SwapPrivateHistoryKind.pay,
    );
    expect(document.records.map((record) => record.id), ['pay']);
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

      final result = await sync.synchronize(
        account: account,
        kind: SwapPrivateHistoryKind.swap,
      );

      expect(result.remoteWritten, isFalse);
      expect(repository.createdKeys, isEmpty);
    },
  );

  test(
    'fresh installation scans contiguous slots and restores latest',
    () async {
      final repository = _MemoryRepository()
        ..objects['archive-v1:1'] = _document(['remote-a'])
        ..objects['archive-v1:2'] = _document(['remote-a', 'remote-b']);
      final store = _MemoryActivityStore(const []);
      final metadata = _MemoryMetadataStore();
      final sync = _sync(
        repository: repository,
        store: store,
        metadata: metadata,
      );

      final result = await sync.synchronize(
        account: account,
        kind: SwapPrivateHistoryKind.swap,
      );

      expect(result.lastSlot, 2);
      expect(result.remoteWritten, isFalse);
      expect(store.records.map((record) => record.id).toSet(), {
        'remote-a',
        'remote-b',
      });
      expect(metadata.value?.lastSlot, 2);
    },
  );

  test('preserves a remote truncation marker without writing a slot', () async {
    final repository = _MemoryRepository()
      ..objects['archive-v1:1'] = SwapPrivateHistoryDocument(
        kind: SwapPrivateHistoryKind.swap,
        records: [_record('newest', SwapIntentStatus.complete)],
        truncated: true,
      ).encode();
    final sync = _sync(
      repository: repository,
      store: _MemoryActivityStore(const []),
    );

    final result = await sync.synchronize(
      account: account,
      kind: SwapPrivateHistoryKind.swap,
    );

    expect(result.truncated, isTrue);
    expect(result.remoteWritten, isFalse);
    expect(repository.createdKeys, isEmpty);
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

      final result = await sync.synchronize(
        account: account,
        kind: SwapPrivateHistoryKind.swap,
      );

      expect(result.lastSlot, 2);
      expect(repository.createdKeys.map((key) => key.itemKey), [
        'archive-v1:1',
        'archive-v1:2',
      ]);
      final latest = SwapPrivateHistoryDocument.decode(
        repository.objects['archive-v1:2']!,
        expectedKind: SwapPrivateHistoryKind.swap,
      );
      expect(latest.records.map((record) => record.id).toSet(), {
        'concurrent',
        'local',
      });
    },
  );

  test(
    'local deletion stays hidden without modifying remote archive',
    () async {
      final remoteRecord = _record('remote', SwapIntentStatus.complete);
      final repository = _MemoryRepository()
        ..objects['archive-v1:1'] = SwapPrivateHistoryDocument(
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

      final result = await sync.synchronize(
        account: account,
        kind: SwapPrivateHistoryKind.swap,
      );

      expect(result.remoteWritten, isFalse);
      expect(store.records, isEmpty);
      expect(repository.objects.keys, ['archive-v1:1']);
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
  final List<PrivateStateObjectKey> createdKeys = [];
  int? conflictSlot;
  Uint8List? conflictWinner;

  @override
  Future<PrivateStateReadResult> read({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  }) async {
    final plaintext = objects[key.itemKey];
    return plaintext == null
        ? const PrivateStateReadAbsent()
        : PrivateStateReadFound(
            plaintext: plaintext,
            version: PrivateStateVersion(
              revision: BigInt.one,
              envelopeHashBase64: 'hash',
            ),
          );
  }

  @override
  Future<PrivateStateWriteResult> create({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required Uint8List plaintext,
  }) async {
    createdKeys.add(key);
    final slot = int.parse(key.itemKey.split(':').last);
    if (slot == conflictSlot) {
      objects[key.itemKey] = conflictWinner!;
      conflictSlot = null;
      return const PrivateStateWriteConflict();
    }
    if (objects.containsKey(key.itemKey)) {
      return const PrivateStateWriteConflict();
    }
    objects[key.itemKey] = plaintext;
    return PrivateStateWriteStored(
      PrivateStateVersion(revision: BigInt.one, envelopeHashBase64: 'hash'),
    );
  }

  @override
  Future<PrivateStateWriteResult> compareAndSet({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required PrivateStateVersion currentVersion,
    required Uint8List plaintext,
  }) => throw UnsupportedError('append-only archive');
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
    );
  }
}
