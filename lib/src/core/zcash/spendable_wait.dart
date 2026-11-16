import 'dart:math' as math;

import '../../rust/api/sync.dart' as rust_sync;
import '../l10n/l10n.dart';
import 'block_spacing.dart';

/// Confirmations before the wallet spends its own change, and before it
/// spends funds received from others. Mirrors `TRUSTED_CONFIRMATIONS` and
/// `UNTRUSTED_CONFIRMATIONS` in `rust/src/wallet/mod.rs`; display only.
const kChangeSpendableConfirmations = 3;
const kReceivedSpendableConfirmations = 6;

/// Held back for the fee of an amount whose fee is not known yet: the
/// two-action minimum before NU7, the larger of the two eras. Display only;
/// an amount this close to the whole balance is reported as a shortfall
/// rather than promised and then refused.
final kSpendableWaitFeeReserve = BigInt.from(10000);

/// A wait until funds can be spent, as a range of minutes.
class AvailableIn implements Comparable<AvailableIn> {
  const AvailableIn.underMinute() : minMinutes = 0, maxMinutes = 1;
  const AvailableIn.minutes(this.minMinutes, this.maxMinutes);

  /// A range around [seconds], the target time of the blocks still needed.
  factory AvailableIn.fromSeconds(int seconds) {
    final minutes = seconds ~/ Duration.secondsPerMinute;
    if (minutes == 0) return const AvailableIn.underMinute();
    return AvailableIn.minutes(math.max(1, minutes - 1), minutes + 1);
  }

  final int minMinutes;
  final int maxMinutes;

  bool get isUnderMinute => minMinutes == 0;

  @override
  int compareTo(AvailableIn other) => maxMinutes != other.maxMinutes
      ? maxMinutes.compareTo(other.maxMinutes)
      : minMinutes.compareTo(other.minMinutes);

  @override
  bool operator ==(Object other) =>
      other is AvailableIn &&
      other.minMinutes == minMinutes &&
      other.maxMinutes == maxMinutes;

  @override
  int get hashCode => Object.hash(minMinutes, maxMinutes);

  @override
  String toString() => 'AvailableIn($minMinutes–$maxMinutes min)';
}

/// "Available in 1–3 min".
String availableInLabel(AppLocalizations l10n, AvailableIn wait) =>
    wait.isUnderMinute
    ? l10n.commonAvailableInUnderMinute
    : l10n.commonAvailableInMinutes(
        wait.minMinutes.toString(),
        wait.maxMinutes.toString(),
      );

/// Blocks still needed before an output mined at [minedHeight] (0 when
/// unmined) can be spent, or null while the tip is unknown.
///
/// An output needing `n` confirmations is spendable once the tip is `n - 1`
/// blocks above the block that mined it.
int? blocksUntilSpendable({
  required int minedHeight,
  required int tipHeight,
  required int requiredConfirmations,
}) {
  if (tipHeight <= 0) return null;
  if (minedHeight <= 0 || minedHeight > tipHeight) {
    return requiredConfirmations;
  }
  final confirmations = tipHeight - minedHeight + 1;
  return math.max(0, requiredConfirmations - confirmations);
}

/// Blocks an output still waits, or null when it explains no wait.
///
/// While the wallet is [catchingUp] with a block it has not scanned, an
/// output that block just completed still counts, as a wait of no blocks:
/// its value stays pending until the scan lands, moments later.
int? _waitingBlocks({
  required int minedHeight,
  required int tipHeight,
  required int requiredConfirmations,
  required bool catchingUp,
}) {
  final blocks = blocksUntilSpendable(
    minedHeight: minedHeight,
    tipHeight: tipHeight,
    requiredConfirmations: requiredConfirmations,
  );
  if (blocks == null) return null;
  if (blocks > 0) return blocks;
  final justCompleted =
      catchingUp && tipHeight - minedHeight + 1 == requiredConfirmations;
  return justCompleted ? 0 : null;
}

AvailableIn _waitForBlocks(int blocks, int tipHeight, BlockSpacing spacing) =>
    AvailableIn.fromSeconds(
      spacing.secondsBetween(tipHeight, tipHeight + blocks),
    );

/// Shielded funds the account holds but cannot spend yet, split by cause.
///
/// A cause carries a wait only when a recent transaction explains it; without
/// one the wait is null and no surface states a time.
class SpendableWait {
  const SpendableWait({
    required this.availableNow,
    required this.changeWaiting,
    required this.receivedWaiting,
    this.changeWait,
    this.receivedWait,
  });

  final BigInt availableNow;

  /// Change from the account's own payments, short of its confirmations.
  final BigInt changeWaiting;

  /// Funds received from others, short of their confirmations.
  final BigInt receivedWaiting;
  final AvailableIn? changeWait;
  final AvailableIn? receivedWait;

  BigInt get waiting => changeWaiting + receivedWaiting;
  BigInt get total => availableNow + waiting;

  /// Whether every waiting amount has a stated wait.
  bool get hasWait =>
      waiting > BigInt.zero &&
      (changeWaiting == BigInt.zero || changeWait != null) &&
      (receivedWaiting == BigInt.zero || receivedWait != null);

  /// When all of [waiting] is spendable.
  AvailableIn? get wait {
    if (!hasWait) return null;
    final waits = [
      if (changeWaiting > BigInt.zero) changeWait!,
      if (receivedWaiting > BigInt.zero) receivedWait!,
    ]..sort();
    return waits.last;
  }

  /// The earliest wait after which [amount] fits the spendable balance, or
  /// null when it fits now, never fits, or no wait can be stated.
  ///
  /// Pass [includesFee] false for an amount whose fee is still unknown;
  /// [kSpendableWaitFeeReserve] is then held back for it.
  AvailableIn? waitFor(BigInt amount, {bool includesFee = true}) {
    final needed = includesFee ? amount : amount + kSpendableWaitFeeReserve;
    if (!hasWait || needed <= availableNow || needed > total) return null;
    final buckets = [
      if (changeWaiting > BigInt.zero) (changeWait!, changeWaiting),
      if (receivedWaiting > BigInt.zero) (receivedWait!, receivedWaiting),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    var covered = availableNow;
    for (final (wait, value) in buckets) {
      covered += value;
      if (needed <= covered) return wait;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is SpendableWait &&
      other.availableNow == availableNow &&
      other.changeWaiting == changeWaiting &&
      other.receivedWaiting == receivedWaiting &&
      other.changeWait == changeWait &&
      other.receivedWait == receivedWait;

  @override
  int get hashCode => Object.hash(
    availableNow,
    changeWaiting,
    receivedWaiting,
    changeWait,
    receivedWait,
  );
}

/// Splits the account's pending shielded balance into change and received
/// funds, with a wait for each from [transactions].
///
/// The wallet reports the two causes summed over every pool, but only a
/// shielded pool ever holds pending change: a transparent output is either
/// spendable or pending value. So [changePending] is all shielded, and the
/// rest of [shieldedPending] is received. Returns null if the sums disagree.
SpendableWait? resolveSpendableWait({
  required BigInt availableNow,
  required BigInt shieldedPending,
  required BigInt transparentPending,
  required BigInt changePending,
  required BigInt valuePending,
  required int tipHeight,
  required BlockSpacing spacing,
  required List<rust_sync.TransactionInfo> transactions,
  bool catchingUp = false,
}) {
  if (shieldedPending == BigInt.zero) {
    return SpendableWait(
      availableNow: availableNow,
      changeWaiting: BigInt.zero,
      receivedWaiting: BigInt.zero,
    );
  }
  if (changePending > shieldedPending ||
      changePending + valuePending != shieldedPending + transparentPending) {
    return null;
  }
  final receivedPending = shieldedPending - changePending;
  int? latestBlocks(bool Function(rust_sync.TransactionInfo) matches, int n) {
    int? latest;
    for (final transaction in transactions) {
      if (transaction.expiredUnmined || !matches(transaction)) continue;
      final blocks = _waitingBlocks(
        minedHeight: transaction.minedHeight.toInt(),
        tipHeight: tipHeight,
        requiredConfirmations: n,
        catchingUp: catchingUp,
      );
      if (blocks == null) continue;
      latest = math.max(latest ?? 0, blocks);
    }
    return latest;
  }

  final changeBlocks = changePending == BigInt.zero
      ? null
      : latestBlocks(_createsChange, kChangeSpendableConfirmations);
  final receivedBlocks = receivedPending == BigInt.zero
      ? null
      : latestBlocks(_isShieldedReceipt, kReceivedSpendableConfirmations);
  return SpendableWait(
    availableNow: availableNow,
    changeWaiting: changePending,
    receivedWaiting: receivedPending,
    changeWait: changeBlocks == null
        ? null
        : _waitForBlocks(changeBlocks, tipHeight, spacing),
    receivedWait: receivedBlocks == null
        ? null
        : _waitForBlocks(receivedBlocks, tipHeight, spacing),
  );
}

bool _createsChange(rust_sync.TransactionInfo transaction) =>
    transaction.txKind == 'sent' || transaction.txKind == 'migration';

bool _isShieldedReceipt(rust_sync.TransactionInfo transaction) =>
    (transaction.txKind == 'received' || transaction.txKind == 'receiving') &&
    !transaction.isTransparent;

/// The chain position waits are measured from, and whether the wallet is
/// still scanning up to it.
typedef SpendableWaitClock = ({
  int tipHeight,
  BlockSpacing spacing,
  bool catchingUp,
});

/// The wait a mined, shielded receipt still has before it can be spent, with
/// its confirmation count; null once spendable or when not a receipt.
({AvailableIn wait, int confirmations})? receivedSpendableWait(
  rust_sync.TransactionInfo transaction,
  SpendableWaitClock clock,
) {
  if (transaction.txKind != 'received' ||
      transaction.isTransparent ||
      transaction.expiredUnmined ||
      transaction.minedHeight <= BigInt.zero) {
    return null;
  }
  final blocks = _waitingBlocks(
    minedHeight: transaction.minedHeight.toInt(),
    tipHeight: clock.tipHeight,
    requiredConfirmations: kReceivedSpendableConfirmations,
    catchingUp: clock.catchingUp,
  );
  if (blocks == null) return null;
  return (
    wait: _waitForBlocks(blocks, clock.tipHeight, clock.spacing),
    confirmations: kReceivedSpendableConfirmations - blocks,
  );
}
