import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/biometric_unlock_provider.dart';
import 'mobile_onboarding_scaffold.dart';

/// Biometric unlock opt-in — Figma `Biometrics FaceID` /
/// `Biometrics Fingerprint` (4394:83068 / 4394:83378). Enabling writes
/// the passcode escrow behind the device's biometric set; the passcode
/// remains the credential either way. Without an enrolled biometric
/// set, enabling explains itself and "Not now" continues home.
class MobileBiometricsScreen extends ConsumerStatefulWidget {
  const MobileBiometricsScreen({super.key});

  @override
  ConsumerState<MobileBiometricsScreen> createState() =>
      _MobileBiometricsScreenState();
}

class _MobileBiometricsScreenState
    extends ConsumerState<MobileBiometricsScreen> {
  var _enabling = false;

  static String get _methodLabel {
    if (kIsWeb) return 'biometrics';
    return Platform.isIOS ? 'Face ID' : 'fingerprint';
  }

  Future<void> _enable() async {
    if (_enabling) return;
    setState(() => _enabling = true);
    try {
      final state = await ref.read(biometricUnlockProvider.future);
      if (!state.availability.usable) {
        if (!mounted) return;
        setState(() => _enabling = false);
        showAppToast(
          context,
          'Set up $_methodLabel in your device settings first.',
        );
        return;
      }
      final passcode = ref
          .read(appSecurityProvider.notifier)
          .requireSessionPasswordForNativeSecretUse();
      await ref.read(biometricUnlockProvider.notifier).enable(passcode);
      if (!mounted) return;
      context.go('/home');
    } catch (e, st) {
      log('MobileBiometrics._enable: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() => _enabling = false);
      showAppToast(
        context,
        "Couldn't enable $_methodLabel. You can try again in settings.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final method = _methodLabel;

    return MobileOnboardingStepScaffold(
      progress: 1,
      aboveTitle: Image.asset(
        'assets/illustrations/biometrics_faceid_knight.png',
        height: 300,
        fit: BoxFit.contain,
      ),
      // Line breaks match the Figma title/subtitle wraps.
      title: 'Unlock your wallet\nwith $method',
      subtitle:
          'This is an easy and fast way to sign in.\n'
          'You can switch back to passcode anytime.',
      bottomArea: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            key: const ValueKey('mobile_biometrics_enable'),
            expand: true,
            onPressed: _enabling ? null : () => unawaited(_enable()),
            child: Text('Enable $method'),
          ),
          const SizedBox(height: AppSpacing.s),
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _enabling ? null : () => context.go('/home'),
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
      child: const SizedBox.shrink(),
    );
  }
}
