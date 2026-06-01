import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/services/voting/voting_models.dart';

void main() {
  test('round details reject fractional snapshot heights', () {
    final status = VotingRoundStatus(
      roundId: 'round-1',
      status: 'active',
      rawJson: const {'snapshot_height': 100.5},
    );

    expect(
      () => VotingRoundDetails.fromStatus(status),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'snapshot_height must be an integer',
        ),
      ),
    );
  });
}
