import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/private_state_sync/in_memory_private_state_remote_store.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_crypto.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_models.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_object_repository.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_server_verifier.dart';
import 'package:zcash_wallet/src/features/voting/voting_private_state_sync.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/private_state/swap_private_history_document.dart';
import 'package:zcash_wallet/src/features/swap/private_state/swap_private_history_sync.dart';
import 'package:zcash_wallet/src/features/swap/private_state/swap_private_history_sync_metadata.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_replica.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';

void main() {
  final now = DateTime.utc(2026, 8, 24, 12);
  late _FakeServerVerifier verifier;
  late InMemoryPrivateStateRemoteStore remote;
  late DefaultPrivateStateObjectRepository desktopRepository;
  late DefaultPrivateStateObjectRepository mobileRepository;

  setUp(() {
    verifier = _FakeServerVerifier();
    remote = InMemoryPrivateStateRemoteStore(
      audience: 'https://sync.vizor.example/v1',
      verifier: verifier,
      now: () => now,
    );
    desktopRepository = DefaultPrivateStateObjectRepository(
      crypto: const _FakeCrypto(),
      remote: remote,
      now: () => now,
    );
    mobileRepository = DefaultPrivateStateObjectRepository(
      crypto: const _FakeCrypto(),
      remote: remote,
      now: () => now,
    );
  });

  test(
    'desktop completion is recovered by a separately identified mobile',
    () async {
      final desktop = VotingPrivateStateSync(desktopRepository);
      final mobile = VotingPrivateStateSync(mobileRepository);
      final published = VotingCompletionRecord(
        roundId: 'round-42',
        completedAtSeconds: 1_724_000_000,
        choicesByProposalId: {7: 1, 8: null},
      );

      await desktop.publishCompletion(
        account: const PrivateStateAccount(
          dbPath: '/desktop/wallet.db',
          network: 'main',
          accountUuid: 'desktop-local-uuid',
        ),
        record: published,
      );
      final recovered = await mobile.readCompletion(
        account: const PrivateStateAccount(
          dbPath: '/mobile/wallet.db',
          network: 'main',
          accountUuid: 'mobile-local-uuid',
        ),
        roundId: 'round-42',
      );

      expect(recovered?.roundId, 'round-42');
      expect(recovered?.completedAtSeconds, 1_724_000_000);
      expect(recovered?.choicesByProposalId, {7: 1, 8: null});
      expect(verifier.putCalls, 1);
    },
  );

  test(
    'finalized activity and voting completion converge across devices',
    () async {
      const desktopAccount = PrivateStateAccount(
        dbPath: '/desktop/wallet.db',
        network: 'main',
        accountUuid: 'desktop-local-uuid',
      );
      const mobileAccount = PrivateStateAccount(
        dbPath: '/mobile/wallet.db',
        network: 'main',
        accountUuid: 'mobile-local-uuid',
      );
      final desktopStore = _MemoryActivityStore([
        _swapRecord('swap-1'),
        _swapRecord('pay-1', payMode: true),
      ]);
      final mobileStore = _MemoryActivityStore(const []);
      final desktopSync = FinalizedActivityArchiveSync(
        repository: desktopRepository,
        replica: SwapActivityReplica(activityStore: desktopStore),
        metadataStore: _MemoryMetadataStore(),
      );
      final mobileMetadata = _MemoryMetadataStore();
      final mobileSync = FinalizedActivityArchiveSync(
        repository: mobileRepository,
        replica: SwapActivityReplica(activityStore: mobileStore),
        metadataStore: mobileMetadata,
      );

      await desktopSync.synchronize(
        account: desktopAccount,
        kind: SwapPrivateHistoryKind.swap,
      );
      await mobileSync.synchronize(
        account: mobileAccount,
        kind: SwapPrivateHistoryKind.swap,
      );
      await desktopSync.synchronize(
        account: desktopAccount,
        kind: SwapPrivateHistoryKind.pay,
      );
      await mobileSync.synchronize(
        account: mobileAccount,
        kind: SwapPrivateHistoryKind.pay,
      );
      expect(mobileStore.records.map((record) => record.id).toSet(), {
        'swap-1',
        'pay-1',
      });

      await mobileSync.recordLocalDeletions(
        accountUuid: mobileAccount.accountUuid,
        records: mobileStore.records.where((record) => record.id == 'swap-1'),
      );
      mobileStore.records = mobileStore.records
          .where((record) => record.id != 'swap-1')
          .toList();
      await mobileSync.synchronize(
        account: mobileAccount,
        kind: SwapPrivateHistoryKind.swap,
      );
      await desktopSync.synchronize(
        account: desktopAccount,
        kind: SwapPrivateHistoryKind.swap,
      );
      expect(desktopStore.records.map((record) => record.id).toSet(), {
        'swap-1',
        'pay-1',
      });

      final desktopVoting = VotingPrivateStateSync(desktopRepository);
      final mobileVoting = VotingPrivateStateSync(mobileRepository);
      await desktopVoting.publishCompletion(
        account: desktopAccount,
        record: VotingCompletionRecord(
          roundId: 'round-99',
          completedAtSeconds: 1_724_000_100,
          choicesByProposalId: const {7: 1},
        ),
      );
      final completion = await mobileVoting.readCompletion(
        account: mobileAccount,
        roundId: 'round-99',
      );
      expect(completion?.choicesByProposalId, {7: 1});
    },
  );

  test('challenge is single-use even for repeated authorized reads', () async {
    final challenge = await remote.createChallenge(object: _reference);
    final authorization = _authorization(
      challenge: challenge,
      method: PrivateStateRequestMethod.get,
    );

    expect(
      await remote.get(object: _reference, authorization: authorization),
      isA<PrivateStateRemoteAbsent>(),
    );
    await expectLater(
      remote.get(object: _reference, authorization: authorization),
      throwsA(isA<PrivateStateProtocolException>()),
    );
  });

  test('a second create cannot replace an existing object', () async {
    const account = PrivateStateAccount(
      dbPath: '/wallet.db',
      network: 'main',
      accountUuid: 'local-id',
    );
    const key = PrivateStateObjectKey(
      namespace: PrivateStateNamespace.votingCompletion,
      itemKey: 'round-v1:round-42',
    );
    await desktopRepository.create(
      account: account,
      key: key,
      plaintext: Uint8List.fromList([1]),
    );
    expect(
      await mobileRepository.create(
        account: account,
        key: key,
        plaintext: Uint8List.fromList([3]),
      ),
      isA<PrivateStateCreateConflict>(),
    );
    final finalRead =
        await desktopRepository.read(account: account, key: key)
            as PrivateStateReadFound;
    expect(finalRead.plaintext, [1]);
  });

  test('authorization cannot be moved to another object', () async {
    final challenge = await remote.createChallenge(object: _reference);
    final authorization = _authorization(
      challenge: challenge,
      method: PrivateStateRequestMethod.get,
    );
    const other = PrivateStateObjectReference(
      protocolVersion: 1,
      objectId: 'other-object',
      authPublicKeyBase64: 'other-key',
    );

    await expectLater(
      remote.get(object: other, authorization: authorization),
      throwsA(isA<PrivateStateProtocolException>()),
    );
  });

  test('invalid self-certifying reference is rejected before allocation', () {
    const invalid = PrivateStateObjectReference(
      protocolVersion: 1,
      objectId: 'unrelated-object-id',
      authPublicKeyBase64: 'unrelated-public-key',
    );

    expect(
      remote.createChallenge(object: invalid),
      throwsA(isA<PrivateStateProtocolException>()),
    );
  });

  test('challenge lifetime must survive whole-second normalization', () {
    expect(
      () => InMemoryPrivateStateRemoteStore(
        audience: 'https://sync.vizor.example/v1',
        verifier: verifier,
        challengeLifetime: const Duration(milliseconds: 999),
      ),
      throwsArgumentError,
    );
  });
}

const _reference = PrivateStateObjectReference(
  protocolVersion: 1,
  objectId: 'shared-object',
  authPublicKeyBase64: 'shared-public-key',
);

PrivateStateRequestAuthorization _authorization({
  required PrivateStateServerChallenge challenge,
  required PrivateStateRequestMethod method,
  String contentHashBase64 = '47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU',
}) {
  return PrivateStateRequestAuthorization(
    protocolVersion: 1,
    objectId: _reference.objectId,
    authPublicKeyBase64: _reference.authPublicKeyBase64,
    method: method,
    challengeBase64: challenge.valueBase64,
    audience: 'https://sync.vizor.example/v1',
    expiresAt: challenge.expiresAt,
    contentHashBase64: contentHashBase64,
    signatureBase64: 'request-signature',
  );
}

class _FakeCrypto implements PrivateStateCrypto {
  const _FakeCrypto();

  @override
  Future<PrivateStateRequestAuthorization> authorize({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required PrivateStateRequestMethod method,
    required PrivateStateServerChallenge challenge,
    required String audience,
    PrivateStateEnvelope? envelope,
  }) async {
    final reference = _referenceForKey(key);
    return PrivateStateRequestAuthorization(
      protocolVersion: 1,
      objectId: reference.objectId,
      authPublicKeyBase64: reference.authPublicKeyBase64,
      method: method,
      challengeBase64: challenge.valueBase64,
      audience: audience,
      expiresAt: challenge.expiresAt,
      contentHashBase64: envelope == null
          ? '47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU'
          : 'signed-envelope-content-hash',
      signatureBase64: 'request-signature',
    );
  }

  @override
  Future<PrivateStateObjectReference> deriveObjectReference({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  }) async => _referenceForKey(key);

  @override
  Future<Uint8List> open({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required PrivateStateEnvelope envelope,
  }) async => Uint8List.fromList(
    base64Url.decode(base64Url.normalize(envelope.ciphertextBase64)),
  );

  @override
  Future<PrivateStateEnvelope> seal({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required Uint8List plaintext,
  }) async {
    final reference = _referenceForKey(key);
    final ciphertext = base64Url.encode(plaintext).replaceAll('=', '');
    return PrivateStateEnvelope(
      protocolVersion: 1,
      objectId: reference.objectId,
      authPublicKeyBase64: reference.authPublicKeyBase64,
      nonceBase64: 'nonce',
      ciphertextBase64: ciphertext,
      signatureBase64: 'envelope-signature',
    );
  }
}

class _FakeServerVerifier implements PrivateStateServerVerifier {
  int putCalls = 0;

  @override
  Future<void> verifyObjectReference(PrivateStateObjectReference object) async {
    if (object != _reference &&
        (!object.objectId.startsWith('shared-object:') ||
            !object.authPublicKeyBase64.startsWith('shared-key:'))) {
      throw const PrivateStateProtocolException('Invalid object reference.');
    }
  }

  @override
  Future<void> verifyAuthorization(
    PrivateStateRequestAuthorization authorization,
  ) async {
    if (authorization.signatureBase64 != 'request-signature') {
      throw const PrivateStateProtocolException('Invalid request signature.');
    }
  }

  @override
  Future<void> verifyPutContent({
    required PrivateStateEnvelope envelope,
    required PrivateStateRequestAuthorization authorization,
  }) async {
    putCalls++;
    if (authorization.contentHashBase64 != 'signed-envelope-content-hash' ||
        envelope.signatureBase64 != 'envelope-signature') {
      throw const PrivateStateProtocolException('Invalid signed envelope.');
    }
  }
}

PrivateStateObjectReference _referenceForKey(PrivateStateObjectKey key) {
  final suffix = '${key.namespace.wireName}:${key.itemKey}';
  return PrivateStateObjectReference(
    protocolVersion: 1,
    objectId: 'shared-object:$suffix',
    authPublicKeyBase64: 'shared-key:$suffix',
  );
}

SwapIntentRecord _swapRecord(String id, {bool payMode = false}) {
  return SwapIntentRecord(
    id: id,
    providerLabel: 'NEAR Intents',
    pairText: 'ZEC -> USDC',
    sellAmountText: '1 ZEC',
    receiveEstimateText: '70 USDC',
    status: SwapIntentStatus.complete,
    nextAction: 'Completed',
    sellAmountBaseUnits: BigInt.one,
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: 'deposit-$id',
    providerQuoteId: 'quote-$id',
    payMode: payMode,
    createdAt: DateTime.utc(2026, 8, 24),
    updatedAt: DateTime.utc(2026, 8, 24),
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

class _MemoryMetadataStore implements FinalizedActivityArchiveMetadataStore {
  final Map<String, FinalizedActivityArchiveMetadata> values = {};

  String _key(String accountUuid, SwapPrivateHistoryKind kind) =>
      '$accountUuid:${kind.wireName}';

  @override
  Future<void> hideRecords({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
    required Iterable<String> recordIds,
  }) async {
    final key = _key(accountUuid, kind);
    final current = values[key];
    values[key] = FinalizedActivityArchiveMetadata(
      lastSlot: current?.lastSlot ?? 0,
      hiddenRecordIds: {...?current?.hiddenRecordIds, ...recordIds},
    );
  }

  @override
  Future<FinalizedActivityArchiveMetadata?> load({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
  }) async => values[_key(accountUuid, kind)];

  @override
  Future<void> save({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
    required FinalizedActivityArchiveMetadata metadata,
  }) async {
    final key = _key(accountUuid, kind);
    final current = values[key];
    values[key] = FinalizedActivityArchiveMetadata(
      lastSlot: metadata.lastSlot,
      hiddenRecordIds: {
        ...?current?.hiddenRecordIds,
        ...metadata.hiddenRecordIds,
      },
    );
  }

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {
    values.removeWhere((key, _) => key.startsWith('$accountUuid:'));
  }
}
