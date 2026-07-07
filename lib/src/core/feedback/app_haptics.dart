import 'package:flutter/foundation.dart';
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

  /// Send success confirmation — native custom haptic where available:
  /// 30ms pulse, then 40ms full-intensity pulse after a 60ms delay.
  static Future<void> sendSuccess() async {
    try {
      final handled = await _channel.invokeMethod<bool>('sendSuccess');
      if (handled == true) return;
    } on PlatformException {
      // Fall through to the non-iOS approximation.
    } on MissingPluginException {
      // Fall through to the non-iOS approximation.
    }
    if (_shouldFallbackCustomSendHaptics) await _sendSuccessFallback();
  }

  /// Send failure confirmation — native custom haptic where available:
  /// four short pulses over 290ms, matching the mobile send-fail design.
  static Future<void> sendFailure() async {
    try {
      final handled = await _channel.invokeMethod<bool>('sendFailure');
      if (handled == true) return;
    } on PlatformException {
      // Fall through to the non-iOS approximation.
    } on MissingPluginException {
      // Fall through to the non-iOS approximation.
    }
    if (_shouldFallbackCustomSendHaptics) await _sendFailureFallback();
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

  static bool get _shouldFallbackCustomSendHaptics =>
      defaultTargetPlatform != TargetPlatform.iOS;

  static Future<void> _sendSuccessFallback() async {
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 160));
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 110));
    await HapticFeedback.selectionClick();
  }

  static Future<void> _sendFailureFallback() => HapticFeedback.lightImpact();
}
