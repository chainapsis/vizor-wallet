import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';

void main() {
  group('friendlyProposeSendError', () {
    test("maps Rust's own no-tip wording onto the sync message", () {
      expect(
        friendlyProposeSendError(
          'Propose failed: Wallet must sync before sending max',
        ),
        'Finishing wallet sync. Try again shortly.',
      );
    });
  });

  group('friendlyPaymentRequestCheckError', () {
    test('names the network when the check could not reach it', () {
      expect(
        friendlyPaymentRequestCheckError('grpc connect failed: dns error'),
        "Couldn't reach the network — check your connection and open the "
        'link again',
      );
    });

    test('never claims a send happened for an unknown failure', () {
      final copy = friendlyPaymentRequestCheckError('something odd');
      expect(
        copy,
        "Couldn't check this request — open Edit to review the details",
      );
      expect(copy.toLowerCase(), isNot(contains('send failed')));
    });
  });
}
