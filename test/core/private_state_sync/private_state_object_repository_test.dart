import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_crypto.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_models.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_object_repository.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_remote_store.dart';

void main() {
  const account = PrivateStateAccount(
    dbPath: '/wallet.db',
    network: 'main',
    accountUuid: 'local-only-account-id',
  );
  const key = PrivateStateObjectKey(
    namespace: PrivateStateNamespace.votingCompletion,
    itemKey: 'round-42',
  );
  final now = DateTime.utc(2026, 8, 24, 12);

  test('authenticated read returns absence without decrypting', () async {
    final crypto = _FakeCrypto();
    final remote = _FakeRemoteStore(now: now)
      ..nextRead = const PrivateStateRemoteAbsent();
    final repository = DefaultPrivateStateObjectRepository(
      crypto: crypto,
      remote: remote,
      now: () => now,
    );

    final result = await repository.read(account: account, key: key);

    expect(result, isA<PrivateStateReadAbsent>());
    expect(crypto.authorizations.single.method, PrivateStateRequestMethod.get);
    expect(crypto.authorizations.single.contentHashBase64, isNull);
    expect(crypto.openCalls, 0);
  });

  test('authenticated read decrypts a found envelope', () async {
    final crypto = _FakeCrypto();
    final remote = _FakeRemoteStore(now: now)
      ..nextRead = PrivateStateRemoteFound(_envelope(revision: BigInt.one));
    final repository = DefaultPrivateStateObjectRepository(
      crypto: crypto,
      remote: remote,
      now: () => now,
    );

    final result = await repository.read(account: account, key: key);

    final found = result as PrivateStateReadFound;
    expect(utf8.decode(found.plaintext), 'verified plaintext');
    expect(found.version.revision, BigInt.one);
    expect(found.version.envelopeHashBase64, 'hash-1');
    expect(crypto.openCalls, 1);
  });

  test('create uses create-if-absent and signs the envelope hash', () async {
    final crypto = _FakeCrypto();
    final remote = _FakeRemoteStore(now: now);
    final repository = DefaultPrivateStateObjectRepository(
      crypto: crypto,
      remote: remote,
      now: () => now,
    );

    final result = await repository.create(
      account: account,
      key: key,
      plaintext: Uint8List.fromList(utf8.encode('document')),
    );

    final stored = result as PrivateStateWriteStored;
    expect(stored.version.revision, BigInt.one);
    expect(remote.putCalls.single.expectedVersion, isNull);
    expect(remote.putCalls.single.envelope.previousHashBase64, isNull);
    expect(
      crypto.authorizations.single.contentHashBase64,
      remote.putCalls.single.envelope.envelopeHashBase64,
    );
  });

  test('compare-and-set chains the authenticated version', () async {
    final crypto = _FakeCrypto();
    final remote = _FakeRemoteStore(now: now);
    final repository = DefaultPrivateStateObjectRepository(
      crypto: crypto,
      remote: remote,
      now: () => now,
    );

    final result = await repository.compareAndSet(
      account: account,
      key: key,
      currentVersion: PrivateStateVersion(
        revision: BigInt.from(4),
        envelopeHashBase64: 'authenticated-hash-4',
      ),
      plaintext: Uint8List.fromList([1, 2, 3]),
    );

    expect(result, isA<PrivateStateWriteStored>());
    final put = remote.putCalls.single;
    expect(put.expectedVersion?.revision, BigInt.from(4));
    expect(put.expectedVersion?.envelopeHashBase64, 'authenticated-hash-4');
    expect(put.envelope.revision, BigInt.from(5));
    expect(put.envelope.previousHashBase64, 'authenticated-hash-4');
  });

  test('CAS conflict is returned without generic merge', () async {
    final crypto = _FakeCrypto();
    final remote = _FakeRemoteStore(now: now)
      ..nextPut = const PrivateStateRemoteConflict();
    final repository = DefaultPrivateStateObjectRepository(
      crypto: crypto,
      remote: remote,
      now: () => now,
    );

    final result = await repository.create(
      account: account,
      key: key,
      plaintext: Uint8List(0),
    );

    expect(result, isA<PrivateStateWriteConflict>());
    expect(remote.getCalls, 0);
  });

  test('expired challenge is rejected before signing', () async {
    final crypto = _FakeCrypto();
    final remote = _FakeRemoteStore(
      now: now,
      challengeExpiresAt: now.subtract(const Duration(seconds: 1)),
    );
    final repository = DefaultPrivateStateObjectRepository(
      crypto: crypto,
      remote: remote,
      now: () => now,
    );

    await expectLater(
      repository.read(account: account, key: key),
      throwsA(isA<PrivateStateProtocolException>()),
    );
    expect(crypto.authorizations, isEmpty);
  });

  test('authorization lifetime is capped independently of server', () async {
    final crypto = _FakeCrypto();
    final remote = _FakeRemoteStore(
      now: now,
      challengeExpiresAt: now.add(const Duration(days: 365)),
    );
    final repository = DefaultPrivateStateObjectRepository(
      crypto: crypto,
      remote: remote,
      now: () => now,
    );

    await repository.read(account: account, key: key);

    expect(
      crypto.authorizations.single.expiresAt,
      now.add(DefaultPrivateStateObjectRepository.maxAuthorizationLifetime),
    );
  });

  test('invalid CAS version is rejected before crypto or transport', () async {
    final crypto = _FakeCrypto();
    final remote = _FakeRemoteStore(now: now);
    final repository = DefaultPrivateStateObjectRepository(
      crypto: crypto,
      remote: remote,
      now: () => now,
    );

    expect(
      () => repository.compareAndSet(
        account: account,
        key: key,
        currentVersion: PrivateStateVersion(
          revision: BigInt.zero,
          envelopeHashBase64: '',
        ),
        plaintext: Uint8List(0),
      ),
      throwsA(isA<PrivateStateProtocolException>()),
    );
    expect(crypto.deriveCalls, 0);
    expect(remote.challengeCalls, 0);
  });

  test(
    'mismatched crypto authorization is rejected before transport',
    () async {
      final crypto = _FakeCrypto()
        ..authorizedContentHashOverride = 'wrong-content-hash';
      final remote = _FakeRemoteStore(now: now);
      final repository = DefaultPrivateStateObjectRepository(
        crypto: crypto,
        remote: remote,
        now: () => now,
      );

      await expectLater(
        repository.create(account: account, key: key, plaintext: Uint8List(0)),
        throwsA(isA<PrivateStateProtocolException>()),
      );
      expect(remote.putCalls, isEmpty);
    },
  );
}

const _reference = PrivateStateObjectReference(
  protocolVersion: 1,
  objectId: 'object-id',
  authPublicKeyBase64: 'public-key',
);

PrivateStateEnvelope _envelope({
  required BigInt revision,
  String? previousHashBase64,
}) {
  return PrivateStateEnvelope(
    protocolVersion: 1,
    objectId: _reference.objectId,
    authPublicKeyBase64: _reference.authPublicKeyBase64,
    revision: revision,
    previousHashBase64: previousHashBase64,
    nonceBase64: 'nonce',
    ciphertextBase64: 'ciphertext',
    signatureBase64: 'signature',
    envelopeHashBase64: 'hash-$revision',
  );
}

class _AuthorizationCall {
  const _AuthorizationCall({
    required this.method,
    required this.expiresAt,
    this.contentHashBase64,
  });

  final PrivateStateRequestMethod method;
  final DateTime expiresAt;
  final String? contentHashBase64;
}

class _FakeCrypto implements PrivateStateCrypto {
  int deriveCalls = 0;
  int openCalls = 0;
  String? authorizedContentHashOverride;
  final List<_AuthorizationCall> authorizations = [];

  @override
  Future<PrivateStateRequestAuthorization> authorize({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required PrivateStateRequestMethod method,
    required PrivateStateServerChallenge challenge,
    required String audience,
    String? contentHashBase64,
  }) async {
    authorizations.add(
      _AuthorizationCall(
        method: method,
        expiresAt: challenge.expiresAt,
        contentHashBase64: contentHashBase64,
      ),
    );
    return PrivateStateRequestAuthorization(
      protocolVersion: 1,
      objectId: _reference.objectId,
      authPublicKeyBase64: _reference.authPublicKeyBase64,
      method: method,
      challengeBase64: challenge.valueBase64,
      audience: audience,
      expiresAt: challenge.expiresAt,
      contentHashBase64:
          authorizedContentHashOverride ??
          contentHashBase64 ??
          '47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU',
      signatureBase64: 'request-signature',
    );
  }

  @override
  Future<PrivateStateObjectReference> deriveObjectReference({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  }) async {
    deriveCalls++;
    return _reference;
  }

  @override
  Future<Uint8List> open({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required PrivateStateEnvelope envelope,
  }) async {
    openCalls++;
    return Uint8List.fromList(utf8.encode('verified plaintext'));
  }

  @override
  Future<PrivateStateEnvelope> seal({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required BigInt revision,
    required String? previousHashBase64,
    required Uint8List plaintext,
  }) async {
    return _envelope(
      revision: revision,
      previousHashBase64: previousHashBase64,
    );
  }
}

class _PutCall {
  const _PutCall({required this.envelope, required this.expectedVersion});

  final PrivateStateEnvelope envelope;
  final PrivateStateVersion? expectedVersion;
}

class _FakeRemoteStore implements PrivateStateRemoteStore {
  _FakeRemoteStore({required this.now, DateTime? challengeExpiresAt})
    : challengeExpiresAt =
          challengeExpiresAt ?? now.add(const Duration(minutes: 2));

  final DateTime now;
  final DateTime challengeExpiresAt;
  PrivateStateRemoteReadResult nextRead = const PrivateStateRemoteAbsent();
  PrivateStateRemotePutResult nextPut = const PrivateStateRemoteStored();
  int challengeCalls = 0;
  int getCalls = 0;
  final List<_PutCall> putCalls = [];

  @override
  String get audience => 'https://sync.vizor.example/v1';

  @override
  Future<PrivateStateServerChallenge> createChallenge({
    required PrivateStateObjectReference object,
  }) async {
    challengeCalls++;
    return PrivateStateServerChallenge(
      valueBase64: 'challenge-with-at-least-16-bytes',
      expiresAt: challengeExpiresAt,
    );
  }

  @override
  Future<PrivateStateRemoteReadResult> get({
    required PrivateStateObjectReference object,
    required PrivateStateRequestAuthorization authorization,
  }) async {
    getCalls++;
    return nextRead;
  }

  @override
  Future<PrivateStateRemotePutResult> put({
    required PrivateStateObjectReference object,
    required PrivateStateEnvelope envelope,
    required PrivateStateRequestAuthorization authorization,
    required PrivateStateVersion? expectedVersion,
  }) async {
    putCalls.add(
      _PutCall(envelope: envelope, expectedVersion: expectedVersion),
    );
    return nextPut;
  }
}
