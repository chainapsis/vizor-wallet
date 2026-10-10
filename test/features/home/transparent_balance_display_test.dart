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
      expect(display.hint, isNull);
    });

    test('a stopped recovery says why for each reason', () {
      final hints = <String>{};
      for (final reason in rust_sync.TransparentStopReason.values) {
        final display = TransparentBalanceDisplay.of(
          SyncState(
            transparentAuthority: rust_sync.TransparentBalanceAuthority.stopped,
            transparentStop: reason,
          ),
        );
        expect(display.text(_format), 'Recovery stopped', reason: '$reason');
        expect(display.amount, isNull, reason: '$reason');
        expect(display.visible, isTrue, reason: '$reason');
        final hint = display.hint;
        expect(hint, isNotNull, reason: '$reason');
        hints.add(hint!);
      }
      expect(hints, hasLength(rust_sync.TransparentStopReason.values.length));
    });

    test('a build that cannot recover says to turn off Private queries', () {
      final display = TransparentBalanceDisplay.of(
        SyncState(
          transparentAuthority: rust_sync.TransparentBalanceAuthority.stopped,
          transparentStop: rust_sync.TransparentStopReason.notSelected,
        ),
      );
      expect(
        display.hint,
        'Private transparent recovery is not selected. Turn off Private '
        'queries to look up transparent funds publicly. If it is already '
        'off, choose Finish turning off in Settings.',
      );
      expect(display.hint, isNot(contains('until private recovery')));
      expect(
        display.hint,
        contains(
          'If it is already off, choose Finish turning off in Settings.',
        ),
      );
    });

    test('conflicting records say turning off discards them', () {
      for (final reason in [
        rust_sync.TransparentStopReason.quarantined,
        rust_sync.TransparentStopReason.legacyDiscrepancy,
      ]) {
        final hint = TransparentBalanceDisplay.of(
          SyncState(
            transparentAuthority: rust_sync.TransparentBalanceAuthority.stopped,
            transparentStop: reason,
          ),
        ).hint;
        expect(
          hint,
          contains(
            'Turning off Private queries discards privately recovered '
            'records and looks up transparent funds publicly.',
          ),
          reason: '$reason',
        );
        expect(hint, isNot(contains('restore public lookups')));
      }
    });

    test('a stopped recovery never reads as a spendable amount', () {
      final display = TransparentBalanceDisplay.of(
        SyncState(
          transparentAuthority: rust_sync.TransparentBalanceAuthority.stopped,
          transparentStop: rust_sync.TransparentStopReason.stalled,
          transparentLastKnownBalance: BigInt.from(9),
          // Nothing is spendable without authority.
          transparentBalance: BigInt.zero,
        ),
      );
      expect(display.text(_format), '9zat (last known, recovery stopped)');
      expect(
        display.authority,
        isNot(rust_sync.TransparentBalanceAuthority.current),
      );
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

    test('a fetched balance carries its stop reason and private policy', () {
      final stopped = SyncState().withFetchedAccountData(
        balance: _balance(
          rust_sync.TransparentBalanceAuthority.stopped,
          lastKnown: BigInt.from(9),
          stop: rust_sync.TransparentStopReason.notSelected,
          private: true,
        ),
        syncComplete: true,
      );
      expect(
        stopped.transparentStop,
        rust_sync.TransparentStopReason.notSelected,
      );
      expect(stopped.transparentPrivate, isTrue);
      // An unrelated update keeps both.
      final updated = stopped.copyWith(percentage: 0.5);
      expect(
        updated.transparentStop,
        rust_sync.TransparentStopReason.notSelected,
      );
      expect(updated.transparentPrivate, isTrue);

      // Restored authority clears the stop reason.
      final current = stopped.withFetchedAccountData(
        balance: _balance(
          rust_sync.TransparentBalanceAuthority.current,
          private: true,
        ),
        syncComplete: true,
      );
      expect(current.transparentStop, isNull);
      expect(current.transparentPrivate, isTrue);
    });

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
    // Vizor's shielding refusal for a private wallet in a build that does not
    // recover it; the Rust status test pins its phrase.
    const notSelectedRefusal =
        'Private transparent recovery is not selected; turn '
        'off private queries to use transparent funds';

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

    test('a build that cannot recover never promises recovery', () {
      expect(isTransparentRecoveryNotSelectedError(notSelectedRefusal), isTrue);
      expect(isTransparentRecoveryIncompleteError(notSelectedRefusal), isFalse);
      expect(isTransparentRecoveryNotSelectedError(shieldingRefusal), isFalse);
      expect(isTransparentRecoveryNotSelectedError(libraryRefusal), isFalse);
      final copy = friendlyShieldBalanceError(Exception(notSelectedRefusal));
      expect(copy, transparentRecoveryNotSelectedMessage);
      expect(copy, contains('Turn off Private queries'));
      expect(
        copy,
        contains(
          'If it is already off, choose Finish turning off in Settings.',
        ),
      );
      expect(copy, isNot(contains('until private recovery completes')));
    });
  });
}

rust_sync.WalletBalance _balance(
  rust_sync.TransparentBalanceAuthority authority, {
  BigInt? lastKnown,
  rust_sync.TransparentStopReason? stop,
  bool private = false,
}) {
  return rust_sync.WalletBalance(
    availability: rust_sync.WalletBalanceAvailability.available,
    transparentAuthority: authority,
    transparentPrivate: private,
    transparentStop: stop,
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
