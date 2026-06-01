import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/voting/voting_endorser_client.dart';

import 'fake_voting_http.dart';

void main() {
  const encodedRoundId = 'El5UdfZTsHTV9MNnMIUmlfNWQWwrbDBCUWqRLlv/3RE=';
  const hexRoundId =
      '125e5475f653b074d5f4c36730852695f356416c2b6c3042516a912e5bffdd11';

  test('parses vote_round_ids from the endorser response', () async {
    final uri = Uri.parse('https://voting.example/endorsed');
    final client = VotingEndorserClient(
      endorsedSetUrl: uri,
      httpClient: FakeVotingHttpClient(
        responses: {
          uri.toString(): {
            'vote_round_ids': [hexRoundId.toUpperCase(), encodedRoundId],
          },
        },
      ),
    );

    expect(await client.getEndorsedSet(), {hexRoundId});
  });

  test('HTTP 500 timeout and malformed JSON soft-fail to empty set', () async {
    Future<Set<String>> load(Object response) {
      final uri = Uri.parse('https://voting.example/endorsed');
      return VotingEndorserClient(
        endorsedSetUrl: uri,
        httpClient: FakeVotingHttpClient(responses: {uri.toString(): response}),
      ).getEndorsedSet();
    }

    expect(await load(textResponse('bad', statusCode: 500)), isEmpty);
    expect(await load(timeoutResponse()), isEmpty);
    expect(await load('{'), isEmpty);
    expect(
      await load({
        'vote_round_ids': ['round-1'],
      }),
      isEmpty,
    );
  });
}
