import 'dart:convert';

import '../network/network_http_client.dart';

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

/// [NetworkHttpClient]-based [EnsRpcTransport].
///
/// All default HTTP goes through the app's policy-aware [NetworkHttpClient],
/// so ENS resolution follows the Tor network-privacy route and fails closed
/// while Tor is starting or broken — a raw `HttpClient` here would leak the
/// user's IP alongside every recipient lookup on a Tor wallet.
///
/// [postJson] and [fetchCcip] are injectable seams so tests never touch the
/// real network; both default to [NetworkHttpClient]-backed implementations.
class HttpEnsRpcTransport implements EnsRpcTransport {
  HttpEnsRpcTransport({
    List<String> endpoints = defaultEnsRpcEndpoints,
    NetworkHttpClient? networkClient,
    Future<String> Function(Uri uri, String body)? postJson,
    Future<String> Function(String method, Uri uri, String? body)? fetchCcip,
  })  : _endpoints = endpoints,
        _networkClient = networkClient,
        _injectedPostJson = postJson,
        _injectedFetchCcip = fetchCcip;

  final List<String> _endpoints;
  final Future<String> Function(Uri uri, String body)? _injectedPostJson;
  final Future<String> Function(String method, Uri uri, String? body)?
  _injectedFetchCcip;

  NetworkHttpClient? _networkClient;

  /// Created lazily so tests that inject both seams never register a
  /// [NetworkHttpClient] instance with the process-wide quiesce set.
  NetworkHttpClient get _client => _networkClient ??= NetworkHttpClient();

  Future<String> Function(Uri uri, String body) get _postJson =>
      _injectedPostJson ?? _policyAwarePostJson;

  Future<String> Function(String method, Uri uri, String? body)
  get _fetchCcip => _injectedFetchCcip ?? _policyAwareFetchCcip;

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

  Future<String> _policyAwarePostJson(Uri uri, String body) async {
    final response = await _client.request(
      'POST',
      uri,
      headers: const {'content-type': 'application/json'},
      bodyBytes: utf8.encode(body),
      timeout: _rpcTimeout,
    );
    return utf8.decode(response.bodyBytes);
  }

  Future<String> _policyAwareFetchCcip(
    String method,
    Uri uri,
    String? body,
  ) async {
    final response = await _client.request(
      method,
      uri,
      headers: {
        'accept': 'application/json',
        if (body != null) 'content-type': 'application/json',
      },
      bodyBytes: body == null ? const [] : utf8.encode(body),
      timeout: _rpcTimeout,
    );
    return utf8.decode(response.bodyBytes);
  }
}
