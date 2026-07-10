import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart' show TextInputAction;

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/mobile_text_field.dart';
import '../../../address_book/models/address_book_contact.dart';
import '../../../address_book/models/address_book_label_lookup.dart';
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
    required this.contacts,
    required this.recents,
    required this.busy,
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
  final List<AddressBookContact> contacts;
  final List<PayRecentRecipient> recents;
  final bool busy;
  final SwapAsset externalAsset;
  final ValueChanged<String> onAddressChanged;
  final VoidCallback onOpenScanner;
  final ValueChanged<String> onChooseRecipient;
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
    final contactMatch = valid ? _contactForAddress(typed) : null;
    final recentMatch = valid ? _recentForAddress(typed) : null;
    final unknownAddress = valid && contactMatch == null && recentMatch == null;
    final visibleRecents = !hasInput
        ? widget.recents
        : contactMatch == null && recentMatch != null
        ? <PayRecentRecipient>[recentMatch]
        : const <PayRecentRecipient>[];
    final visibleContacts = !hasInput
        ? widget.contacts
        : contactMatch != null
        ? <AddressBookContact>[contactMatch]
        : const <AddressBookContact>[];

    return Column(
      key: const ValueKey('mobile_pay_recipient_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: unknownAddress
              ? _buildUnknownAddressBody(context)
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.s,
                    AppSpacing.sm,
                    AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildRecipientField(context),
                      const SizedBox(height: AppSpacing.md),
                      _buildQrRow(context),
                      if (visibleRecents.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        _FlatRecipientSection(
                          key: const ValueKey(
                            'mobile_pay_recent_recipients_section',
                          ),
                          title: 'Recently sent',
                          children: [
                            for (final recent in visibleRecents)
                              _RecipientRow(
                                key: ValueKey(
                                  'mobile_pay_recent_${recent.address}',
                                ),
                                contact: _contactForAddress(recent.address),
                                address: recent.address,
                                amountText: recent.amountText,
                                timeLabel: payRecentTimeLabel(
                                  recent.lastUsedAt,
                                ),
                                onTap: widget.busy
                                    ? null
                                    : () => widget.onChooseRecipient(
                                        recent.address,
                                      ),
                              ),
                          ],
                        ),
                      ],
                      if (visibleContacts.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        _FlatRecipientSection(
                          key: const ValueKey('mobile_pay_contacts_section'),
                          title:
                              '${visibleContacts.length} '
                              'contact${visibleContacts.length == 1 ? '' : 's'}',
                          children: [
                            for (final contact in visibleContacts)
                              _RecipientRow(
                                key: ValueKey(
                                  'mobile_pay_contact_${contact.id}',
                                ),
                                contact: contact,
                                address: contact.address,
                                onTap: widget.busy
                                    ? null
                                    : () => widget.onChooseRecipient(
                                        contact.address,
                                      ),
                              ),
                          ],
                        ),
                      ],
                    ],
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
                if (unknownAddress) ...[
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
                  onPressed: widget.busy ? null : widget.onSelectRecipient,
                  child: const Text('Continue'),
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
          _buildRecipientField(context),
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

  Widget _buildRecipientField(BuildContext context) {
    final colors = context.colors;
    final hasError = widget.addressError != null;
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

  AddressBookContact? _contactForAddress(String address) {
    final needle = _normalizedAddress(address);
    if (needle.isEmpty) return null;
    for (final contact in widget.contacts) {
      if (_normalizedAddress(contact.address) == needle) return contact;
    }
    return null;
  }

  PayRecentRecipient? _recentForAddress(String address) {
    final needle = _normalizedAddress(address);
    if (needle.isEmpty) return null;
    for (final recent in widget.recents) {
      if (_normalizedAddress(recent.address) == needle) return recent;
    }
    return null;
  }

  String _normalizedAddress(String address) {
    final network = AddressBookNetwork.tryFromChainTicker(
      widget.externalAsset.chainTicker,
    );
    return network == null
        ? address.trim()
        : normalizedAddressBookAddress(network, address);
  }
}

class _FlatRecipientSection extends StatelessWidget {
  const _FlatRecipientSection({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 28,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxs),
              child: Row(
                children: [
                  AppIcon(AppIcons.users, size: 20, color: colors.icon.muted),
                  const SizedBox(width: AppSpacing.xxs),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _RecipientRow extends StatelessWidget {
  const _RecipientRow({
    required this.address,
    this.contact,
    this.amountText,
    this.timeLabel,
    this.onTap,
    super.key,
  });

  final AddressBookContact? contact;
  final String address;
  final String? amountText;
  final String? timeLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final compactAddress = compactSwapAddress(
      address,
      maxLength: 22,
      prefixLength: 9,
      suffixLength: 8,
    );
    final amount = _outgoingAmountText(amountText);
    final row = SizedBox(
      height: _recipientRowHeight,
      child: Row(
        children: [
          SizedBox(
            width: AppAssetSize.size,
            child: Align(
              alignment: Alignment.centerLeft,
              child: contact != null
                  ? AppProfilePicture(
                      profilePictureId: contact!.profilePictureId,
                      size: AppProfilePictureSize.large,
                    )
                  : Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: colors.background.neutralSubtleOpacity,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: AppIcon(
                          AppIcons.wallet,
                          size: 16,
                          color: colors.icon.regular,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (contact != null)
                  Text(
                    contact!.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                Text(
                  compactAddress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w400,
                    color: contact == null
                        ? colors.text.accent
                        : colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
          if (amount != null || timeLabel != null) ...[
            const SizedBox(width: AppSpacing.xs),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (amount != null)
                  Text(
                    amount,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                if (amount != null && timeLabel != null)
                  const SizedBox(height: AppSpacing.xxs),
                if (timeLabel != null)
                  Text(
                    timeLabel!,
                    maxLines: 1,
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
}

String? _outgoingAmountText(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  return trimmed.startsWith('-') ? trimmed : '-$trimmed';
}
