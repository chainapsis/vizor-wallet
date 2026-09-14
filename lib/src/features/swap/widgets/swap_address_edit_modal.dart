import '../../../core/widgets/validated_paste_region.dart';
import 'dart:async';
import '../../address_scan/widgets/mobile_address_scan_view.dart';
import 'package:flutter/material.dart' show InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/navigation/payment_request_intake.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/models/address_book_label_lookup.dart';
import '../../address_book/models/address_format_validator.dart';
import '../../address_book/widgets/contact_name_inline.dart';
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
    this.onChanged,
    this.initialAddress,
    this.initialRemember = false,
    this.onDraftCaptured,
    this.resolve,
    this.onPaymentRequest,
    this.validationContext,
    this.readValidationContext,
    this.contacts = const <AddressBookContact>[],
    super.key,
  });

  final SwapState state;
  final SwapAddressSubmitCallback onSubmitted;
  final VoidCallback onScan;
  final VoidCallback onOpenContacts;
  final VoidCallback onCancel;
  final VoidCallback? onChanged;
  final String? initialAddress;
  final bool initialRemember;
  final SwapAddressSubmitCallback? onDraftCaptured;
  final MobileScanResolver? resolve;
  final ValueChanged<String>? onPaymentRequest;
  final Object? validationContext;
  final Object? Function()? readValidationContext;

  /// Saved contacts; when the entered address matches one, its name is shown
  /// under the field so the user knows the address is correct.
  final Iterable<AddressBookContact> contacts;

  @override
  State<SwapAddressEditModal> createState() => _SwapAddressEditModalState();
}

class _SwapAddressEditModalState extends State<SwapAddressEditModal> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  var _rememberAddress = false;
  int _inputGeneration = 0;
  String? _inputError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialAddress ?? widget.state.destinationText,
    );
    _rememberAddress = widget.initialRemember;
    _focusNode = FocusNode(debugLabel: 'SwapAddressModalField');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant SwapAddressEditModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.validationContext != widget.validationContext) {
      _inputGeneration++;
      _inputError = null;
    }
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

  void _captureDraftAndOpen(VoidCallback open) {
    _inputGeneration++;
    widget.onDraftCaptured?.call(_controller.text, _rememberAddress);
    open();
  }

  void _submit() =>
      unawaited(_resolveInput(_controller.text.trim(), submit: true));

  Future<void> _resolveInput(String raw, {bool submit = false}) async {
    final generation = ++_inputGeneration;
    final before = _controller.value;
    final route = ModalRoute.of(context);
    final resolve = widget.resolve;
    final outcome = raw.isEmpty
        ? const MobileScanOutcome.accepted('')
        : resolve == null
        ? MobileScanOutcome.accepted(raw)
        : await resolve(raw);
    if (!mounted ||
        generation != _inputGeneration ||
        before != _controller.value ||
        (route != null && !route.isCurrent) ||
        outcome.isIgnored) {
      return;
    }
    if (!outcome.isAccepted) {
      setState(() => _inputError = outcome.error);
      return;
    }
    if (isPaymentRequestUri(outcome.address!) &&
        widget.onPaymentRequest != null) {
      widget.onDraftCaptured?.call(_controller.text, _rememberAddress);
      widget.onPaymentRequest!(outcome.address!);
      return;
    }
    if (submit) {
      if (resolve == null && !_canSubmit) return;
      widget.onSubmitted(outcome.address!, _rememberAddress);
    } else {
      _controller.value = TextEditingValue(
        text: outcome.address!,
        selection: TextSelection.collapsed(offset: outcome.address!.length),
      );
      widget.onChanged?.call();
      setState(() => _inputError = null);
    }
  }

  void _toggleRemember() {
    _inputGeneration++;
    widget.onChanged?.call();
    setState(() {
      _rememberAddress = !_rememberAddress;
    });
  }

  bool get _canSubmit => _formatError == null;
  bool get _isPaymentRequest => isPaymentRequestUri(_controller.text);

  AddressFormatFinding? get _formatFinding {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return null;
    if (_isPaymentRequest) return null; // Resolved before paste or submit.
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

  /// Saved contact matching the entered address on the destination chain.
  AddressBookContact? get _matchedContact {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return null;
    final network = AddressBookNetwork.tryFromChainTicker(
      widget.state.externalAsset.chainTicker,
    );
    if (network == null) return null;
    return addressBookContactFor(
      contacts: widget.contacts,
      network: network,
      address: trimmed,
    );
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
    final formatFinding = _inputError == null
        ? _formatFinding
        : AddressFormatFinding.error(_inputError!);
    final matchedContact = _matchedContact;

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
                  onPaste: (raw) => _resolveInput(raw),
                  readPasteContext: () =>
                      (widget.readValidationContext?.call(), _inputGeneration),
                  pasteContext: (widget.validationContext, _inputGeneration),
                  onChanged: (_) {
                    _inputGeneration++;
                    _inputError = null;
                    widget.onChanged?.call();
                    setState(() {});
                  },
                  onScan: () => _captureDraftAndOpen(widget.onScan),
                  onOpenContacts: () =>
                      _captureDraftAndOpen(widget.onOpenContacts),
                ),
                const SizedBox(height: AppSpacing.xxs),
                // The design reserves a 16dp message line under the field even
                // while it is empty, so the field→description gap stays put
                // when a format error (destructive), advisory warning
                // (secondary), or matched-contact confirmation appears.
                // Findings take priority over the contact match.
                SizedBox(
                  height: 16,
                  child: formatFinding != null
                      ? Text(
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
                        )
                      : matchedContact == null
                      ? null
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: ContactNameInline(
                            key: const ValueKey(
                              'swap_destination_contact_match',
                            ),
                            name: matchedContact.label,
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
                // Remembered addresses are auto-named (and auto-avatared)
                // on save, so opting in needs no extra fields here.
                if (!_isPaymentRequest)
                  _AddressRememberToggle(
                    selected: _rememberAddress,
                    label: rememberLabel,
                    onTap: _toggleRemember,
                  ),
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
    this.onPaste,
    this.pasteContext,
    this.readPasteContext,
    required this.onScan,
    required this.onOpenContacts,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onChanged;
  final Future<void> Function(String)? onPaste;
  final Object? pasteContext;
  final Object? Function()? readPasteContext;
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
              child: ValidatedPasteRegion(
                controller: controller,
                onPaste: onPaste,
                pasteContext: pasteContext,
                readPasteContext: readPasteContext,
                builder: (menuBuilder) => TextField(
                  contextMenuBuilder: menuBuilder,
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
