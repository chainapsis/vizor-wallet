import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/network/network_http_client.dart';
import 'package:zcash_wallet/src/rust/api/network_privacy.dart' as rust;
import 'package:zcash_wallet/src/features/swap/domain/near_intents_service_status.dart';
import 'package:zcash_wallet/src/features/swap/integrations/near_intents/near_intents_service_status_client.dart';

import 'support/service_status_fixture.dart';

final _now = DateTime.utc(2026, 11, 2, 13);
Map<String, Object?> _window({
  String chain = '*',
  String direction = '*',
  String status = 'active',
  String start = '2026-11-02T12:00:00Z',
  String finish = '2026-11-02T15:00:00Z',
}) => {
  'status': status,
  'scopes': [
    {'scopeType': 'chain', 'scopeValue': chain},
  ],
  'direction': direction,
  'startsAt': start,
  'finishesAt': finish,
};
Map<String, Object?> _incident({
  String chain = '*',
  String type = 'chain',
  String status = 'active',
}) => {'scopeType': type, 'scopeValue': chain, 'status': status};
NearIntentsServiceStatus _status({
  List<NearIntentsServiceIssue> incidents = const [],
  List<NearIntentsServiceIssue> maintenance = const [],
  DateTime? now,
}) => serviceStatusSnapshot(
  serverTime: now ?? _now,
  incidents: incidents,
  maintenance: maintenance,
);

void main() {
  test(
    'incident IDs and schedule starts identify notices independently of ETA updates',
    () {
      final first = NearIntentsServiceIssue(chains: {'eth'}, id: 'incident-A');
      final second = NearIntentsServiceIssue(chains: {'eth'}, id: 'incident-B');
      expect(first.noticeKey, isNot(second.noticeKey));
      final windows = parseNearIntentsMaintenance([
        _window(),
        _window(finish: '2026-11-02T16:00:00Z'),
      ]);
      expect(windows[0].noticeKey, windows[1].noticeKey);
      expect(
        _status(
          maintenance: parseNearIntentsMaintenance([
            _window(status: 'scheduled'),
          ]),
        ).noticeFor(inputChain: 'zec', outputChain: 'eth'),
        isNull,
      );
      for (final status in ['active', 'scheduled']) {
        final future = _status(
          maintenance: parseNearIntentsMaintenance([
            _window(status: status, start: '2026-11-02T14:00:00Z'),
          ]),
        );
        expect(future.noticeFor(inputChain: 'zec', outputChain: 'eth'), isNull);
      }
    },
  );
  test('only active records from the public feed produce incidents', () {
    final issues = parseNearIntentsIncidents({
      'activeIncidentCount': 4,
      'activeIncidents': [
        _incident(chain: 'ETH'),
        _incident(type: 'bridge'),
        _incident(status: 'resolved'),
        _incident(chain: 'zec'),
      ],
      'recentlyResolved': [_incident()],
      'futureOptionalField': true,
    });
    expect(issues.length, 2);
    expect(issues.first.chains, {'eth'});
    expect(issues.first.startsAt, isNull);
    expect(issues.first.finishesAt, isNull);
  });
  test('invalid public responses never become a global incident', () {
    for (final json in [
      null,
      [],
      {'activeIncidentCount': 2, 'activeIncidents': []},
      {
        'activeIncidentCount': 1,
        'activeIncidents': [
          {'status': 'active'},
        ],
      },
    ]) {
      expect(() => parseNearIntentsIncidents(json), throwsFormatException);
    }
  });
  test('wildcard applies to every pair, unrelated chain is excluded', () {
    final global = _status(
      incidents: [
        const NearIntentsServiceIssue(chains: {'*'}),
      ],
    );
    for (final pair in [('zec', 'eth'), ('bsc', 'zec'), ('zec', 'sol')]) {
      expect(
        global.noticeFor(inputChain: pair.$1, outputChain: pair.$2),
        isNotNull,
      );
    }
    final eth = _status(
      incidents: parseNearIntentsIncidents({
        'activeIncidentCount': 1,
        'activeIncidents': [_incident(chain: 'eth')],
      }),
    );
    expect(eth.noticeFor(inputChain: 'zec', outputChain: 'eth'), isNotNull);
    expect(eth.noticeFor(inputChain: 'eth', outputChain: 'zec'), isNotNull);
    expect(eth.noticeFor(inputChain: 'zec', outputChain: 'bsc'), isNull);
  });
  test('maintenance direction distinguishes deposits and withdrawals', () {
    for (final direction in ['deposit', 'withdraw']) {
      final status = _status(
        maintenance: parseNearIntentsMaintenance([
          _window(chain: 'eth', direction: direction),
        ]),
      );
      expect(
        status.noticeFor(inputChain: 'eth', outputChain: 'zec') != null,
        direction == 'deposit',
      );
      expect(
        status.noticeFor(inputChain: 'zec', outputChain: 'eth') != null,
        direction == 'withdraw',
      );
    }
    final zec = _status(
      maintenance: parseNearIntentsMaintenance([_window(chain: 'zec')]),
    );
    expect(zec.noticeFor(inputChain: 'zec', outputChain: 'eth'), isNotNull);
    expect(zec.noticeFor(inputChain: 'eth', outputChain: 'zec'), isNotNull);
  });
  test(
    'future windows stay hidden until their start, then expire at their end',
    () {
      final windows = parseNearIntentsMaintenance([
        _window(
          status: 'active',
          start: '2026-11-02T16:00:00Z',
          finish: '2026-11-02T17:00:00Z',
        ),
      ]);
      NearIntentsServiceNoticeData? notice(DateTime now) => _status(
        maintenance: windows,
        now: now,
      ).noticeFor(inputChain: 'zec', outputChain: 'eth');
      expect(notice(_now.subtract(const Duration(microseconds: 1))), isNull);
      expect(notice(_now), isNull);
      expect(notice(DateTime.utc(2026, 11, 2, 16)), isNotNull);
      expect(notice(DateTime.utc(2026, 11, 2, 17)), isNull);
    },
  );
  test('cancelled, finished, unknown scopes and directions are ignored', () {
    expect(
      parseNearIntentsMaintenance([
        {'status': 'cancelled'},
        {'status': 'finished'},
        {'status': 'new-status'},
        _window(direction: 'unrecognized'),
        {
          ..._window(),
          'scopes': [
            {'scopeType': 'bridge', 'scopeValue': '*'},
          ],
        },
      ]),
      isEmpty,
    );
  });
  test('malformed or zone-less times reject the feed', () {
    for (final start in [
      '2026-11-02T12:00:00',
      '2026-02-31T12:00:00Z',
      '2026-11-02T25:00:00Z',
      '2026-11-02T12:00:00+25:00',
      '2026-11-02T16:00:00Z',
      'garbage',
    ]) {
      expect(
        () => parseNearIntentsMaintenance([_window(start: start)]),
        throwsFormatException,
      );
    }
  });
  test('expired feed is hidden even if it contains a global incident', () {
    final snapshot = serviceStatusSnapshot(
      serverTime: _now,
      elapsed: nearIntentsStatusFreshness,
      incidents: [
        const NearIntentsServiceIssue(chains: {'*'}),
      ],
    );
    expect(snapshot.noticeFor(inputChain: 'zec', outputChain: 'eth'), isNull);
  });
  test(
    'ongoing incidents outlive ended maintenance and exclude future schedules',
    () {
      final snapshot = _status(
        incidents: [
          const NearIntentsServiceIssue(chains: {'*'}),
        ],
        maintenance: parseNearIntentsMaintenance([
          _window(
            status: 'scheduled',
            start: '2026-11-02T15:00:00Z',
            finish: '2026-11-02T17:00:00Z',
          ),
          _window(finish: '2026-11-02T13:00:00Z'),
        ]),
      );
      final notice = snapshot.noticeFor(inputChain: 'zec', outputChain: 'eth')!;
      expect(notice.maintenanceOnly, isFalse);
      expect(notice.issues.length, 1);
      expect(notice.issues.single.isMaintenance, isFalse);
    },
  );
  test(
    'server time and elapsed time govern boundaries even with a very different device date',
    () {
      for (final server in [DateTime.utc(2000), DateTime.utc(2100)]) {
        final feed = NearIntentsServiceObservation(
          receivedAt: const Duration(hours: 30),
          feed: NearIntentsServiceFeed(
            serverTime: server,
            issues: [
              NearIntentsServiceIssue(
                chains: {'*'},
                startsAt: server.add(const Duration(seconds: 2)),
                finishesAt: server.add(const Duration(seconds: 4)),
              ),
            ],
          ),
        );
        NearIntentsServiceStatus at(int seconds) => NearIntentsServiceStatus(
          elapsed: const Duration(hours: 30) + Duration(seconds: seconds),
          maintenanceFeed: feed,
        );
        expect(at(0).noticeFor(inputChain: 'zec', outputChain: 'eth'), isNull);
        expect(at(0).nextUpdateIn, const Duration(seconds: 2));
        expect(
          at(2).noticeFor(inputChain: 'zec', outputChain: 'eth'),
          isNotNull,
        );
        expect(at(2).nextUpdateIn, const Duration(seconds: 2));
        expect(at(4).noticeFor(inputChain: 'zec', outputChain: 'eth'), isNull);
        expect(at(4).nextUpdateIn, const Duration(seconds: 56));
        expect(at(60).nextUpdateIn, isNull);
      }
    },
  );
  test('feeds retain independent server anchors and monotonic expiry', () {
    final first = NearIntentsServiceObservation(
      receivedAt: Duration.zero,
      feed: NearIntentsServiceFeed(
        serverTime: DateTime.utc(2100),
        issues: const [
          NearIntentsServiceIssue(id: 'incident', chains: {'*'}),
        ],
      ),
    );
    final server = DateTime.utc(2000);
    final second = NearIntentsServiceObservation(
      receivedAt: const Duration(seconds: 50),
      feed: NearIntentsServiceFeed(
        serverTime: server,
        issues: [
          NearIntentsServiceIssue(
            id: 'window',
            chains: {'*'},
            startsAt: server.subtract(const Duration(seconds: 1)),
            finishesAt: server.add(const Duration(hours: 1)),
          ),
        ],
      ),
    );
    NearIntentsServiceStatus at(int seconds) => NearIntentsServiceStatus(
      elapsed: Duration(seconds: seconds),
      incidentFeed: first,
      maintenanceFeed: second,
    );
    expect(
      at(50).noticeFor(inputChain: 'zec', outputChain: 'eth')!.issues,
      hasLength(2),
    );
    expect(at(50).nextUpdateIn, const Duration(seconds: 10));
    expect(
      at(60).noticeFor(inputChain: 'zec', outputChain: 'eth')!.issues.single.id,
      'window',
    );
    expect(at(60).nextUpdateIn, const Duration(seconds: 50));
    expect(at(110).noticeFor(inputChain: 'zec', outputChain: 'eth'), isNull);
    expect(at(110).nextUpdateIn, isNull);
    expect(at(-1).noticeFor(inputChain: 'zec', outputChain: 'eth'), isNull);
  });
  test(
    'missing, ambiguous or malformed server time rejects either feed without Date fallback',
    () async {
      final transport = _Transport();
      final client = NearIntentsServiceStatusClient(client: transport);
      addTearDown(client.close);
      for (final headers in <List<String>?>[
        null,
        [],
        [''],
        ['garbage'],
        ['2026-11-04T10:00:00'],
        ['2026-11-04T10:00:00+09:00'],
        ['2026-02-31T10:00:00.000Z'],
        ['2026-11-04T25:00:00.000Z'],
        ['2026-11-04T10:00:00.000Z', '2026-11-04T10:00:00.000Z'],
      ]) {
        transport.serverTimeHeaders = headers;
        for (final load in [client.loadIncidents, client.loadMaintenance]) {
          await expectLater(load(), throwsFormatException);
        }
      }
    },
  );
  test(
    'Tor-selected transport preserves the server time header through Rust decoding',
    () async {
      final bridge = _ServerTimeTorBridge();
      final network = NetworkHttpClient(
        torDesired: () => true,
        torBootstrapping: () => false,
        torBridge: bridge,
      );
      final client = NearIntentsServiceStatusClient(client: network);
      addTearDown(client.close);
      for (final load in [client.loadIncidents, client.loadMaintenance]) {
        final feed = await load();
        expect(feed.serverTime, DateTime.utc(2100, 1, 1, 10));
        expect(feed.issues, isEmpty);
      }
      expect(bridge.calls, 2);
    },
  );
  test(
    'HTTP client uses the Vizor proxy without auth or direct fallbacks',
    () async {
      final transport = _Transport();
      final client = NearIntentsServiceStatusClient(client: transport);
      addTearDown(client.close);
      final cancel = Completer<void>();
      final incidents = await client.loadIncidents(cancelSignal: cancel.future);
      expect(incidents.issues, isEmpty);
      expect(incidents.serverTime, _now);
      expect(
        (await client.loadMaintenance(cancelSignal: cancel.future)).issues,
        isEmpty,
      );
      expect(transport.urls, [
        'https://functions.vizor.cash/api/near-intents/shield/status',
        'https://functions.vizor.cash/api/near-intents/shield/maintenance-modes',
      ]);
      expect(transport.cancelSignals, [cancel.future, cancel.future]);
      for (final status in [403, 502, 504]) {
        transport.status = status;
        for (final load in [client.loadIncidents, client.loadMaintenance]) {
          final callsBefore = transport.urls.length;
          await expectLater(load(), throwsA(isA<HttpException>()));
          expect(transport.urls.length, callsBefore + 1);
        }
      }
      transport.status = 200;
      transport.badJson = true;
      for (final load in [client.loadIncidents, client.loadMaintenance]) {
        final callsBefore = transport.urls.length;
        await expectLater(load(), throwsFormatException);
        expect(transport.urls.length, callsBefore + 1);
      }
      expect(
        transport.urls,
        everyElement(
          startsWith('https://functions.vizor.cash/api/near-intents/shield/'),
        ),
      );
    },
  );
}

class _Transport extends NetworkHttpClient {
  _Transport() : super(torDesired: () => false);
  final urls = <String>[];
  final cancelSignals = <Future<void>?>[];
  int status = 200;
  bool badJson = false;
  List<String>? serverTimeHeaders = const ['2026-11-02T13:00:00.000Z'];
  @override
  Future<NetworkHttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int> bodyBytes = const [],
    Duration? timeout,
    Future<void>? cancelSignal,
    int? maxBodyBytes,
    int maxRedirects = 5,
  }) async {
    urls.add(uri.toString());
    cancelSignals.add(cancelSignal);
    expect(method, 'GET');
    expect(headers, {'accept': 'application/json'});
    expect(timeout, const Duration(seconds: 15));
    expect(maxBodyBytes, 256 * 1024);
    return NetworkHttpResponse(
      statusCode: status,
      headers: {
        'date': ['Wed, 04 Nov 2026 10:00:00 GMT'],
        'x-vizor-server-time': ?serverTimeHeaders,
      },
      bodyBytes: Uint8List.fromList(
        utf8.encode(
          badJson
              ? 'not json'
              : switch (uri.path) {
                  '/api/near-intents/shield/status' =>
                    '{"activeIncidentCount":0,"activeIncidents":[]}',
                  '/api/near-intents/shield/maintenance-modes' => '[]',
                  _ => throw StateError('Unexpected service status URL: $uri'),
                },
        ),
      ),
    );
  }
}

class _ServerTimeTorBridge implements TorHttpBridge {
  int calls = 0;
  @override
  Future<NetworkHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration? timeout,
    Future<void>? cancelSignal,
    int? maxBodyBytes,
  }) async {
    calls++;
    return networkHttpResponseFromRust(
      rust.NetworkHttpResponse(
        statusCode: 200,
        headers: const [
          rust.NetworkHttpHeader(
            name: 'X-Vizor-Server-Time',
            value: '2100-01-01T10:00:00.000Z',
          ),
        ],
        body: Uint8List.fromList(
          utf8.encode(
            uri.path.endsWith('/status')
                ? '{"activeIncidentCount":0,"activeIncidents":[]}'
                : '[]',
          ),
        ),
      ),
    );
  }

  @override
  Future<NetworkHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
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
