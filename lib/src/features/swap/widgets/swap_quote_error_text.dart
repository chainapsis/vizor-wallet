import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../providers/swap_state_provider.dart'
    show kPrivateSwapAddressLimitMessage;

/// A quote error under the swap or pay composer.
class SwapQuoteErrorText extends StatelessWidget {
  const SwapQuoteErrorText({
    required this.message,
    required this.textKey,
    this.maxLines,
    this.action,
    super.key,
  });

  final String message;
  final Key textKey;

  /// Maximum visible lines for the composer error.
  final int? maxLines;

  /// A link under the error to where the user can act on it.
  final ({String label, VoidCallback onPressed})? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Text(
      message,
      key: textKey,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: AppTypography.bodySmall.copyWith(color: colors.text.destructive),
    );
    final action = this.action;
    if (action == null) return text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        text,
        AppButton(
          key: const ValueKey('swap_quote_error_action'),
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.small,
          onPressed: action.onPressed,
          child: Text(action.label),
        ),
      ],
    );
  }
}

/// The "View swaps" link under [kPrivateSwapAddressLimitMessage]: the swaps
/// holding every one-time address are in Activity.
({String label, VoidCallback onPressed})? swapQuoteErrorAction(
  String? message, {
  required VoidCallback onViewSwaps,
}) => message == kPrivateSwapAddressLimitMessage
    ? (label: 'View swaps', onPressed: onViewSwaps)
    : null;
