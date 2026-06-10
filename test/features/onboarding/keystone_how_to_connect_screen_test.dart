import 'dart:ui' show Size;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/widgets.dart' show Text, Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/onboarding/keystone/keystone_how_to_connect_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/keystone/keystone_onboarding_flow.dart';

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('renders the Keystone start content', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_keystoneScreen());

    expect(find.text('Connect Keystone'), findsOneWidget);
    expect(find.text('Prepare your Keystone wallet'), findsOneWidget);
    expect(find.text('Before you start'), findsOneWidget);
    expect(find.text('Check your firmware'), findsOneWidget);
    expect(find.text('Get Cypherpunk firmware'), findsOneWidget);
    expect(find.text('Next step'), findsOneWidget);
    expect(find.text('Prepare to connect'), findsOneWidget);
    expect(find.text("I'm ready now"), findsOneWidget);
  });

  testWidgets('ready CTA resets scan state and opens QR scan step', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final router = GoRouter(
      initialLocation: KeystoneOnboardingStep.howToConnect.routePath,
      routes: [
        GoRoute(
          path: KeystoneOnboardingStep.howToConnect.routePath,
          builder: (_, _) => const KeystoneHowToConnectScreen(),
        ),
        GoRoute(
          path: KeystoneOnboardingStep.scanQrCode.routePath,
          builder: (_, _) => const Text('Scan QR route'),
        ),
        GoRoute(path: '/welcome', builder: (_, _) => const Text('Welcome')),
      ],
    );

    await tester.pumpWidget(_routerHarness(router));
    await tester.tap(find.text("I'm ready now"));
    await tester.pumpAndSettle();

    expect(find.text('Scan QR route'), findsOneWidget);
  });

  test('sidebar metadata matches the Keystone navigation labels', () {
    expect(KeystoneOnboardingStep.howToConnect.iconName, AppIcons.book);
    expect(KeystoneOnboardingStep.selectAccount.label, 'Select Account');
    expect(KeystoneOnboardingStep.selectAccount.iconName, AppIcons.user);
  });
}

Future<void> _loadAppFonts() async {
  final libreCaslonText = FontLoader('Libre Caslon Text')
    ..addFont(rootBundle.load('assets/fonts/LibreCaslonText-Regular.ttf'));
  final geist = FontLoader('Geist')
    ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'));
  final geistMono = FontLoader('Geist Mono')
    ..addFont(rootBundle.load('assets/fonts/GeistMono-Medium.ttf'));

  await Future.wait([libreCaslonText.load(), geist.load(), geistMono.load()]);
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Widget _keystoneScreen() {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    ],
    child: MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: const KeystoneHowToConnectScreen(),
      ),
    ),
  );
}

Widget _routerHarness(GoRouter router) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}
