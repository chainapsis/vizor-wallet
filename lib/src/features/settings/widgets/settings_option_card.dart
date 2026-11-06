import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/feedback/app_haptics.dart';
import '../../../core/l10n/locale_typography.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

/// Applies [labelLocale]'s glyphs to a label written in another language,
/// such as a language's own name in a picker.
TextStyle _labelStyle(TextStyle style, Locale? labelLocale) {
  if (labelLocale == null) return style;
  return style.copyWith(fontFamilyFallback: fontFamilyFallbackFor(labelLocale));
}

/// A selectable row of a desktop settings picker modal (theme, language).
class SettingsOptionCard extends StatelessWidget {
  const SettingsOptionCard({
    required this.label,
    required this.selected,
    required this.onTap,
    this.iconName,
    this.labelLocale,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? iconName;
  final Locale? labelLocale;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconName = this.iconName;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 40,
          padding: EdgeInsets.only(
            left: iconName == null ? AppSpacing.s : AppSpacing.xs,
            right: AppSpacing.s,
          ),
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            boxShadow: appSurfaceShadow(colors),
          ),
          foregroundDecoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                  border: Border.all(
                    color: colors.border.strong,
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                )
              : null,
          child: Row(
            children: [
              if (iconName != null) ...[
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: AppIcon(
                      iconName,
                      size: 18,
                      color: selected
                          ? colors.icon.accent
                          : colors.icon.accent.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Text(
                  label,
                  locale: labelLocale,
                  overflow: TextOverflow.ellipsis,
                  style: _labelStyle(
                    AppTypography.labelMedium.copyWith(
                      color: colors.text.accent,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    labelLocale,
                  ),
                ),
              ),
              _SettingsOptionIndicator(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsOptionIndicator extends StatelessWidget {
  const _SettingsOptionIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: selected
            ? colors.background.inverse
            : colors.background.neutralSubtleOpacity,
        shape: BoxShape.circle,
      ),
      child: selected
          ? Center(
              child: AppIcon(
                AppIcons.check,
                size: 12,
                color: colors.background.ground,
              ),
            )
          : null,
    );
  }
}

/// A selectable row of a mobile settings picker sheet — Figma `Theme Modal`
/// (4494:92272): option card with radio selection.
class MobileSettingsOptionCard extends StatelessWidget {
  const MobileSettingsOptionCard({
    required this.label,
    required this.selected,
    required this.onTap,
    this.iconName,
    this.labelLocale,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? iconName;
  final Locale? labelLocale;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconName = this.iconName;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!selected) unawaited(AppHaptics.selection());
          onTap();
        },
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: Border.all(
              color: selected ? colors.border.strong : colors.border.subtle,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              if (iconName != null) ...[
                Opacity(
                  opacity: selected ? 1 : 0.5,
                  child: AppIcon(iconName, size: 20, color: colors.icon.accent),
                ),
                const SizedBox(width: AppSpacing.s),
              ],
              Expanded(
                child: Text(
                  label,
                  locale: labelLocale,
                  style: _labelStyle(
                    AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                    labelLocale,
                  ),
                ),
              ),
              if (selected)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: colors.background.inverse,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AppIcon(
                      AppIcons.check,
                      size: 14,
                      color: colors.text.inverse,
                    ),
                  ),
                )
              else
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.background.raised,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
