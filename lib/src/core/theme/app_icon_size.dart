/// Icon sizing scale from the Figma token export (Mode 1 / Icons).
///
/// Figma names the sizes `M` and `L`; we rename to `medium` / `large` so
/// call sites read in English rather than one-letter initials. Both modes
/// share these values — see [AppSpacing] for the same rationale.
abstract final class AppIconSize {
  static const double medium = 16;
  static const double large = 24;
}
