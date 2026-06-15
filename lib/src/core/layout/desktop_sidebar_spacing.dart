import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

import '../theme/app_spacing.dart';

const _macOSWindowControlsTopInset = 40.0;

bool _reservesSpaceForWindowControls(TargetPlatform platform) {
  return platform == TargetPlatform.macOS;
}

double mainSidebarTopPadding({
  required bool compact,
  TargetPlatform? platform,
}) {
  final effectivePlatform = platform ?? defaultTargetPlatform;
  if (!_reservesSpaceForWindowControls(effectivePlatform)) {
    return AppSpacing.sm;
  }

  return compact ? AppSpacing.s : _macOSWindowControlsTopInset;
}

double onboardingSidebarTopOffset({TargetPlatform? platform}) {
  final effectivePlatform = platform ?? defaultTargetPlatform;
  return _reservesSpaceForWindowControls(effectivePlatform)
      ? _macOSWindowControlsTopInset
      : 0;
}
