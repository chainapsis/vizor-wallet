import '../../../core/formatting/number_format.dart';
import '../domain/swap_contract.dart';

final _leadingUngroupedAmount = RegExp(
  r'^(\s*(?:[<>~≈$+\-]\s*)*)([0-9]{4,})(?=(?:\.[0-9]+)?(?:$|\s+(?!\s*%)))',
);

/// Groups the integer part of a swap amount without rounding or changing its
/// units. The input may include a sign, fiat symbol, or trailing slippage.
String groupSwapAmountText(String text) => text.replaceFirstMapped(
  _leadingUngroupedAmount,
  (match) => '${match[1]}${formatGroupedIntegerDigits(match[2]!)}',
);

String groupSwapRateText(String text) =>
    text.split(' = ').map(groupSwapAmountText).join(' = ');

String? swapBaseUnitAmountText({
  required String? value,
  required SwapAsset asset,
  required int decimals,
}) {
  final raw = _cleanOptionalText(value);
  if (raw == null || !_isIntegerAmount(raw)) return null;
  final amount = swapTrimDecimal(swapBaseUnitsToDecimal(raw, decimals));
  return '$amount ${asset.symbol}';
}

String? swapStatusAmountText({
  required String? formatted,
  required String? baseUnits,
  required SwapAsset asset,
  required int decimals,
}) {
  final formattedValue = _cleanOptionalText(formatted);
  if (formattedValue != null && double.tryParse(formattedValue) != null) {
    return '${swapTrimDecimal(formattedValue)} ${asset.symbol}';
  }
  return swapBaseUnitAmountText(
    value: baseUnits,
    asset: asset,
    decimals: decimals,
  );
}

double? swapStatusDecimalAmount({
  required String? formatted,
  required String? baseUnits,
  required int decimals,
  bool preferBaseUnits = false,
}) {
  if (preferBaseUnits) {
    final baseUnitAmount = _baseUnitDecimalAmount(
      baseUnits,
      decimals: decimals,
    );
    if (baseUnitAmount != null) return baseUnitAmount;
  }
  final formattedValue = _cleanOptionalText(formatted);
  if (formattedValue != null) {
    final parsed = double.tryParse(formattedValue);
    if (parsed != null) return parsed;
  }
  return _baseUnitDecimalAmount(baseUnits, decimals: decimals);
}

String swapFeeAmountText(SwapAsset asset, double amount) {
  if (!amount.isFinite || amount <= 0) return '0 ${asset.symbol}';
  return '${swapPreciseAmountText(asset, amount)} ${asset.symbol}';
}

String swapPreciseAmountText(SwapAsset asset, double amount) {
  final fractionDigits = asset.decimals.clamp(0, 8).toInt();
  if (fractionDigits == 0) return amount.toStringAsFixed(0);
  final visibleMinimum = _minimumDecimalAmount(fractionDigits);
  if (amount < visibleMinimum) {
    return '<${visibleMinimum.toStringAsFixed(fractionDigits)}';
  }
  return swapTrimDecimal(amount.toStringAsFixed(fractionDigits));
}

String swapBaseUnitsToDecimal(String amount, int decimals) {
  final negative = amount.startsWith('-');
  final digits = negative ? amount.substring(1) : amount;
  if (decimals <= 0) return negative ? '-$digits' : digits;
  final padded = digits.padLeft(decimals + 1, '0');
  final whole = padded.substring(0, padded.length - decimals);
  final fraction = padded.substring(padded.length - decimals);
  final decimal = swapTrimDecimal('$whole.$fraction');
  return negative ? '-$decimal' : decimal;
}

String swapTrimDecimal(String value) {
  var text = value.trim();
  if (!text.contains('.')) return text;
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text;
}

double? _baseUnitDecimalAmount(String? baseUnits, {required int decimals}) {
  final raw = _cleanOptionalText(baseUnits);
  if (raw == null || !_isIntegerAmount(raw)) return null;
  return double.tryParse(swapBaseUnitsToDecimal(raw, decimals));
}

String? _cleanOptionalText(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

bool _isIntegerAmount(String value) {
  return RegExp(r'^-?\d+$').hasMatch(value.trim());
}

double _minimumDecimalAmount(int fractionDigits) {
  var value = 1.0;
  for (var i = 0; i < fractionDigits; i++) {
    value /= 10;
  }
  return value;
}
