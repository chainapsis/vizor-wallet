import 'package:flutter/widgets.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../accounts/widgets/mobile/account_edit_sheets.dart'
    show MobileSheetCancel;
import '../../domain/swap_contract.dart';
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
    super.key,
  });

  final MobileSwapReviewHeaderRow pay;
  final MobileSwapReviewHeaderRow receive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.s,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderRow(row: pay),
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
                      if (row.bottomText != null)
                        Expanded(
                          child: Text(
                            row.bottomText!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelMedium.copyWith(
                              color: colors.text.secondary,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      if (fullAddress != null)
                        _FullAddressButton(
                          onTap: () => showSwapAddressVerifySheet(
                            context,
                            asset: row.asset,
                            address: fullAddress,
                            networkLabel: row.addressNetworkLabel,
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

/// Chunked address verification sheet — Figma `Verify Address`
/// (4731:96657): the network identity on top, the address split into
/// 5-character chunks (edges highlighted crimson so they're easy to
/// compare), and a Cancel action.
Future<void> showSwapAddressVerifySheet(
  BuildContext context, {
  required SwapAsset asset,
  required String address,
  String? networkLabel,
}) {
  return showAppMobileSheet<void>(
    context: context,
    builder: (sheetContext) {
      final colors = sheetContext.colors;
      final chunks = _chunkAddress(address);
      final label =
          networkLabel ??
          (asset.isNativeZec ? 'Zcash address' : '${asset.chainLabel} address');
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SwapAssetIcon(asset: asset, size: 32, showChainBadge: false),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.headlineSmall.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              key: const ValueKey('mobile_swap_verify_address_chunks'),
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.s,
              children: [
                for (var i = 0; i < chunks.length; i++)
                  Text(
                    chunks[i],
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: i == 0 || i == chunks.length - 1
                          ? colors.text.brandCrimson
                          : colors.text.accent,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            MobileSheetCancel(onTap: () => Navigator.of(sheetContext).pop()),
          ],
        ),
      );
    },
  );
}

List<String> _chunkAddress(String address) {
  final trimmed = address.trim();
  return [
    for (var i = 0; i < trimmed.length; i += 5)
      trimmed.substring(i, i + 5 > trimmed.length ? trimmed.length : i + 5),
  ];
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
