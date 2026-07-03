import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_copy_feedback.dart';
import 'app_icon.dart';
import 'app_tooltip.dart';

/// Tx-fee help tooltip copy shared by the send review/status and received
/// screens. Placeholder wording — final copy is still owed by design.
const kTxFeeHelpTooltip =
    'Fee paid to the Zcash network to process this transaction.';

/// One 32px "List Item" row inside a `ReviewWrapCard`: left label, right
/// value cluster with optional 16px leading/trailing icons.
///
/// Covers Status / Message / Timestamp / Tx ID / Tx fee across the send
/// review, status, and received screens. The per-row differences are all
/// prop-driven:
/// * Status — [leadingIconName] (check circle / cancel / loader) and
///   [valueColor] (positive / destructive / secondary); the failed screen
///   also tints the left label via [labelColor],
/// * Message — [trailingIconName] expand affordance,
/// * Tx ID — [trailingIconName] arrow-top-right explorer link,
/// * Tx fee — [trailingIconName] help affordance.
class ReviewListRow extends StatelessWidget {
  const ReviewListRow({
    required this.label,
    required this.value,
    this.labelColor,
    this.valueColor,
    this.leadingIconName,
    this.trailingIconName,
    this.trailingIconColor,
    this.trailingIconTooltip,
    this.copyText,
    this.onPressed,
    this.scaleValueToFit = false,
    super.key,
  });

  /// Left column label ("Status", "Message", "Tx fee", ...).
  final String label;

  /// Right column value text.
  final String value;

  /// Left label color; defaults to the secondary text token. The failed
  /// Status row passes the destructive token.
  final Color? labelColor;

  /// Value (and leading icon) color; defaults to the accent text token.
  final Color? valueColor;

  /// Optional 16px icon before the value (status check/cancel/loader).
  final String? leadingIconName;

  /// Optional 16px icon after the value (expand / arrow-top-right / help).
  final String? trailingIconName;

  /// Trailing icon tint; defaults to the resolved value color.
  final Color? trailingIconColor;

  /// Hover tooltip on the trailing icon (the Tx-fee help affordance). When
  /// set, the icon also tints to the accent color while hovered.
  final String? trailingIconTooltip;

  /// When set (and [onPressed] is null), tapping the value cluster copies
  /// this text with a 'Copied' toast; a copy glyph trails the value unless
  /// [trailingIconName] overrides it.
  final String? copyText;

  /// Tap handler for the value cluster (expand memo, open explorer, show
  /// fee help). The pill stays inert when null.
  final VoidCallback? onPressed;

  /// Scales the value down instead of applying a second ellipsis. Use this when
  /// callers already passed a deliberately compacted display value.
  final bool scaleValueToFit;

  /// Row height pinned by the Figma `List Item` component.
  static const height = 32.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final resolvedValueColor = valueColor ?? colors.text.accent;
    final resolvedTrailingIconName =
        trailingIconName ?? (copyText != null ? AppIcons.copy : null);
    final resolvedOnPressed =
        onPressed ??
        (copyText != null
            ? () => copyTextWithToast(
                context,
                text: copyText!,
                toastMessage: AppLocalizations.of(context).toastCopied,
              )
            : null);

    Widget pill = Container(
      // pl 8 / pr 4 / py 4 with the full radius per the Figma `Item Right`.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.xxs,
        AppSpacing.xxs,
        AppSpacing.xxs,
      ),
      decoration: const ShapeDecoration(shape: StadiumBorder()),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingIconName != null) ...[
            AppIcon(
              leadingIconName!,
              size: AppIconSize.medium,
              color: resolvedValueColor,
            ),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Flexible(
            child: _ReviewListRowValueText(
              value: value,
              scaleToFit: scaleValueToFit,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: resolvedValueColor,
              ),
            ),
          ),
          if (resolvedTrailingIconName != null) ...[
            const SizedBox(width: AppSpacing.xxs),
            if (trailingIconTooltip != null)
              AppTooltip(
                message: trailingIconTooltip,
                child: _HoverTintIcon(
                  iconName: resolvedTrailingIconName,
                  color: trailingIconColor ?? resolvedValueColor,
                  hoverColor: colors.text.accent,
                ),
              )
            else
              AppIcon(
                resolvedTrailingIconName,
                size: AppIconSize.medium,
                color: trailingIconColor ?? resolvedValueColor,
              ),
          ],
        ],
      ),
    );

    if (resolvedOnPressed != null) {
      pill = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: resolvedOnPressed,
          child: pill,
        ),
      );
    }

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Text(
              label,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: labelColor ?? colors.text.secondary,
              ),
            ),
          ),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: pill),
          ),
        ],
      ),
    );
  }
}

class _ReviewListRowValueText extends StatelessWidget {
  const _ReviewListRowValueText({
    required this.value,
    required this.scaleToFit,
    required this.style,
  });

  final String value;
  final bool scaleToFit;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      value,
      maxLines: 1,
      softWrap: false,
      overflow: scaleToFit ? TextOverflow.visible : TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: style,
    );
    if (!scaleToFit) return text;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: text,
    );
  }
}

/// 16px icon that tints from [color] to [hoverColor] while the pointer
/// hovers it (the Tx-fee help affordance).
class _HoverTintIcon extends StatefulWidget {
  const _HoverTintIcon({
    required this.iconName,
    required this.color,
    required this.hoverColor,
  });

  final String iconName;
  final Color color;
  final Color hoverColor;

  @override
  State<_HoverTintIcon> createState() => _HoverTintIconState();
}

class _HoverTintIconState extends State<_HoverTintIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.help,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AppIcon(
        widget.iconName,
        size: AppIconSize.medium,
        color: _hovered ? widget.hoverColor : widget.color,
      ),
    );
  }
}
