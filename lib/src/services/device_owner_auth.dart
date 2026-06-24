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
  DeviceOwnerAuth({
    @visibleForTesting MethodChannel? channel,
    @visibleForTesting bool? requiresAppProvidedCredentialOverride,
  }) : _channel =
           channel ?? const MethodChannel('com.zcash.wallet/device_owner_auth'),
       _requiresAppProvidedCredentialOverride =
           requiresAppProvidedCredentialOverride;

  final MethodChannel _channel;
  final bool? _requiresAppProvidedCredentialOverride;

  bool get _platformSupported =>
      !kIsWeb &&
      (Platform.isIOS ||
          Platform.isAndroid ||
          Platform.isMacOS ||
          Platform.isLinux ||
          Platform.isWindows);

  /// Whether the app must collect the OS credential itself before calling
  /// [verify], instead of the OS presenting its own prompt.
  ///
  /// True only on Windows: there is no Windows consent API that requires the
  /// device PIN/password while excluding Windows Hello biometrics, so the reset
  /// gate renders its own password field and we validate the typed Windows
  /// account password via `LogonUser` (which a biometric can never satisfy).
  /// iOS/macOS/Android/Linux present a native passcode prompt instead, so
  /// [verify] is called without a [password].
  bool get requiresAppProvidedCredential =>
      _requiresAppProvidedCredentialOverride ?? (!kIsWeb && Platform.isWindows);

  /// Returns true only when the OS confirms the device owner.
  ///
  /// A user cancellation returns false. Missing platform support, missing
  /// device credentials, or platform errors throw [DeviceOwnerAuthException].
  ///
  /// [password] is only consumed when [requiresAppProvidedCredential] is true
  /// (Windows); on the OS-prompt platforms it is ignored.
  Future<bool> verify({required String reason, String? password}) async {
    if (!_platformSupported) {
      throw const DeviceOwnerAuthException(
        DeviceOwnerAuthErrorKind.unavailable,
      );
    }

    try {
      final args = <String, Object?>{'reason': reason};
      if (password != null) {
        args['password'] = password;
      }
      return await _channel.invokeMethod<bool>('verify', args) == true;
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
