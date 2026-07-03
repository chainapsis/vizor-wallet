import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/biometric_unlock_provider.dart';
import '../../../providers/device_owner_auth_provider.dart';
import '../../../providers/sync_provider.dart';

const kForgotPasscodeLastWarningArmDelay = Duration(seconds: 3);
const _kForgotPasscodeCountdownTick = Duration(seconds: 1);
const double _kForgotPasscodeButtonMinWidth = 196;

/// Figma `Forgot Passcode` (4885:23293): the first reset confirmation
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
      bodyGap: AppSpacing.md,
      bottomPadding: AppSpacing.base,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "If you can't remember your passcode, the only way to "
            'recover your account is to completely reset the Vizor app, '
            'which means deleting all accounts and requiring you to '
            'import accounts again.',
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('mobile_forgot_passcode_reset'),
            expand: true,
            constrainContent: true,
            minWidth: _kForgotPasscodeButtonMinWidth,
            onPressed: () => Navigator.of(context).pop(true),
            child: const _ModalButtonLabel('Continue to reset Vizor'),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            key: const ValueKey('mobile_forgot_passcode_cancel'),
            variant: AppButtonVariant.ghost,
            expand: true,
            constrainContent: true,
            minWidth: _kForgotPasscodeButtonMinWidth,
            onPressed: () => Navigator.of(context).pop(false),
            child: const _ModalButtonLabel('Cancel'),
          ),
        ],
      ),
    );
  }
}

/// Figma `Forgot Passcode Last warning` (4885:23490): the second,
/// irreversible-action confirmation shown after [ForgotPasscodeSheet].
/// Pops `true` only when the user taps the destructive "Reset Vizor"
/// button, so wiping the wallet always takes two deliberate confirmations.
class ForgotPasscodeLastWarningSheet extends StatelessWidget {
  const ForgotPasscodeLastWarningSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ForgotPasscodeLastWarningContent();
  }
}

class _ForgotPasscodeLastWarningContent extends StatefulWidget {
  const _ForgotPasscodeLastWarningContent();

  @override
  State<_ForgotPasscodeLastWarningContent> createState() =>
      _ForgotPasscodeLastWarningContentState();
}

class _ForgotPasscodeLastWarningContentState
    extends State<_ForgotPasscodeLastWarningContent> {
  Timer? _countdownTimer;
  var _remainingSeconds = kForgotPasscodeLastWarningArmDelay.inSeconds;

  bool get _armed => _remainingSeconds <= 0;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(_kForgotPasscodeCountdownTick, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remainingSeconds = _remainingSeconds > 0 ? _remainingSeconds - 1 : 0;
      });
      if (_armed) timer.cancel();
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final resetLabel =
        _armed ? 'Reset Vizor' : 'Reset after ${_remainingSeconds}s...';
    return MobileModalScaffold(
      title: 'Are you sure?',
      onClose: () => Navigator.of(context).pop(false),
      bodyGap: AppSpacing.md,
      bottomPadding: AppSpacing.base,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              children: [
                // Figma 4885:23490 emphasises the irreversible line in the
                // destructive magenta; the follow-up sits in plain accent.
                TextSpan(
                  text: "This can't be undone.\n",
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.destructive,
                  ),
                ),
                TextSpan(
                  text: 'Proceed on your responsibility.',
                  style: AppTypography.bodyMediumStrong.copyWith(
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
            constrainContent: true,
            minWidth: _kForgotPasscodeButtonMinWidth,
            leading: const Center(child: AppIcon(AppIcons.warning, size: 16.7)),
            onPressed: _armed ? () => Navigator.of(context).pop(true) : null,
            child: _ModalButtonLabel(resetLabel),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            key: const ValueKey('mobile_forgot_passcode_last_warning_cancel'),
            variant: AppButtonVariant.ghost,
            expand: true,
            constrainContent: true,
            minWidth: _kForgotPasscodeButtonMinWidth,
            onPressed: () => Navigator.of(context).pop(false),
            child: const _ModalButtonLabel('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _ModalButtonLabel extends StatelessWidget {
  const _ModalButtonLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Text(text),
    );
  }
}

/// Same reset sequence as the desktop lost-password flow: the only
/// recovery without the passcode is wiping the wallet and importing
/// again. The caller routes to `/welcome` on success and owns error
/// presentation.
Future<bool> resetWalletForForgottenPasscode(WidgetRef ref) async {
  final verified = await verifyDeviceOwnerForWalletReset(ref);
  if (!verified) return false;

  final syncNotifier = ref.read(syncProvider.notifier);
  await syncNotifier.clearSensitiveStateForLock();
  try {
    await ref.read(accountProvider.notifier).resetWallet();
  } finally {
    // Always drop the cached DB path so the next sync re-resolves the freshly
    // generated name, even if the reset threw after deleting the DB.
    syncNotifier.clearCachedWalletDbPath();
  }
  // The escrowed passcode belongs to the wiped wallet - drop it. Runs only on a
  // successful wipe: a failed reset leaves the wallet (and its escrow) intact,
  // and that escrow is a forgetful user's only remaining way back in.
  await ref.read(biometricUnlockProvider.notifier).disable();
  return true;
}
