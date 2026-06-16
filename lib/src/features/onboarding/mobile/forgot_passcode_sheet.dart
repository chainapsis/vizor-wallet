import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/biometric_unlock_provider.dart';
import '../../../providers/sync_provider.dart';

/// Figma `Forgot Passcode` (4596:50252): the first reset confirmation
/// sheet. Pops `true` when the user wants to proceed; the caller then
/// shows [ForgotPasscodeLastWarningSheet] as a second, irreversible-action
/// gate before actually wiping the wallet. Shown from the app-entry unlock
/// screen and the settings passcode verification step.
class ForgotPasscodeSheet extends StatelessWidget {
  const ForgotPasscodeSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileModalScaffold(
      title: 'Forgot Passcode?',
      onClose: () => Navigator.of(context).pop(false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "If you can't remember your passcode, the only way to "
            'recover your account is to completely reset the Vizor app, '
            'which means deleting all accounts and requiring you to '
            'import accounts again.',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('mobile_forgot_passcode_reset'),
            expand: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue to reset Vizor'),
          ),
          const SizedBox(height: AppSpacing.s),
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(false),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(
                    'Cancel',
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
    );
  }
}

/// Figma `Forgot Passcode Last warning` (4600:50435): the second,
/// irreversible-action confirmation shown after [ForgotPasscodeSheet].
/// Pops `true` only when the user taps the destructive "Reset Vizor"
/// button, so wiping the wallet always takes two deliberate confirmations.
class ForgotPasscodeLastWarningSheet extends StatelessWidget {
  const ForgotPasscodeLastWarningSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileModalScaffold(
      title: 'Are you sure?',
      onClose: () => Navigator.of(context).pop(false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              children: [
                // Figma 4752:26222 emphasises the irreversible line in the
                // destructive magenta; the follow-up sits in plain accent.
                TextSpan(
                  text: "This can't be undone.\n",
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.destructive,
                  ),
                ),
                TextSpan(
                  text: 'Proceed on your responsibility.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('mobile_forgot_passcode_last_warning_reset'),
            variant: AppButtonVariant.destructive,
            expand: true,
            leading: const AppIcon(AppIcons.warning),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset Vizor'),
          ),
          const SizedBox(height: AppSpacing.s),
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(false),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(
                    'Cancel',
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
    );
  }
}

/// Same reset sequence as the desktop lost-password flow: the only
/// recovery without the passcode is wiping the wallet and importing
/// again. The caller routes to `/welcome` on success and owns error
/// presentation.
Future<void> resetWalletForForgottenPasscode(WidgetRef ref) async {
  final syncNotifier = ref.read(syncProvider.notifier);
  await syncNotifier.clearSensitiveStateForLock();
  await ref.read(accountProvider.notifier).resetWallet();
  syncNotifier.clearCachedWalletDbPath();
  // The escrowed passcode belongs to the wiped wallet — drop it.
  await ref.read(biometricUnlockProvider.notifier).disable();
}
