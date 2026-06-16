@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav.dart';
import 'package:zcash_wallet/src/core/privacy/sensitive_privacy_overlay.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_seed_phrase_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';
import 'package:zcash_wallet/src/services/biometric_unlock.dart';

const _mnemonic =
    'abandon ability able about above absent absorb abstract absurd abuse access accident';

const _accountState = AccountState(
  accounts: [AccountInfo(uuid: 'account-1', name: 'Knight', order: 0)],
  activeAccountUuid: 'account-1',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/settings/seed-phrase',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _FakeSecurityNotifier extends AppSecurityNotifier {
  @override
  Future<bool> confirmPassword(String password) async => true;
}

class _FakeAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => _accountState;

  @override
  Future<String?> getMnemonicForAccount(String uuid) async => _mnemonic;
}

class _FakeBiometricUnlock extends BiometricUnlock {
  @override
  Future<BiometricAvailability> availability() async =>
      BiometricAvailability.unavailable;
}

Widget _app({
  Stream<void>? screenshotStream,
  SensitivePrivacyOverlayController? privacyOverlayController,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      accountProvider.overrideWith(_FakeAccountNotifier.new),
      appSecurityProvider.overrideWith(_FakeSecurityNotifier.new),
      biometricUnlockServiceProvider.overrideWithValue(_FakeBiometricUnlock()),
    ],
    child: MaterialApp(
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
      home: MobileSeedPhraseScreen(
        screenshotStream: screenshotStream,
        privacyOverlayController: privacyOverlayController,
        loadBirthday: false,
      ),
    ),
  );
}

Future<void> _revealSecret(WidgetTester tester) async {
  for (final digit in '111111'.split('')) {
    await tester.tap(find.bySemanticsLabel('Digit $digit'));
    await tester.pump();
  }
  await tester.pump();
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('shows the screenshot warning after the phrase is revealed', (
    tester,
  ) async {
    final screenshots = StreamController<void>();
    addTearDown(screenshots.close);

    await tester.pumpWidget(_app(screenshotStream: screenshots.stream));
    await _revealSecret(tester);

    expect(find.text('abandon'), findsOneWidget);

    screenshots.add(null);
    await tester.pumpAndSettle();

    expect(find.textContaining("Don't take screenshots"), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_seed_screenshot_ack')),
      findsOneWidget,
    );
  });

  testWidgets(
    'covers the revealed phrase when the privacy controller is unsafe',
    (tester) async {
      final privacyController = SensitivePrivacyOverlayController(
        initiallySafe: false,
      );
      addTearDown(privacyController.dispose);

      await tester.pumpWidget(
        _app(privacyOverlayController: privacyController),
      );
      await _revealSecret(tester);

      final shield = find.byKey(SensitivePrivacyOverlay.shieldKey);
      expect(shield, findsOneWidget);
      expect(
        tester.getTopLeft(shield).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(MobileTopNav)).dy),
      );

      privacyController.markSafe();
      await tester.pump();

      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);
    },
  );
}
