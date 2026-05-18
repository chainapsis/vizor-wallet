import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

class AppTooltip extends StatelessWidget {
  const AppTooltip({
    required this.child,
    this.message,
    this.richMessage,
    super.key,
  }) : assert(
         (message == null) != (richMessage == null),
         'Provide either message or richMessage.',
       );

  final String? message;
  final InlineSpan? richMessage;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.appTheme == AppThemeData.dark;
    final textStyle = AppTypography.bodySmall.copyWith(
      color: isDark ? colors.text.accent : colors.text.inverse,
      letterSpacing: 0,
    );

    return Tooltip(
      message: message,
      richMessage: richMessage == null
          ? null
          : TextSpan(style: textStyle, children: [richMessage!]),
      textStyle: textStyle,
      waitDuration: const Duration(milliseconds: 350),
      showDuration: const Duration(seconds: 8),
      preferBelow: false,
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
