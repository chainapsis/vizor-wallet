import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
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
    this.showSidebar = true,
    super.key,
  });

  final Widget sidebar;
  final Widget pane;
  final double sidebarWidth;
  final bool showSidebar;

  @override
  Widget build(BuildContext context) {
    if (showSidebar && _usesMobileShellPlatform) {
      return _AppMobileShell(
        sidebar: sidebar,
        pane: pane,
        sidebarWidth: sidebarWidth,
      );
    }

    return _AppDesktopShellLayout(
      sidebar: sidebar,
      pane: pane,
      sidebarWidth: sidebarWidth,
      showSidebar: showSidebar,
    );
  }
}

bool get _usesMobileShellPlatform {
  if (kIsWeb) return false;
  return Platform.isAndroid || Platform.isIOS;
}

class _AppDesktopShellLayout extends StatelessWidget {
  const _AppDesktopShellLayout({
    required this.sidebar,
    required this.pane,
    required this.sidebarWidth,
    required this.showSidebar,
  });

  final Widget sidebar;
  final Widget pane;
  final double sidebarWidth;
  final bool showSidebar;

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
              if (showSidebar) ...[
                SizedBox(width: sidebarWidth, child: sidebar),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(child: pane),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppMobileShell extends StatefulWidget {
  const _AppMobileShell({
    required this.sidebar,
    required this.pane,
    required this.sidebarWidth,
  });

  final Widget sidebar;
  final Widget pane;
  final double sidebarWidth;

  @override
  State<_AppMobileShell> createState() => _AppMobileShellState();
}

class _AppMobileShellState extends State<_AppMobileShell> {
  static const _headerHeight = 44.0;
  static const _drawerDuration = Duration(milliseconds: 220);

  bool _sidebarOpen = false;

  void _toggleSidebar() {
    setState(() {
      _sidebarOpen = !_sidebarOpen;
    });
  }

  void _closeSidebar() {
    if (!_sidebarOpen) return;
    setState(() {
      _sidebarOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final sidebarWidth = math.min(
            widget.sidebarWidth,
            math.max(0.0, constraints.maxWidth - AppSpacing.lg),
          );

          return Stack(
            children: [
              _AppMobileMainContent(
                headerHeight: _headerHeight,
                pane: widget.pane,
              ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_sidebarOpen,
                  child: AnimatedOpacity(
                    opacity: _sidebarOpen ? 1 : 0,
                    duration: _drawerDuration,
                    curve: Curves.easeOut,
                    child: GestureDetector(
                      key: const ValueKey('mobile_sidebar_backdrop'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _closeSidebar,
                      child: ColoredBox(color: colors.background.neutralScrim),
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                key: const ValueKey('mobile_sidebar_panel'),
                top: 0,
                right: _sidebarOpen ? 0 : -sidebarWidth,
                bottom: 0,
                width: sidebarWidth,
                duration: _drawerDuration,
                curve: Curves.easeOutCubic,
                child: _AppMobileSidebarPanel(
                  topContentInset: _headerHeight + AppSpacing.xs,
                  child: widget.sidebar,
                ),
              ),
              _AppMobileSidebarToggle(
                sidebarOpen: _sidebarOpen,
                onTap: _toggleSidebar,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AppMobileMainContent extends StatelessWidget {
  const _AppMobileMainContent({required this.headerHeight, required this.pane});

  final double headerHeight;
  final Widget pane;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Column(
          children: [
            SizedBox(
              height: headerHeight,
              child: Row(
                children: [
                  AppIcon(AppIcons.vizor, size: 24, color: colors.icon.accent),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Vizor',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Expanded(child: pane),
          ],
        ),
      ),
    );
  }
}

class _AppMobileSidebarToggle extends StatelessWidget {
  const _AppMobileSidebarToggle({
    required this.sidebarOpen,
    required this.onTap,
  });

  final bool sidebarOpen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final label = sidebarOpen ? 'Close menu' : 'Open menu';

    return Positioned(
      top: viewPadding.top + AppSpacing.xs,
      right: viewPadding.right + AppSpacing.xs,
      child: Semantics(
        button: true,
        label: label,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: const ValueKey('mobile_sidebar_toggle_button'),
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: sidebarOpen
                    ? colors.state.selectedOpacity
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadii.xSmall),
              ),
              alignment: Alignment.center,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: sidebarOpen
                    ? AppIcon(
                        AppIcons.cross,
                        key: const ValueKey('mobile_sidebar_close_icon'),
                        size: 20,
                        color: colors.icon.accent,
                        semanticLabel: label,
                      )
                    : _MobileMenuIcon(
                        key: const ValueKey('mobile_sidebar_menu_icon'),
                        color: colors.icon.accent,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileMenuIcon extends StatelessWidget {
  const _MobileMenuIcon({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 14,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < 3; i += 1)
            Container(
              height: 2,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppRadii.full),
              ),
            ),
        ],
      ),
    );
  }
}

class _AppMobileSidebarPanel extends StatelessWidget {
  const _AppMobileSidebarPanel({
    required this.topContentInset,
    required this.child,
  });

  final double topContentInset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        border: Border(left: BorderSide(color: colors.border.subtle)),
      ),
      child: SafeArea(
        left: false,
        child: Padding(
          padding: EdgeInsets.only(top: topContentInset),
          child: child,
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
    super.key,
  });

  final Widget child;
  final Color? backgroundColor;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
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
    this.leadingGap = AppSpacing.s,
    super.key,
  }) : assert(iconName != null || leading != null);

  final String label;
  final String? iconName;
  final Widget? leading;
  final bool active;
  final VoidCallback? onTap;
  final double leadingGap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final disabled = onTap == null && !active;
    final iconColor = disabled ? colors.icon.disabled : colors.icon.accent;
    final textColor = disabled ? colors.text.disabled : colors.text.accent;
    final row = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: active ? colors.state.selectedOpacity : null,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
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
