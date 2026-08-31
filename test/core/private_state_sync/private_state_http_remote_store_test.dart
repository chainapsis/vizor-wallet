import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/network/network_http_client.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_http_remote_store.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_models.dart';

void main() {
  late _FakeTransport transport;
  late HttpPrivateStateRemoteStore store;

  setUp(() {
    transport = _FakeTransport();
    store = HttpPrivateStateRemoteStore(
      baseUri: Uri.parse(_audience),
      transport: transport,
    );
  });

  test('supports a signing audience distinct from transport', () {
    final aliasedStore = HttpPrivateStateRemoteStore(
      baseUri: Uri.parse('http://10.0.2.2:3000/api/private-state/v1'),
      signingAudience: _audience,
      transport: _FakeTransport(),
    );

    expect(aliasedStore.audience, _audience);
  });

  test('authenticated GET maps absence and parses an envelope', () async {
    transport.responses
      ..add(NetworkHttpResponse(statusCode: 404, bodyBytes: Uint8List(0)))
      ..add(_jsonResponse(200, _envelopeJson));

    expect(
      await store.get(object: _object, authorization: _getAuthorization),
      isA<PrivateStateRemoteAbsent>(),
    );
    final found = await store.get(
      object: _object,
      authorization: _getAuthorization,
    );

    expect(found, isA<PrivateStateRemoteFound>());
    final envelope = (found as PrivateStateRemoteFound).envelope;
    expect(envelope.ciphertextBase64, 'ciphertext');
    expect(transport.requests.last.headers['x-vizor-signature'], _signature);
    expect(transport.requests.last.headers['x-vizor-nonce'], _nonce);
  });

  test('rejects obsolete mutable-envelope fields', () async {
    transport.responses.add(
      _jsonResponse(200, {..._envelopeJson, 'revision': 1}),
    );

    await expectLater(
      store.get(object: _object, authorization: _getAuthorization),
      throwsA(isA<PrivateStateProtocolException>()),
    );
  });

  test(
    'write uses POST alias while preserving signed PUT authorization',
    () async {
      transport.responses.add(
        NetworkHttpResponse(statusCode: 204, bodyBytes: Uint8List(0)),
      );

      final result = await store.create(
        object: _object,
        envelope: _envelope,
        authorization: _putAuthorization,
      );

      expect(result, isA<PrivateStateRemoteCreated>());
      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/private-state/v1/objects/$_objectId/put');
      expect(jsonDecode(utf8.decode(request.bodyBytes)), _envelopeJson);
    },
  );

  test('write maps create conflict and classifies retryable status', () async {
    transport.responses
      ..add(NetworkHttpResponse(statusCode: 409, bodyBytes: Uint8List(0)))
      ..add(NetworkHttpResponse(statusCode: 503, bodyBytes: Uint8List(0)));

    expect(
      await store.create(
        object: _object,
        envelope: _envelope,
        authorization: _putAuthorization,
      ),
      isA<PrivateStateRemoteConflict>(),
    );
    await expectLater(
      store.get(object: _object, authorization: _getAuthorization),
      throwsA(
        isA<PrivateStateHttpStatusException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having((error) => error.isRetryable, 'isRetryable', true),
      ),
    );
  });

  test('rejects mismatched authorization before network access', () async {
    final wrong = PrivateStateRequestAuthorization(
      protocolVersion: 1,
      objectId: _objectId,
      authPublicKeyBase64: _publicKey,
      method: PrivateStateRequestMethod.get,
      nonceBase64: _nonce,
      audience: 'https://other.example/v1',
      expiresAt: _expiry,
      contentHashBase64: _emptyHash,
      signatureBase64: _signature,
    );

    await expectLater(
      store.get(object: _object, authorization: wrong),
      throwsA(isA<PrivateStateProtocolException>()),
    );
    expect(transport.requests, isEmpty);
  });

  test('maps a server clock response to a clock-skew exception', () async {
    transport.responses.add(
      NetworkHttpResponse(
        statusCode: 401,
        headers: const {
          'x-vizor-auth-error': ['clock-skew'],
          'x-vizor-server-time': ['1790000000'],
        },
        bodyBytes: Uint8List(0),
      ),
    );

    await expectLater(
      store.get(object: _object, authorization: _getAuthorization),
      throwsA(
        isA<PrivateStateClockSkewException>().having(
          (error) => error.serverTime.millisecondsSinceEpoch,
          'serverTime',
          1790000000000,
        ),
      ),
    );
  });
}

class _FakeTransport implements PrivateStateHttpTransport {
  final responses = <NetworkHttpResponse>[];
  final requests = <_RecordedRequest>[];

  @override
  Future<NetworkHttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int> bodyBytes = const [],
    Duration? timeout,
  }) async {
    requests.add(
      _RecordedRequest(
        method: method,
        uri: uri,
        headers: Map.unmodifiable(headers),
        bodyBytes: List.unmodifiable(bodyBytes),
      ),
    );
    return responses.removeAt(0);
  }
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.bodyBytes,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int> bodyBytes;
}

NetworkHttpResponse _jsonResponse(int statusCode, Map<String, Object?> body) {
  return NetworkHttpResponse(
    statusCode: statusCode,
    bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(body))),
  );
}

const _audience = 'https://functions.vizor.cash/api/private-state/v1';
const _objectId = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _publicKey = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
const _nonce = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
const _signature =
    'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD';
const _emptyHash = '47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU';
final _expiry = DateTime.fromMillisecondsSinceEpoch(1790000060000, isUtc: true);

const _object = PrivateStateObjectReference(
  protocolVersion: 1,
  objectId: _objectId,
  authPublicKeyBase64: _publicKey,
);

final _getAuthorization = PrivateStateRequestAuthorization(
  protocolVersion: 1,
  objectId: _objectId,
  authPublicKeyBase64: _publicKey,
  method: PrivateStateRequestMethod.get,
  nonceBase64: _nonce,
  audience: _audience,
  expiresAt: _expiry,
  contentHashBase64: _emptyHash,
  signatureBase64: _signature,
);

final _putAuthorization = PrivateStateRequestAuthorization(
  protocolVersion: 1,
  objectId: _objectId,
  authPublicKeyBase64: _publicKey,
  method: PrivateStateRequestMethod.put,
  nonceBase64: _nonce,
  audience: _audience,
  expiresAt: _expiry,
  contentHashBase64: 'envelope-hash',
  signatureBase64: _signature,
);

final _envelope = PrivateStateEnvelope(
  protocolVersion: 1,
  objectId: _objectId,
  authPublicKeyBase64: _publicKey,
  nonceBase64: 'nonce',
  ciphertextBase64: 'ciphertext',
  signatureBase64: 'envelope-signature',
);

const _envelopeJson = <String, Object?>{
  'protocol_version': 1,
  'object_id': _objectId,
  'auth_public_key_base64': _publicKey,
  'nonce_base64': 'nonce',
  'ciphertext_base64': 'ciphertext',
  'signature_base64': 'envelope-signature',
};
