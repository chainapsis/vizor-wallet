@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_create_steps.dart';

Widget _app(String initialLocation) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: mobileOnboardingRoutes(),
  );
  return MaterialApp.router(
    routerConfig: router,
    builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
  );
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('intro continues into address types and skip jumps ahead', (
    tester,
  ) async {
    await tester.pumpWidget(_app('/onboarding/intro'));
    await tester.pumpAndSettle();

    expect(find.text('The Shielded World'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mobile_intro_continue')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileAddressTypesScreen), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_intro_skip')));
    await tester.pumpAndSettle();
    // Secret passphrase is still the placeholder until OB-4.
    expect(find.byType(MobileAddressTypesScreen), findsNothing);
  });

  testWidgets('address types lists both pools and continues', (tester) async {
    await tester.pumpWidget(_app('/onboarding/address-types'));
    await tester.pumpAndSettle();

    expect(find.text('Shielded Address'), findsOneWidget);
    expect(find.text('Transparent Address'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('mobile_address_types_continue')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MobileThingsToKnowScreen), findsOneWidget);
  });

  testWidgets('things to know shows both notes', (tester) async {
    await tester.pumpWidget(_app('/onboarding/things-to-know'));
    await tester.pumpAndSettle();

    expect(find.text('Time to sync'), findsOneWidget);
    expect(find.text('How to keep privacy'), findsOneWidget);
  });
}
