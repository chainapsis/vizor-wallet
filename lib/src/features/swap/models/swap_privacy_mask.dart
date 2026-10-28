import '../../../core/privacy/privacy_mask.dart';

final _swapAmountTextPattern = RegExp(
  r'^[<>~+\-]?\s*\d[\d,]*(?:\.\d+)?(?:\s+(\S+))?$',
);
final _digit = RegExp(r'\d');

/// Masks a swap amount such as `0.21 USDC` while keeping its own symbol
/// (`****** USDC`), because swap legs are often not ZEC. Text without a number
/// (`Included in shown rate`, `Not reported`, `--`) is returned as is.
String swapAmountTextForPrivacy(
  String amountText, {
  required bool privacyModeEnabled,
  int maskLength = kDefaultPrivacyMaskLength,
}) {
  if (!privacyModeEnabled) return amountText;
  final match = _swapAmountTextPattern.firstMatch(amountText.trim());
  if (match == null) {
    // Fail closed: any other text that carries a number is masked whole.
    return amountText.contains(_digit)
        ? fixedPrivacyMask(length: maskLength)
        : amountText;
  }
  return hideAmountIfPrivacyMode(
    amountText,
    privacyModeEnabled: true,
    maskLength: maskLength,
    denomination: match.group(1) ?? '',
  );
}

/// Masks a captured fiat value (`$12.34`) as a bare mask; the `$--`
/// placeholder has no value and stays visible.
String swapFiatTextForPrivacy(
  String fiatText, {
  required bool privacyModeEnabled,
}) {
  if (!privacyModeEnabled || !fiatText.contains(_digit)) {
    return fiatText;
  }
  return fixedPrivacyMask();
}
