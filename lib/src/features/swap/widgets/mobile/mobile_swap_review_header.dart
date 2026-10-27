import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/mobile/mobile_address_verify_sheet.dart';
import '../../../../core/widgets/review_info_row.dart';
import '../../domain/swap_contract.dart';
import '../one_time_address_label.dart';
import '../swap_asset_icon.dart';

/// One serif row of the mobile swap review header.
class MobileSwapReviewHeaderRow {
  const MobileSwapReviewHeaderRow({
    required this.label,
    required this.amountText,
    required this.asset,
    this.bottomText,
    this.fullAddress,
    this.addressNetworkLabel,
    this.oneTimeAddress,
  });

  /// "You're paying" / "You're receiving".
  final String label;

  /// The Headline L serif value ("1.12 ZEC").
  final String amountText;

  final SwapAsset asset;

  /// Small grey line under the amount — the fiat value or
  /// "To: 0x1125 ... 17512".
  final String? bottomText;

  /// When set, the bottom strip gains the eye "Full address" action
  /// opening the chunked verify sheet — Figma `Verify Address`
  /// (4731:96657).
  final String? fullAddress;

  /// Sheet title network label ("Ethereum address"); defaults to the
  /// asset's chain label.
  final String? addressNetworkLabel;

  /// Set when this row's ZEC goes to or comes back to a one-time address,
  /// shown where another row has "Full address".
  final OneTimeAddressRole? oneTimeAddress;
}

/// Serif paying/receiving block shared by the mobile swap review,
/// progress, and completed screens — Figma `Review Info`
/// (4731:85563), built on the core [ReviewInfoFlow].
class MobileSwapReviewHeader extends StatelessWidget {
  const MobileSwapReviewHeader({
    required this.pay,
    required this.receive,
    super.key,
  });

  final MobileSwapReviewHeaderRow pay;
  final MobileSwapReviewHeaderRow receive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: ReviewInfoFlow(
        rows: [_row(context, pay), _row(context, receive)],
      ),
    );
  }

  Widget _row(BuildContext context, MobileSwapReviewHeaderRow row) {
    final fullAddress = row.fullAddress;
    return ReviewInfoRow(
      label: row.label,
      value: row.amountText,
      leading: SwapAssetIcon(
        asset: row.asset,
        size: 32,
        showChainBadge: !row.asset.isNativeZec,
      ),
      bottomLeftText: row.bottomText,
      trailing: fullAddress == null && row.oneTimeAddress != null
          ? OneTimeAddressLabel(role: row.oneTimeAddress!)
          : null,
      trailingActionLabel: fullAddress == null ? null : 'Full address',
      trailingActionKey: const ValueKey('mobile_swap_full_address'),
      onTrailingAction: fullAddress == null
          ? null
          : () => showMobileAddressVerifySheet(
              context,
              title:
                  row.addressNetworkLabel ??
                  (row.asset.isNativeZec
                      ? 'Zcash address'
                      : '${row.asset.chainLabel} address'),
              address: fullAddress,
              leading: SwapAssetIcon(
                asset: row.asset,
                size: 32,
                showChainBadge: false,
              ),
            ),
    );
  }
}

/// "1.1200 ZEC" -> "1.12 ZEC" for the serif header rows, per the
/// Figma amounts (trailing zeros add no information at display size).
String trimSwapAmountText(String text) {
  final parts = text.split(' ');
  if (parts.isEmpty) return text;
  var amount = parts.first;
  if (amount.contains('.')) {
    amount = amount.replaceFirst(RegExp(r'0+$'), '');
    if (amount.endsWith('.')) {
      amount = amount.substring(0, amount.length - 1);
    }
  }
  return [amount, ...parts.skip(1)].join(' ');
}
