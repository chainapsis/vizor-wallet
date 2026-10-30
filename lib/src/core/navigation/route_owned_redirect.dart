import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Wakes route-owned redirects after navigation, including the end of an
/// outgoing barrier. Use a separate instance for each enclosing Navigator.
class RouteOwnedNavigationObserver extends NavigatorObserver
    with ChangeNotifier {
  final _departing = <TransitionRoute<dynamic>>{};
  bool _disposed = false;

  bool get hasDepartingRoutes => _departing.isNotEmpty;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _depart(Route<dynamic>? route) {
    if (route is TransitionRoute && _departing.add(route)) {
      route.completed.whenComplete(() {
        _departing.remove(route);
        _changed();
      });
    }
    _changed();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _depart(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _depart(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _depart(oldRoute);

  @override
  void dispose() {
    _disposed = true;
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
