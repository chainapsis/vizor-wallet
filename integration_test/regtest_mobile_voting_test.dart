import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'support/mobile_voting_regtest_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeMobileVotingRegtestRuntime);
  testWidgets(
    'keeps the Home card during resync, then votes and hides it',
    completeMobileRegtestVote,
    timeout: const Timeout(Duration(minutes: 45)),
  );
}
