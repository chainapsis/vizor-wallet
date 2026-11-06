import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart' show TextInputAction;

import '../../../../core/layout/mobile/mobile_bottom_scroll_fade.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/mobile_text_field.dart';
import '../../../address_book/models/address_book_contact.dart';
import '../../../address_book/models/recipient_suggestions.dart';
import '../../../address_book/widgets/mobile_recipient_list.dart';
import '../../../swap/models/swap_address_formatting.dart';
import '../../../swap/models/swap_models.dart';
import '../../models/pay_recent_recipients.dart';

const _recipientFieldGroupHeight = 81.0;
const _recipientRowHeight = 44.0;
const _recipientErrorGap = AppSpacing.xxs;
const _recipientErrorHeight = 17.0;

/// Mobile Pay recipient step. The screen host owns top navigation; this widget
/// provides the scrollable recipient content and keeps valid-address actions
/// pinned to the bottom of the available viewport.
class MobilePayRecipientStep extends StatefulWidget {
  const MobilePayRecipientStep({
    required this.controller,
    required this.typedAddress,
    required this.addressError,
    this.quoteError,
    required this.contacts,
    required this.recents,
    required this.busy,
    this.enabled = true,
    this.waitLabel,
    this.selectedContactId,
    required this.externalAsset,
    required this.onAddressChanged,
    required this.onOpenScanner,
    required this.onChooseRecipient,
    required this.onSelectRecipient,
    required this.onAddToContacts,
    super.key,
  });

  final TextEditingController controller;
  final String typedAddress;
  final String? addressError;
  final String? quoteError;
  final List<AddressBookContact> contacts;
  final List<PayRecentRecipient> recents;
  final bool busy;
  final bool enabled;

  /// Why Continue can't fetch a quote yet, as its label.
  final String? waitLabel;
  final String? selectedContactId;
  final SwapAsset externalAsset;
  final ValueChanged<String> onAddressChanged;
  final VoidCallback onOpenScanner;
  final ValueChanged<PayRecipientSelection> onChooseRecipient;
  final VoidCallback onSelectRecipient;
  final VoidCallback onAddToContacts;

  @override
  State<MobilePayRecipientStep> createState() => _MobilePayRecipientStepState();
}

class _MobilePayRecipientStepState extends State<MobilePayRecipientStep> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'MobilePayRecipient');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typed = widget.typedAddress.trim();
    final hasInput = typed.isNotEmpty;
    final valid = hasInput && widget.addressError == null;
    final network = AddressBookNetwork.tryFromChainTicker(
      widget.externalAsset.chainTicker,
    );
    final suggestions = network == null
        ? RecipientSuggestions<PayRecentRecipient>(
            recents: hasInput ? const [] : widget.recents,
            contacts: hasInput ? const [] : widget.contacts,
          )
        : matchRecipientSuggestions(
            query: typed,
            network: network,
            recents: widget.recents,
            recentAddress: (recent) => recent.address,
            contacts: widget.contacts,
          );
    final unknownAddress = valid && !suggestions.isNotEmpty;
    final canAddContact =
        valid && payContactsForAddress(widget.contacts, typed).isEmpty;
    // Text that matches a contact name is a search, not a malformed address.
    final showAddressError =
        widget.addressError != null && !suggestions.isSearch;

    Widget buildRecentRow(PayRecentRecipient recent) {
      final selection = payRecipientSelectionForRecent(widget.contacts, recent);
      final contact = payContactForSelection(widget.contacts, selection);
      final identityKey = recent.contactId == null
          ? recent.address
          : '${recent.address}_${recent.contactId}';
      return MobileRecipientRow(
        key: ValueKey('mobile_pay_recent_$identityKey'),
        surfaceKey: contact == null
            ? null
            : ValueKey('mobile_pay_contact_row_surface_${contact.id}'),
        name: contact?.label,
        profilePictureId: contact?.profilePictureId,
        addressText: _compactAddress(recent.address),
        amountText: _outgoingAmountText(recent.amountText),
        timeLabel: payRecentTimeLabel(recent.lastUsedAt),
        selected:
            selection.contactId != null &&
            selection.contactId == widget.selectedContactId,
        onTap: widget.busy || !widget.enabled
            ? null
            : () => widget.onChooseRecipient(selection),
      );
    }

    return Column(
      key: const ValueKey('mobile_pay_recipient_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: unknownAddress
              ? _buildUnknownAddressBody(context)
              : MobileBottomScrollFade(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm,
                      AppSpacing.s,
                      AppSpacing.sm,
                      AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildRecipientField(
                          context,
                          showError: showAddressError,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _buildQrRow(context),
                        if (suggestions.recents.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md),
                          MobileRecipientSection(
                            key: const ValueKey(
                              'mobile_pay_recent_recipients_section',
                            ),
                            title: 'Recents',
                            children: [
                              for (final recent in suggestions.recents)
                                buildRecentRow(recent),
                            ],
                          ),
                        ],
                        if (suggestions.contacts.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md),
                          MobileRecipientSection(
                            key: const ValueKey('mobile_pay_contacts_section'),
                            title: 'Contacts',
                            children: [
                              for (final contact in suggestions.contacts)
                                MobileRecipientRow(
                                  key: ValueKey(
                                    'mobile_pay_contact_${contact.id}',
                                  ),
                                  surfaceKey: ValueKey(
                                    'mobile_pay_contact_row_surface_'
                                    '${contact.id}',
                                  ),
                                  name: contact.label,
                                  profilePictureId: contact.profilePictureId,
                                  addressText: _compactAddress(contact.address),
                                  selected:
                                      widget.selectedContactId == contact.id,
                                  selectionSlotKey:
                                      payContactsForAddress(
                                            widget.contacts,
                                            contact.address,
                                          ).length >
                                          1
                                      ? ValueKey(
                                          'mobile_pay_contact_selection_slot_'
                                          '${contact.id}',
                                        )
                                      : null,
                                  onTap: widget.busy || !widget.enabled
                                      ? null
                                      : () => widget.onChooseRecipient(
                                          PayRecipientSelection(
                                            address: contact.address,
                                            contactId: contact.id,
                                          ),
                                        ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
        if (valid)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.s,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: Column(
              key: const ValueKey('mobile_pay_recipient_actions'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.quoteError != null) ...[
                  Text(
                    widget.quoteError!,
                    key: const ValueKey('mobile_pay_recipient_quote_error'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: context.colors.text.destructive,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s),
                ],
                if (canAddContact) ...[
                  AppButton(
                    key: const ValueKey('mobile_pay_add_to_contacts_button'),
                    variant: AppButtonVariant.ghost,
                    expand: true,
                    onPressed: widget.busy ? null : widget.onAddToContacts,
                    child: const Text('Add to contacts'),
                  ),
                  const SizedBox(height: AppSpacing.s),
                ],
                AppButton(
                  key: const ValueKey('mobile_pay_recipient_continue_button'),
                  expand: true,
                  trailing: widget.busy ? const AppIcon(AppIcons.loader) : null,
                  iconGap: AppSpacing.xxs,
                  onPressed:
                      widget.busy || !widget.enabled || widget.waitLabel != null
                      ? null
                      : widget.onSelectRecipient,
                  child: Text(
                    widget.busy
                        ? 'Fetching quote'
                        : widget.waitLabel ?? 'Continue',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildUnknownAddressBody(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.s,
        AppSpacing.sm,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildRecipientField(context, showError: false),
          const SizedBox(height: AppSpacing.md),
          _buildQrRow(context),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: SizedBox(
                      key: const ValueKey('mobile_pay_new_address_notice'),
                      width: 256,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(
                            AppIcons.users,
                            size: 20,
                            color: colors.icon.muted,
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            'New address detected.',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMediumStrong.copyWith(
                              color: colors.text.primary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            "You haven't interacted with this address before.",
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMedium.copyWith(
                              color: colors.text.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipientField(BuildContext context, {required bool showError}) {
    final colors = context.colors;
    final hasError = showError;
    return SizedBox(
      key: const ValueKey('mobile_pay_recipient_field_group'),
      height: _recipientFieldGroupHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MobileTextField(
            key: const ValueKey('mobile_pay_recipient_field'),
            fieldKey: const ValueKey('mobile_pay_recipient_input'),
            controller: widget.controller,
            focusNode: _focusNode,
            enabled: !widget.busy,
            hintText: '${widget.externalAsset.chainLabel} address',
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            textStyle: AppTypography.labelLarge.copyWith(
              fontWeight: FontWeight.w400,
              color: colors.text.accent,
            ),
            hintStyle: AppTypography.labelLarge.copyWith(
              fontWeight: FontWeight.w400,
              color: colors.text.muted,
            ),
            restingBorderColor: hasError
                ? colors.border.utilityDestructive
                : null,
            focusedBorderColor: hasError
                ? colors.border.utilityDestructive
                : null,
            leading: SizedBox(
              width: AppInputSizing.iconWrapWidth,
              height: AppInputSizing.height,
              child: Align(
                alignment: Alignment.centerRight,
                child: AppIcon(
                  AppIcons.plane,
                  size: 20,
                  color: colors.icon.regular,
                ),
              ),
            ),
            onChanged: widget.onAddressChanged,
          ),
          SizedBox(
            height: _recipientErrorGap + _recipientErrorHeight,
            child: hasError
                ? Padding(
                    padding: const EdgeInsets.only(top: _recipientErrorGap),
                    child: Row(
                      children: [
                        AppIcon(
                          AppIcons.warning,
                          size: 16,
                          color: colors.text.destructive,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Expanded(
                          child: Text(
                            widget.addressError!,
                            key: const ValueKey('mobile_pay_recipient_error'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.text.destructive,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildQrRow(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.busy ? null : widget.onOpenScanner,
        child: SizedBox(
          key: const ValueKey('mobile_pay_recipient_qr_row'),
          height: _recipientRowHeight,
          child: Row(
            children: [
              Container(
                width: AppAssetSize.size,
                height: AppAssetSize.size,
                decoration: BoxDecoration(
                  color: colors.background.neutralSubtleOpacity,
                  borderRadius: BorderRadius.circular(AppRadii.full),
                ),
                child: Center(
                  child: AppIcon(
                    AppIcons.qr,
                    size: AppAssetSize.icon,
                    color: colors.icon.accent,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scan a QR code',
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Scan an address using camera',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _compactAddress(String address) => compactSwapAddress(
  address,
  maxLength: 22,
  prefixLength: 9,
  suffixLength: 8,
);

String? _outgoingAmountText(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  return trimmed.startsWith('-') ? trimmed : '-$trimmed';
}
