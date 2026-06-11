import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../models/swap_models.dart';
import 'swap_asset_icon.dart';

/// One side of the [SwapReviewInfo] summary.
class SwapReviewInfoSideData {
  const SwapReviewInfoSideData({
    required this.asset,
    required this.label,
    required this.amountText,
    required this.detailText,
    this.detailCopyText,
  });

  final SwapAsset asset;

  /// Section label, e.g. `You're paying` / `You're receiving`.
  final String label;

  /// Amount with symbol, rendered in the serif display style.
  final String amountText;

  /// Bottom line: the fiat value, or the counterparty address line
  /// (`To: … on <chain>` / `Refund to: …`).
  final String detailText;

  /// When set, the bottom line shows a Copy affordance copying this value.
  final String? detailCopyText;
}

/// Figma 'Review Info': the paying/receiving summary block shared by the
/// swap review, in-progress, and completed surfaces.
class SwapReviewInfo extends StatelessWidget {
  const SwapReviewInfo({
    required this.pay,
    required this.receive,
    this.onCopy,
    super.key,
  });

  final SwapReviewInfoSideData pay;
  final SwapReviewInfoSideData receive;
  final ValueChanged<String>? onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      key: const ValueKey('swap_review_info'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SwapReviewInfoSide(
            key: const ValueKey('swap_review_info_pay'),
            data: pay,
            copyButtonKey: const ValueKey('swap_review_info_pay_copy'),
            onCopy: onCopy,
          ),
          SizedBox(
            height: 24,
            child: Center(
              child: AppIcon(
                AppIcons.arrowDownward,
                size: 24,
                color: colors.icon.accent,
              ),
            ),
          ),
          _SwapReviewInfoSide(
            key: const ValueKey('swap_review_info_receive'),
            data: receive,
            copyButtonKey: const ValueKey('swap_review_info_receive_copy'),
            onCopy: onCopy,
          ),
        ],
      ),
    );
  }
}

class _SwapReviewInfoSide extends StatelessWidget {
  const _SwapReviewInfoSide({
    required this.data,
    required this.copyButtonKey,
    required this.onCopy,
    super.key,
  });

  final SwapReviewInfoSideData data;
  final Key copyButtonKey;
  final ValueChanged<String>? onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final detailStyle = AppTypography.labelMedium.copyWith(
      color: colors.text.secondary,
    );
    final copyText = data.detailCopyText;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SwapAssetIcon(
          asset: data.asset,
          selected: true,
          size: 32,
          showChainBadge: data.asset != SwapAsset.zec,
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
                    data.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: detailStyle,
                  ),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  data.amountText,
                  maxLines: 1,
                  style: appSerifDisplayStyle(color: colors.text.accent),
                ),
              ),
              SizedBox(
                height: 24,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        data.detailText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: detailStyle,
                      ),
                    ),
                    if (copyText != null && onCopy != null) ...[
                      const SizedBox(width: AppSpacing.xxs),
                      _SwapReviewCopyButton(
                        key: copyButtonKey,
                        onTap: () => onCopy!(copyText),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SwapReviewCopyButton extends StatelessWidget {
  const _SwapReviewCopyButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final labelColor = colors.button.ghost.label;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(AppIcons.copy, size: 16, color: labelColor),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Copy',
                style: AppTypography.labelLarge.copyWith(color: labelColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
