import 'package:flutter/widgets.dart';

import '../../../core/formatting/address_display.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/review_info_row.dart';
import '../../../core/widgets/review_list_row.dart';

/// Recipient display data for the redesigned send review/status screens.
///
/// The two variants from the Figma specs:
/// * [SendReviewAddressRecipient] — truncated UA headline + "Shielded" badge,
/// * [SendReviewContactRecipient] — avatar + contact-name headline with the
///   truncated address as the sub-line.
sealed class SendReviewRecipient {
  const SendReviewRecipient({required this.address});

  /// Full recipient address; rendering truncates via [truncatedAddress].
  final String address;
}

/// Raw-address recipient (no address-book match).
final class SendReviewAddressRecipient extends SendReviewRecipient {
  const SendReviewAddressRecipient({required super.address});
}

/// Address-book contact recipient.
final class SendReviewContactRecipient extends SendReviewRecipient {
  const SendReviewContactRecipient({
    required super.address,
    required this.name,
    required this.profilePictureId,
  });

  /// Contact display name (serif headline).
  final String name;

  /// Avatar id resolved through `AppProfilePicture`.
  final String profilePictureId;
}

/// The shared "Review Info" block: Amount row, connector icon, and "To" row,
/// inside the Figma 16px horizontal inset.
///
/// The status screens reuse it with [connectorIconName] swapped to the
/// uturn-up glyph and [recipientStruckThrough] on the failed phase.
class SendReviewInfoSection extends StatelessWidget {
  const SendReviewInfoSection({
    required this.amountText,
    required this.recipient,
    this.isShieldedRecipient = true,
    this.recipientAddressType,
    this.fiatText,
    this.connectorIconName = AppIcons.arrowDown,
    this.recipientStruckThrough = false,
    this.onShowFullAddress,
    super.key,
  });

  /// Formatted send amount ("123.12 ZEC").
  final String amountText;

  final SendReviewRecipient recipient;

  /// Pool badge for raw-address recipients. Contact recipients keep the
  /// truncated-address sub-line shown in Figma instead of a pool badge.
  final bool isShieldedRecipient;

  /// Full protocol address type from validation when available.
  ///
  /// This keeps TEX distinguishable from ordinary transparent recipients while
  /// preserving the existing shielded/transparent fallback for static previews.
  final String? recipientAddressType;

  /// Optional fiat sub-label under the amount; hidden when null.
  final String? fiatText;

  /// Connector between the Amount and To rows — arrow-down on review /
  /// in-progress / completed, uturn-up on failed.
  final String connectorIconName;

  /// Line-through on the recipient headline (failed send).
  final bool recipientStruckThrough;

  final VoidCallback? onShowFullAddress;

  String? get _normalizedRecipientAddressType =>
      recipientAddressType?.trim().toLowerCase();

  bool get _recipientBadgeIsShielded =>
      switch (_normalizedRecipientAddressType) {
        'unified' || 'sapling' => true,
        'transparent' || 'tex' => false,
        _ => isShieldedRecipient,
      };

  String get _recipientBadgeText => _normalizedRecipientAddressType == 'tex'
      ? 'TEX'
      : _recipientBadgeIsShielded
      ? 'Shielded'
      : 'Transparent';

  bool get _recipientBadgeIsTex => _normalizedRecipientAddressType == 'tex';

  String? get _contactRecipientBottomLeftIconName =>
      _recipientBadgeIsTex ? AppIcons.transparentBalance : null;

  String _contactRecipientBottomLeftText(String address) {
    final displayAddress = truncatedAddress(address);
    return _recipientBadgeIsTex ? 'TEX - $displayAddress' : displayAddress;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReviewInfoRow(
            label: 'Amount',
            value: amountText,
            leading: const _ZecCoinImage(),
            bottomLeftText: fiatText,
          ),
          _ReviewConnectorIcon(iconName: connectorIconName),
          _recipientRow(context),
        ],
      ),
    );
  }

  Widget _recipientRow(BuildContext context) {
    return switch (recipient) {
      SendReviewAddressRecipient(:final address) => ReviewInfoRow(
        label: 'To',
        value: truncatedAddress(address),
        leading: const ReviewInfoIconCircle(iconName: AppIcons.wallet),
        struckThrough: recipientStruckThrough,
        bottomLeftIconName: _recipientBadgeIsShielded
            ? AppIcons.shieldKeyhole
            : AppIcons.transparentBalance,
        bottomLeftIconColor: _recipientBadgeIsShielded
            ? context.colors.text.brandCrimson
            : null,
        bottomLeftText: _recipientBadgeText,
        trailingActionLabel: 'Show full address',
        onTrailingAction: onShowFullAddress,
      ),
      SendReviewContactRecipient(
        :final name,
        :final profilePictureId,
        :final address,
      ) =>
        ReviewInfoRow(
          label: 'To',
          value: name,
          leading: AppProfilePicture(
            profilePictureId: profilePictureId,
            size: AppProfilePictureSize.large,
          ),
          struckThrough: recipientStruckThrough,
          bottomLeftIconName: _contactRecipientBottomLeftIconName,
          bottomLeftText: _contactRecipientBottomLeftText(address),
          trailingActionLabel: 'Show full address',
          onTrailingAction: onShowFullAddress,
        ),
    };
  }
}

/// The 420px content column shared by the review and status views: Body-L
/// SemiBold title over the screen sections with the Figma 32px gap.
///
/// The column is horizontally centered but top-pinned in the content area. In
/// the Figma frames, the title starts 16px below `Content Area` rather than
/// vertically centering the whole group in the pane.
///
/// Scrolling is owned by the containing pane scaffold.
class SendReviewContentColumn extends StatelessWidget {
  const SendReviewContentColumn({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;

  /// Screen sections (info block, wrap card, optional buttons stack),
  /// separated by 32px.
  final List<Widget> children;

  static const _sectionGap = 32.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: AppWindowSizing.contentAreaMaxWidth,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                // Figma `Body L` SemiBold — branch pattern is the
                // bodyLarge token with an inline weight bump.
                style: AppTypography.bodyLarge.copyWith(
                  color: colors.text.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              for (final child in children) ...[
                const SizedBox(height: _sectionGap),
                child,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The Message row of a review wrap card with the expand/collapse behavior
/// carried over from the legacy review receipt.
///
/// Collapsed, it is a single `ReviewListRow` whose pill holds the truncated
/// memo and the expand glyph. Expanded, the pill swaps to a "Collapse"
/// affordance and the full memo renders underneath the row.
class ReviewMemoRows extends StatelessWidget {
  const ReviewMemoRows({
    required this.memoText,
    this.expanded = false,
    this.onToggle,
    super.key,
  });

  /// Full memo text; the collapsed row truncates it to one line.
  final String memoText;

  final bool expanded;

  /// Expand/collapse tap handler; the affordance is inert when null.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return ReviewListRow(
        label: 'Message',
        value: memoText,
        trailingIconName: AppIcons.expand,
        onPressed: onToggle,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReviewListRow(
          label: 'Message',
          value: 'Collapse',
          trailingIconName: AppIcons.collapsed,
          onPressed: onToggle,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Text(
            memoText,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: context.colors.text.accent,
            ),
          ),
        ),
      ],
    );
  }
}

/// 32px round ZEC coin image leading the Amount row.
class _ZecCoinImage extends StatelessWidget {
  const _ZecCoinImage();

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        'assets/icons/network_zec.png',
        width: AppAssetSize.size,
        height: AppAssetSize.size,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// 24px connector glyph centered in the 32px leading column, between the
/// Amount and To rows.
class _ReviewConnectorIcon extends StatelessWidget {
  const _ReviewConnectorIcon({required this.iconName});

  final String iconName;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: AppAssetSize.size,
        child: Center(
          child: AppIcon(
            iconName,
            size: AppIconSize.large,
            color: context.colors.text.accent,
          ),
        ),
      ),
    );
  }
}
