import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/security/wallet_lock_controller.dart';

void main() {
  group('shouldAutoLock', () {
    test('returns false when no hidden timestamp is recorded', () {
      expect(
        shouldAutoLock(hiddenAt: null, now: const Duration(hours: 1)),
        isFalse,
      );
    });

    test('returns false when hidden duration is shorter than threshold', () {
      const hiddenAt = Duration(minutes: 5);
      final now = hiddenAt + kAutoLockBackgroundTimeout - const Duration(seconds: 1);
      expect(shouldAutoLock(hiddenAt: hiddenAt, now: now), isFalse);
    });

    test('returns true at exactly the threshold boundary', () {
      const hiddenAt = Duration(minutes: 5);
      final now = hiddenAt + kAutoLockBackgroundTimeout;
      expect(shouldAutoLock(hiddenAt: hiddenAt, now: now), isTrue);
    });

    test('returns true when hidden duration exceeds threshold', () {
      const hiddenAt = Duration(minutes: 5);
      final now = hiddenAt + kAutoLockBackgroundTimeout * 3;
      expect(shouldAutoLock(hiddenAt: hiddenAt, now: now), isTrue);
    });

    test('respects a custom threshold override', () {
      const hiddenAt = Duration(minutes: 5);
      final now = hiddenAt + const Duration(seconds: 30);
      expect(
        shouldAutoLock(
          hiddenAt: hiddenAt,
          now: now,
          threshold: const Duration(seconds: 15),
        ),
        isTrue,
      );
      expect(
        shouldAutoLock(
          hiddenAt: hiddenAt,
          now: now,
          threshold: const Duration(minutes: 1),
        ),
        isFalse,
      );
    });

    test('default threshold is 10 minutes', () {
      expect(kAutoLockBackgroundTimeout, const Duration(minutes: 10));
    });

    test('does not lock when monotonic time appears to go backward', () {
      const hiddenAt = Duration(minutes: 30);
      const now = Duration(minutes: 5);
      expect(shouldAutoLock(hiddenAt: hiddenAt, now: now), isFalse);
    });
  });
}
