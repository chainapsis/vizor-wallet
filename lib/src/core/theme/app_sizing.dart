/// Component sizing tokens from `1 Sizing-3.zip`.
///
/// The Figma `Sizing` variable collection has a Desktop and a Mobile
/// mode. Like `AppTypography`, both modes exist as complete const sets
/// (`*Desktop` / `*Mobile`) and the unsuffixed class selects between
/// them at compile time via [kAppFormFactor] — mobile builds get larger
/// touch-target metrics with no call-site changes. Reference a mode set
/// directly only in tooling that must show both modes in one binary.
///
/// The `Spacing`, `Radii`, `Units`, and `Window` token groups are
/// identical across both Figma modes, so `AppSpacing`, `AppRadii`, and
/// [AppWindowSizing] stay single-mode constants.
library;

import '../layout/app_form_factor.dart';
import 'app_radii.dart';

/// Asset (avatar/badge) sizing — Desktop mode.
abstract final class AppAssetSizeDesktop {
  static const double size = 32;
  static const double icon = 16;
  static const double padding = 4;
}

/// Asset (avatar/badge) sizing — Mobile mode.
abstract final class AppAssetSizeMobile {
  static const double size = 40;
  static const double icon = 18;
  static const double padding = 0;
}

/// Button sizing — Desktop mode (Figma `Buttons/L`).
abstract final class AppButtonSizingDesktop {
  static const double largeHeight = 44;

  /// Figma `Buttons/MSIconSize`.
  static const double mediumSmallIconSize = 16;
}

/// Button sizing — Mobile mode (Figma `Buttons/L`).
abstract final class AppButtonSizingMobile {
  static const double largeHeight = 50;

  /// Figma `Buttons/MSIconSize`.
  static const double mediumSmallIconSize = 20;
}

/// Input sizing — Desktop mode.
abstract final class AppInputSizingDesktop {
  static const double height = 46;
  static const double iconWrapWidth = 32;
  static const double iconSize = 20;

  /// Figma `Input/Radii` aliases `Radii.S` (12) on desktop.
  static const double radius = AppRadii.small;
}

/// Input sizing — Mobile mode.
abstract final class AppInputSizingMobile {
  static const double height = 60;
  static const double iconWrapWidth = 36;
  static const double iconSize = 24;

  /// Figma `Input/Radii` aliases `Radii.SM` (16) on mobile. Note the
  /// Figma radii scale gained an `SM` step, shifting its names one tier
  /// against Dart's: Figma `SM`/`M`/`L` = Dart `medium`/`large`/`xLarge`
  /// (values unchanged).
  static const double radius = AppRadii.medium;
}

const _mobile = kAppFormFactor == AppFormFactor.mobile;

/// Asset (avatar/badge) sizing for this binary's form factor.
abstract final class AppAssetSize {
  static const size = _mobile
      ? AppAssetSizeMobile.size
      : AppAssetSizeDesktop.size;
  static const icon = _mobile
      ? AppAssetSizeMobile.icon
      : AppAssetSizeDesktop.icon;
  static const padding = _mobile
      ? AppAssetSizeMobile.padding
      : AppAssetSizeDesktop.padding;
}

/// Button sizing for this binary's form factor.
abstract final class AppButtonSizing {
  static const largeHeight = _mobile
      ? AppButtonSizingMobile.largeHeight
      : AppButtonSizingDesktop.largeHeight;
  static const mediumSmallIconSize = _mobile
      ? AppButtonSizingMobile.mediumSmallIconSize
      : AppButtonSizingDesktop.mediumSmallIconSize;
}

/// Input sizing for this binary's form factor.
abstract final class AppInputSizing {
  static const height = _mobile
      ? AppInputSizingMobile.height
      : AppInputSizingDesktop.height;
  static const iconWrapWidth = _mobile
      ? AppInputSizingMobile.iconWrapWidth
      : AppInputSizingDesktop.iconWrapWidth;
  static const iconSize = _mobile
      ? AppInputSizingMobile.iconSize
      : AppInputSizingDesktop.iconSize;
  static const radius = _mobile
      ? AppInputSizingMobile.radius
      : AppInputSizingDesktop.radius;
}

/// Window sizing tokens — desktop-only by nature and identical across
/// both Figma modes.
abstract final class AppWindowSizing {
  static const double minWidth = 1080;
  static const double minHeight = 720;
  static const double maxWidth = 1296;
  static const double maxHeight = 864;
  static const double contentAreaMaxWidth = 420;
  static const double paneRadius = 20;
}
