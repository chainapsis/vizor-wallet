import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';

void main() {
  test('ballots convert to zatoshi at 0.125 ZEC', () {
    expect(proxyBallotsToZatoshi(BigInt.from(8)), BigInt.from(100000000));
    final preview = ProxyAllocationPreview(
      delegations: [
        ProxyPreviewDelegation(delegateIndex: 1, ballots: BigInt.from(3)),
        ProxyPreviewDelegation(delegateIndex: 2, ballots: BigInt.from(5)),
      ],
      keptBallots: BigInt.two,
      dcCount: 2,
      bundleCount: 1,
      singleShare: false,
    );
    expect(preview.delegatedBallots, BigInt.from(8));
  });
}
