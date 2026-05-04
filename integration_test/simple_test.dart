import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets('Welcome screen shows create and import buttons', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildZcashWalletApp(bootstrap: AppBootstrapState.empty),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create a new wallet'), findsOneWidget);
    expect(find.text('Import a wallet'), findsOneWidget);
  });
}
