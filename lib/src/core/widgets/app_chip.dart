import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

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
    this.width,
  });

  final String? leadingText;
  final String label;
  final Widget? leading;
  final Widget? trailing;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 29,
        minWidth: width ?? 0,
        maxWidth: width ?? double.infinity,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: Row(
          mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
          children: [
            if (leading != null) ...[
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
                style: AppTypography.codeMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
            if (trailing != null) ...[
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
