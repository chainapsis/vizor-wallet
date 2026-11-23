import 'package:flutter/widgets.dart';

import '../../../core/formatting/address_display.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/address_line_text.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/pool_badge.dart';

const _rowHeight = 44.0;
const _lineHeight = 17.0;

/// A titled group of recipient rows ("Recents", "Contacts") in the mobile
/// Send and Pay recipient steps.
class MobileRecipientSection extends StatelessWidget {
  const MobileRecipientSection({
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

/// One recipient: a named contact or account (avatar, name, address) or a
/// bare address (wallet glyph, address, optional pool line).
class MobileRecipientRow extends StatelessWidget {
  const MobileRecipientRow({
    required this.address,
    this.longAddress = true,
    this.name,
    this.profilePictureId,
    this.isShielded,
    this.amountText,
    this.timeLabel,
    this.selected = false,
    this.selectionSlotKey,
    this.surfaceKey,
    this.onTap,
    super.key,
  });

  /// The full address.
  final String address;

  /// Shows [address] in the long form (falling back to the short form where
  /// the row leaves too little room); false keeps every row short, for a list
  /// whose rows carry amounts.
  final bool longAddress;
  final String? name;
  final String? profilePictureId;

  /// The pool of a bare address, shown under it as the shared [PoolBadge],
  /// as activity rows show it.
  final bool? isShielded;
  final String? amountText;
  final String? timeLabel;
  final bool selected;

  /// Shows a selection check slot with this key, for addresses shared by
  /// several contacts.
  final Key? selectionSlotKey;
  final Key? surfaceKey;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = name;
    final row = SizedBox(
      key: surfaceKey,
      height: _rowHeight,
      child: Row(
        children: [
          SizedBox(
            width: AppAssetSize.size,
            child: Align(
              alignment: Alignment.centerLeft,
              child: title != null
                  ? AppProfilePicture(
                      profilePictureId:
                          profilePictureId ?? kDefaultProfilePictureId,
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
                if (title != null)
                  _RecipientLine(title, color: colors.text.accent)
                else
                  _RecipientLine.address(
                    address,
                    long: longAddress,
                    color: colors.text.accent,
                  ),
                if (title != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  _RecipientLine.address(
                    address,
                    long: longAddress,
                    color: colors.text.secondary,
                    fontWeight: FontWeight.w400,
                  ),
                ] else if (isShielded != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  // Unscaled like the lines above, so the fixed-height row
                  // keeps one text size.
                  SizedBox(
                    height: _lineHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: MediaQuery.withNoTextScaling(
                        child: PoolBadge(isShielded: isShielded!),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (amountText != null || timeLabel != null) ...[
            const SizedBox(width: AppSpacing.xs),
            // Unscaled like the name and address lines, so the fixed-height
            // row keeps one text size.
            MediaQuery.withNoTextScaling(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (amountText != null)
                    Text(
                      amountText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  if (amountText != null && timeLabel != null)
                    const SizedBox(height: AppSpacing.xxs),
                  if (timeLabel != null)
                    Text(
                      timeLabel!,
                      maxLines: 1,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (selectionSlotKey != null) ...[
            const SizedBox(width: AppSpacing.xs),
            SizedBox(
              key: selectionSlotKey,
              width: 18,
              height: 18,
              child: selected
                  ? Center(
                      child: AppIcon(
                        AppIcons.check,
                        size: 16,
                        color: colors.icon.accent,
                        semanticLabel: context.l10n.commonSelectedContact,
                      ),
                    )
                  : null,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return Semantics(selected: selected, child: row);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
}

/// A fixed-height single line so two of them fit the 44px row at any text
/// scale, matching the scan row above the lists.
class _RecipientLine extends StatelessWidget {
  const _RecipientLine(String this.text, {required this.color})
    : address = null,
      long = false,
      fontWeight = FontWeight.w500;

  /// A line showing [address] in the recipient lists' long form, falling
  /// back to the short form where the row leaves too little room.
  const _RecipientLine.address(
    String this.address, {
    required this.long,
    required this.color,
    this.fontWeight = FontWeight.w500,
  }) : text = null;

  final String? text;
  final String? address;

  /// Whether [address] takes the long form (else the short form).
  final bool long;
  final Color color;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.labelLarge.copyWith(
      color: color,
      fontWeight: fontWeight,
    );
    return SizedBox(
      height: _lineHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.noScaling),
          child: switch (address) {
            final address? => AddressLineText(
              long
                  ? AddressLine(
                      address: truncatedLongAddress(address),
                      shortAddress: truncatedAddress(address),
                    )
                  : AddressLine(address: truncatedAddress(address)),
              style: style,
              singleLine: true,
            ),
            null => Text(
              text!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          },
        ),
      ),
    );
  }
}
