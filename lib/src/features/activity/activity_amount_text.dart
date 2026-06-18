import '../../core/layout/app_form_factor.dart';

const mobileActivityAmountMaxCharacters = 14;

/// Compacts [value] to [mobileActivityAmountMaxCharacters] on the mobile
/// form factor and leaves desktop rows unchanged. Form-factor branching is a
/// compile-time [kAppFormFactor] const so the unused branch is tree-shaken.
String activityAmountTextForFormFactor(String value) =>
    kAppFormFactor == AppFormFactor.mobile
    ? compactMobileActivityAmountText(value)
    : value;

String compactMobileActivityAmountText(
  String value, {
  int maxCharacters = mobileActivityAmountMaxCharacters,
}) {
  if (maxCharacters < 1) {
    throw ArgumentError.value(
      maxCharacters,
      'maxCharacters',
      'must be positive',
    );
  }

  final base = value.trim().replaceAllMapped(RegExp(r'~(?=\d)'), (_) => '');
  final match = RegExp(
    r'^([<>+\-]?)([\d,]+(?:\.\d+)?)(\s+.+)$',
  ).firstMatch(base);
  if (match == null) return base;

  final prefix = match[1] ?? '';
  final amountText = match[2]!;
  final suffix = match[3]!;
  final amount = double.tryParse(amountText.replaceAll(',', ''));
  if (amount == null || !amount.isFinite) return base;

  if (amount >= 1000000) {
    return _compactActivityNumber(
      prefix: prefix,
      value: amount / 1000000,
      marker: 'M',
      suffix: suffix,
      maxCharacters: maxCharacters,
    );
  }
  if (amount >= 1000) {
    return _compactActivityNumber(
      prefix: prefix,
      value: amount / 1000,
      marker: 'K',
      suffix: suffix,
      maxCharacters: maxCharacters,
    );
  }

  return '$prefix${_truncateActivityDecimal(amountText)}$suffix';
}

String _truncateActivityDecimal(String amountText) {
  final parts = amountText.split('.');
  if (parts.length != 2) return amountText;

  final integerText = parts[0];
  final fractionText = parts[1];
  final integer = int.tryParse(integerText.replaceAll(',', ''));
  final maxFractionDigits = integer == 0 && fractionText.startsWith('000')
      ? 8
      : 6;
  if (fractionText.length <= maxFractionDigits) return amountText;
  return '$integerText.${fractionText.substring(0, maxFractionDigits)}';
}

String _compactActivityNumber({
  required String prefix,
  required double value,
  required String marker,
  required String suffix,
  required int maxCharacters,
}) {
  for (var fractionDigits = 3; fractionDigits >= 0; fractionDigits--) {
    final text =
        '$prefix${_truncatedCompactNumber(value, fractionDigits)}$marker$suffix';
    if (text.length <= maxCharacters || fractionDigits == 0) return text;
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
