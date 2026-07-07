import 'package:flutter/widgets.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../core/formatting/address_display.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/review_info_row.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../../accounts/widgets/account_modal_card.dart';

/// Recipient flavor shown by [VerifyAddressModal].
enum VerifyAddressModalVariant {
  /// Recipient is not in the address book: shield icon header.
  unknown,

  /// Recipient matches a saved contact: avatar + name header.
  knownContact,
}

/// Address pool copy/icon used by the unknown-recipient modal header.
enum VerifyAddressModalAddressKind { shielded, transparent }

/// The address verification modal opened from "Show full address" on the
/// send review screen (and later the received receipt).
///
/// Renders the full unified address through the canonical verify grid
/// ([addressVerifyGrid]): 5-character groups, 5 groups per row, with the
/// fixed head/tail groups emphasized in the brand crimson.
///
/// Static only — no provider wiring. The caller hosts this card inside an
/// `AppPaneModalOverlay` and supplies the callbacks.
class VerifyAddressModal extends StatelessWidget {
  const VerifyAddressModal({
    required this.address,
    required this.variant,
    required this.onClose,
    this.contactName,
    this.contactProfilePictureId,
    this.previousTransactionCount,
    this.unknownAddressKind = VerifyAddressModalAddressKind.shielded,
    super.key,
  }) : assert(
         variant == VerifyAddressModalVariant.unknown ||
             (contactName != null && contactProfilePictureId != null),
         'knownContact requires contactName and contactProfilePictureId.',
       );

  /// Full unified address rendered as the verify grid.
  final String address;

  final VerifyAddressModalVariant variant;

  /// Header copy/icon for [VerifyAddressModalVariant.unknown].
  final VerifyAddressModalAddressKind unknownAddressKind;

  /// Ghost Close action (both variants).
  final VoidCallback onClose;

  /// Saved contact display name ([VerifyAddressModalVariant.knownContact]).
  final String? contactName;

  /// Saved contact avatar id ([VerifyAddressModalVariant.knownContact]).
  final String? contactProfilePictureId;

  /// Optional "N previous transactions" sub-line under the contact name.
  /// Hidden when null while the caller is still loading or cannot provide a
  /// count.
  final int? previousTransactionCount;

  /// Title-row height pinned by the Figma `Title` node. (Its 12px-radius
  /// hover fill equals the card background in the spec, so no fill is
  /// painted here.)
  static const _titleRowHeight = 44.0;

  /// Figma min-width for the ghost Close button.
  static const _closeMinWidth = 196.0;

  bool get _hasPreviousTransactions => (previousTransactionCount ?? 0) > 0;

  String get _previousTransactionsLabel => previousTransactionCount == 1
      ? '1 previous transaction'
      : '$previousTransactionCount previous transactions';

  @override
  Widget build(BuildContext context) {
    return AccountModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: _titleRowHeight, child: _header(context)),
          const SizedBox(height: AppSpacing.md),
          _AddressVerifyGrid(address: address),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: AppButton(
              key: const ValueKey('verify_address_close_button'),
              onPressed: onClose,
              variant: AppButtonVariant.ghost,
              minWidth: _closeMinWidth,
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final colors = context.colors;
    final titleStyle = AppTypography.labelLarge.copyWith(
      color: colors.text.accent,
      fontWeight: FontWeight.w600,
    );

    switch (variant) {
      case VerifyAddressModalVariant.unknown:
        final (iconName, title) = switch (unknownAddressKind) {
          VerifyAddressModalAddressKind.shielded => (
            AppIcons.shieldKeyholeOutline,
            AppLocalizations.of(context).sendUnknownShieldedAddress,
          ),
          VerifyAddressModalAddressKind.transparent => (
            AppIcons.transparentBalance,
            AppLocalizations.of(context).sendUnknownTransparentAddress,
          ),
        };
        return Row(
          children: [
            ReviewInfoIconCircle(iconName: iconName),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
          ],
        );
      case VerifyAddressModalVariant.knownContact:
        // Both verify-header variants are leading-aligned per the Figma
        // frame; saved contacts add the transaction-count sub-line.
        return Row(
          children: [
            AppProfilePicture(
              profilePictureId: contactProfilePictureId!,
              size: AppProfilePictureSize.large,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contactName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  if (_hasPreviousTransactions) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: [
                        AppIcon(
                          AppIcons.checkCircle,
                          size: AppIconSize.medium,
                          color: colors.text.secondary,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Flexible(
                          child: Text(
                            _previousTransactionsLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.text.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
    }
  }
}

/// The full-address grid body: centered rows of 5-character groups with
/// row dividers between address lines. Highlighted groups
/// render Label M
/// SemiBold in the brand crimson; normal groups render Label M in the
/// primary text color, per the Figma address-color pattern.
class _AddressVerifyGrid extends StatelessWidget {
  const _AddressVerifyGrid({required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rows = addressVerifyGrid(address);
    final normalStyle = AppTypography.labelLarge.copyWith(
      color: colors.text.primary,
    );
    final highlightedStyle = AppTypography.labelLarge.copyWith(
      color: colors.text.brandCrimson,
      fontWeight: FontWeight.w600,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Each address line except the last carries a hairline divider
          // 12px below its digits; lines are separated by a further 8px,
          // per the Figma "Address Line" column structure.
          for (var row = 0; row < rows.length; row++) ...[
            if (row > 0) const SizedBox(height: AppSpacing.xs),
            // scaleDown keeps wide glyph metrics (and the test environment's
            // square Ahem font) from overflowing the 256px column; with the
            // production Geist metrics the row fits and renders 1:1.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < rows[row].length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.s),
                    Text(
                      rows[row][i].text,
                      style: rows[row][i].highlighted
                          ? highlightedStyle
                          : normalStyle,
                    ),
                  ],
                ],
              ),
            ),
            if (row < rows.length - 1) ...[
              const SizedBox(height: AppSpacing.s),
              const ReviewWrapDivider(),
            ],
          ],
        ],
      ),
    );
  }
}
