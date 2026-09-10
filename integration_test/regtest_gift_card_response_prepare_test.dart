import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';

import 'support/gift_card_outcomes_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeZcashWalletRuntime);
  testWidgets(
    'retains an accepted Gift Card claim after its response is lost',
    (tester) => prepareGiftOutcome(tester, competition: false),
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
