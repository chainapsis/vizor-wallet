import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/wallet_balance_cache.dart';
import 'package:zcash_wallet/src/features/home/services/account_balance_breakdown.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  group('AccountBalanceBreakdown', () {
    test('names what the shielded balance leaves out', () {
      final sync = SyncState(accountUuid: 'account-1').withFetchedAccountData(
        balance: _balance(
          orchard: 200,
          ironwood: 40,
          orchardPending: 10,
          saplingLocked: 3,
          orchardLocked: 20,
          ironwoodLocked: 7,
          transparent: 100,
          transparentLocked: 5,
        ),
        syncComplete: true,
      );

      final breakdown = AccountBalanceBreakdown.of(sync, ironwoodOnly: false);

      expect(breakdown.headline, sync.displayShieldedBalance);
      expect(breakdown.headline, BigInt.from(250));
      // Transparent funds a pending spend holds stay in the transparent row.
      expect(breakdown.transparent, BigInt.from(105));
      expect(breakdown.migrating, BigInt.zero);
      expect(breakdown.onHold, BigInt.from(30));
      expect(_sum(breakdown), BigInt.from(385));
      expect(_sum(breakdown), sync.displayTotalBalance);
      expect(breakdown.hasMore, isTrue);
    });

    test('counts migrating Orchard once while Home shows Ironwood only', () {
      final sync = SyncState(accountUuid: 'account-1').withFetchedAccountData(
        balance: _balance(
          orchard: 200,
          ironwood: 40,
          ironwoodPending: 2,
          orchardLocked: 20,
          ironwoodLocked: 7,
        ),
        syncComplete: true,
      );

      final breakdown = AccountBalanceBreakdown.of(sync, ironwoodOnly: true);

      expect(breakdown.headline, BigInt.from(42));
      // Orchard holdings include the notes the migration locked.
      expect(breakdown.migrating, sync.displayOrchardHoldingsBalance);
      expect(breakdown.migrating, BigInt.from(220));
      expect(breakdown.onHold, BigInt.from(7));
      expect(_sum(breakdown), sync.displayTotalBalance);
    });

    test('leaves out transparent funds whose amount is not current', () {
      final sync = SyncState(accountUuid: 'account-1').withFetchedAccountData(
        balance: _balance(
          orchard: 200,
          transparentAuthority: rust_sync.TransparentBalanceAuthority.lastKnown,
          transparentLastKnown: 100,
        ),
        syncComplete: true,
      );

      final breakdown = AccountBalanceBreakdown.of(sync, ironwoodOnly: false);

      expect(breakdown.transparent, BigInt.zero);
      expect(breakdown.hasMore, isFalse);
      expect(_sum(breakdown), breakdown.headline);
    });

    test('a cached transparent amount is not counted as funds on hold', () {
      // The cache keeps the saved total while it demotes the transparent
      // amount to last known; the parts are read on their own, so that
      // difference never shows up as held funds.
      final sync = SyncState(accountUuid: 'account-1').withCachedBalance(
        CachedWalletBalance(
          _balance(orchard: 200, transparent: 100, orchardLocked: 20),
          DateTime(2026, 11, 20),
        ),
      );

      final breakdown = AccountBalanceBreakdown.of(sync, ironwoodOnly: false);

      expect(breakdown.transparent, BigInt.zero);
      expect(breakdown.onHold, BigInt.from(20));
      expect(_sum(breakdown), BigInt.from(220));
    });
  });

  group('displayShieldedLockedBalance', () {
    test('follows the snapshot rules of the other display balances', () {
      final completed = SyncState(accountUuid: 'account-1').withCachedBalance(
        CachedWalletBalance(
          _balance(orchard: 200, saplingLocked: 1, orchardLocked: 20),
          DateTime(2026, 11, 20),
        ),
      );
      expect(completed.displayShieldedLockedBalance, BigInt.from(21));

      // A read during the catch-up leaves the snapshot in place.
      final midScan = completed.withFetchedAccountData(
        balance: _balance(orchard: 150, ironwoodLocked: 70),
        syncComplete: false,
      );
      expect(midScan.displayShieldedLockedBalance, BigInt.from(21));
      expect(midScan.displayShieldedBalance, completed.displayShieldedBalance);

      // A completion without a balance keeps it too.
      final unread = midScan.withFetchedAccountData(syncComplete: true);
      expect(unread.displayShieldedLockedBalance, BigInt.from(21));

      final released = midScan.withFetchedAccountData(
        balance: _balance(orchard: 150, ironwoodLocked: 70),
        syncComplete: true,
      );
      expect(released.displayShieldedLockedBalance, BigInt.from(70));
      expect(released.displayShieldedBalance, BigInt.from(150));
    });

    test('is dropped with the rest of an account\'s balance', () {
      final sync = SyncState(accountUuid: 'account-1').withFetchedAccountData(
        balance: _balance(orchard: 200, orchardLocked: 20),
        syncComplete: true,
      );

      expect(
        sync.scopedToAccount('account-2').displayShieldedLockedBalance,
        BigInt.zero,
      );
      expect(
        sync.copyWith(isSyncing: true).displayShieldedLockedBalance,
        BigInt.from(20),
      );
    });
  });
}

/// Everything the breakdown accounts for; equals the wallet total once a
/// balance is read.
BigInt _sum(AccountBalanceBreakdown breakdown) =>
    breakdown.headline +
    breakdown.transparent +
    breakdown.migrating +
    breakdown.onHold;

rust_sync.WalletBalance _balance({
  int orchard = 0,
  int ironwood = 0,
  int orchardPending = 0,
  int ironwoodPending = 0,
  int saplingLocked = 0,
  int orchardLocked = 0,
  int ironwoodLocked = 0,
  int transparent = 0,
  int transparentLocked = 0,
  rust_sync.TransparentBalanceAuthority transparentAuthority =
      rust_sync.TransparentBalanceAuthority.current,
  int? transparentLastKnown,
}) {
  final locked = saplingLocked + orchardLocked + ironwoodLocked;
  return rust_sync.WalletBalance(
    availability: rust_sync.WalletBalanceAvailability.available,
    transparentAuthority: transparentAuthority,
    transparentLastKnown: transparentLastKnown == null
        ? null
        : BigInt.from(transparentLastKnown),
    transparentPrivate: false,
    transparent: BigInt.from(transparent),
    sapling: BigInt.zero,
    orchard: BigInt.from(orchard),
    ironwood: BigInt.from(ironwood),
    transparentLocked: BigInt.from(transparentLocked),
    saplingLocked: BigInt.from(saplingLocked),
    orchardLocked: BigInt.from(orchardLocked),
    ironwoodLocked: BigInt.from(ironwoodLocked),
    transparentPending: BigInt.zero,
    saplingPending: BigInt.zero,
    orchardPending: BigInt.from(orchardPending),
    ironwoodPending: BigInt.from(ironwoodPending),
    changePendingConfirmation: BigInt.zero,
    pendingSpendable: const [],
    pendingSpendableTipHeight: 0,
    valuePendingSpendability: BigInt.zero,
    uneconomicValue: BigInt.zero,
    spendable: BigInt.from(orchard + ironwood),
    locked: BigInt.from(locked + transparentLocked),
    total: BigInt.from(
      orchard +
          ironwood +
          orchardPending +
          ironwoodPending +
          locked +
          transparent +
          transparentLocked,
    ),
  );
}
