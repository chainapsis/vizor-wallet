import 'package:flutter/widgets.dart';

import '../../../core/account_name_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_text_field.dart';
import 'account_modal_card.dart';

class AccountGroupEditModal extends StatefulWidget {
  const AccountGroupEditModal({
    required this.anchorAccountUuid,
    required this.groupName,
    required this.onCancel,
    required this.onUpdate,
    super.key,
  });

  final String anchorAccountUuid;
  final String groupName;
  final VoidCallback onCancel;
  final Future<void> Function(String name) onUpdate;

  @override
  State<AccountGroupEditModal> createState() => _AccountGroupEditModalState();
}

class _AccountGroupEditModalState extends State<AccountGroupEditModal> {
  static const _fieldHeight = 66.0;
  static const _fieldWithMessageHeight = 86.0;

  late final TextEditingController _controller = TextEditingController(
    text: widget.groupName,
  );
  bool _isSubmitting = false;
  String? _submitError;

  String get _trimmedName => normalizeAccountName(_controller.text);
  bool get _isLengthValid => isAccountNameLengthValid(_trimmedName);
  bool get _canUpdate =>
      !_isSubmitting &&
      _isLengthValid &&
      _trimmedName != normalizeAccountName(widget.groupName);

  String? get _messageText {
    if (_submitError != null) return _submitError;
    if (accountNameCharacterLength(_trimmedName) <= kAccountNameMaxCharacters) {
      return null;
    }
    return kAccountNameLengthMessage;
  }

  @override
  void didUpdateWidget(covariant AccountGroupEditModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.anchorAccountUuid != widget.anchorAccountUuid) {
      _controller.text = widget.groupName;
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
      setState(() => _submitError = "Couldn't update the group.");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AccountModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Edit group name',
            style: AppTypography.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: context.colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: _messageText == null
                ? _fieldHeight
                : _fieldWithMessageHeight,
            child: AppTextField(
              key: const ValueKey('account_group_edit_name'),
              label: 'Group name',
              hintText: '1-20 characters',
              controller: _controller,
              autofocus: true,
              enabled: !_isSubmitting,
              inputHorizontalPadding: AppSpacing.s,
              messageText: _messageText,
              tone: _messageText == null
                  ? AppTextFieldTone.neutral
                  : AppTextFieldTone.destructive,
              onChanged: (_) => setState(() => _submitError = null),
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
