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
          {'vote_round_id': 'round-1', 'status': 'active'},
        ],
        '/shielded-vote/v1/round/round-1': {
          'round': {'vote_round_id': 'round-1', 'status': 'open'},
        },
        '/shielded-vote/v1/tally-results/round-1': {
          'vote_round_id': 'round-1',
          'results': [],
        },
        '/shielded-vote/v1/delegate-vote': {
          'tx_hash': 'delegation-tx',
          'code': 0,
          'log': '',
        },
        'https://helper.example/shielded-vote/v1/shares': {
          'share_id': 'share-1',
        },
        'https://helper.example/shielded-vote/v1/share-status/round-1/share-1':
            {'share_id': 'share-1', 'status': 'pending'},
      },
    );
    final client = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: http,
    );

    final rounds = await client.listRounds();
    final status = await client.getRoundStatus('round-1');
    final tally = await client.getRoundTally('round-1');
    final delegation = await client.submitDelegation(
      submission: {'vote_round_id': 'round-1', 'proof': 'AQ=='},
    );
    await client.submitShare(
      roundId: 'round-1',
      serverUrl: Uri.parse('https://helper.example'),
      share: {'share_index': 0},
    );
    await client.getShareStatus(
      roundId: 'round-1',
      serverUrl: Uri.parse('https://helper.example'),
      shareId: 'share-1',
    );
    await client.resubmitShare(
      roundId: 'round-1',
      serverUrl: Uri.parse('https://helper.example'),
      shareId: 'share-1',
      share: {'share_index': 0},
    );

    expect(http.requests.map((request) => request.uri.path), [
      '/shielded-vote/v1/rounds',
      '/shielded-vote/v1/round/round-1',
      '/shielded-vote/v1/tally-results/round-1',
      '/shielded-vote/v1/delegate-vote',
      '/shielded-vote/v1/shares',
      '/shielded-vote/v1/share-status/round-1/share-1',
      '/shielded-vote/v1/shares',
    ]);
    expect(http.requests[4].uri.host, 'helper.example');
    expect(http.requests[5].uri.host, 'helper.example');
    expect(rounds.single.roundId, 'round-1');
    expect(status.roundId, 'round-1');
    expect(tally.roundId, 'round-1');
    expect(delegation.txHash, 'delegation-tx');
    expect(delegation.code, 0);
  });

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
            'vote_round_id': encodedRoundId,
            'results': [],
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

  test('share request payloads preserve service JSON field names', () async {
    final http = FakeVotingHttpClient(
      responses: {
        'https://helper.example/shielded-vote/v1/shares': {
          'share_id': 'share-1',
        },
      },
    );
    final client = VotingApiClient(
      baseUrl: Uri.parse('https://voting.valargroup.org'),
      httpClient: http,
    );

    await client.submitShare(
      roundId: 'round-1',
      serverUrl: Uri.parse('https://helper.example'),
      share: {'share_index': 7},
    );

    expect(http.requests.single.body, {
      'vote_round_id': 'round-1',
      'share_index': 7,
    });
  });
}
