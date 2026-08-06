import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/network/network_http_client.dart';
import 'package:zcash_wallet/src/rust/api/network_privacy.dart'
    as rust_network_privacy;

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

  test('Rust Tor responses preserve typed repeated headers', () {
    final response = networkHttpResponseFromRust(
      rust_network_privacy.NetworkHttpResponse(
        statusCode: 200,
        headers: const [
          rust_network_privacy.NetworkHttpHeader(
            name: 'Content-Type',
            value: 'application/json',
          ),
          rust_network_privacy.NetworkHttpHeader(
            name: 'Set-Cookie',
            value: 'a=1',
          ),
          rust_network_privacy.NetworkHttpHeader(
            name: 'Set-Cookie',
            value: 'b=2',
          ),
        ],
        body: Uint8List.fromList([1, 2, 3]),
      ),
    );

    expect(response.headers, {
      'content-type': ['application/json'],
      'set-cookie': ['a=1', 'b=2'],
    });
    expect(response.headers['content-type'], isA<List<String>>());
    expect(response.bodyBytes, [1, 2, 3]);
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

  test('cross-origin redirects strip credentials', () async {
    final bridge = _RecordingTorBridge([
      NetworkHttpResponse(
        statusCode: 302,
        bodyBytes: utf8.encode(''),
        headers: const {
          'location': ['https://cdn.example.net/final'],
        },
      ),
      NetworkHttpResponse(statusCode: 200, bodyBytes: utf8.encode('done')),
    ]);
    final client = NetworkHttpClient(torDesired: () => true, torBridge: bridge);
    addTearDown(() => client.close());

    await client.request(
      'GET',
      Uri.parse('https://api.example.com/start'),
      headers: const {
        HttpHeaders.authorizationHeader: 'Bearer secret',
        HttpHeaders.cookieHeader: 'session=secret',
        HttpHeaders.acceptHeader: 'application/json',
      },
    );

    expect(bridge.requests[1].headers, {
      HttpHeaders.acceptHeader: 'application/json',
    });
  });

  test('Tor redirects reject HTTPS to HTTP downgrade', () async {
    final bridge = _RecordingTorBridge([
      NetworkHttpResponse(
        statusCode: 302,
        bodyBytes: utf8.encode(''),
        headers: const {
          'location': ['http://example.com/final'],
        },
      ),
    ]);
    final client = NetworkHttpClient(torDesired: () => true, torBridge: bridge);
    addTearDown(() => client.close());

    await expectLater(
      client.request('GET', Uri.parse('https://example.com/start')),
      throwsA(isA<HttpException>()),
    );
  });

  test('Tor preserves POST across 307 redirects', () async {
    final bridge = _RecordingTorBridge([
      NetworkHttpResponse(
        statusCode: 307,
        bodyBytes: utf8.encode(''),
        headers: const {
          'location': ['/final'],
        },
      ),
      NetworkHttpResponse(statusCode: 200, bodyBytes: utf8.encode('done')),
    ]);
    final client = NetworkHttpClient(torDesired: () => true, torBridge: bridge);
    addTearDown(() => client.close());

    await client.request(
      'POST',
      Uri.parse('https://example.com/start'),
      bodyBytes: utf8.encode('payload'),
    );

    expect(bridge.requests.map((request) => request.method), ['POST', 'POST']);
    expect(bridge.requests[1].bodyBytes, utf8.encode('payload'));
  });

  test('Tor downloads stream to the requested file', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'vizor-network-http-client-',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final destination = File('${tempDirectory.path}/params.bin');
    final bridge = _RecordingTorBridge([
      NetworkHttpResponse(
        statusCode: 200,
        bodyBytes: Uint8List.fromList([0, 1, 2, 3]),
      ),
    ]);
    final client = NetworkHttpClient(torDesired: () => true, torBridge: bridge);
    addTearDown(() => client.close());

    final response = await client.downloadToFile(
      Uri.parse('https://example.com/params.bin'),
      destination,
    );

    expect(response.statusCode, 200);
    expect(response.bodyBytes, isEmpty);
    expect(await destination.readAsBytes(), [0, 1, 2, 3]);
  });

  test(
    'Tor activation drains in-flight direct requests after client disposal',
    () async {
      final requestReceived = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        if (!requestReceived.isCompleted) requestReceived.complete();
      });
      final client = NetworkHttpClient(torDesired: () => false);
      final blockedClient = NetworkHttpClient(torDesired: () => false);
      addTearDown(() async {
        NetworkHttpClient.allowDirectRequests();
        client.close(force: true);
        blockedClient.close(force: true);
        await server.close(force: true);
      });

      final pendingRequest = client.request(
        'GET',
        Uri(
          scheme: 'http',
          host: InternetAddress.loopbackIPv4.address,
          port: server.port,
          path: '/stalled',
        ),
      );
      final pendingExpectation = expectLater(pendingRequest, throwsA(anything));
      await requestReceived.future;
      client.close();

      await NetworkHttpClient.quiesceDirectRequests().timeout(
        const Duration(seconds: 2),
      );

      await pendingExpectation;
      await expectLater(
        blockedClient.request('GET', Uri.parse('https://example.com/new')),
        throwsA(isA<DirectNetworkRequestsBlockedException>()),
      );
    },
  );
}

class _RecordingTorBridge implements TorHttpBridge {
  _RecordingTorBridge(this.responses);

  final List<NetworkHttpResponse> responses;
  final requests = <_RecordedRequest>[];

  @override
  Future<NetworkHttpResponse> download(
    Uri uri, {
    required Map<String, String> headers,
    required String destinationPath,
  }) async {
    final response = responses[requests.length];
    requests.add(
      _RecordedRequest(
        method: 'GET',
        url: uri.toString(),
        headers: Map.of(headers),
      ),
    );
    await File(destinationPath).writeAsBytes(response.bodyBytes);
    return NetworkHttpResponse(
      statusCode: response.statusCode,
      bodyBytes: Uint8List(0),
      headers: response.headers,
    );
  }

  @override
  Future<NetworkHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    requests.add(
      _RecordedRequest(
        method: 'GET',
        url: uri.toString(),
        headers: Map.of(headers),
      ),
    );
    return responses[requests.length - 1];
  }

  @override
  Future<NetworkHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
  }) async {
    requests.add(
      _RecordedRequest(
        method: 'POST',
        url: uri.toString(),
        headers: Map.of(headers),
        bodyBytes: List.of(bodyBytes),
      ),
    );
    return responses[requests.length - 1];
  }
}

class _FailingTorBridge implements TorHttpBridge {
  const _FailingTorBridge();

  @override
  Future<NetworkHttpResponse> download(
    Uri uri, {
    required Map<String, String> headers,
    required String destinationPath,
  }) => throw StateError('Tor is not ready');

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
  const _RecordedRequest({
    required this.method,
    required this.url,
    this.headers = const {},
    this.bodyBytes = const [],
  });

  final String method;
  final String url;
  final Map<String, String> headers;
  final List<int> bodyBytes;

  @override
  bool operator ==(Object other) =>
      other is _RecordedRequest && method == other.method && url == other.url;

  @override
  int get hashCode => Object.hash(method, url);
}
