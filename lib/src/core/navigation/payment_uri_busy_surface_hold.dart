/// The one way a surface takes a `paymentUriBusySurfaceProvider` hold.
///
/// Every holder owes the notifier the same contract — acquire once from a
/// post-frame callback after mount, give exactly that hold back from
/// `dispose` via `releaseAfterNavigation`, and guard both ends with a
/// per-holder bit so a surface disposed before its callback ran cannot
/// decrement a hold it never took. Writing that by hand in a dozen Keystone
/// screens is how one of them ends up releasing twice, so the pattern lives
/// here once.
///
/// Two shapes, because the surfaces come in two shapes:
///
/// * [PaymentUriBusySurfaceHoldMixin] for a screen whose whole lifetime is
///   the signing session (`/send/keystone/scan`, the mobile signing screens).
/// * [PaymentUriBusySurfaceHold] for a QR that is only part of a longer-lived
///   screen — the desktop send review and the voting status screen show one
///   mid-flow, and the hold must last exactly as long as that subtree, not as
///   long as the review.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'payment_uri_busy_surface_provider.dart';

/// Holds one `paymentUriBusySurfaceProvider` hold for the mounted lifetime of
/// the state that mixes it in.
///
/// The state must call `super.initState()` first and `super.dispose()` last,
/// which is the normal shape anyway.
mixin PaymentUriBusySurfaceHoldMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  /// Captured in [initState] so [dispose] can give the hold back without
  /// reading from `ref` after the element is gone.
  late final PaymentUriBusySurfaceNotifier _paymentUriBusySurface;

  /// Whether this holder actually took a hold. Guards the release so a holder
  /// disposed before its post-frame callback ran cannot decrement a hold it
  /// never took.
  bool _holdsPaymentUriBusySurface = false;

  @override
  void initState() {
    super.initState();
    _paymentUriBusySurface = ref.read(paymentUriBusySurfaceProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _holdsPaymentUriBusySurface) return;
      _paymentUriBusySurface.acquire();
      _holdsPaymentUriBusySurface = true;
    });
  }

  @override
  void dispose() {
    if (_holdsPaymentUriBusySurface) {
      _holdsPaymentUriBusySurface = false;
      _paymentUriBusySurface.releaseAfterNavigation();
    }
    super.dispose();
  }
}

/// Wraps [child] in one `paymentUriBusySurfaceProvider` hold for as long as it
/// is mounted.
///
/// Use it where the QR surface is a conditional subtree rather than a whole
/// screen; use [PaymentUriBusySurfaceHoldMixin] where the screen *is* the
/// session. Put it above any keyed subtree that remounts mid-session (a
/// per-round signing flow), so the count never dips to zero between rounds and
/// lets a parked link through in the gap.
class PaymentUriBusySurfaceHold extends ConsumerStatefulWidget {
  const PaymentUriBusySurfaceHold({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PaymentUriBusySurfaceHold> createState() =>
      _PaymentUriBusySurfaceHoldState();
}

class _PaymentUriBusySurfaceHoldState
    extends ConsumerState<PaymentUriBusySurfaceHold>
    with PaymentUriBusySurfaceHoldMixin {
  @override
  Widget build(BuildContext context) => widget.child;
}
