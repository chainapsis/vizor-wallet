import 'package:flutter/widgets.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../models/swap_message.dart';

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

/// The "View swaps" link under the error for a full set of one-time
/// addresses ([SwapNoticeKind.privateReceiveAddressLimit]), when [shown] is
/// that [quoteError]: the swaps holding every one-time address are in
/// Activity.
({String label, VoidCallback onPressed})? swapQuoteErrorAction(
  AppLocalizations l10n,
  SwapMessage? quoteError, {
  required String? shown,
  required VoidCallback onViewSwaps,
}) =>
    quoteError == const SwapNotice(SwapNoticeKind.privateReceiveAddressLimit) &&
        shown == quoteError?.text(l10n)
    ? (label: l10n.swapQuoteErrorViewSwaps, onPressed: onViewSwaps)
    : null;
