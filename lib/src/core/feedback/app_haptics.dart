import 'package:flutter/services.dart';

/// Haptic vocabulary for the passcode surfaces and the mobile tab bar.
///
/// All methods are fire-and-forget safe — call them unawaited so a slow
/// platform round trip never delays input handling.
abstract final class AppHaptics {
  static const _channel = MethodChannel('com.zcash.wallet/haptics');

  /// A passcode digit key press — a short, light tap (iOS
  /// UIImpactFeedbackGenerator(.light)).
  static Future<void> digit() => HapticFeedback.lightImpact();

  /// Auxiliary keys (delete, biometric retry) and tab switches — the
  /// subtle selection tick (iOS UISelectionFeedbackGenerator), one step
  /// softer than the digits.
  static Future<void> auxiliaryKey() => HapticFeedback.selectionClick();

  /// A rejected passcode. Native notification-error where the platform
  /// has one (iOS UINotificationFeedbackGenerator(.error), Android
  /// REJECT on API 30+); otherwise a double heavy knock approximates
  /// it.
  static Future<void> error() async {
    try {
      final handled = await _channel.invokeMethod<bool>('error');
      if (handled == true) return;
    } on PlatformException {
      // Fall through to the approximation.
    } on MissingPluginException {
      // Desktop/web hosts have no haptics channel.
    }
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.heavyImpact();
  }
}
