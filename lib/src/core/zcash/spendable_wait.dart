import 'dart:math' as math;

import '../../rust/api/sync.dart' as rust_sync;
import '../l10n/l10n.dart';
import 'block_spacing.dart';

/// Held back for the fee of an amount whose fee is not known yet: the
/// two-action minimum before NU7, the larger of the two eras. Display only.
///
/// The fee cannot be quoted for funds that are not spendable yet, so this is
/// a floor, not the fee: a payment needing more actions than it covers, for
/// an amount within that difference of the whole balance, is still told a
/// wait and then a shortfall.
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

/// Shielded funds the account holds that wait only on confirmations, split
/// by cause. A cause has a wait exactly when it has an amount.
class SpendableWait {
  SpendableWait({
    required this.availableNow,
    required this.changeWaiting,
    required this.receivedWaiting,
    this.changeWait,
    this.receivedWait,
  }) : assert(changeWaiting > BigInt.zero == (changeWait != null)),
       assert(receivedWaiting > BigInt.zero == (receivedWait != null));

  final BigInt availableNow;

  /// Change from the account's own payments, short of its confirmations.
  final BigInt changeWaiting;

  /// Funds received from others, short of their confirmations.
  final BigInt receivedWaiting;
  final AvailableIn? changeWait;
  final AvailableIn? receivedWait;

  BigInt get waiting => changeWaiting + receivedWaiting;
  BigInt get total => availableNow + waiting;

  bool get hasWait => waiting > BigInt.zero;

  /// When all of [waiting] is spendable.
  AvailableIn? get wait {
    final waits = [?changeWait, ?receivedWait]..sort();
    return waits.isEmpty ? null : waits.last;
  }

  /// The earliest wait after which [amount] fits the spendable balance, or
  /// null when it fits now or never fits.
  ///
  /// Pass [includesFee] false for an amount whose fee is still unknown;
  /// [kSpendableWaitFeeReserve] is then held back for it.
  AvailableIn? waitFor(BigInt amount, {bool includesFee = true}) {
    final needed = includesFee ? amount : amount + kSpendableWaitFeeReserve;
    if (needed <= availableNow || needed > total) return null;
    final buckets = [
      if (changeWait != null) (changeWait!, changeWaiting),
      if (receivedWait != null) (receivedWait!, receivedWaiting),
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

/// The wallet's waiting funds as [SpendableWait].
///
/// [entries] come with the balance [availableNow] was read from and count
/// blocks from the chain tip of that read; [tipHeight] only picks the block
/// spacing.
SpendableWait spendableWaitOf({
  required BigInt availableNow,
  required Iterable<rust_sync.PendingSpendableEntry> entries,
  required int tipHeight,
  required BlockSpacing spacing,
}) {
  var changeWaiting = BigInt.zero;
  var receivedWaiting = BigInt.zero;
  var changeBlocks = 0;
  var receivedBlocks = 0;
  for (final entry in entries) {
    if (entry.isChange) {
      changeWaiting += entry.value;
      changeBlocks = math.max(changeBlocks, entry.blocksUntilSpendable);
    } else {
      receivedWaiting += entry.value;
      receivedBlocks = math.max(receivedBlocks, entry.blocksUntilSpendable);
    }
  }
  return SpendableWait(
    availableNow: availableNow,
    changeWaiting: changeWaiting,
    receivedWaiting: receivedWaiting,
    changeWait: changeWaiting == BigInt.zero
        ? null
        : _waitForBlocks(changeBlocks, tipHeight, spacing),
    receivedWait: receivedWaiting == BigInt.zero
        ? null
        : _waitForBlocks(receivedBlocks, tipHeight, spacing),
  );
}

AvailableIn _waitForBlocks(int blocks, int tipHeight, BlockSpacing spacing) =>
    AvailableIn.fromSeconds(
      spacing.secondsBetween(tipHeight, tipHeight + blocks),
    );

/// A mined receipt the account cannot spend yet: when it can, and how far
/// along its confirmations are.
typedef ReceivedSpendableWait = ({
  AvailableIn wait,
  int confirmations,
  int requiredConfirmations,
});

/// The waiting receipts among [entries], by [rust_sync.TransactionInfo.txidHex].
///
/// A receipt still in the mempool is left to its pending row.
Map<String, ReceivedSpendableWait> receivedSpendableWaits({
  required Iterable<rust_sync.PendingSpendableEntry> entries,
  required int tipHeight,
  required BlockSpacing spacing,
}) => {
  for (final entry in entries)
    if (!entry.isChange && entry.confirmations > 0)
      entry.txidHex: (
        wait: _waitForBlocks(entry.blocksUntilSpendable, tipHeight, spacing),
        confirmations: entry.confirmations,
        requiredConfirmations: entry.confirmations + entry.blocksUntilSpendable,
      ),
};

/// [transaction]'s entry in [waits] when it is a receipt.
ReceivedSpendableWait? receivedSpendableWaitFor(
  rust_sync.TransactionInfo transaction,
  Map<String, ReceivedSpendableWait> waits,
) => transaction.txKind == 'received' ? waits[transaction.txidHex] : null;
