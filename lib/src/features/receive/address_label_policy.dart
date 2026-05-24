const int kAddressLabelMaxLength = 50;

/// Normalizes a user-entered address label: trims whitespace, enforces the
/// max length, and returns null for blank input (which clears the label).
String? normalizeAddressLabel(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.length > kAddressLabelMaxLength
      ? trimmed.substring(0, kAddressLabelMaxLength)
      : trimmed;
}
