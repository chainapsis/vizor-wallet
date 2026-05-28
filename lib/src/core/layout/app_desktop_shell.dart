import 'dart:ui';

import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_toast.dart';

class AppDesktopShell extends StatelessWidget {
  const AppDesktopShell({
    required this.sidebar,
    required this.pane,
    this.sidebarWidth = 256,
    super.key,
  });

  final Widget sidebar;
  final Widget pane;
  final double sidebarWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: sidebarWidth, child: sidebar),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: pane),
            ],
          ),
        ),
      ),
    );
  }
}

class AppDesktopSidebarSurface extends StatelessWidget {
  const AppDesktopSidebarSurface({
    required this.child,
    this.backgroundColor,
    this.clipBehavior = Clip.antiAlias,
    this.glass = false,
    super.key,
  });

  final Widget child;
  final Color? backgroundColor;
  final Clip clipBehavior;
  final bool glass;

  static const _glassRadius = 20.0;
  static const _glassBlur = 17.5;

  @override
  Widget build(BuildContext context) {
    if (glass) {
      final colors = context.colors;
      final isDark =
          colors.background.ground == AppColors.dark.background.ground;
      final radius = BorderRadius.circular(_glassRadius);
      final fill =
          backgroundColor ??
          (isDark
              ? const Color(0xFF1A1A1A).withValues(alpha: 0.25)
              : const Color(0xFFFFFFFF).withValues(alpha: 0.78));

      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.12),
              blurRadius: 44,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          clipBehavior: clipBehavior,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: _glassBlur, sigmaY: _glassBlur),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: radius,
                border: Border.all(
                  color: const Color(0xFF1A1A1A).withValues(alpha: 0.23),
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  child,
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(
                          color: const Color(
                            0xFFFFFFFF,
                          ).withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      clipBehavior: clipBehavior,
      child: child,
    );
  }
}

class AppDesktopPane extends StatelessWidget {
  const AppDesktopPane({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      clipBehavior: Clip.antiAlias,
      child: AppToastHost(
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class AppSidebarItem extends StatelessWidget {
  const AppSidebarItem({
    required this.label,
    this.iconName,
    this.leading,
    this.active = false,
    this.onTap,
    this.leadingGap = AppSpacing.md,
    this.inactiveOpacity = 1,
    super.key,
  }) : assert(iconName != null || leading != null);

  final String label;
  final String? iconName;
  final Widget? leading;
  final bool active;
  final VoidCallback? onTap;
  final double leadingGap;
  final double inactiveOpacity;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final disabled = onTap == null && !active;
    final itemOpacity = active || disabled ? 1.0 : inactiveOpacity;
    final iconColor = disabled
        ? colors.icon.disabled
        : active
        ? colors.navPanel.activeIcon
        : colors.icon.accent.withValues(alpha: itemOpacity);
    final textColor = disabled
        ? colors.text.disabled
        : active
        ? colors.navPanel.activeLabel
        : colors.text.accent.withValues(alpha: itemOpacity);
    final row = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      height: 40,
      padding: const EdgeInsets.only(left: 14, right: AppSpacing.xs),
      decoration: BoxDecoration(
        color: active ? colors.navPanel.activeBg : null,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Row(
        children: [
          leading ?? AppIcon(iconName!, size: 20, color: iconColor),
          SizedBox(width: leadingGap),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(color: textColor),
            ),
          ),
        ],
      ),
    );

    return onTap == null
        ? row
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: row,
            ),
          );
  }
}
