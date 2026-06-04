import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/voting/pir_snapshot_resolver.dart';

import 'fake_voting_http.dart';

void main() {
  test('empty endpoint list throws typed no-endpoints error', () async {
    final resolver = PirSnapshotResolver(httpClient: FakeVotingHttpClient());

    expect(
      resolver.resolve(endpoints: const [], expectedSnapshotHeight: 100),
      throwsA(isA<PirSnapshotNoEndpoints>()),
    );
  });

  test('matching endpoint is returned', () async {
    final endpoint = Uri.parse('https://pir.example/snapshot');
    final resolver = PirSnapshotResolver(
      httpClient: FakeVotingHttpClient(
        responses: {
          'https://pir.example/snapshot/root': {'height': 100},
        },
      ),
    );

    final result = await resolver.resolve(
      endpoints: [endpoint],
      expectedSnapshotHeight: 100,
    );

    expect(result.endpoint, endpoint);
    expect(result.diagnostics.single.status, PirSnapshotEndpointStatus.matched);
  });

  test('ignores guessed height aliases', () async {
    final endpoint = Uri.parse('https://pir.example/snapshot');
    final resolver = PirSnapshotResolver(
      httpClient: FakeVotingHttpClient(
        responses: {
          'https://pir.example/snapshot/root': {
            'root_height': 100,
            'rootHeight': 100,
            'snapshot_height': 100,
            'snapshotHeight': 100,
          },
        },
      ),
    );

    try {
      await resolver.resolve(
        endpoints: [endpoint],
        expectedSnapshotHeight: 100,
      );
      fail('expected no matching endpoint');
    } on PirSnapshotNoMatchingEndpoint catch (e) {
      expect(
        e.diagnostics.single.status,
        PirSnapshotEndpointStatus.missingHeight,
      );
    }
  });

  test('non-height fields do not conflict with canonical height', () async {
    final endpoint = Uri.parse('https://pir.example/snapshot');
    final resolver = PirSnapshotResolver(
      httpClient: FakeVotingHttpClient(
        responses: {
          'https://pir.example/snapshot/root': {
            'height': 100,
            'snapshot_height': 101,
          },
        },
      ),
    );

    final result = await resolver.resolve(
      endpoints: [endpoint],
      expectedSnapshotHeight: 100,
    );

    expect(result.endpoint, endpoint);
    expect(result.diagnostics.single.status, PirSnapshotEndpointStatus.matched);
  });

  test('non-integer height values are treated as malformed', () async {
    final endpoints = [
      Uri.parse('https://pir.example/fractional'),
      Uri.parse('https://pir.example/negative'),
      Uri.parse('https://pir.example/too-large'),
    ];
    final resolver = PirSnapshotResolver(
      httpClient: FakeVotingHttpClient(
        responses: {
          'https://pir.example/fractional/root': {'height': 100.5},
          'https://pir.example/negative/root': {'height': -1},
          'https://pir.example/too-large/root': {
            'height': '18446744073709551616',
          },
        },
      ),
    );

    try {
      await resolver.resolve(endpoints: endpoints, expectedSnapshotHeight: 100);
      fail('expected no matching endpoint');
    } on PirSnapshotNoMatchingEndpoint catch (e) {
      expect(e.diagnostics.map((diagnostic) => diagnostic.status), [
        PirSnapshotEndpointStatus.malformedJson,
        PirSnapshotEndpointStatus.malformedJson,
        PirSnapshotEndpointStatus.malformedJson,
      ]);
    }
  });

  test(
    'excludes behind ahead missing malformed non-200 and timeout endpoints',
    () async {
      final endpoints = [
        Uri.parse('https://pir.example/behind'),
        Uri.parse('https://pir.example/ahead'),
        Uri.parse('https://pir.example/missing'),
        Uri.parse('https://pir.example/malformed'),
        Uri.parse('https://pir.example/non-200'),
        Uri.parse('https://pir.example/timeout'),
        Uri.parse('https://pir.example/match'),
      ];
      final resolver = PirSnapshotResolver(
        httpClient: FakeVotingHttpClient(
          responses: {
            'https://pir.example/behind/root': {'height': 99},
            'https://pir.example/ahead/root': {'height': 101},
            'https://pir.example/missing/root': {'root': 'abc'},
            'https://pir.example/malformed/root': '{',
            'https://pir.example/non-200/root': textResponse(
              'down',
              statusCode: 500,
            ),
            'https://pir.example/timeout/root': timeoutResponse(),
            'https://pir.example/match/root': {'height': 100},
          },
        ),
      );

      final result = await resolver.resolve(
        endpoints: endpoints,
        expectedSnapshotHeight: 100,
      );

      expect(result.endpoint, endpoints.last);
      expect(result.diagnostics.map((diagnostic) => diagnostic.status), [
        PirSnapshotEndpointStatus.behind,
        PirSnapshotEndpointStatus.ahead,
        PirSnapshotEndpointStatus.missingHeight,
        PirSnapshotEndpointStatus.malformedJson,
        PirSnapshotEndpointStatus.nonSuccessStatus,
        PirSnapshotEndpointStatus.timeoutOrNetworkError,
        PirSnapshotEndpointStatus.matched,
      ]);
    },
  );

  test('all excluded throws typed no-match error with diagnostics', () async {
    final endpoints = [
      Uri.parse('https://pir.example/behind'),
      Uri.parse('https://pir.example/ahead'),
    ];
    final resolver = PirSnapshotResolver(
      httpClient: FakeVotingHttpClient(
        responses: {
          'https://pir.example/behind/root': {'height': 99},
          'https://pir.example/ahead/root': {'height': 101},
        },
      ),
    );

    try {
      await resolver.resolve(endpoints: endpoints, expectedSnapshotHeight: 100);
      fail('expected no matching endpoint');
    } on PirSnapshotNoMatchingEndpoint catch (e) {
      expect(e.expectedSnapshotHeight, 100);
      expect(e.diagnostics.length, 2);
      expect(e.diagnostics.first.status, PirSnapshotEndpointStatus.behind);
    }
  });
}
