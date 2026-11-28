import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import 'proxy_delegation_routes.dart';
import 'screens/delegate_ballot_screen.dart';
import 'screens/delegate_key_import_screen.dart';
import 'screens/delegate_mode_home_screen.dart';
import 'screens/delegate_registration_screen.dart';
import 'screens/delegate_retire_screen.dart';
import 'screens/mobile/mobile_delegate_mode_screens.dart';
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

/// Desktop routes for delegate mode (DG screens). Registered only when the
/// dormant flag is on.
List<GoRoute> delegateModeDesktopRoutes({required ProxyRouteGuard guard}) {
  /// A guarded route for [screen] at [path].
  GoRoute route(String path, Widget Function(GoRouterState) screen) =>
      GoRoute(path: path, builder: (_, state) => guard(screen(state)));
  return [
    route(kDelegateModePath, (_) => const DelegateModeHomeScreen()),
    route(kDelegateKeyImportPath, (_) => const DelegateKeyImportScreen()),
    route(kDelegateRegistrationPath, (_) => const DelegateRegistrationScreen()),
    route(
      kDelegateBallotPath,
      (state) => DelegateBallotScreen(roundId: _roundId(state)),
    ),
    route(kDelegateRetirePath, (_) => const DelegateRetireScreen()),
  ];
}

/// Mobile routes for delegate mode (DG screens). Registered only when the
/// dormant flag is on.
List<GoRoute> delegateModeMobileRoutes({required ProxyRouteGuard guard}) {
  /// A guarded Cupertino page for [screen] at [path].
  GoRoute route(String path, Widget Function(GoRouterState) screen) => GoRoute(
    path: path,
    pageBuilder: (_, state) =>
        CupertinoPage(key: state.pageKey, child: guard(screen(state))),
  );
  return [
    route(kDelegateModePath, (_) => const MobileDelegateModeHomeScreen()),
    route(kDelegateKeyImportPath, (_) => const MobileDelegateKeyImportScreen()),
    route(
      kDelegateRegistrationPath,
      (_) => const MobileDelegateRegistrationScreen(),
    ),
    route(
      kDelegateBallotPath,
      (state) => MobileDelegateBallotScreen(roundId: _roundId(state)),
    ),
    route(kDelegateRetirePath, (_) => const MobileDelegateRetireScreen()),
  ];
}

/// The `roundId` path parameter.
String _roundId(GoRouterState state) => state.pathParameters['roundId'] ?? '';
