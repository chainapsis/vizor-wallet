const swapDisplayMaxFractionDigits = 6;
const swapReviewSummaryMaxChars = 13;

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
  final withoutApproximationPrefix = value.replaceAllMapped(
    RegExp(r'~(?=\d)'),
    (_) => '',
  );
  if (maxFractionDigits == 0) {
    return withoutApproximationPrefix.replaceAllMapped(
      RegExp(r'([<>+\-]?)(\d+)\.(\d+)'),
      (match) => '${match[1]}${match[2]}',
    );
  }
  final expression = RegExp(
    '([<>+\\-]?)(\\d+)\\.(\\d{$maxFractionDigits})(\\d+)',
  );
  return withoutApproximationPrefix.replaceAllMapped(
    expression,
    (match) => '${match[1]}${match[2]}.${match[3]}',
  );
}

bool isLongSwapSummaryAmountText(String value) {
  return compactSwapAmountText(value).length > swapReviewSummaryMaxChars;
}

String compactSwapSummaryAmountText(
  String value, {
  bool forceCompactThousands = false,
  int? maxCharacters,
}) {
  final base = compactSwapAmountText(value);
  final match = RegExp(
    r'^([<>+\-]?)([\d,]+(?:\.\d+)?)(\s+.+)$',
  ).firstMatch(base.trim());
  if (match == null) return base;

  final amount = double.tryParse(match[2]!.replaceAll(',', ''));
  if (amount == null || !amount.isFinite) return base;

  final prefix = match[1] ?? '';
  final suffix = match[3]!;
  if (amount >= 1000000) {
    return _compactSummaryNumber(
      prefix: prefix,
      value: amount / 1000000,
      marker: 'M',
      suffix: suffix,
      maxCharacters: maxCharacters,
    );
  }
  if (forceCompactThousands && amount >= 1000) {
    return _compactSummaryNumber(
      prefix: prefix,
      value: amount / 1000,
      marker: 'K',
      suffix: suffix,
      maxCharacters: maxCharacters,
    );
  }
  return base;
}

String _compactSummaryNumber({
  required String prefix,
  required double value,
  required String marker,
  required String suffix,
  required int? maxCharacters,
}) {
  for (var fractionDigits = 3; fractionDigits >= 0; fractionDigits--) {
    final text =
        '$prefix${_truncatedCompactNumber(value, fractionDigits)}$marker$suffix';
    if (maxCharacters == null ||
        text.length <= maxCharacters ||
        fractionDigits == 0) {
      return text;
    }
  }
  throw StateError('unreachable');
}

String _truncatedCompactNumber(double value, int fractionDigits) {
  var factor = 1.0;
  for (var index = 0; index < fractionDigits; index++) {
    factor *= 10;
  }
  final truncated = (value * factor).truncateToDouble() / factor;
  var text = truncated.toStringAsFixed(fractionDigits);
  while (text.contains('.') && text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text;
}
