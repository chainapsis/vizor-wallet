import 'dart:convert';
import 'dart:io' show HttpHeaders;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;

import '../config/private_state_sync_config.dart';
import '../network/network_http_client.dart';
import '../network/tor_runtime_support.dart';
import '../storage/wallet_paths.dart';
import '../../rust/api/network_privacy.dart' as rust_network_privacy;
import 'private_state_models.dart';
import 'private_state_remote_store.dart';

abstract interface class PrivateStateHttpTransport {
  Future<NetworkHttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String> headers,
    List<int> bodyBytes,
    Duration? timeout,
  });
}

class PrivateStateSyncDisabledException implements Exception {
  const PrivateStateSyncDisabledException();

  @override
  String toString() => 'Private state sync is disabled.';
}

class GatedPrivateStateHttpTransport implements PrivateStateHttpTransport {
  const GatedPrivateStateHttpTransport({
    required PrivateStateHttpTransport delegate,
    required bool Function() canStartRequest,
  }) : _delegate = delegate,
       _canStartRequest = canStartRequest;

  final PrivateStateHttpTransport _delegate;
  final bool Function() _canStartRequest;

  @override
  Future<NetworkHttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int> bodyBytes = const [],
    Duration? timeout,
  }) {
    if (!_canStartRequest()) {
      return Future.error(const PrivateStateSyncDisabledException());
    }
    return _delegate.request(
      method,
      uri,
      headers: headers,
      bodyBytes: bodyBytes,
      timeout: timeout,
    );
  }
}

class NetworkPrivateStateHttpTransport implements PrivateStateHttpTransport {
  NetworkPrivateStateHttpTransport({NetworkHttpClient? client})
    : _client = client ?? NetworkHttpClient();

  final NetworkHttpClient _client;

  @override
  Future<NetworkHttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int> bodyBytes = const [],
    Duration? timeout,
  }) {
    return _client.request(
      method,
      uri,
      headers: headers,
      bodyBytes: bodyBytes,
      timeout: timeout,
      followRedirects: false,
    );
  }

  void close({bool force = false}) => _client.close(force: force);
}

class DebugDirectPrivateStateHttpTransport
    extends NetworkPrivateStateHttpTransport {
  DebugDirectPrivateStateHttpTransport({NetworkHttpClient? client})
    : super(client: _requireDebugClient(client));

  static NetworkHttpClient _requireDebugClient(NetworkHttpClient? client) {
    if (!kDebugMode) {
      throw StateError(
        'Debug-direct private-state HTTP is unavailable in this build.',
      );
    }
    return client ?? NetworkHttpClient.debugDirect();
  }
}

abstract interface class PrivateStateTorRuntime {
  Future<void> ensureReady();
}

class RustPrivateStateTorRuntime implements PrivateStateTorRuntime {
  const RustPrivateStateTorRuntime({
    this.resolveTorDirectory = getTorDataDirectoryPath,
    this.excludeTorDirectoryFromBackup = excludeTorDirectoryFromDeviceBackup,
    this.ensureRuntime = rust_network_privacy.ensurePrivateStateTor,
  });

  final Future<String> Function() resolveTorDirectory;
  final Future<void> Function(String directory) excludeTorDirectoryFromBackup;
  final Future<void> Function({required String torDirectory}) ensureRuntime;

  @override
  Future<void> ensureReady() async {
    final directory = await resolveTorDirectory();
    await _markDirectory(directory);
    try {
      await ensureRuntime(torDirectory: directory);
    } finally {
      await _markDirectory(directory);
    }
  }

  Future<void> _markDirectory(String directory) async {
    try {
      await excludeTorDirectoryFromBackup(directory);
    } catch (_) {
      // A backup exclusion failure must not weaken or replace the Tor route.
    }
  }
}

class _RequiredTorHttpBridge implements TorHttpBridge {
  const _RequiredTorHttpBridge({
    required PrivateStateTorRuntime runtime,
    TorHttpBridge delegate = const RustPrivateStateTorHttpBridge(),
  }) : _runtime = runtime,
       _delegate = delegate;

  final PrivateStateTorRuntime _runtime;
  final TorHttpBridge _delegate;

  @override
  Future<NetworkHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    await _runtime.ensureReady();
    return _delegate.get(uri, headers: headers);
  }

  @override
  Future<NetworkHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
  }) async {
    await _runtime.ensureReady();
    return _delegate.post(uri, headers: headers, bodyBytes: bodyBytes);
  }

  @override
  Future<NetworkHttpResponse> download(
    Uri uri, {
    required Map<String, String> headers,
    required String destinationPath,
  }) {
    throw const TorUnsupportedHttpMethodException('DOWNLOAD');
  }
}

class RustPrivateStateTorHttpBridge implements TorHttpBridge {
  const RustPrivateStateTorHttpBridge();

  @override
  Future<NetworkHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    final response = await rust_network_privacy.privateStateTorHttpGet(
      url: uri.toString(),
      headers: networkHttpHeadersToRust(headers),
    );
    return networkHttpResponseFromRust(response);
  }

  @override
  Future<NetworkHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
  }) async {
    final response = await rust_network_privacy.privateStateTorHttpPost(
      url: uri.toString(),
      headers: networkHttpHeadersToRust(headers),
      body: bodyBytes,
    );
    return networkHttpResponseFromRust(response);
  }

  @override
  Future<NetworkHttpResponse> download(
    Uri uri, {
    required Map<String, String> headers,
    required String destinationPath,
  }) {
    throw const TorUnsupportedHttpMethodException('DOWNLOAD');
  }
}

class TorRequiredPrivateStateHttpTransport
    extends NetworkPrivateStateHttpTransport {
  TorRequiredPrivateStateHttpTransport({
    PrivateStateTorRuntime runtime = const RustPrivateStateTorRuntime(),
    TorHttpBridge torBridge = const RustPrivateStateTorHttpBridge(),
  }) : super(
         client: NetworkHttpClient(
           torDesired: _alwaysUseTor,
           torBridge: _RequiredTorHttpBridge(
             runtime: runtime,
             delegate: torBridge,
           ),
         ),
       );

  static bool _alwaysUseTor() => true;
}

NetworkPrivateStateHttpTransport privateStateHttpTransportForBuild() {
  return switch (privateStateTransportModeForBuild()) {
    PrivateStateTransportMode.debugDirect =>
      DebugDirectPrivateStateHttpTransport(),
    PrivateStateTransportMode.torRequired =>
      TorRequiredPrivateStateHttpTransport(),
  };
}

class PrivateStateHttpStatusException implements Exception {
  const PrivateStateHttpStatusException(this.operation, this.statusCode);

  final String operation;
  final int statusCode;

  bool get isRetryable => statusCode == 429 || statusCode >= 500;

  @override
  String toString() =>
      'PrivateStateHttpStatusException: $operation returned HTTP $statusCode';
}

class HttpPrivateStateRemoteStore implements PrivateStateRemoteStore {
  HttpPrivateStateRemoteStore({
    required Uri baseUri,
    required PrivateStateHttpTransport transport,
    String? signingAudience,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUri = baseUri,
       _audience = signingAudience ?? baseUri.toString(),
       _transport = transport;

  static const _maximumObjectResponseBytes = 384 * 1024;

  final Uri _baseUri;
  final String _audience;
  final PrivateStateHttpTransport _transport;
  final Duration timeout;

  @override
  String get audience => _audience;

  @override
  Future<PrivateStateRemoteReadResult> get({
    required PrivateStateObjectReference object,
    required PrivateStateRequestAuthorization authorization,
  }) async {
    _requireAuthorizationMatches(
      object,
      authorization,
      PrivateStateRequestMethod.get,
    );
    final response = await _transport.request(
      'GET',
      _objectUri(object.objectId),
      headers: _authorizationHeaders(authorization),
      timeout: timeout,
    );
    _throwClockSkew(response);
    if (response.statusCode == 404) return const PrivateStateRemoteAbsent();
    if (response.statusCode != 200) {
      throw PrivateStateHttpStatusException('get object', response.statusCode);
    }
    return PrivateStateRemoteFound(
      _decodeEnvelope(response.bodyBytes, expectedObject: object),
    );
  }

  @override
  Future<PrivateStateRemoteCreateResult> create({
    required PrivateStateObjectReference object,
    required PrivateStateEnvelope envelope,
    required PrivateStateRequestAuthorization authorization,
  }) async {
    _requireAuthorizationMatches(
      object,
      authorization,
      PrivateStateRequestMethod.put,
    );
    if (envelope.protocolVersion != object.protocolVersion ||
        envelope.objectId != object.objectId ||
        envelope.authPublicKeyBase64 != object.authPublicKeyBase64) {
      throw const PrivateStateProtocolException(
        'PUT envelope does not match its object or authorization.',
      );
    }
    final response = await _transport.request(
      // The server aliases this POST to the signed PUT operation so writes can
      // use the app's fail-closed Tor transport without weakening signatures.
      'POST',
      _objectUri(object.objectId, suffix: 'put'),
      headers: {..._jsonHeaders, ..._authorizationHeaders(authorization)},
      bodyBytes: _jsonBytes(_envelopeJson(envelope)),
      timeout: timeout,
    );
    _throwClockSkew(response);
    if (response.statusCode == 204) return const PrivateStateRemoteCreated();
    if (response.statusCode == 409) return const PrivateStateRemoteConflict();
    throw PrivateStateHttpStatusException('put object', response.statusCode);
  }

  Uri _objectUri(String objectId, {String? suffix}) {
    return _baseUri.replace(
      pathSegments: [
        ..._baseUri.pathSegments.where((segment) => segment.isNotEmpty),
        'objects',
        objectId,
        ?suffix,
      ],
    );
  }

  Map<String, String> _authorizationHeaders(
    PrivateStateRequestAuthorization authorization,
  ) {
    return {
      HttpHeaders.acceptHeader: 'application/json',
      'x-vizor-protocol-version': authorization.protocolVersion.toString(),
      'x-vizor-auth-public-key': authorization.authPublicKeyBase64,
      'x-vizor-nonce': authorization.nonceBase64,
      'x-vizor-audience': authorization.audience,
      'x-vizor-expires-at':
          (authorization.expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000)
              .toString(),
      'x-vizor-content-hash': authorization.contentHashBase64,
      'x-vizor-signature': authorization.signatureBase64,
    };
  }

  void _throwClockSkew(NetworkHttpResponse response) {
    if (response.statusCode != 401 ||
        response.header('x-vizor-auth-error') != 'clock-skew') {
      return;
    }
    final rawServerTime = response.header('x-vizor-server-time');
    final seconds = rawServerTime == null ? null : int.tryParse(rawServerTime);
    if (seconds == null || seconds <= 0) {
      throw const PrivateStateProtocolException(
        'Remote store returned an invalid clock-skew response.',
      );
    }
    try {
      throw PrivateStateClockSkewException(
        DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
      );
    } on RangeError {
      throw const PrivateStateProtocolException(
        'Remote store returned an invalid server time.',
      );
    }
  }

  void _requireAuthorizationMatches(
    PrivateStateObjectReference object,
    PrivateStateRequestAuthorization authorization,
    PrivateStateRequestMethod method,
  ) {
    if (authorization.protocolVersion != object.protocolVersion ||
        authorization.objectId != object.objectId ||
        authorization.authPublicKeyBase64 != object.authPublicKeyBase64 ||
        authorization.method != method ||
        authorization.audience != audience) {
      throw const PrivateStateProtocolException(
        'Authorization does not match the HTTP request.',
      );
    }
  }

  PrivateStateEnvelope _decodeEnvelope(
    Uint8List bytes, {
    required PrivateStateObjectReference expectedObject,
  }) {
    final body = _decodeJsonObject(
      bytes,
      maximumBytes: _maximumObjectResponseBytes,
    );
    _requireOnlyKeys(body, const {
      'protocol_version',
      'object_id',
      'auth_public_key_base64',
      'nonce_base64',
      'ciphertext_base64',
      'signature_base64',
    });
    if (body['protocol_version'] != expectedObject.protocolVersion ||
        body['object_id'] != expectedObject.objectId ||
        body['auth_public_key_base64'] != expectedObject.authPublicKeyBase64) {
      throw const PrivateStateProtocolException(
        'Remote store returned an invalid object envelope.',
      );
    }
    final nonce = _requiredString(body, 'nonce_base64');
    final ciphertext = _requiredString(body, 'ciphertext_base64');
    final signature = _requiredString(body, 'signature_base64');
    return PrivateStateEnvelope(
      protocolVersion: expectedObject.protocolVersion,
      objectId: expectedObject.objectId,
      authPublicKeyBase64: expectedObject.authPublicKeyBase64,
      nonceBase64: nonce,
      ciphertextBase64: ciphertext,
      signatureBase64: signature,
    );
  }

  Map<String, Object?> _envelopeJson(PrivateStateEnvelope envelope) {
    return {
      'protocol_version': envelope.protocolVersion,
      'object_id': envelope.objectId,
      'auth_public_key_base64': envelope.authPublicKeyBase64,
      'nonce_base64': envelope.nonceBase64,
      'ciphertext_base64': envelope.ciphertextBase64,
      'signature_base64': envelope.signatureBase64,
    };
  }

  Map<String, dynamic> _decodeJsonObject(
    Uint8List bytes, {
    required int maximumBytes,
  }) {
    if (bytes.length > maximumBytes) {
      throw const PrivateStateProtocolException(
        'Remote private-state response exceeds the protocol limit.',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on Object {
      throw const PrivateStateProtocolException(
        'Remote private-state response is not valid UTF-8 JSON.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const PrivateStateProtocolException(
        'Remote private-state response is not a JSON object.',
      );
    }
    return decoded;
  }

  void _requireOnlyKeys(Map<String, dynamic> body, Set<String> allowed) {
    if (body.keys.any((key) => !allowed.contains(key)) ||
        body.length != allowed.length) {
      throw const PrivateStateProtocolException(
        'Remote private-state response has an unexpected shape.',
      );
    }
  }

  String _requiredString(Map<String, dynamic> body, String key) {
    final value = body[key];
    if (value is! String || value.isEmpty) {
      throw const PrivateStateProtocolException(
        'Remote private-state response contains an invalid string.',
      );
    }
    return value;
  }

  static const _jsonHeaders = {
    HttpHeaders.acceptHeader: 'application/json',
    HttpHeaders.contentTypeHeader: 'application/json',
  };

  List<int> _jsonBytes(Map<String, Object?> body) =>
      utf8.encode(jsonEncode(body));
}
