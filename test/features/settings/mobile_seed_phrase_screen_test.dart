@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav.dart';
import 'package:zcash_wallet/src/core/privacy/sensitive_privacy_overlay.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/passcode_widgets.dart';
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

class _FakeBiometricController {
  _FakeBiometricController({required this.initialState});

  BiometricUnlockState initialState;
  String? passcode;
  var reads = 0;
  String? lastReason;
}

class _FakeBiometricNotifier extends BiometricUnlockNotifier {
  _FakeBiometricNotifier(this.controller);

  final _FakeBiometricController controller;

  @override
  Future<BiometricUnlockState> build() async => controller.initialState;

  @override
  Future<String?> readPasscode({required String reason}) async {
    controller.reads += 1;
    controller.lastReason = reason;
    return controller.passcode;
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

const _fingerprintBiometricState = BiometricUnlockState(
  availability: BiometricAvailability(
    supported: true,
    enrolled: true,
    kind: BiometricKind.fingerprint,
  ),
  enabled: true,
);

Widget _app({
  Stream<void>? screenshotStream,
  SensitivePrivacyOverlayController? privacyOverlayController,
  _FakeBiometricController? biometric,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      accountProvider.overrideWith(_FakeAccountNotifier.new),
      appSecurityProvider.overrideWith(_FakeSecurityNotifier.new),
      if (biometric == null)
        biometricUnlockServiceProvider.overrideWithValue(_FakeBiometricUnlock())
      else
        biometricUnlockProvider.overrideWith(
          () => _FakeBiometricNotifier(biometric),
        ),
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

  testWidgets('confirm gate uses the shared passcode layout', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Confirm Access'), findsNothing);
    expect(find.text('Enter Passcode'), findsOneWidget);
    expect(find.text('Confirm your access'), findsOneWidget);
    final title = tester.widget<Text>(find.text('Enter Passcode'));
    expect(title.style?.fontSize, AppTypography.displayLarge.fontSize);
    expect(find.byType(PasscodeNumpad), findsOneWidget);
    expect(find.bySemanticsLabel('Passcode help'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Passcode help'));
    await tester.pumpAndSettle();

    expect(find.text('Forgot Passcode?'), findsOneWidget);
    expect(find.text('Continue to reset Vizor'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot Passcode?'), findsNothing);
  });

  testWidgets('confirm gate keeps biometric retry after prompt cancel', (
    tester,
  ) async {
    final biometric = _FakeBiometricController(
      initialState: _faceBiometricState,
    );
    await tester.pumpWidget(_app(biometric: biometric));
    await tester.pumpAndSettle();

    expect(biometric.reads, 1);
    expect(find.text('Enter Passcode'), findsOneWidget);
    expect(find.bySemanticsLabel('Sign in with Face ID'), findsOneWidget);

    biometric.passcode = '111111';
    await tester.tap(find.bySemanticsLabel('Sign in with Face ID'));
    await tester.pumpAndSettle();

    expect(biometric.reads, 2);
    expect(biometric.lastReason, 'Confirm access to your secret passphrase');
    expect(find.text('abandon'), findsOneWidget);
  });

  testWidgets('confirm gate labels fingerprint retry by modality', (
    tester,
  ) async {
    final biometric = _FakeBiometricController(
      initialState: _fingerprintBiometricState,
    );
    await tester.pumpWidget(_app(biometric: biometric));
    await tester.pumpAndSettle();

    expect(biometric.reads, 1);
    expect(find.bySemanticsLabel('Sign in with fingerprint'), findsOneWidget);
    expect(find.bySemanticsLabel('Sign in with Face ID'), findsNothing);
    expect(find.byIcon(Icons.fingerprint), findsOneWidget);
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

    expect(find.textContaining('Don’t take screenshots'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_seed_screenshot_ack')),
      findsOneWidget,
    );
    final sheetFinder = find.byKey(
      const ValueKey('mobile_seed_screenshot_sheet'),
    );
    final buttonFinder = find.byKey(
      const ValueKey('mobile_seed_screenshot_ack'),
    );
    expect(tester.widget(sheetFinder), isA<MobileModalScaffold>());
    final eye = tester.widget<AppIcon>(
      find.byKey(const ValueKey('mobile_seed_screenshot_icon')),
    );
    final title = tester.widget<Text>(
      find.byKey(const ValueKey('mobile_seed_screenshot_title')),
    );
    final titleSize = tester.getSize(
      find.byKey(const ValueKey('mobile_seed_screenshot_title')),
    );
    final body = tester.widget<Text>(
      find.byKey(const ValueKey('mobile_seed_screenshot_body')),
    );
    final buttonLabel = tester.widget<Text>(find.text('I understand'));

    expect(eye.size, 30);
    expect(title.data, 'Don’t take screenshots of your Secret Passphrase');
    expect(title.maxLines, isNull);
    expect(title.overflow, isNull);
    expect(title.style?.fontFamily, 'Young Serif');
    expect(title.style?.fontSize, 24);
    expect(title.style?.height, 28 / 24);
    expect(title.style?.fontWeight, FontWeight.w500);
    expect(title.style?.letterSpacing, -0.4);
    expect(titleSize.width, 253);
    expect(body.textAlign, TextAlign.center);
    expect(body.maxLines, isNull);
    expect(body.overflow, isNull);
    final bodySpan = body.textSpan! as TextSpan;
    expect(
      bodySpan.toPlainText(),
      'Screenshots are not reliable. Anyone who has access to your phone '
      'or your photo library will be able to see your Secret Passphrase. '
      'Write down your Phrase on a piece of paper instead.',
    );
    expect(
      bodySpan.style,
      AppTypography.bodyMedium.copyWith(
        color: AppThemeData.light.colors.text.accent,
      ),
    );
    expect(
      (bodySpan.children!.first as TextSpan).style,
      AppTypography.bodyMediumStrong,
    );
    expect(buttonLabel.style, AppTypography.labelLarge);
    expect(tester.getSize(buttonFinder).height, 50);
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
