/// Keystroke guards for the two "Request ZEC" amount fields.
///
/// Every other amount field in the app installs these; the request field was
/// the one exception, and it is the field least able to afford it. A ZIP-321
/// amount has a stricter grammar than the parser that draws the conversion
/// line, so text the screen happily converts (`.5`) and text a comma-decimal
/// keypad emits on its own (`0,5`) both reach the builder as a rejection the
/// user never asked for — a dead "Create request" and no way to see why.
///
/// Same rules and same order as the send composers
/// (`send_screen.dart`, `mobile_send_screen.dart`): comma first, so the
/// decimal validator only ever sees a period.
library;

import 'package:flutter/services.dart';

import '../../../../core/widgets/comma_to_dot_input_formatter.dart';

/// A zatoshi is the eighth decimal place; cents are the second.
const int _kZecFractionDigits = 8;
const int _kUsdFractionDigits = 2;

/// `21000000.00000000` is 17 characters, and no ZEC amount is longer. The
/// dollar cap is the send composer's.
const int _kZecMaxLength = 17;
const int _kUsdMaxLength = 12;

const List<TextInputFormatter> _zecAmountFormatters = [
  CommaToDotInputFormatter(),
  RequestDecimalAmountInputFormatter(
    maxFractionDigits: _kZecFractionDigits,
    maxLength: _kZecMaxLength,
  ),
];

const List<TextInputFormatter> _usdAmountFormatters = [
  CommaToDotInputFormatter(),
  RequestDecimalAmountInputFormatter(
    maxFractionDigits: _kUsdFractionDigits,
    maxLength: _kUsdMaxLength,
  ),
];

/// The formatters a request amount field installs for the unit it is
/// currently collecting.
List<TextInputFormatter> requestAmountInputFormatters({required bool isUsd}) =>
    isUsd ? _usdAmountFormatters : _zecAmountFormatters;

/// Keeps a field to one plain decimal number.
///
/// Everything that is not a digit or the first period is dropped, a leading
/// period is completed to `0.`, and both the whole length and the fraction
/// are capped. Paste goes through this as well as typing, which is what the
/// desktop field needs: its keyboard has every character on it.
class RequestDecimalAmountInputFormatter extends TextInputFormatter {
  const RequestDecimalAmountInputFormatter({
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
