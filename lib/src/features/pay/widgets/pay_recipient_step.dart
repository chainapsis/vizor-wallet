import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_icon_hover_button.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../swap/models/swap_address_formatting.dart';
import '../models/pay_recent_recipients.dart';

/// Step 2 "Select Recipient" of the desktop pay wizard — Figma 6241:85245
/// plus the 2B1/2B2/2B3 field states (85845 / 104834 / 86376).
class PayRecipientStep extends StatelessWidget {
  const PayRecipientStep({
    required this.controller,
    required this.typedAddress,
    required this.addressError,
    required this.contacts,
    required this.recents,
    required this.busy,
    required this.onAddressChanged,
    required this.onOpenScanner,
    required this.onChooseRecipient,
    super.key,
  });

  final TextEditingController controller;
  final String typedAddress;

  /// Address-format issue for the pay chain, null when the address parses.
  final String? addressError;

  /// Saved contacts already filtered to networks compatible with the pay
  /// chain (see [payCompatibleContacts]).
  final List<AddressBookContact> contacts;
  final List<PayRecentRecipient> recents;

  /// True while the review quote is being fetched — disables the CTA.
  final bool busy;

  final ValueChanged<String> onAddressChanged;
  final VoidCallback onOpenScanner;

  /// Row tap: commit this address as the selected recipient. Quote/review
  /// starts only from the explicit "Select recipient" action.
  final ValueChanged<String> onChooseRecipient;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typed = typedAddress.trim();
    final hasInput = typed.isNotEmpty;
    final validDestination = hasInput && addressError == null;
    final matchedRecents = !hasInput
        ? recents
        : [
            for (final recent in recents)
              if (_payRecentMatchesQuery(
                recent,
                payRecipientContactForAddress(contacts, recent.address),
                typed,
              ))
                recent,
          ];
    final matchedRecentAddresses = {
      for (final recent in matchedRecents) recent.address.trim().toLowerCase(),
    };
    final matchedContacts = !hasInput
        ? contacts
        : [
            for (final contact in contacts)
              if (_payContactMatchesQuery(contact, typed) &&
                  !matchedRecentAddresses.contains(
                    contact.address.trim().toLowerCase(),
                  ))
                contact,
          ];
    final hasMatches = matchedRecents.isNotEmpty || matchedContacts.isNotEmpty;
    final unknownAddress = validDestination && !hasMatches;
    final showAddressError = hasInput && addressError != null && !hasMatches;

    return Column(
      key: const ValueKey('pay_recipient_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          key: const ValueKey('pay_recipient_search_field'),
          label: 'Recipient address',
          showLabel: false,
          controller: controller,
          hintText: 'Paste an address or scan QR code',
          leading: AppIcon(AppIcons.user, size: 20, color: colors.icon.regular),
          leadingSlotWidth: 32,
          trailing: AppIconHoverButton(
            key: const ValueKey('pay_recipient_scan_button'),
            icon: AppIcons.qr,
            semanticLabel: 'Scan QR code',
            iconSize: 20,
            iconColor: colors.icon.regular,
            onTap: onOpenScanner,
          ),
          trailingSlotWidth: 40,
          trailingFitsSlot: true,
          onChanged: onAddressChanged,
          textStyle: AppTypography.codeMedium.copyWith(
            color: colors.text.accent,
          ),
          tone: showAddressError
              ? AppTextFieldTone.destructive
              : AppTextFieldTone.neutral,
          messageText: showAddressError ? addressError : null,
        ),
        const SizedBox(height: AppSpacing.s),
        if (unknownAddress)
          SizedBox(
            height: 310,
            child: Center(
              child: SizedBox(
                width: 256,
                child: Column(
                  key: const ValueKey('pay_recipient_new_address_notice'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(AppIcons.users, size: 20, color: colors.icon.muted),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'New address detected.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.primary,
                      ),
                    ),
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
          )
        else ...[
          if (matchedRecents.isNotEmpty) ...[
            _PayRecipientListCard(
              key: const ValueKey('pay_recent_recipients_card'),
              title: 'Recently sent',
              children: [
                for (final recent in matchedRecents)
                  _PayRecipientRow(
                    key: ValueKey('pay_recent_${recent.address}'),
                    contact: payRecipientContactForAddress(
                      contacts,
                      recent.address,
                    ),
                    address: recent.address,
                    amountText: recent.amountText,
                    timeLabel: payRecentTimeLabel(recent.lastUsedAt),
                    onTap: busy
                        ? null
                        : () => onChooseRecipient(recent.address),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (matchedContacts.isNotEmpty)
            _PayRecipientListCard(
              key: const ValueKey('pay_contacts_card'),
              title: 'Contacts',
              children: [
                for (final contact in matchedContacts)
                  _PayRecipientRow(
                    key: ValueKey('pay_contact_${contact.id}'),
                    contact: contact,
                    address: contact.address,
                    amountText: null,
                    timeLabel: null,
                    onTap: busy
                        ? null
                        : () => onChooseRecipient(contact.address),
                  ),
              ],
            ),
        ],
      ],
    );
  }
}

bool _payContactMatchesQuery(AddressBookContact contact, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  return contact.address.trim().toLowerCase().contains(needle) ||
      contact.label.trim().toLowerCase().contains(needle);
}

bool _payRecentMatchesQuery(
  PayRecentRecipient recent,
  AddressBookContact? contact,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  return recent.address.trim().toLowerCase().contains(needle) ||
      (contact?.label.trim().toLowerCase().contains(needle) ?? false);
}

/// Contacts arrive pre-filtered to compatible networks, so address equality
/// is the only remaining check.
AddressBookContact? payRecipientContactForAddress(
  Iterable<AddressBookContact> contacts,
  String address,
) {
  final needle = address.trim().toLowerCase();
  if (needle.isEmpty) return null;
  for (final contact in contacts) {
    if (contact.address.trim().toLowerCase() == needle) return contact;
  }
  return null;
}

/// Bottom-pinned actions for a valid Recipient selection.
class PayRecipientActions extends StatelessWidget {
  const PayRecipientActions({
    required this.typedAddress,
    required this.addressError,
    required this.contacts,
    required this.busy,
    required this.quoteError,
    required this.onSelectRecipient,
    required this.onAddToContacts,
    super.key,
  });

  final String typedAddress;
  final String? addressError;
  final List<AddressBookContact> contacts;
  final bool busy;
  final String? quoteError;
  final VoidCallback onSelectRecipient;
  final VoidCallback onAddToContacts;

  bool get visible {
    final typed = typedAddress.trim();
    return typed.isNotEmpty && addressError == null;
  }

  @override
  Widget build(BuildContext context) {
    final typed = typedAddress.trim();
    final contact = payRecipientContactForAddress(contacts, typed);
    final canAddContact = contact == null;

    return Column(
      key: const ValueKey('pay_recipient_actions'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (quoteError != null) ...[
          SizedBox(
            width: PayWizardActionMetrics.width,
            child: Text(
              quoteError!,
              key: const ValueKey('pay_recipient_quote_error'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.destructive,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
        ],
        if (canAddContact) ...[
          AppButton(
            key: const ValueKey('pay_add_to_contacts_button'),
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.large,
            minWidth: PayWizardActionMetrics.width,
            onPressed: busy ? null : onAddToContacts,
            child: const Text('Add to contacts'),
          ),
          const SizedBox(height: AppSpacing.s),
        ],
        AppButton(
          key: const ValueKey('pay_select_recipient_button'),
          variant: AppButtonVariant.primary,
          size: AppButtonSize.large,
          minWidth: PayWizardActionMetrics.width,
          onPressed: busy ? null : onSelectRecipient,
          child: Text(busy ? 'Fetching quote' : 'Select recipient'),
        ),
      ],
    );
  }
}

abstract final class PayWizardActionMetrics {
  static const double width = 196;
}

class _PayRecipientListCard extends StatelessWidget {
  const _PayRecipientListCard({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: appSurfaceShadow(colors),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.labelLarge.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.xs),
            children[index],
          ],
        ],
      ),
    );
  }
}

class _PayRecipientRow extends StatelessWidget {
  const _PayRecipientRow({
    required this.contact,
    required this.address,
    required this.amountText,
    required this.timeLabel,
    required this.onTap,
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
      maxLength: 16,
      prefixLength: 7,
      suffixLength: 5,
    );
    final row = SizedBox(
      height: 44,
      child: Row(
        children: [
          if (contact != null)
            AppProfilePicture(
              profilePictureId: contact!.profilePictureId,
              size: AppProfilePictureSize.large,
            )
          else
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.background.neutralSubtleOpacity,
                shape: BoxShape.circle,
              ),
              child: AppIcon(
                AppIcons.wallet,
                size: 16,
                color: colors.icon.accent,
              ),
            ),
          const SizedBox(width: AppSpacing.xs),
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
                    fontWeight: contact != null
                        ? FontWeight.w400
                        : FontWeight.w500,
                    color: contact != null
                        ? colors.text.secondary
                        : colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
          if (amountText != null || timeLabel != null) ...[
            const SizedBox(width: AppSpacing.xs),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (amountText != null)
                  Text(
                    amountText!,
                    maxLines: 1,
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w400,
                      color: colors.text.accent,
                    ),
                  ),
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
}
