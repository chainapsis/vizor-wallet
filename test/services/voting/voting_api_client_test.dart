import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/network/network_http_client.dart';
import 'package:zcash_wallet/src/rust/api/network_privacy.dart'
    as rust_network_privacy;
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/services/voting/voting_api_client.dart';
import 'package:zcash_wallet/src/services/voting/voting_http.dart';
import 'package:zcash_wallet/src/services/voting/voting_retry.dart';

import 'fake_voting_http.dart';

void main() {
  const encodedRoundId = 'El5UdfZTsHTV9MNnMIUmlfNWQWwrbDBCUWqRLlv/3RE=';
  const hexRoundId =
      '125e5475f653b074d5f4c36730852695f356416c2b6c3042516a912e5bffdd11';
  const otherHexRoundId =
      'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

  test('composes vote-sdk URLs under shielded-vote v1', () async {
    final http = FakeVotingHttpClient(
      responses: {
        '/shielded-vote/v1/rounds': {
          'rounds': [
            {'vote_round_id': encodedRoundId, 'status': 'active'},
          ],
        },
        '/shielded-vote/v1/round/$hexRoundId': {
          'round': {'vote_round_id': encodedRoundId, 'status': 'open'},
        },
        '/shielded-vote/v1/tally-results/$hexRoundId': {
          'results': [
            {'vote_round_id': encodedRoundId},
          ],
        },
      },
    );
    final client = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: http,
    );

    final rounds = await client.listRounds();
    final status = await client.getRoundStatus(encodedRoundId);
    final tally = await client.getRoundTally(encodedRoundId);

    expect(http.requests.map((request) => request.uri.path), [
      '/shielded-vote/v1/rounds',
      '/shielded-vote/v1/round/$hexRoundId',
      '/shielded-vote/v1/tally-results/$hexRoundId',
    ]);
    expect(rounds.single.roundId, hexRoundId);
    expect(status.roundId, hexRoundId);
    expect(tally.roundId, hexRoundId);
  });

  test(
    'fetches active round and treats missing active round as null',
    () async {
      final http = FakeVotingHttpClient(
        responses: {
          '/shielded-vote/v1/rounds/active': {
            'round': {'vote_round_id': encodedRoundId, 'status': 'active'},
          },
        },
      );
      final client = VotingApiClient(
        baseUrl: Uri.parse('https://voting.valargroup.org'),
        httpClient: http,
      );

      final active = await client.getActiveRoundStatus();

      expect(active?.roundId, hexRoundId);
      expect(active?.status, 'active');

      final missing = VotingApiClient(
        baseUrl: Uri.parse('https://voting.valargroup.org'),
        httpClient: FakeVotingHttpClient(
          responses: {
            '/shielded-vote/v1/rounds/active': {'round': null},
          },
        ),
      );
      await expectLater(missing.getActiveRoundStatus(), completion(isNull));

      final notFound = VotingApiClient(
        baseUrl: Uri.parse('https://voting.valargroup.org'),
        httpClient: FakeVotingHttpClient(
          responses: {
            '/shielded-vote/v1/rounds/active': jsonResponse({
              'error': 'not found',
            }, statusCode: 404),
          },
        ),
      );
      await expectLater(notFound.getActiveRoundStatus(), completion(isNull));
    },
  );

  test(
    'fetches proposal tally from the vote-sdk proposal tally endpoint',
    () async {
      final http = FakeVotingHttpClient(
        responses: {
          '/shielded-vote/v1/tally/$hexRoundId/2': {
            'tally': {'0': 'support-ciphertext', '1': 'oppose-ciphertext'},
          },
        },
      );
      final client = VotingApiClient(
        baseUrl: Uri.parse('https://voting.valargroup.org'),
        httpClient: http,
      );

      final tally = await client.getProposalTally(hexRoundId, 2);

      expect(tally.roundId, hexRoundId);
      expect(tally.rawJson['tally'], {
        '0': 'support-ciphertext',
        '1': 'oppose-ciphertext',
      });
      expect(
        http.requests.single.uri.path,
        '/shielded-vote/v1/tally/$hexRoundId/2',
      );
    },
  );

  test(
    'normalizes base64 vote_round_id payloads to routeable hex ids',
    () async {
      final http = FakeVotingHttpClient(
        responses: {
          '/shielded-vote/v1/rounds': {
            'rounds': [
              {'vote_round_id': encodedRoundId, 'status': 'active'},
            ],
          },
          '/shielded-vote/v1/round/$hexRoundId': {
            'round': {'vote_round_id': encodedRoundId, 'status': 'active'},
          },
          '/shielded-vote/v1/tally-results/$hexRoundId': {
            'results': [
              {'vote_round_id': encodedRoundId},
            ],
          },
        },
      );
      final client = VotingApiClient(
        baseUrl: Uri.parse('https://voting.valargroup.org'),
        httpClient: http,
      );

      final rounds = await client.listRounds();
      final status = await client.getRoundStatus(rounds.single.roundId);
      final tally = await client.getRoundTally(rounds.single.roundId);

      expect(rounds.single.roundId, hexRoundId);
      expect(status.roundId, hexRoundId);
      expect(tally.roundId, hexRoundId);
      expect(http.requests.map((request) => request.uri.path), [
        '/shielded-vote/v1/rounds',
        '/shielded-vote/v1/round/$hexRoundId',
        '/shielded-vote/v1/tally-results/$hexRoundId',
      ]);
    },
  );

  test('preserves numeric round status codes as strings', () async {
    final http = FakeVotingHttpClient(
      responses: {
        '/shielded-vote/v1/rounds': {
          'rounds': [
            {
              'vote_round_id': encodedRoundId,
              'title': 'Closed poll',
              'status': 3,
            },
            {'vote_round_id': hexRoundId, 'title': 'Active poll', 'status': 1},
          ],
        },
      },
    );
    final client = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: http,
    );

    final rounds = await client.listRounds();

    expect(rounds.map((round) => round.status), ['3', '1']);
  });

  test('list rounds treats proto3 empty object as no rounds', () async {
    final http = FakeVotingHttpClient(
      responses: {'/shielded-vote/v1/rounds': <String, dynamic>{}},
    );
    final client = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: http,
    );

    await expectLater(client.listRounds(), completion(isEmpty));
  });

  test('list rounds rejects historical bare list responses', () async {
    final http = FakeVotingHttpClient(
      responses: {
        '/shielded-vote/v1/rounds': [
          {'vote_round_id': encodedRoundId, 'status': 'active'},
        ],
      },
    );
    final client = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: http,
    );

    await expectLater(client.listRounds(), throwsA(isA<FormatException>()));
  });

  test('list rounds rejects nonempty objects without rounds', () async {
    final http = FakeVotingHttpClient(
      responses: {
        '/shielded-vote/v1/rounds': {'error': 'db corrupt'},
      },
    );
    final client = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: http,
    );

    await expectLater(
      client.listRounds(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'listRounds expected a rounds field',
        ),
      ),
    );
  });

  test('list rounds rejects summaries without a routeable round id', () async {
    final http = FakeVotingHttpClient(
      responses: {
        '/shielded-vote/v1/rounds': {
          'rounds': [
            {'title': 'Poll', 'status': 'active'},
          ],
        },
      },
    );
    final client = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: http,
    );

    await expectLater(
      client.listRounds(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Missing required string: vote_round_id',
        ),
      ),
    );
  });

  test('rejects malformed round ids before composing request URLs', () async {
    final http = FakeVotingHttpClient();
    final client = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: http,
    );

    await expectLater(
      client.getRoundStatus('round-1'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Invalid vote_round_id: expected 64 hex chars or 32-byte base64',
        ),
      ),
    );
    expect(http.requests, isEmpty);
  });

  test('round status requires the live vote-sdk round envelope', () async {
    final client = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: FakeVotingHttpClient(
        responses: {
          '/shielded-vote/v1/round/$hexRoundId': {
            'vote_round_id': hexRoundId,
            'status': 'active',
          },
        },
      ),
    );

    await expectLater(
      client.getRoundStatus(hexRoundId),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Expected round field',
        ),
      ),
    );
  });

  test('rejects round-scoped responses with mismatched round ids', () async {
    final statusClient = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: FakeVotingHttpClient(
        responses: {
          '/shielded-vote/v1/round/$hexRoundId': {
            'round': {'vote_round_id': otherHexRoundId, 'status': 'active'},
          },
        },
      ),
    );
    await expectLater(
      statusClient.getRoundStatus(hexRoundId),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'getRoundStatus response round id mismatch',
        ),
      ),
    );

    final tallyClient = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: FakeVotingHttpClient(
        responses: {
          '/shielded-vote/v1/tally-results/$hexRoundId': {
            'results': [
              {'vote_round_id': otherHexRoundId},
            ],
          },
        },
      ),
    );
    await expectLater(
      tallyClient.getRoundTally(hexRoundId),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'getRoundTally response round id mismatch',
        ),
      ),
    );

    final tallyEnvelopeClient = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: FakeVotingHttpClient(
        responses: {
          '/shielded-vote/v1/tally-results/$hexRoundId': {
            'vote_round_id': otherHexRoundId,
            'results': [],
          },
        },
      ),
    );
    await expectLater(
      tallyEnvelopeClient.getRoundTally(hexRoundId),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'getRoundTally response round id mismatch',
        ),
      ),
    );

    final proposalTallyClient = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: FakeVotingHttpClient(
        responses: {
          '/shielded-vote/v1/tally/$hexRoundId/2': {
            'vote_round_id': otherHexRoundId,
            'tally': {'0': 'ciphertext'},
          },
        },
      ),
    );
    await expectLater(
      proposalTallyClient.getProposalTally(hexRoundId, 2),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'getProposalTally response round id mismatch',
        ),
      ),
    );
  });

  test('retries transient round reads for 500 responses', () async {
    final delays = <Duration>[];
    final http = FakeVotingHttpClient(
      responses: {
        '/shielded-vote/v1/rounds': SequentialVotingHttpResponses([
          jsonResponse({'error': 'upstream'}, statusCode: 500),
          {'rounds': const []},
        ]),
      },
    );
    final client = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: http,
      readRetryPolicy: VotingRetryPolicy.transientHttp(
        name: 'test-read-retry',
        delays: const [Duration(milliseconds: 2)],
      ),
      delay: (delay) async => delays.add(delay),
    );

    final rounds = await client.listRounds();

    expect(rounds, isEmpty);
    expect(http.requests.length, 2);
    expect(delays, const [Duration(milliseconds: 2)]);
  });

  test('fails over chain reads to secondary vote server', () async {
    final primary = Uri.parse('https://vote-primary.example');
    final secondary = Uri.parse('https://vote-secondary.example');
    final http = FakeVotingHttpClient(
      responses: {
        'https://vote-primary.example/shielded-vote/v1/round/$hexRoundId':
            timeoutResponse(),
        'https://vote-secondary.example/shielded-vote/v1/round/$hexRoundId': {
          'round': {'vote_round_id': encodedRoundId, 'status': 'active'},
        },
      },
    );
    final client = VotingApiClient(
      baseUrl: primary,
      fallbackBaseUrls: [secondary],
      httpClient: http,
      readRetryPolicy: VotingRetryPolicy.transientHttp(
        name: 'test-failover-read',
        delays: const [],
      ),
      delay: (_) async {},
    );

    final status = await client.getRoundStatus(hexRoundId);

    expect(status.roundId, hexRoundId);
    expect(http.requests.map((request) => request.uri.host), [
      'vote-primary.example',
      'vote-secondary.example',
    ]);
  });

  group('over Tor', () {
    final rust = _ExitLookupFailureRustApi(
      failingHost: 'vote-primary.example',
      body: jsonEncode({
        'round': {'vote_round_id': encodedRoundId, 'status': 'active'},
      }),
    );
    setUpAll(() => RustLib.initMock(api: rust));
    tearDownAll(RustLib.dispose);

    test(
      'fails over round reads when an exit cannot resolve the primary',
      () async {
        final network = NetworkHttpClient(
          torDesired: () => true,
          torBootstrapping: () => false,
        );
        addTearDown(network.close);
        final client = VotingApiClient(
          baseUrl: Uri.parse('https://vote-primary.example'),
          fallbackBaseUrls: [Uri.parse('https://vote-secondary.example')],
          httpClient: DartIoVotingHttpClient(networkClient: network),
          readRetryPolicy: VotingRetryPolicy.transientHttp(
            name: 'test-tor-failover-read',
            delays: const [],
          ),
          delay: (_) async {},
        );

        final status = await client.getRoundStatus(hexRoundId);

        expect(status.roundId, hexRoundId);
        expect(rust.hosts, ['vote-primary.example', 'vote-secondary.example']);
      },
    );
  });
}

/// Rust Tor bridge whose exit relay cannot resolve [failingHost] and that
/// answers every other GET with [body].
class _ExitLookupFailureRustApi implements RustLibApi {
  _ExitLookupFailureRustApi({required this.failingHost, required this.body});

  final String failingHost;
  final String body;
  final hosts = <String>[];

  @override
  Future<rust_network_privacy.NetworkHttpResponse>
  crateApiNetworkPrivacyTorHttpGet({
    required String url,
    required List<rust_network_privacy.NetworkHttpHeader> headers,
    BigInt? timeoutMilliseconds,
    BigInt? requestId,
    BigInt? maxBodyBytes,
  }) async {
    final host = Uri.parse(url).host;
    hosts.add(host);
    if (host == failingHost) {
      throw 'Tor HTTP connection could not be opened: Tor error: tor: remote '
          'hostname lookup failure: Protocol error while launching a data '
          'stream';
    }
    return rust_network_privacy.NetworkHttpResponse(
      statusCode: 200,
      headers: const [],
      body: utf8.encode(body),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
