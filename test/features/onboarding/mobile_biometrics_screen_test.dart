@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';

Widget _app() {
  final router = GoRouter(
    initialLocation: '/onboarding/biometrics',
    routes: [
      ...mobileOnboardingRoutes(),
      GoRoute(path: '/home', builder: (_, _) => const Text('home stub')),
    ],
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
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('enable shows the unsupported sheet, then lands on home', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_biometrics_enable')));
    await tester.pumpAndSettle();
    expect(find.text('Not available yet'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('home stub'), findsOneWidget);
  });

  testWidgets('not now skips straight to home', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_biometrics_not_now')));
    await tester.pumpAndSettle();
    expect(find.text('home stub'), findsOneWidget);
  });
}
