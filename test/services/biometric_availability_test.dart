import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/biometric_unlock.dart';
import '../support/test_l10n.dart';

void main() {
  test('only iOS Face ID requires a manual sensitive-action request', () {
    for (final (platform, kind, allowed) in [
      (TargetPlatform.iOS, BiometricKind.face, false),
      (TargetPlatform.iOS, BiometricKind.touchId, true),
      (TargetPlatform.android, BiometricKind.face, true),
      (TargetPlatform.android, BiometricKind.fingerprint, true),
    ]) {
      expect(
        shouldAutoPromptSensitiveBiometric(kind, platform: platform),
        allowed,
        reason: '$platform / $kind',
      );
    }
  });

  test('native method is preserved independently from readiness', () {
    for (final (native, kind, label) in [
      ('face', BiometricKind.face, 'Face ID'),
      ('touchId', BiometricKind.touchId, 'Touch ID'),
      ('fingerprint', BiometricKind.fingerprint, 'fingerprint'),
      ('unknown', BiometricKind.none, 'biometrics'),
    ]) {
      for (final enrolled in [false, true]) {
        final availability = BiometricAvailability.fromPlatform({
          'supported': true,
          'enrolled': enrolled,
          'kind': native,
        });
        expect(availability.kind, kind);
        expect(availability.usable, enrolled);
        expect(availability.kind.signInLabel(testL10n), 'Sign in with $label');
      }
    }
    expect(BiometricAvailability.fromPlatform({}).usable, isFalse);
    expect(
      BiometricKind.touchId.changedMessage(testL10n),
      'Touch ID changed. Enter your passcode.',
    );
  });
}
