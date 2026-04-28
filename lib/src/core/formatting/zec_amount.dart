import 'package:flutter/services.dart';

final BigInt zatoshiPerZec = BigInt.from(100000000);

String formatZecAmount(BigInt zatoshi, {int minFractionDigits = 0}) {
  assert(minFractionDigits >= 0 && minFractionDigits <= 8);

  final sign = zatoshi < BigInt.zero ? '-' : '';
  final abs = zatoshi.abs();
  final whole = abs ~/ zatoshiPerZec;
  var fraction = (abs % zatoshiPerZec).toString().padLeft(8, '0');

  fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
  if (fraction.length < minFractionDigits) {
    fraction = fraction.padRight(minFractionDigits, '0');
  }

  return fraction.isEmpty ? '$sign$whole' : '$sign$whole.$fraction';
}

BigInt? parseZecAmount(String input) {
  var value = input.trim();
  if (value.isEmpty || value == '.' || value.contains(',')) return null;
  if (value.startsWith('.')) value = '0$value';

  final parts = value.split('.');
  if (parts.length > 2) return null;

  final wholePart = parts[0];
  final fractionPart = parts.length > 1 ? parts[1] : '';
  if (!_digitsOnly(wholePart) || !_digitsOnly(fractionPart)) return null;
  if (fractionPart.length > 8) return null;

  final whole = BigInt.parse(wholePart.isEmpty ? '0' : wholePart);
  final fraction = BigInt.parse(fractionPart.padRight(8, '0'));
  return (whole * zatoshiPerZec) + fraction;
}

bool _digitsOnly(String value) => RegExp(r'^\d*$').hasMatch(value);

class ZecAmountInputFormatter extends TextInputFormatter {
  const ZecAmountInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(',', '.');
    if (text.isEmpty) return newValue.copyWith(text: text);
    if (!RegExp(r'^[0-9.]*$').hasMatch(text)) return oldValue;
    if ('.'.allMatches(text).length > 1) return oldValue;

    final dotIndex = text.indexOf('.');
    if (dotIndex != -1 && text.length - dotIndex - 1 > 8) return oldValue;

    return newValue.copyWith(text: text);
  }
}
