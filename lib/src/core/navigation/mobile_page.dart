import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../feedback/app_haptics.dart';
import '../layout/mobile/covered_route_keyboard_hold.dart';

/// A mobile screen pushed onto the wallet navigator, with a fade and zoom.
///
/// The new page fades in while growing from slightly smaller, and the page
/// it covers grows a touch, so going deeper reads as moving forward. Popping
/// plays it backwards. With reduced motion only the fade remains. Opening
/// or closing a page plays a light tap ([AppHaptics.pageTransition]).
///
/// Dragging from the leading edge pops the page as the iOS back swipe does:
/// the page slides with the finger, opaque and at full size, so the page
/// below shows beside it rather than through it, and a fling or a drag past
/// halfway completes the pop. The gesture uses the same thresholds as
/// `CupertinoPageRoute`, which these pages replace.
///
/// With [animated] false the page appears and leaves at once, with no fade
/// or zoom; onboarding steps use this. The back swipe and the tap stay.
class MobilePage<T> extends Page<T> {
  const MobilePage({
    required super.key,
    required this.child,
    this.animated = true,
  });

  final Widget child;

  /// Whether opening and closing the page fades and zooms.
  final bool animated;

  @override
  Route<T> createRoute(BuildContext context) => MobilePageRoute<T>(page: this);
}

/// The route a [MobilePage] creates.
class MobilePageRoute<T> extends PageRoute<T> {
  MobilePageRoute({required MobilePage<T> page}) : super(settings: page);

  MobilePage<T> get _page => settings as MobilePage<T>;

  static const _enterDuration = Duration(milliseconds: 320);
  static const _exitDuration = Duration(milliseconds: 260);

  /// A strong ease-out: the page arrives quickly and settles gently. The
  /// reverse is its mirror, so a pop also starts fast and lands softly.
  static const Curve _curve = Cubic(0.23, 1, 0.32, 1);
  static const Curve _reverseCurve = Cubic(0.68, 0, 0.77, 0);

  /// The fade finishes in the first 40% of the zoom, close to how the zoom
  /// curve looks. A translucent page costs a full-screen offscreen layer
  /// every frame, so it is translucent only while the fade shows. A pop
  /// fades out over its first 40% and draws nothing after.
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
    final popped = super.didPop(result);
    if (popped) unawaited(AppHaptics.pageTransition());
    return popped;
  }

  @override
  Duration get transitionDuration =>
      _page.animated ? _enterDuration : Duration.zero;

  @override
  Duration get reverseTransitionDuration =>
      _page.animated ? _exitDuration : Duration.zero;

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
  ) => _FadeZoomTransition(
    animated: _page.animated,
    animation: animation,
    secondaryAnimation: secondaryAnimation,
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

class _FadeZoomTransition extends StatefulWidget {
  const _FadeZoomTransition({
    required this.animated,
    required this.animation,
    required this.secondaryAnimation,
    required this.followsFinger,
    required this.child,
  });

  /// [MobilePage.animated]. Without it the page never fades or zooms.
  final bool animated;
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final bool followsFinger;
  final Widget child;

  @override
  State<_FadeZoomTransition> createState() => _FadeZoomTransitionState();
}

class _FadeZoomTransitionState extends State<_FadeZoomTransition> {
  late CurvedAnimation _entering;
  late CurvedAnimation _fading;
  late CurvedAnimation _covered;

  @override
  void initState() {
    super.initState();
    _entering = _curved(widget.animation);
    _fading = _faded(widget.animation);
    _covered = _curved(widget.secondaryAnimation);
  }

  @override
  void didUpdateWidget(_FadeZoomTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _entering.dispose();
      _entering = _curved(widget.animation);
      _fading.dispose();
      _fading = _faded(widget.animation);
    }
    if (oldWidget.secondaryAnimation != widget.secondaryAnimation) {
      _covered.dispose();
      _covered = _curved(widget.secondaryAnimation);
    }
  }

  @override
  void dispose() {
    _entering.dispose();
    _fading.dispose();
    _covered.dispose();
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

  @override
  Widget build(BuildContext context) {
    final followsFinger = widget.followsFinger;
    // Under the finger the page only slides, opaque and at full size, so the
    // page below shows beside it rather than through it. The fade and zoom
    // are for opening and closing.
    final entering = followsFinger ? 1.0 : _entering.value;
    final opacity = followsFinger ? 1.0 : _fading.value;
    final covered = followsFinger
        ? widget.secondaryAnimation.value
        : _covered.value;
    final animated = widget.animated;
    final zooms = animated && !MediaQuery.disableAnimationsOf(context);
    final scale = zooms
        ? lerpDouble(MobilePageRoute._enterScale, 1, entering)! *
              lerpDouble(1, MobilePageRoute._coveredScale, covered)!
        : 1.0;
    // It never slides on its own.
    final shift = followsFinger
        ? (1 - widget.animation.value) *
              (Directionality.of(context) == TextDirection.rtl ? -1 : 1)
        : 0.0;
    return FractionalTranslation(
      translation: Offset(shift, 0),
      child: Transform.scale(
        scale: scale,
        child: animated
            ? Opacity(opacity: opacity.clamp(0.0, 1.0), child: widget.child)
            : widget.child,
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
