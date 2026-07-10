import '../../../core/config/fiat_currencies.dart';

String swapFormatFiatValue(double value) {
  if (value <= 0) return '0';
  final digits = value >= 100
      ? 0
      : value >= 1
      ? 2
      : 4;
  return swapTrimFixed(
    swapTruncateToFractionDigits(value, digits),
    fractionDigits: digits,
  );
}

String swapTrimFixed(double value, {required int fractionDigits}) =>
    trimTrailingFiatZeros(value, fractionDigits: fractionDigits);

double swapTruncateToFractionDigits(double value, int fractionDigits) {
  if (!value.isFinite || value <= 0) return 0;
  var factor = 1.0;
  for (var i = 0; i < fractionDigits; i++) {
    factor *= 10;
  }
  return (value * factor).truncateToDouble() / factor;
}
