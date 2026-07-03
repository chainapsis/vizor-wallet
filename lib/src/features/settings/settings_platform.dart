import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

bool settingsUninstallSupported({TargetPlatform? platform}) {
  final effectivePlatform = platform ?? defaultTargetPlatform;
  return effectivePlatform == TargetPlatform.macOS ||
      effectivePlatform == TargetPlatform.linux;
}
