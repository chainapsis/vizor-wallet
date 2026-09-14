/// Keystroke guards for the desktop and mobile "Request ZEC" amount fields.
/// Commas are normalized first. Unlike the rejecting amount formatter used by
/// Send, request inputs retain their existing sanitizing/truncating behavior.
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
    final sourceText = newValue.text;
    // Do not interfere with the input method while it owns a composing range.
    if (sourceText.isEmpty || !newValue.composing.isCollapsed) return newValue;

    final buffer = StringBuffer();
    final boundaryOffsets = List<int>.filled(sourceText.length + 1, 0);
    var hasDecimal = false;
    for (var index = 0; index < sourceText.length; index++) {
      final codeUnit = sourceText.codeUnitAt(index);
      final ch = String.fromCharCode(codeUnit);
      if (ch == '.') {
        if (!hasDecimal) {
          hasDecimal = true;
          buffer.write(ch);
        }
      } else if (codeUnit >= 0x30 && codeUnit <= 0x39) {
        buffer.write(ch);
      }
      boundaryOffsets[index + 1] = buffer.length;
    }

    var text = buffer.toString();
    final insertedLeadingZero = text.startsWith('.');
    if (insertedLeadingZero) text = '0$text';
    if (text.length > maxLength) text = text.substring(0, maxLength);
    final decimalIndex = text.indexOf('.');
    if (decimalIndex >= 0) {
      final maxEnd = decimalIndex + 1 + maxFractionDigits;
      if (text.length > maxEnd) text = text.substring(0, maxEnd);
    }

    if (text == sourceText) return newValue;

    int mapOffset(int offset) {
      if (offset < 0) return offset;
      final mapped =
          boundaryOffsets[offset.clamp(0, sourceText.length)] +
          (insertedLeadingZero ? 1 : 0);
      return mapped.clamp(0, text.length);
    }

    return newValue.copyWith(
      text: text,
      selection: newValue.selection.copyWith(
        baseOffset: mapOffset(newValue.selection.baseOffset),
        extentOffset: mapOffset(newValue.selection.extentOffset),
      ),
      composing: TextRange.empty,
    );
  }
}
