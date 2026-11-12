import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/l10n/l10n.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/enhance_pir_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/one_time_ivk.dart' show SwapAccountReadiness;
import 'swap_zec_staging_address_service.dart';

/// Why the composer holds a quote for the swap's one-time ZEC address. The
/// wallet would refuse it, so the button waits instead of showing an error.
enum SwapAddressWait {
  /// The wallet is still checking the payout address's history, as it does
  /// after NEAR swap privacy is turned on.
  preparing,

  /// A refund address needs wallet sync within [kSwapRefundScanLag] blocks of
  /// the chain tip.
  sync,

  /// The payout address's history check needs a private query server, so the
  /// button opens the server picker instead of waiting.
  server,
}

/// The composer button's label while a quote waits for [wait].
String swapAddressWaitLabel(AppLocalizations l10n, SwapAddressWait wait) =>
    switch (wait) {
      SwapAddressWait.preparing => l10n.swapOneTimeAddressPreparing,
      SwapAddressWait.sync => l10n.swapAddressWaitSync,
      SwapAddressWait.server => l10n.swapAddressWaitServer,
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
  if (!ref.watch(swapAddressHistoryPendingProvider)) return null;
  return ref.watch(swapRecoveryNeedsServerProvider)
      ? SwapAddressWait.server
      : SwapAddressWait.preparing;
});

/// How far the wallet's fully scanned height may trail the chain tip before
/// it refuses a new refund address, matching the wallet library's refund rule.
const kSwapRefundScanLag = 1;

/// Whether the wallet refuses a refund address until it syncs: its fully
/// scanned height, the block before the earliest unscanned range, is more
/// than [kSwapRefundScanLag] blocks below the chain tip. An unknown tip never
/// waits.
bool swapRefundAddressNeedsSync({
  required int chainTipHeight,
  required int scannedHeight,
  required int? pendingScanStartHeight,
}) {
  if (chainTipHeight <= 0) return false;
  final fullyScanned = pendingScanStartHeight == null
      ? scannedHeight
      : pendingScanStartHeight - 1;
  return chainTipHeight - fullyScanned > kSwapRefundScanLag;
}

/// Reads an account's private swap readiness (see
/// [SyncNotifier.swapAccountReadiness]). Overridable in tests.
final swapAccountReadinessReaderProvider =
    Provider<Future<SwapAccountReadiness?> Function(String accountUuid)>(
      (ref) => ref.read(syncProvider.notifier).swapAccountReadiness,
    );

/// Whether the active account's next one-time payout address is still having
/// its history checked, so a quote would be refused.
///
/// True while the account's restored seed is still being walked (see
/// [SwapAccountReadiness.seedWalk]), unless the last recovery round failed: a
/// press then shows why instead of waiting without end. Also true after a
/// quote for the account was refused for it, until the next round, filter
/// step or completed sync, any of which can make the address usable.
/// Another account's recovery never holds it. Settings shows the wallet-wide
/// lookup instead.
final swapAddressHistoryPendingProvider =
    NotifierProvider<SwapAddressHistoryPending, bool>(
      SwapAddressHistoryPending.new,
    );

/// See [swapAddressHistoryPendingProvider]. Starts over for each active
/// account, and reads the account's readiness again after every recovery
/// round, filter step, completed sync and NEAR swap privacy change. A read
/// the wallet refuses keeps the last answer.
class SwapAddressHistoryPending extends Notifier<bool> {
  String? _account;
  var _seedWalk = false;
  var _refused = false;
  var _reads = 0;

  @override
  bool build() {
    _account = ref.watch(
      accountProvider.select((value) => value.value?.activeAccountUuid),
    );
    _seedWalk = false;
    _refused = false;
    _reads++;
    void recheck(_, _) {
      _refused = false;
      _publish();
      unawaited(_read());
    }

    ref.listen(swapRecoveryRoundsProvider, recheck);
    ref.listen(swapFilterStepsProvider, recheck);
    ref.listen(
      syncProvider.select((sync) => sync.value?.lastSyncCompletedAt),
      recheck,
    );
    ref.listen(nearSwapPrivacyProvider, (_, _) => unawaited(_read()));
    ref.listen(swapRecoveryRoundFailedProvider, (_, _) => _publish());
    unawaited(Future<void>.microtask(_read));
    return _pending();
  }

  /// Records that a quote for `accountUuid` was refused because the address's
  /// history is unchecked even after a recovery round. A refusal for an
  /// account that is no longer active is ignored.
  void quoteRefused(String accountUuid) {
    if (accountUuid != _account) return;
    _refused = true;
    _publish();
  }

  /// Reads whether the active account's seed walk is unfinished.
  Future<void> _read() async {
    final account = _account;
    final read = ++_reads;
    if (account == null) return;
    try {
      final readiness = await ref.read(swapAccountReadinessReaderProvider)(
        account,
      );
      if (!ref.mounted || read != _reads) return;
      _seedWalk = readiness?.seedWalk ?? false;
      _publish();
    } catch (error) {
      log('Swap account readiness not read: $error');
    }
  }

  bool _pending() =>
      _refused || (_seedWalk && !ref.read(swapRecoveryRoundFailedProvider));

  void _publish() {
    if (ref.mounted) state = _pending();
  }
}
