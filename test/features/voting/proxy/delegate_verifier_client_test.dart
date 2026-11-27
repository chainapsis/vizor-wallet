import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_verifier_client.dart';
import 'package:zcash_wallet/src/services/voting/voting_api_client.dart';
import 'package:zcash_wallet/src/services/voting/voting_http.dart';

/// Verifier hosts answering from a host map, recording each request.
class _Verifiers implements VotingHttpClient {
  /// The answer per host: a response, or an error to throw.
  final answers = <String, Object>{};

  /// Every request, in order.
  final requests = <Uri>[];

  /// Every body, in order.
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<VotingHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
    Future<void>? cancelSignal,
    int? maxBodyBytes,
  }) => throw UnsupportedError('The verifier is only posted to');

  @override
  Future<VotingHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    Duration? timeout,
    int? maxBodyBytes,
  }) async {
    requests.add(uri);
    bodies.add(body);
    final answer = answers[uri.host];
    if (answer is VotingHttpResponse) return answer;
    throw answer ?? const SocketException('no route to verifier');
  }
}

/// An answer of [status] carrying [text].
VotingHttpResponse _answer(int status, String text) => VotingHttpResponse(
  statusCode: status,
  bodyBytes: Uint8List.fromList(utf8.encode(text)),
);

void main() {
  final body = Uint8List.fromList(
    utf8.encode('{"provider":1,"proof_url":"https://x.com/a/status/1"}'),
  );

  /// The status of the first answer from [urls] that [accept] takes, or
  /// every JSON answer when [accept] is not given.
  Future<int?> statusFrom(
    _Verifiers hosts,
    List<String> urls, {
    Future<int> Function(VotingChainAnswer answer)? accept,
  }) => DelegateVerifierClient(hosts).post(
    network: 'main',
    urls: urls,
    path: '/v1/attest',
    body: body,
    accept: accept ?? (answer) async => answer.statusCode,
  );

  test('a JSON answer is the verifier\'s, refusal or not', () async {
    final hosts = _Verifiers()
      ..answers['a.example'] = _answer(409, '{"error":"marker_mismatch"}')
      ..answers['b.example'] = _answer(200, '{}');
    expect(
      await statusFrom(hosts, ['https://a.example', 'https://b.example']),
      409,
    );
    expect(hosts.requests.single.toString(), 'https://a.example/v1/attest');
    expect(hosts.bodies.single, jsonDecode(utf8.decode(body)));
  });

  test('an outage, a page that is not JSON or an oversized answer moves on '
      'to the next host', () async {
    final hosts = _Verifiers()
      ..answers['a.example'] = const SocketException('down')
      ..answers['b.example'] = _answer(502, '<html>bad gateway</html>')
      ..answers['c.example'] = VotingHttpResponse(
        statusCode: 200,
        bodyBytes: Uint8List(DelegateVerifierClient.maxResponseBytes + 1),
      )
      ..answers['d.example'] = _answer(200, '{"delegate_index":0}');
    expect(
      await statusFrom(hosts, [
        'https://a.example',
        'https://b.example',
        'https://c.example',
        'https://d.example',
      ]),
      200,
    );
    expect(hosts.requests.map((uri) => uri.host), [
      'a.example',
      'b.example',
      'c.example',
      'd.example',
    ]);
    expect(
      await statusFrom(_Verifiers(), ['https://a.example']),
      isNull,
      reason: 'no host answered',
    );
  });

  /// Reads an answer as the delegate repository does: `{}` is not the
  /// API's, and a 409 is a refusal that ends the call.
  Future<int> strict(VotingChainAnswer answer) async {
    if (utf8.decode(answer.body) == '{}') {
      throw DelegateVerifierAnswerUnusable('malformed ${answer.statusCode}');
    }
    if (answer.statusCode == 409) throw StateError('refused');
    return answer.statusCode;
  }

  test('an answer the reader finds unusable moves on to the next host, and '
      'the reader\'s refusal ends the call', () async {
    final hosts = _Verifiers()
      ..answers['a.example'] = _answer(200, '{}')
      ..answers['b.example'] = _answer(409, '{"error":"marker_mismatch"}')
      ..answers['c.example'] = _answer(200, '{"delegate_index":0}');
    await expectLater(
      statusFrom(hosts, [
        'https://a.example',
        'https://b.example',
        'https://c.example',
      ], accept: strict),
      throwsA(isA<StateError>()),
    );
    expect(hosts.requests.map((uri) => uri.host), ['a.example', 'b.example']);

    final healthy = _Verifiers()
      ..answers['a.example'] = _answer(200, '{}')
      ..answers['c.example'] = _answer(200, '{"delegate_index":0}');
    expect(
      await statusFrom(healthy, [
        'https://a.example',
        'https://c.example',
      ], accept: strict),
      200,
    );
  });

  test(
    'when every answer is unusable, the last one\'s cause is thrown',
    () async {
      final hosts = _Verifiers()
        ..answers['a.example'] = _answer(200, '{}')
        ..answers['b.example'] = _answer(503, '{}');
      await expectLater(
        statusFrom(hosts, [
          'https://a.example',
          'https://b.example',
        ], accept: strict),
        throwsA('malformed 503'),
      );
    },
  );
}
