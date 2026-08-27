@Tags(['mobile'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_keystone_sign_screen.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';

void main() {
  test('mobile TEX advances 1 of 2 to 2 of 2 and returns both rounds', () {
    final args = SendReviewArgs(
      proposalId: BigInt.one,
      sendFlowId: 'tex-flow',
      proposalAccountUuid: 'account',
      address: 'tex1test',
      addressType: 'tex',
      amountZatoshi: BigInt.one,
      feeZatoshi: BigInt.one,
      needsSaplingParams: false,
    );
    final rounds = MobileKeystoneSigningRounds(args: args);

    expect(rounds.title, 'Confirm transaction 1 of 2');
    expect(rounds.add([1], [3]), isFalse);
    expect(rounds.title, 'Confirm transaction 2 of 2');
    expect(rounds.add([2], [4]), isTrue);

    final result = rounds.result();
    expect(result.pcztWithProofs, [
      [1],
      [2],
    ]);
    expect(result.pcztWithSignatures, [
      [3],
      [4],
    ]);
  });

  test('mobile non-TEX retains the single-round signing contract', () {
    final rounds = MobileKeystoneSigningRounds(
      args: SendReviewArgs(
        proposalId: BigInt.one,
        sendFlowId: 'single-flow',
        proposalAccountUuid: 'account',
        address: 'u1test',
        addressType: 'unified',
        amountZatoshi: BigInt.one,
        feeZatoshi: BigInt.one,
        needsSaplingParams: false,
      ),
    );

    expect(rounds.title, 'Confirm transaction');
    expect(rounds.add([1], [2]), isTrue);
    expect(rounds.result().pcztWithProofs, [
      [1],
    ]);
  });
}
