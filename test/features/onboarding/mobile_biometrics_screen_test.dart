@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_toast.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';
import 'package:zcash_wallet/src/services/biometric_unlock.dart';

class _FakeBiometricUnlock extends BiometricUnlock {
  _FakeBiometricUnlock({required this.avail});

  BiometricAvailability avail;
  String? escrow;

  @override
  Future<BiometricAvailability> availability() async => avail;

  @override
  Future<void> enable(String passcode) async => escrow = passcode;

  @override
  Future<void> disable() async => escrow = null;
}

Widget _app(_FakeBiometricUnlock biometric) {
  final router = GoRouter(
    initialLocation: '/onboarding/biometrics',
    routes: [
      ...mobileOnboardingRoutes(),
      GoRoute(path: '/home', builder: (_, _) => const Text('home stub')),
    ],
  );
  return ProviderScope(
    overrides: [biometricUnlockServiceProvider.overrideWithValue(biometric)],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(
        data: AppThemeData.light,
        child: AppToastHost(child: child!),
      ),
    ),
  );
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
    FlutterSecureStorage.setMockInitialValues({});
    AppSecureStore.instance.setSessionPassword('123456');
  });

  tearDown(AppSecureStore.instance.clearSessionPassword);

  testWidgets('enable writes the escrow and lands on home', (tester) async {
    final biometric = _FakeBiometricUnlock(
      avail: const BiometricAvailability(
        supported: true,
        enrolled: true,
        kind: BiometricKind.face,
      ),
    );
    await tester.pumpWidget(_app(biometric));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_biometrics_enable')));
    await tester.pumpAndSettle();

    expect(biometric.escrow, '123456');
    expect(find.text('home stub'), findsOneWidget);
    expect(
      await AppSecureStore.instance.readPlain(kBiometricUnlockEnabledKey),
      'true',
    );
  });

  testWidgets('enable without enrollment explains and stays', (tester) async {
    final biometric = _FakeBiometricUnlock(
      avail: const BiometricAvailability(
        supported: true,
        enrolled: false,
        kind: BiometricKind.face,
      ),
    );
    await tester.pumpWidget(_app(biometric));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_biometrics_enable')));
    await tester.pumpAndSettle();

    expect(biometric.escrow, isNull);
    expect(find.text('home stub'), findsNothing);
    expect(
      find.textContaining('in your device settings first'),
      findsOneWidget,
    );
  });

  testWidgets('not now skips straight to home', (tester) async {
    final biometric = _FakeBiometricUnlock(
      avail: const BiometricAvailability(
        supported: true,
        enrolled: false,
        kind: BiometricKind.fingerprint,
      ),
    );
    await tester.pumpWidget(_app(biometric));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_biometrics_not_now')));
    await tester.pumpAndSettle();
    expect(find.text('home stub'), findsOneWidget);
  });

  testWidgets('a device without biometric hardware skips the screen', (
    tester,
  ) async {
    final biometric = _FakeBiometricUnlock(
      avail: BiometricAvailability.unavailable,
    );
    await tester.pumpWidget(_app(biometric));
    await tester.pumpAndSettle();

    expect(find.text('home stub'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_biometrics_enable')),
      findsNothing,
    );
  });
}
