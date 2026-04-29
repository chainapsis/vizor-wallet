const kDefaultPrivacyMaskLength = 6;

String fixedPrivacyMask({int length = kDefaultPrivacyMaskLength}) {
  return '*' * length;
}

String hideIfPrivacyMode(
  String visibleText, {
  required bool privacyModeEnabled,
  int maskLength = kDefaultPrivacyMaskLength,
  String suffix = '',
}) {
  if (!privacyModeEnabled) return visibleText;
  return '${fixedPrivacyMask(length: maskLength)}$suffix';
}

String hideAmountIfPrivacyMode(
  String visibleText, {
  required bool privacyModeEnabled,
  int maskLength = kDefaultPrivacyMaskLength,
  String denomination = 'ZEC',
}) {
  return hideIfPrivacyMode(
    visibleText,
    privacyModeEnabled: privacyModeEnabled,
    maskLength: maskLength,
    suffix: denomination.isEmpty ? '' : ' $denomination',
  );
}
