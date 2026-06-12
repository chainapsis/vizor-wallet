import 'package:flutter/widgets.dart';

import '../../../core/account_name_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/app_text_field.dart';
import 'account_modal_card.dart';

/// The single edit-account modal from the accounts redesign: a centered
/// avatar with an edit badge (tap opens the profile-picture picker) above
/// the account-name field. Update commits the name and any picked picture
/// together; the picker round-trip is owned by the screen, which threads
/// the drafts back in through [initialName] / [profilePictureId].
class AccountEditModal extends StatefulWidget {
  const AccountEditModal({
    required this.accountName,
    required this.initialName,
    required this.profilePictureId,
    required this.profilePictureChanged,
    required this.onEditProfilePicture,
    required this.onNameChanged,
    required this.onCancel,
    required this.onUpdate,
    super.key,
  });

  /// Committed account name, for change detection.
  final String accountName;

  /// Draft name shown in the field (survives the picker round-trip).
  final String initialName;

  /// Draft profile picture shown in the avatar.
  final String profilePictureId;

  /// Whether the draft picture differs from the committed one; enables
  /// Update even when the name is unchanged.
  final bool profilePictureChanged;

  final VoidCallback onEditProfilePicture;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onCancel;
  final Future<void> Function(String name) onUpdate;

  @override
  State<AccountEditModal> createState() => _AccountEditModalState();
}

class _AccountEditModalState extends State<AccountEditModal> {
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
      (_trimmedName != widget.accountName.trim() ||
          widget.profilePictureChanged);

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
    _controller.text = widget.initialName;
  }

  @override
  void didUpdateWidget(covariant AccountEditModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different committed name means the modal was rebound to another
    // account while open (settings binds to the active account, and the
    // sidebar can switch it under the pane overlay). Drop the previous
    // account's text so Update can't commit it to the new account.
    if (oldWidget.accountName != widget.accountName) {
      _controller.text = widget.initialName;
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
        _submitError = "Couldn't update account.";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _handleChanged(String value) {
    widget.onNameChanged(value);
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
          _EditableAccountAvatar(
            profilePictureId: widget.profilePictureId,
            onPressed: _isSubmitting ? null : widget.onEditProfilePicture,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: _messageText == null
                ? _fieldHeight
                : _fieldWithMessageHeight,
            child: AppTextField(
              label: 'Account name',
              hintText: '1-20 characters',
              controller: _controller,
              autofocus: true,
              enabled: !_isSubmitting,
              inputHorizontalPadding: AppSpacing.s,
              messageText: _messageText,
              tone: _messageText == null
                  ? AppTextFieldTone.neutral
                  : AppTextFieldTone.destructive,
              onChanged: _handleChanged,
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

/// The modal's 72px avatar with the 24px edit badge in its bottom-right
/// corner; the whole cluster is one tap target into the picture picker.
class _EditableAccountAvatar extends StatelessWidget {
  const _EditableAccountAvatar({
    required this.profilePictureId,
    required this.onPressed,
  });

  final String profilePictureId;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: 'Change profile picture',
      child: MouseRegion(
        cursor: onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          key: const ValueKey('account_edit_profile_picture_button'),
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AppProfilePicture(
                  profilePictureId: profilePictureId,
                  size: AppProfilePictureSize.xxLarge,
                ),
                Positioned(
                  // Figma: 24px badge at (52,52) on the 72px avatar, ringed
                  // by a 3px outside stroke in the modal surface color.
                  left: 52,
                  top: 52,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: colors.background.inverse,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colors.background.base,
                        width: 3,
                        strokeAlign: BorderSide.strokeAlignOutside,
                      ),
                    ),
                    child: Center(
                      child: AppIcon(
                        AppIcons.edit,
                        size: 16,
                        color: colors.icon.inverse,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
