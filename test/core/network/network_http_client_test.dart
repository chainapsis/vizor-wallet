import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/network/network_http_client.dart';

void main() {
  test('Tor mode routes GET through the Rust bridge', () async {
    final bridge = _RecordingTorBridge([
      NetworkHttpResponse(
        statusCode: 200,
        bodyBytes: utf8.encode('through tor'),
      ),
    ]);
    final client = NetworkHttpClient(torDesired: () => true, torBridge: bridge);
    addTearDown(() => client.close());

    final response = await client.request(
      'GET',
      Uri.parse('https://example.com/data'),
      headers: const {'accept': 'application/json'},
    );

    expect(utf8.decode(response.bodyBytes), 'through tor');
    expect(bridge.requests, [
      const _RecordedRequest(method: 'GET', url: 'https://example.com/data'),
    ]);
  });

  test('Tor errors do not fall back to the direct client', () async {
    final client = NetworkHttpClient(
      torDesired: () => true,
      torBridge: const _FailingTorBridge(),
    );
    addTearDown(() => client.close());

    await expectLater(
      client.request('GET', Uri.parse('https://example.com/data')),
      throwsA(isA<StateError>()),
    );
  });

  test('unsupported methods are blocked while Tor is desired', () async {
    final client = NetworkHttpClient(
      torDesired: () => true,
      torBridge: _RecordingTorBridge(const []),
    );
    addTearDown(() => client.close());

    await expectLater(
      client.request('DELETE', Uri.parse('https://example.com/package/1')),
      throwsA(isA<TorUnsupportedHttpMethodException>()),
    );
  });

  test('GET redirects stay on Tor', () async {
    final bridge = _RecordingTorBridge([
      NetworkHttpResponse(
        statusCode: 302,
        bodyBytes: utf8.encode(''),
        headers: const {
          'location': ['/final'],
        },
      ),
      NetworkHttpResponse(statusCode: 200, bodyBytes: utf8.encode('done')),
    ]);
    final client = NetworkHttpClient(torDesired: () => true, torBridge: bridge);
    addTearDown(() => client.close());

    final response = await client.request(
      'GET',
      Uri.parse('https://example.com/start'),
    );

    expect(utf8.decode(response.bodyBytes), 'done');
    expect(bridge.requests.map((request) => request.url), [
      'https://example.com/start',
      'https://example.com/final',
    ]);
  });
}

class _RecordingTorBridge implements TorHttpBridge {
  _RecordingTorBridge(this.responses);

  final List<NetworkHttpResponse> responses;
  final requests = <_RecordedRequest>[];

  @override
  Future<NetworkHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    requests.add(_RecordedRequest(method: 'GET', url: uri.toString()));
    return responses[requests.length - 1];
  }

  @override
  Future<NetworkHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
  }) async {
    requests.add(_RecordedRequest(method: 'POST', url: uri.toString()));
    return responses[requests.length - 1];
  }
}

class _FailingTorBridge implements TorHttpBridge {
  const _FailingTorBridge();

  @override
  Future<NetworkHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) => throw StateError('Tor is not ready');

  @override
  Future<NetworkHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
  }) => throw StateError('Tor is not ready');
}

class _RecordedRequest {
  const _RecordedRequest({required this.method, required this.url});

  final String method;
  final String url;

  @override
  bool operator ==(Object other) =>
      other is _RecordedRequest && method == other.method && url == other.url;

  @override
  int get hashCode => Object.hash(method, url);
}
