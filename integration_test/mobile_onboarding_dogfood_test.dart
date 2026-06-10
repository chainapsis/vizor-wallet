import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/features/home/screens/mobile/mobile_home_screen.dart';

/// Manual dogfood runner for the mobile create-wallet onboarding.
///
/// Walks the real app — welcome → intro → address types → things to
/// know → secret passphrase → passcode (×2) → biometrics → home — with
/// the real Rust mnemonic, the real lightwalletd birthday fetch, and
/// the real keychain. It therefore CREATES A MAINNET WALLET on the
/// target device: run it on a disposable simulator with no existing
/// wallet (`./clear-app.sh` resets one), with the mobile token lane:
///
///   fvm flutter test integration_test/mobile_onboarding_dogfood_test.dart \
///     -d SIMULATOR --dart-define=VIZOR_FORM_FACTOR=mobile
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets('create flow walks from welcome to the home tab shell', (
    tester,
  ) async {
    final app = await buildBootstrappedZcashWalletApp();
    await tester.pumpWidget(app);

    Future<void> tapWhenVisible(
      Finder finder, {
      Duration timeout = const Duration(seconds: 20),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (finder.evaluate().isEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Timed out waiting for $finder');
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 350));
    }

    await tapWhenVisible(find.byKey(const ValueKey('mobile_welcome_create')));
    await tapWhenVisible(find.byKey(const ValueKey('mobile_intro_continue')));
    await tapWhenVisible(
      find.byKey(const ValueKey('mobile_address_types_continue')),
    );
    await tapWhenVisible(
      find.byKey(const ValueKey('mobile_things_to_know_continue')),
    );

    // Reveal the generated phrase, then continue into passcode setup.
    await tapWhenVisible(
      find.byKey(const ValueKey('mobile_secret_passphrase_primary')),
    );
    await tapWhenVisible(
      find.byKey(const ValueKey('mobile_secret_passphrase_primary')),
    );

    // Create and confirm the passcode. The confirm submit performs the
    // real account creation (birthday fetch over the network).
    for (var round = 0; round < 2; round++) {
      for (var i = 0; i < 6; i++) {
        await tapWhenVisible(find.bySemanticsLabel('Digit 1'));
      }
    }

    // Account creation can take a while (network); the biometrics step
    // appearing proves the wallet + passcode landed.
    await tapWhenVisible(
      find.byKey(const ValueKey('mobile_biometrics_not_now')),
      timeout: const Duration(seconds: 90),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (find.byType(MobileHomeScreen).evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out waiting for the home tab shell');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(MobileHomeScreen), findsOneWidget);
  });
}
