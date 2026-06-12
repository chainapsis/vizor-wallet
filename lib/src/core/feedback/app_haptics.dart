import 'package:flutter/services.dart';

/// Haptic vocabulary for the passcode surfaces.
///
/// All methods are fire-and-forget safe — call them unawaited so a slow
/// platform round trip never delays input handling.
abstract final class AppHaptics {
  static const _channel = MethodChannel('com.zcash.wallet/haptics');

  /// A passcode digit key press.
  static Future<void> digit() => HapticFeedback.mediumImpact();

  /// Auxiliary keys (delete, biometric retry) — one step softer than
  /// the digits.
  static Future<void> auxiliaryKey() => HapticFeedback.lightImpact();

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
