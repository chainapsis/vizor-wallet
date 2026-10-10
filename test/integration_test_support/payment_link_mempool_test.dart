import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/payment_link_regtest_flow.dart';

void main() {
  final protocolTxid = List.generate(
    32,
    (index) => index.toRadixString(16).padLeft(2, '0'),
  ).join();
  final rpcTxid = paymentLinkClaimTxidToRpcOrder(protocolTxid);

  testWidgets('pending history cannot substitute for node acceptance', (
    tester,
  ) async {
    var reads = 0;
    await tester.runAsync(() async {
      await waitForPaymentLinkMempoolTxids(
        tester,
        [protocolTxid],
        readMempool: () async {
          reads++;
          return reads == 3 ? [rpcTxid] : ['ff' * 32];
        },
      );
    });
    expect(reads, 3);
  });

  testWidgets('all required transactions must be accepted, in RPC order', (
    tester,
  ) async {
    var reads = 0;
    final second = 'ab' * 32;
    await tester.runAsync(() async {
      await waitForPaymentLinkMempoolTxids(
        tester,
        [protocolTxid, second],
        readMempool: () async =>
            ++reads == 1 ? [protocolTxid, second] : [rpcTxid, second],
      );
    });
    expect(reads, 2);
  });

  testWidgets('original node errors remain failures', (tester) async {
    final failure = StateError('node mempool request failed');
    await expectLater(
      waitForPaymentLinkMempoolTxids(tester, [
        protocolTxid,
      ], readMempool: () async => throw failure),
      throwsA(same(failure)),
    );
  });

  testWidgets('bounded acceptance wait reports failure, never mines', (
    tester,
  ) async {
    var reads = 0;
    await expectLater(
      waitForPaymentLinkMempoolTxids(
        tester,
        [protocolTxid],
        timeout: Duration.zero,
        readMempool: () async {
          reads++;
          return [];
        },
      ),
      throwsA(isA<TestFailure>()),
    );
    expect(reads, 0);
  });
}
