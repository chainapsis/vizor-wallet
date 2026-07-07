import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Icon, Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/biometric_unlock_provider.dart';
import '../../../services/biometric_unlock.dart';
import 'mobile_onboarding_scaffold.dart';
import '../../../../l10n/app_localizations.dart';

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

  static String _methodLabel(BiometricKind kind, AppLocalizations l10n) {
    return kind.inlineLabel(l10n);
  }

  static BiometricKind _fallbackKind() {
    if (kIsWeb) return BiometricKind.none;
    return Platform.isIOS ? BiometricKind.face : BiometricKind.fingerprint;
  }

  Future<void> _enable() async {
    if (_enabling) return;
    setState(() => _enabling = true);
    var method = _methodLabel(_fallbackKind(), AppLocalizations.of(context));
    try {
      final state = await ref.read(biometricUnlockProvider.future);
      if (!mounted) return;
      method = _methodLabel(
        state.availability.kind,
        AppLocalizations.of(context),
      );
      if (!state.availability.usable) {
        setState(() => _enabling = false);
        showAppToast(
          context,
          AppLocalizations.of(context).biometricSetUpFirst(method),
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
        AppLocalizations.of(context).biometricEnableFailed(method),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final biometric = ref.watch(biometricUnlockProvider).value;
    final kind = biometric?.availability.kind ?? _fallbackKind();

    return MobileOnboardingStepScaffold(
      progress: 1,
      showBackButton: false,
      aboveTitle: _BiometricHero(kind: kind),
      // Line breaks match the Figma title/subtitle wraps.
      title: AppLocalizations.of(context).onbBiometricsTitle(
        kind.onboardingTitleSuffix(AppLocalizations.of(context)),
      ),
      subtitle: AppLocalizations.of(context).onbBiometricsSubtitle,
      bottomArea: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            key: const ValueKey('mobile_biometrics_enable'),
            expand: true,
            onPressed: _enabling ? null : () => unawaited(_enable()),
            leading: kind == BiometricKind.face
                ? const AppIcon(AppIcons.faceId)
                : const Icon(Icons.fingerprint),
            child: Text(kind.enableLabel(AppLocalizations.of(context))),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            key: const ValueKey('mobile_biometrics_not_now'),
            variant: AppButtonVariant.ghost,
            expand: true,
            onPressed: _enabling ? null : () => context.go('/home'),
            child: Text(
              AppLocalizations.of(context).onbNotNow,
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
    final assetName = kind == BiometricKind.fingerprint
        ? 'assets/illustrations/biometrics_fingerprint_knight.png'
        : 'assets/illustrations/biometrics_faceid_knight.png';
    final imageHeight = kind == BiometricKind.fingerprint ? 262.0 : 300.0;
    return SizedBox(
      height: _frameHeight,
      child: Center(
        child: Image.asset(assetName, height: imageHeight, fit: BoxFit.contain),
      ),
    );
  }
}
