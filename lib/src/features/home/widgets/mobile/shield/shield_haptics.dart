import 'dart:async';
import 'package:flutter/services.dart';
import '../../../../../core/feedback/app_haptics.dart';

// Presentation feedback uses the app's existing platform haptic boundary.
// Intensity is kept in the particle API; unsupported devices approximate it.
abstract final class Haptics {
  static void prepare() {}
  static void selection() => unawaited(HapticFeedback.selectionClick());
  static void success() => unawaited(AppHaptics.sendSuccess());
  static void impact(ImpactStyle style, {double intensity = 1}) {
    unawaited(switch (style) {
      ImpactStyle.light || ImpactStyle.soft => HapticFeedback.lightImpact(),
      ImpactStyle.medium => HapticFeedback.mediumImpact(),
      ImpactStyle.heavy || ImpactStyle.rigid => HapticFeedback.heavyImpact(),
    });
  }
}

enum ImpactStyle { light, medium, heavy, soft, rigid }
