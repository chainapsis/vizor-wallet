@Tags(['mobile'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/forgot_passcode_sheet.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_unlock_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/passcode_widgets.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_auth_shell.dart';
import 'package:zcash_wallet/widgetbook/screen_use_cases.dart';

void main() {
  testWidgets('mobile lock use cases render biometric variants', (
    tester,
  ) async {
    await _pumpMobileLockUseCase(tester, buildMobileUnlockPasscodeUseCase);
    expect(tester.takeException(), isNull);
    expect(find.byType(MobileUnlockScreen), findsOneWidget);
    expect(find.text('Sign in with Face ID'), findsNothing);
    expect(find.text('Sign in with biometrics'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_unlock_biometric_footer')),
      findsOneWidget,
    );
    final keypadTopWithoutBiometrics = tester
        .getTopLeft(find.byType(PasscodeNumpad))
        .dy;
    final keypadBottomWithoutBiometrics = tester
        .getBottomLeft(find.byType(PasscodeNumpad))
        .dy;
    final footerTop = tester
        .getTopLeft(
          find.byKey(const ValueKey('mobile_unlock_biometric_footer')),
        )
        .dy;
    expect(
      footerTop - keypadBottomWithoutBiometrics,
      closeTo(AppSpacing.md, 0.1),
    );

    await _pumpMobileLockUseCase(tester, buildMobileUnlockFaceIdUseCase);
    expect(tester.takeException(), isNull);
    expect(find.text('Sign in with Face ID'), findsOneWidget);
    expect(find.text('Sign in with biometrics'), findsNothing);
    expect(
      tester.getTopLeft(find.byType(PasscodeNumpad)).dy,
      closeTo(keypadTopWithoutBiometrics, 0.1),
    );
    final biometricButtonSize = tester.getSize(
      find.byKey(const ValueKey('passcode_biometric_button')),
    );
    expect(biometricButtonSize.height, 36);
    expect(biometricButtonSize.width, greaterThan(150));
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

    await _pumpMobileLockUseCase(tester, buildMobileUnlockBiometricsUseCase);
    expect(tester.takeException(), isNull);
    expect(find.text('Sign in with biometrics'), findsOneWidget);
    expect(find.text('Sign in with Face ID'), findsNothing);
    final biometricsButtonSize = tester.getSize(
      find.byKey(const ValueKey('passcode_biometric_button')),
    );
    expect(biometricsButtonSize.height, 36);
    expect(biometricsButtonSize.width, greaterThan(150));
  });

  testWidgets('mobile lock use cases render the biometric sign-in backdrop', (
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

  testWidgets('last-warning reset arms after the desktop countdown', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
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
      key: UniqueKey(),
      home: AppTheme(
        data: theme,
        child: Builder(builder: builder),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
