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

const _integrationUrl = String.fromEnvironment(
  'VIZOR_PRIVATE_STATE_INTEGRATION_URL',
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
        transport: writerTransport,
      );
      addTearDown(() => writerTransport.close(force: true));

      final envelope = await fixture.envelope();
      final putChallenge = await writer.createChallenge(object: fixture.object);
      final putAuthorization = await fixture.authorization(
        method: PrivateStateRequestMethod.put,
        challenge: putChallenge,
        audience: writer.audience,
        contentHashBase64: envelope.envelopeHashBase64,
      );
      expect(
        await writer.put(
          object: fixture.object,
          envelope: envelope,
          authorization: putAuthorization,
          expectedVersion: null,
        ),
        isA<PrivateStateRemoteStored>(),
      );
      writerTransport.close(force: true);

      final readerTransport = NetworkPrivateStateHttpTransport(
        client: NetworkHttpClient(torDesired: () => false),
      );
      final reader = HttpPrivateStateRemoteStore(
        baseUri: Uri.parse(_integrationUrl),
        transport: readerTransport,
      );
      addTearDown(() => readerTransport.close(force: true));
      final getChallenge = await reader.createChallenge(object: fixture.object);
      final getAuthorization = await fixture.authorization(
        method: PrivateStateRequestMethod.get,
        challenge: getChallenge,
        audience: reader.audience,
        contentHashBase64: _emptyContentHash,
      );
      final result = await reader.get(
        object: fixture.object,
        authorization: getAuthorization,
      );

      expect(result, isA<PrivateStateRemoteFound>());
      final recovered = (result as PrivateStateRemoteFound).envelope;
      expect(recovered.envelopeHashBase64, envelope.envelopeHashBase64);
      expect(recovered.ciphertextBase64, envelope.ciphertextBase64);
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

  static Future<_WireFixture> create() async {
    final random = Random.secure();
    final seed = List<int>.generate(32, (_) => random.nextInt(256));
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

  Future<PrivateStateEnvelope> envelope() async {
    final nonce = Uint8List.fromList(List<int>.filled(12, 1));
    final ciphertext = Uint8List.fromList([
      ...utf8.encode('opaque-private-state-integration'),
      ...List<int>.filled(16, 7),
    ]);
    final unsigned = _concat([
      utf8.encode('Vizor private state envelope v1'),
      _u32(_protocolVersion),
      _bytes(utf8.encode(object.objectId)),
      _u64(BigInt.one),
      [0],
      _bytes(utf8.encode(object.authPublicKeyBase64)),
      _bytes(nonce),
      _bytes(ciphertext),
    ]);
    final signature = await _signatureAlgorithm.sign(
      unsigned,
      keyPair: _keyPair,
    );
    final envelopeHash = _hash([
      ...utf8.encode('Vizor private state envelope hash v1'),
      ...unsigned,
      ...signature.bytes,
    ]);
    return PrivateStateEnvelope(
      protocolVersion: _protocolVersion,
      objectId: object.objectId,
      authPublicKeyBase64: object.authPublicKeyBase64,
      revision: BigInt.one,
      previousHashBase64: null,
      nonceBase64: _encodeBase64Url(nonce),
      ciphertextBase64: _encodeBase64Url(ciphertext),
      signatureBase64: _encodeBase64Url(signature.bytes),
      envelopeHashBase64: _encodeBase64Url(envelopeHash),
    );
  }

  Future<PrivateStateRequestAuthorization> authorization({
    required PrivateStateRequestMethod method,
    required PrivateStateServerChallenge challenge,
    required String audience,
    required String contentHashBase64,
  }) async {
    final expiry = challenge.expiresAt.toUtc();
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

final _emptyContentHash = _encodeBase64Url(_hash(const []));

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
