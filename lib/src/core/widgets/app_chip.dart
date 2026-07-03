import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

enum AppChipType { defaultText, icons }

/// Compact inline token used for mnemonic rows and similar label clusters.
///
/// Figma's Chip page defines a text-first default treatment and an
/// icon-decorated treatment. This widget keeps the structure reusable while
/// leaving the surface transparent so screens can compose it directly into
/// cards, lists, or blurred overlays.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    this.leadingText,
    required this.label,
    this.leading,
    this.trailing,
    this.type = AppChipType.defaultText,
    this.width,
    this.minWidth,
    this.labelOverflow = TextOverflow.ellipsis,
  });

  final String? leadingText;
  final String label;
  final Widget? leading;
  final Widget? trailing;
  final AppChipType type;
  final double? width;
  final double? minWidth;
  final TextOverflow? labelOverflow;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final defaultFixedWidth = switch (type) {
      AppChipType.defaultText => 80.0,
      AppChipType.icons => null,
    };
    final fixedWidth = width ?? (minWidth == null ? defaultFixedWidth : null);
    final resolvedMinWidth = fixedWidth ?? minWidth ?? 0;
    final hasLeadingIcon = leading != null;
    final hasTrailingIcon = trailing != null;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 26,
        minWidth: resolvedMinWidth,
        maxWidth: fixedWidth ?? double.infinity,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: Row(
          mainAxisSize: fixedWidth == null
              ? MainAxisSize.min
              : MainAxisSize.max,
          children: [
            if (hasLeadingIcon) ...[
              SizedBox(
                width: AppIconSize.medium,
                height: AppIconSize.medium,
                child: leading,
              ),
              const SizedBox(width: AppSpacing.xxs),
            ],
            if (leadingText != null) ...[
              Text(
                leadingText!,
                style: AppTypography.codeSmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
            ],
            _AppChipLabel(
              fixedWidth: fixedWidth != null,
              label: label,
              overflow: labelOverflow,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
            if (hasTrailingIcon) ...[
              const SizedBox(width: AppSpacing.xxs),
              SizedBox(
                width: AppIconSize.medium,
                height: AppIconSize.medium,
                child: trailing,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AppChipLabel extends StatelessWidget {
  const _AppChipLabel({
    required this.fixedWidth,
    required this.label,
    required this.overflow,
    required this.style,
  });

  final bool fixedWidth;
  final String label;
  final TextOverflow? overflow;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final text = Text(label, maxLines: 1, overflow: overflow, style: style);
    if (!fixedWidth) return text;
    return Flexible(child: text);
  }
}
