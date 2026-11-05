import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/app_bootstrap.dart';
import '../src/features/accounts/screens/mobile/mobile_account_removal_passcode_screen.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/layout/mobile/mobile_window_layout.dart';
import '../src/core/layout/mobile/mobile_window_policy.dart';
import '../src/features/onboarding/mobile/mobile_passcode_screen.dart';
import '../src/features/onboarding/mobile/mobile_onboarding_progress.dart';
import '../src/features/onboarding/mobile/mobile_onboarding_progress_scope.dart';
import '../src/features/onboarding/shared/onboarding_flow_args.dart';
import '../src/features/onboarding/mobile/mobile_unlock_screen.dart';
import '../src/features/settings/screens/mobile/mobile_change_passcode_screen.dart';
import '../src/features/settings/screens/mobile/mobile_seed_phrase_screen.dart';
import '../src/features/settings/screens/mobile/mobile_viewing_key_screen.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/app_security_provider.dart';
import '../src/providers/biometric_unlock_provider.dart';

/// Real passcode screens with no wallet, storage, network or Rust dependency.
enum PasscodeCaptureScreen {
  change,
  create,
  unlock,
  viewingKey,
  seedPhrase,
  accountRemoval,
}

class MobilePasscodeCapture extends StatefulWidget {
  const MobilePasscodeCapture({
    required this.screen,
    this.biometric = BiometricUnlockState.initial,
    super.key,
  });

  final PasscodeCaptureScreen screen;
  final BiometricUnlockState biometric;

  @override
  State<MobilePasscodeCapture> createState() => _MobilePasscodeCaptureState();
}

class _MobilePasscodeCaptureState extends State<MobilePasscodeCapture> {
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final policy = MobileWindowPolicy.resolve(media);
    final pane = MobileWindowLayout.resolve(media: media).body;
    return ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          AppBootstrapState(
            initialLocation: '/unlock',
            initialAccountState: const AccountState(accounts: []),
            initialSyncSnapshot: AppSyncSnapshot.empty,
            network: 'main',
            rpcEndpointConfig: defaultRpcEndpointConfig('main'),
            themeMode: ThemeMode.light,
            privacyModeEnabled: false,
            isPasswordConfigured: true,
            isUnlocked: false,
            passwordRotationRecoveryFailed: false,
          ),
        ),
        appSecurityProvider.overrideWith(_CaptureSecurity.new),
        biometricUnlockProvider.overrideWith(
          () => _CaptureBiometrics(widget.biometric),
        ),
      ],
      child: MobileWindowPolicyScope(
        policy: policy,
        child: Align(
          child: SizedBox.fromSize(
            size: policy.usesWideLayout ? pane.size : media.size,
            child: MediaQuery(
              data: policy.usesWideLayout
                  ? mobilePaneMedia(media, pane)
                  : media,
              child: switch (widget.screen) {
                PasscodeCaptureScreen.accountRemoval =>
                  const MobileAccountRemovalPasscodeScreen(
                    isLastAccount: false,
                  ),
                PasscodeCaptureScreen.change =>
                  const MobileChangePasscodeScreen(),
                PasscodeCaptureScreen.create => MobileOnboardingProgressScope(
                  setupMode: OnboardingSetupMode.createPasscode,
                  child: MobilePasscodeScreen(
                    args: SetPasswordScreenArgs.create(
                      mnemonic:
                          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
                    ),
                  ),
                ),
                PasscodeCaptureScreen.unlock => const MobileUnlockScreen(
                  autoPromptBiometric: false,
                ),
                PasscodeCaptureScreen.viewingKey =>
                  const MobileViewingKeyScreen(),
                PasscodeCaptureScreen.seedPhrase => MobileSeedPhraseScreen(
                  screenshotStream: const Stream.empty(),
                  loadBirthday: false,
                ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptureSecurity extends AppSecurityNotifier {
  @override
  Future<bool> confirmPassword(String password) async => false;

  @override
  Future<bool> unlock(String password) async => false;
}

class _CaptureBiometrics extends BiometricUnlockNotifier {
  _CaptureBiometrics(this.initial);
  final BiometricUnlockState initial;

  @override
  Future<String?> readPasscode({required String reason}) async => null;
  @override
  Future<BiometricUnlockState> build() async => initial;
}

Widget buildMobilePasscodeChangeCapture(BuildContext context) =>
    const MobilePasscodeCapture(screen: PasscodeCaptureScreen.change);
Widget buildMobilePasscodeCreateCapture(BuildContext context) =>
    const MobilePasscodeCapture(screen: PasscodeCaptureScreen.create);
Widget buildMobilePasscodeUnlockCapture(BuildContext context) =>
    const MobilePasscodeCapture(screen: PasscodeCaptureScreen.unlock);
Widget buildMobilePasscodeViewingKeyCapture(BuildContext context) =>
    const MobilePasscodeCapture(screen: PasscodeCaptureScreen.viewingKey);
Widget buildMobilePasscodeSeedPhraseCapture(BuildContext context) =>
    const MobilePasscodeCapture(screen: PasscodeCaptureScreen.seedPhrase);

Widget buildMobilePasscodeAccountRemovalCapture(BuildContext context) =>
    const MobilePasscodeCapture(screen: PasscodeCaptureScreen.accountRemoval);
