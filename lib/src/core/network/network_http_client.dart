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
    return _fromRust(response);
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
    return _fromRust(response);
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

  static NetworkHttpResponse _fromRust(
    rust_network_privacy.NetworkHttpResponse response,
  ) {
    final headers = <String, List<String>>{};
    for (final header in response.headers) {
      (headers[header.name.toLowerCase()] ??= []).add(header.value);
    }
    return NetworkHttpResponse(
      statusCode: response.statusCode,
      bodyBytes: response.body,
      headers: Map.unmodifiable({
        for (final entry in headers.entries)
          entry.key: List.unmodifiable(entry.value),
      }),
    );
  }
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
       _torBridge = torBridge ?? const RustTorHttpBridge();

  final HttpClient _directClient;
  final bool Function() _torDesired;
  final TorHttpBridge _torBridge;

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
        : _requestDirect(
            method.toUpperCase(),
            uri,
            headers: headers,
            bodyBytes: bodyBytes,
          );
    return timeout == null ? future : future.timeout(timeout);
  }

  void close({bool force = false}) => _directClient.close(force: force);

  Future<NetworkHttpResponse> _requestViaTorWithRedirects(
    String method,
    Uri initialUri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
  }) async {
    if (method != 'GET' && method != 'POST') {
      throw TorUnsupportedHttpMethodException(method);
    }

    var uri = initialUri;
    for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
      final response = method == 'GET'
          ? await _torBridge.get(uri, headers: headers)
          : await _torBridge.post(uri, headers: headers, bodyBytes: bodyBytes);
      final location = response.header(HttpHeaders.locationHeader);
      if (method != 'GET' ||
          !_isRedirect(response.statusCode) ||
          location == null) {
        return response;
      }
      if (redirectCount == 5) {
        throw const HttpException('Too many HTTP redirects');
      }
      uri = uri.resolve(location);
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

  static bool _isRedirect(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;
}
