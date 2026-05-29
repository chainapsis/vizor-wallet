import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/models/address_format_validator.dart';
import '../models/swap_models.dart';
import 'swap_modal_controls.dart';

typedef SwapAddressSubmitCallback = void Function(String value, bool remember);

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
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    // Guard the keyboard "done"/enter path the same way the primary button is
    // gated, so a malformed address cannot be committed by pressing enter.
    if (_formatError != null) return;
    widget.onSubmitted(_controller.text.trim(), _rememberAddress);
  }

  String? get _formatError {
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
        ? '${asset.symbol} recipient address'
        : '${asset.symbol} refund address';
    final fieldLabel = sendsZec ? 'Recipient' : 'Refund to';
    final hint = widget.state.destinationFieldHint;
    final description = sendsZec
        ? 'The external asset will be delivered to this address.'
        : 'If swap fails, or market conditions change, your transaction may be refunded minus the fee. The refund currency is ${asset.symbol} on Near.';
    final rememberLabel = sendsZec
        ? 'Remember this address for recipients'
        : 'Remember this address for refunds';
    final formatError = _formatError;

    return Container(
      key: const ValueKey('swap_address_modal'),
      width: 312,
      height: 440,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SwapModalIconBadge(
                iconName: AppIcons.wallet,
                iconColor: colors.icon.regular,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.text.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      fieldLabel,
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: colors.background.base,
                        border: Border.all(
                          color: colors.border.subtle,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(AppRadii.small),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: TextField(
                                key: const ValueKey('swap_destination_field'),
                                controller: _controller,
                                focusNode: _focusNode,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _submit(),
                                onChanged: (_) => setState(() {}),
                                style: AppTypography.labelLarge.copyWith(
                                  color: colors.text.accent,
                                ),
                                cursorColor: colors.text.accent,
                                decoration: InputDecoration.collapsed(
                                  hintText: hint,
                                  hintStyle: AppTypography.labelLarge.copyWith(
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
                                  key: const ValueKey(
                                    'swap_address_scan_button',
                                  ),
                                  iconName: AppIcons.qr,
                                  onTap: widget.onScan,
                                ),
                                const SizedBox(width: 4),
                                SwapInlineIconButton(
                                  key: const ValueKey(
                                    'swap_address_contacts_button',
                                  ),
                                  iconName: AppIcons.users,
                                  onTap: widget.onOpenContacts,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (formatError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        formatError,
                        key: const ValueKey('swap_destination_format_error'),
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.destructive,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      description,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _AddressRememberToggle(
                      selected: _rememberAddress,
                      label: rememberLabel,
                      onTap: () {
                        setState(() => _rememberAddress = !_rememberAddress);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          SwapModalButtons(
            primaryKey: const ValueKey('swap_address_update_button'),
            cancelKey: const ValueKey('swap_address_cancel_button'),
            onPrimary: _submit,
            onCancel: widget.onCancel,
            primaryEnabled: formatError == null,
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
