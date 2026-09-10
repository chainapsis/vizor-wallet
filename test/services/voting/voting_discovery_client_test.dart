import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/voting/voting_discovery_client.dart';
import 'fake_voting_http.dart';

void main() {
  final now = DateTime.utc(2026, 9, 10);
  final endpoint = Uri.parse('https://example.com/custom/path');
  Map<String, dynamic> snapshot() => {
    'schemaVersion': 1,
    'scope': 'prod',
    'revision': 'sha256:${'a' * 64}',
    'checkedAt': now.toIso8601String(),
  };
  test('uses configured full URL and issues one bounded GET', () async {
    final http = FakeVotingHttpClient(
      responses: {endpoint.toString(): snapshot()},
    );
    final result = await VotingDiscoveryClient(http).fetch(endpoint, () => now);
    expect(result.revision, snapshot()['revision']);
    expect(http.requests, hasLength(1));
    expect(http.requests.single.uri, endpoint);
    expect(http.requests.single.timeout, const Duration(seconds: 5));
  });
  test('accepts IPv6 loopback HTTP and preserves the complete URL', () async {
    final local = Uri.parse('http://[::1]:8080/v1/voting/discovery/prod');
    final http = FakeVotingHttpClient(
      responses: {local.toString(): snapshot()},
    );
    await VotingDiscoveryClient(http).fetch(local, () => now);
    expect(http.requests.single.uri, local);
  });

  test('rejects non-loopback IPv6 HTTP before making a request', () async {
    final http = FakeVotingHttpClient();
    for (final host in ['2001:db8::1', '::', 'fe80::1']) {
      await expectLater(
        VotingDiscoveryClient(
          http,
        ).fetch(Uri.parse('http://[$host]:8080/discovery'), () => now),
        throwsFormatException,
      );
    }
    expect(http.requests, isEmpty);
  });

  test('rejects unsupported, malformed, stale and future responses', () async {
    for (final change in <Map<String, dynamic>>[
      {'scope': 'stage'},
      {'schemaVersion': 2},
      {'revision': 'wrong'},
      {'checkedAt': 'bad'},
      {
        'checkedAt': now
            .subtract(const Duration(minutes: 10))
            .toIso8601String(),
      },
      {'checkedAt': now.add(const Duration(minutes: 2)).toIso8601String()},
    ]) {
      final http = FakeVotingHttpClient(
        responses: {
          endpoint.toString(): {...snapshot(), ...change},
        },
      );
      await expectLater(
        VotingDiscoveryClient(http).fetch(endpoint, () => now),
        throwsFormatException,
      );
    }
  });
  test('503 is a failure, never an empty snapshot', () async {
    final http = FakeVotingHttpClient(
      responses: {
        endpoint.toString(): jsonResponse({
          'error': 'offline',
        }, statusCode: 503),
      },
    );
    await expectLater(
      VotingDiscoveryClient(http).fetch(endpoint, () => now),
      throwsStateError,
    );
    expect(http.requests, hasLength(1));
  });
  test('build define overrides the default URL', () {
    expect(
      votingDiscoveryUrl,
      const String.fromEnvironment(
        'VIZOR_VOTING_DISCOVERY_URL',
        defaultValue: 'https://functions.vizor.cash/v1/voting/discovery/prod',
      ),
    );
  });
  test(
    'stage validates its response scope and rejects production hints',
    () async {
      final http = FakeVotingHttpClient(
        responses: {
          endpoint.toString(): {...snapshot(), 'scope': 'stage'},
        },
      );
      await VotingDiscoveryClient(
        http,
      ).fetch(endpoint, () => now, scope: VotingDiscoveryScope.stage);
      await expectLater(
        VotingDiscoveryClient(http).fetch(endpoint, () => now),
        throwsFormatException,
      );
      final prod = FakeVotingHttpClient(
        responses: {endpoint.toString(): snapshot()},
      );
      await expectLater(
        VotingDiscoveryClient(
          prod,
        ).fetch(endpoint, () => now, scope: VotingDiscoveryScope.stage),
        throwsFormatException,
      );
    },
  );

  test('stage build define is independent from production URL', () {
    expect(
      votingDiscoveryStageUrl,
      const String.fromEnvironment(
        'VIZOR_VOTING_DISCOVERY_STAGE_URL',
        defaultValue: 'https://functions.vizor.cash/v1/voting/discovery/stage',
      ),
    );
  });
}
