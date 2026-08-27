import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/network/network_http_client.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_http_remote_store.dart';

void main() {
  test(
    'gate lets an in-flight request finish but blocks the next one',
    () async {
      var allowed = true;
      final delegate = _ControlledTransport();
      final transport = GatedPrivateStateHttpTransport(
        delegate: delegate,
        canStartRequest: () => allowed,
      );

      final first = transport.request(
        'POST',
        Uri.parse('https://private.example/challenge'),
      );
      allowed = false;
      delegate.complete();

      expect((await first).statusCode, HttpStatus.ok);
      await expectLater(
        transport.request('GET', Uri.parse('https://private.example/object')),
        throwsA(isA<PrivateStateSyncDisabledException>()),
      );
      expect(delegate.requestCount, 1);
    },
  );

  test(
    'Debug direct transport bypasses the global direct-request gate',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('local');
        await request.response.close();
      });
      final transport = DebugDirectPrivateStateHttpTransport();
      addTearDown(() async {
        NetworkHttpClient.allowDirectRequests();
        transport.close(force: true);
        await server.close(force: true);
      });

      await NetworkHttpClient.quiesceDirectRequests();
      final response = await transport.request(
        'GET',
        Uri(
          scheme: 'http',
          host: InternetAddress.loopbackIPv4.address,
          port: server.port,
        ),
      );

      expect(utf8.decode(response.bodyBytes), 'local');
    },
  );

  test('Tor-required transport ensures Tor before every request', () async {
    final events = <String>[];
    final transport = TorRequiredPrivateStateHttpTransport(
      runtime: _RecordingRuntime(events),
      torBridge: _RecordingBridge(events),
    );
    addTearDown(() => transport.close(force: true));

    final response = await transport.request(
      'POST',
      Uri.parse('https://private.example/object'),
      bodyBytes: utf8.encode('payload'),
    );

    expect(response.statusCode, HttpStatus.noContent);
    expect(events, ['ensure', 'post']);
  });

  test(
    'Tor-required transport does not fall back when Tor setup fails',
    () async {
      final bridge = _RecordingBridge(<String>[]);
      final transport = TorRequiredPrivateStateHttpTransport(
        runtime: const _FailingRuntime(),
        torBridge: bridge,
      );
      addTearDown(() => transport.close(force: true));

      await expectLater(
        transport.request('GET', Uri.parse('https://private.example/object')),
        throwsStateError,
      );
      expect(bridge.events, isEmpty);
    },
  );
}

class _ControlledTransport implements PrivateStateHttpTransport {
  final _completer = Completer<NetworkHttpResponse>();
  var requestCount = 0;

  @override
  Future<NetworkHttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int> bodyBytes = const [],
    Duration? timeout,
  }) {
    requestCount++;
    return _completer.future;
  }

  void complete() {
    _completer.complete(
      NetworkHttpResponse(statusCode: HttpStatus.ok, bodyBytes: Uint8List(0)),
    );
  }
}

class _RecordingRuntime implements PrivateStateTorRuntime {
  const _RecordingRuntime(this.events);

  final List<String> events;

  @override
  Future<void> ensureReady() async => events.add('ensure');
}

class _FailingRuntime implements PrivateStateTorRuntime {
  const _FailingRuntime();

  @override
  Future<void> ensureReady() => throw StateError('Tor unavailable');
}

class _RecordingBridge implements TorHttpBridge {
  const _RecordingBridge(this.events);

  final List<String> events;

  @override
  Future<NetworkHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    events.add('get');
    return NetworkHttpResponse(
      statusCode: HttpStatus.ok,
      bodyBytes: Uint8List(0),
    );
  }

  @override
  Future<NetworkHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
  }) async {
    events.add('post');
    return NetworkHttpResponse(
      statusCode: HttpStatus.noContent,
      bodyBytes: Uint8List(0),
    );
  }

  @override
  Future<NetworkHttpResponse> download(
    Uri uri, {
    required Map<String, String> headers,
    required String destinationPath,
  }) => throw UnsupportedError('not used');
}
