import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';

/// A quote error under the swap or pay composer.
class SwapQuoteErrorText extends StatelessWidget {
  const SwapQuoteErrorText({
    required this.message,
    required this.textKey,
    this.maxLines,
    super.key,
  });

  final String message;
  final Key textKey;

  /// Maximum visible lines for the composer error.
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Text(
      message,
      key: textKey,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: AppTypography.bodySmall.copyWith(color: colors.text.destructive),
    );
  }
}
