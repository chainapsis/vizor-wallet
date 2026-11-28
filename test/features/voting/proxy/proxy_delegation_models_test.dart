import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';

void main() {
  test('ballots convert to zatoshi at 0.125 ZEC', () {
    expect(proxyBallotsToZatoshi(BigInt.from(8)), BigInt.from(100000000));
  });
}
