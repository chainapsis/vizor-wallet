import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/password_text_field.dart';
import '../../providers/device_owner_auth_provider.dart';
import '../../services/device_owner_auth.dart';

/// Windows-only credential prompt for the wallet-reset gate.
///
/// Windows has no consent API that can require the device password while
/// excluding Windows Hello biometrics, so — instead of a native OS prompt — the
/// reset gate renders this field and validates the typed Windows account
/// password through the `device_owner_auth` channel (`LogonUser`). A biometric
/// can never satisfy `LogonUser`, so the passcode-only guarantee holds by
/// construction. Returns true once the OS confirms the password, false on
/// cancel.
Future<bool> showWindowsAccountPasswordDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _WindowsAccountPasswordDialog(),
  );
  return confirmed ?? false;
}

class _WindowsAccountPasswordDialog extends ConsumerStatefulWidget {
  const _WindowsAccountPasswordDialog();

  @override
  ConsumerState<_WindowsAccountPasswordDialog> createState() =>
      _WindowsAccountPasswordDialogState();
}

class _WindowsAccountPasswordDialogState
    extends ConsumerState<_WindowsAccountPasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _verifying = false;
  String? _error;

  static const double _cardWidth = 396;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handlePasswordChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handlePasswordChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handlePasswordChanged() {
    if (_error == null || _verifying) return;
    setState(() => _error = null);
  }

  Future<void> _submit() async {
    final password = _controller.text;
    if (password.isEmpty || _verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final verified = await ref
          .read(deviceOwnerAuthProvider)
          .verify(reason: kWalletResetDeviceAuthReason, password: password);
      if (!mounted) return;
      if (verified) {
        Navigator.of(context).pop(true);
        return;
      }
      // LogonUser reported the password is wrong — let the user retry.
      setState(() {
        _verifying = false;
        _error = 'Incorrect password. Try again.';
      });
    } on DeviceOwnerAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error =
            e.kind == DeviceOwnerAuthErrorKind.unavailable
                ? "This Windows account can't be verified by password."
                : kWalletResetDeviceAuthFailedMessage;
      });
    }
  }

  void _cancel() => Navigator.of(context).pop(false);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: Container(
        width: _cardWidth,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: colors.surface.card,
          borderRadius: BorderRadius.circular(AppSpacing.md),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Confirm reset Vizor',
              style: AppTypography.displaySmall.copyWith(
                color: colors.text.accent,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Enter your Windows account password to reset Vizor. '
              'Windows Hello is not used.',
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.base),
            PasswordTextField(
              label: 'Windows password',
              hintText: 'Enter Windows password',
              showLabel: false,
              surface: AppTextFieldSurface.secondary,
              controller: _controller,
              autofocus: true,
              enabled: !_verifying,
              messageText: _error,
              tone:
                  _error == null
                      ? AppTextFieldTone.neutral
                      : AppTextFieldTone.destructive,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.base),
            AppButton(
              onPressed: _verifying ? null : _submit,
              variant: AppButtonVariant.primary,
              expand: true,
              child: const Text('Confirm reset'),
            ),
            const SizedBox(height: AppSpacing.s),
            AppButton(
              onPressed: _verifying ? null : _cancel,
              variant: AppButtonVariant.ghost,
              expand: true,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
