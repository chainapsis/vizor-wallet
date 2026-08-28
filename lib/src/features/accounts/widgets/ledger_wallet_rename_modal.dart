import 'package:flutter/widgets.dart';

import '../../../core/account_name_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_text_field.dart';
import 'account_modal_card.dart';

class LedgerWalletRenameModal extends StatefulWidget {
  const LedgerWalletRenameModal({
    required this.initialName,
    required this.onCancel,
    required this.onRename,
    super.key,
  });

  final String initialName;
  final VoidCallback onCancel;
  final Future<void> Function(String name) onRename;

  @override
  State<LedgerWalletRenameModal> createState() =>
      _LedgerWalletRenameModalState();
}

class _LedgerWalletRenameModalState extends State<LedgerWalletRenameModal> {
  final _controller = TextEditingController();
  bool _isSubmitting = false;
  String? _submitError;

  String get _name => normalizeAccountName(_controller.text);
  bool get _canRename =>
      !_isSubmitting &&
      isAccountNameLengthValid(_name) &&
      _name != widget.initialName;

  String? get _messageText {
    if (_submitError != null) return _submitError;
    if (accountNameCharacterLength(_name) <= kAccountNameMaxCharacters) {
      return null;
    }
    return kAccountNameLengthMessage;
  }

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialName;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canRename) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      await widget.onRename(_name);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitError = "Couldn't rename group.");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AccountModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Rename group name',
            textAlign: TextAlign.center,
            style: AppTypography.headlineSmall.copyWith(
              color: context.colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            key: const ValueKey('ledger_wallet_rename_field'),
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
          const SizedBox(height: AppSpacing.md),
          AccountModalActions(
            onCancel: _isSubmitting ? null : widget.onCancel,
            actionLabel: _isSubmitting ? 'Renaming...' : 'Rename',
            onAction: _canRename ? _submit : null,
          ),
        ],
      ),
    );
  }
}
