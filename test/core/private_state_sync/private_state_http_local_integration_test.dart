@Tags(['external-service'])
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/network/network_http_client.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_http_remote_store.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_models.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_object_repository.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_remote_store.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/private_state/swap_private_history_document.dart';
import 'package:zcash_wallet/src/features/swap/private_state/swap_private_history_sync.dart';
import 'package:zcash_wallet/src/features/swap/private_state/swap_private_history_sync_metadata.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_replica.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';

const _integrationUrl = String.fromEnvironment(
  'VIZOR_PRIVATE_STATE_INTEGRATION_URL',
);
const _integrationAudience = String.fromEnvironment(
  'VIZOR_PRIVATE_STATE_INTEGRATION_AUDIENCE',
);

void main() {
  test(
    'local Lambda stores a signed write and a second client recovers it',
    () async {
      // Keep this safe even when a broad `--run-skipped` overrides the tag's
      // default skip without supplying the external service URL.
      if (_integrationUrl.isEmpty) return;

      final fixture = await _WireFixture.create();
      final writerTransport = NetworkPrivateStateHttpTransport(
        client: NetworkHttpClient(torDesired: () => false),
      );
      final writer = HttpPrivateStateRemoteStore(
        baseUri: Uri.parse(_integrationUrl),
        signingAudience: _integrationAudience.isEmpty
            ? _integrationUrl
            : _integrationAudience,
        transport: writerTransport,
      );
      addTearDown(() => writerTransport.close(force: true));

      final envelope = await fixture.envelope();
      final putChallenge = await writer.createChallenge(object: fixture.object);
      final putAuthorization = await fixture.authorization(
        method: PrivateStateRequestMethod.put,
        challenge: putChallenge,
        audience: writer.audience,
        envelope: envelope,
      );
      expect(
        await writer.create(
          object: fixture.object,
          envelope: envelope,
          authorization: putAuthorization,
        ),
        isA<PrivateStateRemoteCreated>(),
      );
      writerTransport.close(force: true);

      final readerTransport = NetworkPrivateStateHttpTransport(
        client: NetworkHttpClient(torDesired: () => false),
      );
      final reader = HttpPrivateStateRemoteStore(
        baseUri: Uri.parse(_integrationUrl),
        signingAudience: _integrationAudience.isEmpty
            ? _integrationUrl
            : _integrationAudience,
        transport: readerTransport,
      );
      addTearDown(() => readerTransport.close(force: true));
      final getChallenge = await reader.createChallenge(object: fixture.object);
      final getAuthorization = await fixture.authorization(
        method: PrivateStateRequestMethod.get,
        challenge: getChallenge,
        audience: reader.audience,
      );
      final result = await reader.get(
        object: fixture.object,
        authorization: getAuthorization,
      );

      expect(result, isA<PrivateStateRemoteFound>());
      final recovered = (result as PrivateStateRemoteFound).envelope;
      expect(recovered.signatureBase64, envelope.signatureBase64);
      expect(recovered.ciphertextBase64, envelope.ciphertextBase64);
    },
    skip: _integrationUrl.isEmpty
        ? 'Set VIZOR_PRIVATE_STATE_INTEGRATION_URL to a local Lambda server.'
        : false,
  );

  test(
    'concurrent finalized archives converge through rotating HTTP objects',
    () async {
      if (_integrationUrl.isEmpty) return;

      final transport = NetworkPrivateStateHttpTransport(
        client: NetworkHttpClient(torDesired: () => false),
      );
      addTearDown(() => transport.close(force: true));
      final remote = HttpPrivateStateRemoteStore(
        baseUri: Uri.parse(_integrationUrl),
        signingAudience: _integrationAudience.isEmpty
            ? _integrationUrl
            : _integrationAudience,
        transport: transport,
      );
      final random = Random.secure();
      final masterSeed = Uint8List.fromList(
        List<int>.generate(32, (_) => random.nextInt(256)),
      );
      final desktopRepository = _WireRepository(remote, masterSeed);
      final mobileRepository = _WireRepository(remote, masterSeed);
      final desktopStore = _MemoryActivityStore([
        _record('desktop-complete', SwapIntentStatus.complete),
        _record('desktop-failed', SwapIntentStatus.failed),
      ]);
      final mobileStore = _MemoryActivityStore([
        _record('mobile-refunded', SwapIntentStatus.refunded),
      ]);
      final desktop = FinalizedActivityArchiveSync(
        repository: desktopRepository,
        replica: SwapActivityReplica(activityStore: desktopStore),
        metadataStore: _MemoryMetadataStore(),
      );
      final mobile = FinalizedActivityArchiveSync(
        repository: mobileRepository,
        replica: SwapActivityReplica(activityStore: mobileStore),
        metadataStore: _MemoryMetadataStore(),
      );
      const desktopAccount = PrivateStateAccount(
        dbPath: '/unused.db',
        network: 'main',
        accountUuid: 'desktop-local-account-id',
      );
      const mobileAccount = PrivateStateAccount(
        dbPath: '/unused.db',
        network: 'main',
        accountUuid: 'mobile-local-account-id',
      );
      const recoveryAccount = PrivateStateAccount(
        dbPath: '/unused.db',
        network: 'main',
        accountUuid: 'reimported-local-account-id',
      );

      await Future.wait([
        desktop.synchronize(
          account: desktopAccount,
          kind: SwapPrivateHistoryKind.swap,
        ),
        mobile.synchronize(
          account: mobileAccount,
          kind: SwapPrivateHistoryKind.swap,
        ),
      ]);

      final recoveryStore = _MemoryActivityStore(const []);
      final recoveryRepository = _WireRepository(remote, masterSeed);
      final recovery = FinalizedActivityArchiveSync(
        repository: recoveryRepository,
        replica: SwapActivityReplica(activityStore: recoveryStore),
        metadataStore: _MemoryMetadataStore(),
      );
      final result = await recovery.synchronize(
        account: recoveryAccount,
        kind: SwapPrivateHistoryKind.swap,
      );

      expect(result.lastSlot, 2);
      expect(recoveryStore.records.map((record) => record.id).toSet(), {
        'desktop-complete',
        'mobile-refunded',
      });
      expect(
        recoveryStore.records.any((record) => record.id == 'desktop-failed'),
        isFalse,
      );
      final slotOne = recoveryRepository.references['archive-v1:1']!;
      final slotTwo = recoveryRepository.references['archive-v1:2']!;
      expect(slotOne.objectId, isNot(slotTwo.objectId));
      expect(slotOne.authPublicKeyBase64, isNot(slotTwo.authPublicKeyBase64));
    },
    skip: _integrationUrl.isEmpty
        ? 'Set VIZOR_PRIVATE_STATE_INTEGRATION_URL to a local Lambda server.'
        : false,
  );
}

class _WireFixture {
  _WireFixture({required this.object, required SimpleKeyPair keyPair})
    : _keyPair = keyPair;

  static const _protocolVersion = 1;
  static final _signatureAlgorithm = Ed25519();

  final PrivateStateObjectReference object;
  final SimpleKeyPair _keyPair;

  static Future<_WireFixture> create({List<int>? seed}) async {
    final random = Random.secure();
    seed ??= List<int>.generate(32, (_) => random.nextInt(256));
    final keyPair = await _signatureAlgorithm.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    final publicKeyBase64 = _encodeBase64Url(publicKey.bytes);
    final objectId = _encodeBase64Url(
      _hash([
        ...utf8.encode('Vizor private state object ID v1'),
        ...publicKey.bytes,
      ]),
    );
    return _WireFixture(
      object: PrivateStateObjectReference(
        protocolVersion: _protocolVersion,
        objectId: objectId,
        authPublicKeyBase64: publicKeyBase64,
      ),
      keyPair: keyPair,
    );
  }

  Future<PrivateStateEnvelope> envelope([Uint8List? plaintext]) async {
    final nonce = Uint8List.fromList(List<int>.filled(12, 1));
    final ciphertext = Uint8List.fromList([
      ...?plaintext,
      if (plaintext == null) ...utf8.encode('opaque-private-state-integration'),
      ...List<int>.filled(16, 7),
    ]);
    final unsigned = _concat([
      utf8.encode('Vizor private state envelope v1'),
      _u32(_protocolVersion),
      _bytes(utf8.encode(object.objectId)),
      _bytes(utf8.encode(object.authPublicKeyBase64)),
      _bytes(nonce),
      _bytes(ciphertext),
    ]);
    final signature = await _signatureAlgorithm.sign(
      unsigned,
      keyPair: _keyPair,
    );
    return PrivateStateEnvelope(
      protocolVersion: _protocolVersion,
      objectId: object.objectId,
      authPublicKeyBase64: object.authPublicKeyBase64,
      nonceBase64: _encodeBase64Url(nonce),
      ciphertextBase64: _encodeBase64Url(ciphertext),
      signatureBase64: _encodeBase64Url(signature.bytes),
    );
  }

  Uint8List open(PrivateStateEnvelope envelope) {
    final ciphertext = _decodeBase64Url(envelope.ciphertextBase64);
    return Uint8List.sublistView(ciphertext, 0, ciphertext.length - 16);
  }

  Future<PrivateStateRequestAuthorization> authorization({
    required PrivateStateRequestMethod method,
    required PrivateStateServerChallenge challenge,
    required String audience,
    PrivateStateEnvelope? envelope,
  }) async {
    final expiry = challenge.expiresAt.toUtc();
    final contentHashBase64 = envelope == null
        ? _emptyContentHash
        : _contentHash(envelope);
    final unsigned = _concat([
      utf8.encode('Vizor private state request v1'),
      _u32(_protocolVersion),
      _bytes(utf8.encode(method.wireName)),
      _bytes(utf8.encode(object.objectId)),
      _bytes(_decodeBase64Url(challenge.valueBase64)),
      _bytes(utf8.encode(audience)),
      _u64(BigInt.from(expiry.millisecondsSinceEpoch ~/ 1000)),
      _bytes(_decodeBase64Url(contentHashBase64)),
    ]);
    final signature = await _signatureAlgorithm.sign(
      unsigned,
      keyPair: _keyPair,
    );
    return PrivateStateRequestAuthorization(
      protocolVersion: _protocolVersion,
      objectId: object.objectId,
      authPublicKeyBase64: object.authPublicKeyBase64,
      method: method,
      challengeBase64: challenge.valueBase64,
      audience: audience,
      expiresAt: expiry,
      contentHashBase64: contentHashBase64,
      signatureBase64: _encodeBase64Url(signature.bytes),
    );
  }
}

class _WireRepository implements PrivateStateObjectRepository {
  _WireRepository(this._remote, this._masterSeed);

  final PrivateStateRemoteStore _remote;
  final Uint8List _masterSeed;
  final Map<String, _WireFixture> _fixtures = {};
  final Map<String, PrivateStateObjectReference> references = {};

  Future<_WireFixture> _fixture(PrivateStateObjectKey key) async {
    final scope = '${key.namespace.wireName}:${key.itemKey}';
    final existing = _fixtures[scope];
    if (existing != null) return existing;
    final seed = _hash([..._masterSeed, ...utf8.encode(scope)]);
    final created = await _WireFixture.create(seed: seed);
    _fixtures[scope] = created;
    references[key.itemKey] = created.object;
    return created;
  }

  @override
  Future<PrivateStateReadResult> read({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  }) async {
    final fixture = await _fixture(key);
    final challenge = await _remote.createChallenge(object: fixture.object);
    final authorization = await fixture.authorization(
      method: PrivateStateRequestMethod.get,
      challenge: challenge,
      audience: _remote.audience,
    );
    final result = await _remote.get(
      object: fixture.object,
      authorization: authorization,
    );
    return switch (result) {
      PrivateStateRemoteAbsent() => const PrivateStateReadAbsent(),
      PrivateStateRemoteFound(:final envelope) => PrivateStateReadFound(
        plaintext: fixture.open(envelope),
      ),
    };
  }

  @override
  Future<PrivateStateCreateResult> create({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required Uint8List plaintext,
  }) async {
    final fixture = await _fixture(key);
    final envelope = await fixture.envelope(plaintext);
    final challenge = await _remote.createChallenge(object: fixture.object);
    final authorization = await fixture.authorization(
      method: PrivateStateRequestMethod.put,
      challenge: challenge,
      audience: _remote.audience,
      envelope: envelope,
    );
    final result = await _remote.create(
      object: fixture.object,
      envelope: envelope,
      authorization: authorization,
    );
    return switch (result) {
      PrivateStateRemoteCreated() => const PrivateStateCreated(),
      PrivateStateRemoteConflict() => const PrivateStateCreateConflict(),
    };
  }
}

class _MemoryActivityStore implements SwapActivityStore {
  _MemoryActivityStore(this.records);

  List<SwapIntentRecord> records;

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {
    records = const [];
  }

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
}

class _MemoryMetadataStore implements FinalizedActivityArchiveMetadataStore {
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
    value = metadata;
  }
}

SwapIntentRecord _record(String id, SwapIntentStatus status) =>
    SwapIntentRecord(
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
      createdAt: DateTime.utc(2026, 8, 25),
      updatedAt: DateTime.utc(2026, 8, 25),
    );

final _emptyContentHash = _encodeBase64Url(_hash(const []));

String _contentHash(PrivateStateEnvelope envelope) {
  final unsigned = _concat([
    utf8.encode('Vizor private state envelope v1'),
    _u32(envelope.protocolVersion),
    _bytes(utf8.encode(envelope.objectId)),
    _bytes(utf8.encode(envelope.authPublicKeyBase64)),
    _bytes(_decodeBase64Url(envelope.nonceBase64)),
    _bytes(_decodeBase64Url(envelope.ciphertextBase64)),
  ]);
  return _encodeBase64Url(
    _hash([
      ...utf8.encode('Vizor private state envelope content hash v1'),
      ...unsigned,
      ..._decodeBase64Url(envelope.signatureBase64),
    ]),
  );
}

Uint8List _hash(List<int> value) {
  return Uint8List.fromList(sha256.convert(value).bytes);
}

String _encodeBase64Url(List<int> value) {
  return base64Url.encode(value).replaceAll('=', '');
}

Uint8List _decodeBase64Url(String value) {
  final padding = '=' * ((4 - value.length % 4) % 4);
  return Uint8List.fromList(base64Url.decode('$value$padding'));
}

Uint8List _bytes(List<int> value) => _concat([_u32(value.length), value]);

Uint8List _u32(int value) {
  return Uint8List(4)..buffer.asByteData().setUint32(0, value);
}

Uint8List _u64(BigInt value) {
  final result = Uint8List(8);
  final data = result.buffer.asByteData();
  data.setUint32(0, (value >> 32).toInt());
  data.setUint32(4, (value & BigInt.from(0xffffffff)).toInt());
  return result;
}

Uint8List _concat(List<List<int>> values) {
  final builder = BytesBuilder(copy: false);
  for (final value in values) {
    builder.add(value);
  }
  return builder.takeBytes();
}
