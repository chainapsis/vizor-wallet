import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../feedback/app_haptics.dart';
import '../layout/mobile/covered_route_keyboard_hold.dart';

/// Motion for a mobile page. Fully non-animated routes use NoTransitionPage.
enum MobilePageTransition {
  /// Fade and zoom on entry; slide out while the previous page scales back.
  fadeZoom,

  /// Appear immediately; slide out on Back. The previous page stays still.
  onboarding,
}

/// A mobile screen pushed onto the wallet navigator.
///
/// The new page fades in while growing from slightly smaller, and the page
/// it covers grows a touch, so going deeper reads as moving forward. Back
/// slides the opaque, full-size page out while the page below scales back.
/// With reduced motion only the fade remains. Opening
/// or closing a page plays a light tap ([AppHaptics.pageTransition]).
///
/// Dragging from the leading edge pops the page as the iOS back swipe does:
/// the page slides with the finger, opaque and at full size, so the page
/// below shows beside it rather than through it, and a fling or a drag past
/// halfway completes the pop. The gesture uses the same thresholds as
/// `CupertinoPageRoute`, which these pages replace.
///
/// [MobilePageTransition.onboarding] enters immediately and slides out on
/// Back. Under reduced motion its button-driven exit fades instead. A back
/// swipe stays attached to the finger, including its completion or cancellation.
class MobilePage<T> extends Page<T> {
  const MobilePage({
    required super.key,
    required this.child,
    this.transition = MobilePageTransition.fadeZoom,
  });

  final Widget child;

  final MobilePageTransition transition;

  @override
  Route<T> createRoute(BuildContext context) => MobilePageRoute<T>(page: this);
}

/// The route a [MobilePage] creates.
class MobilePageRoute<T> extends PageRoute<T> {
  MobilePageRoute({required MobilePage<T> page}) : super(settings: page);

  MobilePage<T> get _page => settings as MobilePage<T>;

  static const _enterDuration = Duration(milliseconds: 320);
  static const _exitDuration = Duration(milliseconds: 400);

  /// A strong ease-out: the page arrives quickly and settles gently. Its
  /// reverse is used when a pop interrupts that entrance.
  static const Curve _curve = Cubic(0.23, 1, 0.32, 1);
  static const Curve _reverseCurve = Cubic(0.68, 0, 0.77, 0);

  /// The fade finishes in the first 40% of the zoom, close to how the zoom
  /// curve looks. A translucent page costs a full-screen offscreen layer
  /// every frame, so it is translucent only while the fade shows. Reduced-
  /// motion and interrupted-entry pops use the fade's reverse.
  static const Curve _fadeCurve = Interval(0, 0.4, curve: Curves.easeOut);
  static const Curve _reverseFadeCurve = Interval(0.6, 1, curve: Curves.easeIn);

  /// The size a page grows from as it enters.
  static const _enterScale = 0.94;

  /// The size a page grows to while another covers it.
  static const _coveredScale = 1.03;

  /// The leading-edge strip that starts a back swipe, as on iOS.
  static const _swipeEdgeWidth = 20.0;

  /// Screen widths per second above which a released swipe counts as a
  /// fling.
  static const _swipeFlingVelocity = 1.0;

  /// How a released swipe settles, forward or back.
  static const _swipeSettleDuration = Duration(milliseconds: 350);
  static const Curve _swipeSettleCurve = Curves.fastEaseInToSlowEaseOut;

  /// A light tap whenever a page opens or closes, including a completed
  /// back swipe. A navigator's first page appears without one.
  @override
  TickerFuture didPush() {
    unawaited(AppHaptics.pageTransition());
    return super.didPush();
  }

  @override
  bool didPop(T? result) {
    // An interrupted entrance reverses in place so it does not jump from a
    // partly transparent, smaller page to a full-size opaque slide.
    final fullyEntered = animation!.isCompleted;
    final popped = super.didPop(result);
    if (popped) {
      _slideOnPop = fullyEntered;
      unawaited(AppHaptics.pageTransition());
    }
    return popped;
  }

  bool _slideOnPop = false;

  @override
  Duration get transitionDuration =>
      _page.transition == MobilePageTransition.onboarding
      ? Duration.zero
      : _enterDuration;

  @override
  Duration get reverseTransitionDuration => _exitDuration;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  /// Only another mobile page moves this one as it covers it; a sheet or a
  /// translucent overlay leaves it still.
  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) =>
      nextRoute is MobilePageRoute;

  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) =>
      _page.transition != MobilePageTransition.onboarding;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Semantics(
    scopesRoute: true,
    explicitChildNodes: true,
    // A covered page holds still while a sheet's keyboard moves.
    child: CoveredRouteKeyboardHold(child: _page.child),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _MobileTransition(
    transition: _page.transition,
    animation: animation,
    secondaryAnimation: secondaryAnimation,
    slideOnPop: _slideOnPop,
    // A back swipe drives the animation from the finger, so it must map
    // 1:1 rather than through the curves.
    followsFinger: popGestureInProgress,
    child: _BackSwipeDetector(route: this, child: child),
  );

  NavigatorState? _swipeNavigator;

  void _startSwipe() {
    assert(popGestureEnabled);
    _swipeNavigator = navigator!..didStartUserGesture();
  }

  /// [delta] is the drag in page widths, positive toward dismissal.
  void _updateSwipe(double delta) {
    controller!.value -= delta;
  }

  /// [velocity] is in page widths per second, positive toward dismissal.
  void _endSwipe(double velocity) {
    final controller = this.controller!;
    final navigator = _swipeNavigator!;
    _swipeNavigator = null;
    final bool settleBack;
    if (!isCurrent) {
      // Navigated away mid-swipe: finish whichever way the stack now
      // points.
      settleBack = isActive;
    } else if (velocity.abs() >= _swipeFlingVelocity) {
      settleBack = velocity <= 0;
    } else {
      settleBack = controller.value > 0.5;
    }

    if (settleBack) {
      controller.animateTo(
        1,
        duration: _swipeSettleDuration,
        curve: _swipeSettleCurve,
      );
    } else {
      if (isCurrent) navigator.pop();
      // The pop may already have finished if the page was fully dragged.
      if (controller.isAnimating) {
        controller.animateBack(
          0,
          duration: _swipeSettleDuration,
          curve: _swipeSettleCurve,
        );
      }
    }

    if (controller.isAnimating) {
      // The gesture stays in progress until the page settles, so the
      // transition keeps following the controller linearly.
      late final AnimationStatusListener onSettled;
      onSettled = (status) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(onSettled);
      };
      controller.addStatusListener(onSettled);
    } else {
      navigator.didStopUserGesture();
    }
  }
}

class _MobileTransition extends StatefulWidget {
  const _MobileTransition({
    required this.transition,
    required this.animation,
    required this.secondaryAnimation,
    required this.slideOnPop,
    required this.followsFinger,
    required this.child,
  });

  final MobilePageTransition transition;
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final bool slideOnPop;
  final bool followsFinger;
  final Widget child;

  @override
  State<_MobileTransition> createState() => _MobileTransitionState();
}

class _MobileTransitionState extends State<_MobileTransition> {
  late CurvedAnimation _entering;
  late CurvedAnimation _fading;
  late CurvedAnimation _covered;
  late CurvedAnimation _sliding;

  @override
  void initState() {
    super.initState();
    _entering = _curved(widget.animation);
    _fading = _faded(widget.animation);
    _covered = _cover(widget.secondaryAnimation);
    _sliding = _slide(widget.animation);
  }

  @override
  void didUpdateWidget(_MobileTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _entering.dispose();
      _entering = _curved(widget.animation);
      _fading.dispose();
      _fading = _faded(widget.animation);
      _sliding.dispose();
      _sliding = _slide(widget.animation);
    }
    if (oldWidget.secondaryAnimation != widget.secondaryAnimation) {
      _covered.dispose();
      _covered = _cover(widget.secondaryAnimation);
    }
  }

  @override
  void dispose() {
    _entering.dispose();
    _fading.dispose();
    _covered.dispose();
    _sliding.dispose();
    super.dispose();
  }

  static CurvedAnimation _curved(Animation<double> parent) => CurvedAnimation(
    parent: parent,
    curve: MobilePageRoute._curve,
    reverseCurve: MobilePageRoute._reverseCurve,
  );

  static CurvedAnimation _faded(Animation<double> parent) => CurvedAnimation(
    parent: parent,
    curve: MobilePageRoute._fadeCurve,
    reverseCurve: MobilePageRoute._reverseFadeCurve,
  );

  // Keep the entrance's zoom, then restore the previous page in step with
  // the outgoing page's slide. CurvedAnimation preserves the entrance curve
  // if a push reverses before completing, avoiding a discontinuity.
  static CurvedAnimation _cover(Animation<double> parent) => CurvedAnimation(
    parent: parent,
    curve: MobilePageRoute._curve,
    reverseCurve: MobilePageRoute._swipeSettleCurve.flipped,
  );

  static CurvedAnimation _slide(Animation<double> parent) => CurvedAnimation(
    parent: parent,
    curve: MobilePageRoute._swipeSettleCurve,
    reverseCurve: MobilePageRoute._swipeSettleCurve.flipped,
  );

  @override
  Widget build(BuildContext context) {
    final followsFinger = widget.followsFinger;
    final onboarding = widget.transition == MobilePageTransition.onboarding;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Button Back and a back swipe share the opaque, full-size slide. Only
    // the gesture uses raw progress; the button-driven slide is eased.
    final slides =
        followsFinger || (!reduceMotion && (onboarding || widget.slideOnPop));
    final entering = slides ? 1.0 : _entering.value;
    final opacity = slides
        ? 1.0
        : onboarding
        ? _sliding.value
        : _fading.value;
    final covered = followsFinger
        ? widget.secondaryAnimation.value
        : _covered.value;
    final zooms = !onboarding && !reduceMotion;
    final scale = zooms
        ? lerpDouble(MobilePageRoute._enterScale, 1, entering)! *
              lerpDouble(1, MobilePageRoute._coveredScale, covered)!
        : 1.0;
    // Keep the same widget structure through a gesture, including settling.
    // Replacing the detector's ancestors could dispose an active drag.
    final shift = slides
        ? (1 - (followsFinger ? widget.animation.value : _sliding.value)) *
              (Directionality.of(context) == TextDirection.rtl ? -1 : 1)
        : 0.0;
    return FractionalTranslation(
      translation: Offset(shift, 0),
      child: Transform.scale(
        scale: scale,
        child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: widget.child),
      ),
    );
  }
}

/// Starts a back swipe from the page's leading edge, as
/// `CupertinoPageRoute` does.
class _BackSwipeDetector<T> extends StatefulWidget {
  const _BackSwipeDetector({required this.route, required this.child});

  final MobilePageRoute<T> route;
  final Widget child;

  @override
  State<_BackSwipeDetector<T>> createState() => _BackSwipeDetectorState<T>();
}

class _BackSwipeDetectorState<T> extends State<_BackSwipeDetector<T>> {
  late final HorizontalDragGestureRecognizer _recognizer =
      HorizontalDragGestureRecognizer(debugOwner: this)
        ..onStart = _onStart
        ..onUpdate = _onUpdate
        ..onEnd = _onEnd
        ..onCancel = _onCancel;
  bool _swiping = false;

  @override
  void dispose() {
    _recognizer.dispose();
    if (_swiping) {
      // Disposed mid-swipe: release the navigator's gesture lock.
      final navigator = widget.route._swipeNavigator;
      widget.route._swipeNavigator = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator?.mounted ?? false) navigator!.didStopUserGesture();
      });
    }
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (widget.route.popGestureEnabled) _recognizer.addPointer(event);
  }

  void _onStart(DragStartDetails details) {
    _swiping = true;
    widget.route._startSwipe();
  }

  void _onUpdate(DragUpdateDetails details) {
    widget.route._updateSwipe(
      _towardDismissal(details.primaryDelta! / context.size!.width),
    );
  }

  void _onEnd(DragEndDetails details) {
    _swiping = false;
    widget.route._endSwipe(
      _towardDismissal(
        details.velocity.pixelsPerSecond.dx / context.size!.width,
      ),
    );
  }

  void _onCancel() {
    // Also called for a pointer that never started a drag.
    if (!_swiping) return;
    _swiping = false;
    widget.route._endSwipe(0);
  }

  double _towardDismissal(double value) =>
      Directionality.of(context) == TextDirection.rtl ? -value : value;

  @override
  Widget build(BuildContext context) {
    // Devices with a notch on the leading side get a wider strip.
    final padding = MediaQuery.paddingOf(context);
    final inset = Directionality.of(context) == TextDirection.rtl
        ? padding.right
        : padding.left;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        PositionedDirectional(
          start: 0,
          width: math.max(inset, MobilePageRoute._swipeEdgeWidth),
          top: 0,
          bottom: 0,
          child: Listener(
            onPointerDown: _onPointerDown,
            behavior: HitTestBehavior.translucent,
          ),
        ),
      ],
    );
  }
}
