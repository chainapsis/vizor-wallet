import 'package:flutter/widgets.dart';

import '../layout/app_form_factor.dart';
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

/// One 90px-high Figma `_Reivew Info` row (4265:59148), shared by every
/// review, status, and receipt surface on desktop and mobile: an
/// [AppAssetSize.size] leading icon/avatar slot, a small label, a serif
/// headline value, and an optional bottom row.
///
/// The label and bottom text follow the form factor: Label S on desktop,
/// Label M on mobile (Figma 4484:62917, 6268:86109).
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
    this.valueKey,
    this.struckThrough = false,
    this.bottomLeftIconName,
    this.bottomLeftIconColor,
    this.bottomLeftText,
    this.bottomLeftTextKey,
    this.trailingActionLabel,
    this.trailingActionIconName = AppIcons.eye,
    this.trailingActionKey,
    this.onTrailingAction,
    this.trailing,
    this.valueFit,
    this.valueStyle,
    this.valuePlaceholder,
    this.bottomLeftPlaceholder,
    this.rowHeight = ReviewInfoRow.height,
    this.reserveBottomRow = true,
    super.key,
  });

  /// Small secondary label above the value ("Amount", "To", "From").
  final String label;

  /// Serif headline value (amount, truncated address, or contact name).
  final String value;

  /// Leading coin image, [ReviewInfoIconCircle], or avatar, centered in the
  /// [AppAssetSize.size] square slot.
  final Widget leading;

  /// Key on the headline value text, for test lookups.
  final Key? valueKey;

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

  /// Key on [bottomLeftText], for test lookups.
  final Key? bottomLeftTextKey;

  /// Label of the trailing ghost button; the button is omitted when null.
  final String? trailingActionLabel;

  /// 16px icon inside the trailing ghost button.
  final String trailingActionIconName;

  /// Key on the trailing ghost button, for test lookups.
  final Key? trailingActionKey;

  /// Tap handler for the trailing ghost button.
  final VoidCallback? onTrailingAction;

  /// A bottom-right widget in place of the trailing ghost button, for a
  /// label that is not an action.
  final Widget? trailing;

  /// When set, the headline value shrinks to fit instead of truncating
  /// (long swap amounts scale down rather than ellipsize).
  final BoxFit? valueFit;

  /// Overrides the serif headline style — the pay review cards use the
  /// smaller Young Serif 28 (`AppTypography.headlineMedium`) while the
  /// send/status screens keep the default 32.
  final TextStyle? valueStyle;

  /// Loading content painted in the headline's usual line box.
  final Widget? valuePlaceholder;

  /// Loading content in the reserved bottom strip.
  final Widget? bottomLeftPlaceholder;

  /// Minimum component height. Pay review rows use the compact 76px
  /// variant; the send/status component remains 90px by default. Scaled
  /// text can grow the row past it.
  final double rowHeight;

  /// Keeps the 24px bottom slot even when it has no content.
  ///
  /// Existing send/status rows reserve this space to preserve their shared
  /// vertical rhythm. Rows whose Figma variant contains only a label and
  /// headline can opt out without changing the default component behavior.
  final bool reserveBottomRow;

  /// Row height pinned by the Figma `_Review Info` component.
  static const height = 90.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final valueStyle =
        (this.valueStyle ?? appSerifDisplayStyle(color: colors.text.accent))
            .copyWith(
              decoration: struckThrough ? TextDecoration.lineThrough : null,
              decorationColor: struckThrough ? colors.text.accent : null,
            );
    final labelRowHeight = rowHeight < ReviewInfoRow.height
        ? 14.0
        : AppSpacing.md;
    final textStyle = _textStyle.copyWith(color: colors.text.secondary);

    // Minimum heights rather than fixed ones, so scaled text grows the row
    // instead of overflowing it.
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: rowHeight),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: AppAssetSize.size,
            child: Center(child: leading),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: labelRowHeight),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(label, style: textStyle),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                if (valuePlaceholder != null)
                  SizedBox(
                    width: double.infinity,
                    child: Stack(
                      children: [
                        Text('', maxLines: 1, style: valueStyle),
                        Positioned.fill(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: valuePlaceholder,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (valueFit != null)
                  FittedBox(
                    fit: valueFit!,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      key: valueKey,
                      maxLines: 1,
                      style: valueStyle,
                    ),
                  )
                else
                  Text(
                    value,
                    key: valueKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: valueStyle,
                  ),
                if (_hasBottomRow) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: AppSpacing.md),
                    child: _bottomRow(colors, textStyle),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _textStyle = kAppFormFactor == AppFormFactor.mobile
      ? AppTypography.labelLarge
      : AppTypography.labelSmall;

  bool get _hasBottomRow =>
      reserveBottomRow ||
      bottomLeftIconName != null ||
      bottomLeftText != null ||
      bottomLeftPlaceholder != null ||
      trailingActionLabel != null;

  Widget _bottomRow(AppColors colors, TextStyle textStyle) {
    final leadingIconWidth = bottomLeftIconName == null
        ? 0.0
        : AppIconSize.medium + AppSpacing.xxs;
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          if (bottomLeftIconName != null) ...[
            AppIcon(
              bottomLeftIconName!,
              size: AppIconSize.medium,
              color: bottomLeftIconColor ?? colors.text.secondary,
            ),
            const SizedBox(width: AppSpacing.xxs),
          ],
          if (bottomLeftPlaceholder != null)
            Expanded(child: bottomLeftPlaceholder!)
          else if (bottomLeftText != null)
            Expanded(
              child: Text(
                bottomLeftText!,
                key: bottomLeftTextKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            )
          else
            const Spacer(),
          if (trailing case final trailing?)
            trailing
          else if (trailingActionLabel != null)
            // Keeps its natural width but never pushes past the strip, so a
            // long or scaled label ellipsizes instead of overflowing.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (constraints.maxWidth - leadingIconWidth).clamp(
                  0.0,
                  constraints.maxWidth,
                ),
              ),
              child: IntrinsicWidth(
                child: AppButton(
                  key: trailingActionKey,
                  onPressed: onTrailingAction,
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.small,
                  iconGap: 0,
                  constrainContent: true,
                  // The eye glyph matches the ghost label color per the Figma
                  // frames (not the default icon tint).
                  leading: AppIcon(
                    trailingActionIconName,
                    color: colors.button.ghost.label,
                  ),
                  // The compact Figma ghost button is outer p4 + icon16 +
                  // label px4, with no extra icon gap between those nested
                  // nodes.
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxs,
                    ),
                    child: Text(
                      trailingActionLabel!,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      // Explicit Label M style per Figma — the small button's
                      // own token is Label S; the ghost label color still
                      // flows in from the button's DefaultTextStyle merge.
                      style: AppTypography.labelLarge,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Figma `Review Icon`: the 24px connector glyph centered in the leading
/// column, between two [ReviewInfoRow]s.
///
/// Aligns itself to the start edge, so the glyph stays under the leading
/// column whatever cross-axis alignment its parent uses.
class ReviewConnectorIcon extends StatelessWidget {
  const ReviewConnectorIcon({
    this.iconName = AppIcons.arrowDown,
    this.color,
    super.key,
  });

  final String iconName;

  /// Glyph tint; defaults to the accent icon color.
  final Color? color;

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
            color: color ?? context.colors.icon.accent,
          ),
        ),
      ),
    );
  }
}

/// Figma `Review Info`: [rows] read top-down, joined by a
/// [ReviewConnectorIcon] between each pair. Mobile spaces the items 8px
/// apart; desktop stacks them flush.
class ReviewInfoFlow extends StatelessWidget {
  const ReviewInfoFlow({
    required this.rows,
    this.connectorIconName = AppIcons.arrowDown,
    this.connectorColor,
    super.key,
  });

  final List<Widget> rows;
  final String connectorIconName;
  final Color? connectorColor;

  static const _gap = kAppFormFactor == AppFormFactor.mobile
      ? AppSpacing.xs
      : 0.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: _gap,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            ReviewConnectorIcon(
              iconName: connectorIconName,
              color: connectorColor,
            ),
          rows[i],
        ],
      ],
    );
  }
}
