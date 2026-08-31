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
    final remote = _FakeRemoteStore(now: now);
    final repository = DefaultPrivateStateObjectRepository(
      crypto: crypto,
      remote: remote,
      now: () => now,
    );

    expect(
      await repository.read(account: account, key: key),
      isA<PrivateStateReadAbsent>(),
    );
    expect(crypto.authorizations.single.method, PrivateStateRequestMethod.get);
    expect(crypto.authorizations.single.envelope, isNull);
    expect(crypto.openCalls, 0);
  });

  test('authenticated read decrypts a found envelope', () async {
    final crypto = _FakeCrypto();
    final remote = _FakeRemoteStore(now: now)
      ..nextRead = const PrivateStateRemoteFound(_envelope);
    final repository = DefaultPrivateStateObjectRepository(
      crypto: crypto,
      remote: remote,
      now: () => now,
    );

    final found =
        await repository.read(account: account, key: key)
            as PrivateStateReadFound;

    expect(utf8.decode(found.plaintext), 'verified plaintext');
    expect(crypto.openCalls, 1);
  });

  test('create signs and submits exactly the sealed envelope', () async {
    final crypto = _FakeCrypto();
    final remote = _FakeRemoteStore(now: now);
    final repository = DefaultPrivateStateObjectRepository(
      crypto: crypto,
      remote: remote,
      now: () => now,
    );

    expect(
      await repository.create(
        account: account,
        key: key,
        plaintext: Uint8List.fromList(utf8.encode('document')),
      ),
      isA<PrivateStateCreated>(),
    );
    expect(crypto.authorizations.single.envelope, same(_envelope));
    expect(remote.createCalls.single, same(_envelope));
  });

  test(
    'existing object conflict is returned without a read or merge',
    () async {
      final remote = _FakeRemoteStore(now: now)
        ..nextCreate = const PrivateStateRemoteConflict();
      final repository = DefaultPrivateStateObjectRepository(
        crypto: _FakeCrypto(),
        remote: remote,
        now: () => now,
      );

      expect(
        await repository.create(
          account: account,
          key: key,
          plaintext: Uint8List(0),
        ),
        isA<PrivateStateCreateConflict>(),
      );
      expect(remote.getCalls, 0);
    },
  );

  test('server clock skew retries once with a fresh authorization', () async {
    final crypto = _FakeCrypto();
    final serverNow = now.add(const Duration(hours: 3));
    final remote = _FakeRemoteStore(now: serverNow)..clockSkewFailures = 1;
    final repository = DefaultPrivateStateObjectRepository(
      crypto: crypto,
      remote: remote,
      now: () => now,
    );

    expect(
      await repository.read(account: account, key: key),
      isA<PrivateStateReadAbsent>(),
    );
    expect(remote.getCalls, 2);
    expect(crypto.authorizations, hasLength(2));
    expect(
      crypto.authorizations.first.nonceBase64,
      isNot(crypto.authorizations.last.nonceBase64),
    );
    expect(
      crypto.authorizations.last.expiresAt,
      serverNow.add(DefaultPrivateStateObjectRepository.authorizationLifetime),
    );
  });

  test('server clock skew is retried no more than once', () async {
    final serverNow = now.add(const Duration(hours: 3));
    final remote = _FakeRemoteStore(now: serverNow)..clockSkewFailures = 2;
    final repository = DefaultPrivateStateObjectRepository(
      crypto: _FakeCrypto(),
      remote: remote,
      now: () => now,
    );

    await expectLater(
      repository.read(account: account, key: key),
      throwsA(isA<PrivateStateClockSkewException>()),
    );
    expect(remote.getCalls, 2);
  });

  test('authorization uses the short client lifetime', () async {
    final crypto = _FakeCrypto();
    final remote = _FakeRemoteStore(now: now);
    final repository = DefaultPrivateStateObjectRepository(
      crypto: crypto,
      remote: remote,
      now: () => now,
    );

    await repository.read(account: account, key: key);

    expect(
      crypto.authorizations.single.expiresAt,
      now.add(DefaultPrivateStateObjectRepository.authorizationLifetime),
    );
  });
}

const _reference = PrivateStateObjectReference(
  protocolVersion: 1,
  objectId: 'object-id',
  authPublicKeyBase64: 'public-key',
);

const _envelope = PrivateStateEnvelope(
  protocolVersion: 1,
  objectId: 'object-id',
  authPublicKeyBase64: 'public-key',
  nonceBase64: 'nonce',
  ciphertextBase64: 'ciphertext',
  signatureBase64: 'signature',
);

class _AuthorizationCall {
  const _AuthorizationCall({
    required this.method,
    required this.nonceBase64,
    required this.expiresAt,
    required this.envelope,
  });

  final PrivateStateRequestMethod method;
  final String nonceBase64;
  final DateTime expiresAt;
  final PrivateStateEnvelope? envelope;
}

class _FakeCrypto implements PrivateStateCrypto {
  int openCalls = 0;
  final List<_AuthorizationCall> authorizations = [];

  @override
  Future<PrivateStateRequestAuthorization> authorize({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required PrivateStateRequestMethod method,
    required String audience,
    required DateTime expiresAt,
    PrivateStateEnvelope? envelope,
  }) async {
    final nonceBase64 = 'request-nonce-${authorizations.length + 1}';
    authorizations.add(
      _AuthorizationCall(
        method: method,
        nonceBase64: nonceBase64,
        expiresAt: expiresAt,
        envelope: envelope,
      ),
    );
    return PrivateStateRequestAuthorization(
      protocolVersion: 1,
      objectId: _reference.objectId,
      authPublicKeyBase64: _reference.authPublicKeyBase64,
      method: method,
      nonceBase64: nonceBase64,
      audience: audience,
      expiresAt: expiresAt,
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
  }) async => _reference;

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
    required Uint8List plaintext,
  }) async => _envelope;
}

class _FakeRemoteStore implements PrivateStateRemoteStore {
  _FakeRemoteStore({required this.now});

  final DateTime now;
  int clockSkewFailures = 0;
  PrivateStateRemoteReadResult nextRead = const PrivateStateRemoteAbsent();
  PrivateStateRemoteCreateResult nextCreate = const PrivateStateRemoteCreated();
  int getCalls = 0;
  final List<PrivateStateEnvelope> createCalls = [];

  @override
  String get audience => 'https://sync.vizor.example/v1';

  @override
  Future<PrivateStateRemoteReadResult> get({
    required PrivateStateObjectReference object,
    required PrivateStateRequestAuthorization authorization,
  }) async {
    getCalls++;
    if (clockSkewFailures > 0) {
      clockSkewFailures--;
      throw PrivateStateClockSkewException(now);
    }
    return nextRead;
  }

  @override
  Future<PrivateStateRemoteCreateResult> create({
    required PrivateStateObjectReference object,
    required PrivateStateEnvelope envelope,
    required PrivateStateRequestAuthorization authorization,
  }) async {
    createCalls.add(envelope);
    return nextCreate;
  }
}
