import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/navigation/payment_uri_drain_policy.dart';
import '../features/send/models/send_prefill_args.dart';

/// Holds a ZIP-321 payment-URI prefill that has been parsed from a `zcash:`
/// link but not yet delivered.
///
/// This exists so the prefill survives the lock screen. A `zcash:` link opened
/// while the wallet is locked routes to `/unlock` and parks the prefill here;
/// the unlock flow then claims it (via [PaymentUriPrefillNotifier.takeIfFresh])
/// and presents it as a card over the wallet it just unlocked, so the payment
/// intent is not lost. When the wallet is already unlocked the app-level
/// `_IncomingLinkHost` drains it directly.
///
/// **Deliberately not the same store as `paymentLinkIntakeProvider`**, even
/// though both hold links that arrived on the same native channel. A payment
/// request is an *instruction to spend this wallet's money*: one at a time
/// (latest wins, no queue), stale after [kPaymentUriParkTtl] because paying a
/// forgotten request later is worse than losing it, and dropped by a wallet
/// reset because the wallet it was going to pay from no longer exists. A Gift
/// Card is a bearer claim on funds held elsewhere, so it queues, never
/// expires, and outlives a reset. Merging the two would have to pick one set
/// of those answers and would be wrong for the other product.
class PaymentUriPrefillNotifier extends Notifier<SendPrefillArgs?> {
  /// A parked prefill older than this is treated as stale and dropped on the
  /// next unlock. Without it, a link opened then left parked (the user never
  /// unlocks) would fire as a payment on a much later, unrelated unlock.
  static const parkTtl = kPaymentUriParkTtl;

  DateTime? _parkedAtUtc;

  @override
  SendPrefillArgs? build() => null;

  /// How long the current prefill has been parked, or null when nothing is
  /// parked. The drain policy uses this to drop a prefill that outlived
  /// [parkTtl] before it can navigate anywhere.
  Duration? get parkedFor {
    final parkedAt = _parkedAtUtc;
    if (state == null || parkedAt == null) return null;
    return DateTime.now().toUtc().difference(parkedAt);
  }

  /// Parks [prefill], replacing whatever was parked before — latest wins,
  /// there is no queue.
  ///
  /// Returns true when it displaced a prefill that was still parked, so the
  /// caller can tell the user the earlier link was dropped. A duplicate
  /// delivery of the same link counts as a replacement too; the caller does
  /// not compare fingerprints.
  bool set(SendPrefillArgs prefill) {
    final replacedParkedPrefill = state != null;
    _parkedAtUtc = DateTime.now().toUtc();
    state = prefill;
    return replacedParkedPrefill;
  }

  void clear() {
    _parkedAtUtc = null;
    state = null;
  }

  /// Returns the pending prefill and clears it in one step, withholding a
  /// prefill older than [parkTtl] (while still clearing it) so a stale parked
  /// link is dropped rather than delivered as a payment on an unrelated later
  /// unlock.
  ///
  /// The TTL is not optional and there is deliberately no unconditional twin:
  /// a claim path that skipped the age check is exactly the "link opened
  /// overnight fires as a payment" case [parkTtl] exists to prevent.
  ///
  /// `expired` separates the two ways this returns no prefill: nothing was
  /// parked at all, or a link the user did open sat past its window. Only the
  /// second is something to tell them about — the unlock flow shows
  /// `kPaymentUriExpiredMessage` for it, matching what the drain policy does
  /// with the same age on every other screen.
  ({SendPrefillArgs? prefill, bool expired}) takeIfFresh() {
    final prefill = state;
    final parkedAt = _parkedAtUtc;
    clear();
    if (prefill == null || parkedAt == null) {
      return (prefill: null, expired: false);
    }
    if (DateTime.now().toUtc().difference(parkedAt) > parkTtl) {
      return (prefill: null, expired: true);
    }
    return (prefill: prefill, expired: false);
  }

  /// Test seam: pretends the parked link arrived [age] ago, so the TTL branch
  /// can be exercised without a ten-minute wait.
  @visibleForTesting
  void debugAgePark(Duration age) {
    final parkedAt = _parkedAtUtc;
    if (parkedAt == null) return;
    _parkedAtUtc = parkedAt.subtract(age);
  }
}

final paymentUriPrefillProvider =
    NotifierProvider<PaymentUriPrefillNotifier, SendPrefillArgs?>(
      PaymentUriPrefillNotifier.new,
    );
