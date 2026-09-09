import 'package:flutter/services.dart';

/// Accepts decimal amount edits within the configured precision and optional
/// total length. Invalid edits are rejected without rewriting the text,
/// selection, or composing range.
class DecimalAmountInputFormatter extends TextInputFormatter {
  const DecimalAmountInputFormatter({
    required this.maxFractionDigits,
    this.maxLength,
  }) : assert(maxFractionDigits >= 0),
       assert(maxLength == null || maxLength >= 0);

  final int maxFractionDigits;
  final int? maxLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    final maximumLength = maxLength;
    if (maximumLength != null && text.length > maximumLength) {
      return oldValue;
    }
    final pattern = RegExp('^\\d*(\\.\\d{0,$maxFractionDigits})?\$');
    return pattern.hasMatch(text) ? newValue : oldValue;
  }
}
