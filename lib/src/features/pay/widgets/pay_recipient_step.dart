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
    required this.onSelectRecipient,
    required this.onAddToContacts,
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

  /// Row tap: commit this address and continue to review.
  final ValueChanged<String> onChooseRecipient;

  /// CTA with the typed address.
  final VoidCallback onSelectRecipient;
  final VoidCallback onAddToContacts;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typed = typedAddress.trim();
    final hasInput = typed.isNotEmpty;
    final valid = hasInput && addressError == null;
    final contactMatch = valid ? _contactForAddress(typed) : null;
    final recentMatch = valid && contactMatch == null
        ? _recentForAddress(typed)
        : null;
    final unknownAddress = valid && contactMatch == null && recentMatch == null;

    final matchedContacts = !hasInput
        ? contacts
        : contactMatch != null
        ? [contactMatch]
        : const <AddressBookContact>[];
    final matchedRecents = !hasInput
        ? recents
        : contactMatch == null && recentMatch != null
        ? [recentMatch]
        : const <PayRecentRecipient>[];

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
          leading: AppIcon(AppIcons.user, size: 20, color: colors.icon.muted),
          leadingSlotWidth: 40,
          trailing: AppIconHoverButton(
            key: const ValueKey('pay_recipient_scan_button'),
            icon: AppIcons.qr,
            semanticLabel: 'Scan QR code',
            iconSize: 20,
            onTap: onOpenScanner,
          ),
          trailingSlotWidth: 40,
          trailingFitsSlot: true,
          onChanged: onAddressChanged,
          textStyle: AppTypography.codeMedium.copyWith(
            color: colors.text.accent,
          ),
          tone: hasInput && addressError != null
              ? AppTextFieldTone.destructive
              : AppTextFieldTone.neutral,
          messageText: hasInput && addressError != null ? addressError : null,
        ),
        const SizedBox(height: AppSpacing.s),
        if (unknownAddress)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Column(
              key: const ValueKey('pay_recipient_new_address_notice'),
              children: [
                AppIcon(AppIcons.users, size: 32, color: colors.icon.muted),
                const SizedBox(height: AppSpacing.s),
                Text(
                  'New address detected.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  "You haven't interacted with this address before.",
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
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
                    contact: null,
                    address: recent.address,
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
                    timeLabel: null,
                    onTap: busy
                        ? null
                        : () => onChooseRecipient(contact.address),
                  ),
              ],
            ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (valid && contactMatch == null)
          Center(
            child: AppButton(
              key: const ValueKey('pay_add_to_contacts_button'),
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.small,
              onPressed: busy ? null : onAddToContacts,
              child: const Text('Add to Contacts'),
            ),
          ),
        if (valid) ...[
          const SizedBox(height: AppSpacing.s),
          AppButton(
            key: const ValueKey('pay_select_recipient_button'),
            variant: AppButtonVariant.primary,
            size: AppButtonSize.large,
            expand: true,
            onPressed: busy ? null : onSelectRecipient,
            child: Text(busy ? 'Fetching quote' : 'Select Recipient'),
          ),
        ],
      ],
    );
  }

  /// Contacts arrive pre-filtered to compatible networks, so address equality
  /// is the only remaining check.
  AddressBookContact? _contactForAddress(String typed) {
    final needle = typed.toLowerCase();
    for (final contact in contacts) {
      if (contact.address.trim().toLowerCase() == needle) return contact;
    }
    return null;
  }

  PayRecentRecipient? _recentForAddress(String typed) {
    final needle = typed.toLowerCase();
    for (final recent in recents) {
      if (recent.address.trim().toLowerCase() == needle) return recent;
    }
    return null;
  }
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
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: colors.border.subtleOpacity),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...children,
        ],
      ),
    );
  }
}

class _PayRecipientRow extends StatelessWidget {
  const _PayRecipientRow({
    required this.contact,
    required this.address,
    required this.timeLabel,
    required this.onTap,
    super.key,
  });

  final AddressBookContact? contact;
  final String address;
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
                color: colors.background.inverse,
                shape: BoxShape.circle,
              ),
              child: AppIcon(
                AppIcons.wallet,
                size: 16,
                color: colors.icon.inverse,
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
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                Text(
                  compactAddress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: contact != null
                      ? AppTypography.bodySmall.copyWith(
                          color: colors.text.secondary,
                        )
                      : AppTypography.bodyMedium.copyWith(
                          color: colors.text.accent,
                        ),
                ),
              ],
            ),
          ),
          if (timeLabel != null) ...[
            const SizedBox(width: AppSpacing.xs),
            Text(
              timeLabel!,
              maxLines: 1,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
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
