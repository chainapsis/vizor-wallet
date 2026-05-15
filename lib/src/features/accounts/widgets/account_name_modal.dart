import 'package:flutter/widgets.dart';

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
  static const _buttonWidth = 280.0;
  static const _minNameLength = 1;
  static const _maxNameLength = 20;

  final _controller = TextEditingController();
  bool _isSubmitting = false;
  String? _submitError;

  String get _trimmedName => _controller.text.trim();

  bool get _isLengthValid =>
      _trimmedName.length >= _minNameLength &&
      _trimmedName.length <= _maxNameLength;

  bool get _canUpdate =>
      !_isSubmitting &&
      _isLengthValid &&
      _trimmedName != widget.accountName.trim();

  String? get _messageText {
    if (_submitError != null) return _submitError;
    if (_trimmedName.length <= _maxNameLength) return null;
    return 'Use up to 20 characters.';
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
      header: _AccountNameModalHeader(
        leading: _AccountNameModalAvatar(
          profilePictureId: widget.profilePictureId,
        ),
        title: widget.accountName,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _fieldHeight,
            child: AppTextField(
              label: 'New Account Name',
              hintText: '1-20 Characters',
              controller: _controller,
              autofocus: true,
              enabled: !_isSubmitting,
              trailingSlotWidth: 40,
              inputHorizontalPadding: AppSpacing.s,
              messageText: _messageText,
              tone:
                  _messageText == null
                      ? AppTextFieldTone.neutral
                      : AppTextFieldTone.destructive,
              onChanged: (_) => _handleChanged(),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            onPressed: _canUpdate ? _submit : null,
            variant: AppButtonVariant.primary,
            minWidth: _buttonWidth,
            child: Text(_isSubmitting ? 'Updating...' : 'Update'),
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
}

class _AccountNameModalCard extends StatelessWidget {
  const _AccountNameModalCard({required this.header, required this.child});

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
        children: [header, const SizedBox(height: AppSpacing.md), child],
      ),
    );
  }
}

class _AccountNameModalHeader extends StatelessWidget {
  const _AccountNameModalHeader({required this.leading, required this.title});

  final Widget leading;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        leading,
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            title,
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

class _AccountNameModalAvatar extends StatelessWidget {
  const _AccountNameModalAvatar({required this.profilePictureId});

  final String profilePictureId;

  @override
  Widget build(BuildContext context) {
    return AppProfilePicture(
      profilePictureId: profilePictureId,
      size: AppProfilePictureSize.large,
    );
  }
}
