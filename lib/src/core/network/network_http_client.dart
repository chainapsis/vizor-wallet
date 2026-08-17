import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../rust/api/network_privacy.dart' as rust_network_privacy;

class NetworkHttpResponse {
  const NetworkHttpResponse({
    required this.statusCode,
    required this.bodyBytes,
    this.headers = const {},
  });

  final int statusCode;
  final Uint8List bodyBytes;
  final Map<String, List<String>> headers;

  String? header(String name) {
    final values = headers[name.toLowerCase()];
    return values == null || values.isEmpty ? null : values.first;
  }
}

class TorUnsupportedHttpMethodException implements Exception {
  const TorUnsupportedHttpMethodException(this.method);

  final String method;

  @override
  String toString() =>
      'The $method request was blocked because the embedded Tor transport '
      'does not support this method.';
}

class DirectNetworkRequestsBlockedException implements Exception {
  const DirectNetworkRequestsBlockedException();

  @override
  String toString() =>
      'Direct network requests are blocked while the app switches to Tor.';
}

abstract interface class TorHttpBridge {
  Future<NetworkHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  });

  Future<NetworkHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
  });

  Future<NetworkHttpResponse> download(
    Uri uri, {
    required Map<String, String> headers,
    required String destinationPath,
  });
}

class RustTorHttpBridge implements TorHttpBridge {
  const RustTorHttpBridge();

  @override
  Future<NetworkHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    final response = await rust_network_privacy.torHttpGet(
      url: uri.toString(),
      headers: _rustHeaders(headers),
    );
    return networkHttpResponseFromRust(response);
  }

  @override
  Future<NetworkHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
  }) async {
    final response = await rust_network_privacy.torHttpPost(
      url: uri.toString(),
      headers: _rustHeaders(headers),
      body: bodyBytes,
    );
    return networkHttpResponseFromRust(response);
  }

  @override
  Future<NetworkHttpResponse> download(
    Uri uri, {
    required Map<String, String> headers,
    required String destinationPath,
  }) async {
    final response = await rust_network_privacy.torHttpDownload(
      url: uri.toString(),
      headers: _rustHeaders(headers),
      destinationPath: destinationPath,
    );
    return networkHttpResponseFromRust(response);
  }

  static List<rust_network_privacy.NetworkHttpHeader> _rustHeaders(
    Map<String, String> headers,
  ) => [
    for (final entry in headers.entries)
      rust_network_privacy.NetworkHttpHeader(
        name: entry.key,
        value: entry.value,
      ),
  ];
}

/// Converts the generated Rust response while preserving the concrete nested
/// generic types. Leaving either collection inferred through `unmodifiable`
/// produces `Map<dynamic, dynamic>` / `List<dynamic>` at runtime and breaks
/// every successful Tor HTTP response when it is read as typed headers.
NetworkHttpResponse networkHttpResponseFromRust(
  rust_network_privacy.NetworkHttpResponse response,
) {
  final headers = <String, List<String>>{};
  for (final header in response.headers) {
    (headers[header.name.toLowerCase()] ??= <String>[]).add(header.value);
  }
  final immutableHeaders = <String, List<String>>{
    for (final entry in headers.entries)
      entry.key: List<String>.unmodifiable(entry.value),
  };
  return NetworkHttpResponse(
    statusCode: response.statusCode,
    bodyBytes: response.body,
    headers: Map<String, List<String>>.unmodifiable(immutableHeaders),
  );
}

/// Routes app-owned HTTP traffic through the process-wide network privacy
/// policy. Tor mode never falls back to [HttpClient] when Tor is unavailable.
class NetworkHttpClient {
  NetworkHttpClient({
    HttpClient? directClient,
    bool Function()? torDesired,
    TorHttpBridge? torBridge,
  }) : _directClient = directClient ?? HttpClient(),
       _torDesired = torDesired ?? rust_network_privacy.isTorEnabled,
       _torBridge = torBridge ?? const RustTorHttpBridge() {
    _instances.add(this);
  }

  static final Set<NetworkHttpClient> _instances = {};
  static bool _directRequestsBlocked = false;

  HttpClient _directClient;
  final bool Function() _torDesired;
  final TorHttpBridge _torBridge;
  var _activeDirectRequests = 0;
  var _directClientNeedsReset = false;
  var _closed = false;
  Completer<void>? _directRequestsDrained;

  /// Prevents new direct HTTP work, force-closes every app-owned direct
  /// client, and waits until the interrupted operations have unwound.
  static Future<void> quiesceDirectRequests() async {
    _directRequestsBlocked = true;
    await Future.wait([
      for (final client in List<NetworkHttpClient>.of(_instances))
        client._quiesceDirectRequests(),
    ]);
  }

  /// Reopens direct HTTP routing only after Rust has confirmed the route
  /// switch away from Tor.
  static void allowDirectRequests() {
    for (final client in List<NetworkHttpClient>.of(_instances)) {
      client._resetDirectClientAfterQuiesce();
    }
    _directRequestsBlocked = false;
  }

  Future<NetworkHttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int> bodyBytes = const [],
    Duration? timeout,
  }) {
    final future = _torDesired()
        ? _requestViaTorWithRedirects(
            method.toUpperCase(),
            uri,
            headers: headers,
            bodyBytes: bodyBytes,
          )
        : _runDirectRequest(
            () => _requestDirect(
              method.toUpperCase(),
              uri,
              headers: headers,
              bodyBytes: bodyBytes,
            ),
          );
    return timeout == null ? future : future.timeout(timeout);
  }

  /// Streams a GET response to [destination] without retaining the response
  /// body in Dart memory. Tor mode performs the file write inside Rust so large
  /// downloads do not cross the FFI boundary as a whole-body byte array.
  Future<NetworkHttpResponse> downloadToFile(
    Uri uri,
    File destination, {
    Map<String, String> headers = const {},
    Duration? timeout,
  }) {
    final future = _torDesired()
        ? _requestViaTorWithRedirects(
            'GET',
            uri,
            headers: headers,
            bodyBytes: const [],
            destinationPath: destination.path,
          )
        : _runDirectRequest(
            () => _downloadDirect(uri, destination, headers: headers),
          );
    return timeout == null ? future : future.timeout(timeout);
  }

  void close({bool force = false}) {
    if (_closed) return;
    _closed = true;
    _directClient.close(force: force);
    if (_activeDirectRequests == 0) _instances.remove(this);
  }

  Future<T> _runDirectRequest<T>(Future<T> Function() request) async {
    if (_directRequestsBlocked || _closed) {
      throw const DirectNetworkRequestsBlockedException();
    }
    _activeDirectRequests++;
    try {
      return await request();
    } finally {
      _activeDirectRequests--;
      if (_activeDirectRequests == 0) {
        _directRequestsDrained?.complete();
        _directRequestsDrained = null;
        if (_closed) _instances.remove(this);
      }
    }
  }

  Future<void> _quiesceDirectRequests() {
    _directClient.close(force: true);
    if (!_closed) _directClientNeedsReset = true;
    if (_activeDirectRequests == 0) return Future.value();
    return (_directRequestsDrained ??= Completer<void>()).future;
  }

  void _resetDirectClientAfterQuiesce() {
    if (_closed || !_directClientNeedsReset) return;
    _directClient = HttpClient();
    _directClientNeedsReset = false;
  }

  Future<NetworkHttpResponse> _requestViaTorWithRedirects(
    String method,
    Uri initialUri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
    String? destinationPath,
  }) async {
    if (method != 'GET' && method != 'POST') {
      throw TorUnsupportedHttpMethodException(method);
    }

    var currentMethod = method;
    var currentUri = initialUri;
    var currentHeaders = Map<String, String>.of(headers);
    var currentBody = bodyBytes;
    for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
      final response = destinationPath != null
          ? await _torBridge.download(
              currentUri,
              headers: currentHeaders,
              destinationPath: destinationPath,
            )
          : currentMethod == 'GET'
          ? await _torBridge.get(currentUri, headers: currentHeaders)
          : await _torBridge.post(
              currentUri,
              headers: currentHeaders,
              bodyBytes: currentBody,
            );
      final location = response.header(HttpHeaders.locationHeader);
      if (!_isRedirect(response.statusCode) || location == null) {
        return response;
      }
      if (redirectCount == 5) {
        throw const HttpException('Too many HTTP redirects');
      }
      final nextUri = currentUri.resolve(location);
      if (currentUri.scheme == 'https' && nextUri.scheme != 'https') {
        throw HttpException(
          'Refusing HTTPS redirect to ${nextUri.scheme}',
          uri: nextUri,
        );
      }
      currentHeaders = _headersForRedirect(currentUri, nextUri, currentHeaders);
      if (currentMethod == 'POST' &&
          (response.statusCode == HttpStatus.movedPermanently ||
              response.statusCode == HttpStatus.found ||
              response.statusCode == HttpStatus.seeOther)) {
        currentMethod = 'GET';
        currentBody = const [];
      }
      currentUri = nextUri;
    }
    throw const HttpException('Too many HTTP redirects');
  }

  Future<NetworkHttpResponse> _requestDirect(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
  }) async {
    final request = await _directClient.openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (bodyBytes.isNotEmpty) request.add(bodyBytes);
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    final responseHeaders = <String, List<String>>{};
    response.headers.forEach((name, values) {
      responseHeaders[name.toLowerCase()] = List.unmodifiable(values);
    });
    return NetworkHttpResponse(
      statusCode: response.statusCode,
      bodyBytes: Uint8List.fromList(bytes),
      headers: Map.unmodifiable(responseHeaders),
    );
  }

  Future<NetworkHttpResponse> _downloadDirect(
    Uri uri,
    File destination, {
    required Map<String, String> headers,
  }) async {
    final request = await _directClient.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close();
    await response.pipe(destination.openWrite());
    final responseHeaders = <String, List<String>>{};
    response.headers.forEach((name, values) {
      responseHeaders[name.toLowerCase()] = List.unmodifiable(values);
    });
    return NetworkHttpResponse(
      statusCode: response.statusCode,
      bodyBytes: Uint8List(0),
      headers: Map.unmodifiable(responseHeaders),
    );
  }

  static Map<String, String> _headersForRedirect(
    Uri from,
    Uri to,
    Map<String, String> headers,
  ) {
    if (_sameOrigin(from, to)) return headers;
    const sensitive = {
      HttpHeaders.authorizationHeader,
      HttpHeaders.cookieHeader,
      HttpHeaders.proxyAuthorizationHeader,
    };
    return {
      for (final entry in headers.entries)
        if (!sensitive.contains(entry.key.toLowerCase()))
          entry.key: entry.value,
    };
  }

  static bool _sameOrigin(Uri left, Uri right) =>
      left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
      left.host.toLowerCase() == right.host.toLowerCase() &&
      left.port == right.port;

  static bool _isRedirect(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;
}
