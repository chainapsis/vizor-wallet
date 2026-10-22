import 'package:flutter/cupertino.dart' show CupertinoPage;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../feedback/app_review.dart';

import '../../features/accounts/screens/mobile/mobile_accounts_screen.dart';
import '../../features/activity/screens/mobile/mobile_activity_screen.dart';
import '../../features/home/screens/mobile/mobile_home_screen.dart';
import '../../features/home/screens/mobile/mobile_software_shield_screen.dart';
import '../../features/home/screens/mobile/mobile_keystone_shield_screen.dart';
import '../../features/home/screens/mobile/mobile_ledger_shield_screen.dart';
import '../../features/home/widgets/mobile/shield/mobile_shield_backdrop.dart';
import '../../features/migration/screens/mobile/mobile_ironwood_migration_flow_screen.dart';
import '../../features/migration/models/mobile_ironwood_migration_status_entry.dart';
import '../../features/migration/screens/ironwood_migration_flow_screen.dart'
    show
        MobileIronwoodMigrationKeystoneCombinedSignEntry,
        MobileIronwoodMigrationKeystoneCombinedSignScreen,
        MobileIronwoodMigrationKeystoneImmediateSignScreen,
        MobileIronwoodMigrationKeystoneBatchSignScreen,
        MobileIronwoodMigrationKeystoneDenominationSignEntry,
        MobileIronwoodMigrationKeystoneDenominationSignScreen;
import '../../features/onboarding/mobile/mobile_gift_education_screen.dart';
import '../../features/pay/screens/mobile/mobile_pay_screen.dart';
import '../../features/pay/screens/mobile/mobile_pay_submitted_screen.dart';
import '../../features/pay/models/pay_recent_recipients.dart';
import '../../features/payment_links/providers/payment_link_cards_provider.dart';
import '../../features/payment_links/screens/payment_links_screen.dart';
import '../../features/receive/screens/mobile/mobile_receive_screen.dart';
import '../../features/address_book/screens/mobile/mobile_address_book_screen.dart';
import '../../features/activity/screens/mobile/mobile_swap_activity_detail_screen.dart';
import '../../features/activity/screens/mobile/mobile_transaction_status_screen.dart';
import '../../features/send/screens/mobile/mobile_keystone_sign_screen.dart';
import '../../features/send/screens/mobile/mobile_ledger_send_sign_screen.dart';
import '../../features/swap/models/swap_activity_navigation.dart';
import '../../features/swap/screens/mobile/mobile_swap_keystone_sign_screen.dart';
import '../../features/swap/screens/mobile/mobile_swap_ledger_sign_screen.dart';
import '../../features/swap/screens/mobile/mobile_swap_review_screen.dart';
import '../../core/formatting/zec_amount.dart' show parseZecAmount;
import '../../features/send/services/send_flow.dart'
    show
        KeystoneBroadcastArgs,
        LedgerBroadcastArgs,
        SendReviewArgs,
        sanitisePaymentRequestLabel;
import '../../features/send/models/send_prefill_args.dart';
import '../../features/send/screens/mobile/mobile_send_screen.dart';
import '../../features/send/screens/mobile/mobile_send_status_screen.dart';
import '../../rust/api/sync.dart' as rust_sync;
import '../../features/about/screens/mobile/mobile_about_screens.dart';
import '../../features/settings/screens/mobile/mobile_change_passcode_screen.dart';
import '../../features/settings/screens/mobile/mobile_endpoint_screen.dart';
import '../../features/settings/screens/mobile/mobile_explorer_screen.dart';
import '../../features/settings/screens/mobile/mobile_seed_phrase_screen.dart';
import '../../features/settings/screens/mobile/mobile_settings_screen.dart';
import '../../features/settings/screens/mobile/mobile_viewing_key_screen.dart';
import '../../features/swap/screens/mobile/mobile_swap_screen.dart';
import '../../features/voting/screens/mobile/mobile_voting_screens.dart';
import '../config/swap_feature_config.dart';
import '../layout/mobile/app_mobile_shell.dart';
import '../layout/mobile/mobile_adaptive_frame.dart';
import '../layout/mobile/app_mobile_tab_bar.dart';
import '../layout/mobile/mobile_navigation_scope.dart';
import '../layout/mobile/mobile_page_viewport.dart';
import 'mobile_destinations.dart';
import 'route_owned_redirect.dart';
import 'payload_page_key.dart';
import 'mobile_shield_page.dart';

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
    // Root modals cover the full window. The wallet Navigator covers the
    // right pane; each opaque page constrains only its foreground content.
    ShellRoute(
      observers: [RouteOwnedNavigationObserver()],
      pageBuilder: (context, state, child) => NoTransitionPage(
        key: state.pageKey,
        child: MobileAdaptiveFrame(router: GoRouter.of(context), child: child),
      ),
      routes: _walletRoutes(),
    ),
  ];
}

List<RouteBase> _walletRoutes() {
  return [
    StatefulShellRoute.indexedStack(
      pageBuilder: (context, state, navigationShell) => _mobilePage(
        key: state.pageKey,
        constrainContent: false,
        child: MobileShieldBackdropHost(
          child: _MobileTabShell(
            navigationShell: navigationShell,
            tabs: _allMobileTabs,
          ),
        ),
      ),
      branches: [
        for (final tab in _allMobileTabs)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: tab.path,
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: MobilePageViewport(child: tab.screen),
                ),
                // Settings detail screens push over the shell (top-level
                // routes below) so the bottom tab bar is hidden while
                // they're open; nothing extra nests inside a branch.
              ),
              // The Accounts screen lives in the home branch (its
              // Figma frame keeps the tab bar) under its own path.
              if (tab.path == '/home')
                GoRoute(
                  path: '/accounts',
                  pageBuilder: (context, state) => _mobilePage(
                    key: state.pageKey,
                    child: const MobileAccountsScreen(),
                  ),
                ),
            ],
          ),
      ],
    ),
    // Backup, education, and settings detail screens push over the shell so
    // the bottom tab bar is hidden while they're open. Absolute paths
    // match the desktop routes for the shared redirect guard and deep
    // links.
    for (final entry in {
      '/setup/education/intro': GiftEducationPage.intro,
      '/setup/education/address-types': GiftEducationPage.addressTypes,
      '/setup/education/things-to-know': GiftEducationPage.thingsToKnow,
    }.entries)
      GoRoute(
        path: entry.key,
        pageBuilder: (context, state) => _mobilePage(
          key: state.pageKey,
          child: MobileGiftEducationScreen(
            page: entry.value,
            accountUuid: state.extra is String ? state.extra as String : null,
          ),
        ),
      ),
    GoRoute(
      path: '/setup/backup',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: MobileSeedPhraseScreen(
          accountUuid: state.extra is String ? state.extra as String : null,
          showBackupIntro: true,
        ),
      ),
    ),
    GoRoute(
      path: '/settings/seed-phrase',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: MobileSeedPhraseScreen(
          accountUuid: state.extra is String ? state.extra as String : null,
        ),
      ),
    ),
    GoRoute(
      path: '/settings/viewing-key',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: MobileViewingKeyScreen(
          accountUuid: state.extra is String ? state.extra as String : null,
        ),
      ),
    ),
    GoRoute(
      path: '/settings/address-book',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: const MobileAddressBookScreen(),
      ),
    ),
    GoRoute(
      path: '/settings/endpoint',
      pageBuilder: (context, state) =>
          _mobilePage(key: state.pageKey, child: const MobileEndpointScreen()),
    ),
    GoRoute(
      path: '/settings/explorer',
      pageBuilder: (context, state) =>
          _mobilePage(key: state.pageKey, child: const MobileExplorerScreen()),
    ),
    // The Set New Passcode frames also drop the tab bar — same
    // full-screen push pattern.
    GoRoute(
      path: '/settings/change-password',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: const MobileChangePasscodeScreen(),
      ),
    ),
    GoRoute(
      path: '/send',
      pageBuilder: (context, state) {
        final extra = state.extra;
        // A ZIP-321 payment URI arrives as SendPrefillArgs (address + amount +
        // memo); other callers still pass a bare recipient string. Unpack the
        // request opens on the amount step even when it asks the payer to
        // supply the amount. Bare recipient strings still open address entry.
        final prefill = extra is SendPrefillArgs ? extra : null;
        return _mobilePage(
          // `_MobileSendScreenState` seeds every `initial*` field in
          // `initState` and has no `didUpdateWidget`, so the page has to
          // change identity with the prefill or a second request answered
          // onto `/send` keeps the first request's recipient.
          key: payloadScopedPageKey(state, prefill?.id),
          child: MobileSendScreen(
            useRouteSteps: true,
            initialRecipient:
                prefill?.address ?? (extra is String ? extra : null),
            initialAmountStep: prefill?.source == kPaymentUriPrefillSource,
            initialAmount: prefill?.amountText,
            initialMemo: prefill?.memoText,
            preserveInitialMemoWhitespace: prefill?.preserveMemoText ?? false,
            // Editing a payment request keeps the request's framing on the
            // review step; a hand-composed send has none of this.
            isPaymentRequest: prefill?.source == kPaymentUriPrefillSource,
            paymentRequestLabel: prefill?.source == kPaymentUriPrefillSource
                ? sanitisePaymentRequestLabel(prefill?.label)
                : null,
            requestedAmountZatoshi: prefill?.source == kPaymentUriPrefillSource
                ? parseZecAmount(prefill?.amountText ?? '')
                : null,
          ),
        );
      },
    ),
    GoRoute(
      path: '/payment-links',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: PaymentLinksScreen(
          initialReceivedCardAddress: state.uri.queryParameters['received'],
          initialCards: state.extra is PaymentLinkCardsSnapshot
              ? state.extra! as PaymentLinkCardsSnapshot
              : null,
        ),
      ),
    ),
    GoRoute(
      path: '/send/amount',
      pageBuilder: (context, state) {
        final extra = state.extra;
        final child = extra is MobileSendAmountArgs
            ? MobileSendAmountScreen(args: extra)
            : const MobileSendScreen(useRouteSteps: true);
        return _mobilePage(key: state.pageKey, child: child);
      },
    ),
    GoRoute(
      path: '/send/review',
      pageBuilder: (context, state) {
        final extra = state.extra;
        final draft = extra is MobileSendReviewDraftArgs ? extra : null;
        return _mobilePage(
          // `MobileSendReviewScreen` is a keyless pass-through to the same
          // `MobileSendScreen` state, so the draft's identity is what keeps a
          // second request from being confirmed against the first one.
          key: payloadScopedPageKey(state, draft?.sendFlowId),
          child: draft != null
              ? MobileSendReviewScreen(args: draft)
              : const MobileSendScreen(useRouteSteps: true),
        );
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
          LedgerBroadcastArgs() => MobileSendStatusScreen(
            args: extra.reviewArgs,
            ledger: extra,
          ),
          SendReviewArgs() => MobileSendStatusScreen(args: extra),
          _ => const MobileSendScreen(useRouteSteps: true),
        };
        return _mobilePage(key: state.pageKey, child: child);
      },
    ),
    GoRoute(
      path: '/swap/review',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: const MobileSwapReviewScreen(),
      ),
    ),
    GoRoute(
      path: '/swap/keystone-sign',
      redirect: (_, state) =>
          state.extra is MobileSwapKeystoneSignArgs ? null : '/swap',
      pageBuilder: (context, state) {
        final child = MobileSwapKeystoneSignScreen(
          args: state.extra as MobileSwapKeystoneSignArgs,
        );
        return _mobilePage(key: state.pageKey, child: child);
      },
    ),
    GoRoute(
      path: '/swap/ledger-sign',
      redirect: (_, state) =>
          state.extra is MobileSwapLedgerSignArgs ? null : '/swap',
      pageBuilder: (context, state) {
        final child = MobileSwapLedgerSignScreen(
          args: state.extra as MobileSwapLedgerSignArgs,
        );
        return CustomTransitionPage(
          key: state.pageKey,
          child: child,
          opaque: false,
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
        );
      },
    ),
    GoRoute(
      path: '/pay/review',
      pageBuilder: (context, state) {
        final extra = state.extra;
        return _mobilePage(
          key: state.pageKey,
          child: MobileSwapReviewScreen(
            payMode: true,
            recipientSelection: extra is PayRecipientSelection ? extra : null,
          ),
        );
      },
    ),
    GoRoute(
      path: '/pay/submitted/:intentId',
      pageBuilder: (context, state) => _mobilePage(
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
        return _mobilePage(
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
        return _mobilePage(
          key: state.pageKey,
          child: MobileTransactionStatusScreen(args: args),
        );
      },
    ),
    GoRoute(
      path: '/activity/swap/:swapId',
      pageBuilder: (context, state) {
        final swapId = state.pathParameters['swapId'] ?? '';
        return _mobilePage(
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
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: MobileKeystoneSignScreen(args: state.extra! as SendReviewArgs),
      ),
    ),
    GoRoute(
      path: '/send/ledger-sign',
      pageBuilder: (context, state) {
        final extra = state.extra;
        final child = extra is SendReviewArgs
            ? MobileLedgerSendSignScreen(args: extra)
            : const MobileSendScreen(useRouteSteps: true);
        return CustomTransitionPage(
          key: state.pageKey,
          child: child,
          opaque: false,
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
        );
      },
    ),
    GoRoute(
      path: '/home/shield',
      pageBuilder: (context, state) => MobileShieldPage(
        key: state.pageKey,
        child: MobileSoftwareShieldScreen(
          backdrop: state.extra is MobileShieldBackdrop
              ? state.extra as MobileShieldBackdrop
              : null,
        ),
      ),
    ),
    GoRoute(
      path: '/home/keystone-shield',
      pageBuilder: (context, state) => MobileShieldPage(
        key: state.pageKey,
        child: MobileKeystoneShieldScreen(
          backdrop: state.extra is MobileShieldBackdrop
              ? state.extra as MobileShieldBackdrop
              : null,
        ),
      ),
    ),
    GoRoute(
      path: '/voting',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: const MobileVotingAccountGuard(child: MobileVotingPollsScreen()),
      ),
    ),
    GoRoute(
      path: '/voting/poll/:roundId',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: MobileVotingAccountGuard(
          child: MobileVotingProposalDetailScreen(
            roundId: state.pathParameters['roundId'] ?? '',
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/voting/poll/:roundId/review',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: MobileVotingAccountGuard(
          child: MobileVotingReviewScreen(
            roundId: state.pathParameters['roundId'] ?? '',
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/voting/poll/:roundId/status',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: MobileVotingAccountGuard(
          child: MobileVotingStatusScreen(
            roundId: state.pathParameters['roundId'] ?? '',
            accountUuid: state.uri.queryParameters['account'],
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/voting/poll/:roundId/submitted',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: MobileVotingAccountGuard(
          child: MobileVotingSubmissionConfirmationScreen(
            roundId: state.pathParameters['roundId'] ?? '',
            accountUuid: state.uri.queryParameters['account'],
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/voting/poll/:roundId/results',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: MobileVotingAccountGuard(
          child: MobileVotingResultsScreen(
            roundId: state.pathParameters['roundId'] ?? '',
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/home/ledger-shield',
      pageBuilder: (context, state) => MobileShieldPage(
        key: state.pageKey,
        child: MobileLedgerShieldScreen(
          backdrop: state.extra is MobileShieldBackdrop
              ? state.extra as MobileShieldBackdrop
              : null,
        ),
      ),
    ),
    GoRoute(
      path: '/receive',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        maxContentWidth: MobileReceiveScreen.maximumWideWidth,
        child: const MobileReceiveScreen(),
      ),
    ),
    GoRoute(
      path: '/migration',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: const MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.intro,
        ),
      ),
    ),
    GoRoute(
      path: '/migration/intro',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: const MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.intro,
        ),
      ),
    ),
    GoRoute(
      path: '/migration/how-it-works',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: const MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.howItWorks,
        ),
      ),
    ),
    GoRoute(
      path: '/migration/options',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: const MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.options,
        ),
      ),
    ),
    GoRoute(
      path: '/migration/private/notifications',
      redirect: _redirectUnsupportedPrivateMigration,
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.notifications,
          previewPrivatePlan: switch (state.extra) {
            rust_sync.OrchardMigrationPrivatePlan plan => plan,
            _ => null,
          },
        ),
      ),
    ),
    GoRoute(
      path: '/migration/private/start',
      redirect: _redirectUnsupportedPrivateMigration,
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: MobileIronwoodMigrationStartScreen(
          approvedPlan: switch (state.extra) {
            rust_sync.OrchardMigrationPrivatePlan plan => plan,
            _ => null,
          },
        ),
      ),
    ),
    // Completion has its own destination so home does not have to route
    // through the status screen, whose entry refresh renders a progress
    // surface before the finished phase resolves.
    GoRoute(
      path: '/migration/complete',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: const MobileIronwoodMigrationCompleteScreen(),
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
        return _mobilePage(
          key: state.pageKey,
          child: MobileIronwoodMigrationPrivateStatusScreen(
            approvedPlan: entry?.approvedPlan,
          ),
        );
      },
    ),
    GoRoute(
      path: '/migration/private/schedule',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: const MobileIronwoodMigrationScheduleScreen(),
      ),
    ),
    GoRoute(
      path: '/migration/private/preparation-schedule',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: const MobileIronwoodMigrationPreparationScheduleScreen(),
      ),
    ),
    GoRoute(
      path: '/migration/private/keystone/sign',
      pageBuilder: (context, state) {
        final entry = switch (state.extra) {
          MobileIronwoodMigrationKeystoneCombinedSignEntry value => value,
          _ => null,
        };
        final approvedSchedule = switch (state.extra) {
          List<rust_sync.MigrationScheduledTransfer> schedule => schedule,
          _ => entry?.approvedSchedule ?? const [],
        };
        return _mobilePage(
          key: state.pageKey,
          child: MobileIronwoodMigrationKeystoneCombinedSignScreen(
            approvedSchedule: approvedSchedule,
            initialRequest: entry?.request,
            initialAccountUuid: entry?.accountUuid,
          ),
        );
      },
    ),
    GoRoute(
      path: '/migration/private/keystone/denominations/sign',
      pageBuilder: (context, state) {
        final entry = switch (state.extra) {
          MobileIronwoodMigrationKeystoneDenominationSignEntry value => value,
          _ => null,
        };
        final approvedSchedule = switch (state.extra) {
          List<rust_sync.MigrationScheduledTransfer> schedule => schedule,
          _ => entry?.approvedSchedule ?? const [],
        };
        return _mobilePage(
          key: state.pageKey,
          child: MobileIronwoodMigrationKeystoneDenominationSignScreen(
            approvedSchedule: approvedSchedule,
            initialRequest: entry?.request,
            initialAccountUuid: entry?.accountUuid,
          ),
        );
      },
    ),
    GoRoute(
      path: '/migration/private/keystone/batch/sign',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: const MobileIronwoodMigrationKeystoneBatchSignScreen(),
      ),
    ),
    GoRoute(
      path: '/migration/immediate/keystone/sign',
      redirect: (_, state) =>
          state.extra is rust_sync.OrchardMigrationImmediatePlan
          ? null
          : '/migration/fast/review',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: MobileIronwoodMigrationKeystoneImmediateSignScreen(
          approvedPlan: state.extra! as rust_sync.OrchardMigrationImmediatePlan,
        ),
      ),
    ),
    // Immediate migration skips notification setup and opens its review
    // directly from the production option picker.
    GoRoute(
      path: '/migration/fast/review',
      pageBuilder: (context, state) => _mobilePage(
        key: state.pageKey,
        child: const MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.fastReview,
        ),
      ),
    ),
    GoRoute(
      path: '/about',
      pageBuilder: (context, state) =>
          _mobilePage(key: state.pageKey, child: const MobileAboutScreen()),
    ),
  ];
}

CupertinoPage<dynamic> _mobilePage({
  required LocalKey key,
  required Widget child,
  bool constrainContent = true,
  double? maxContentWidth,
}) => CupertinoPage(
  key: key,
  child: MobilePageViewport(
    constrainContent: constrainContent,
    maxContentWidth: maxContentWidth,
    child: child,
  ),
);

String? _redirectUnsupportedPrivateMigration(
  BuildContext context,
  GoRouterState state,
) => supportsPrivateMobileIronwoodMigration() ? null : '/migration/fast/review';

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
final List<_MobileTab> _allMobileTabs = [
  for (var i = 0; i < mobileDestinations.length; i++)
    _MobileTab(
      path: mobileDestinations[i].path,
      item: mobileDestinations[i].item,
      screen: switch (mobileDestinations[i].path) {
        '/home' => const MobileHomeScreen(),
        '/swap' => const MobileSwapScreen(),
        '/activity' => const MobileActivityScreen(),
        '/settings' => const MobileSettingsScreen(),
        _ => throw StateError('Missing mobile destination screen'),
      },
    ),
];

class _MobileTabShell extends ConsumerStatefulWidget {
  const _MobileTabShell({required this.navigationShell, required this.tabs});

  final StatefulNavigationShell navigationShell;
  final List<_MobileTab> tabs;

  @override
  ConsumerState<_MobileTabShell> createState() => _MobileTabShellState();
}

class _MobileTabShellState extends ConsumerState<_MobileTabShell> {
  MobileBranchNavigation? _navigation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navigation = MobileNavigationScope.maybeOf(context)?.navigation;
    if (!identical(navigation, _navigation)) {
      _navigation?.detach(this);
      _navigation = navigation;
    }
    _navigation?.attach(this, _selectPath);
  }

  void _selectPath(String path) {
    if (!mounted) return;
    final index = widget.tabs.indexWhere((tab) => tab.path == path);
    if (index < 0) return;
    if (index != widget.navigationShell.currentIndex && path != '/home') {
      expectAppReviewVisit(ref, path);
    }
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  void dispose() {
    _navigation?.detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    final navigationShell = widget.navigationShell;

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
        axis:
            MobileNavigationScope.maybeOf(context)?.mode ==
                MobileNavigationMode.systemSideTabs
            ? Axis.vertical
            : Axis.horizontal,
        items: [for (final tab in visibleTabs) tab.item],
        currentIndex: tabBarCurrentIndex,
        onSelect: (index) {
          _selectPath(visibleTabs[index].path);
        },
      ),
    );
  }
}
