import 'package:go_router/go_router.dart';

/// Inspect leaf route definitions without depending on presentation shells.
Iterable<GoRoute> goRouteDescendants(Iterable<RouteBase> routes) sync* {
  for (final route in routes) {
    if (route is GoRoute) yield route;
    yield* goRouteDescendants(route.routes);
  }
}
