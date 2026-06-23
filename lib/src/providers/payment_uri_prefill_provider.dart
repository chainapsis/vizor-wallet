import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/send/models/send_prefill_args.dart';

/// Holds a ZIP-321 payment-URI prefill that has been parsed from a `zcash:`
/// link but not yet delivered to the send screen.
///
/// This exists so the prefill survives the lock screen. A `zcash:` link opened
/// while the wallet is locked routes to `/unlock` and parks the prefill here;
/// the unlock flow then claims it (via [PaymentUriPrefillNotifier.take]) and
/// navigates straight to `/send` instead of the default `/home`, so the payment
/// intent is not lost. When the wallet is already unlocked the
/// `_PaymentUriLinkListener` drains it directly.
class PaymentUriPrefillNotifier extends Notifier<SendPrefillArgs?> {
  @override
  SendPrefillArgs? build() => null;

  void set(SendPrefillArgs prefill) => state = prefill;

  void clear() => state = null;

  /// Returns the pending prefill (if any) and clears it in one step, so a
  /// single caller can claim it without another consumer also acting on it.
  SendPrefillArgs? take() {
    final prefill = state;
    state = null;
    return prefill;
  }
}

final paymentUriPrefillProvider =
    NotifierProvider<PaymentUriPrefillNotifier, SendPrefillArgs?>(
      PaymentUriPrefillNotifier.new,
    );
