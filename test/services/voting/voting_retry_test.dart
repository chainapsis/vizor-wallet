import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/voting/voting_models.dart';
import 'package:zcash_wallet/src/services/voting/voting_retry.dart';

void main() {
  test('retries transient timeout errors and returns success', () async {
    var attempts = 0;
    final delays = <Duration>[];

    final result = await withVotingRetry<int>(
      policy: VotingRetryPolicy.transientHttp(
        name: 'test-timeout',
        delays: const [Duration(milliseconds: 1)],
      ),
      delay: (delay) async => delays.add(delay),
      operation: () async {
        attempts += 1;
        if (attempts == 1) throw TimeoutException('timed out');
        return 7;
      },
    );

    expect(result, 7);
    expect(attempts, 2);
    expect(delays, const [Duration(milliseconds: 1)]);
  });

  test('retries retryable HTTP status codes', () async {
    var attempts = 0;
    final delays = <Duration>[];

    final result = await withVotingRetry<String>(
      policy: VotingRetryPolicy.transientHttp(
        name: 'test-http-500',
        delays: const [Duration(milliseconds: 1)],
      ),
      delay: (delay) async => delays.add(delay),
      operation: () async {
        attempts += 1;
        if (attempts == 1) {
          throw VotingHttpException(
            uri: Uri.parse('https://vote.example/rounds'),
            statusCode: 500,
            body: 'gateway failure',
          );
        }
        return 'ok';
      },
    );

    expect(result, 'ok');
    expect(attempts, 2);
    expect(delays, const [Duration(milliseconds: 1)]);
  });

  test('does not retry non-retryable HTTP status codes', () async {
    var attempts = 0;

    await expectLater(
      withVotingRetry<void>(
        policy: VotingRetryPolicy.transientHttp(
          name: 'test-http-422',
          delays: const [Duration(milliseconds: 1)],
        ),
        operation: () async {
          attempts += 1;
          throw VotingHttpException(
            uri: Uri.parse('https://vote.example/cast'),
            statusCode: 422,
            body: 'deterministic rejection',
          );
        },
      ),
      throwsA(
        isA<VotingHttpException>().having(
          (error) => error.statusCode,
          'statusCode',
          422,
        ),
      ),
    );
    expect(attempts, 1);
  });
}
