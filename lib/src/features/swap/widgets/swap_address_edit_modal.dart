import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/models/address_format_validator.dart';
import '../models/swap_models.dart';
import 'swap_modal_controls.dart';

typedef SwapAddressSubmitCallback =
    void Function(
      String value,
      bool remember,
      String? nickname,
      String profilePictureId,
    );

class SwapAddressEditModal extends StatefulWidget {
  const SwapAddressEditModal({
    required this.state,
    required this.onSubmitted,
    required this.onScan,
    required this.onOpenContacts,
    required this.onCancel,
    super.key,
  });

  final SwapState state;
  final SwapAddressSubmitCallback onSubmitted;
  final VoidCallback onScan;
  final VoidCallback onOpenContacts;
  final VoidCallback onCancel;

  @override
  State<SwapAddressEditModal> createState() => _SwapAddressEditModalState();
}

class _SwapAddressEditModalState extends State<SwapAddressEditModal> {
  late final TextEditingController _controller;
  late final TextEditingController _nicknameController;
  late final FocusNode _focusNode;
  late final FocusNode _nicknameFocusNode;
  var _rememberAddress = false;
  var _pickingAvatar = false;
  var _selectedProfilePictureId = kDefaultProfilePictureId;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.state.destinationText);
    _nicknameController = TextEditingController();
    _focusNode = FocusNode(debugLabel: 'SwapAddressModalField');
    _nicknameFocusNode = FocusNode(debugLabel: 'SwapAddressModalNicknameField');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant SwapAddressEditModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.destinationText == widget.state.destinationText) {
      return;
    }
    _controller.value = TextEditingValue(
      text: widget.state.destinationText,
      selection: TextSelection.collapsed(
        offset: widget.state.destinationText.length,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _nicknameController.dispose();
    _focusNode.dispose();
    _nicknameFocusNode.dispose();
    super.dispose();
  }

  void _submit() {
    // Guard the keyboard "done"/enter path the same way the primary button is
    // gated, so a malformed address (or a missing/invalid nickname when the
    // user opted to remember it) cannot be committed by pressing enter.
    if (!_canSubmit) return;
    widget.onSubmitted(
      _controller.text.trim(),
      _rememberAddress,
      _rememberAddress ? _nicknameController.text.trim() : null,
      _selectedProfilePictureId,
    );
  }

  void _toggleRemember() {
    setState(() {
      _rememberAddress = !_rememberAddress;
      if (!_rememberAddress) _pickingAvatar = false;
    });
    if (_rememberAddress) _nicknameFocusNode.requestFocus();
  }

  void _selectAvatar(String id) {
    setState(() {
      _selectedProfilePictureId = id;
      _pickingAvatar = false;
    });
  }

  bool get _canSubmit => _formatError == null && _nicknameError == null;

  AddressFormatFinding? get _formatFinding {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return null;
    final network = AddressBookNetwork.tryFromChainTicker(
      widget.state.externalAsset.chainTicker,
    );
    if (network == null) return null;
    return addressFormatCheck(network, trimmed);
  }

  // Only error-severity findings block submission; warning-severity findings
  // (e.g. a bare NEAR top-level name) are surfaced but submittable.
  String? get _formatError {
    final finding = _formatFinding;
    return finding?.severity == AddressFormatSeverity.error
        ? finding!.message
        : null;
  }

  // Only constrains submission when the user opted to remember the address; the
  // saved entry becomes an address-book contact, so we reuse the same label
  // rules (non-empty, 1-20 chars) the address-book add form enforces.
  String? get _nicknameError {
    if (!_rememberAddress) return null;
    return validateAddressBookLabel(_nicknameController.text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sendsZec = widget.state.direction.sendsZec;
    final asset = widget.state.externalAsset;
    final title = sendsZec
        ? '${asset.symbol} recipient address'
        : '${asset.symbol} refund address';
    final fieldLabel = sendsZec ? 'Recipient' : 'Refund to';
    final hint = widget.state.destinationFieldHint;
    final description = sendsZec
        ? 'Your ${asset.symbol} will be delivered to this address.'
        : "If the swap fails or the rate moves, you'll be refunded in "
              '${asset.symbol} on ${asset.chainLabel}, minus the fee.';
    final rememberLabel = sendsZec
        ? 'Remember this address for recipients'
        : 'Remember this address for refunds';
    final formatFinding = _formatFinding;
    // Suppress the "Add a label" error on the pristine empty field — the hint
    // already says what to do, and the disabled button signals it can't submit
    // yet. Surface the error only once the user typed something invalid.
    final nicknameError = _nicknameController.text.trim().isEmpty
        ? null
        : _nicknameError;

    return AppModalCard(
      key: const ValueKey('swap_address_modal'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // The body sits inside a 4dp horizontal / 8dp vertical inset so the
          // field group lines up with the Figma body frame width.
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: AppSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  fieldLabel,
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colors.text.secondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                _AddressInputField(
                  controller: _controller,
                  focusNode: _focusNode,
                  hint: hint,
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) => setState(() {}),
                  onScan: widget.onScan,
                  onOpenContacts: widget.onOpenContacts,
                ),
                const SizedBox(height: AppSpacing.xxs),
                // The design reserves a 16dp message line under the field even
                // while it is empty, so the field→description gap stays put
                // when a format error (destructive) or advisory warning
                // (secondary) appears.
                SizedBox(
                  height: 16,
                  child: formatFinding == null
                      ? null
                      : Text(
                          formatFinding.message,
                          key:
                              formatFinding.severity ==
                                  AddressFormatSeverity.error
                              ? const ValueKey('swap_destination_format_error')
                              : const ValueKey(
                                  'swap_destination_format_warning',
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelLarge.copyWith(
                            fontWeight: FontWeight.w400,
                            color:
                                formatFinding.severity ==
                                    AddressFormatSeverity.error
                                ? colors.text.destructive
                                : colors.text.secondary,
                          ),
                        ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  description,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _AddressRememberToggle(
                  selected: _rememberAddress,
                  label: rememberLabel,
                  onTap: _toggleRemember,
                ),
                if (_rememberAddress) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Address label',
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w400,
                      color: colors.text.secondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      _AddressAvatarButton(
                        profilePictureId: _selectedProfilePictureId,
                        onTap: () =>
                            setState(() => _pickingAvatar = !_pickingAvatar),
                      ),
                      const SizedBox(width: AppSpacing.s),
                      Expanded(
                        child: _NicknameInputBox(
                          controller: _nicknameController,
                          focusNode: _nicknameFocusNode,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _submit(),
                        ),
                      ),
                    ],
                  ),
                  if (nicknameError != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      nicknameError,
                      key: const ValueKey('swap_address_nickname_error'),
                      style: AppTypography.labelLarge.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colors.text.destructive,
                      ),
                    ),
                  ],
                  if (_pickingAvatar) ...[
                    const SizedBox(height: AppSpacing.s),
                    _AvatarPickerStrip(
                      selectedId: _selectedProfilePictureId,
                      onSelected: _selectAvatar,
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppModalActions(
            actionKey: const ValueKey('swap_address_update_button'),
            cancelKey: const ValueKey('swap_address_cancel_button'),
            actionLabel: 'Update',
            onAction: _canSubmit ? _submit : null,
            onCancel: widget.onCancel,
          ),
        ],
      ),
    );
  }
}

/// The 46dp refund/recipient address field: a [colors.background.ground]
/// rounded box holding the text input on the left and the QR-scan + contacts
/// trailing icon buttons on the right.
class _AddressInputField extends StatelessWidget {
  const _AddressInputField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onSubmitted,
    required this.onChanged,
    required this.onScan,
    required this.onOpenContacts,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onChanged;
  final VoidCallback onScan;
  final VoidCallback onOpenContacts;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: TextField(
                key: const ValueKey('swap_destination_field'),
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.done,
                onSubmitted: onSubmitted,
                onChanged: onChanged,
                // Inputs/Field master: typed value Label M Medium, placeholder
                // Label M Regular (Geist 14/16, -0.06).
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
                cursorColor: colors.text.accent,
                decoration: InputDecoration.collapsed(
                  hintText: hint,
                  hintStyle: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colors.text.muted,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwapInlineIconButton(
                  key: const ValueKey('swap_address_scan_button'),
                  iconName: AppIcons.qr,
                  onTap: onScan,
                ),
                const SizedBox(width: AppSpacing.xxs),
                SwapInlineIconButton(
                  key: const ValueKey('swap_address_contacts_button'),
                  iconName: AppIcons.users,
                  onTap: onOpenContacts,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressRememberToggle extends StatelessWidget {
  const _AddressRememberToggle({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const ValueKey('swap_address_remember_toggle'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          children: [
            Container(
              key: const ValueKey('swap_address_remember_checkbox'),
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? colors.background.inverse : null,
                border: Border.all(
                  color: selected
                      ? colors.border.strong
                      : colors.border.regular,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(AppRadii.xSmall),
              ),
              child: selected
                  ? AppIcon(
                      AppIcons.check,
                      size: 12,
                      color: colors.icon.inverse,
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NicknameInputBox extends StatelessWidget {
  const _NicknameInputBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
        child: TextField(
          key: const ValueKey('swap_address_nickname_field'),
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.done,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          cursorColor: colors.text.accent,
          decoration: InputDecoration.collapsed(
            hintText: 'Add a label (1-20 characters)',
            hintStyle: AppTypography.labelLarge.copyWith(
              fontWeight: FontWeight.w400,
              color: colors.text.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _AddressAvatarButton extends StatelessWidget {
  const _AddressAvatarButton({
    required this.profilePictureId,
    required this.onTap,
  });

  final String profilePictureId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const ValueKey('swap_address_avatar_button'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AppProfilePicture(
                profilePictureId: profilePictureId,
                size: AppProfilePictureSize.large,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: colors.background.inverse,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AppIcon(
                      AppIcons.edit,
                      size: 10,
                      color: colors.icon.inverse,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarPickerStrip extends StatelessWidget {
  const _AvatarPickerStrip({
    required this.selectedId,
    required this.onSelected,
  });

  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in kProfilePictureOptions)
          _AvatarChoice(
            option: option,
            selected: option.id == selectedId,
            onSelected: onSelected,
          ),
      ],
    );
  }
}

class _AvatarChoice extends StatelessWidget {
  const _AvatarChoice({
    required this.option,
    required this.selected,
    required this.onSelected,
  });

  final ProfilePictureOption option;
  final bool selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('swap_address_avatar_${option.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelected(option.id),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AppProfilePicture(
                profilePictureId: option.id,
                size: AppProfilePictureSize.large,
              ),
              if (selected)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: colors.background.inverse,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: AppIcon(
                        AppIcons.check,
                        size: 10,
                        color: colors.icon.inverse,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
