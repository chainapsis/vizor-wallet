@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/screens/mobile/mobile_voting_screens.dart';

import 'voting_retry_recovery_test_utils.dart';

void main() {
  testWidgets(
    'mobile retry leaves the error screen before asynchronous recovery',
    (tester) async {
      await expectVotingRetryClearsError(
        tester,
        screenBuilder: (roundId) => MobileVotingStatusScreen(roundId: roundId),
        surfaceSize: const Size(390, 844),
      );
    },
  );
}
