import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/send/models/send_prefill_args.dart';

/// Holds a ZIP-321 payment-URI prefill that has been parsed from a `zcash:`
/// link but not yet delivered to the send screen.
///
/// This exists so the prefill survives the lock screen. A `zcash:` link opened
/// while the wallet is locked routes to `/unlock` and parks the prefill here;
/// the unlock flow then claims it (via [PaymentUriPrefillNotifier.takeIfFresh])
/// and navigates straight to `/send` instead of the default `/home`, so the
/// payment intent is not lost. When the wallet is already unlocked the
/// `_PaymentUriLinkListener` drains it directly.
class PaymentUriPrefillNotifier extends Notifier<SendPrefillArgs?> {
  /// A parked prefill older than this is treated as stale and dropped on the
  /// next unlock. Without it, a link opened then left parked (the user never
  /// unlocks) would fire as a payment on a much later, unrelated unlock.
  static const parkTtl = Duration(minutes: 10);

  DateTime? _parkedAtUtc;

  @override
  SendPrefillArgs? build() => null;

  void set(SendPrefillArgs prefill) {
    _parkedAtUtc = DateTime.now().toUtc();
    state = prefill;
  }

  void clear() {
    _parkedAtUtc = null;
    state = null;
  }

  /// Returns the pending prefill (if any) and clears it in one step.
  SendPrefillArgs? take() {
    final prefill = state;
    clear();
    return prefill;
  }

  /// Like [take], but returns null (while still clearing) when the parked
  /// prefill is older than [parkTtl]. The unlock flow uses this so a stale
  /// parked link is dropped rather than delivered as a payment on an unrelated
  /// later unlock.
  SendPrefillArgs? takeIfFresh() {
    final prefill = state;
    final parkedAt = _parkedAtUtc;
    clear();
    if (prefill == null || parkedAt == null) return null;
    if (DateTime.now().toUtc().difference(parkedAt) > parkTtl) return null;
    return prefill;
  }
}

final paymentUriPrefillProvider =
    NotifierProvider<PaymentUriPrefillNotifier, SendPrefillArgs?>(
      PaymentUriPrefillNotifier.new,
    );
