@Tags(['mobile'])
library;

import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_hardware_selection_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_keystone_screens.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_ledger_connect_screen.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);

  Future<GoRouter> pump(
    WidgetTester tester, {
    LedgerCapability capability = const LedgerCapability.supported(),
    TargetPlatform platform = TargetPlatform.iOS,
    Size size = const Size(393, 852),
    double textScale = 1,
    AppThemeData theme = AppThemeData.light,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/previous',
      routes: [
        GoRoute(path: '/previous', builder: (_, _) => const Text('Previous')),
        ...mobileOnboardingRoutes(),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          ledgerStaticCapabilityProvider.overrideWithValue(capability),
          ledgerTargetPlatformProvider.overrideWithValue(platform),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(top: 55, bottom: 24),
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child: AppTheme(data: theme, child: child!),
          ),
        ),
      ),
    );
    router.push('/onboarding/hardware');
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('production Keystone entry returns to the hardware selector', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('mobile_welcome_keystone')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileKeystoneIntroScreen), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileHardwareSelectionScreen), findsOneWidget);
  });

  testWidgets('production Ledger entry returns to the hardware selector', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('mobile_welcome_ledger')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileLedgerConnectScreen), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileHardwareSelectionScreen), findsOneWidget);
  });

  testWidgets('selector Back returns to its actual caller', (tester) async {
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Previous'), findsOneWidget);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform offers Ledger on a supported build', (tester) async {
      await pump(tester, platform: platform);
      expect(find.text('Connect Ledger'), findsOneWidget);
    });
  }

  testWidgets('unsupported build hides Ledger and keeps Keystone available', (
    tester,
  ) async {
    await pump(
      tester,
      capability: const LedgerCapability.unsupported('Testnet'),
    );
    expect(find.text('Connect Ledger'), findsNothing);
    expect(find.text('Connect Keystone'), findsOneWidget);
  });

  testWidgets('non-Bluetooth platform hides Ledger', (tester) async {
    await pump(tester, platform: TargetPlatform.windows);
    expect(find.text('Connect Ledger'), findsNothing);
  });

  testWidgets('cards expose their description and an accessible tap action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pump(tester);
      final node = tester.getSemantics(
        find.byKey(const ValueKey('mobile_welcome_keystone')),
      );
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.label, 'Connect Keystone. Import from Keystone wallet');
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    } finally {
      semantics.dispose();
    }
  });

  for (final theme in [AppThemeData.light, AppThemeData.dark]) {
    testWidgets('small viewport and enlarged text keep both choices reachable '
        'in ${theme == AppThemeData.light ? 'light' : 'dark'}', (tester) async {
      await pump(
        tester,
        size: const Size(320, 568),
        textScale: 2,
        theme: theme,
      );
      expect(tester.takeException(), isNull);
      final ledger = find.byKey(const ValueKey('mobile_welcome_ledger'));
      await tester.ensureVisible(ledger);
      await tester.pumpAndSettle();
      expect(ledger.hitTestable(), findsOneWidget);
      expect(find.text('Import from Ledger wallet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
