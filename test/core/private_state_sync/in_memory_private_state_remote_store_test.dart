import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/private_state_sync/in_memory_private_state_remote_store.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_crypto.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_models.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_object_repository.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_server_verifier.dart';
import 'package:zcash_wallet/src/features/voting/voting_private_state_sync.dart';

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
      expect(verifier.putTransitionCalls, 1);
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

  test('stale concurrent writer receives conflict without rollback', () async {
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
    final firstRead =
        await desktopRepository.read(account: account, key: key)
            as PrivateStateReadFound;
    final secondRead =
        await mobileRepository.read(account: account, key: key)
            as PrivateStateReadFound;

    expect(
      await desktopRepository.compareAndSet(
        account: account,
        key: key,
        currentVersion: firstRead.version,
        plaintext: Uint8List.fromList([2]),
      ),
      isA<PrivateStateWriteStored>(),
    );
    expect(
      await mobileRepository.compareAndSet(
        account: account,
        key: key,
        currentVersion: secondRead.version,
        plaintext: Uint8List.fromList([3]),
      ),
      isA<PrivateStateWriteConflict>(),
    );
    final finalRead =
        await desktopRepository.read(account: account, key: key)
            as PrivateStateReadFound;
    expect(finalRead.version.revision, BigInt.two);
    expect(finalRead.plaintext, [2]);
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
    String? contentHashBase64,
  }) async {
    return PrivateStateRequestAuthorization(
      protocolVersion: 1,
      objectId: _reference.objectId,
      authPublicKeyBase64: _reference.authPublicKeyBase64,
      method: method,
      challengeBase64: challenge.valueBase64,
      audience: audience,
      expiresAt: challenge.expiresAt,
      contentHashBase64:
          contentHashBase64 ?? '47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU',
      signatureBase64: 'request-signature',
    );
  }

  @override
  Future<PrivateStateObjectReference> deriveObjectReference({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  }) async => _reference;

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
    required BigInt revision,
    required String? previousHashBase64,
    required Uint8List plaintext,
  }) async {
    final ciphertext = base64Url.encode(plaintext).replaceAll('=', '');
    return PrivateStateEnvelope(
      protocolVersion: 1,
      objectId: _reference.objectId,
      authPublicKeyBase64: _reference.authPublicKeyBase64,
      revision: revision,
      previousHashBase64: previousHashBase64,
      nonceBase64: 'nonce-$revision',
      ciphertextBase64: ciphertext,
      signatureBase64: 'envelope-signature',
      envelopeHashBase64: 'hash-$revision-$ciphertext',
    );
  }
}

class _FakeServerVerifier implements PrivateStateServerVerifier {
  int putTransitionCalls = 0;

  @override
  Future<void> verifyObjectReference(PrivateStateObjectReference object) async {
    if (object != _reference) {
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
  Future<void> verifyPutTransition({
    required PrivateStateEnvelope envelope,
    required PrivateStateRequestAuthorization authorization,
    required PrivateStateEnvelope? current,
  }) async {
    putTransitionCalls++;
    await verifyAuthorization(authorization);
    if (authorization.contentHashBase64 != envelope.envelopeHashBase64 ||
        envelope.signatureBase64 != 'envelope-signature') {
      throw const PrivateStateProtocolException('Invalid signed envelope.');
    }
    if (current == null) {
      if (envelope.revision != BigInt.one ||
          envelope.previousHashBase64 != null) {
        throw const PrivateStateProtocolException('Invalid object creation.');
      }
      return;
    }
    if (envelope.revision != current.revision + BigInt.one ||
        envelope.previousHashBase64 != current.envelopeHashBase64) {
      throw const PrivateStateProtocolException('Invalid object successor.');
    }
  }
}
