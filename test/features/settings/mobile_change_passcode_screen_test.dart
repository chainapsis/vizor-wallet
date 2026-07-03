@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_change_passcode_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';
import 'package:zcash_wallet/src/services/biometric_unlock.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

/// Intercepts the two security calls the screen makes so no secure
/// storage is touched.
class _FakeSecurityNotifier extends AppSecurityNotifier {
  _FakeSecurityNotifier({this.confirmResult = true});

  final bool confirmResult;
  final confirmedWith = <String>[];
  ({String current, String next})? changedWith;

  @override
  Future<bool> confirmPassword(String password) async {
    confirmedWith.add(password);
    return confirmResult;
  }

  @override
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changedWith = (current: currentPassword, next: newPassword);
    return true;
  }
}

class _FakeBiometricController {
  _FakeBiometricController({required this.initialState});

  BiometricUnlockState initialState;
  String? enabledWith;
  var disabled = false;
}

class _FakeBiometricNotifier extends BiometricUnlockNotifier {
  _FakeBiometricNotifier(this.controller);

  final _FakeBiometricController controller;

  @override
  Future<BiometricUnlockState> build() async => controller.initialState;

  @override
  Future<String?> readPasscode({required String reason}) async {
    throw StateError('Change-passcode gate must not read biometrics.');
  }

  @override
  Future<void> enable(String passcode) async {
    controller.enabledWith = passcode;
    controller.initialState = controller.initialState.copyWith(enabled: true);
    state = AsyncData(controller.initialState);
  }

  @override
  Future<void> disable() async {
    controller.disabled = true;
    controller.initialState = controller.initialState.copyWith(enabled: false);
    state = AsyncData(controller.initialState);
  }
}

const _faceBiometricState = BiometricUnlockState(
  availability: BiometricAvailability(
    supported: true,
    enrolled: true,
    kind: BiometricKind.face,
  ),
  enabled: true,
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/settings',
  initialAccountState: const AccountState(accounts: []),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

/// Hosts the screen behind a go_router push (the screen pops via
/// `context.pop`) so pop-with-result is observable.
Widget _app(
  _FakeSecurityNotifier security, {
  required List<bool?> popResult,
  _FakeBiometricController? biometric,
}) {
  final router = GoRouter(
    initialLocation: '/host',
    routes: [
      GoRoute(
        path: '/host',
        builder: (context, state) => GestureDetector(
          onTap: () async {
            popResult.add(
              await context.push<bool>('/settings/change-password'),
            );
          },
          child: const Text('open'),
        ),
      ),
      GoRoute(
        path: '/settings/change-password',
        builder: (context, state) => const MobileChangePasscodeScreen(),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      appSecurityProvider.overrideWith(() => security),
      if (biometric != null)
        biometricUnlockProvider.overrideWith(
          () => _FakeBiometricNotifier(biometric),
        ),
    ],
    child: MaterialApp.router(
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
    ),
  );
}

Future<void> _enterPasscode(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.bySemanticsLabel('Digit $digit'));
    await tester.pump();
  }
  // Let the async verify/change call settle.
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a wrong current passcode shows Incorrect Passcode and stays '
      'on the verify phase', (tester) async {
    final security = _FakeSecurityNotifier(confirmResult: false);
    await tester.pumpWidget(_app(security, popResult: []));
    await open(tester);

    expect(find.text('Enter Passcode'), findsOneWidget);
    expect(find.text('Confirm your access'), findsOneWidget);
    final verifyTitle = tester.widget<Text>(find.text('Enter Passcode'));
    expect(verifyTitle.style?.fontSize, AppTypography.displayLarge.fontSize);
    expect(find.bySemanticsLabel('Passcode help'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Passcode help'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot Passcode?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await _enterPasscode(tester, '111111');
    expect(find.text('Incorrect Passcode'), findsOneWidget);
    expect(find.text('Enter Passcode'), findsOneWidget);
    expect(security.confirmedWith, ['111111']);
  });

  testWidgets('the full flow verifies, collects the new passcode twice, and '
      'pops with true', (tester) async {
    final security = _FakeSecurityNotifier();
    final popResult = <bool?>[];
    await tester.pumpWidget(_app(security, popResult: popResult));
    await open(tester);

    expect(find.bySemanticsLabel('Passcode help'), findsOneWidget);
    await _enterPasscode(tester, '111111');
    expect(find.text('Set New Passcode'), findsOneWidget);
    expect(find.text('6 digits length'), findsOneWidget);
    expect(find.bySemanticsLabel('Passcode help'), findsNothing);
    expect(find.bySemanticsLabel('Sign in with Face ID'), findsNothing);

    await _enterPasscode(tester, '222222');
    expect(find.text('Confirm Passcode'), findsOneWidget);
    expect(find.text('6 digits length'), findsOneWidget);

    await _enterPasscode(tester, '222222');
    expect(security.changedWith, (current: '111111', next: '222222'));
    expect(popResult, [true]);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a confirm mismatch restarts the new-passcode phase', (
    tester,
  ) async {
    final security = _FakeSecurityNotifier();
    await tester.pumpWidget(_app(security, popResult: []));
    await open(tester);

    await _enterPasscode(tester, '111111');
    await _enterPasscode(tester, '222222');
    await _enterPasscode(tester, '333333');

    expect(find.text('Set New Passcode'), findsOneWidget);
    expect(find.text("Passcodes didn't match. Try again."), findsOneWidget);
    expect(security.changedWith, isNull);
  });

  testWidgets('reusing the current passcode as the new one is rejected', (
    tester,
  ) async {
    final security = _FakeSecurityNotifier();
    await tester.pumpWidget(_app(security, popResult: []));
    await open(tester);

    await _enterPasscode(tester, '111111');
    await _enterPasscode(tester, '111111');

    expect(find.text('Set New Passcode'), findsOneWidget);
    expect(find.text('Your new passcode must be different.'), findsOneWidget);
    expect(security.changedWith, isNull);
  });

  testWidgets('current-passcode phase does not offer biometric verification', (
    tester,
  ) async {
    final security = _FakeSecurityNotifier();
    final biometric = _FakeBiometricController(
      initialState: _faceBiometricState,
    );
    await tester.pumpWidget(
      _app(security, popResult: [], biometric: biometric),
    );
    await open(tester);

    expect(find.text('Enter Passcode'), findsOneWidget);
    expect(find.bySemanticsLabel('Sign in with Face ID'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_change_passcode_biometric_footer')),
      findsNothing,
    );

    await _enterPasscode(tester, '111111');

    expect(security.confirmedWith, ['111111']);
    expect(find.text('Set New Passcode'), findsOneWidget);
  });
}
