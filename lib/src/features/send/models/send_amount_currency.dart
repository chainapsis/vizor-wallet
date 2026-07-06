import '../../../core/formatting/number_format.dart';
import '../../../core/formatting/zec_amount.dart';

enum SendAmountInputMode { zec, usd }

BigInt? sendZatoshiFromUsdText(String text, double? zecUsdUnitPrice) {
  final normalized = text.trim();
  if (normalized.isEmpty || normalized == '.' || normalized == '0.') {
    return null;
  }
  final usd = _DecimalAmount.tryParse(normalized);
  final price = _DecimalAmount.tryParseDouble(zecUsdUnitPrice);
  if (usd == null || price == null || usd.units <= BigInt.zero) return null;

  final numerator = usd.units * zatoshiPerZec * price.scale;
  final denominator = usd.scale * price.units;
  final zatoshi = numerator ~/ denominator;
  return zatoshi > BigInt.zero ? zatoshi : null;
}

String sendUsdInputTextForZatoshi(BigInt zatoshi, double zecUsdUnitPrice) {
  final price = _DecimalAmount.tryParseDouble(zecUsdUnitPrice);
  if (price == null || zatoshi <= BigInt.zero) return '';

  final numerator = zatoshi * price.units * BigInt.from(100);
  final denominator = zatoshiPerZec * price.scale;
  final cents = _roundDiv(numerator, denominator);
  final whole = cents ~/ BigInt.from(100);
  final fraction = (cents % BigInt.from(100)).toString().padLeft(2, '0');
  return '$whole.$fraction';
}

String sendableUsdInputTextForZatoshi(BigInt zatoshi, double zecUsdUnitPrice) {
  final text = sendUsdInputTextForZatoshi(zatoshi, zecUsdUnitPrice);
  return text == '0.00' ? '' : text;
}

String sendUsdDisplayTextForZatoshi(BigInt zatoshi, double zecUsdUnitPrice) {
  final raw = sendUsdInputTextForZatoshi(zatoshi, zecUsdUnitPrice);
  if (raw.isEmpty) return '0.00';
  final parts = raw.split('.');
  final whole = int.tryParse(parts.first) ?? 0;
  final fraction = parts.length > 1 ? parts[1] : '00';
  return '${formatGroupedInteger(whole)}.$fraction';
}

BigInt _roundDiv(BigInt numerator, BigInt denominator) {
  return (numerator + (denominator ~/ BigInt.two)) ~/ denominator;
}

class _DecimalAmount {
  const _DecimalAmount({required this.units, required this.scale});

  final BigInt units;
  final BigInt scale;

  static _DecimalAmount? tryParseDouble(double? value) {
    if (value == null || !value.isFinite || value <= 0) return null;
    return tryParse(_expandScientificNotation(value.toString()));
  }

  static _DecimalAmount? tryParse(String input) {
    var value = input.trim();
    if (value.isEmpty || value.contains(',')) return null;
    if (value.startsWith('.')) value = '0$value';

    final parts = value.split('.');
    if (parts.length > 2) return null;
    final wholePart = parts[0];
    final fractionPart = parts.length > 1 ? parts[1] : '';
    if (!_digitsOnly(wholePart) || !_digitsOnly(fractionPart)) return null;

    final units = BigInt.parse(
      '${wholePart.isEmpty ? '0' : wholePart}$fractionPart',
    );
    final scale = BigInt.from(10).pow(fractionPart.length);
    return _DecimalAmount(units: units, scale: scale);
  }

  static bool _digitsOnly(String value) => RegExp(r'^\d*$').hasMatch(value);

  static String _expandScientificNotation(String value) {
    final match = RegExp(
      r'^(\d+)(?:\.(\d+))?[eE]([+-]?\d+)$',
    ).firstMatch(value);
    if (match == null) return value;

    final whole = match.group(1)!;
    final fraction = match.group(2) ?? '';
    final exponent = int.parse(match.group(3)!);
    final digits = '$whole$fraction';
    final decimalIndex = whole.length + exponent;
    if (decimalIndex <= 0) {
      return '0.${_zeros(-decimalIndex)}$digits';
    }
    if (decimalIndex >= digits.length) {
      return '$digits${_zeros(decimalIndex - digits.length)}';
    }
    return '${digits.substring(0, decimalIndex)}.'
        '${digits.substring(decimalIndex)}';
  }

  static String _zeros(int count) => List.filled(count, '0').join();
}
