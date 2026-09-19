import 'package:flutter/material.dart'
    show Tooltip, TooltipState, TooltipTriggerMode;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

class AppTooltip extends StatelessWidget {
  const AppTooltip({
    required this.child,
    this.message,
    this.richMessage,
    this.preferBelow = false,
    this.tapToShow = false,
    this.mouseClickToShow = false,
    this.excludeFromSemantics = false,
    super.key,
  }) : assert(
         (message == null) != (richMessage == null),
         'Provide either message or richMessage.',
       );

  final String? message;
  final InlineSpan? richMessage;
  final bool preferBelow;
  final bool tapToShow;

  /// Opens immediately on mouse click while preserving hover dismissal.
  /// Clicking outside dismisses; clicking again keeps the tooltip visible.
  final bool mouseClickToShow;
  final bool excludeFromSemantics;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.appTheme == AppThemeData.dark;
    final textStyle = AppTypography.bodySmall.copyWith(
      color: isDark ? colors.text.accent : colors.text.inverse,
      letterSpacing: 0,
    );

    final tooltip = Tooltip(
      // Flutter's default pointer-down dismissal clears the hover device set,
      // leaving a manually opened tooltip stuck after the mouse exits. For
      // mouse-click help, let TapRegion handle outside dismissal instead.
      enableTapToDismiss: !mouseClickToShow,
      message: message,
      richMessage: richMessage == null
          ? null
          : TextSpan(style: textStyle, children: [richMessage!]),
      textStyle: textStyle,
      waitDuration: const Duration(milliseconds: 350),
      showDuration: const Duration(seconds: 8),
      triggerMode: tapToShow ? TooltipTriggerMode.tap : null,
      preferBelow: preferBelow,
      excludeFromSemantics: excludeFromSemantics,
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isDark ? colors.surface.tooltip : colors.background.inverse,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
        border: isDark ? Border.all(color: colors.border.regular) : null,
      ),
      child: mouseClickToShow
          ? Builder(
              builder: (context) => MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  supportedDevices: const {PointerDeviceKind.mouse},
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context
                      .findAncestorStateOfType<TooltipState>()
                      ?.ensureTooltipVisible(),
                  child: child,
                ),
              ),
            )
          : child,
    );
    if (!mouseClickToShow) return tooltip;
    return TapRegion(
      onTapOutside: (_) => Tooltip.dismissAllToolTips(),
      child: tooltip,
    );
  }
}
