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
  });

  final String? leadingText;
  final String label;
  final Widget? leading;
  final Widget? trailing;
  final AppChipType type;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final resolvedWidth =
        width ??
        switch (type) {
          AppChipType.defaultText => 80.0,
          AppChipType.icons => null,
        };
    final hasLeadingIcon = leading != null;
    final hasTrailingIcon = trailing != null;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 26,
        minWidth: resolvedWidth ?? 0,
        maxWidth: resolvedWidth ?? double.infinity,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: Row(
          mainAxisSize: resolvedWidth == null
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
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
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
