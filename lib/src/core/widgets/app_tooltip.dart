import 'package:flutter/material.dart' show Tooltip, TooltipTriggerMode;
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

class AppTooltip extends StatelessWidget {
  const AppTooltip({
    required this.child,
    this.message,
    this.richMessage,
    this.preferBelow = false,
    this.tapToShow = false,
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
  final bool excludeFromSemantics;
  final Widget child;

  static TextStyle textStyleOf(BuildContext context) {
    final colors = context.colors;
    return AppTypography.bodySmall.copyWith(
      color: context.appTheme == AppThemeData.dark
          ? colors.text.accent
          : colors.text.inverse,
      letterSpacing: 0,
    );
  }

  static BoxDecoration decorationOf(BuildContext context) {
    final colors = context.colors;
    final isDark = context.appTheme == AppThemeData.dark;
    return BoxDecoration(
      color: isDark ? colors.surface.tooltip : colors.background.inverse,
      borderRadius: BorderRadius.circular(AppRadii.xSmall),
      border: isDark ? Border.all(color: colors.border.regular) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = textStyleOf(context);

    return Tooltip(
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
      decoration: decorationOf(context),
      child: child,
    );
  }
}
