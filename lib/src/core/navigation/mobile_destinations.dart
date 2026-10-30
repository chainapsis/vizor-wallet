import 'package:go_router/go_router.dart';

import '../layout/mobile/app_mobile_tab_bar.dart';
import '../widgets/app_icon.dart';

const mobileDestinations = <({String path, AppMobileTabItem item})>[
  (
    path: '/home',
    item: AppMobileTabItem(iconName: AppIcons.home, label: 'Home'),
  ),
  (
    path: '/swap',
    item: AppMobileTabItem(iconName: AppIcons.swapArrows, label: 'Swap'),
  ),
  (
    path: '/activity',
    item: AppMobileTabItem(iconName: AppIcons.history, label: 'Activity'),
  ),
  (
    path: '/settings',
    item: AppMobileTabItem(iconName: AppIcons.cog, label: 'Settings'),
  ),
];

/// Sidebar visibility and navigation are separate: protected flows keep the
/// sidebar visible but cannot be abandoned via its newly available controls.
bool hasMobileWalletSidebar(String path) => const [
  '/home',
  '/accounts',
  '/swap',
  '/activity',
  '/settings',
  '/send',
  '/receive',
  '/pay',
  '/payment-links',
  '/voting',
  '/migration',
  '/about',
  '/setup/backup',
].any((root) => path == root || path.startsWith('$root/'));

/// Stateful flows must publish their current exit permission. Unknown/new
/// wallet routes fail closed until reviewed; read-only routes need no handler.
bool requiresMobileSidebarExitPolicy(String path) =>
    !(const [
          '/home',
          '/accounts',
          '/swap',
          '/activity',
          '/settings',
          '/receive',
          '/about',
          '/voting',
        ].contains(path) ||
        path.startsWith('/activity/') ||
        RegExp(r'^/voting/poll/[^/]+/results$').hasMatch(path) ||
        (path.startsWith('/settings/') &&
            !const [
              '/settings/change-password',
              '/settings/seed-phrase',
              '/settings/viewing-key',
            ].contains(path)));

/// Imperative pushes retain the base URI in currentConfiguration.uri. Walk
/// the actual top route (including nested shell branches) for flow protection.
String mobileVisiblePath(GoRouter router) {
  RouteMatchBase? match =
      router.routerDelegate.currentConfiguration.matches.lastOrNull;
  while (true) {
    if (match is ImperativeRouteMatch) {
      match = match.matches.matches.lastOrNull;
    } else if (match is ShellRouteMatch) {
      match = match.matches.lastOrNull;
    } else {
      return match is RouteMatch ? match.matchedLocation : '';
    }
  }
}
