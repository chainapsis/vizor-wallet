import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/full_address_viewer.dart';
import '../../../core/widgets/review_info_row.dart';
import '../../accounts/widgets/account_modal_card.dart';

/// Recipient flavor shown by [VerifyAddressModal].
enum VerifyAddressModalVariant {
  /// Recipient is not in the address book: shield icon header.
  unknown,

  /// Recipient matches a saved contact: avatar + name header.
  knownContact,
}

/// Address pool copy/icon used by the unknown-recipient modal header.
enum VerifyAddressModalAddressKind { shielded, transparent, external }

/// The address verification modal opened from "Show full address" on the
/// send review screen (and later the received receipt).
///
/// Renders the full address as a continuous Geist Mono string that wraps
/// naturally, with Copy as the primary action.
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

  /// Full unified address rendered as wrapping monospace text.
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
          _header(context),
          const SizedBox(height: AppSpacing.sm),
          FullAddressText(address: address),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  key: const ValueKey('verify_address_close_button'),
                  onPressed: onClose,
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.mediumLarge,
                  expand: true,
                  constrainContent: true,
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Close', maxLines: 1),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: FullAddressCopyButton(
                  address: address,
                  expand: true,
                  label: 'Copy',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final colors = context.colors;
    final titleStyle = AppTypography.bodyLarge.copyWith(
      color: colors.text.accent,
      fontWeight: FontWeight.w600,
    );

    switch (variant) {
      case VerifyAddressModalVariant.unknown:
        final (iconName, title) = switch (unknownAddressKind) {
          VerifyAddressModalAddressKind.shielded => (
            AppIcons.shieldKeyholeOutline,
            'Unknown shielded address',
          ),
          VerifyAddressModalAddressKind.transparent => (
            AppIcons.transparentBalance,
            'Unknown transparent address',
          ),
          VerifyAddressModalAddressKind.external => (
            AppIcons.wallet,
            'Recipient address',
          ),
        };
        return Row(
          children: [
            ReviewInfoIconCircle(iconName: iconName),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                title,
                maxLines: 2,
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
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contactName!,
                    maxLines: 2,
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
