import 'package:flutter/widgets.dart';

/// Tracks whether this route has been fully covered by a route pushed on top.
///
/// A screen that shows a secret drives a global native screenshot shield
/// (`SensitivePrivacyOverlay` → Android `FLAG_SECURE` / iOS secure-field
/// blanking). When it pushes the next step, it must drop that token so the
/// pushed, non-secret screens are not blanked — but only *after* the secret
/// screen is off-screen. Keying the drop off the route's `secondaryAnimation`
/// (rather than the push/pop `Future`) keeps the shield engaged through the
/// entire push slide-out and pop slide-in, so the secret is never visible
/// unblanked during a transition.
mixin RouteCoverageAware<T extends StatefulWidget> on State<T> {
  Animation<double>? _secondaryAnimation;
  bool _coveredByNextRoute = false;

  /// True only once the next route has fully slid over this one. False while
  /// this route is on top and throughout both the push and pop transitions.
  bool get isCoveredByNextRoute => _coveredByNextRoute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final secondary = ModalRoute.of(context)?.secondaryAnimation;
    if (identical(secondary, _secondaryAnimation)) return;
    _secondaryAnimation?.removeStatusListener(_onSecondaryStatus);
    _secondaryAnimation = secondary;
    _secondaryAnimation?.addStatusListener(_onSecondaryStatus);
    // Set directly — build runs right after didChangeDependencies; the listener
    // uses setState for later status changes.
    _coveredByNextRoute = secondary?.status == AnimationStatus.completed;
  }

  void _onSecondaryStatus(AnimationStatus status) {
    final covered = status == AnimationStatus.completed;
    if (covered == _coveredByNextRoute || !mounted) return;
    setState(() => _coveredByNextRoute = covered);
  }

  @override
  void dispose() {
    _secondaryAnimation?.removeStatusListener(_onSecondaryStatus);
    super.dispose();
  }
}
