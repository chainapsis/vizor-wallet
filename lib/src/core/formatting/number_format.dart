/// Formats an integer with comma thousands separators.
///
/// Examples: `1234567` -> `1,234,567`, `42` -> `42`, `-1000` -> `-1,000`.
String formatGroupedInteger(int value) {
  final negative = value < 0;
  final text = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final remaining = text.length - i;
    buffer.write(text[i]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  return negative ? '-$buffer' : buffer.toString();
}
