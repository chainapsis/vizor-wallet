import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import 'proxy_delegation_routes.dart';
import 'screens/mobile/mobile_proxy_delegation_screens.dart';
import 'screens/proxy_allocation_screen.dart';
import 'screens/proxy_delegate_directory_screen.dart';

/// Wraps a voting screen in the router's account guard.
typedef ProxyRouteGuard = Widget Function(Widget child);

/// Desktop routes for the delegator screens: choosing delegates and the
/// split, which return to the round's questions. Registered only when
/// the dormant flag is on.
List<GoRoute> proxyDelegationDesktopRoutes({required ProxyRouteGuard guard}) {
  /// A guarded route for [screen] at [path].
  GoRoute route(String path, Widget Function(GoRouterState) screen) =>
      GoRoute(path: path, builder: (_, state) => guard(screen(state)));
  return [
    route(
      kProxyDelegateDirectoryPath,
      (state) => ProxyDelegateDirectoryScreen(roundId: _roundId(state)),
    ),
    route(
      kProxyAllocationPath,
      (state) => ProxyAllocationScreen(roundId: _roundId(state)),
    ),
  ];
}

/// Mobile routes for the delegator screens; see
/// [proxyDelegationDesktopRoutes]. Registered only when the dormant flag is
/// on.
List<GoRoute> proxyDelegationMobileRoutes({required ProxyRouteGuard guard}) {
  /// A guarded Cupertino page for [screen] at [path].
  GoRoute route(String path, Widget Function(GoRouterState) screen) => GoRoute(
    path: path,
    pageBuilder: (_, state) =>
        CupertinoPage(key: state.pageKey, child: guard(screen(state))),
  );
  return [
    route(
      kProxyDelegateDirectoryPath,
      (state) => MobileProxyDelegateDirectoryScreen(roundId: _roundId(state)),
    ),
    route(
      kProxyAllocationPath,
      (state) => MobileProxyAllocationScreen(roundId: _roundId(state)),
    ),
  ];
}

/// The `roundId` path parameter.
String _roundId(GoRouterState state) => state.pathParameters['roundId'] ?? '';
