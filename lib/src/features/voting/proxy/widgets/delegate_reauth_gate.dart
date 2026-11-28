import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/app_form_factor.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/biometric_icon.dart';
import '../../../../providers/app_security_provider.dart';
import '../../../../providers/biometric_unlock_provider.dart';
import '../../../../services/biometric_unlock.dart';
import '../../../onboarding/mobile/mobile_passcode_screen.dart'
    show kMobilePasscodeLength;
import '../../../onboarding/mobile/passcode_widgets.dart';
import '../../../settings/widgets/confirm_access_card.dart';
import '../delegate_mode_repository.dart';

/// What a delegate-mode re-auth unlocks; it words the prompt.
enum DelegateReauthPurpose {
  /// Showing the delegate key's export.
  exportKey,

  /// Signing REGISTER with a new delegate key.
  register,

  /// Signing the round's ballot (DG-10).
  signBallot,

  /// Signing RETIRE for the entry (DG-11).
  retire;

  /// Subtitle under the gate's title.
  String subtitle(AppLocalizations l10n) => switch (this) {
    exportKey => l10n.delegateReauthExportSubtitle,
    register => l10n.delegateReauthRegisterSubtitle,
    signBallot => l10n.delegateReauthBallotSubtitle,
    retire => l10n.delegateReauthRetireSubtitle,
  };

  /// Reason the OS biometric prompt shows.
  String biometricReason(AppLocalizations l10n) => switch (this) {
    exportKey => l10n.delegateReauthExportBiometricReason,
    register => l10n.delegateReauthRegisterBiometricReason,
    signBallot => l10n.delegateReauthBallotBiometricReason,
    retire => l10n.delegateReauthRetireBiometricReason,
  };
}

/// Confirms access before a delegate-mode secret is used. Resolves true
/// only after the check passes, false when the user backs out.
typedef DelegateReauth =
    Future<bool> Function(BuildContext context, DelegateReauthPurpose purpose);

/// The re-auth every DG screen calls. Production shows the app's own
/// confirm-access gate; tests override it.
final delegateReauthProvider = Provider<DelegateReauth>(
  (_) => showDelegateReauthGate,
);

/// How a signing call on [context] confirms presence for [purpose]: the
/// app's re-auth, which the repository asks right before the key signs.
DelegateReauthCheck delegateSigningReauth(
  BuildContext context,
  WidgetRef ref,
  DelegateReauthPurpose purpose,
) {
  final reauth = ref.read(delegateReauthProvider);
  return () async => context.mounted && await reauth(context, purpose);
}

/// Shows the app's confirm-access gate for [purpose], as the secret
/// passphrase screens do: the wallet password on desktop, the passcode or
/// biometrics on mobile, both checked with `confirmPassword`. Resolves
/// false when dismissed.
Future<bool> showDelegateReauthGate(
  BuildContext context,
  DelegateReauthPurpose purpose,
) async {
  final bool? confirmed;
  if (kAppFormFactor == AppFormFactor.mobile) {
    confirmed = await showAppMobileSheet<bool>(
      context: context,
      builder: (_) => DelegateReauthPasscodeSheet(purpose: purpose),
    );
  } else {
    confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => DelegateReauthPasswordDialog(purpose: purpose),
    );
  }
  return confirmed ?? false;
}

/// Desktop gate: the shared confirm-access card in a dialog. Pops true once
/// the wallet password verifies.
class DelegateReauthPasswordDialog extends ConsumerStatefulWidget {
  /// Creates the dialog for [purpose].
  const DelegateReauthPasswordDialog({required this.purpose, super.key});

  /// What the confirmation unlocks.
  final DelegateReauthPurpose purpose;

  @override
  ConsumerState<DelegateReauthPasswordDialog> createState() =>
      _DelegateReauthPasswordDialogState();
}

class _DelegateReauthPasswordDialogState
    extends ConsumerState<DelegateReauthPasswordDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Checks the typed password and pops true when it verifies.
  Future<void> _submit() async {
    if (_checking || _controller.text.isEmpty) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final l10n = context.l10n;
    bool valid;
    try {
      valid = await ref
          .read(appSecurityProvider.notifier)
          .confirmPassword(_controller.text);
    } catch (_) {
      valid = false;
      _error = l10n.delegateReauthFailed;
    }
    if (!mounted) return;
    if (valid) {
      Navigator.of(context).pop(true);
      return;
    }
    _controller.clear();
    setState(() {
      _checking = false;
      _error ??= context.l10n.passwordIncorrect;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConfirmAccessCard(
            key: const ValueKey('delegate_reauth_card'),
            subtitle: widget.purpose.subtitle(context.l10n),
            controller: _controller,
            errorText: _error,
            isSubmitting: _checking,
            canSubmit: _controller.text.isNotEmpty,
            onChanged: () => setState(() => _error = null),
            onSubmit: _submit,
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            width: ConfirmAccessCard.width,
            child: AppButton(
              key: const ValueKey('delegate_reauth_cancel'),
              onPressed: _checking
                  ? null
                  : () => Navigator.of(context).pop(false),
              variant: AppButtonVariant.secondary,
              expand: true,
              child: Text(context.l10n.commonCancel),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mobile gate: the app's passcode numpad, offering biometrics first when
/// enabled. Pops true once the passcode verifies.
class DelegateReauthPasscodeSheet extends ConsumerStatefulWidget {
  /// Creates the sheet for [purpose].
  const DelegateReauthPasscodeSheet({required this.purpose, super.key});

  /// What the confirmation unlocks.
  final DelegateReauthPurpose purpose;

  @override
  ConsumerState<DelegateReauthPasscodeSheet> createState() =>
      _DelegateReauthPasscodeSheetState();
}

class _DelegateReauthPasscodeSheetState
    extends ConsumerState<DelegateReauthPasscodeSheet> {
  String _entry = '';
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_tryBiometric());
    });
  }

  /// The biometric state, or the unavailable state when it cannot load.
  Future<BiometricUnlockState> _biometric() async {
    try {
      return await ref.read(biometricUnlockProvider.future);
    } catch (_) {
      return BiometricUnlockState.initial;
    }
  }

  /// Reads the escrowed passcode with the OS prompt, then verifies it.
  Future<void> _tryBiometric() async {
    if (_checking) return;
    final biometric = await _biometric();
    if (!mounted || !biometric.usable) return;
    setState(() => _checking = true);
    final passcode = await ref
        .read(biometricUnlockProvider.notifier)
        .readPasscode(reason: widget.purpose.biometricReason(context.l10n));
    if (!mounted) return;
    if (passcode == null) {
      setState(() {
        _entry = '';
        _checking = false;
      });
      return;
    }
    _entry = passcode;
    await _confirm();
  }

  /// Adds [digit] and submits at the full passcode length.
  void _onDigit(int digit) {
    if (_checking || _entry.length >= kMobilePasscodeLength) return;
    setState(() {
      _entry += '$digit';
      _error = null;
    });
    if (_entry.length == kMobilePasscodeLength) unawaited(_confirm());
  }

  /// Removes the last digit.
  void _onBackspace() {
    if (_checking || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  /// Verifies the entered passcode and pops true when it is right.
  Future<void> _confirm() async {
    setState(() => _checking = true);
    final l10n = context.l10n;
    bool valid;
    String? error;
    try {
      valid = await ref
          .read(appSecurityProvider.notifier)
          .confirmPassword(_entry);
    } catch (_) {
      valid = false;
      error = l10n.delegateReauthFailed;
    }
    if (!mounted) return;
    if (valid) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _entry = '';
      _checking = false;
      _error = error ?? context.l10n.settingsIncorrectPasscode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final biometric =
        ref.watch(biometricUnlockProvider).value ??
        BiometricUnlockState.initial;
    final showBiometric = !_checking && biometric.usable;
    return MobileModalScaffold(
      title: context.l10n.settingsEnterPasscodeTitle,
      showTitle: false,
      onClose: () => Navigator.of(context).pop(false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.settingsEnterPasscodeTitle,
            textAlign: TextAlign.center,
            style: AppTypography.displaySmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.purpose.subtitle(context.l10n),
            textAlign: TextAlign.center,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.primary,
            ),
          ),
          SizedBox(
            height: kPasscodePromptDigitsHeight,
            child: PasscodePromptField(
              length: kMobilePasscodeLength,
              filled: _entry.length,
              error: _error,
              minGap: 0,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          PasscodeNumpad(
            onDigit: _onDigit,
            onBackspace: _onBackspace,
            canDelete: _entry.isNotEmpty,
            enabled: !_checking,
          ),
          if (showBiometric) ...[
            const SizedBox(height: AppSpacing.s),
            PasscodeBiometricButton(
              label: biometric.availability.kind.signInLabel(context.l10n),
              icon: Center(
                child: BiometricIcon(
                  kind: biometric.availability.kind,
                  size: 13.5,
                  fingerprintSize: 16,
                ),
              ),
              onPressed: () => unawaited(_tryBiometric()),
            ),
          ],
        ],
      ),
    );
  }
}
