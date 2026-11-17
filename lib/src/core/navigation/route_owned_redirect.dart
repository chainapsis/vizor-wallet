import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Wakes route-owned redirects after navigation, including the end of an
/// outgoing barrier. Use a separate instance for each enclosing Navigator.
class RouteOwnedNavigationObserver extends NavigatorObserver
    with ChangeNotifier {
  final _departing = <TransitionRoute<dynamic>>{};
  bool _disposed = false;
  final _nativeReturns = <TransitionRoute<dynamic>, Route<dynamic>>{};
  Route<dynamic>? _gestureRoute;
  Route<dynamic>? _gesturePreviousRoute;
  bool _gestureCancelled = false;
  int _nativeWatchers = 0;

  /// Native tabs may reveal under this exact page return before it settles.
  /// Redirects continue to use [hasDepartingRoutes], including popup barriers.
  bool revealsNativeTabsFor(Route<dynamic> route) =>
      !_departing.any((departing) => !_nativeReturns.containsKey(departing)) &&
      ((route.isCurrent &&
              _nativeReturns.values.any(
                (target) => identical(target, route),
              )) ||
          (_gestureRoute is PageRoute &&
              _gestureRoute!.isCurrent &&
              !_gestureCancelled &&
              identical(_gesturePreviousRoute, route)));

  /// GoRouter forwards some inner-Navigator notifications to root observers.
  /// Only returns to this shell's actual route ancestry can lift that fence.
  bool blocksNativeTabRevealFor(Iterable<Route<dynamic>> owners) =>
      _departing.any((route) => !owners.contains(_nativeReturns[route]));

  bool get nativeGestureInProgress => _gestureRoute != null;

  /// Only mounted native registrations observe releases. Cupertino reports
  /// AnimationStatus.forward both while dragging and while settling a cancel;
  /// the controller is actively animating only in the latter case.
  void watchNativeTabReturns() {
    if (_nativeWatchers++ == 0) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_nativePointer);
    }
  }

  void unwatchNativeTabReturns() {
    if (--_nativeWatchers == 0 && !_disposed) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_nativePointer);
    }
  }

  void _nativePointer(PointerEvent event) {
    if (event is! PointerUpEvent && event is! PointerCancelEvent) return;
    final route = _gestureRoute;
    if (route is! TransitionRoute) return;
    // After recognizers finish dispatch, a still-current page animating forward
    // is cancelling. Accepted-pointer handoff leaves its controller paused;
    // unrelated fingers therefore neither cancel nor delay the real release.
    scheduleMicrotask(() {
      if (_disposed || !identical(route, _gestureRoute)) return;
      if (!_gestureCancelled &&
          route.isCurrent &&
          route.animation?.status == AnimationStatus.forward &&
          _activelyAnimating(route.animation)) {
        _gestureCancelled = true;
        _changed();
      }
    });
  }

  bool _activelyAnimating(Animation<double>? animation) {
    final visited = <Animation<double>>{};
    while (animation != null && visited.add(animation)) {
      if (animation is AnimationController) return animation.isAnimating;
      animation = switch (animation) {
        AnimationWithParentMixin<double> parent => parent.parent,
        ProxyAnimation proxy => proxy.parent,
        _ => null,
      };
    }
    // An unfamiliar animation cannot prove that the gesture was released.
    return false;
  }

  @override
  void didStartUserGesture(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) {
    _gestureRoute = route;
    _gesturePreviousRoute = previousRoute;
    _gestureCancelled = false;
    _changed();
  }

  @override
  void didStopUserGesture() {
    _gestureRoute = null;
    _gesturePreviousRoute = null;
    _gestureCancelled = false;
    _changed();
  }

  bool get hasDepartingRoutes => _departing.isNotEmpty;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _depart(Route<dynamic>? route) {
    if (route is TransitionRoute && _departing.add(route)) {
      route.completed.whenComplete(() {
        _departing.remove(route);
        _nativeReturns.remove(route);
        _changed();
      });
    }
    _changed();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute && previousRoute != null) {
      _nativeReturns[route] = previousRoute;
    }
    _depart(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _depart(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _depart(oldRoute);

  @override
  void dispose() {
    _disposed = true;
    if (_nativeWatchers > 0) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_nativePointer);
    }
    super.dispose();
  }
}

/// A state-driven redirect owned by this mounted screen, never a global queue
/// of user clicks. Covered pages keep their intent; execution reads the latest
/// widget and revalidates the account/session after all enclosing routes settle.
/// Removing this widget cancels its intent without retaining its BuildContext.
class RouteOwnedRedirect extends StatefulWidget {
  const RouteOwnedRedirect({
    required this.requestKey,
    required this.isValid,
    required this.onNavigate,
    required this.child,
    super.key,
  });

  final Object requestKey;
  final bool Function() isValid;
  final VoidCallback onNavigate;
  final Widget child;

  @override
  State<RouteOwnedRedirect> createState() => _RouteOwnedRedirectState();
}

class _RouteOwnedRedirectState extends State<RouteOwnedRedirect> {
  List<ModalRoute<dynamic>> _routes = [];
  final _observers = <RouteOwnedNavigationObserver>{};
  final _animations = <Animation<double>>{};
  Object? _completedKey;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final routes = <ModalRoute<dynamic>>[];
    var route = ModalRoute.of(context);
    while (route != null) {
      routes.add(route);
      final parent = route.navigator?.context;
      route = parent == null ? null : ModalRoute.of(parent);
    }
    if (!listEquals(routes, _routes)) _completedKey = null;
    _routes = routes;
    final observers = {
      for (final route in routes)
        ...?route.navigator?.widget.observers
            .whereType<RouteOwnedNavigationObserver>(),
    };
    for (final observer in _observers.difference(observers)) {
      observer.removeListener(_schedule);
    }
    for (final observer in observers.difference(_observers)) {
      observer.addListener(_schedule);
    }
    _observers
      ..clear()
      ..addAll(observers);
    final animations = {for (final route in routes) ?route.animation};
    for (final animation in _animations.difference(animations)) {
      animation.removeStatusListener(_animationChanged);
    }
    for (final animation in animations.difference(_animations)) {
      animation.addStatusListener(_animationChanged);
    }
    _animations
      ..clear()
      ..addAll(animations);
  }

  void _animationChanged(AnimationStatus _) => _schedule();

  bool get _ready =>
      _routes.isNotEmpty &&
      _routes.every((route) => route.isActive && route.isCurrent) &&
      _observers.every((observer) => !observer.hasDepartingRoutes) &&
      _animations.every(
        (animation) => animation.status == AnimationStatus.completed,
      );

  void _schedule() {
    if (!mounted || _scheduled || _completedKey == widget.requestKey) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted ||
          _completedKey == widget.requestKey ||
          !_ready ||
          !widget.isValid()) {
        return;
      }
      final key = widget.requestKey;
      widget.onNavigate();
      _completedKey = key;
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    _schedule();
    return widget.child;
  }

  @override
  void dispose() {
    for (final observer in _observers) {
      observer.removeListener(_schedule);
    }
    for (final animation in _animations) {
      animation.removeStatusListener(_animationChanged);
    }
    super.dispose();
  }
}
