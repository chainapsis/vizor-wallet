import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/swap_past_swaps_check_provider.dart';
import '../../../providers/sync_provider.dart';
import 'swap_zec_staging_address_service.dart';

/// Why the composer holds a quote for the swap's one-time ZEC address. The
/// wallet would refuse it, so the button waits instead of showing an error.
enum SwapAddressWait {
  /// The wallet is still checking the payout address's history, as it does
  /// after NEAR swap privacy is turned on.
  preparing,

  /// A refund address needs wallet sync within 10 blocks of the chain tip.
  sync,
}

/// The composer button's label while a quote waits for [wait].
String swapAddressWaitLabel(SwapAddressWait wait) => switch (wait) {
  SwapAddressWait.preparing => 'Preparing address…',
  SwapAddressWait.sync => 'Waiting for sync…',
};

/// What, if anything, a quote for a swap that sends ZEC ([sendsZec]) or
/// receives it waits for. Only swaps with a one-time ZEC address wait.
final swapAddressWaitProvider = Provider.family<SwapAddressWait?, bool>((
  ref,
  sendsZec,
) {
  if (!ref.watch(swapUsesOneTimeAddressProvider)) return null;
  if (sendsZec) {
    final behind = ref.watch(
      syncProvider.select(
        (sync) => switch (sync.value) {
          final state? => swapRefundAddressNeedsSync(
            chainTipHeight: state.chainTipHeight,
            scannedHeight: state.scannedHeight,
            pendingScanStartHeight: state.pendingScanStartHeight,
          ),
          null => false,
        },
      ),
    );
    return behind ? SwapAddressWait.sync : null;
  }
  return ref.watch(swapAddressHistoryPendingProvider)
      ? SwapAddressWait.preparing
      : null;
});

/// Whether the wallet refuses a refund address until it syncs: its fully
/// scanned height, the block before the earliest unscanned range, is more
/// than 10 blocks below the chain tip. An unknown tip never waits.
bool swapRefundAddressNeedsSync({
  required int chainTipHeight,
  required int scannedHeight,
  required int? pendingScanStartHeight,
}) {
  if (chainTipHeight <= 0) return false;
  final fullyScanned = pendingScanStartHeight == null
      ? scannedHeight
      : pendingScanStartHeight - 1;
  return chainTipHeight - fullyScanned > 10;
}

/// Whether the next one-time payout address is still having its history
/// checked, so a quote would be refused.
///
/// True while the wallet's automatic history lookup is unfinished (see
/// [swapPastSwapsCheckProvider]), unless the last recovery round failed: a
/// press then shows why instead of waiting without end. Also true after a
/// quote was refused for it, until the next round ends. The wallet reports
/// one state for all its accounts, so another account's lookup can hold this
/// one's quote too.
final swapAddressHistoryPendingProvider =
    NotifierProvider<SwapAddressHistoryPending, bool>(
      SwapAddressHistoryPending.new,
    );

/// See [swapAddressHistoryPendingProvider].
class SwapAddressHistoryPending extends Notifier<bool> {
  var _refused = false;

  @override
  bool build() {
    _refused = false;
    ref.listen(swapRecoveryRoundsProvider, (_, _) {
      _refused = false;
      _publish();
    });
    ref.listen(swapPastSwapsCheckProvider, (_, _) => _publish());
    ref.listen(swapRecoveryRoundFailedProvider, (_, _) => _publish());
    return _pending();
  }

  /// Records that a quote was refused because the address's history is
  /// unchecked even after a recovery round.
  void quoteRefused() {
    _refused = true;
    _publish();
  }

  bool _pending() =>
      _refused ||
      (ref.read(swapPastSwapsCheckProvider) &&
          !ref.read(swapRecoveryRoundFailedProvider));

  void _publish() {
    if (ref.mounted) state = _pending();
  }
}
