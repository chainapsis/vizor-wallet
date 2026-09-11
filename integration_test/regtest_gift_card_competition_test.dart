import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';

import 'support/gift_card_outcomes_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeZcashWalletRuntime);
  testWidgets(
    'one Gift Card winner and a finalized losing claim',
    (tester) => prepareGiftOutcome(tester, competition: true),
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
