/// Formats an integer with comma thousands separators.
///
/// Examples: `1234567` -> `1,234,567`, `42` -> `42`, `-1000` -> `-1,000`.
String formatGroupedInteger(int value) {
  final text = value.toString();
  return value < 0
      ? '-${formatGroupedIntegerDigits(text.substring(1))}'
      : formatGroupedIntegerDigits(text);
}

/// Groups unsigned ASCII integer digits without converting to a numeric type.
String formatGroupedIntegerDigits(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    buffer.write(digits[i]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  return buffer.toString();
}
