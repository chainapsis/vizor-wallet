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

final _now = DateTime.utc(2026, 10, 28);

Map<String, Object?> _record({
  String name = 'alice',
  Object? address = _address,
  Object? lastAction = 'claim',
  Object? expiresAt = '1824002006',
}) => {
  'name': name,
  'address': address,
  'txid': 'ed98bed2e92ac46f16b27db5c55597539abc714fb259f1bc2b2fa5dfb586e266',
  'height': 3523662,
  'last_action': lastAction,
  'expires_at': expiresAt,
};

List<int> _reply(Object? result) =>
    utf8.encode(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': result}));

ZnsResolution? _parse(
  Object? result, {
  int statusCode = 200,
  String requestedName = 'alice',
}) => parseZnsResolveResponse(
  statusCode: statusCode,
  body: _reply(result),
  requestedName: requestedName,
  now: _now,
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
    test('reads a live registration', () {
      final resolution = _parse(_record());
      expect(resolution, const ZnsResolution(name: 'alice', address: _address));
      expect(resolution!.displayName, 'alice.zcash');
    });

    test('accepts an update and a name that never expires', () {
      expect(
        _parse(_record(lastAction: 'update', expiresAt: 'none')),
        isNotNull,
      );
    });

    test('a missing, released, or expired name resolves to nothing', () {
      expect(_parse(null), isNull);
      expect(_parse(_record(lastAction: 'release')), isNull);
      final expiredAt = _now.millisecondsSinceEpoch ~/ 1000;
      expect(_parse(_record(expiresAt: '$expiredAt')), isNull);
      expect(_parse(_record(expiresAt: '${expiredAt + 1}')), isNotNull);
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
          now: _now,
        ),
        throwsA(isA<ZnsLookupException>()),
      );
      expect(
        () => parseZnsResolveResponse(
          statusCode: 200,
          body: utf8.encode('<html>'),
          requestedName: 'alice',
          now: _now,
        ),
        throwsA(isA<ZnsLookupException>()),
      );
    });

    test('refuses a record that does not answer the question asked', () {
      for (final record in [
        _record(name: 'mallory'),
        _record(address: null),
        _record(address: '  '),
        _record(lastAction: 'transfer'),
        _record(expiresAt: null),
        _record(expiresAt: 'soon'),
      ]) {
        expect(
          () => _parse(record),
          throwsA(isA<ZnsLookupException>()),
          reason: '$record',
        );
      }
    });
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
        networkClient: client,
        now: () => _now,
      );
    }

    test('posts one JSON-RPC resolve call on the Tor route', () async {
      final bridge = _ScriptedTorBridge({primary: _reply(_record())});

      final resolution = await resolverOver(bridge).resolve('alice');

      expect(resolution?.address, _address);
      expect(bridge.posted, [primary]);
      expect(jsonDecode(utf8.decode(bridge.bodies.single)), {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'resolve',
        'params': {'query': 'alice'},
      });
    });

    test('uses the fallback only when the primary is unreachable', () async {
      final bridge = _ScriptedTorBridge({
        primary: const SocketException('unreachable'),
        fallback: _reply(_record()),
      });

      final resolution = await resolverOver(bridge).resolve('alice');

      expect(resolution?.name, 'alice');
      expect(bridge.posted, [primary, fallback]);
    });

    test('an answer from the primary is final', () async {
      final bridge = _ScriptedTorBridge({
        primary: _reply(null),
        fallback: _reply(_record()),
      });

      expect(await resolverOver(bridge).resolve('alice'), isNull);
      expect(bridge.posted, [primary]);
    });

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
/// throw as the transport failure.
class _ScriptedTorBridge implements TorHttpBridge {
  _ScriptedTorBridge(this.script);

  final Map<Uri, Object> script;
  final posted = <Uri>[];
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
    posted.add(uri);
    bodies.add(bodyBytes);
    final entry = script[uri];
    if (entry is Exception) throw entry;
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
