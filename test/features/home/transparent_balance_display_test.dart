import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/zcash/transparent_ledger_errors.dart';
import 'package:zcash_wallet/src/features/home/services/transparent_balance_display.dart';
import 'package:zcash_wallet/src/features/home/services/transparent_shielding_service.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

String _format(BigInt zatoshi) => '${zatoshi}zat';

void main() {
  group('TransparentBalanceDisplay', () {
    test('shows the current amount, including pending value', () {
      final display = TransparentBalanceDisplay.of(
        SyncState(
          transparentBalance: BigInt.from(5),
          transparentPendingBalance: BigInt.from(2),
        ),
      );
      expect(display.text(_format), '7zat');
      expect(display.visible, isTrue);
    });

    test('hides a current zero balance', () {
      expect(TransparentBalanceDisplay.of(SyncState()).visible, isFalse);
    });

    test('marks a last-known amount and never shows it as spendable', () {
      final display = TransparentBalanceDisplay.of(
        SyncState(
          transparentAuthority: rust_sync.TransparentBalanceAuthority.lastKnown,
          transparentLastKnownBalance: BigInt.from(9),
        ),
      );
      expect(display.text(_format), '9zat (last known)');
      expect(display.visible, isTrue);
    });

    test('shows an unknown balance as unavailable, never zero', () {
      final display = TransparentBalanceDisplay.of(
        SyncState(
          transparentAuthority:
              rust_sync.TransparentBalanceAuthority.unavailable,
        ),
      );
      expect(display.text(_format), 'Unavailable');
      expect(display.amount, isNull);
      expect(display.visible, isTrue);
    });
  });

  group('SyncState transparent authority', () {
    test(
      'a fetched balance replaces the authority and its last-known amount',
      () {
        final lastKnown = SyncState().withFetchedAccountData(
          balance: _balance(
            rust_sync.TransparentBalanceAuthority.lastKnown,
            lastKnown: BigInt.from(9),
          ),
          syncComplete: true,
        );
        expect(
          lastKnown.transparentAuthority,
          rust_sync.TransparentBalanceAuthority.lastKnown,
        );
        expect(lastKnown.transparentLastKnownBalance, BigInt.from(9));

        final current = lastKnown.withFetchedAccountData(
          balance: _balance(rust_sync.TransparentBalanceAuthority.current),
          syncComplete: true,
        );
        expect(
          current.transparentAuthority,
          rust_sync.TransparentBalanceAuthority.current,
        );
        expect(current.transparentLastKnownBalance, isNull);
      },
    );

    test('an unrelated update keeps the authority', () {
      final state = SyncState(
        transparentAuthority: rust_sync.TransparentBalanceAuthority.lastKnown,
        transparentLastKnownBalance: BigInt.from(9),
      ).copyWith(percentage: 0.5);
      expect(
        state.transparentAuthority,
        rust_sync.TransparentBalanceAuthority.lastKnown,
      );
      expect(state.transparentLastKnownBalance, BigInt.from(9));
    });
  });

  group('transparent recovery errors', () {
    // The library's and Vizor's refusals; the Rust guard test pins both.
    const libraryRefusal =
        'Transparent funds are unavailable: private transparent authority '
        'is required but not available';
    const shieldingRefusal =
        'Transparent recovery is incomplete; transparent funds are '
        'unavailable until it completes';

    test('match the recovery-incomplete copy', () {
      expect(isTransparentRecoveryIncompleteError(libraryRefusal), isTrue);
      expect(isTransparentRecoveryIncompleteError(shieldingRefusal), isTrue);
      expect(
        isTransparentRecoveryIncompleteError('insufficient funds'),
        isFalse,
      );
    });

    test('shielding reports recovery, not insufficient funds', () {
      expect(
        friendlyShieldBalanceError(Exception(shieldingRefusal)),
        transparentRecoveryIncompleteMessage,
      );
    });
  });
}

rust_sync.WalletBalance _balance(
  rust_sync.TransparentBalanceAuthority authority, {
  BigInt? lastKnown,
}) {
  return rust_sync.WalletBalance(
    availability: rust_sync.WalletBalanceAvailability.available,
    transparentAuthority: authority,
    transparentLastKnown: lastKnown,
    transparent: BigInt.zero,
    sapling: BigInt.zero,
    orchard: BigInt.zero,
    ironwood: BigInt.zero,
    transparentLocked: BigInt.zero,
    saplingLocked: BigInt.zero,
    orchardLocked: BigInt.zero,
    ironwoodLocked: BigInt.zero,
    transparentPending: BigInt.zero,
    saplingPending: BigInt.zero,
    orchardPending: BigInt.zero,
    ironwoodPending: BigInt.zero,
    changePendingConfirmation: BigInt.zero,
    valuePendingSpendability: BigInt.zero,
    uneconomicValue: BigInt.zero,
    spendable: BigInt.zero,
    locked: BigInt.zero,
    total: BigInt.zero,
  );
}
