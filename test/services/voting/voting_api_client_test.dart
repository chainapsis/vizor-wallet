import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/voting/voting_api_client.dart';

import 'fake_voting_http.dart';

void main() {
  const encodedRoundId = 'El5UdfZTsHTV9MNnMIUmlfNWQWwrbDBCUWqRLlv/3RE=';
  const hexRoundId =
      '125e5475f653b074d5f4c36730852695f356416c2b6c3042516a912e5bffdd11';

  test('composes vote-sdk URLs under shielded-vote v1', () async {
    final http = FakeVotingHttpClient(
      responses: {
        '/shielded-vote/v1/rounds': [
          {'vote_round_id': encodedRoundId, 'status': 'active'},
        ],
        '/shielded-vote/v1/round/$hexRoundId': {
          'round': {'vote_round_id': encodedRoundId, 'status': 'open'},
        },
        '/shielded-vote/v1/tally-results/$hexRoundId': {
          'results': [
            {'vote_round_id': encodedRoundId},
          ],
        },
        '/shielded-vote/v1/delegate-vote': {
          'tx_hash': 'delegation-tx',
          'code': 0,
          'log': '',
        },
        'https://helper.example/shielded-vote/v1/shares': {'status': 'ok'},
        'https://helper.example/shielded-vote/v1/share-status/$hexRoundId/share-1':
            {'share_id': 'share-1', 'status': 'pending'},
      },
    );
    final client = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: http,
    );

    final rounds = await client.listRounds();
    final status = await client.getRoundStatus(encodedRoundId);
    final tally = await client.getRoundTally(encodedRoundId);
    final delegation = await client.submitDelegation(
      submission: {'vote_round_id': encodedRoundId, 'proof': 'AQ=='},
    );
    await client.submitShare(
      roundId: encodedRoundId,
      serverUrl: Uri.parse('https://helper.example'),
      share: {'share_index': 0},
    );
    await client.getShareStatus(
      roundId: encodedRoundId,
      serverUrl: Uri.parse('https://helper.example'),
      shareId: 'share-1',
    );
    await client.resubmitShare(
      roundId: encodedRoundId,
      serverUrl: Uri.parse('https://helper.example'),
      shareId: 'share-1',
      share: {'share_index': 0},
    );

    expect(http.requests.map((request) => request.uri.path), [
      '/shielded-vote/v1/rounds',
      '/shielded-vote/v1/round/$hexRoundId',
      '/shielded-vote/v1/tally-results/$hexRoundId',
      '/shielded-vote/v1/delegate-vote',
      '/shielded-vote/v1/shares',
      '/shielded-vote/v1/share-status/$hexRoundId/share-1',
      '/shielded-vote/v1/shares',
    ]);
    expect(http.requests[4].uri.host, 'helper.example');
    expect(http.requests[5].uri.host, 'helper.example');
    expect(rounds.single.roundId, hexRoundId);
    expect(status.roundId, hexRoundId);
    expect(tally.roundId, hexRoundId);
    expect(delegation.txHash, 'delegation-tx');
    expect(delegation.code, 0);
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
            '/shielded-vote/v1/rounds/active': jsonResponse(
              {},
              statusCode: 404,
            ),
          },
        ),
      );
      await expectLater(missing.getActiveRoundStatus(), completion(isNull));
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
          '/shielded-vote/v1/rounds': [
            {'vote_round_id': encodedRoundId, 'status': 'active'},
          ],
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
        '/shielded-vote/v1/rounds': [
          {
            'vote_round_id': encodedRoundId,
            'title': 'Closed poll',
            'status': 3,
          },
          {'vote_round_id': hexRoundId, 'title': 'Active poll', 'status': 1},
        ],
      },
    );
    final client = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: http,
    );

    final rounds = await client.listRounds();

    expect(rounds.map((round) => round.status), ['3', '1']);
  });

  test('normalizes base64 round ids before composing status URLs', () async {
    final http = FakeVotingHttpClient(
      responses: {
        '/shielded-vote/v1/round/$hexRoundId': {
          'round': {'vote_round_id': encodedRoundId, 'status': 'active'},
        },
        '/shielded-vote/v1/tally-results/$hexRoundId': {
          'vote_round_id': encodedRoundId,
          'results': [],
        },
        '/shielded-vote/v1/share-status/$hexRoundId/share-1': {
          'share_id': 'share-1',
          'status': 'confirmed',
        },
      },
    );
    final client = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: http,
    );

    await client.getRoundStatus(encodedRoundId);
    await client.getRoundTally(encodedRoundId);
    await client.getShareStatus(
      roundId: encodedRoundId,
      serverUrl: Uri.parse('https://voting.valargroup.org'),
      shareId: 'share-1',
    );

    expect(http.requests.map((request) => request.uri.path), [
      '/shielded-vote/v1/round/$hexRoundId',
      '/shielded-vote/v1/tally-results/$hexRoundId',
      '/shielded-vote/v1/share-status/$hexRoundId/share-1',
    ]);
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
          'listRounds expected a JSON list or rounds field',
        ),
      ),
    );
  });

  test('list rounds rejects summaries without a routeable round id', () async {
    final http = FakeVotingHttpClient(
      responses: {
        '/shielded-vote/v1/rounds': [
          {'title': 'Poll', 'status': 'active'},
        ],
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

  test('fetches transaction confirmation events', () async {
    final http = FakeVotingHttpClient(
      responses: {
        '/shielded-vote/v1/tx/delegation-tx': {
          'height': 12,
          'code': 0,
          'log': '',
          'events': [
            {
              'type': 'delegate_vote',
              'attributes': [
                {'key': 'leaf_index', 'value': '3'},
              ],
            },
          ],
        },
      },
    );
    final client = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: http,
    );

    final confirmation = await client.getTxConfirmation('delegation-tx');

    expect(confirmation?.height, 12);
    expect(confirmation?.event('delegate_vote')?.attribute('leaf_index'), '3');
  });

  test('retries transient broadcast errors', () async {
    final delays = <Duration>[];
    final http = FakeVotingHttpClient(
      responses: {
        '/shielded-vote/v1/cast-vote': SequentialVotingHttpResponses([
          jsonResponse({'error': 'gateway'}, statusCode: 503),
          {'tx_hash': 'vote-tx', 'code': 0, 'log': ''},
        ]),
      },
    );
    final client = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: http,
      broadcastRetryDelays: const [Duration(milliseconds: 1)],
      delay: (delay) async => delays.add(delay),
    );

    final result = await client.submitVoteCommitment(
      commitment: {'vote_round_id': encodedRoundId},
    );

    expect(result.txHash, 'vote-tx');
    expect(http.requests.map((request) => request.uri.path), [
      '/shielded-vote/v1/cast-vote',
      '/shielded-vote/v1/cast-vote',
    ]);
    expect(delays, const [Duration(milliseconds: 1)]);
  });

  test('rejects malformed successful broadcast responses', () async {
    Future<Object> submit(Object response) {
      final http = FakeVotingHttpClient(
        responses: {'/shielded-vote/v1/cast-vote': response},
      );
      return VotingApiClient(
        baseUrl: Uri.parse('https://voting.valargroup.org'),
        httpClient: http,
      ).submitVoteCommitment(commitment: {'vote_round_id': encodedRoundId});
    }

    await expectLater(
      submit({'tx_hash': 'vote-tx', 'log': ''}),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Missing required int: code',
        ),
      ),
    );
    await expectLater(
      submit({'tx_hash': '', 'code': 0, 'log': ''}),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Missing required string: tx_hash',
        ),
      ),
    );
  });

  test(
    'retries transient delegate timeout but not deterministic rejection',
    () async {
      final http = FakeVotingHttpClient(
        responses: {
          '/shielded-vote/v1/delegate-vote': SequentialVotingHttpResponses([
            TimeoutException('timed out'),
            {'tx_hash': 'delegation-tx', 'code': 0, 'log': ''},
            jsonResponse({
              'tx_hash': '',
              'code': 7,
              'log': 'rejected',
            }, statusCode: 422),
          ]),
        },
      );
      final client = VotingApiClient(
        baseUrl: Uri.parse('https://voting.valargroup.org'),
        httpClient: http,
        broadcastRetryDelays: const [Duration.zero],
        delay: (_) async {},
      );

      final retried = await client.submitDelegation(
        submission: {'vote_round_id': encodedRoundId},
      );
      final rejected = await client.submitDelegation(
        submission: {'vote_round_id': encodedRoundId},
      );

      expect(retried.txHash, 'delegation-tx');
      expect(rejected.code, 7);
      expect(http.requests.length, 3);
    },
  );

  test('share request payloads preserve service JSON field names', () async {
    final http = FakeVotingHttpClient(
      responses: {
        'https://helper.example/shielded-vote/v1/shares': {'status': 'ok'},
      },
    );
    final client = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: http,
    );

    await client.submitShare(
      roundId: encodedRoundId,
      serverUrl: Uri.parse('https://helper.example'),
      share: {'share_index': 7, 'vote_round_id': 'bad-override'},
    );

    expect(http.requests.single.body, {
      'share_index': 7,
      'vote_round_id': hexRoundId,
    });
    expect(http.requests.single.timeout, const Duration(seconds: 5));
  });
}
