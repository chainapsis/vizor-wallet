import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Which design-token set this binary was compiled with.
///
/// The Figma variable collections `Sizing` and `Fonts` each carry a
/// Desktop / Mobile mode; [kAppFormFactor] selects between them. Color
/// tokens are form-factor invariant (they vary by Dark / Light theme
/// only), so the form factor never affects `AppColors`.
///
/// The form factor is a **build-time** constant driven by
/// `--dart-define=VIZOR_FORM_FACTOR=desktop|mobile` (default: desktop).
/// Token selectors like `AppTypography.bodyMedium` are const
/// conditionals over [kAppFormFactor], so each binary embeds exactly one
/// token set and the unused branch is tree-shaken in release builds.
/// Desktop builds (macOS, the daily `fvm flutter run` loop, widgetbook,
/// `flutter test`) need no flag; mobile builds must pass
/// `--dart-define=VIZOR_FORM_FACTOR=mobile`. A mismatched debug build
/// fails fast via [debugCheckFormFactorMatchesPlatform].
enum AppFormFactor { desktop, mobile }

const String _formFactorDefine = String.fromEnvironment(
  'VIZOR_FORM_FACTOR',
  defaultValue: 'desktop',
);

/// The token form factor this binary was built for.
const AppFormFactor kAppFormFactor = _formFactorDefine == 'mobile'
    ? AppFormFactor.mobile
    : AppFormFactor.desktop;

/// True on the desktop platforms that `window_manager` supports and where
/// layout switching is meaningful.
bool get isDesktopLayoutPlatform {
  if (kIsWeb) return false;
  return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
}

/// Debug guard: the compiled [kAppFormFactor] must match the platform
/// the app is actually running on.
///
/// Called from the app entry point as `assert(debugCheck...())` so a
/// `flutter run` on a phone without the mobile define dies immediately
/// with the exact flag to pass, instead of silently rendering desktop
/// tokens. Intentionally NOT called from the widgetbook entry point —
/// previewing the mobile token set on a desktop host is legitimate
/// there.
bool debugCheckFormFactorMatchesPlatform() {
  if (_formFactorDefine != 'desktop' && _formFactorDefine != 'mobile') {
    throw StateError(
      'Unknown VIZOR_FORM_FACTOR value "$_formFactorDefine". '
      'Use --dart-define=VIZOR_FORM_FACTOR=desktop or =mobile.',
    );
  }
  final expected = isDesktopLayoutPlatform
      ? AppFormFactor.desktop
      : AppFormFactor.mobile;
  if (kAppFormFactor != expected) {
    throw StateError(
      'This binary was built with the ${kAppFormFactor.name} design-token '
      'set but is running on a ${expected.name} platform. '
      'Rebuild with --dart-define=VIZOR_FORM_FACTOR=${expected.name}.',
    );
  }
  return true;
}
