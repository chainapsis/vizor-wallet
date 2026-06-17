@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_keystone_screens.dart';

Widget _app(String initialLocation) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/onboarding/keystone',
        builder: (_, _) => const MobileKeystoneIntroScreen(),
      ),
      GoRoute(
        path: '/onboarding/keystone/scan',
        builder: (_, _) => const SizedBox(key: ValueKey('scan-screen')),
      ),
    ],
  );
  return ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

void _setViewSize(WidgetTester tester, Size size) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
}

void main() {
  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  testWidgets('intro uses two compact Figma cards', (tester) async {
    _setViewSize(tester, const Size(393, 852));

    await tester.pumpWidget(_app('/onboarding/keystone'));
    await tester.pumpAndSettle();

    const firmwareCardKey = ValueKey('mobile_keystone_intro_firmware_card');
    const prepareCardKey = ValueKey('mobile_keystone_intro_prepare_card');

    expect(find.byKey(firmwareCardKey), findsOneWidget);
    expect(find.byKey(prepareCardKey), findsOneWidget);
    expect(find.text('1. Check Keystone firmware'), findsOneWidget);
    expect(find.text('2. Prepare to connect'), findsOneWidget);

    expect(tester.getSize(find.byKey(firmwareCardKey)).width, 361);
    expect(tester.getSize(find.byKey(prepareCardKey)).width, 361);

    final firmwareBottom = tester.getBottomLeft(find.byKey(firmwareCardKey)).dy;
    final prepareTop = tester.getTopLeft(find.byKey(prepareCardKey)).dy;
    expect(prepareTop - firmwareBottom, AppSpacing.sm);
  });

  testWidgets('intro preserves the scan CTA', (tester) async {
    _setViewSize(tester, const Size(393, 852));

    await tester.pumpWidget(_app('/onboarding/keystone'));
    await tester.pumpAndSettle();

    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Tell me how Zcash works'), findsNothing);
    expect(
      find.text(
        'Allow camera access when prompted and scan the QR code with your phone.',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('mobile_keystone_intro_continue')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('scan-screen')), findsOneWidget);
  });
}
