import 'package:flutter/cupertino.dart' show CupertinoPage;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/screens/mobile/mobile_accounts_screen.dart';
import '../../features/activity/screens/mobile/mobile_activity_screen.dart';
import '../../features/home/screens/mobile/mobile_home_screen.dart';
import '../../features/home/screens/mobile/mobile_keystone_shield_screen.dart';
import '../../features/migration/screens/mobile/mobile_ironwood_migration_flow_screen.dart';
import '../../features/migration/models/mobile_ironwood_migration_status_entry.dart';
import '../../features/migration/screens/ironwood_migration_flow_screen.dart'
    show
        MobileIronwoodMigrationKeystoneBatchSignScreen,
        MobileIronwoodMigrationKeystoneDenominationSignScreen;
import '../../features/pay/screens/mobile/mobile_pay_screen.dart';
import '../../features/pay/screens/mobile/mobile_pay_submitted_screen.dart';
import '../../features/receive/screens/mobile/mobile_receive_screen.dart';
import '../../features/address_book/screens/mobile/mobile_address_book_screen.dart';
import '../../features/activity/screens/mobile/mobile_swap_activity_detail_screen.dart';
import '../../features/activity/screens/mobile/mobile_transaction_status_screen.dart';
import '../../features/send/screens/mobile/mobile_keystone_sign_screen.dart';
import '../../features/swap/models/swap_activity_navigation.dart';
import '../../features/swap/screens/mobile/mobile_swap_keystone_sign_screen.dart';
import '../../features/swap/screens/mobile/mobile_swap_review_screen.dart';
import '../../features/send/services/send_flow.dart'
    show KeystoneBroadcastArgs, SendReviewArgs;
import '../../features/send/screens/mobile/mobile_send_screen.dart';
import '../../features/send/screens/mobile/mobile_send_status_screen.dart';
import '../../rust/api/sync.dart' as rust_sync;
import '../../features/about/screens/mobile/mobile_about_screens.dart';
import '../../features/settings/screens/mobile/mobile_change_passcode_screen.dart';
import '../../features/settings/screens/mobile/mobile_endpoint_screen.dart';
import '../../features/settings/screens/mobile/mobile_seed_phrase_screen.dart';
import '../../features/settings/screens/mobile/mobile_settings_screen.dart';
import '../../features/swap/screens/mobile/mobile_swap_screen.dart';
import '../config/swap_feature_config.dart';
import '../layout/mobile/app_mobile_shell.dart';
import '../layout/mobile/app_mobile_tab_bar.dart';
import '../widgets/app_icon.dart';
import 'mobile_tab_history.dart';

/// The mobile route tree: the shared entry/onboarding routes, a
/// stateful tab shell (home / swap / activity / settings), and
/// full-screen flows pushed over the shell as [CupertinoPage]s so iOS
/// edge-swipe back works.
///
/// Route paths intentionally match the desktop tree so the shared
/// redirect guard, deep links, and `bootstrap.initialLocation` work
/// unchanged. The shared entry routes are passed in (rather than
/// imported from `app.dart`) to keep the import graph acyclic.
List<RouteBase> buildMobileRoutes({required List<RouteBase> entryRoutes}) {
  return [
    ...entryRoutes,
    StatefulShellRoute.indexedStack(
      pageBuilder: (context, state, navigationShell) => CupertinoPage(
        key: state.pageKey,
        child: _MobileTabShell(
          navigationShell: navigationShell,
          tabs: _allMobileTabs,
        ),
      ),
      branches: [
        for (final tab in _allMobileTabs)
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
    // The Set New Passcode frames also drop the tab bar — same
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
      pageBuilder: (context, state) {
        final extra = state.extra;
        return CupertinoPage(
          key: state.pageKey,
          child: MobileSendScreen(
            useRouteSteps: true,
            initialRecipient: extra is String ? extra : null,
          ),
        );
      },
    ),
    GoRoute(
      path: '/send/amount',
      pageBuilder: (context, state) {
        final extra = state.extra;
        final child = extra is MobileSendAmountArgs
            ? MobileSendAmountScreen(args: extra)
            : const MobileSendScreen(useRouteSteps: true);
        return CupertinoPage(key: state.pageKey, child: child);
      },
    ),
    GoRoute(
      path: '/send/review',
      pageBuilder: (context, state) {
        final extra = state.extra;
        final child = extra is MobileSendReviewDraftArgs
            ? MobileSendReviewScreen(args: extra)
            : const MobileSendScreen(useRouteSteps: true);
        return CupertinoPage(key: state.pageKey, child: child);
      },
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
          _ => const MobileSendScreen(useRouteSteps: true),
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
    GoRoute(
      path: '/swap/keystone-sign',
      pageBuilder: (context, state) {
        final extra = state.extra;
        final child = extra is MobileSwapKeystoneSignArgs
            ? MobileSwapKeystoneSignScreen(args: extra)
            : const MobileSwapScreen();
        return CupertinoPage(key: state.pageKey, child: child);
      },
    ),
    GoRoute(
      path: '/pay/review',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: const MobileSwapReviewScreen(payMode: true),
      ),
    ),
    GoRoute(
      path: '/pay/submitted/:intentId',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: MobilePaySubmittedScreen(
          intentId: state.pathParameters['intentId'] ?? '',
        ),
      ),
    ),
    GoRoute(
      path: '/pay',
      pageBuilder: (context, state) {
        final args = state.extra;
        return CupertinoPage(
          key: state.pageKey,
          child: MobilePayScreen(
            preservePreparedComposer:
                args is PayComposerNavigationArgs &&
                args.preservePreparedComposer,
          ),
        );
      },
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
      path: '/home/keystone-shield',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: const MobileKeystoneShieldScreen(),
      ),
    ),
    GoRoute(
      path: '/receive',
      pageBuilder: (context, state) =>
          CupertinoPage(key: state.pageKey, child: const MobileReceiveScreen()),
    ),
    GoRoute(
      path: '/migration',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: const MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.intro,
        ),
      ),
    ),
    GoRoute(
      path: '/migration/intro',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: const MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.intro,
        ),
      ),
    ),
    GoRoute(
      path: '/migration/how-it-works',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: const MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.howItWorks,
        ),
      ),
    ),
    GoRoute(
      path: '/migration/options',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: const MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.options,
        ),
      ),
    ),
    GoRoute(
      path: '/migration/private/review',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: const MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.privateReview,
        ),
      ),
    ),
    GoRoute(
      path: '/migration/private/notifications',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: const MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.notifications,
        ),
      ),
    ),
    GoRoute(
      path: '/migration/private/status',
      pageBuilder: (context, state) {
        final entry = switch (state.extra) {
          MobileIronwoodMigrationStatusEntry value => value,
          rust_sync.OrchardMigrationPrivatePlan plan =>
            MobileIronwoodMigrationStatusEntry(approvedPlan: plan),
          _ => null,
        };
        return CupertinoPage(
          key: state.pageKey,
          child: MobileIronwoodMigrationPrivateStatusScreen(
            approvedPlan: entry?.approvedPlan,
          ),
        );
      },
    ),
    GoRoute(
      path: '/migration/private/keystone/denominations/sign',
      pageBuilder: (context, state) {
        final approvedSchedule = switch (state.extra) {
          List<rust_sync.MigrationScheduledTransfer> schedule => schedule,
          _ => const <rust_sync.MigrationScheduledTransfer>[],
        };
        return CupertinoPage(
          key: state.pageKey,
          child: MobileIronwoodMigrationKeystoneDenominationSignScreen(
            approvedSchedule: approvedSchedule,
          ),
        );
      },
    ),
    GoRoute(
      path: '/migration/private/keystone/batch/sign',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: const MobileIronwoodMigrationKeystoneBatchSignScreen(),
      ),
    ),
    // Immediate migration skips notification setup and opens its review
    // directly from the production option picker.
    GoRoute(
      path: '/migration/fast/review',
      pageBuilder: (context, state) => CupertinoPage(
        key: state.pageKey,
        child: const MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.fastReview,
        ),
      ),
    ),
    GoRoute(
      path: '/about',
      pageBuilder: (context, state) =>
          CupertinoPage(key: state.pageKey, child: const MobileAboutScreen()),
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
const List<_MobileTab> _allMobileTabs = [
  _MobileTab(
    path: '/home',
    item: AppMobileTabItem(iconName: AppIcons.home, label: 'Home'),
    screen: MobileHomeScreen(),
  ),
  _MobileTab(
    path: '/swap',
    item: AppMobileTabItem(iconName: AppIcons.swapArrows, label: 'Swap'),
    screen: MobileSwapScreen(),
  ),
  _MobileTab(
    path: '/activity',
    item: AppMobileTabItem(iconName: AppIcons.history, label: 'Activity'),
    screen: MobileActivityScreen(),
  ),
  _MobileTab(
    path: '/settings',
    item: AppMobileTabItem(iconName: AppIcons.cog, label: 'Settings'),
    screen: MobileSettingsScreen(),
  ),
];

class _MobileTabShell extends ConsumerWidget {
  const _MobileTabShell({required this.navigationShell, required this.tabs});

  final StatefulNavigationShell navigationShell;
  final List<_MobileTab> tabs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final swapFeatureEnabled = ref.watch(swapFeatureEnabledProvider);
    final visibleTabs = [
      for (final tab in tabs)
        if (swapFeatureEnabled || tab.path != '/swap') tab,
    ];
    final currentBranchIndex = navigationShell.currentIndex;
    final currentTab =
        currentBranchIndex >= 0 && currentBranchIndex < tabs.length
        ? tabs[currentBranchIndex]
        : tabs.first;
    final currentVisibleIndex = visibleTabs.indexOf(currentTab);
    final tabBarCurrentIndex = currentVisibleIndex < 0
        ? 0
        : currentVisibleIndex;

    return AppMobileShell(
      body: navigationShell,
      tabBar: AppMobileTabBar(
        items: [for (final tab in visibleTabs) tab.item],
        currentIndex: tabBarCurrentIndex,
        onSelect: (index) {
          final targetTab = visibleTabs[index];
          final targetBranchIndex = tabs.indexOf(targetTab);
          // Record the outgoing tab path so a tab root can offer a
          // "back to where you came from" affordance (the indexedStack
          // shell keeps no tab history of its own). Skip when re-selecting
          // the active tab — that just resets it to root.
          if (targetBranchIndex != currentBranchIndex) {
            ref
                .read(mobilePreviousTabPathProvider.notifier)
                .record(currentTab.path);
          }
          navigationShell.goBranch(
            targetBranchIndex,
            // Re-selecting the active tab resets that tab to its root,
            // the platform-conventional behavior.
            initialLocation: targetBranchIndex == currentBranchIndex,
          );
        },
      ),
    );
  }
}
