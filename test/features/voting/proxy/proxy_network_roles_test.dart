import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/network/network_http_client.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_verifier_client.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_providers.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_registry_fetcher.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_registry_proof_client.dart';
import 'package:zcash_wallet/src/services/voting/voting_api_client.dart';
import 'package:zcash_wallet/src/services/voting/voting_http.dart';

import 'support/proxy_registry_proof_fakes.dart';
import 'support/proxy_rust_fake.dart';

/// One request a [_RecordingTor] carried.
typedef _TorRequest = ({
  String method,
  Uri uri,
  Map<String, String> headers,
  List<int>? body,
  int? limit,
});

/// Tor that answers every GET and POST with [answer] and records each one.
class _RecordingTor implements TorHttpBridge {
  /// Creates the bridge.
  _RecordingTor(this.answer);

  /// The answer to a request for a URI.
  final VotingHttpResponse Function(Uri uri) answer;

  /// Every request, in order.
  final requests = <_TorRequest>[];

  /// Records a request and answers it.
  NetworkHttpResponse _answer(
    String method,
    Uri uri,
    Map<String, String> headers,
    List<int>? body,
    int? limit,
  ) {
    requests.add((
      method: method,
      uri: uri,
      headers: headers,
      body: body,
      limit: limit,
    ));
    final response = answer(uri);
    return NetworkHttpResponse(
      statusCode: response.statusCode,
      bodyBytes: response.bodyBytes,
    );
  }

  @override
  Future<NetworkHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration? timeout,
    Future<void>? cancelSignal,
    int? maxBodyBytes,
  }) async => _answer('GET', uri, headers, null, maxBodyBytes);

  @override
  Future<NetworkHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
    required Duration? timeout,
    Future<void>? cancelSignal,
    int? maxBodyBytes,
  }) async => _answer('POST', uri, headers, bodyBytes, maxBodyBytes);

  @override
  Future<NetworkHttpResponse> download(
    Uri uri, {
    required Map<String, String> headers,
    required String destinationPath,
  }) => throw UnsupportedError('Proxy roles never download');
}

/// Tor that is selected but cannot carry a request.
class _BrokenTor implements TorHttpBridge {
  /// Requests Tor refused.
  var attempts = 0;

  /// Counts a refused request.
  Never _refuse() {
    attempts++;
    throw StateError('Tor connection failed');
  }

  @override
  Future<NetworkHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration? timeout,
    Future<void>? cancelSignal,
    int? maxBodyBytes,
  }) async => _refuse();

  @override
  Future<NetworkHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
    required Duration? timeout,
    Future<void>? cancelSignal,
    int? maxBodyBytes,
  }) async => _refuse();

  @override
  Future<NetworkHttpResponse> download(
    Uri uri, {
    required Map<String, String> headers,
    required String destinationPath,
  }) async => _refuse();
}

/// A local host that answers with [answer] and records each request's
/// method, path and codespace header.
Future<(HttpServer, List<(String, String, String?)>)> _localHost(
  VotingHttpResponse Function(Uri uri) answer,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  final requests = <(String, String, String?)>[];
  server.listen((request) async {
    requests.add((
      request.method,
      request.uri.path,
      request.headers.value('x-svote-codespace'),
    ));
    await request.drain<void>();
    final response = answer(request.requestedUri);
    request.response
      ..statusCode = response.statusCode
      ..add(response.bodyBytes);
    unawaited(request.response.close());
  });
  return (server, requests);
}

/// A JSON answer of [body] with [status].
VotingHttpResponse _json(String body, {int status = 200}) => VotingHttpResponse(
  statusCode: status,
  bodyBytes: Uint8List.fromList(utf8.encode(body)),
);

/// The attester's rate-limit refusal.
const _verifierRefusal = '{"error":"rate_limited","retry_after":1790006400}';

/// An attest request body, as zcash_voting builds it.
final _attestBody = Uint8List.fromList(
  utf8.encode(
    '{"provider":1,"proof_url":"https://x.com/a/status/1","dk":"zvdk1"}',
  ),
);

/// One proxy network role: how a host answers, how the client calls a URL
/// list, and what reaches a host.
typedef _Role = ({
  String name,
  VotingHttpResponse Function(Uri uri) answer,

  /// Calls the role on [network] over [http] with [urls]: a short account
  /// of the answer it accepted, or null when no host served one.
  Future<String?> Function(
    VotingHttpClient http,
    String network,
    List<String> urls,
  )
  call,

  /// A public URL for [call], and the paths one call requests below it.
  String publicUrl,
  List<String> paths,

  /// What [call] returns for a healthy host.
  String Function(String host) accepted,
  int maxResponseBytes,
});

final _roles = <_Role>[
  (
    name: 'proof hosts',
    answer: (uri) => proofHostAnswer(uri, 101),
    call: (http, network, urls) async {
      final bridge = proxyRust.proofs = FakeRegistryProofRust();
      try {
        await ProxyRegistryProofClient(http, delay: (_) async {}).prove(
          network: network,
          proofRpcUrls: [for (final url in urls) Uri.parse(url)],
          delegateIndices: [1],
        );
      } on ProxyDelegationError catch (error) {
        expect(error.kind, ProxyDelegationErrorKind.cannotVerify);
        return null;
      }
      return bridge.verifiedHosts.join(',');
    },
    publicUrl: 'https://proof-a.example',
    paths: ['/commit', '/validators', '/abci_query'],
    accepted: (host) => host,
    maxResponseBytes: ProxyRegistryProofClient.maxResponseBytes,
  ),
  (
    name: 'registry mirrors',
    answer: (_) => _json('{"ok":1}'),
    call: (http, network, urls) async {
      final body = await ProxyRegistryFetcher(http).first(
        network: network,
        urls: urls,
        role: 'wallet list',
        accept: (body) async => body,
      );
      return body == null ? null : utf8.decode(body);
    },
    publicUrl: 'https://mirror-a.example/list.json',
    paths: ['/list.json'],
    accepted: (_) => '{"ok":1}',
    maxResponseBytes: ProxyRegistryFetcher.maxResponseBytes,
  ),
  (
    name: 'verifiers',
    answer: (_) => _json(_verifierRefusal, status: 429),
    call: (http, network, urls) async {
      final answer = await DelegateVerifierClient(http).post(
        network: network,
        urls: urls,
        path: '/v1/attest',
        body: _attestBody,
        accept: (answer) async => answer,
      );
      return answer == null
          ? null
          : '${answer.statusCode} ${utf8.decode(answer.body)}';
    },
    publicUrl: 'https://verifier.example/api',
    paths: ['/api/v1/attest'],
    accepted: (_) => '429 $_verifierRefusal',
    maxResponseBytes: DelegateVerifierClient.maxResponseBytes,
  ),
];

/// [role]'s public URL moved to a local [port] on [host], keeping its path.
String _local(_Role role, int port, {String host = '127.0.0.1'}) => Uri.parse(
  role.publicUrl,
).replace(scheme: 'http', host: host, port: port).toString();

/// A local host whose every answer is a chunked body without end: 64 KiB
/// chunks until the client hangs up or [cap] bytes went out. The future
/// completes with the bytes sent before the client hung up, or with -1 when
/// it never did. A raw socket, because an [HttpServer] answer does not see
/// the client go away.
Future<(ServerSocket, Future<int>)> _endlessHost({int cap = 64 << 20}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(server.close);
  final hungUp = Completer<int>();
  server.listen((socket) async {
    var gone = false;
    socket.listen(
      (_) {},
      onDone: () => gone = true,
      onError: (Object _) => gone = true,
    );
    final chunk = Uint8List(64 * 1024);
    final chunkHeader = utf8.encode('${chunk.length.toRadixString(16)}\r\n');
    var written = 0;
    try {
      socket.add(
        utf8.encode('HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n'),
      );
      while (!gone && written < cap) {
        socket
          ..add(chunkHeader)
          ..add(chunk)
          ..add(utf8.encode('\r\n'));
        await socket.flush();
        written += chunk.length;
      }
    } catch (_) {
      gone = true;
    }
    if (!hungUp.isCompleted) hungUp.complete(gone ? written : -1);
    socket.destroy();
  });
  return (server, hungUp.future);
}

/// The voting HTTP client over a route-aware [NetworkHttpClient] that
/// selects Tor, through [tor], when [torSelected], and direct otherwise.
DartIoVotingHttpClient _routed(TorHttpBridge tor, {required bool torSelected}) {
  final http = DartIoVotingHttpClient(
    networkClient: NetworkHttpClient(
      torDesired: () => torSelected,
      torBootstrapping: () => false,
      torBridge: tor,
    ),
  );
  addTearDown(() => http.close(force: true));
  return http;
}

void main() {
  useProxyRustFake();
  for (final role in _roles) {
    group('${role.name} follow the selected route', () {
      test('over the selected Tor route', () async {
        final tor = _RecordingTor(role.answer);
        final accepted = await role.call(
          _routed(tor, torSelected: true),
          'main',
          [role.publicUrl],
        );
        final public = Uri.parse(role.publicUrl);
        expect(accepted, role.accepted(public.host));
        expect(
          [for (final request in tor.requests) request.uri.path],
          [for (final path in role.paths) path],
        );
        expect(tor.requests.map((request) => request.uri.host).toSet(), {
          public.host,
        });
        for (final request in tor.requests) {
          expect(request.body, request.method == 'POST' ? _attestBody : null);
          expect(request.limit, role.maxResponseBytes);
        }
      });

      test('an unsigned URL list cannot point it at plain HTTP or '
          'credentials', () async {
        final public = Uri.parse(role.publicUrl);
        final tor = _RecordingTor(role.answer);
        final accepted = await role
            .call(_routed(tor, torSelected: true), 'main', [
              public.replace(scheme: 'http').toString(),
              public.replace(userInfo: 'user:secret').toString(),
              'not a url',
            ]);
        expect(accepted, isNull);
        expect(tor.requests, isEmpty);
      });
    });
  }

  group('vote-chain reads and posts ask for the codespace on the selected '
      'route', () {
    /// A vote server client at [baseUrl] over [http].
    VotingApiClient voteServer(VotingHttpClient http, Uri baseUrl) =>
        VotingApiClient(
          baseUrl: baseUrl,
          httpClient: http,
          delay: (_) async {},
        );

    /// A delegate op body, as zcash_voting builds it.
    final op = Uint8List.fromList(
      utf8.encode('{"retire":{"delegate_index":1}}'),
    );

    test('over Tor', () async {
      final tor = _RecordingTor((_) => _json('{}'));
      final api = voteServer(
        _routed(tor, torSelected: true),
        Uri.parse('https://vote.example'),
      );
      await api.getChainAnswer('/shielded-vote/v1/delegates/by-key/ab');
      await api.postChainBody('/shielded-vote/v1/delegate-op', op);
      expect(
        [
          for (final request in tor.requests)
            (
              request.method,
              request.uri.path,
              request.headers['x-svote-codespace'],
            ),
        ],
        [
          ('GET', '/shielded-vote/v1/delegates/by-key/ab', '1'),
          ('POST', '/shielded-vote/v1/delegate-op', '1'),
        ],
      );
    });

    test('directly', () async {
      final (server, requests) = await _localHost((_) => _json('{}'));
      final api = voteServer(
        _routed(_BrokenTor(), torSelected: false),
        Uri.parse('http://127.0.0.1:${server.port}'),
      );
      await api.getChainAnswer('/shielded-vote/v1/delegates/by-key/ab');
      await api.postChainBody('/shielded-vote/v1/delegate-op', op);
      expect(requests, [
        ('GET', '/shielded-vote/v1/delegates/by-key/ab', '1'),
        ('POST', '/shielded-vote/v1/delegate-op', '1'),
      ]);
    });
  });

  test('every proxy network role shares one route-aware client', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final http = container.read(proxyHttpClientProvider);
    expect(container.read(proxyRegistryProofClientProvider).http, same(http));
    expect(container.read(proxyRegistryFetcherProvider).http, same(http));
    expect(container.read(delegateVerifierClientProvider).http, same(http));
  });

  test('proxy delegation builds HTTP only on the route-aware client', () {
    // Every proxy host is a row of rust/src/wallet/voting/README.md's route
    // table: the feature opens no socket of its own and builds its one
    // client from DartIoVotingHttpClient, which rides NetworkHttpClient.
    final files = Directory('lib/src/features/voting/proxy')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final raw = RegExp(
      r"import 'dart:io'|\bHttpClient\(|NetworkHttpClient\(|Socket\.",
    );
    final builders = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(raw.hasMatch(source), isFalse, reason: file.path);
      if (source.contains('DartIoVotingHttpClient(')) builders.add(file.path);
    }
    expect(builders, [
      'lib/src/features/voting/proxy/proxy_delegation_providers.dart',
    ]);
  });

  // Every role rides the one route-aware client, so one role proves its
  // route and size cap end to end.
  group('${_roles.first.name} on a broken or endless route', () {
    final role = _roles.first;

    test(
      'a broken Tor route fails over across hosts, never to direct',
      () async {
        final (server, requests) = await _localHost(role.answer);
        final tor = _BrokenTor();
        final accepted = await role.call(
          _routed(tor, torSelected: true),
          'regtest',
          [
            _local(role, server.port),
            _local(role, server.port, host: 'localhost'),
          ],
        );
        expect(accepted, isNull);
        expect(tor.attempts, 2, reason: 'each host is tried once, over Tor');
        expect(requests, isEmpty, reason: 'nothing reached a host directly');
      },
    );

    test('an oversized answer is cut off while it streams, and failover '
        'continues', () async {
      final (huge, sent) = await _endlessHost();
      final (healthy, requests) = await _localHost(role.answer);
      final accepted = await role.call(
        _routed(_BrokenTor(), torSelected: false),
        'regtest',
        [
          _local(role, huge.port),
          _local(role, healthy.port, host: 'localhost'),
        ],
      );
      expect(accepted, role.accepted('localhost'));
      expect([for (final (_, path, _) in requests) path], role.paths);
      expect(
        await sent,
        inExclusiveRange(0, 64 << 20),
        reason: 'the client hung up mid-stream',
      );
    });
  });
}
