import 'package:flutter/material.dart';

/// How long a payment-link notice stays up.
const _paymentUriNoticeDuration = Duration(seconds: 4);

/// Shows one payment-link notice on [messenger], after the current frame.
///
/// Two places drop a `zcash:` link: the drain policy in `app.dart`, and the
/// unlock screens' claim of a link parked while the wallet was locked. They
/// share this so both read the same way and a change to one cannot leave the
/// other behind.
///
/// The messenger is passed in rather than looked up here on purpose: the
/// unlock screens navigate to `/home` in the same turn, so by the time the
/// post-frame callback runs their own `BuildContext` is gone, while the
/// app-level `ScaffoldMessengerState` is not.
void showPaymentUriNotice(ScaffoldMessengerState messenger, String message) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!messenger.mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: _paymentUriNoticeDuration),
    );
  });
  // addPostFrameCallback does not request a frame on its own. An idle app
  // (locked, nothing animating) would otherwise sit on the notice until some
  // unrelated frame happens to be scheduled.
  WidgetsBinding.instance.scheduleFrame();
}
