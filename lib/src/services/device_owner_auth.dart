import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum DeviceOwnerAuthErrorKind { unavailable, failed }

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
  DeviceOwnerAuth({@visibleForTesting MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.zcash.wallet/device_owner_auth');

  final MethodChannel _channel;

  bool get _platformSupported =>
      !kIsWeb &&
      (Platform.isIOS ||
          Platform.isAndroid ||
          Platform.isMacOS ||
          Platform.isLinux ||
          Platform.isWindows);

  /// Returns true only when the OS confirms the device owner.
  ///
  /// A user cancellation returns false. Missing platform support, missing
  /// device credentials, or platform errors throw [DeviceOwnerAuthException].
  Future<bool> verify({required String reason}) async {
    if (!_platformSupported) {
      throw const DeviceOwnerAuthException(
        DeviceOwnerAuthErrorKind.unavailable,
      );
    }

    try {
      return await _channel.invokeMethod<bool>('verify', {'reason': reason}) ==
          true;
    } on MissingPluginException {
      throw const DeviceOwnerAuthException(
        DeviceOwnerAuthErrorKind.unavailable,
      );
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') return false;
      final kind = switch (e.code) {
        'unavailable' => DeviceOwnerAuthErrorKind.unavailable,
        _ => DeviceOwnerAuthErrorKind.failed,
      };
      throw DeviceOwnerAuthException(kind, e.message);
    }
  }
}
