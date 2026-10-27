import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/mobile/mobile_address_verify_sheet.dart';
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
/// (4731:85563): two 90px rows joined by the flow arrow, each with a
/// 32px asset coin (chain badge on external assets), the small grey
/// label, the Headline L serif amount, and a bottom strip.
class MobileSwapReviewHeader extends StatelessWidget {
  const MobileSwapReviewHeader({
    required this.pay,
    required this.receive,
    this.flowConnector,
    super.key,
  });

  final MobileSwapReviewHeaderRow pay;
  final MobileSwapReviewHeaderRow receive;

  /// Optional replacement for the whole flow arrow row.
  final Widget? flowConnector;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderRow(row: pay),
          flowConnector ??
              SizedBox(
                width: 40,
                child: Center(
                  child: AppIcon(
                    AppIcons.arrowDown,
                    size: AppIconSize.large,
                    color: context.colors.icon.accent,
                  ),
                ),
              ),
          _HeaderRow(row: receive),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.row});

  final MobileSwapReviewHeaderRow row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fullAddress = row.fullAddress;
    final oneTimeAddress = fullAddress == null ? row.oneTimeAddress : null;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 90),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            child: Center(
              child: SwapAssetIcon(
                asset: row.asset,
                size: 32,
                showChainBadge: !row.asset.isNativeZec,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 24,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      row.label,
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  row.amountText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.headlineLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                SizedBox(
                  height: 24,
                  child: Row(
                    children: [
                      if (row.bottomText case final bottomText?)
                        // Beside a one-time label the fiat value keeps its
                        // width and the label takes the rest.
                        oneTimeAddress != null
                            ? Text(
                                bottomText,
                                maxLines: 1,
                                style: AppTypography.labelMedium.copyWith(
                                  color: colors.text.secondary,
                                ),
                              )
                            : Expanded(
                                child: Text(
                                  bottomText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.labelMedium.copyWith(
                                    color: colors.text.secondary,
                                  ),
                                ),
                              )
                      else if (oneTimeAddress == null)
                        const Spacer(),
                      if (oneTimeAddress != null)
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: OneTimeAddressLabel(role: oneTimeAddress),
                          ),
                        ),
                      if (fullAddress != null)
                        _FullAddressButton(
                          onTap: () => showMobileAddressVerifySheet(
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
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FullAddressButton extends StatelessWidget {
  const _FullAddressButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      child: GestureDetector(
        key: const ValueKey('mobile_swap_full_address'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIcons.eye,
                size: AppIconSize.medium,
                color: colors.button.ghost.label,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Full address',
                style: AppTypography.labelLarge.copyWith(
                  color: colors.button.ghost.label,
                ),
              ),
            ],
          ),
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
