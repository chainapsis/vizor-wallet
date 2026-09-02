/// Hold count for in-progress surfaces a payment URI must not interrupt but
/// that a route path cannot name.
///
/// A delivered request is now presented as a card over the current screen, so
/// `decidePaymentUriDrain` no longer refuses to deliver based on where the
/// user is: nothing gets unmounted. What a hold here still buys is the one
/// case where even a modal card is destructive — a live animated QR an
/// external device's camera is reading. The desktop Keystone shield signing
/// overlay is that case today: it lives on `/home`, holds a prepared PCZT and
/// drives a device approval, yet `matchedLocation` stays `/home` the whole
/// time. A holder keeps the link parked (the drain answers `wait`), and
/// `app.dart` re-runs the drain when the count falls back to zero.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A count rather than a flag so overlapping holders compose: the surface is
/// busy while at least one holder is mounted, and an outgoing holder cannot
/// clear an incoming one's hold.
///
/// Every holder must take at most one hold and give exactly that one back.
/// [releaseAfterNavigation] exists because `dispose()` is one of the places
/// Riverpod forbids a synchronous provider write; hold the "did I acquire"
/// bit on the holder itself so a double release can never steal another
/// surface's hold.
class PaymentUriBusySurfaceNotifier extends Notifier<int> {
  var _disposed = false;

  @override
  int build() {
    ref.onDispose(() => _disposed = true);
    return 0;
  }

  /// Takes one hold. Call once per holder, from a post-frame callback rather
  /// than `initState`/`build`.
  void acquire() {
    if (_disposed) return;
    state = state + 1;
  }

  /// Gives one hold back. Clamped at zero so a stray release cannot drive the
  /// count negative and wedge the latch open.
  void release() {
    if (_disposed || state == 0) return;
    state = state - 1;
  }

  /// Releases once the current lifecycle call has returned, for holders that
  /// give their hold back from `dispose`. A microtask rather than a timer, so
  /// it cannot outlive a widget test's tree.
  void releaseAfterNavigation() {
    scheduleMicrotask(() {
      if (_disposed) return;
      release();
    });
  }
}

final paymentUriBusySurfaceProvider =
    NotifierProvider<PaymentUriBusySurfaceNotifier, int>(
      PaymentUriBusySurfaceNotifier.new,
    );
