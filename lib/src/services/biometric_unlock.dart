import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_localizations.dart';

/// What the device offers for the escrow prompt; drives copy ("Face ID",
/// "fingerprint", or generic "biometrics") and whether opt-in surfaces render.
enum BiometricKind { face, fingerprint, none }

extension BiometricKindCopy on BiometricKind {
  String inlineLabel(AppLocalizations l10n) => switch (this) {
    BiometricKind.face => l10n.biometricFaceId,
    BiometricKind.fingerprint => l10n.biometricFingerprintInline,
    BiometricKind.none => l10n.biometricBiometricsInline,
  };

  String standaloneLabel(AppLocalizations l10n) => switch (this) {
    BiometricKind.face => l10n.biometricFaceId,
    BiometricKind.fingerprint => l10n.biometricFingerprintStandalone,
    BiometricKind.none => l10n.biometricBiometricsStandalone,
  };

  String onboardingTitleSuffix(AppLocalizations l10n) => switch (this) {
    BiometricKind.face => l10n.biometricFaceId,
    BiometricKind.fingerprint => l10n.biometricYourFingerprint,
    BiometricKind.none => l10n.biometricBiometricsInline,
  };

  String unlockFeatureLabel(AppLocalizations l10n) => switch (this) {
    BiometricKind.face => l10n.biometricUnlockFeatureFace,
    BiometricKind.fingerprint => l10n.biometricUnlockFeatureFingerprint,
    BiometricKind.none => l10n.biometricUnlockFeatureNone,
  };

  String inlineUnlockFeatureLabel(AppLocalizations l10n) => switch (this) {
    BiometricKind.face => l10n.biometricUnlockFeatureFace,
    BiometricKind.fingerprint => l10n.biometricUnlockFeatureInlineFingerprint,
    BiometricKind.none => l10n.biometricUnlockFeatureInlineNone,
  };

  String changedMessage(AppLocalizations l10n) => switch (this) {
    BiometricKind.face => l10n.biometricChangedFace,
    BiometricKind.fingerprint => l10n.biometricChangedFingerprint,
    BiometricKind.none => l10n.biometricChangedNone,
  };

  String enableLabel(AppLocalizations l10n) =>
      l10n.biometricEnable(inlineLabel(l10n));

  String signInLabel(AppLocalizations l10n) =>
      l10n.biometricSignIn(inlineLabel(l10n));
}

class BiometricAvailability {
  const BiometricAvailability({
    required this.supported,
    required this.enrolled,
    required this.kind,
  });

  static const unavailable = BiometricAvailability(
    supported: false,
    enrolled: false,
    kind: BiometricKind.none,
  );

  final bool supported;
  final bool enrolled;
  final BiometricKind kind;

  bool get usable => supported && enrolled;
}

enum BiometricUnlockErrorKind {
  /// The user dismissed the prompt — not an error to surface.
  cancelled,

  /// Too many failed attempts; the OS locked biometry out until the
  /// device is re-authenticated.
  lockedOut,

  /// Biometric enrollment changed since the escrow was written; the OS
  /// invalidated the item. The caller must drop the enabled flag and
  /// fall back to the passcode.
  invalidated,

  /// No biometrics enrolled / hardware unavailable.
  unavailable,

  /// Anything else (treated as a soft failure → passcode fallback).
  failed,
}

class BiometricUnlockException implements Exception {
  const BiometricUnlockException(this.kind, [this.message]);

  final BiometricUnlockErrorKind kind;
  final String? message;

  @override
  String toString() =>
      'BiometricUnlockException(${kind.name}${message == null ? '' : ': $message'})';
}

/// Platform escrow for the wallet passcode, protected by the device's
/// current biometric set (iOS: keychain item behind
/// `biometryCurrentSet`; Android: Keystore key requiring
/// BiometricPrompt). The passcode remains the single source of truth —
/// a successful prompt merely supplies it to the existing unlock path.
class BiometricUnlock {
  BiometricUnlock({@visibleForTesting MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.zcash.wallet/biometric_unlock');

  final MethodChannel _channel;

  bool get _platformSupported =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  Future<BiometricAvailability> availability() async {
    if (!_platformSupported) return BiometricAvailability.unavailable;
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'availability',
      );
      if (raw == null) return BiometricAvailability.unavailable;
      return BiometricAvailability(
        supported: raw['supported'] == true,
        enrolled: raw['enrolled'] == true,
        kind: switch (raw['kind']) {
          'face' => BiometricKind.face,
          'fingerprint' => BiometricKind.fingerprint,
          _ => BiometricKind.none,
        },
      );
    } on PlatformException {
      return BiometricAvailability.unavailable;
    } on MissingPluginException {
      return BiometricAvailability.unavailable;
    }
  }

  /// Writes (or overwrites) the escrow. Requires an enrolled biometric
  /// set; the prompt is NOT shown for writes.
  Future<void> enable(String passcode) async {
    try {
      await _channel.invokeMethod<void>('enable', {'passcode': passcode});
    } on PlatformException catch (e) {
      throw _mapError(e);
    }
  }

  /// Deletes the escrow. Idempotent.
  Future<void> disable() async {
    try {
      await _channel.invokeMethod<void>('disable');
    } on PlatformException catch (e) {
      throw _mapError(e);
    }
  }

  /// Shows the biometric prompt and returns the escrowed passcode.
  Future<String> read({required String reason}) async {
    try {
      final passcode = await _channel.invokeMethod<String>('read', {
        'reason': reason,
      });
      if (passcode == null || passcode.isEmpty) {
        throw const BiometricUnlockException(BiometricUnlockErrorKind.failed);
      }
      return passcode;
    } on PlatformException catch (e) {
      throw _mapError(e);
    }
  }

  BiometricUnlockException _mapError(PlatformException e) {
    final kind = switch (e.code) {
      'cancelled' => BiometricUnlockErrorKind.cancelled,
      'lockedOut' => BiometricUnlockErrorKind.lockedOut,
      'invalidated' => BiometricUnlockErrorKind.invalidated,
      'unavailable' || 'notEnrolled' => BiometricUnlockErrorKind.unavailable,
      _ => BiometricUnlockErrorKind.failed,
    };
    return BiometricUnlockException(kind, e.message);
  }
}
