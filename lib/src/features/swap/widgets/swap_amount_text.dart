const swapDisplayMaxFractionDigits = 6;

String compactSwapAmountText(
  String value, {
  int maxFractionDigits = swapDisplayMaxFractionDigits,
}) {
  if (maxFractionDigits < 0) {
    throw ArgumentError.value(
      maxFractionDigits,
      'maxFractionDigits',
      'must not be negative',
    );
  }
  if (maxFractionDigits == 0) {
    return value.replaceAllMapped(
      RegExp(r'([~<>+\-]?)(\d+)\.(\d+)'),
      (match) => '${match[1]}${match[2]}',
    );
  }
  final expression = RegExp(
    '([~<>+\\-]?)(\\d+)\\.(\\d{$maxFractionDigits})(\\d+)',
  );
  return value.replaceAllMapped(
    expression,
    (match) => '${match[1]}${match[2]}.${match[3]}',
  );
}
