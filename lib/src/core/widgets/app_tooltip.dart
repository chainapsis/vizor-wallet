import 'package:flutter/material.dart'
    show Tooltip, TooltipState, TooltipTriggerMode;
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

class AppTooltip extends StatefulWidget {
  const AppTooltip({
    required this.child,
    this.message,
    this.richMessage,
    this.preferBelow = false,
    this.tapToShow = false,
    this.excludeFromSemantics = false,
    this.focusable = false,
    super.key,
  }) : assert(
         (message == null) != (richMessage == null),
         'Provide either message or richMessage.',
       );

  final String? message;
  final InlineSpan? richMessage;
  final bool preferBelow;
  final bool tapToShow;
  final bool excludeFromSemantics;

  /// For a help icon that is the only way to reach [message]: joins the tab
  /// order, announces as a button with the message as its name, and shows
  /// the tooltip while focused. Leave off when [child] is already an
  /// interactive control with its own focus and name.
  final bool focusable;
  final Widget child;

  @override
  State<AppTooltip> createState() => _AppTooltipState();
}

class _AppTooltipState extends State<AppTooltip> {
  final _tooltipKey = GlobalKey<TooltipState>();

  void _onFocusChange(bool focused) {
    if (focused) {
      _tooltipKey.currentState?.ensureTooltipVisible();
    } else {
      Tooltip.dismissAllToolTips();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.appTheme == AppThemeData.dark;
    final textStyle = AppTypography.bodySmall.copyWith(
      color: isDark ? colors.text.accent : colors.text.inverse,
      letterSpacing: 0,
    );

    Widget child = widget.child;
    if (widget.focusable) {
      child = Focus(
        onFocusChange: _onFocusChange,
        child: Semantics(
          button: true,
          label: widget.message,
          child: child,
        ),
      );
    }

    return Tooltip(
      key: _tooltipKey,
      message: widget.message,
      richMessage: widget.richMessage == null
          ? null
          : TextSpan(style: textStyle, children: [widget.richMessage!]),
      textStyle: textStyle,
      waitDuration: const Duration(milliseconds: 350),
      showDuration: const Duration(seconds: 8),
      triggerMode: widget.tapToShow ? TooltipTriggerMode.tap : null,
      preferBelow: widget.preferBelow,
      // The focusable wrapper already carries the name; a second copy from
      // the tooltip itself would read twice.
      excludeFromSemantics: widget.excludeFromSemantics || widget.focusable,
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
      child: child,
    );
  }
}
