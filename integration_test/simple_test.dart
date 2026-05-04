import 'package:desktop_window_bootstrap/desktop_window_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/layout/app_layout.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FlutterForegroundTask.initCommunicationPort();
    await RustLib.init();
    await initializeDesktopWindow();
    if (isDesktopLayoutPlatform) {
      await DesktopWindowBootstrap.initialize();
      await showDesktopWindow();
    }
  });

  testWidgets('Welcome screen shows create and import buttons', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        ],
        child: const ZcashWalletApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create a new wallet'), findsOneWidget);
    expect(find.text('Import a wallet'), findsOneWidget);
  });
}
