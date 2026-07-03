import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_icon.dart';
import 'app_tooltip.dart';

/// Small hover-filled icon button: a fixed-size circle (or rounded rect)
/// that tints its background while the pointer is over it. The shared form
/// of the per-feature `_SmallIconButton` copies.
class AppIconHoverButton extends StatefulWidget {
  const AppIconHoverButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.size = 32,
    this.iconSize = AppIconSize.medium,
    this.borderRadius,
    this.hoverColor,
    this.idleColor,
    this.iconColor,
    this.tooltip,
    super.key,
  });

  final String icon;
  final String semanticLabel;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  /// Null renders a circle.
  final BorderRadius? borderRadius;

  /// Defaults to the ghost button hover fill.
  final Color? hoverColor;
  final Color? idleColor;

  /// Defaults to the accent icon color.
  final Color? iconColor;
  final String? tooltip;

  @override
  State<AppIconHoverButton> createState() => _AppIconHoverButtonState();
}

class _AppIconHoverButtonState extends State<AppIconHoverButton> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hoverColor = widget.hoverColor ?? colors.button.ghost.bgHover;
    final idleColor =
        widget.idleColor ?? colors.background.ground.withValues(alpha: 0);

    Widget button = Semantics(
      button: true,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: _hovered ? hoverColor : idleColor,
              shape: widget.borderRadius == null
                  ? BoxShape.circle
                  : BoxShape.rectangle,
              borderRadius: widget.borderRadius,
            ),
            child: Center(
              child: AppIcon(
                widget.icon,
                size: widget.iconSize,
                color: widget.iconColor ?? colors.icon.accent,
              ),
            ),
          ),
        ),
      ),
    );

    final tooltip = widget.tooltip;
    if (tooltip != null) {
      button = AppTooltip(message: tooltip, child: button);
    }
    return button;
  }
}
