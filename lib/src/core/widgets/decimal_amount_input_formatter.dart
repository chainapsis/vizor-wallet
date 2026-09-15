import 'package:flutter/services.dart';

/// Accepts decimal amounts within the configured precision and optional length.
/// Committed leading-decimal edits gain a zero while preserving the selection.
/// Invalid edits are rejected; active composing text is not rewritten.
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
    final sourceText = newValue.text;
    if (sourceText.isEmpty) return newValue;
    final insertLeadingZero =
        sourceText.startsWith('.') && newValue.composing.isCollapsed;
    final text = insertLeadingZero ? '0$sourceText' : sourceText;
    final maximumLength = maxLength;
    if (maximumLength != null && text.length > maximumLength) {
      return oldValue;
    }
    final pattern = RegExp('^\\d*(\\.\\d{0,$maxFractionDigits})?\$');
    if (!pattern.hasMatch(text)) return oldValue;
    if (!insertLeadingZero) return newValue;

    int shiftOffset(int offset) => offset < 0 ? offset : offset + 1;

    return newValue.copyWith(
      text: text,
      selection: newValue.selection.copyWith(
        baseOffset: shiftOffset(newValue.selection.baseOffset),
        extentOffset: shiftOffset(newValue.selection.extentOffset),
      ),
      composing: TextRange.empty,
    );
  }
}
