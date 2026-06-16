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

  static String _methodLabel(BiometricKind kind) {
    return switch (kind) {
      BiometricKind.face => 'Face ID',
      BiometricKind.fingerprint => 'biometrics',
      BiometricKind.none => 'biometrics',
    };
  }

  static String _fallbackMethodLabel() {
    if (kIsWeb) return 'biometrics';
    return Platform.isIOS ? 'Face ID' : 'biometrics';
  }

  Future<void> _enable() async {
    if (_enabling) return;
    setState(() => _enabling = true);
    var method = _fallbackMethodLabel();
    try {
      final state = await ref.read(biometricUnlockProvider.future);
      method = _methodLabel(state.availability.kind);
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
    final method = biometric == null
        ? _fallbackMethodLabel()
        : _methodLabel(biometric.availability.kind);

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
