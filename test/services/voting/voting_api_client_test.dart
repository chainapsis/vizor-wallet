import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/voting/voting_api_client.dart';

import 'fake_voting_http.dart';

void main() {
  test('composes vote-sdk URLs under shielded-vote v1', () async {
    final http = FakeVotingHttpClient(
      responses: {
        '/shielded-vote/v1/rounds': [
          {'round_id': 'round-1', 'status': 'active'},
        ],
        '/shielded-vote/v1/round/round-1': {
          'round': {'round_id': 'round-1', 'status': 'open'},
        },
        '/shielded-vote/v1/tally-results/round-1': {
          'round_id': 'round-1',
          'results': [],
        },
        '/shielded-vote/v1/delegate-vote': {
          'round_id': 'round-1',
          'status': 'accepted',
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

    await client.listRounds();
    await client.getRoundStatus('round-1');
    await client.getRoundTally('round-1');
    await client.submitDelegationPczt(roundId: 'round-1', txHex: 'abcd');
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
