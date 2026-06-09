import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart' show Colors, Scaffold, Scrollbar;
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
    this.sidebarWidth = 256,
    super.key,
  });

  final Widget sidebar;
  final Widget pane;
  final Widget? background;
  final double sidebarWidth;

  @override
  Widget build(BuildContext context) {
    final background = this.background;
    return Scaffold(
      backgroundColor: Colors.transparent,
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

  static const _glassRadius = 20.0;
  static const _glassBlur = 17.5;

  @override
  Widget build(BuildContext context) {
    if (glass) {
      final isDark = context.appTheme == AppThemeData.dark;
      final radius = BorderRadius.circular(_glassRadius);
      final fill =
          backgroundColor ??
          (isDark ? const Color(0xFF101010) : const Color(0xFFFFFFFF));
      final thinBorderColor = isDark
          ? const Color(0xFF1A1A1A).withValues(alpha: 0.23)
          : const Color(0xFFFFFFFF).withValues(alpha: 0.55);
      final innerHighlightColor = const Color(
        0xFFFFFFFF,
      ).withValues(alpha: 0.15);

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
        color: paintBackground
            ? backgroundColor ?? context.colors.background.ground
            : null,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      clipBehavior: Clip.antiAlias,
      child: AppToastHost(
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class AppPaneToolbar extends StatelessWidget {
  const AppPaneToolbar({
    this.onBeforeNavigate,
    this.leading,
    this.trailing,
    this.height = 48,
    this.padding = const EdgeInsets.all(AppSpacing.xxs),
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

class AppPaneScrollableFill extends StatefulWidget {
  const AppPaneScrollableFill({
    required this.child,
    this.controller,
    this.physics,
    super.key,
  });

  final Widget child;
  final ScrollController? controller;
  final ScrollPhysics? physics;

  @override
  State<AppPaneScrollableFill> createState() => _AppPaneScrollableFillState();
}

class _AppPaneScrollableFillState extends State<AppPaneScrollableFill> {
  late final ScrollController _internalController;
  bool _isHovered = false;
  bool _canScroll = false;

  ScrollController get _effectiveController =>
      widget.controller ?? _internalController;

  @override
  void initState() {
    super.initState();
    _internalController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateCanScroll();
    });
  }

  @override
  void didUpdateWidget(covariant AppPaneScrollableFill oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateCanScroll();
    });
  }

  @override
  void dispose() {
    _internalController.dispose();
    super.dispose();
  }

  void _updateCanScroll() {
    final controller = _effectiveController;
    if (!controller.hasClients) return;
    final canScroll = controller.positions.any(
      (position) =>
          position.hasContentDimensions && position.maxScrollExtent > 0,
    );
    if (canScroll == _canScroll) return;
    setState(() {
      _canScroll = canScroll;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 0.0;
        return NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _updateCanScroll();
            });
            return false;
          },
          child: MouseRegion(
            onEnter: (_) {
              if (_isHovered) return;
              setState(() {
                _isHovered = true;
              });
            },
            onExit: (_) {
              if (!_isHovered) return;
              setState(() {
                _isHovered = false;
              });
            },
            child: Scrollbar(
              controller: _effectiveController,
              thumbVisibility: _isHovered && _canScroll,
              child: SingleChildScrollView(
                controller: _effectiveController,
                physics: widget.physics,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight),
                  child: IntrinsicHeight(child: widget.child),
                ),
              ),
            ),
          ),
        );
      },
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
