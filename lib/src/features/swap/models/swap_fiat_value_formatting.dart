import '../../../core/config/fiat_currencies.dart';

String swapFormatFiatValue(double value) {
  if (value <= 0) return '0';
  final digits = value >= 100
      ? 0
      : value >= 1
      ? 2
      : 4;
  return swapTrimFixed(
    _truncateToFractionDigits(value, digits),
    fractionDigits: digits,
  );
}

/// Swap quotes are provider-priced in USD, so this stays USD regardless of
/// the Settings display currency; wallet-native surfaces use
/// [formatCompactFiatValueFor] with the selected currency.
String swapFormatCompactFiatValue(double value) =>
    formatCompactFiatValueFor(kUsdFiatCurrency, value);

String swapTrimFixed(double value, {required int fractionDigits}) {
  var text = value.toStringAsFixed(fractionDigits);
  while (text.contains('.') && text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text;
}

double _truncateToFractionDigits(double value, int fractionDigits) {
  if (!value.isFinite || value <= 0) return 0;
  var factor = 1.0;
  for (var i = 0; i < fractionDigits; i++) {
    factor *= 10;
  }
  return (value * factor).truncateToDouble() / factor;
}
