import 'package:flutter/widgets.dart';

import '../../../core/security/password_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/password_text_field.dart';
import 'account_modal_card.dart';

enum AccountRemoveProgress { stoppingSync, removingAccount }

typedef AccountRemoveProgressCallback =
    void Function(AccountRemoveProgress progress);

class AccountRemoveModal extends StatefulWidget {
  const AccountRemoveModal({
    required this.accountName,
    required this.profilePictureId,
    required this.isLastAccount,
    required this.onCancel,
    required this.onConfirmPassword,
    required this.onRemove,
    super.key,
  });

  final String accountName;
  final String profilePictureId;
  final bool isLastAccount;
  final VoidCallback onCancel;
  final Future<bool> Function(String password) onConfirmPassword;
  final Future<void> Function(AccountRemoveProgressCallback onProgress)
  onRemove;

  @override
  State<AccountRemoveModal> createState() => _AccountRemoveModalState();
}

class _AccountRemoveModalState extends State<AccountRemoveModal> {
  static const _destructiveButtonWidth = kAccountModalButtonMinWidth;
  static const _destructiveLabelWidth = 84.0;
  static const _fieldHeight = 66.0;

  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  _AccountRemoveSubmitPhase? _submitPhase;
  String? _passwordError;
  String? _submitError;

  bool get _canSubmit =>
      !_isSubmitting && isWalletPasswordValid(_passwordController.text);

  String? get _passwordMessage {
    if (_passwordError != null) return _passwordError;
    return validateWalletPassword(_passwordController.text);
  }

  @override
  void dispose() {
    _passwordController.clear();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final passwordError = validateRequiredWalletPassword(
      _passwordController.text,
    );
    if (passwordError != null) {
      setState(() {
        _passwordError = passwordError;
        _submitError = null;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitPhase = _AccountRemoveSubmitPhase.checkingPassword;
      _passwordError = null;
      _submitError = null;
    });

    bool isPasswordValid;
    try {
      isPasswordValid = await widget.onConfirmPassword(
        _passwordController.text,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _passwordError = "Couldn't check your password. Please try again.";
        _isSubmitting = false;
        _submitPhase = null;
      });
      return;
    }

    if (!mounted) return;
    if (!isPasswordValid) {
      setState(() {
        _passwordError = 'Incorrect password. Please try again.';
        _isSubmitting = false;
        _submitPhase = null;
      });
      return;
    }

    setState(() {
      _passwordController.clear();
      _submitPhase = _AccountRemoveSubmitPhase.stoppingSync;
    });

    try {
      await widget.onRemove(_setProgress);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitError = widget.isLastAccount
            ? "Couldn't reset Vizor."
            : "Couldn't remove account.";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submitPhase = null;
        });
      }
    }
  }

  void _handlePasswordChanged() {
    setState(() {
      _passwordError = null;
      _submitError = null;
    });
  }

  void _setProgress(AccountRemoveProgress progress) {
    if (!mounted) return;
    final next = switch (progress) {
      AccountRemoveProgress.stoppingSync =>
        _AccountRemoveSubmitPhase.stoppingSync,
      AccountRemoveProgress.removingAccount =>
        _AccountRemoveSubmitPhase.removingAccount,
    };
    if (_submitPhase == next) return;
    setState(() {
      _submitPhase = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final passwordMessage = _passwordMessage;

    return AccountModalCard(
      bottomPadding: AppSpacing.sm,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AccountRemoveModalHeader(
            accountName: widget.accountName,
            profilePictureId: widget.profilePictureId,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _bodyText,
            textAlign: TextAlign.left,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: _fieldHeight,
            child: PasswordTextField(
              label: 'Password',
              hintText: 'Enter Your Password',
              leadingSlotWidth: 32,
              trailingSlotWidth: 40,
              inputHorizontalPadding: AppSpacing.s,
              controller: _passwordController,
              autofocus: true,
              enabled: !_isSubmitting,
              tone: passwordMessage == null
                  ? AppTextFieldTone.neutral
                  : AppTextFieldTone.destructive,
              onChanged: (_) => _handlePasswordChanged(),
              onSubmitted: (_) => _submit(),
            ),
          ),
          if (passwordMessage != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              passwordMessage,
              style: AppTypography.labelMedium.copyWith(
                color: context.colors.text.destructive,
              ),
            ),
          ],
          if (_submitError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _submitError!,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.destructive,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              AppButton(
                onPressed: _isSubmitting ? null : widget.onCancel,
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.medium,
                height: kAccountModalButtonHeight,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AppButton(
                    onPressed: _canSubmit ? _submit : null,
                    variant: AppButtonVariant.destructive,
                    size: AppButtonSize.medium,
                    height: kAccountModalButtonHeight,
                    minWidth: _destructiveButtonWidth,
                    leading: _isSubmitting
                        ? null
                        : const AppIcon(
                            AppIcons.trash,
                            size: AppIconSize.medium,
                          ),
                    child: _submitButton,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String get _bodyText {
    if (widget.isLastAccount) {
      return 'Removing this account will completely reset the Vizor app. '
          'This means deleting all accounts and requiring you to import '
          'accounts again.\n'
          'This cannot be undone.';
    }
    return "Are you sure you want to remove this account? "
        "This action can't be reverted.\n"
        'You will have to re-import your account.';
  }

  String get _submitButtonLabel {
    if (!_isSubmitting) {
      return widget.isLastAccount ? 'Reset Vizor' : 'Remove';
    }

    return switch (_submitPhase) {
      _AccountRemoveSubmitPhase.checkingPassword => 'Checking password...',
      _AccountRemoveSubmitPhase.stoppingSync => 'Stopping sync...',
      _AccountRemoveSubmitPhase.removingAccount =>
        widget.isLastAccount ? 'Resetting...' : 'Removing account...',
      null => widget.isLastAccount ? 'Resetting...' : 'Removing account...',
    };
  }

  Widget get _submitButton {
    final label = _submitButtonLabel;
    return SizedBox(
      width: _destructiveLabelWidth,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
  }
}

enum _AccountRemoveSubmitPhase {
  checkingPassword,
  stoppingSync,
  removingAccount,
}

class _AccountRemoveModalHeader extends StatelessWidget {
  const _AccountRemoveModalHeader({
    required this.accountName,
    required this.profilePictureId,
  });

  final String accountName;
  final String profilePictureId;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppProfilePicture(
          profilePictureId: profilePictureId,
          size: AppProfilePictureSize.large,
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            accountName,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
