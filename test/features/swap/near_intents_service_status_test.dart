import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/network/network_http_client.dart';
import 'package:zcash_wallet/src/features/swap/domain/near_intents_service_status.dart';
import 'package:zcash_wallet/src/features/swap/integrations/near_intents/near_intents_service_status_client.dart';

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
}) => NearIntentsServiceStatus(
  now: now ?? _now,
  incidents: incidents,
  maintenance: maintenance,
  incidentsFetchedAt: now ?? _now,
  maintenanceFetchedAt: now ?? _now,
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
    final snapshot = NearIntentsServiceStatus(
      now: _now.add(nearIntentsStatusFreshness),
      incidents: [
        const NearIntentsServiceIssue(chains: {'*'}),
      ],
      incidentsFetchedAt: _now,
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
    'HTTP client uses the two public URLs, no auth, cancellation and limits',
    () async {
      final transport = _Transport();
      final client = NearIntentsServiceStatusClient(client: transport);
      addTearDown(client.close);
      await client.loadIncidents();
      await client.loadMaintenance();
      expect(transport.urls, [
        'https://shield.chaindefuser.com/public/status',
        'https://partners.near-intents.org/api/shield/public/maintenance-modes',
      ]);
      transport.status = 403;
      await expectLater(client.loadIncidents(), throwsA(isA<Exception>()));
      transport.status = 200;
      transport.badJson = true;
      await expectLater(client.loadMaintenance(), throwsFormatException);
    },
  );
}

class _Transport extends NetworkHttpClient {
  _Transport() : super(torDesired: () => false);
  final urls = <String>[];
  int status = 200;
  bool badJson = false;
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
    expect(method, 'GET');
    expect(headers, {'accept': 'application/json'});
    expect(timeout, const Duration(seconds: 15));
    expect(maxBodyBytes, 256 * 1024);
    return NetworkHttpResponse(
      statusCode: status,
      bodyBytes: Uint8List.fromList(
        utf8.encode(
          badJson
              ? 'not json'
              : uri.host == 'shield.chaindefuser.com'
              ? '{"activeIncidentCount":0,"activeIncidents":[]}'
              : '[]',
        ),
      ),
    );
  }
}
