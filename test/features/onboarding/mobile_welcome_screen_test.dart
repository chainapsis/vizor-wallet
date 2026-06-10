@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_create_steps.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_screens.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_welcome_screen.dart';

Widget _app({String initialLocation = '/welcome'}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: mobileOnboardingRoutes(),
  );
  return ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1000)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('welcome shows the three entry points and the legal footer', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Create a wallet'), findsOneWidget);
    expect(find.text('Import a wallet'), findsOneWidget);
    expect(find.text('Connect Keystone'), findsOneWidget);
    expect(find.textContaining('you agree to our'), findsOneWidget);
  });

  testWidgets('create pushes the intro step with swipe-back semantics', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_welcome_create')));
    await tester.pumpAndSettle();

    expect(find.byType(MobileOnboardingIntroScreen), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileWelcomeScreen), findsOneWidget);
  });

  testWidgets('import pushes the import entry step', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_welcome_import')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileImportMethodScreen), findsOneWidget);
  });

  testWidgets('keystone shows the unsupported sheet', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_welcome_keystone')));
    await tester.pumpAndSettle();

    expect(find.text('Not available yet'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Not available yet'), findsNothing);
  });

  testWidgets('add-account variant shows back to home affordance', (
    tester,
  ) async {
    await tester.pumpWidget(_app(initialLocation: '/add-account'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Back'), findsOneWidget);
  });
}
