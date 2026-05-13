import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/send/screens/send_status_screen.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  test('definite software broadcast rejection does not promise retry', () {
    const result = rust_sync.ExecuteProposalResult(
      txids: 'abc123',
      status: 'rejected_broadcast',
      broadcastedCount: 0,
      totalCount: 1,
      message: 'Broadcast rejected: bad-txns-inputs-spent (code -26)',
    );

    final message = softwareBroadcastStatusMessage(result);

    expect(message, contains('rejected by the network'));
    expect(message.toLowerCase(), isNot(contains('retry')));
    expect(message.toLowerCase(), isNot(contains('expires')));
  });

  test('legacy broadcast rejected message does not promise retry', () {
    const result = rust_sync.ExecuteProposalResult(
      txids: 'abc123',
      status: 'pending_broadcast',
      broadcastedCount: 0,
      totalCount: 1,
      message: 'Broadcast rejected: bad-txns-inputs-spent (code -26)',
    );

    final message = softwareBroadcastStatusMessage(result);

    expect(message, contains('rejected by the network'));
    expect(message.toLowerCase(), isNot(contains('retry')));
    expect(message.toLowerCase(), isNot(contains('expires')));
  });
}
