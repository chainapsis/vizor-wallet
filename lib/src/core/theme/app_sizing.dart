import 'app_radii.dart';

/// Component sizing tokens from the Desktop mode in `1 Sizing.zip`.
abstract final class AppAssetSize {
  static const double size = 32;
  static const double icon = 16;
  static const double padding = 4;
}

/// Button sizing tokens from the Desktop mode in `1 Sizing.zip`.
abstract final class AppButtonSizing {
  static const double largeHeight = 44;
}

/// Input sizing tokens from the Desktop mode in `1 Sizing.zip`.
abstract final class AppInputSizing {
  static const double height = 46;
  static const double iconWrapWidth = 32;
  static const double iconSize = 20;
  static const double radius = AppRadii.small;
}

/// Window sizing tokens from the Desktop mode in `1 Sizing.zip`.
abstract final class AppWindowSizing {
  static const double minWidth = 1080;
  static const double minHeight = 720;
  static const double maxWidth = 1296;
  static const double maxHeight = 864;
  static const double contentAreaMaxWidth = 420;
  static const double paneRadius = 20;
}
