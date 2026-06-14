import 'package:flutter/cupertino.dart' show CupertinoPage;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/screens/mobile/mobile_accounts_screen.dart';
import '../../features/activity/screens/mobile/mobile_activity_screen.dart';
import '../../features/home/screens/mobile/mobile_home_screen.dart';
import '../../features/receive/screens/mobile/mobile_receive_screen.dart';
import '../../features/address_book/screens/mobile/mobile_address_book_screen.dart';
import '../../features/activity/screens/mobile/mobile_swap_activity_detail_screen.dart';
import '../../features/activity/screens/mobile/mobile_transaction_status_screen.dart';
import '../../features/send/screens/mobile/mobile_keystone_sign_screen.dart';
import '../../features/swap/models/swap_activity_navigation.dart';
import '../../features/swap/screens/mobile/mobile_swap_review_screen.dart';
import '../../features/send/services/send_flow.dart'
    show KeystoneBroadcastArgs, SendReviewArgs;
import '../../features/send/screens/mobile/mobile_send_scan_screen.dart';
import '../../features/send/screens/mobile/mobile_send_screen.dart';
import '../../features/send/screens/mobile/mobile_send_status_screen.dart';
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
                // Settings detail screens push over the shell (top-level
                // routes below) so the bottom tab bar is hidden while
                // they're open; nothing extra nests inside a branch.
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
    // Settings detail screens are full-screen pushes over the shell so
    // the bottom tab bar is hidden while they're open. Absolute paths
    // match the desktop routes for the shared redirect guard and deep
    // links.
    GoRoute(
      path: '/settings/seed-phrase',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: const MobileSeedPhraseScreen(),
      ),
    ),
    GoRoute(
      path: '/settings/address-book',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: const MobileAddressBookScreen(),
      ),
    ),
    GoRoute(
      path: '/settings/endpoint',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: const MobileEndpointScreen(),
      ),
    ),
    // The Update Passcode frames also drop the tab bar — same
    // full-screen push pattern.
    GoRoute(
      path: '/settings/change-password',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: const MobileChangePasscodeScreen(),
      ),
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
      path: '/send/status',
      pageBuilder: (context, state) {
        final extra = state.extra;
        final child = switch (extra) {
          KeystoneBroadcastArgs() => MobileSendStatusScreen(
            args: extra.reviewArgs,
            keystone: extra,
          ),
          SendReviewArgs() => MobileSendStatusScreen(args: extra),
          _ => const MobileSendScreen(),
        };
        return CupertinoPage(key: state.pageKey, child: child);
      },
    ),
    GoRoute(
      path: '/swap/review',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: const MobileSwapReviewScreen(),
      ),
    ),
    // Same path as the desktop transaction status route so the shared
    // redirect guard and deep links treat them identically.
    GoRoute(
      path: '/activity/tx/:txid',
      pageBuilder: (context, state) {
        final extra = state.extra;
        final args = extra is MobileTransactionStatusArgs
            ? extra
            : MobileTransactionStatusArgs(
                txidHex: state.pathParameters['txid'] ?? '',
                txKind: state.uri.queryParameters['kind'],
              );
        return CupertinoPage(
          key: state.pageKey,
          child: MobileTransactionStatusScreen(args: args),
        );
      },
    ),
    GoRoute(
      path: '/activity/swap/:swapId',
      pageBuilder: (context, state) {
        final swapId = state.pathParameters['swapId'] ?? '';
        return CupertinoPage(
          key: state.pageKey,
          child: MobileSwapActivityDetailScreen(
            swapIntentId: swapId,
            returnTarget: SwapActivityReturnTarget.fromQueryValue(
              state.uri.queryParameters[swapActivityReturnQueryKey],
            ),
            autoSignZecDeposit:
                state.uri.queryParameters[swapActivitySignQueryKey] ==
                swapActivitySignZecDepositValue,
          ),
        );
      },
    ),
    GoRoute(
      path: '/send/keystone-sign',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: MobileKeystoneSignScreen(args: state.extra! as SendReviewArgs),
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
