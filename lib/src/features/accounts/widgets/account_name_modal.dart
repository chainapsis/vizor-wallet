import 'package:flutter/widgets.dart';

import '../../../core/account_name_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/app_text_field.dart';
import 'account_modal_card.dart';

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
  static const _fieldHeight = 66.0;
  static const _fieldWithMessageHeight = 86.0;

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
    return AccountModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AccountNameModalHeader(profilePictureId: widget.profilePictureId),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: _messageText == null
                ? _fieldHeight
                : _fieldWithMessageHeight,
            child: AppTextField(
              label: 'New account name',
              hintText: '1-20 characters',
              controller: _controller,
              autofocus: true,
              enabled: !_isSubmitting,
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
          AccountModalActions(
            onCancel: _isSubmitting ? null : widget.onCancel,
            actionLabel: _isSubmitting ? 'Updating...' : 'Update',
            onAction: _canUpdate ? _submit : null,
          ),
        ],
      ),
    );
  }
}

class _AccountNameModalHeader extends StatelessWidget {
  const _AccountNameModalHeader({required this.profilePictureId});

  final String profilePictureId;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppProfilePicture(
          profilePictureId: profilePictureId,
          size: AppProfilePictureSize.large,
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Text(
            'Account name',
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
