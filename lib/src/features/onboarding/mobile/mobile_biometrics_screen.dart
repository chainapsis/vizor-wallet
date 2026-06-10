import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/mobile/unsupported_sheet.dart';
import 'mobile_onboarding_scaffold.dart';

/// Biometric unlock opt-in — Figma `Biometrics FaceID` /
/// `Biometrics Fingerprint` (4394:83068 / 4394:83378). UI only for
/// now: enabling shows the unsupported sheet and the flow lands on
/// home either way. The wallet stays reachable through the passcode.
class MobileBiometricsScreen extends StatelessWidget {
  const MobileBiometricsScreen({super.key});

  static String get _methodLabel {
    if (kIsWeb) return 'biometrics';
    return Platform.isIOS ? 'Face ID' : 'fingerprint';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final method = _methodLabel;

    return MobileOnboardingStepScaffold(
      progress: 1,
      title: 'Unlock your wallet with $method',
      subtitle:
          'This is an easy and fast way to sign in. You can switch back '
          'to passcode anytime.',
      bottomArea: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            key: const ValueKey('mobile_biometrics_enable'),
            // TODO(mobile-biometrics): wire local authentication once
            // the dependency and security review land; passcode remains
            // the credential either way.
            onPressed: () async {
              await showUnsupportedSheet(
                context,
                message:
                    'Biometric unlock is still in progress. Your '
                    'passcode keeps your wallet safe in the meantime.',
              );
              if (context.mounted) context.go('/home');
            },
            child: Text('Enable $method'),
          ),
          const SizedBox(height: AppSpacing.s),
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.go('/home'),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(
                    'Not now',
                    key: const ValueKey('mobile_biometrics_not_now'),
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.md),
          // TODO(mobile-biometrics): swap in the dedicated mirror-knight
          // illustration once it is exported from Figma.
          Image.asset(
            'assets/illustrations/home_rest_character.png',
            height: 260,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }
}
