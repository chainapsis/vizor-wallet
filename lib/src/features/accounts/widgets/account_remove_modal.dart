import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';

class AccountRemoveModal extends StatefulWidget {
  const AccountRemoveModal({
    required this.accountName,
    required this.profilePictureId,
    required this.isLastAccount,
    required this.onCancel,
    required this.onRemove,
    super.key,
  });

  final String accountName;
  final String profilePictureId;
  final bool isLastAccount;
  final VoidCallback onCancel;
  final Future<void> Function() onRemove;

  @override
  State<AccountRemoveModal> createState() => _AccountRemoveModalState();
}

class _AccountRemoveModalState extends State<AccountRemoveModal> {
  static const _buttonWidth = 280.0;

  bool _isSubmitting = false;
  String? _submitError;

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      await widget.onRemove();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitError = "Couldn't remove account.";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AccountRemoveModalCard(
      header: _AccountRemoveModalHeader(
        accountName: widget.accountName,
        profilePictureId: widget.profilePictureId,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _bodyText,
            textAlign: TextAlign.left,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.accent,
            ),
          ),
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
          AppButton(
            onPressed: _isSubmitting ? null : _submit,
            variant: AppButtonVariant.destructive,
            minWidth: _buttonWidth,
            leading: const AppIcon(AppIcons.trash),
            child: Text(_submitButtonLabel),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            onPressed: _isSubmitting ? null : widget.onCancel,
            variant: AppButtonVariant.ghost,
            minWidth: _buttonWidth,
            child: const Text('Cancel'),
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
    if (_isSubmitting) {
      return widget.isLastAccount ? 'Resetting...' : 'Removing...';
    }
    return widget.isLastAccount ? 'Reset Vizor' : 'Remove';
  }
}

class _AccountRemoveModalCard extends StatelessWidget {
  const _AccountRemoveModalCard({required this.header, required this.child});

  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 312,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: context.colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
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
