import 'package:flutter/widgets.dart';

import '../../../core/account_name_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/app_text_field.dart';

class AccountNameModal extends StatefulWidget {
  const AccountNameModal({
    required this.accountName,
    required this.profilePictureId,
    required this.onCancel,
    required this.onUpdate,
    super.key,
  });

  final String accountName;
  final String profilePictureId;
  final VoidCallback onCancel;
  final Future<void> Function(String name) onUpdate;

  @override
  State<AccountNameModal> createState() => _AccountNameModalState();
}

class _AccountNameModalState extends State<AccountNameModal> {
  static const _fieldHeight = 86.0;
  static const _primaryButtonWidth = 112.0;

  final _controller = TextEditingController();
  bool _isSubmitting = false;
  String? _submitError;

  String get _trimmedName => _controller.text.trim();

  bool get _isLengthValid => isAccountNameLengthValid(_trimmedName);

  bool get _canUpdate =>
      !_isSubmitting &&
      _isLengthValid &&
      _trimmedName != widget.accountName.trim();

  String? get _messageText {
    if (_submitError != null) return _submitError;
    if (accountNameCharacterLength(_trimmedName) <= kAccountNameMaxCharacters) {
      return null;
    }
    return kAccountNameLengthMessage;
  }

  @override
  void initState() {
    super.initState();
    _controller.text = widget.accountName;
  }

  @override
  void didUpdateWidget(covariant AccountNameModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountName != widget.accountName) {
      _controller.text = widget.accountName;
      _submitError = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canUpdate) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      await widget.onUpdate(_trimmedName);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitError = "Couldn't update account name.";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _handleChanged() {
    setState(() {
      _submitError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _AccountNameModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AccountNameModalHeader(profilePictureId: widget.profilePictureId),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: _fieldHeight,
            child: AppTextField(
              label: 'Account name',
              hintText: 'Account name',
              controller: _controller,
              autofocus: true,
              enabled: !_isSubmitting,
              trailingSlotWidth: 40,
              inputHorizontalPadding: AppSpacing.s,
              messageText: _messageText,
              tone: _messageText == null
                  ? AppTextFieldTone.neutral
                  : AppTextFieldTone.destructive,
              onChanged: (_) => _handleChanged(),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              AppButton(
                onPressed: _isSubmitting ? null : widget.onCancel,
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.medium,
                child: const Text('Cancel'),
              ),
              const Spacer(),
              AppButton(
                onPressed: _canUpdate ? _submit : null,
                variant: AppButtonVariant.primary,
                size: AppButtonSize.medium,
                minWidth: _primaryButtonWidth,
                child: Text(_isSubmitting ? 'Updating...' : 'Update'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountNameModalCard extends StatelessWidget {
  const _AccountNameModalCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 312,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(
          color: colors.border.subtleOpacity,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
        boxShadow: _accountNameModalShadow(colors),
      ),
      child: child,
    );
  }
}

class _AccountNameModalHeader extends StatelessWidget {
  const _AccountNameModalHeader({required this.profilePictureId});

  final String profilePictureId;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppProfilePicture(
          profilePictureId: profilePictureId,
          size: AppProfilePictureSize.xLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Edit Name',
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyLarge.copyWith(
            color: context.colors.text.accent,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

List<BoxShadow> _accountNameModalShadow(AppColors colors) {
  return [
    BoxShadow(color: colors.shadows.regular, blurRadius: 1),
    BoxShadow(
      color: colors.shadows.regular,
      offset: const Offset(0, 4),
      blurRadius: 12,
    ),
    BoxShadow(
      color: colors.shadows.regular,
      offset: const Offset(0, 12),
      blurRadius: 28,
    ),
  ];
}
