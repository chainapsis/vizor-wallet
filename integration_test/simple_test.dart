import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());

  testWidgets('Welcome screen shows create and import buttons',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ZcashWalletApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create New Wallet'), findsOneWidget);
    expect(find.text('Import Wallet'), findsOneWidget);
  });
}
