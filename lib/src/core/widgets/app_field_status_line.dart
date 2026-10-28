import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_text_field.dart';

/// A one-line message under a field that draws its own message, such as a
/// mobile field. It uses the tone colors and icons [AppTextField] uses, so a
/// status reads the same on every form factor.
class AppFieldStatusLine extends StatelessWidget {
  const AppFieldStatusLine({
    required this.text,
    this.tone = AppTextFieldTone.neutral,
    this.icon,
    this.style,
    super.key,
  });

  final String text;
  final AppTextFieldTone tone;

  /// Replaces the tone's default icon. A neutral tone has none by default.
  final Widget? icon;

  /// Base style; the tone sets the color.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final color = appTextFieldMessageColor(context.colors, tone);
    final leading = icon ?? appTextFieldMessageIcon(tone, color);
    return Row(
      children: [
        if (leading != null) ...[
          leading,
          const SizedBox(width: AppSpacing.xxs),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (style ?? AppTypography.labelMedium).copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
