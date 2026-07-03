import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import '../app_icon.dart';

/// Shared review-header vocabulary for the mobile transaction-status
/// screens (post-send `MobileSendStatusScreen` and activity-tap
/// `MobileTransactionStatusScreen`). These were duplicated verbatim in
/// both screens; they are phase-independent presentation widgets, so they
/// live here while each screen keeps its own phase-coupled detail card.

/// One serif review row — Figma `_Reivew Info` (4265:59148): a 40px leading
/// badge, the small grey label, the Headline-L serif value, and an optional
/// bottom strip (pool tag / show-full-address / sub-address).
class MobileReviewInfoRow extends StatelessWidget {
  const MobileReviewInfoRow({
    required this.label,
    required this.value,
    required this.leading,
    this.bottom,
    this.strikethrough = false,
    super.key,
  });

  final String label;
  final String value;
  final Widget leading;
  final Widget? bottom;
  final bool strikethrough;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 90),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 40, child: Center(child: leading)),
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
                      label,
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.headlineLarge.copyWith(
                    color: colors.text.accent,
                    decoration: strikethrough
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                SizedBox(height: 24, child: bottom ?? const SizedBox()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The 24px flow arrow centered under the 40px badge column.
class MobileReviewFlowArrow extends StatelessWidget {
  const MobileReviewFlowArrow({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      child: Center(
        child: AppIcon(
          AppIcons.arrowDown,
          size: AppIconSize.large,
          color: context.colors.icon.accent,
        ),
      ),
    );
  }
}

/// The round ZEC coin — Figma `Asset Image` with the ZEC network logo.
class MobileReviewZecBadge extends StatelessWidget {
  const MobileReviewZecBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.full),
      child: Image.asset(
        'assets/swap/tokens/zec.png',
        width: 32,
        height: 32,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// 40px circular badge on the neutral subtle-opacity fill — the generic
/// wallet/counterparty leading slot. Circular (not a stadium/pill) to match
/// the desktop receipt's `ReviewInfoIconCircle` and the 40px contact avatar.
class MobileReviewIconBadge extends StatelessWidget {
  const MobileReviewIconBadge({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: context.colors.background.neutralSubtleOpacity,
        shape: BoxShape.circle,
      ),
      child: Center(child: child),
    );
  }
}
