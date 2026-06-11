import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/review_info_row.dart';
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
///
/// Built on two core [ReviewInfoRow] instances separated by the centered
/// downward arrow — the same primitive the send review/status surfaces use.
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
          _side(
            data: pay,
            key: const ValueKey('swap_review_info_pay'),
            copyButtonKey: const ValueKey('swap_review_info_pay_copy'),
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
          _side(
            data: receive,
            key: const ValueKey('swap_review_info_receive'),
            copyButtonKey: const ValueKey('swap_review_info_receive_copy'),
          ),
        ],
      ),
    );
  }

  Widget _side({
    required SwapReviewInfoSideData data,
    required Key key,
    required Key copyButtonKey,
  }) {
    final copyText = data.detailCopyText;
    final showCopy = copyText != null && onCopy != null;
    return ReviewInfoRow(
      key: key,
      label: data.label,
      value: data.amountText,
      valueFit: BoxFit.scaleDown,
      leading: SwapAssetIcon(
        asset: data.asset,
        selected: true,
        size: 32,
        showChainBadge: data.asset != SwapAsset.zec,
      ),
      bottomLeftText: data.detailText,
      trailingActionLabel: showCopy ? 'Copy' : null,
      trailingActionIconName: AppIcons.copy,
      trailingActionKey: showCopy ? copyButtonKey : null,
      onTrailingAction: showCopy ? () => onCopy!(copyText) : null,
    );
  }
}
