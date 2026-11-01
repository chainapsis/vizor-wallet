import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/naming/zns_name_resolver.dart';
import 'package:zcash_wallet/src/core/network/network_http_client.dart';

const _address =
    'u14lms6q2sg984hhng068lqesatnak86mlg297x0qkqsvkqgk2m7dyj5x2grlku3adg2tq6t'
    'rl5ue3vce7c3jnu5808kw9lsr890kfetrg524q4pgcn4zcnp84na85453pz67cjfy4sx7y6z'
    '6zc9t7666utasw5mehe9r2dwwcrgzp94ah';

const _registryKey = 'uview1registry';

Map<String, Object?> _record({
  String name = 'alice',
  Object? address = _address,
  Object? lastAction = 'claim',
}) => {
  'name': name,
  'address': address,
  'txid': 'ed98bed2e92ac46f16b27db5c55597539abc714fb259f1bc2b2fa5dfb586e266',
  'height': 3523662,
  'last_action': lastAction,
  'expires_at': '1824002006',
};

List<int> _reply(Object? result) =>
    utf8.encode(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': result}));

List<int> _status([String viewingKey = _registryKey]) => _reply({
  'synced_height': 3533383,
  'synced': true,
  'viewing_key': viewingKey,
});

ZnsResolution? _parse(
  Object? result, {
  int statusCode = 200,
  String requestedName = 'alice',
}) => parseZnsResolveResponse(
  statusCode: statusCode,
  body: _reply(result),
  requestedName: requestedName,
);

void main() {
  group('znsNameFromRecipientInput', () {
    test('accepts both suffixes in any case and trims', () {
      expect(znsNameFromRecipientInput('alice.zcash'), 'alice');
      expect(znsNameFromRecipientInput('Alice.ZEC'), 'alice');
      expect(znsNameFromRecipientInput('  bob42.Zcash \n'), 'bob42');
    });

    test('never treats a bare word or an address as a name', () {
      expect(znsNameFromRecipientInput('alice'), isNull);
      expect(znsNameFromRecipientInput(_address), isNull);
      expect(znsNameFromRecipientInput('t1abc'), isNull);
      expect(znsNameFromRecipientInput(''), isNull);
    });

    test('rejects names the registry cannot hold', () {
      expect(znsNameFromRecipientInput('.zcash'), isNull);
      expect(znsNameFromRecipientInput('al-ice.zcash'), isNull);
      expect(znsNameFromRecipientInput('a.b.zcash'), isNull);
      expect(znsNameFromRecipientInput('ålice.zec'), isNull);
      expect(znsNameFromRecipientInput('${'a' * 63}.zec'), 'a' * 63);
      expect(znsNameFromRecipientInput('${'a' * 64}.zec'), isNull);
    });
  });

  group('parseZnsResolveResponse', () {
    test('reads a registration', () {
      final resolution = _parse(_record());
      expect(resolution, const ZnsResolution(name: 'alice', address: _address));
      expect(resolution!.displayName, 'alice.zcash');
      expect(_parse(_record(lastAction: 'update')), isNotNull);
    });

    test('leaves expiry to the Mint', () {
      final pastExpiry = _record()..['expires_at'] = '1';
      expect(_parse(pastExpiry), isNotNull);
      expect(_parse(_record()..remove('expires_at')), isNotNull);
    });

    test('a missing or released name resolves to nothing', () {
      expect(_parse(null), isNull);
      expect(_parse(_record(lastAction: 'release')), isNull);
    });

    test('an HTTP or JSON-RPC failure is an error, not a missing name', () {
      expect(
        () => _parse(_record(), statusCode: 503),
        throwsA(isA<ZnsLookupException>()),
      );
      expect(
        () => parseZnsResolveResponse(
          statusCode: 200,
          body: utf8.encode(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'error': {'code': -32601, 'message': 'Method not found'},
            }),
          ),
          requestedName: 'alice',
        ),
        throwsA(isA<ZnsLookupException>()),
      );
      expect(
        () => parseZnsResolveResponse(
          statusCode: 200,
          body: utf8.encode('<html>'),
          requestedName: 'alice',
        ),
        throwsA(isA<ZnsLookupException>()),
      );
    });

    test('a reply that is not a JSON-RPC answer is a host failure', () {
      for (final reply in <Object?>[
        {'status': 'maintenance'},
        {'jsonrpc': '2.0', 'id': 1},
        {'jsonrpc': '1.0', 'id': 1, 'result': null},
        {'jsonrpc': '2.0', 'id': 7, 'result': null},
      ]) {
        expect(
          () => parseZnsResolveResponse(
            statusCode: 200,
            body: utf8.encode(jsonEncode(reply)),
            requestedName: 'alice',
          ),
          throwsA(isA<ZnsHostUnavailableException>()),
          reason: '$reply',
        );
      }
    });

    test('refuses a record that does not answer the question asked', () {
      for (final record in [
        _record(name: 'mallory'),
        _record(address: null),
        _record(address: '  '),
        _record(lastAction: 'transfer'),
      ]) {
        expect(
          () => _parse(record),
          throwsA(isA<ZnsLookupException>()),
          reason: '$record',
        );
      }
    });
  });

  test('parseZnsStatusViewingKey reads the registry key', () {
    expect(
      parseZnsStatusViewingKey(statusCode: 200, body: _status()),
      _registryKey,
    );
    expect(
      () => parseZnsStatusViewingKey(statusCode: 200, body: _reply({})),
      throwsA(isA<ZnsLookupException>()),
    );
  });

  test('the published keys are well-formed', () {
    expect(kZnsMainnetRegistryViewingKey, startsWith('uview1'));
    expect(kZnsTestnetRegistryViewingKey, startsWith('uviewtest1'));
    for (final key in [
      kZnsMainnetRegistryViewingKey,
      kZnsTestnetRegistryViewingKey,
    ]) {
      expect(key, matches(RegExp(r'^[a-z0-9]+$')));
    }
  });

  group('ZnsJsonRpcNameResolver', () {
    final primary = Uri.parse('https://primary.example');
    final fallback = Uri.parse('https://fallback.example');

    ZnsJsonRpcNameResolver resolverOver(_ScriptedTorBridge bridge) {
      final client = NetworkHttpClient(
        torDesired: () => true,
        torBootstrapping: () => false,
        torBridge: bridge,
      );
      addTearDown(client.close);
      return ZnsJsonRpcNameResolver(
        endpoints: [primary, fallback],
        registryViewingKey: _registryKey,
        networkClient: client,
      );
    }

    test('checks the registry once, then resolves on the Tor route', () async {
      final bridge = _ScriptedTorBridge({primary: _reply(_record())});
      final resolver = resolverOver(bridge);

      expect((await resolver.resolve('alice'))?.address, _address);
      expect(await resolver.resolve('alice'), isNotNull);

      expect(bridge.calls, [
        (primary, 'status'),
        (primary, 'resolve'),
        (primary, 'resolve'),
      ]);
      expect(jsonDecode(utf8.decode(bridge.bodies.last)), {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'resolve',
        'params': {'query': 'alice'},
      });
    });

    test('refuses a host that serves another registry', () async {
      final bridge = _ScriptedTorBridge(
        {primary: _reply(_record()), fallback: _reply(_record())},
        status: {primary: _status('uview1other')},
      );

      await expectLater(
        resolverOver(bridge).resolve('alice'),
        throwsA(isA<ZnsLookupException>()),
      );
      expect(bridge.calls, [(primary, 'status')]);
    });

    test('uses the fallback only when the primary is unreachable', () async {
      final bridge = _ScriptedTorBridge({
        primary: const SocketException('unreachable'),
        fallback: _reply(_record()),
      });

      final resolution = await resolverOver(bridge).resolve('alice');

      expect(resolution?.name, 'alice');
      expect(bridge.calls, [
        (primary, 'status'),
        (fallback, 'status'),
        (fallback, 'resolve'),
      ]);
    });

    test('an answer from the primary is final', () async {
      final bridge = _ScriptedTorBridge({
        primary: _reply(null),
        fallback: _reply(_record()),
      });

      expect(await resolverOver(bridge).resolve('alice'), isNull);
      expect(bridge.calls.map((call) => call.$1).toSet(), {primary});
    });

    test('a failing primary hands the lookup to the fallback', () async {
      for (final failure in [
        _HttpReply(502, utf8.encode('<html>Bad gateway</html>')),
        _HttpReply(200, utf8.encode('<html>challenge</html>')),
        _HttpReply(
          200,
          utf8.encode(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'error': {'code': -32603, 'message': 'internal'},
            }),
          ),
        ),
      ]) {
        final bridge = _ScriptedTorBridge({
          primary: failure,
          fallback: _reply(_record()),
        });

        expect(
          (await resolverOver(bridge).resolve('alice'))?.address,
          _address,
          reason: '${failure.statusCode}',
        );
      }
    });

    test(
      'a JSON page or a bad status hands the lookup to the fallback',
      () async {
        final maintenance = _HttpReply(
          200,
          utf8.encode(jsonEncode({'status': 'maintenance'})),
        );
        for (final bridge in [
          _ScriptedTorBridge({
            primary: maintenance,
            fallback: _reply(_record()),
          }),
          _ScriptedTorBridge(
            {primary: _reply(_record()), fallback: _reply(_record())},
            status: {
              primary: _reply({'synced': true}),
            },
          ),
        ]) {
          expect(
            (await resolverOver(bridge).resolve('alice'))?.address,
            _address,
          );
          expect(bridge.calls.last, (fallback, 'resolve'));
        }
      },
    );

    test('throws when no resolver can be reached', () async {
      final bridge = _ScriptedTorBridge({
        primary: const SocketException('unreachable'),
        fallback: const SocketException('unreachable'),
      });

      await expectLater(
        resolverOver(bridge).resolve('alice'),
        throwsA(isA<ZnsLookupException>()),
      );
    });
  });
}

/// Answers each POST from a per-endpoint script: a reply body, or an error to
/// throw as the transport failure. `status` calls read [status], which
/// defaults to the expected registry key; a scripted transport error applies
/// to both methods.
class _ScriptedTorBridge implements TorHttpBridge {
  _ScriptedTorBridge(this.resolve, {Map<Uri, Object>? status})
    : status = status ?? const {};

  final Map<Uri, Object> resolve;
  final Map<Uri, Object> status;
  final calls = <(Uri, String)>[];
  final bodies = <List<int>>[];

  @override
  Future<NetworkHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
    required Duration? timeout,
    Future<void>? cancelSignal,
    int? maxBodyBytes,
  }) async {
    final method =
        (jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>)['method']
            as String;
    calls.add((uri, method));
    bodies.add(bodyBytes);
    final scripted = resolve[uri];
    if (scripted is Exception) throw scripted;
    if (scripted is _HttpReply) {
      return NetworkHttpResponse(
        statusCode: scripted.statusCode,
        bodyBytes: Uint8List.fromList(scripted.body),
      );
    }
    final entry = method == 'status' ? status[uri] ?? _status() : scripted;
    return NetworkHttpResponse(
      statusCode: 200,
      bodyBytes: Uint8List.fromList(entry! as List<int>),
    );
  }

  @override
  Future<NetworkHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration? timeout,
    Future<void>? cancelSignal,
    int? maxBodyBytes,
  }) => throw UnimplementedError();

  @override
  Future<NetworkHttpResponse> download(
    Uri uri, {
    required Map<String, String> headers,
    required String destinationPath,
  }) => throw UnimplementedError();
}

/// A scripted host failure, returned for every method on that host.
class _HttpReply {
  const _HttpReply(this.statusCode, this.body);

  final int statusCode;
  final List<int> body;
}
