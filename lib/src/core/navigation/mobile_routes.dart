import 'package:flutter/cupertino.dart' show CupertinoPage;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/screens/mobile/mobile_accounts_screen.dart';
import '../../features/activity/screens/mobile/mobile_activity_screen.dart';
import '../../features/home/screens/mobile/mobile_home_screen.dart';
import '../../features/receive/screens/mobile/mobile_receive_screen.dart';
import '../../features/send/screens/mobile/mobile_send_scan_screen.dart';
import '../../features/send/screens/mobile/mobile_send_screen.dart';
import '../../features/about/screens/mobile/mobile_about_screens.dart';
import '../../features/settings/screens/mobile/mobile_change_passcode_screen.dart';
import '../../features/settings/screens/mobile/mobile_endpoint_screen.dart';
import '../../features/settings/screens/mobile/mobile_seed_phrase_screen.dart';
import '../../features/settings/screens/mobile/mobile_settings_screen.dart';
import '../../features/swap/screens/mobile/mobile_swap_screen.dart';
import '../layout/mobile/app_mobile_shell.dart';
import '../layout/mobile/app_mobile_tab_bar.dart';
import '../widgets/app_icon.dart';

/// The mobile route tree: the shared entry/onboarding routes, a
/// stateful tab shell (home / swap / activity / settings), and
/// full-screen flows pushed over the shell as [CupertinoPage]s so iOS
/// edge-swipe back works.
///
/// Route paths intentionally match the desktop tree so the shared
/// redirect guard, deep links, and `bootstrap.initialLocation` work
/// unchanged. The shared entry routes are passed in (rather than
/// imported from `app.dart`) to keep the import graph acyclic.
List<RouteBase> buildMobileRoutes({
  required List<RouteBase> entryRoutes,
  required bool swapFeatureEnabled,
}) {
  final tabs = _mobileTabs(swapFeatureEnabled: swapFeatureEnabled);
  return [
    ...entryRoutes,
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          _MobileTabShell(navigationShell: navigationShell, tabs: tabs),
      branches: [
        for (final tab in tabs)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: tab.path,
                pageBuilder: (context, state) =>
                    NoTransitionPage(key: state.pageKey, child: tab.screen),
                // Settings detail screens keep the floating tab bar
                // visible in their Figma frames, so they push inside
                // the branch navigator. Full-screen flows (send,
                // receive, scan) stay outside the shell below.
                routes: tab.path == '/settings'
                    ? [
                        // Same paths as the desktop routes so the
                        // shared redirect guard and deep links treat
                        // them identically.
                        GoRoute(
                          path: 'change-password',
                          pageBuilder: (context, state) => CupertinoPage(
                            key: state.pageKey,
                            child: const MobileChangePasscodeScreen(),
                          ),
                        ),
                        GoRoute(
                          path: 'seed-phrase',
                          pageBuilder: (context, state) => CupertinoPage(
                            key: state.pageKey,
                            child: const MobileSeedPhraseScreen(),
                          ),
                        ),
                        GoRoute(
                          path: 'endpoint',
                          pageBuilder: (context, state) => CupertinoPage(
                            key: state.pageKey,
                            child: const MobileEndpointScreen(),
                          ),
                        ),
                      ]
                    : const <RouteBase>[],
              ),
              // The Accounts screen lives in the home branch (its
              // Figma frame keeps the tab bar) under its own path.
              if (tab.path == '/home')
                GoRoute(
                  path: '/accounts',
                  pageBuilder: (context, state) => CupertinoPage(
                    key: state.pageKey,
                    child: const MobileAccountsScreen(),
                  ),
                ),
            ],
          ),
      ],
    ),
    GoRoute(
      path: '/send',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: MobileSendScreen(initialRecipient: state.extra as String?),
      ),
    ),
    GoRoute(
      path: '/send/scan',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: const MobileSendScanScreen(),
      ),
    ),
    GoRoute(
      path: '/receive',
      pageBuilder: (context, state) =>
          CupertinoPage(key: state.pageKey, child: const MobileReceiveScreen()),
    ),
    GoRoute(
      path: '/about',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: const MobileAboutScreen(),
      ),
    ),
  ];
}

class _MobileTab {
  const _MobileTab({
    required this.path,
    required this.item,
    required this.screen,
  });

  final String path;
  final AppMobileTabItem item;
  final Widget screen;
}

/// Branch order and tab-bar order derive from this single list so their
/// indices can never drift apart.
List<_MobileTab> _mobileTabs({required bool swapFeatureEnabled}) => [
  const _MobileTab(
    path: '/home',
    item: AppMobileTabItem(iconName: AppIcons.home, label: 'Home'),
    screen: MobileHomeScreen(),
  ),
  if (swapFeatureEnabled)
    const _MobileTab(
      path: '/swap',
      item: AppMobileTabItem(iconName: AppIcons.swapArrows, label: 'Swap'),
      screen: MobileSwapScreen(),
    ),
  const _MobileTab(
    path: '/activity',
    item: AppMobileTabItem(iconName: AppIcons.history, label: 'Activity'),
    screen: MobileActivityScreen(),
  ),
  const _MobileTab(
    path: '/settings',
    item: AppMobileTabItem(iconName: AppIcons.cog, label: 'Settings'),
    screen: MobileSettingsScreen(),
  ),
];

class _MobileTabShell extends StatelessWidget {
  const _MobileTabShell({required this.navigationShell, required this.tabs});

  final StatefulNavigationShell navigationShell;
  final List<_MobileTab> tabs;

  @override
  Widget build(BuildContext context) {
    return AppMobileShell(
      body: navigationShell,
      tabBar: AppMobileTabBar(
        items: [for (final tab in tabs) tab.item],
        currentIndex: navigationShell.currentIndex,
        onSelect: (index) => navigationShell.goBranch(
          index,
          // Re-selecting the active tab resets that tab to its root,
          // the platform-conventional behavior.
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
