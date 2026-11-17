import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/l10n/locale_typography.dart';
import '../../swap/domain/swap_direction.dart';
import '../../swap/models/swap_state.dart';

/// Width of the centered amount `TextField` so the unit suffix hugs the
/// digits (a full-width field would pin the suffix to the far edge).
double payAmountInputWidth({
  required BuildContext context,
  required String text,
  required TextStyle style,
  required double maxWidth,
  double minWidth = 56,
  double additionalWidth = AppSpacing.sm,
}) {
  final displayText = text.trim().isEmpty ? '0' : text.trim();
  final painter = TextPainter(
    text: TextSpan(
      text: displayText,
      style: withLocaleFontFallback(context, style),
    ),
    maxLines: 1,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = (painter.width + additionalWidth)
      .clamp(minWidth, maxWidth)
      .toDouble();
  painter.dispose();
  return width;
}

/// Whether the Pay amount step can advance on either form factor.
bool payAmountCanContinue(SwapState state) {
  final hasAmount = state.receiveAmount != null || state.quoteAmount != null;
  return hasAmount &&
      !state.hasQuoteAmountPrecisionError &&
      state.externalAssetIsAvailable &&
      !state.quoteLoading &&
      !state.pricingLoading;
}

/// Whether the quote's estimated ZEC spend meets or exceeds the spendable
/// balance (>= keeps headroom for the network fee).
bool payAmountExceedsAvailableZec(SwapState state, BigInt availableZatoshi) {
  if (!state.direction.sendsZec) return false;
  final quote = state.quote;
  if (quote == null || quote.sellAmount <= 0 || !quote.sellAmount.isFinite) {
    return false;
  }
  final requiredZatoshi = BigInt.from((quote.sellAmount * 100000000).ceil());
  return requiredZatoshi >= availableZatoshi;
}
