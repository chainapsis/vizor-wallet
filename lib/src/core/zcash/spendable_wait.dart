import 'dart:math' as math;

import 'package:flutter/foundation.dart';

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
    List<SpendableArrival>? arrivals,
  }) : assert(changeWaiting > BigInt.zero == (changeWait != null)),
       assert(receivedWaiting > BigInt.zero == (receivedWait != null)),
       arrivals =
           arrivals ??
           [
             if (changeWait != null) (wait: changeWait, value: changeWaiting),
             if (receivedWait != null)
               (wait: receivedWait, value: receivedWaiting),
           ] {
    assert(
      this.arrivals.fold(BigInt.zero, (sum, a) => sum + a.value) == waiting,
    );
  }

  final BigInt availableNow;

  /// Change from the account's own payments, short of its confirmations.
  final BigInt changeWaiting;

  /// Funds received from others, short of their confirmations.
  final BigInt receivedWaiting;

  /// When all of [changeWaiting] is spendable.
  final AvailableIn? changeWait;

  /// When all of [receivedWaiting] is spendable.
  final AvailableIn? receivedWait;

  /// Each waiting amount with its own wait: transactions at different depths
  /// arrive at different times. Defaults to one arrival per cause.
  final List<SpendableArrival> arrivals;

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
    final ordered = [...arrivals]..sort((a, b) => a.wait.compareTo(b.wait));
    var covered = availableNow;
    for (final (:wait, :value) in ordered) {
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
      other.receivedWait == receivedWait &&
      listEquals(other.arrivals, arrivals);

  @override
  int get hashCode => Object.hash(
    availableNow,
    changeWaiting,
    receivedWaiting,
    changeWait,
    receivedWait,
    Object.hashAll(arrivals),
  );
}

/// An amount that becomes spendable after [wait].
typedef SpendableArrival = ({AvailableIn wait, BigInt value});

/// The funds the wallet listed as waiting only on confirmations in one
/// balance read, with the chain tip that read counted from.
class PendingSpendable {
  const PendingSpendable({required this.tipHeight, required this.entries});

  PendingSpendable.of(rust_sync.WalletBalance balance)
    : tipHeight = balance.pendingSpendableTipHeight,
      entries = balance.pendingSpendable;

  static const none = PendingSpendable(tipHeight: 0, entries: []);

  final int tipHeight;
  final List<rust_sync.PendingSpendableEntry> entries;

  /// Each entry as it stands once the wallet has scanned to [scannedHeight]:
  /// a block scanned past the read's tip is one fewer to wait and one more
  /// confirmation. A block the chain has but the wallet has not scanned does
  /// not count, since the funds cannot be spent before it is. An unmined
  /// entry stays as read, since no block counts toward it until one mines it.
  Iterable<
    ({rust_sync.PendingSpendableEntry entry, int blocks, int confirmations})
  >
  at(int scannedHeight) sync* {
    final elapsed = math.max(0, scannedHeight - tipHeight);
    for (final entry in entries) {
      final passed = entry.confirmations == 0
          ? 0
          : math.min(elapsed, entry.blocksUntilSpendable);
      yield (
        entry: entry,
        blocks: entry.blocksUntilSpendable - passed,
        confirmations: entry.confirmations + passed,
      );
    }
  }
}

/// The wallet's waiting funds as [SpendableWait] once it has scanned to
/// [scannedHeight].
///
/// [availableNow] is the spendable balance of the read [pending] came with.
/// Funds whose blocks have all passed since are still listed, as available
/// in under a minute, until the next read moves them to the balance.
SpendableWait spendableWaitOf({
  required BigInt availableNow,
  required PendingSpendable pending,
  required int scannedHeight,
  required BlockSpacing spacing,
}) {
  final height = math.max(scannedHeight, pending.tipHeight);
  var changeWaiting = BigInt.zero;
  var receivedWaiting = BigInt.zero;
  var changeBlocks = 0;
  var receivedBlocks = 0;
  final arrivals = <SpendableArrival>[];
  for (final (:entry, :blocks, confirmations: _) in pending.at(scannedHeight)) {
    arrivals.add((
      wait: _waitForBlocks(blocks, height, spacing),
      value: entry.value,
    ));
    if (entry.isChange) {
      changeWaiting += entry.value;
      changeBlocks = math.max(changeBlocks, blocks);
    } else {
      receivedWaiting += entry.value;
      receivedBlocks = math.max(receivedBlocks, blocks);
    }
  }
  return SpendableWait(
    availableNow: availableNow,
    changeWaiting: changeWaiting,
    receivedWaiting: receivedWaiting,
    changeWait: changeWaiting == BigInt.zero
        ? null
        : _waitForBlocks(changeBlocks, height, spacing),
    receivedWait: receivedWaiting == BigInt.zero
        ? null
        : _waitForBlocks(receivedBlocks, height, spacing),
    arrivals: arrivals,
  );
}

AvailableIn _waitForBlocks(int blocks, int height, BlockSpacing spacing) =>
    AvailableIn.fromSeconds(spacing.secondsBetween(height, height + blocks));

/// A mined receipt the account cannot spend yet: when it can, and how far
/// along its confirmations are.
typedef ReceivedSpendableWait = ({
  AvailableIn wait,
  int confirmations,
  int requiredConfirmations,
});

/// The waiting receipts in [pending] once the wallet has scanned to
/// [scannedHeight], by [rust_sync.TransactionInfo.txidHex].
///
/// A receipt still in the mempool is left to its pending row.
Map<String, ReceivedSpendableWait> receivedSpendableWaits({
  required PendingSpendable pending,
  required int scannedHeight,
  required BlockSpacing spacing,
}) => {
  for (final (:entry, :blocks, :confirmations) in pending.at(scannedHeight))
    if (!entry.isChange && confirmations > 0)
      entry.txidHex: (
        wait: _waitForBlocks(
          blocks,
          math.max(scannedHeight, pending.tipHeight),
          spacing,
        ),
        confirmations: confirmations,
        requiredConfirmations: confirmations + blocks,
      ),
};

/// [transaction]'s entry in [waits] when it is a receipt.
ReceivedSpendableWait? receivedSpendableWaitFor(
  rust_sync.TransactionInfo transaction,
  Map<String, ReceivedSpendableWait> waits,
) => transaction.txKind == 'received' ? waits[transaction.txidHex] : null;
