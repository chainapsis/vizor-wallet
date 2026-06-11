import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import '../app_icon.dart';

/// Touch-sized list row used inside [MobileSurfaceCard]s — the Figma
/// `Content Line` pattern (361 wide on a 52 px pitch): leading icon or
/// avatar, label, optional trailing value, optional chevron or custom
/// trailing widget.
class MobileListRow extends StatelessWidget {
  const MobileListRow({
    required this.label,
    this.leading,
    this.value,
    this.trailing,
    this.showChevron = false,
    this.onTap,
    this.enabled = true,
    this.labelColor,
    super.key,
  });

  static const minHeight = 52.0;

  final Widget? leading;
  final String label;

  /// Overrides the default label color (e.g. destructive menu rows).
  final Color? labelColor;

  /// Right-aligned secondary value (e.g. current setting).
  final String? value;

  /// Custom trailing widget; rendered after [value] and instead of the
  /// chevron when provided.
  final Widget? trailing;
  final bool showChevron;
  final VoidCallback? onTap;

  /// Disabled rows render muted and ignore taps — used for entries
  /// whose mobile flow hasn't shipped yet.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final labelColor =
        this.labelColor ??
        (enabled ? colors.text.accent : colors.text.disabled);
    final valueColor = enabled ? colors.text.secondary : colors.text.disabled;

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minHeight),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpacing.s),
          ],
          // With a value, the value column owns the flexible space and
          // right-aligns against the chevron (an Expanded label next to
          // a loose Flexible value strands the value's unused allocation
          // at the row end, pulling short values off the right edge).
          // Rows with a value keep static labels; the label only gets
          // the truncating Expanded when it is the sole text.
          if (value != null) ...[
            Text(
              label,
              style: AppTypography.bodyMedium.copyWith(color: labelColor),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                value!,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppTypography.bodyMedium.copyWith(color: valueColor),
              ),
            ),
          ] else
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium.copyWith(color: labelColor),
              ),
            ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.xs),
            trailing!,
          ] else if (showChevron) ...[
            const SizedBox(width: AppSpacing.xs),
            AppIcon(
              AppIcons.chevronForward,
              size: AppIconSize.medium,
              color: enabled ? colors.icon.muted : colors.icon.disabled,
            ),
          ],
        ],
      ),
    );

    if (onTap == null || !enabled) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
    );
  }
}
