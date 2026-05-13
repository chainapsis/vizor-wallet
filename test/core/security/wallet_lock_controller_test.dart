import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/security/wallet_lock_controller.dart';

void main() {
  group('shouldAutoLock', () {
    test('returns false for zero elapsed', () {
      expect(shouldAutoLock(elapsed: Duration.zero), isFalse);
    });

    test('returns false when elapsed is shorter than threshold', () {
      expect(
        shouldAutoLock(
          elapsed: kAutoLockBackgroundTimeout - const Duration(seconds: 1),
        ),
        isFalse,
      );
    });

    test('returns true at exactly the threshold boundary', () {
      expect(shouldAutoLock(elapsed: kAutoLockBackgroundTimeout), isTrue);
    });

    test('returns true when elapsed exceeds threshold', () {
      expect(
        shouldAutoLock(elapsed: kAutoLockBackgroundTimeout * 3),
        isTrue,
      );
    });

    test('respects a custom threshold override', () {
      expect(
        shouldAutoLock(
          elapsed: const Duration(seconds: 30),
          threshold: const Duration(seconds: 15),
        ),
        isTrue,
      );
      expect(
        shouldAutoLock(
          elapsed: const Duration(seconds: 30),
          threshold: const Duration(minutes: 1),
        ),
        isFalse,
      );
    });

    test('default threshold is 10 minutes', () {
      expect(kAutoLockBackgroundTimeout, const Duration(minutes: 10));
    });

    test('returns false when elapsed is negative (backward-time guard)', () {
      expect(
        shouldAutoLock(elapsed: const Duration(seconds: -1)),
        isFalse,
      );
    });
  });
}
