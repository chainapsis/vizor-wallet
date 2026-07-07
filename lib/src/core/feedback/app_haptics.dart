import 'package:flutter/services.dart';

/// Haptic vocabulary for passcode surfaces, mobile navigation, and
/// privacy controls.
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

  /// Privacy visibility toggles — a more deliberate medium tap (iOS
  /// UIImpactFeedbackGenerator(.medium)).
  static Future<void> privacyToggle() => HapticFeedback.mediumImpact();

  /// Copying sensitive values — a light confirmation tap.
  static Future<void> copy() => HapticFeedback.lightImpact();

  /// Send success confirmation — native-only custom haptic:
  /// 30ms pulse, then 40ms full-intensity pulse after a 60ms delay.
  static Future<void> sendSuccess() async {
    try {
      await _channel.invokeMethod<bool>('sendSuccess');
    } on PlatformException {
      // No fallback: keep send success free of system-style audio feedback.
    } on MissingPluginException {
      // Desktop/web hosts have no haptics channel.
    }
  }

  /// Send failure confirmation — native-only custom haptic:
  /// four short pulses over 290ms, matching the mobile send-fail design.
  static Future<void> sendFailure() async {
    try {
      await _channel.invokeMethod<bool>('sendFailure');
    } on PlatformException {
      // No fallback: keep send failure on the authored haptic path only.
    } on MissingPluginException {
      // Desktop/web hosts have no haptics channel.
    }
  }

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
