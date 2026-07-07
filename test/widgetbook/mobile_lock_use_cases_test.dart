@Tags(['mobile'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Icons, MaterialApp;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/privacy/sensitive_privacy_overlay.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/forgot_passcode_sheet.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_unlock_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/passcode_widgets.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_auth_shell.dart';
import 'package:zcash_wallet/widgetbook/screen_use_cases.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('mobile lock use cases render method-specific variants', (
    tester,
  ) async {
    await _pumpMobileLockUseCase(tester, buildMobileUnlockPasscodeUseCase);
    expect(tester.takeException(), isNull);
    expect(find.byType(MobileUnlockScreen), findsOneWidget);
    expect(find.text('Sign in with Face ID'), findsNothing);
    expect(find.text('Sign in with fingerprint'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_unlock_biometric_footer')),
      findsOneWidget,
    );
    final keypadTopWithoutMethod = tester
        .getTopLeft(find.byType(PasscodeNumpad))
        .dy;
    final keypadBottomWithoutMethod = tester
        .getBottomLeft(find.byType(PasscodeNumpad))
        .dy;
    final footerTop = tester
        .getTopLeft(
          find.byKey(const ValueKey('mobile_unlock_biometric_footer')),
        )
        .dy;
    expect(footerTop - keypadBottomWithoutMethod, closeTo(AppSpacing.md, 0.1));

    await _pumpMobileLockUseCase(tester, buildMobileUnlockFaceIdUseCase);
    expect(tester.takeException(), isNull);
    expect(find.text('Sign in with Face ID'), findsOneWidget);
    expect(find.text('Sign in with fingerprint'), findsNothing);
    expect(
      tester.getTopLeft(find.byType(PasscodeNumpad)).dy,
      closeTo(keypadTopWithoutMethod, 0.1),
    );
    final faceIdButtonSize = tester.getSize(
      find.byKey(const ValueKey('passcode_biometric_button')),
    );
    expect(faceIdButtonSize.height, 36);
    expect(faceIdButtonSize.width, greaterThan(150));
    final faceIdLabel = tester.widget<Text>(find.text('Sign in with Face ID'));
    expect(faceIdLabel.style?.fontSize, AppTypography.labelLarge.fontSize);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIcon &&
            widget.name == AppIcons.faceId &&
            widget.size == 13.5,
      ),
      findsOneWidget,
    );

    await _pumpMobileLockUseCase(tester, buildMobileUnlockFingerprintUseCase);
    expect(tester.takeException(), isNull);
    expect(find.text('Sign in with fingerprint'), findsOneWidget);
    expect(find.text('Sign in with Face ID'), findsNothing);
    final fingerprintButtonSize = tester.getSize(
      find.byKey(const ValueKey('passcode_biometric_button')),
    );
    expect(fingerprintButtonSize.height, 36);
    expect(fingerprintButtonSize.width, greaterThan(150));
  });

  testWidgets('mobile onboarding use cases render simulator-hard states', (
    tester,
  ) async {
    await _pumpMobileLockUseCase(
      tester,
      buildMobileSecretPassphraseRevealedUseCase,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Secret Passphrase'), findsWidgets);
    expect(find.text('abandon'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);

    await _pumpMobileLockUseCase(
      tester,
      buildMobileSecretPassphraseProtectedUseCase,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('abandon'), findsOneWidget);
    expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);

    await _pumpMobileLockUseCase(
      tester,
      buildMobileSecretPassphraseScreenshotWarningUseCase,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('abandon'), findsOneWidget);
    expect(
      find.text('Don’t take screenshots of your Secret Passphrase'),
      findsOneWidget,
    );
    expect(find.text('I understand'), findsOneWidget);

    await _pumpMobileLockUseCase(tester, buildMobileCreatePasscodeUseCase);
    expect(tester.takeException(), isNull);
    expect(find.text('Create Passcode'), findsOneWidget);
    expect(find.text('6 digits length'), findsOneWidget);
    expect(find.byType(PasscodeNumpad), findsOneWidget);
    final passcodeTitle = tester.widget<Text>(find.text('Create Passcode'));
    expect(passcodeTitle.style?.fontSize, AppTypography.displayLarge.fontSize);

    await _pumpMobileLockUseCase(tester, buildMobileFaceIdOptInUseCase);
    expect(tester.takeException(), isNull);
    expect(find.text('Unlock your wallet\nwith Face ID'), findsOneWidget);
    final faceIdTitle = tester.widget<Text>(
      find.text('Unlock your wallet\nwith Face ID'),
    );
    expect(faceIdTitle.style?.fontSize, AppTypography.displayLarge.fontSize);
    expect(find.bySemanticsLabel('Back'), findsNothing);
    expect(find.text('Enable Face ID'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.faceId,
      ),
      findsOneWidget,
    );

    await _pumpMobileLockUseCase(tester, buildMobileFingerprintOptInUseCase);
    expect(tester.takeException(), isNull);
    expect(
      find.text('Unlock your wallet\nwith your fingerprint'),
      findsOneWidget,
    );
    expect(find.text('Enable fingerprint'), findsOneWidget);
    expect(find.byIcon(Icons.fingerprint), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/illustrations/biometrics_fingerprint_knight.png',
      ),
      findsOneWidget,
    );
  });

  testWidgets('mobile lock use cases render the Face ID sign-in backdrop', (
    tester,
  ) async {
    await _pumpMobileLockUseCase(
      tester,
      buildMobileUnlockBiometricBackdropUseCase,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(MobileBiometricSignInView), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_biometric_sign_in_background')),
      findsOneWidget,
    );
    final backgroundImage = tester.widget<Image>(
      find.byKey(const ValueKey('mobile_biometric_sign_in_background')),
    );
    expect(
      (backgroundImage.image as AssetImage).assetName,
      mobileBiometricSignInBackgroundAsset,
    );
    final backgroundSize = tester.getSize(
      find.byKey(const ValueKey('mobile_biometric_sign_in_background')),
    );
    expect(backgroundSize.width, closeTo(392, 0.1));
    expect(backgroundSize.height, closeTo(720, 0.1));
    expect(
      find.byKey(const ValueKey('mobile_biometric_sign_in_badge')),
      findsOneWidget,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_biometric_sign_in_badge')),
      ),
      const Size(130, 130),
    );
    expect(
      find.byKey(const ValueKey('mobile_biometric_prompt_preview')),
      findsNothing,
    );
    expect(find.byType(PasscodeNumpad), findsNothing);
  });

  testWidgets('passcode numpad fits a narrow padded phone width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates:
            AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AppTheme(
          data: AppThemeData.light,
          child: Center(
            child: SizedBox(
              width: 288,
              child: PasscodeNumpad(
                onDigit: (_) {},
                onBackspace: () {},
                canDelete: true,
                onHelp: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(PasscodeNumpad)).width, 288);
  });

  testWidgets('keeps desktop and mobile auth backgrounds separate', (
    tester,
  ) async {
    expect(_pngSize(onboardingAuthBackgroundAsset), const Size(1344, 720));
    expect(
      _pngSize(mobileBiometricSignInBackgroundAsset),
      const Size(392, 720),
    );
  });

  testWidgets('mobile lock modal use cases render forgot-passcode states', (
    tester,
  ) async {
    await _pumpMobileLockUseCase(tester, buildMobileForgotPasscodeSheetUseCase);
    expect(tester.takeException(), isNull);
    expect(find.text('Forgot Passcode?'), findsOneWidget);
    expect(find.text('Continue to reset Vizor'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    final forgotBody = tester.widget<Text>(
      find.textContaining("If you can't remember your passcode"),
    );
    expect(forgotBody.style?.color, AppThemeData.light.colors.text.accent);
    final continueButton = tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_forgot_passcode_reset')),
    );
    expect(continueButton.variant, AppButtonVariant.primary);
    expect(continueButton.height, isNull);
    expect(continueButton.expand, isTrue);
    expect(continueButton.minWidth, 196);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_forgot_passcode_reset')),
      ),
      const Size(329, AppButtonSizing.largeHeight),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_forgot_passcode_cancel')),
      ),
      const Size(329, AppButtonSizing.largeHeight),
    );

    await _pumpMobileLockUseCase(
      tester,
      buildMobileForgotPasscodeLastWarningUseCase,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Are you sure?'), findsOneWidget);
    expect(
      find.textContaining("This can't be undone.", findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Reset after 3s...'), findsOneWidget);
    final resetButton = tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_forgot_passcode_last_warning_reset')),
    );
    expect(resetButton.variant, AppButtonVariant.destructive);
    expect(resetButton.height, isNull);
    expect(resetButton.expand, isTrue);
    expect(resetButton.minWidth, 196);
    expect(resetButton.onPressed, isNull);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_forgot_passcode_last_warning_reset')),
      ),
      const Size(329, AppButtonSizing.largeHeight),
    );
    expect(
      tester.getSize(
        find.byKey(
          const ValueKey('mobile_forgot_passcode_last_warning_cancel'),
        ),
      ),
      const Size(329, AppButtonSizing.largeHeight),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIcon &&
            widget.name == AppIcons.warning &&
            widget.size == 16.7,
      ),
      findsOneWidget,
    );
  });

  testWidgets('mobile lock modal use cases render screenshot warning', (
    tester,
  ) async {
    await _pumpMobileLockUseCase(
      tester,
      buildMobileSeedScreenshotWarningSheetUseCase,
    );
    expect(tester.takeException(), isNull);
    expect(
      find.text('Don’t take screenshots of your Secret Passphrase'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Screenshots are not reliable', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('I understand'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('mobile_seed_screenshot_title')))
          .width,
      253,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_seed_screenshot_ack'))),
      const Size(329, AppButtonSizing.largeHeight),
    );
  });

  testWidgets('last-warning reset arms after the desktop countdown', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates:
            AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AppTheme(
          data: AppThemeData.light,
          child: ForgotPasscodeLastWarningSheet(),
        ),
      ),
    );
    await tester.pump();

    AppButton resetButton() => tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_forgot_passcode_last_warning_reset')),
    );

    expect(find.text('Reset after 3s...'), findsOneWidget);
    expect(resetButton().onPressed, isNull);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Reset after 2s...'), findsOneWidget);
    expect(resetButton().onPressed, isNull);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Reset after 1s...'), findsOneWidget);
    expect(resetButton().onPressed, isNull);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Reset Vizor'), findsOneWidget);
    expect(resetButton().onPressed, isNotNull);
  });
}

Size _pngSize(String assetPath) {
  final bytes = File(assetPath).readAsBytesSync();
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  return Size(
    data.getUint32(16, Endian.big).toDouble(),
    data.getUint32(20, Endian.big).toDouble(),
  );
}

Future<void> _pumpMobileLockUseCase(
  WidgetTester tester,
  WidgetBuilder builder, {
  AppThemeData theme = AppThemeData.light,
}) async {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      key: UniqueKey(),
      home: AppTheme(
        data: theme,
        child: Builder(builder: builder),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _loadAppFonts() async {
  final geist = FontLoader('Geist')
    ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'));
  final youngSerif = FontLoader('Young Serif')
    ..addFont(rootBundle.load('assets/fonts/YoungSerif-Regular.ttf'));

  await Future.wait([geist.load(), youngSerif.load()]);
}
