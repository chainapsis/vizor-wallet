import 'package:flutter/services.dart';

class SendDecimalAmountInputFormatter extends TextInputFormatter {
  const SendDecimalAmountInputFormatter({
    required this.maxFractionDigits,
    required this.maxLength,
  });

  final int maxFractionDigits;
  final int maxLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;
    if (text.isEmpty) return newValue;

    final buffer = StringBuffer();
    var hasDecimal = false;
    for (final codeUnit in text.codeUnits) {
      final ch = String.fromCharCode(codeUnit);
      if (ch == '.') {
        if (hasDecimal) continue;
        hasDecimal = true;
        buffer.write(ch);
        continue;
      }
      if (codeUnit >= 0x30 && codeUnit <= 0x39) {
        buffer.write(ch);
      }
    }

    text = buffer.toString();
    if (text.startsWith('.')) text = '0$text';
    if (text.length > maxLength) text = text.substring(0, maxLength);
    final decimalIndex = text.indexOf('.');
    if (decimalIndex >= 0) {
      final maxEnd = decimalIndex + 1 + maxFractionDigits;
      if (text.length > maxEnd) text = text.substring(0, maxEnd);
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
