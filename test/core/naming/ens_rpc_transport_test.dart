import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/naming/ens_rpc_transport.dart';
import 'package:zcash_wallet/src/core/network/network_http_client.dart';

void main() {
  group('HttpEnsRpcTransport.ethCall', () {
    test('returns result on success from first endpoint', () async {
      final calls = <Uri>[];
      final transport = HttpEnsRpcTransport(
        postJson: (uri, body) async {
          calls.add(uri);
          return jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'result': '0xdeadbeef',
          });
        },
      );

      final result = await transport.ethCall(to: '0xabc', data: '0x123');

      expect(result, '0xdeadbeef');
      expect(calls, hasLength(1));
      expect(calls.single, Uri.parse('https://eth.llamarpc.com'));
    });

    test(
      'sends jsonrpc eth_call body with to/data params and latest block',
      () async {
        String? capturedBody;
        final transport = HttpEnsRpcTransport(
          postJson: (uri, body) async {
            capturedBody = body;
            return jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x01'});
          },
        );

        await transport.ethCall(to: '0xabc', data: '0x123');

        final decoded = jsonDecode(capturedBody!) as Map<String, dynamic>;
        expect(decoded['jsonrpc'], '2.0');
        expect(decoded['id'], 1);
        expect(decoded['method'], 'eth_call');
        final params = decoded['params'] as List<dynamic>;
        expect(params[0], {'to': '0xabc', 'data': '0x123'});
        expect(params[1], 'latest');
      },
    );

    test(
      'throws EnsRpcException with revertData when JSON-RPC error has data',
      () async {
        final transport = HttpEnsRpcTransport(
          postJson: (uri, body) async {
            return jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'error': {
                'code': 3,
                'message': 'execution reverted',
                'data': '0xdeadbeef',
              },
            });
          },
        );

        await expectLater(
          transport.ethCall(to: '0xabc', data: '0x123'),
          throwsA(
            isA<EnsRpcException>()
                .having((e) => e.revertData, 'revertData', '0xdeadbeef')
                .having(
                  (e) => e.message,
                  'message',
                  contains('execution reverted'),
                ),
          ),
        );
      },
    );

    test(
      'falls through to second endpoint when first endpoint network call throws',
      () async {
        final calls = <Uri>[];
        final transport = HttpEnsRpcTransport(
          postJson: (uri, body) async {
            calls.add(uri);
            if (calls.length == 1) {
              throw Exception('network unreachable');
            }
            return jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'result': '0xsecondendpoint',
            });
          },
        );

        final result = await transport.ethCall(to: '0xabc', data: '0x123');

        expect(result, '0xsecondendpoint');
        expect(calls, hasLength(2));
        expect(calls[0], Uri.parse('https://eth.llamarpc.com'));
        expect(calls[1], Uri.parse('https://ethereum-rpc.publicnode.com'));
      },
    );

    test('throws EnsRpcException when all endpoints fail', () async {
      final transport = HttpEnsRpcTransport(
        postJson: (uri, body) async {
          throw Exception('network unreachable');
        },
      );

      await expectLater(
        transport.ethCall(to: '0xabc', data: '0x123'),
        throwsA(isA<EnsRpcException>()),
      );
    });

    test(
      'falls through to second endpoint when first returns non-JSON body',
      () async {
        final calls = <Uri>[];
        final transport = HttpEnsRpcTransport(
          postJson: (uri, body) async {
            calls.add(uri);
            if (calls.length == 1) {
              return '<html>rate limited</html>';
            }
            return jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'result': '0xsecondendpoint',
            });
          },
        );

        final result = await transport.ethCall(to: '0xabc', data: '0x123');

        expect(result, '0xsecondendpoint');
        expect(calls, hasLength(2));
        expect(calls[0], Uri.parse('https://eth.llamarpc.com'));
        expect(calls[1], Uri.parse('https://ethereum-rpc.publicnode.com'));
      },
    );

    test(
      'throws EnsRpcException (not FormatException) when all endpoints '
      'return non-JSON bodies',
      () async {
        final transport = HttpEnsRpcTransport(
          postJson: (uri, body) async => '<html>rate limited</html>',
        );

        await expectLater(
          transport.ethCall(to: '0xabc', data: '0x123'),
          throwsA(isA<EnsRpcException>()),
        );
      },
    );

    test('uses injected endpoint list instead of default', () async {
      final calls = <Uri>[];
      final transport = HttpEnsRpcTransport(
        endpoints: const ['https://custom-rpc.example.com'],
        postJson: (uri, body) async {
          calls.add(uri);
          return jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x01'});
        },
      );

      await transport.ethCall(to: '0xabc', data: '0x123');

      expect(calls, [Uri.parse('https://custom-rpc.example.com')]);
    });
  });

  group('HttpEnsRpcTransport.ccipFetch', () {
    test('uses GET and substitutes placeholders when template has {data}', () async {
      Uri? capturedUri;
      String? capturedMethod;
      final transport = HttpEnsRpcTransport(
        postJson: (uri, body) async =>
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x01'}),
        fetchCcip: (method, uri, body) async {
          capturedUri = uri;
          capturedMethod = method;
          return jsonEncode({'data': '0xccipresult'});
        },
      );

      final result = await transport.ccipFetch(
        url: 'https://gateway.example.com/{sender}/{data}.json',
        sender: '0xsender',
        data: '0xdatavalue',
      );

      expect(result, '0xccipresult');
      expect(capturedMethod, 'GET');
      expect(
        capturedUri,
        Uri.parse('https://gateway.example.com/0xsender/0xdatavalue.json'),
      );
    });

    test('uses POST with sender/data body when template has no {data}', () async {
      Uri? capturedUri;
      String? capturedMethod;
      String? capturedBody;
      final transport = HttpEnsRpcTransport(
        postJson: (uri, body) async =>
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x01'}),
        fetchCcip: (method, uri, body) async {
          capturedUri = uri;
          capturedMethod = method;
          capturedBody = body;
          return jsonEncode({'data': '0xpostresult'});
        },
      );

      final result = await transport.ccipFetch(
        url: 'https://gateway.example.com/{sender}',
        sender: '0xsender',
        data: '0xdatavalue',
      );

      expect(result, '0xpostresult');
      expect(capturedMethod, 'POST');
      expect(capturedUri, Uri.parse('https://gateway.example.com/0xsender'));
      final decoded = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(decoded['sender'], '0xsender');
      expect(decoded['data'], '0xdatavalue');
    });

    test(
      'throws EnsRpcException (not FormatException) when gateway returns '
      'non-JSON body',
      () async {
        final transport = HttpEnsRpcTransport(
          postJson: (uri, body) async =>
              jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0x01'}),
          fetchCcip: (method, uri, body) async => '<html>not json</html>',
        );

        await expectLater(
          transport.ccipFetch(
            url: 'https://gateway.example.com/{sender}/{data}.json',
            sender: '0xsender',
            data: '0xdatavalue',
          ),
          throwsA(isA<EnsRpcException>()),
        );
      },
    );
  });

  group('HttpEnsRpcTransport network privacy', () {
    NetworkHttpClient torClient(TorHttpBridge bridge) {
      final client = NetworkHttpClient(torDesired: () => true, torBridge: bridge);
      addTearDown(() => client.close(force: true));
      return client;
    }

    test('default eth_call routes through the policy-aware Tor bridge', () async {
      final bridge = _RecordingTorBridge(
        responseBody: jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'result': '0xdeadbeef',
        }),
      );
      final transport = HttpEnsRpcTransport(networkClient: torClient(bridge));

      final result = await transport.ethCall(to: '0xabc', data: '0x123');

      expect(result, '0xdeadbeef');
      expect(bridge.posts, [Uri.parse('https://eth.llamarpc.com')]);
      final decoded =
          jsonDecode(bridge.lastPostBody!) as Map<String, dynamic>;
      expect(decoded['method'], 'eth_call');
    });

    test('default eth_call fails closed while the Tor route is broken', () async {
      final bridge = _RecordingTorBridge(
        error: const DirectNetworkRequestsBlockedException(),
      );
      final transport = HttpEnsRpcTransport(networkClient: torClient(bridge));

      await expectLater(
        transport.ethCall(to: '0xabc', data: '0x123'),
        throwsA(isA<EnsRpcException>()),
      );
      // Every configured endpoint was attempted via the bridge — never via a
      // direct connection.
      expect(bridge.posts, hasLength(defaultEnsRpcEndpoints.length));
    });

    test('default ccipFetch routes through the policy-aware Tor bridge', () async {
      final bridge = _RecordingTorBridge(
        responseBody: jsonEncode({'data': '0xccipresult'}),
      );
      final transport = HttpEnsRpcTransport(networkClient: torClient(bridge));

      final result = await transport.ccipFetch(
        url: 'https://gateway.example.com/{sender}/{data}.json',
        sender: '0xsender',
        data: '0xdatavalue',
      );

      expect(result, '0xccipresult');
      expect(bridge.gets, [
        Uri.parse('https://gateway.example.com/0xsender/0xdatavalue.json'),
      ]);
    });

    test('default ccipFetch fails closed while the Tor route is broken', () async {
      final bridge = _RecordingTorBridge(
        error: const DirectNetworkRequestsBlockedException(),
      );
      final transport = HttpEnsRpcTransport(networkClient: torClient(bridge));

      await expectLater(
        transport.ccipFetch(
          url: 'https://gateway.example.com/{sender}/{data}.json',
          sender: '0xsender',
          data: '0xdatavalue',
        ),
        throwsA(isA<DirectNetworkRequestsBlockedException>()),
      );
    });
  });
}

class _RecordingTorBridge implements TorHttpBridge {
  _RecordingTorBridge({this.responseBody, this.error});

  final String? responseBody;
  final Object? error;

  final List<Uri> gets = [];
  final List<Uri> posts = [];
  String? lastPostBody;

  NetworkHttpResponse get _response => NetworkHttpResponse(
    statusCode: 200,
    bodyBytes: Uint8List.fromList(utf8.encode(responseBody ?? '')),
  );

  @override
  Future<NetworkHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    gets.add(uri);
    if (error != null) throw error!;
    return _response;
  }

  @override
  Future<NetworkHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
  }) async {
    posts.add(uri);
    lastPostBody = utf8.decode(bodyBytes);
    if (error != null) throw error!;
    return _response;
  }

  @override
  Future<NetworkHttpResponse> download(
    Uri uri, {
    required Map<String, String> headers,
    required String destinationPath,
  }) async {
    throw UnsupportedError('download is not used by ENS resolution');
  }
}
