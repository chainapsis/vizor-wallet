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
    accountUuid: 'local-account',
  );

  test(
    'first pass uploads legacy local history and records metadata',
    () async {
      final activityStore = _MemoryActivityStore([_record('legacy')]);
      final repository = _MemoryRepository();
      final metadataStore = _MemoryMetadataStore();
      final sync = SwapPrivateHistorySync(
        repository: repository,
        replica: SwapActivityReplica(activityStore: activityStore),
        metadataStore: metadataStore,
        now: () => DateTime.utc(2026, 8, 25),
      );

      final result = await sync.synchronize(
        account: account,
        kind: SwapPrivateHistoryKind.swap,
      );

      expect(result.remoteWritten, isTrue);
      expect(repository.createCount, 1);
      expect(repository.lastKey?.namespace, PrivateStateNamespace.swapHistory);
      expect(repository.lastKey?.itemKey, 'history-v1');
      final uploaded = SwapPrivateHistoryDocument.decode(
        repository.plaintext!,
        expectedKind: SwapPrivateHistoryKind.swap,
      );
      expect(uploaded.records.single.id, 'legacy');
      expect(
        metadataStore.values.values.single.remoteVersion?.revision,
        BigInt.one,
      );
    },
  );

  test(
    'remote-only history is restored locally without redundant write',
    () async {
      final activityStore = _MemoryActivityStore(const []);
      final changes = <SwapActivityReplicaChange>[];
      final remote = SwapPrivateHistoryDocument(
        kind: SwapPrivateHistoryKind.swap,
        records: [_record('remote')],
      ).encode();
      final repository = _MemoryRepository(
        plaintext: remote,
        version: _version(4),
      );
      final sync = SwapPrivateHistorySync(
        repository: repository,
        replica: SwapActivityReplica(
          activityStore: activityStore,
          onChanged: changes.add,
        ),
        metadataStore: _MemoryMetadataStore(),
      );

      final result = await sync.synchronize(
        account: account,
        kind: SwapPrivateHistoryKind.swap,
      );

      expect(result.remoteWritten, isFalse);
      expect(repository.putCount, 0);
      expect(activityStore.records.single.id, 'remote');
      expect(activityStore.records.single.accountUuid, account.accountUuid);
      expect(
        changes.single.source,
        SwapActivityReplicaChangeSource.remoteReconcile,
      );
    },
  );

  test(
    'truncation marker remains sticky after remote-only restoration',
    () async {
      final remote = SwapPrivateHistoryDocument(
        kind: SwapPrivateHistoryKind.swap,
        records: [_record('remote')],
        truncated: true,
      ).encode();
      final repository = _MemoryRepository(
        plaintext: remote,
        version: _version(4),
      );
      final sync = SwapPrivateHistorySync(
        repository: repository,
        replica: SwapActivityReplica(
          activityStore: _MemoryActivityStore(const []),
        ),
        metadataStore: _MemoryMetadataStore(),
      );

      final result = await sync.synchronize(
        account: account,
        kind: SwapPrivateHistoryKind.swap,
      );

      expect(result.truncated, isTrue);
      expect(result.remoteWritten, isFalse);
      expect(repository.putCount, 0);
    },
  );

  test('CAS conflict re-reads, merges the winner, and retries', () async {
    final activityStore = _MemoryActivityStore([_record('local')]);
    final repository = _MemoryRepository()
      ..conflictFirstWriteWith(
        SwapPrivateHistoryDocument(
          kind: SwapPrivateHistoryKind.swap,
          records: [_record('concurrent')],
        ).encode(),
      );
    final sync = SwapPrivateHistorySync(
      repository: repository,
      replica: SwapActivityReplica(activityStore: activityStore),
      metadataStore: _MemoryMetadataStore(),
    );

    final result = await sync.synchronize(
      account: account,
      kind: SwapPrivateHistoryKind.swap,
    );

    expect(result.remoteWritten, isTrue);
    expect(repository.readCount, 2);
    expect(repository.createCount, 1);
    expect(repository.putCount, 1);
    final uploaded = SwapPrivateHistoryDocument.decode(
      repository.plaintext!,
      expectedKind: SwapPrivateHistoryKind.swap,
    );
    expect(uploaded.records.map((record) => record.id).toSet(), {
      'local',
      'concurrent',
    });
    expect(activityStore.records.map((record) => record.id).toSet(), {
      'local',
      'concurrent',
    });
  });

  test(
    'empty local and absent remote do not reveal account presence',
    () async {
      final repository = _MemoryRepository();
      final metadata = _MemoryMetadataStore();
      final sync = SwapPrivateHistorySync(
        repository: repository,
        replica: SwapActivityReplica(
          activityStore: _MemoryActivityStore(const []),
        ),
        metadataStore: metadata,
      );

      final result = await sync.synchronize(
        account: account,
        kind: SwapPrivateHistoryKind.pay,
      );

      expect(result.remoteWritten, isFalse);
      expect(repository.createCount, 0);
      expect(repository.lastKey?.namespace, PrivateStateNamespace.payHistory);
      expect(metadata.values.values.single.remoteVersion, isNull);
    },
  );

  test('corrupt metadata is ignored because it is only an optimization', () {
    expect(SwapPrivateHistorySyncMetadata.fromJson({'schema': 1}), isNull);
    expect(
      SwapPrivateHistorySyncMetadata.fromJson({
        'schema': 1,
        'plaintext_hash': 'hash',
        'synchronized_at': '2026-08-25T00:00:00Z',
        'remote_revision': '0',
        'remote_envelope_hash': 'envelope',
      }),
      isNull,
    );
  });
}

PrivateStateVersion _version(int revision) => PrivateStateVersion(
  revision: BigInt.from(revision),
  envelopeHashBase64: 'hash-$revision',
);

SwapIntentRecord _record(String id, {bool payMode = false}) {
  return SwapIntentRecord(
    id: id,
    providerLabel: 'NEAR Intents',
    pairText: 'ZEC -> USDC',
    sellAmountText: '1 ZEC',
    receiveEstimateText: '70 USDC',
    status: SwapIntentStatus.awaitingDeposit,
    nextAction: 'Checking status',
    sellAmountBaseUnits: BigInt.one,
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: 'deposit-$id',
    providerQuoteId: 'quote-$id',
    payMode: payMode,
    createdAt: DateTime.utc(2026, 8, 25),
    updatedAt: DateTime.utc(2026, 8, 25),
  );
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

class _MemoryMetadataStore implements SwapPrivateHistorySyncMetadataStore {
  final Map<String, SwapPrivateHistorySyncMetadata> values = {};

  String _key(String accountUuid, SwapPrivateHistoryKind kind) =>
      '$accountUuid:${kind.wireName}';

  @override
  Future<SwapPrivateHistorySyncMetadata?> load({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
  }) async => values[_key(accountUuid, kind)];

  @override
  Future<void> save({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
    required SwapPrivateHistorySyncMetadata metadata,
  }) async {
    values[_key(accountUuid, kind)] = metadata;
  }

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {
    values.removeWhere((key, _) => key.startsWith('$accountUuid:'));
  }
}

class _MemoryRepository implements PrivateStateObjectRepository {
  _MemoryRepository({this.plaintext, this.version});

  Uint8List? plaintext;
  PrivateStateVersion? version;
  Uint8List? _conflictPlaintext;
  int readCount = 0;
  int createCount = 0;
  int putCount = 0;
  PrivateStateObjectKey? lastKey;

  void conflictFirstWriteWith(Uint8List value) {
    _conflictPlaintext = value;
  }

  @override
  Future<PrivateStateReadResult> read({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  }) async {
    readCount++;
    lastKey = key;
    final current = plaintext;
    final currentVersion = version;
    if (current == null || currentVersion == null) {
      return const PrivateStateReadAbsent();
    }
    return PrivateStateReadFound(
      plaintext: Uint8List.fromList(current),
      version: currentVersion,
    );
  }

  @override
  Future<PrivateStateWriteResult> create({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required Uint8List plaintext,
  }) async {
    createCount++;
    lastKey = key;
    final conflict = _conflictPlaintext;
    if (conflict != null) {
      _conflictPlaintext = null;
      this.plaintext = Uint8List.fromList(conflict);
      version = _version(2);
      return const PrivateStateWriteConflict();
    }
    if (this.plaintext != null) return const PrivateStateWriteConflict();
    this.plaintext = Uint8List.fromList(plaintext);
    version = _version(1);
    return PrivateStateWriteStored(version!);
  }

  @override
  Future<PrivateStateWriteResult> compareAndSet({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required PrivateStateVersion currentVersion,
    required Uint8List plaintext,
  }) async {
    putCount++;
    lastKey = key;
    if (version?.revision != currentVersion.revision ||
        version?.envelopeHashBase64 != currentVersion.envelopeHashBase64) {
      return const PrivateStateWriteConflict();
    }
    final next = currentVersion.revision.toInt() + 1;
    this.plaintext = Uint8List.fromList(plaintext);
    version = _version(next);
    return PrivateStateWriteStored(version!);
  }
}
