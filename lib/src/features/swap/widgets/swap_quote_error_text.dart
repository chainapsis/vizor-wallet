import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';

/// A quote error under the swap or pay composer.
class SwapQuoteErrorText extends StatelessWidget {
  const SwapQuoteErrorText({
    required this.message,
    required this.textKey,
    this.maxLines,
    this.style,
    super.key,
  });

  final String message;
  final Key textKey;

  /// Maximum visible lines for the composer error.
  final int? maxLines;

  /// Text style before the destructive color, [AppTypography.bodySmall] when
  /// null. Mobile composers use [AppTypography.bodyMedium].
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Text(
      message,
      key: textKey,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: (style ?? AppTypography.bodySmall).copyWith(
        color: colors.text.destructive,
      ),
    );
  }
}
