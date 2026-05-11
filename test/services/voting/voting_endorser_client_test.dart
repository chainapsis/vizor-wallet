import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/voting/voting_endorser_client.dart';

import 'fake_voting_http.dart';

void main() {
  test('parses endorsed round IDs from list and object forms', () async {
    final uri = Uri.parse('https://voting.example/endorsed');
    final client = VotingEndorserClient(
      endorsedSetUrl: uri,
      httpClient: FakeVotingHttpClient(
        responses: {
          uri.toString(): {
            'endorsed_round_ids': ['round-1', 'round-2'],
          },
        },
      ),
    );

    expect(await client.getEndorsedSet(), {'round-1', 'round-2'});
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
  });
}
