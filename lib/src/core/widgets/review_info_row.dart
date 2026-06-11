import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_button.dart';
import 'app_icon.dart';

/// 32px circular leading slot for [ReviewInfoRow] — a 16px icon centered on
/// the subtle neutral fill (Figma `foreground/neutral/alpha/subtle-opacity`).
///
/// Used for the wallet glyph on "To"/"From" rows. Amount rows pass a coin
/// image (no fill) and contact rows pass an `AppProfilePicture` instead.
class ReviewInfoIconCircle extends StatelessWidget {
  const ReviewInfoIconCircle({
    required this.iconName,
    this.iconColor,
    super.key,
  });

  final String iconName;

  /// Tint for the inner icon. Defaults to the ambient icon color.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppAssetSize.size,
      height: AppAssetSize.size,
      decoration: BoxDecoration(
        color: context.colors.background.neutralSubtleOpacity,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: AppIcon(iconName, size: AppIconSize.medium, color: iconColor),
      ),
    );
  }
}

/// One 90px-high "Review Info" row from the send review/status and received
/// receipt screens: a 32px leading icon/avatar slot, a small label, a serif
/// headline value, and an optional bottom row.
///
/// The bottom row composes the per-screen variants from the Figma specs:
/// * Shielded/Transparent badge — [bottomLeftIconName] + [bottomLeftText],
/// * truncated sub-address or fiat sub-label — [bottomLeftText] alone,
/// * trailing ghost action ("Show full address" / "Verify address") —
///   [trailingActionLabel] + [onTrailingAction].
///
/// [struckThrough] renders the headline with a line-through — the failed
/// status screen's "To" row.
///
/// Figma's `Headline L` (Young Serif 32) uses the upstream Young Serif
/// family as a local override on the [AppTypography.headlineLarge] token —
/// the same screen-level override convention the onboarding titles use
/// (only the Regular weight ships, hence the explicit w400). The Figma
/// `"case" 1` font feature is applied so digits render as lining figures —
/// without it Young Serif falls back to oldstyle figures whose descenders
/// visually crowd the badge row below the headline.
class ReviewInfoRow extends StatelessWidget {
  const ReviewInfoRow({
    required this.label,
    required this.value,
    required this.leading,
    this.struckThrough = false,
    this.bottomLeftIconName,
    this.bottomLeftIconColor,
    this.bottomLeftText,
    this.trailingActionLabel,
    this.trailingActionIconName = AppIcons.eye,
    this.trailingActionKey,
    this.onTrailingAction,
    this.valueFit,
    super.key,
  });

  /// Small secondary label above the value ("Amount", "To", "From").
  final String label;

  /// Serif headline value (amount, truncated address, or contact name).
  final String value;

  /// 32×32 leading slot — coin image, [ReviewInfoIconCircle], or avatar.
  final Widget leading;

  /// Line-through on [value] (failed send recipient).
  final bool struckThrough;

  /// Optional 16px icon before [bottomLeftText] (e.g. shield keyhole for the
  /// "Shielded" badge).
  final String? bottomLeftIconName;

  /// Tint of [bottomLeftIconName]; falls back to the secondary text color.
  /// The "Shielded" badge passes the brand crimson per the Figma frames.
  final Color? bottomLeftIconColor;

  /// Bottom-left text: badge label, truncated sub-address, or fiat value.
  final String? bottomLeftText;

  /// Label of the trailing ghost button; the button is omitted when null.
  final String? trailingActionLabel;

  /// 16px icon inside the trailing ghost button.
  final String trailingActionIconName;

  /// Key on the trailing ghost button, for test lookups.
  final Key? trailingActionKey;

  /// Tap handler for the trailing ghost button.
  final VoidCallback? onTrailingAction;

  /// When set, the headline value shrinks to fit instead of truncating
  /// (long swap amounts scale down rather than ellipsize).
  final BoxFit? valueFit;

  /// Row height pinned by the Figma `_Review Info` component.
  static const height = 90.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final valueStyle = appSerifDisplayStyle(color: colors.text.accent).copyWith(
      decoration: struckThrough ? TextDecoration.lineThrough : null,
      decorationColor: struckThrough ? colors.text.accent : null,
    );

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: AppAssetSize.size,
            height: AppAssetSize.size,
            child: leading,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: AppSpacing.md,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      style: AppTypography.labelSmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                if (valueFit != null)
                  FittedBox(
                    fit: valueFit!,
                    alignment: Alignment.centerLeft,
                    child: Text(value, maxLines: 1, style: valueStyle),
                  )
                else
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: valueStyle,
                  ),
                const SizedBox(height: AppSpacing.xxs),
                SizedBox(height: AppSpacing.md, child: _bottomRow(colors)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomRow(AppColors colors) {
    return Row(
      children: [
        if (bottomLeftIconName != null) ...[
          AppIcon(
            bottomLeftIconName!,
            size: AppIconSize.medium,
            color: bottomLeftIconColor ?? colors.text.secondary,
          ),
          const SizedBox(width: AppSpacing.xxs),
        ],
        if (bottomLeftText != null)
          Expanded(
            child: Text(
              bottomLeftText!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
          )
        else
          const Spacer(),
        if (trailingActionLabel != null)
          AppButton(
            key: trailingActionKey,
            onPressed: onTrailingAction,
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.small,
            iconGap: 0,
            // The eye glyph matches the ghost label color per the Figma
            // frames (not the default icon tint).
            leading: AppIcon(
              trailingActionIconName,
              color: colors.button.ghost.label,
            ),
            // The compact Figma ghost button is outer p4 + icon16 +
            // label px4, with no extra icon gap between those nested nodes.
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
              child: Text(
                trailingActionLabel!,
                // Explicit Label M (14px) style per Figma — the small
                // button's own token is Label S 13px; the ghost label color
                // still flows in from the button's DefaultTextStyle merge.
                style: AppTypography.labelLarge,
              ),
            ),
          ),
      ],
    );
  }
}
