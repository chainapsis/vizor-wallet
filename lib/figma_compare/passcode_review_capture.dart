import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/features/onboarding/mobile/mobile_passcode_screen.dart';
import '../src/features/onboarding/mobile/mobile_unlock_screen.dart';
import '../src/features/onboarding/shared/onboarding_flow_args.dart';
import '../src/providers/biometric_unlock_provider.dart';
import '../src/services/biometric_unlock.dart';

/// Actual screen widgets with inert biometric state and no wallet operations.
/// The comparison test enters six fixture digits to reach confirmation.
Widget buildPasscodeReviewCreate(BuildContext context) => _frame(
  context,
  MobilePasscodeScreen(
    args: SetPasswordScreenArgs.create(mnemonic: 'visual fixture only'),
  ),
);

Widget buildPasscodeReviewUnlock(BuildContext context) =>
    _frame(context, const MobileUnlockScreen(autoPromptBiometric: false));

Widget _frame(BuildContext context, Widget child) {
  final media = MediaQuery.of(context);
  final padding = media.size.width == 393
      ? const EdgeInsets.only(top: 55, bottom: 24)
      : const EdgeInsets.only(top: 20, bottom: 25);
  return ProviderScope(
    overrides: [
      biometricUnlockProvider.overrideWith(_CaptureBiometrics.new),
      biometricUnlockEnabledHintProvider.overrideWithValue(false),
    ],
    child: MediaQuery(
      data: media.copyWith(padding: padding, viewPadding: padding),
      child: child,
    ),
  );
}

class _CaptureBiometrics extends BiometricUnlockNotifier {
  @override
  Future<BiometricUnlockState> build() async => const BiometricUnlockState(
    availability: BiometricAvailability(
      supported: true,
      enrolled: true,
      kind: BiometricKind.face,
    ),
    enabled: true,
  );
}
