import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets('Welcome exposes desktop account entry actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildZcashWalletApp(bootstrap: AppBootstrapState.empty),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('welcome_create_wallet_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('welcome_import_wallet_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('welcome_redeem_card_button')),
      findsOneWidget,
    );
  });
}
