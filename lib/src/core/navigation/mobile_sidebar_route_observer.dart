import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root popups cover the router, whereas the persistent sidebar lives outside
/// it. Disable that sidebar for the entire popup lifetime, including transitions.
class MobileSidebarRouteObserver extends NavigatorObserver with ChangeNotifier {
  final _popups = <Route<dynamic>>{};
  bool get hasPopup => _popups.isNotEmpty;
  bool _scheduled = false;
  bool _disposed = false;

  void _changed() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      _popups.add(route);
      _changed();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _remove(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _remove(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _remove(oldRoute);
    if (newRoute is PopupRoute) {
      _popups.add(newRoute);
      _changed();
    }
  }

  void _remove(Route<dynamic>? route) {
    // Keep input disabled until the outgoing barrier has finished animating.
    if (route is TransitionRoute && _popups.contains(route)) {
      route.completed.whenComplete(() {
        if (_popups.remove(route)) _changed();
      });
    } else if (_popups.remove(route)) {
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final mobileSidebarRouteObserverProvider = Provider((ref) {
  final observer = MobileSidebarRouteObserver();
  ref.onDispose(observer.dispose);
  return observer;
});
