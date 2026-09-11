import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/biometric_unlock.dart';

void main() {
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
        expect(availability.kind.signInLabel, 'Sign in with $label');
      }
    }
    expect(BiometricAvailability.fromPlatform({}).usable, isFalse);
    expect(
      BiometricKind.touchId.changedMessage,
      'Touch ID changed. Enter your passcode.',
    );
  });
}
