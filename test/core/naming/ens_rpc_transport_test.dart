import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/naming/ens_rpc_transport.dart';

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
  });
}
