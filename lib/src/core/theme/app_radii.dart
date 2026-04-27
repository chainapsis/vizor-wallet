/// Corner-radius scale from the Figma token export (Mode 1 / Radii).
///
/// Figma names these `XS / S / SM / M / L / Full`; Dart exposes full words so
/// callers read like the rest of the design-system API.
///
/// [full] is the pill/stadium radius. Flutter's `StadiumBorder` is usually
/// a better choice than `BorderRadius.circular(AppRadii.full)` since it
/// adapts automatically to any element height. Keep [full] available for
/// the few places where a literal radius is more convenient.
abstract final class AppRadii {
  static const double xSmall = 8;
  static const double small = 12;
  static const double medium = 16;
  static const double large = 24;
  static const double xLarge = 32;
  static const double full = 999;
}
