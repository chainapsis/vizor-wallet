import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../swap/domain/swap_direction.dart';
import '../../swap/models/swap_state.dart';

/// Digits-and-dot amount formatter shared by the pay composer and wizard.
class PayDecimalAmountInputFormatter extends TextInputFormatter {
  const PayDecimalAmountInputFormatter({this.maxFractionDigits});

  final int? maxFractionDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    final max = maxFractionDigits;
    final pattern = max == null
        ? RegExp(r'^\d*(\.\d*)?$')
        : RegExp('^\\d*(\\.\\d{0,$max})?\$');
    if (pattern.hasMatch(text)) return newValue;
    return oldValue;
  }
}

/// Width of the centered amount `TextField` so the unit suffix hugs the
/// digits (a full-width field would pin the suffix to the far edge).
double payAmountInputWidth({
  required BuildContext context,
  required String text,
  required TextStyle style,
  required double maxWidth,
}) {
  final displayText = text.trim().isEmpty ? '0' : text.trim();
  final painter = TextPainter(
    text: TextSpan(text: displayText, style: style),
    maxLines: 1,
    textDirection: Directionality.of(context),
  )..layout();
  return (painter.width + AppSpacing.sm).clamp(56.0, maxWidth).toDouble();
}

/// Whether the Pay amount step can advance on either form factor.
bool payAmountCanContinue(SwapState state) {
  final hasAmount = state.receiveAmount != null || state.quoteAmount != null;
  return hasAmount &&
      state.quoteAmountPrecisionError == null &&
      state.externalAssetIsSupported &&
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
