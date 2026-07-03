import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/mobile_text_field.dart';
import '../../../address_book/models/address_book_contact.dart';
import '../../../address_book/models/address_format_validator.dart';
import '../../models/swap_models.dart';
import '../swap_modal_controls.dart';

/// Mobile address editor — built on [MobileModalScaffold] (the shared
/// `_Modal Type` chrome: title top-left, pinned close top-right, outer
/// pt32/pb24/px16 padding). The body is the input box (with the
/// contacts-then-QR inline icons), a reserved one-line error slot, the
/// description, the remember toggle, and a separate Buttons Stack (full-width
/// `Update` + `Cancel`).
///
/// On mobile, "Remember this address" saves hands-free: the screen auto-names
/// the saved contact with a persona label and assigns a random avatar, so there
/// is deliberately no nickname/avatar form here — the toggle is the whole
/// remember UI.
class MobileSwapAddressEditModal extends StatefulWidget {
  const MobileSwapAddressEditModal({
    required this.state,
    required this.onSubmitted,
    required this.onScan,
    required this.onOpenContacts,
    required this.onCancel,
    super.key,
  });

  final SwapState state;
  final void Function(String value, bool remember) onSubmitted;
  final VoidCallback onScan;
  final VoidCallback onOpenContacts;
  final VoidCallback onCancel;

  @override
  State<MobileSwapAddressEditModal> createState() =>
      _MobileSwapAddressEditModalState();
}

class _MobileSwapAddressEditModalState
    extends State<MobileSwapAddressEditModal> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  var _rememberAddress = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.state.destinationText);
    _focusNode = FocusNode(debugLabel: 'SwapAddressModalField');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant MobileSwapAddressEditModal oldWidget) {
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
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    // Guard the keyboard "done"/enter path the same way the primary button is
    // gated, so a malformed address cannot be committed by pressing enter.
    if (!_canSubmit) return;
    widget.onSubmitted(_controller.text.trim(), _rememberAddress);
  }

  void _toggleRemember() {
    setState(() => _rememberAddress = !_rememberAddress);
  }

  bool get _canSubmit => _formatError == null;

  AddressFormatFinding? get _formatError {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return null;
    final network = AddressBookNetwork.tryFromChainTicker(
      widget.state.externalAsset.chainTicker,
    );
    if (network == null) return null;
    return addressFormatIssue(network, trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sendsZec = widget.state.direction.sendsZec;
    final asset = widget.state.externalAsset;
    final title = sendsZec
        ? AppLocalizations.of(context).swapRecipientAddressTitle(asset.symbol)
        : AppLocalizations.of(context).swapRefundAddressTitle(asset.symbol);
    final hint = widget.state.destinationFieldHint(
      AppLocalizations.of(context),
    );
    final description = sendsZec
        ? AppLocalizations.of(context).swapDeliveredToAddress(asset.symbol)
        : AppLocalizations.of(context).swapRefundsReturnedAs(asset.symbol, asset.chainLabel);
    final rememberLabel = sendsZec
        ? AppLocalizations.of(context).swapRememberRecipients
        : AppLocalizations.of(context).swapRememberRefunds;
    final formatError = _formatError;

    // MobileModalScaffold supplies the title, the pinned close button and the
    // outer pt32/pb24/px16 padding, so this body owns only its vertical
    // rhythm. _Modal Type body spec: an 8px top inset, the field, 12, a
    // reserved one-line error slot, 12, the description, 16, the remember
    // toggle; then the Buttons Stack 24 below (the field+description+remember
    // group has an 8px bottom inset, then a 16px gap to the buttons), so the
    // only gap beneath Cancel is the scaffold's pb24.
    return MobileModalScaffold(
      key: const ValueKey('swap_address_modal'),
      title: title,
      onClose: widget.onCancel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.xs),
          MobileTextField(
            fieldKey: const ValueKey('swap_destination_field'),
            controller: _controller,
            focusNode: _focusNode,
            hintText: hint,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (_) => setState(() {}),
            trailing: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwapInlineIconButton(
                    key: const ValueKey('swap_address_contacts_button'),
                    iconName: AppIcons.users,
                    onTap: widget.onOpenContacts,
                    size: AppInputSizing.iconSize,
                  ),
                  const SizedBox(width: 8),
                  SwapInlineIconButton(
                    key: const ValueKey('swap_address_scan_button'),
                    iconName: AppIcons.qr,
                    onTap: widget.onScan,
                    size: AppInputSizing.iconSize,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Reserve one label-m line for the format error so the description
          // keeps a stable offset whether or not an error shows — matching the
          // opacity-0 error line the Figma _Modal Type holds.
          SizedBox(
            height: 16,
            child: formatError == null
                ? null
                : Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      addressFormatFindingMessage(
                        formatError,
                        AppLocalizations.of(context),
                      ),
                      key: const ValueKey('swap_destination_format_error'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.destructive,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: 16),
          _AddressRememberToggle(
            selected: _rememberAddress,
            label: rememberLabel,
            onTap: _toggleRemember,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('swap_address_update_button'),
            expand: true,
            onPressed: _canSubmit ? _submit : null,
            child: Text(AppLocalizations.of(context).swapUpdateAction),
          ),
          const SizedBox(height: 12),
          AppButton(
            key: const ValueKey('swap_address_cancel_button'),
            variant: AppButtonVariant.ghost,
            expand: true,
            onPressed: widget.onCancel,
            child: Text(AppLocalizations.of(context).commonCancel),
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
