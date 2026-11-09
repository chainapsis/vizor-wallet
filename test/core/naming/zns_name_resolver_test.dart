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

List<int> _page(List<Map<String, Object?>> items, {int? total}) => _reply({
  'items': items,
  'total': total ?? items.length,
  'limit': kZnsIndexPageSize,
  'offset': 0,
});

ZnsNamesPage _parse(List<int> body, {int statusCode = 200}) =>
    parseZnsNamesPage(statusCode: statusCode, body: body);

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

  group('parseZnsNamesPage', () {
    test('reads the records and the total', () {
      final page = _parse(
        _page([
          _record(),
          _record(name: 'bob', lastAction: 'update'),
        ], total: 900),
      );
      expect(page.total, 900);
      expect(page.names, const [
        ZnsResolution(name: 'alice', address: _address),
        ZnsResolution(name: 'bob', address: _address),
      ]);
      expect(page.names.first.displayName, 'alice.zcash');
    });

    test('leaves expiry to the Mint', () {
      final pastExpiry = _record()..['expires_at'] = '1';
      expect(_parse(_page([pastExpiry])).names, hasLength(1));
      expect(
        _parse(_page([_record()..remove('expires_at')])).names,
        hasLength(1),
      );
    });

    test('a released record comes back with no address', () {
      final page = _parse(_page([_record(lastAction: 'release')]));
      expect(page.names.single.address, isEmpty);
    });

    test('an HTTP or JSON-RPC failure is a host failure', () {
      for (final (statusCode, body) in [
        (503, _page([_record()])),
        (
          200,
          utf8.encode(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'error': {'code': -32601, 'message': 'Method not found'},
            }),
          ),
        ),
        (200, utf8.encode('<html>')),
      ]) {
        expect(
          () => _parse(body, statusCode: statusCode),
          throwsA(isA<ZnsHostUnavailableException>()),
          reason: '$statusCode',
        );
      }
    });

    test('a reply that is not a page is a host failure', () {
      for (final reply in <Object?>[
        {'status': 'maintenance'},
        {'jsonrpc': '2.0', 'id': 1},
        {'jsonrpc': '1.0', 'id': 1, 'result': null},
        {'jsonrpc': '2.0', 'id': 7, 'result': null},
        {'jsonrpc': '2.0', 'id': 1, 'result': null},
        {
          'jsonrpc': '2.0',
          'id': 1,
          'result': {'items': <Object>[]},
        },
        {
          'jsonrpc': '2.0',
          'id': 1,
          'result': {'items': null, 'total': 0},
        },
      ]) {
        expect(
          () => _parse(utf8.encode(jsonEncode(reply))),
          throwsA(isA<ZnsHostUnavailableException>()),
          reason: '$reply',
        );
      }
    });

    test('one malformed record refuses the page', () {
      for (final record in [
        _record(name: 'Mallory'),
        _record(name: 'al-ice'),
        _record(address: null),
        _record(address: '  '),
        _record(lastAction: 'transfer'),
      ]) {
        expect(
          () => _parse(_page([_record(name: 'aaa'), record])),
          throwsA(
            isA<ZnsLookupException>().having(
              (e) => e,
              'not a host failure',
              isNot(isA<ZnsHostUnavailableException>()),
            ),
          ),
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

  group('ZnsIndexNameResolver', () {
    final primary = Uri.parse('https://primary.example');
    final fallback = Uri.parse('https://fallback.example');
    late DateTime now;

    setUp(() => now = DateTime.utc(2026, 11, 9, 12));

    ZnsIndexNameResolver resolverOver(_ScriptedTorBridge bridge) {
      final client = NetworkHttpClient(
        torDesired: () => true,
        torBootstrapping: () => false,
        torBridge: bridge,
      );
      addTearDown(client.close);
      return ZnsIndexNameResolver(
        endpoints: [primary, fallback],
        registryViewingKey: _registryKey,
        networkClient: client,
        clock: () => now,
      );
    }

    test(
      'downloads the index on the Tor route and never sends a name',
      () async {
        final bridge = _ScriptedTorBridge({
          primary: _page([_record(), _record(name: 'bob')]),
        });
        final resolver = resolverOver(bridge);

        expect((await resolver.resolve('alice'))?.address, _address);
        expect((await resolver.resolve('bob'))?.name, 'bob');
        expect(await resolver.resolve('carol'), isNull);

        expect(bridge.calls, [(primary, 'status'), (primary, 'list_names')]);
        expect(jsonDecode(utf8.decode(bridge.bodies.last)), {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'list_names',
          'params': {'limit': kZnsIndexPageSize, 'offset': 0},
        });
        for (final body in bridge.bodies) {
          final sent = utf8.decode(body);
          expect(sent, isNot(contains('alice')));
          expect(sent, isNot(contains('carol')));
        }
      },
    );

    test('downloads the index again once it is older than maxAge', () async {
      var address = _address;
      final bridge = _ScriptedTorBridge({
        primary: (int offset) => _page([_record(address: address)]),
      });
      final resolver = resolverOver(bridge);

      expect((await resolver.resolve('alice'))?.address, _address);
      address = 'u1moved';
      now = now.add(const Duration(minutes: 4));
      expect((await resolver.resolve('alice'))?.address, _address);
      now = now.add(const Duration(minutes: 1));
      expect((await resolver.resolve('alice'))?.address, 'u1moved');

      expect(bridge.calls, [
        (primary, 'status'),
        (primary, 'list_names'),
        (primary, 'list_names'),
      ]);
    });

    test('concurrent lookups share one download', () async {
      final bridge = _ScriptedTorBridge({
        primary: _page([_record()]),
      });
      final resolver = resolverOver(bridge);

      final results = await Future.wait([
        resolver.resolve('alice'),
        resolver.resolve('bob'),
      ]);

      expect(results.first?.name, 'alice');
      expect(results.last, isNull);
      expect(bridge.calls.where((c) => c.$2 == 'list_names'), hasLength(1));
    });

    test('a failed download is not kept', () async {
      var reachable = false;
      final bridge = _ScriptedTorBridge({
        primary: (int offset) => reachable
            ? _page([_record()])
            : throw const SocketException('unreachable'),
        fallback: const SocketException('unreachable'),
      });
      final resolver = resolverOver(bridge);

      await expectLater(
        resolver.resolve('alice'),
        throwsA(isA<ZnsLookupException>()),
      );
      reachable = true;
      expect(await resolver.resolve('alice'), isNotNull);
    });

    test('pages through an index larger than one page', () async {
      final names = [
        for (var i = 0; i < kZnsIndexPageSize + 3; i++)
          'n${i.toString().padLeft(4, '0')}',
      ];
      final bridge = _ScriptedTorBridge({
        primary: (int offset) => _page([
          for (final name in names.skip(offset).take(kZnsIndexPageSize))
            _record(name: name),
        ], total: names.length),
      });
      final resolver = resolverOver(bridge);

      expect(await resolver.resolve(names.last), isNotNull);
      expect(await resolver.resolve(names.first), isNotNull);
      final offsets = [
        for (final body in bridge.bodies.skip(1))
          (jsonDecode(utf8.decode(body))['params'] as Map)['offset'],
      ];
      expect(offsets, [0, kZnsIndexPageSize]);
    });

    test('a released record is not a registration', () async {
      final bridge = _ScriptedTorBridge({
        primary: _page([
          _record(name: 'alice', lastAction: 'release'),
          _record(name: 'bob'),
        ]),
      });
      final resolver = resolverOver(bridge);

      expect(await resolver.resolve('alice'), isNull);
      expect(await resolver.resolve('bob'), isNotNull);
    });

    test('restarts a download when the index moves between pages', () async {
      final names = [
        for (var i = 0; i < kZnsIndexPageSize + 1; i++)
          'n${i.toString().padLeft(4, '0')}',
      ];
      var listCalls = 0;
      final bridge = _ScriptedTorBridge({
        primary: (int offset) {
          listCalls++;
          // The second page of the first attempt repeats a name, as when a
          // registration lands before the offset mid-download.
          final start = listCalls == 2 ? offset - 1 : offset;
          return _page([
            for (final name in names.skip(start).take(kZnsIndexPageSize))
              _record(name: name),
          ], total: names.length);
        },
      });

      expect(await resolverOver(bridge).resolve(names.last), isNotNull);
      expect(listCalls, 4);
    });

    test('refuses an index too large to download', () async {
      final bridge = _ScriptedTorBridge({
        primary: _page([_record()], total: kZnsMaxIndexNames + 1),
        fallback: _page([_record()]),
      });

      await expectLater(
        resolverOver(bridge).resolve('alice'),
        throwsA(isA<ZnsLookupException>()),
      );
      expect(bridge.calls.map((call) => call.$1).toSet(), {primary});
    });

    test('refuses a host that serves another registry', () async {
      final bridge = _ScriptedTorBridge(
        {
          primary: _page([_record()]),
          fallback: _page([_record()]),
        },
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
        fallback: _page([_record()]),
      });

      final resolution = await resolverOver(bridge).resolve('alice');

      expect(resolution?.name, 'alice');
      expect(bridge.calls, [
        (primary, 'status'),
        (fallback, 'status'),
        (fallback, 'list_names'),
      ]);
    });

    test('an index from the primary is final', () async {
      final bridge = _ScriptedTorBridge({
        primary: _page([]),
        fallback: _page([_record()]),
      });

      expect(await resolverOver(bridge).resolve('alice'), isNull);
      expect(bridge.calls.map((call) => call.$1).toSet(), {primary});
    });

    test('a failing primary hands the download to the fallback', () async {
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
        _HttpReply(200, utf8.encode(jsonEncode({'status': 'maintenance'}))),
      ]) {
        final bridge = _ScriptedTorBridge({
          primary: failure,
          fallback: _page([_record()]),
        });

        expect(
          (await resolverOver(bridge).resolve('alice'))?.address,
          _address,
          reason: '${failure.statusCode}',
        );
        expect(bridge.calls.last, (fallback, 'list_names'));
      }
    });

    test('a bad status hands the download to the fallback', () async {
      final bridge = _ScriptedTorBridge(
        {
          primary: _page([_record()]),
          fallback: _page([_record()]),
        },
        status: {
          primary: _reply({'synced': true}),
        },
      );

      expect((await resolverOver(bridge).resolve('alice'))?.address, _address);
      expect(bridge.calls.last, (fallback, 'list_names'));
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

/// Answers each POST from a per-endpoint script: a `list_names` reply body,
/// a function of the requested offset that returns one, or an error to
/// throw as the transport failure. `status` calls read [status], which
/// defaults to the expected registry key; a scripted transport error or
/// [_HttpReply] applies to both methods.
class _ScriptedTorBridge implements TorHttpBridge {
  _ScriptedTorBridge(this.listNames, {Map<Uri, Object>? status})
    : status = status ?? const {};

  final Map<Uri, Object> listNames;
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
    final request = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
    final method = request['method'] as String;
    calls.add((uri, method));
    bodies.add(bodyBytes);
    final scripted = listNames[uri];
    if (scripted is Exception) throw scripted;
    if (scripted is _HttpReply) {
      return NetworkHttpResponse(
        statusCode: scripted.statusCode,
        bodyBytes: Uint8List.fromList(scripted.body),
      );
    }
    final Object? entry;
    if (method == 'status') {
      entry = status[uri] ?? _status();
    } else if (scripted is List<int> Function(int)) {
      entry = scripted((request['params'] as Map)['offset'] as int);
    } else {
      entry = scripted;
    }
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
