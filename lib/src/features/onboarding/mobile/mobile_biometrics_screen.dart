import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/biometric_icon.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/biometric_unlock_provider.dart';
import '../../../services/biometric_unlock.dart';
import 'mobile_onboarding_scaffold.dart';

/// Biometric unlock opt-in — Figma `Biometrics FaceID` /
/// `Biometrics` (4394:83068 / 4394:83378). Enabling writes
/// the passcode escrow behind the device's biometric set; the passcode
/// remains the credential either way. Devices without biometric
/// hardware skip straight home; an un-enrolled set keeps the screen
/// and enabling explains itself.
class MobileBiometricsScreen extends ConsumerStatefulWidget {
  const MobileBiometricsScreen({super.key});

  @override
  ConsumerState<MobileBiometricsScreen> createState() =>
      _MobileBiometricsScreenState();
}

class _MobileBiometricsScreenState
    extends ConsumerState<MobileBiometricsScreen> {
  var _enabling = false;
  var _skipped = false;

  @override
  void initState() {
    super.initState();
    // No biometric hardware at all → the opt-in question cannot be
    // answered on this device; continue straight home. (Enrollment
    // missing is different: the screen stays, since the user can
    // enroll in the device settings.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_skipWithoutHardware());
    });
  }

  Future<void> _skipWithoutHardware() async {
    final state = await ref.read(biometricUnlockProvider.future);
    if (!mounted || _skipped || state.availability.supported) return;
    _skipped = true;
    context.go('/home');
  }

  Future<void> _enable() async {
    if (_enabling) return;
    setState(() => _enabling = true);
    var method = BiometricKind.none.inlineLabel;
    try {
      final state = await ref.read(biometricUnlockProvider.future);
      method = state.availability.kind.inlineLabel;
      if (!state.availability.usable) {
        if (!mounted) return;
        setState(() => _enabling = false);
        showAppToast(context, 'Set up $method in your device settings first.');
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
        "Couldn't enable $method. You can try again in settings.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final biometric = ref.watch(biometricUnlockProvider).value;
    final kind = biometric?.availability.kind ?? BiometricKind.none;

    return MobileOnboardingStepScaffold(
      progress: 1,
      showBackButton: false,
      aboveTitle: _BiometricHero(kind: kind),
      // Line breaks match the Figma title/subtitle wraps.
      title: 'Unlock your wallet\nwith ${kind.onboardingTitleSuffix}',
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
            onPressed: _enabling || biometric == null
                ? null
                : () => unawaited(_enable()),
            leading: BiometricIcon(kind: kind),
            child: Text(kind.enableLabel),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            key: const ValueKey('mobile_biometrics_not_now'),
            variant: AppButtonVariant.ghost,
            expand: true,
            onPressed: _enabling ? null : () => context.go('/home'),
            child: Text(
              'Not now',
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.primary,
              ),
            ),
          ),
        ],
      ),
      child: const SizedBox.shrink(),
    );
  }
}

class _BiometricHero extends StatelessWidget {
  const _BiometricHero({required this.kind});

  final BiometricKind kind;

  static const _frameHeight = 321.0;

  @override
  Widget build(BuildContext context) {
    if (kind == BiometricKind.none) {
      return const SizedBox(height: _frameHeight);
    }
    final isFingerprint =
        kind == BiometricKind.fingerprint || kind == BiometricKind.touchId;
    final assetName = isFingerprint
        ? 'assets/illustrations/biometrics_fingerprint_knight.png'
        : 'assets/illustrations/biometrics_faceid_knight.png';
    final imageHeight = isFingerprint ? 262.0 : 300.0;
    return SizedBox(
      height: _frameHeight,
      child: Center(
        child: Image.asset(assetName, height: imageHeight, fit: BoxFit.contain),
      ),
    );
  }
}
