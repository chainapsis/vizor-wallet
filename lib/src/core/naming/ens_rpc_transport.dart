import 'dart:convert';
import 'dart:io';

/// Transport abstraction for ENS resolution: Ethereum JSON-RPC `eth_call`
/// plus CCIP-Read (EIP-3668) offchain gateway fetches.
abstract interface class EnsRpcTransport {
  /// eth_call to [to] with [data] (both 0x-hex). Returns 0x-hex result.
  /// Throws [EnsRpcException] carrying any JSON-RPC `error.data` revert hex.
  Future<String> ethCall({required String to, required String data});

  /// CCIP-Read gateway fetch (EIP-3668): GET/POST templated [url].
  Future<String> ccipFetch({
    required String url,
    required String sender,
    required String data,
  });
}

class EnsRpcException implements Exception {
  const EnsRpcException(this.message, {this.revertData});

  final String message;

  /// 0x-hex revert payload when the node returns one.
  final String? revertData;

  @override
  String toString() => 'EnsRpcException: $message';
}

/// Default public Ethereum mainnet JSON-RPC endpoints, tried in order until
/// one succeeds.
const List<String> defaultEnsRpcEndpoints = [
  'https://eth.llamarpc.com',
  'https://ethereum-rpc.publicnode.com',
  'https://cloudflare-eth.com',
];

const _rpcTimeout = Duration(seconds: 15);

/// `dart:io` `HttpClient`-based [EnsRpcTransport].
///
/// [postJson] and [fetchCcip] are injectable seams so tests never touch the
/// real network; both default to real `dart:io` HTTP implementations.
class HttpEnsRpcTransport implements EnsRpcTransport {
  HttpEnsRpcTransport({
    List<String> endpoints = defaultEnsRpcEndpoints,
    Future<String> Function(Uri uri, String body)? postJson,
    Future<String> Function(String method, Uri uri, String? body)? fetchCcip,
  })  : _endpoints = endpoints,
        _postJson = postJson ?? _defaultPostJson,
        _fetchCcip = fetchCcip ?? _defaultFetchCcip;

  final List<String> _endpoints;
  final Future<String> Function(Uri uri, String body) _postJson;
  final Future<String> Function(String method, Uri uri, String? body)
  _fetchCcip;

  @override
  Future<String> ethCall({required String to, required String data}) async {
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'eth_call',
      'params': [
        {'to': to, 'data': data},
        'latest',
      ],
    });

    Object? lastError;
    for (final endpoint in _endpoints) {
      final String responseBody;
      try {
        responseBody = await _postJson(Uri.parse(endpoint), body);
      } catch (e) {
        lastError = e;
        continue;
      }

      final Object? decoded;
      try {
        decoded = jsonDecode(responseBody);
      } on FormatException catch (e) {
        lastError = e;
        continue;
      }
      if (decoded is! Map<String, dynamic>) {
        lastError = EnsRpcException(
          'Unexpected JSON-RPC response shape from $endpoint',
        );
        continue;
      }

      final error = decoded['error'];
      if (error != null) {
        if (error is Map<String, dynamic>) {
          final message = error['message'];
          final errorData = error['data'];
          throw EnsRpcException(
            message is String ? message : 'JSON-RPC error',
            revertData: errorData is String ? errorData : null,
          );
        }
        throw EnsRpcException('JSON-RPC error: $error');
      }

      final result = decoded['result'];
      if (result is String) {
        return result;
      }

      lastError = EnsRpcException(
        'JSON-RPC response from $endpoint missing result',
      );
    }

    throw EnsRpcException(
      'All ENS RPC endpoints failed: $lastError',
    );
  }

  @override
  Future<String> ccipFetch({
    required String url,
    required String sender,
    required String data,
  }) async {
    final resolvedUrl = url
        .replaceAll('{sender}', sender)
        .replaceAll('{data}', data);
    final uri = Uri.parse(resolvedUrl);

    final String responseBody;
    if (url.contains('{data}')) {
      responseBody = await _fetchCcip('GET', uri, null);
    } else {
      final body = jsonEncode({'sender': sender, 'data': data});
      responseBody = await _fetchCcip('POST', uri, body);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(responseBody);
    } on FormatException catch (e) {
      throw EnsRpcException(
        'CCIP-Read gateway response was not valid JSON: $e',
      );
    }
    if (decoded is Map<String, dynamic>) {
      final result = decoded['data'];
      if (result is String) {
        return result;
      }
    }
    throw const EnsRpcException('CCIP-Read gateway response missing data');
  }
}

Future<String> _defaultPostJson(Uri uri, String body) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri).timeout(_rpcTimeout);
    request.headers.contentType = ContentType.json;
    request.write(body);

    final response = await request.close().timeout(_rpcTimeout);
    return await utf8.decoder.bind(response).join();
  } finally {
    client.close(force: true);
  }
}

Future<String> _defaultFetchCcip(
  String method,
  Uri uri,
  String? body,
) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, uri).timeout(_rpcTimeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(body);
    }

    final response = await request.close().timeout(_rpcTimeout);
    return await utf8.decoder.bind(response).join();
  } finally {
    client.close(force: true);
  }
}
