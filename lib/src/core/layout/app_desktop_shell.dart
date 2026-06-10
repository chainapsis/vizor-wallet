import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import '../widgets/app_back_link.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_toast.dart';

class AppDesktopShell extends StatelessWidget {
  const AppDesktopShell({
    required this.sidebar,
    required this.pane,
    this.background,
    this.backgroundColor,
    this.sidebarWidth = 256,
    super.key,
  });

  final Widget sidebar;
  final Widget pane;
  final Widget? background;
  final Color? backgroundColor;
  final double sidebarWidth;

  @override
  Widget build(BuildContext context) {
    final background = this.background;
    return Scaffold(
      backgroundColor: backgroundColor ?? context.colors.macosUtility.window,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (background != null)
              Positioned.fill(child: IgnorePointer(child: background)),
            Padding(
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
          ],
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

  static const glassRadius = 20.0;
  static const _glassBlur = 17.5;

  @override
  Widget build(BuildContext context) {
    if (glass) {
      final colors = context.colors;
      final radius = BorderRadius.circular(glassRadius);
      final fill = backgroundColor ?? colors.macosUtility.navPanel;
      final thinBorderColor = colors.macosUtility.thinBorder;
      final innerHighlightColor = colors.macosUtility.innerBorder;

      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.12),
              blurRadius: 44,
            ),
            BoxShadow(color: thinBorderColor, blurRadius: 0, spreadRadius: 1),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          clipBehavior: clipBehavior,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: _glassBlur, sigmaY: _glassBlur),
            child: DecoratedBox(
              decoration: BoxDecoration(color: fill, borderRadius: radius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  child,
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(color: innerHighlightColor),
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
    this.backgroundColor,
    this.paintBackground = true,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final bool paintBackground;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: paintBackground ? backgroundColor ?? Colors.transparent : null,
        borderRadius: BorderRadius.circular(AppWindowSizing.paneRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: AppToastHost(
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Pane-level back toolbar.
///
/// Design rule (verified across every Figma section): the back chevron sits
/// 16px from the pane's left edge, inside a 48px toolbar band, and the label
/// grows to the right. That 16px is composed of this toolbar's 4px
/// (`AppSpacing.xxs`) left padding plus [AppBackLink]'s own 12px
/// (`AppSpacing.s`) internal horizontal inset (the pill button's design inset).
/// The default [padding] encodes the toolbar half of that rule, so screens
/// should NOT pass their own horizontal padding unless a design explicitly
/// deviates. The vertical `xs` keeps the band visually balanced; because the
/// back link is vertically centered within [height], the exact symmetric
/// vertical padding does not move the link.
class AppPaneToolbar extends StatelessWidget {
  const AppPaneToolbar({
    this.onBeforeNavigate,
    this.leading,
    this.trailing,
    this.height = 48,
    this.padding = const EdgeInsets.only(
      left: AppSpacing.xxs,
      top: AppSpacing.xs,
      bottom: AppSpacing.xs,
    ),
    this.backLinkMinWidth = 0,
    super.key,
  });

  final FutureOr<void> Function()? onBeforeNavigate;
  final Widget? leading;
  final Widget? trailing;
  final double height;
  final EdgeInsetsGeometry padding;
  final double backLinkMinWidth;

  @override
  Widget build(BuildContext context) {
    final leadingWidget =
        leading ??
        AppRouteBackLink(
          onBeforeNavigate: onBeforeNavigate,
          minWidth: backLinkMinWidth,
        );

    return SizedBox(
      height: height,
      child: Padding(
        padding: padding,
        child: trailing == null
            ? Align(alignment: Alignment.centerLeft, child: leadingWidget)
            : Row(children: [leadingWidget, const Spacer(), trailing!]),
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
    this.iconAnimated = true,
    super.key,
  }) : assert(iconName != null || leading != null);

  final String label;
  final String? iconName;
  final Widget? leading;
  final bool active;
  final VoidCallback? onTap;
  final double leadingGap;
  final double inactiveOpacity;
  final bool iconAnimated;

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
          leading ??
              AppIcon(
                iconName!,
                size: 20,
                color: iconColor,
                animated: iconAnimated,
              ),
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
