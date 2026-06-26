import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum DeviceOwnerAuthErrorKind { unavailable, failed, noLocalCredential }

class DeviceOwnerAuthException implements Exception {
  const DeviceOwnerAuthException(this.kind, [this.message]);

  final DeviceOwnerAuthErrorKind kind;
  final String? message;

  @override
  String toString() =>
      'DeviceOwnerAuthException(${kind.name}${message == null ? '' : ': $message'})';
}

/// OS-level device owner verification for high-risk local actions.
///
/// Unlike biometric unlock, this never returns or unwraps the wallet passcode.
/// The platform prompt only proves that the current OS user can satisfy the
/// device credential / local authentication challenge.
class DeviceOwnerAuth {
  DeviceOwnerAuth({
    @visibleForTesting MethodChannel? channel,
    @visibleForTesting bool? hasOsResetGateOverride,
    @visibleForTesting Duration verifyTimeout = const Duration(minutes: 3),
  }) : _channel =
           channel ?? const MethodChannel('com.zcash.wallet/device_owner_auth'),
       _hasOsResetGateOverride = hasOsResetGateOverride,
       _verifyTimeout = verifyTimeout;

  final MethodChannel _channel;
  final bool? _hasOsResetGateOverride;

  // Safety net for a native side that never replies: the Android < 30
  // confirm-credential path drops its result if the activity is recreated
  // while the system prompt is up, which would otherwise hang the reset flow
  // forever. Generous so a slow-but-legitimate credential entry never trips it.
  final Duration _verifyTimeout;

  bool get _platformSupported =>
      !kIsWeb &&
      (Platform.isIOS ||
          Platform.isAndroid ||
          Platform.isMacOS ||
          Platform.isLinux ||
          Platform.isWindows);

  /// Whether this platform exposes an OS device-owner auth gate used before a
  /// wallet reset. False on Linux: the only available mechanism (polkit) needs
  /// a system-installed policy that the portable AppImage build cannot
  /// register, and polkit cannot exclude biometrics anyway, so the Linux reset
  /// relies on the in-app confirmation (the countdown on the reset screen)
  /// instead of an OS prompt. Callers must not claim OS verification on Linux.
  bool get hasOsResetGate =>
      _hasOsResetGateOverride ?? (!kIsWeb && !Platform.isLinux);

  /// Returns true only when the OS confirms the device owner.
  ///
  /// A user cancellation returns false. Missing platform support, missing
  /// device credentials, or platform errors throw [DeviceOwnerAuthException].
  /// If the local OS/account cannot provide any usable credential for the reset
  /// guard, [DeviceOwnerAuthErrorKind.noLocalCredential] lets callers fall back
  /// to their own non-auth confirmation flow.
  ///
  Future<bool> verify({required String reason}) async {
    if (!_platformSupported) {
      throw const DeviceOwnerAuthException(
        DeviceOwnerAuthErrorKind.unavailable,
      );
    }

    try {
      return await _channel
              .invokeMethod<bool>('verify', <String, Object?>{'reason': reason})
              .timeout(_verifyTimeout) ==
          true;
    } on TimeoutException {
      // The native side never replied; fail closed instead of hanging.
      throw const DeviceOwnerAuthException(
        DeviceOwnerAuthErrorKind.unavailable,
      );
    } on MissingPluginException {
      throw const DeviceOwnerAuthException(
        DeviceOwnerAuthErrorKind.unavailable,
      );
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') return false;
      final kind = switch (e.code) {
        'unavailable' => DeviceOwnerAuthErrorKind.unavailable,
        'no_local_credential' => DeviceOwnerAuthErrorKind.noLocalCredential,
        _ => DeviceOwnerAuthErrorKind.failed,
      };
      throw DeviceOwnerAuthException(kind, e.message);
    }
  }
}
