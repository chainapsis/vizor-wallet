import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/security/wallet_lock_controller.dart';

void main() {
  group('shouldAutoLock', () {
    test('returns false when no hidden timestamp is recorded', () {
      expect(
        shouldAutoLock(
          hiddenAt: null,
          now: DateTime(2026, 1, 1, 12, 0, 0),
        ),
        isFalse,
      );
    });

    test('returns false when hidden duration is shorter than threshold', () {
      final hiddenAt = DateTime(2026, 1, 1, 12, 0, 0);
      final now = hiddenAt.add(kAutoLockBackgroundTimeout - const Duration(seconds: 1));
      expect(shouldAutoLock(hiddenAt: hiddenAt, now: now), isFalse);
    });

    test('returns true at exactly the threshold boundary', () {
      final hiddenAt = DateTime(2026, 1, 1, 12, 0, 0);
      final now = hiddenAt.add(kAutoLockBackgroundTimeout);
      expect(shouldAutoLock(hiddenAt: hiddenAt, now: now), isTrue);
    });

    test('returns true when hidden duration exceeds threshold', () {
      final hiddenAt = DateTime(2026, 1, 1, 12, 0, 0);
      final now = hiddenAt.add(kAutoLockBackgroundTimeout * 3);
      expect(shouldAutoLock(hiddenAt: hiddenAt, now: now), isTrue);
    });

    test('respects a custom threshold override', () {
      final hiddenAt = DateTime(2026, 1, 1, 12, 0, 0);
      final now = hiddenAt.add(const Duration(seconds: 30));
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
  });
}
