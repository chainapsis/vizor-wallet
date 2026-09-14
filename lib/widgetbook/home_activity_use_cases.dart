// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/config/swap_feature_config.dart';
import '../src/core/layout/app_layout.dart';
import '../src/core/layout/mobile/app_mobile_shell.dart';
import '../src/core/layout/mobile/app_mobile_tab_bar.dart';
import '../src/core/privacy/privacy_mask.dart';
import '../src/core/profile_pictures.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_button.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/app_toast.dart';
import '../src/core/widgets/review_list_row.dart';
import '../src/features/accounts/widgets/mobile/mobile_accounts_sheet.dart';
import '../src/features/activity/activity_row_mapper.dart';
import '../src/features/activity/gift_card_activity_index.dart';
import '../src/features/activity/models/activity_row_data.dart';
import '../src/features/activity/screens/activity_screen.dart';
import '../src/features/activity/screens/activity_transaction_status_screen.dart';
import '../src/features/activity/screens/mobile/mobile_activity_screen.dart';
import '../src/features/activity/screens/mobile/mobile_swap_activity_detail_screen.dart';
import '../src/features/activity/screens/mobile/mobile_transaction_status_screen.dart';
import '../src/features/activity/screens/swap_activity_detail_screen.dart';
import '../src/features/activity/swap_activity_row_items_provider.dart';
import '../src/features/activity/swap_activity_row_mapper.dart';
import '../src/features/activity/widgets/activity_feed.dart';
import '../src/features/address_book/models/address_book_contact.dart';
import '../src/features/address_book/providers/address_book_provider.dart';
import '../src/features/home/screens/home_screen.dart';
import '../src/features/home/services/transparent_shielding_service.dart';
import '../src/features/home/screens/mobile/mobile_home_screen.dart';
import '../src/features/home/screens/mobile/mobile_keystone_shield_screen.dart';
import '../src/features/home/widgets/keystone_shield_signing_overlay.dart';
import '../src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import '../src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import '../src/features/payment_links/models/vizor_payment_link.dart';
import '../src/features/send/services/sapling_params.dart';
import '../src/features/send/widgets/send_recipient_resolver.dart';
import '../src/features/swap/models/swap_models.dart';
import '../src/features/swap/providers/swap_activity_store.dart';
import '../src/features/swap/providers/swap_state_provider.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/migration_send_gate_provider.dart';
import '../src/providers/network_privacy_provider.dart';
import '../src/providers/privacy_mode_provider.dart';
import '../src/providers/receive_address_provider.dart';
import '../src/providers/sync_failure.dart';
import '../src/providers/sync_keep_awake_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/providers/voting/voting_config_source_provider.dart';
import '../src/providers/voting/voting_home_entry_provider.dart';
import '../src/providers/wallet_provider.dart';
import '../src/providers/zec_price_change_provider.dart';
import '../src/rust/api/sync.dart' as rust_sync;
import 'support/wb_fake_scanner_platform.dart';
import 'support/wb_layout.dart';
import 'support/wb_sidebar.dart';

/// Deterministic Home fixtures for the gallery's knob axes.
///
/// The desktop and mobile screens are the real `HomeScreen` /
/// `MobileHomeScreen`, driven only through provider overrides; every value
/// here is a constant so a preview never reads storage, Rust, or the clock.

// --- Axes ------------------------------------------------------------------

/// `walletProvider` state the pane branches on (spinner / error text / pane).
enum HomeWalletState { data, loading, error }

enum HomeBalanceAmount { zero, funded, large, fundedTransparent }

/// What the recent-activity list holds. One axis: the row count and the
/// Gift Card rows are the same "what is in the list" question.
enum HomeActivityFeed { empty, oneRow, threeRows, fiveRows, giftCards }

/// Wallet-scan progress. `importingUnnamed` is the importing screen for an
/// account with no name — it only differs while importing, so it rides this
/// axis instead of adding an account axis that does nothing elsewhere.
enum HomeSyncProgress {
  synced,
  importingStarted,
  importingPartway,
  importingNearlyDone,
  importingUnnamed,
}

/// Route the wallet syncs over. `torConnecting` also forces the preflight
/// phase, since that is the only state in which the route is visible.
enum HomeNetworkRoute { direct, torConnecting, torBlocked }

/// Notice card source, including which action the sync failure offers. Tor
/// failures are the `HomeNetworkRoute` axis; a sync-failure notice replaces
/// the Tor failure, so pick one or the other.
enum HomeNoticeKind {
  none,
  passwordRotation,
  syncFailure,
  syncFailureEndpointSettings,
}

/// Shield action on the transparent strip. Only meaningful when the balance
/// carries a transparent amount.
enum HomeShieldAction { enabled, hidden }

/// Window box the desktop screen is framed in, so the empty-activity
/// illustration crosses its compact threshold.
///
/// [compact] is 1080×560, deliberately *below* the app's 1080×720 minimum
/// (`app_layout.dart`): `_HomeDesktopEmptyActivity` branches on the pane's own
/// `maxHeight < 300`, which the preview only reaches by shortening the window.
/// The sub-minimum size is the point of the option — do not "correct" it to
/// 720.
enum HomeWindowHeight { full, compact }

/// ZEC price display: the 24h change badge, plus the case where no price is
/// available at all and the fiat line goes with it.
enum HomePriceChange { up, down, flat, hidden, priceUnavailable }

enum HomeAccountKind { software, keystone }

enum HomeMobileFrame { phone, unconstrained }

extension on HomeSyncProgress {
  bool get isImporting => this != HomeSyncProgress.synced;

  double get percentage => switch (this) {
    HomeSyncProgress.synced => 1,
    HomeSyncProgress.importingStarted => 0,
    HomeSyncProgress.importingPartway => 0.34,
    HomeSyncProgress.importingNearlyDone => 0.99,
    HomeSyncProgress.importingUnnamed => 0.34,
  };
}

// --- Desktop ---------------------------------------------------------------

/// `HomeScreen` in a minimal router, with every axis of the desktop home
/// surface (balance card, transparent strip, notice card, activity card,
/// importing screen) driven by providers.
Widget homeDesktopFixture({
  HomeWalletState wallet = HomeWalletState.data,
  HomeBalanceAmount balance = HomeBalanceAmount.funded,
  HomeActivityFeed activity = HomeActivityFeed.threeRows,
  HomeSyncProgress sync = HomeSyncProgress.synced,
  HomeNetworkRoute network = HomeNetworkRoute.direct,
  HomeNoticeKind notice = HomeNoticeKind.none,
  HomeShieldAction shieldAction = HomeShieldAction.enabled,
  HomeWindowHeight windowHeight = HomeWindowHeight.full,
  HomePriceChange priceChange = HomePriceChange.up,
  bool payInUsdc = false,
  bool privacyMode = false,
}) {
  final accountState = _homeAccountState(
    HomeAccountKind.software,
    named: sync != HomeSyncProgress.importingUnnamed,
  );
  const harness = _HomeDesktopHarness();
  return ProviderScope(
    overrides: [
      swapStateProvider.overrideWith(_HomePayNotifier.new),
      ..._homeOverrides(
        accountState: accountState,
        balance: balance,
        activity: activity,
        sync: sync,
        network: network,
        notice: notice,
        shieldAction: shieldAction,
        priceChange: priceChange,
        swapEnabled: payInUsdc,
        privacyMode: privacyMode,
      ),
      if (wallet != HomeWalletState.data)
        walletProvider.overrideWith(() => _HomeWalletNotifier(wallet)),
      ironwoodHomeBalancePresentationProvider.overrideWithValue(
        IronwoodHomeBalancePresentationMode.allShielded,
      ),
      ironwoodMigrationCoordinatorProvider.overrideWith(
        _HomeMigrationCoordinator.new,
      ),
    ],
    child: windowHeight == HomeWindowHeight.compact
        ? const Center(
            child: _HomeDesktopHarness(
              windowSize: Size(kWbDesktopWindowWidth, 560),
            ),
          )
        : harness,
  );
}

// --- Mobile ----------------------------------------------------------------

/// `MobileHomeScreen` inside the mobile shell and a phone frame.
Widget homeMobileFixture({
  HomeBalanceAmount balance = HomeBalanceAmount.funded,
  HomeActivityFeed activity = HomeActivityFeed.threeRows,
  HomeSyncProgress sync = HomeSyncProgress.synced,
  HomeNetworkRoute network = HomeNetworkRoute.direct,
  HomeAccountKind account = HomeAccountKind.software,
  HomeMobileFrame frame = HomeMobileFrame.phone,
  HomePriceChange priceChange = HomePriceChange.up,
  bool payEntry = true,
  bool privacyMode = false,
  bool votingEntryVisible = true,
  bool sendBlockedByMigration = false,
  bool accountsSheetOpen = false,
  bool keepAwakePromptOpen = false,
}) {
  final accountState = _homeAccountState(account);
  return ProviderScope(
    overrides: [
      swapStateProvider.overrideWith(_HomePayNotifier.new),
      ..._homeOverrides(
        accountState: accountState,
        balance: balance,
        activity: activity,
        sync: sync,
        network: network,
        notice: HomeNoticeKind.none,
        shieldAction: HomeShieldAction.enabled,
        priceChange: priceChange,
        swapEnabled: payEntry,
        privacyMode: privacyMode,
        keepAwakePromptPending: keepAwakePromptOpen,
      ),
      // The real notifier writes the "prompt seen" flag to secure storage the
      // moment the sheet opens, which would also make the preview one-shot.
      syncKeepAwakeProvider.overrideWith(_HomeSyncKeepAwakeNotifier.new),
      votingHomeEntryVisibleProvider.overrideWithValue(votingEntryVisible),
      votingHomeRefreshActionProvider.overrideWithValue(() async {}),
      // The voting entry listens to the config source above its own
      // visibility guard, so the notifier is always built — stub its store
      // instead of letting it reach secure storage.
      votingConfigSourceStoreProvider.overrideWithValue(
        const _HomeVotingConfigSourceStore(),
      ),
      migrationSendGateProvider.overrideWithValue(sendBlockedByMigration),
    ],
    child: _HomeMobileFrame(
      constrainToDesignSize: frame == HomeMobileFrame.phone,
      child: _HomeMobileHarness(accountsSheetOpen: accountsSheetOpen),
    ),
  );
}

// --- Shared overrides ------------------------------------------------------

List<Override> _homeOverrides({
  required AccountState accountState,
  required HomeBalanceAmount balance,
  required HomeActivityFeed activity,
  required HomeSyncProgress sync,
  required HomeNetworkRoute network,
  required HomeNoticeKind notice,
  required HomeShieldAction shieldAction,
  required HomePriceChange priceChange,
  required bool swapEnabled,
  required bool privacyMode,
  List<SwapActivityRowItem> swapRowItems = const [],
  GiftCardActivityIndex? giftCardIndex,
  bool keepAwakePromptPending = false,
}) {
  final accountUuid = accountState.activeAccountUuid;
  final marketData = priceChange == HomePriceChange.priceUnavailable
      ? null
      : ZecMarketData(
          usdPrice: 8.397,
          change24hPct: _priceChangePct(priceChange),
        );
  return [
    appLayoutProvider.overrideWith(_HomeNoOpLayoutNotifier.new),
    wbSidebarActions,
    wbPostMigrationState,
    receiveAddressServiceProvider.overrideWithValue(
      const _HomeReceiveAddressService(),
    ),
    transparentShieldingRunnerProvider.overrideWithValue(
      ({required ref, required accountUuid, logContext = 'Preview'}) async =>
          _homeShieldPendingResult,
    ),
    appBootstrapProvider.overrideWithValue(
      _homeBootstrap(
        accountState,
        privacyModeEnabled: privacyMode,
        passwordRotationRecoveryFailed:
            notice == HomeNoticeKind.passwordRotation,
      ),
    ),
    accountProvider.overrideWith(() => _HomeAccountNotifier(accountState)),
    syncProvider.overrideWith(
      () => _HomeSyncNotifier(
        _keepAwakeEligibleSyncState(
          _homeSyncState(
            accountUuid: accountUuid,
            balance: balance,
            activity: activity,
            sync: sync,
            network: network,
            notice: notice,
            shieldAction: shieldAction,
          ),
          pending: keepAwakePromptPending,
        ),
      ),
    ),
    privacyModeProvider.overrideWith(_HomePrivacyModeNotifier.new),
    networkPrivacyProvider.overrideWith(
      () => _HomeNetworkPrivacyNotifier(_networkPrivacyState(network)),
    ),
    zecMarketDataSourceProvider.overrideWithValue(
      _HomeZecMarketDataSource(marketData),
    ),
    zecHomeUsdUnitPriceProvider.overrideWithValue(marketData?.usdPrice),
    zecPriceChange24hPctProvider.overrideWithValue(marketData?.change24hPct),
    swapFeatureEnabledProvider.overrideWithValue(swapEnabled),
    // The periodic swap-status refresh reads secure storage; an in-memory
    // store keeps it inert instead of reaching a platform channel.
    swapActivityStoreProvider.overrideWithValue(
      const _ActivityNoopSwapActivityStore(),
    ),
    swapActivityRowItemsProvider.overrideWith((ref, accountUuid) async {
      return swapRowItems;
    }),
    giftCardActivityIndexProvider.overrideWith(
      (ref, accountUuid) async =>
          giftCardIndex ??
          (activity == HomeActivityFeed.giftCards
              ? _homeGiftCardActivityIndex()
              : GiftCardActivityIndex.empty),
    ),
    ironwoodHomeMigrationCtaProvider.overrideWith(
      (ref) async => const IronwoodHomeMigrationCtaState.hidden(),
    ),
    ironwoodHomeMigrationPresentationProvider.overrideWithValue(
      const IronwoodHomeMigrationCtaState.hidden(),
    ),
    ironwoodMigrationAnnouncementProvider.overrideWith(
      (ref) async => const IronwoodMigrationAnnouncementState.hidden(),
    ),
    // Mobile Home also checks completion on mount, independently of the CTA.
    ironwoodMigrationCompletionProvider.overrideWith(
      (ref) async => const IronwoodMigrationCompletionState.hidden(),
    ),
  ];
}

double? _priceChangePct(HomePriceChange change) => switch (change) {
  HomePriceChange.up => 13.12,
  HomePriceChange.down => -8.42,
  HomePriceChange.flat => 0,
  HomePriceChange.hidden || HomePriceChange.priceUnavailable => null,
};

/// Start of the run the keep-awake prompt measures against. Fixed and far
/// past, so the production estimator's `DateTime.now()` always lands well over
/// the one-minute prompt threshold.
final _homeKeepAwakeSyncStartedAt = DateTime.utc(2026, 5, 14, 9);

/// Widens [state] into a run the keep-awake prompt is eligible for: syncing,
/// part-way, with known heights more than [kSyncKeepAwakeNearTipBlockGap]
/// apart so the near-tip exclusion does not fire.
SyncState _keepAwakeEligibleSyncState(
  SyncState state, {
  required bool pending,
}) {
  if (!pending) return state;
  return state.copyWith(
    isSyncing: true,
    percentage: 0.2,
    scannedHeight: 2_400_000,
    chainTipHeight: 2_800_000,
    lastSyncStartedAt: _homeKeepAwakeSyncStartedAt,
  );
}

NetworkPrivacyState _networkPrivacyState(HomeNetworkRoute network) {
  return switch (network) {
    HomeNetworkRoute.direct => const NetworkPrivacyState.off(),
    HomeNetworkRoute.torConnecting => const NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.connecting,
    ),
    HomeNetworkRoute.torBlocked => const NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.failed,
      error: 'Preview Tor bootstrap failure',
    ),
  };
}

// --- Fixture state ---------------------------------------------------------

const _homeAccountUuid = 'home-gallery-account';
const _homeKeystoneUuid = 'home-gallery-keystone-account';

AccountState _homeAccountState(HomeAccountKind kind, {bool named = true}) {
  if (kind == HomeAccountKind.keystone) {
    return const AccountState(
      accounts: [
        AccountInfo(
          uuid: _homeKeystoneUuid,
          name: 'Keystone Vault',
          order: 0,
          isHardware: true,
          profilePictureId: 'pfp-02',
        ),
      ],
      activeAccountUuid: _homeKeystoneUuid,
      activeAddress: 'u1widgetbookkeystoneaddress',
    );
  }
  return AccountState(
    accounts: [
      AccountInfo(
        uuid: _homeAccountUuid,
        name: named ? 'Account Name' : '',
        order: 0,
        isSeedAnchor: true,
        profilePictureId: kDefaultProfilePictureId,
      ),
      const AccountInfo(
        uuid: 'home-gallery-account-2',
        name: 'Account Name',
        order: 1,
        profilePictureId: 'pfp-01',
      ),
    ],
    activeAccountUuid: _homeAccountUuid,
    activeAddress: 'u1widgetbookhomeaddress',
  );
}

AppBootstrapState _homeBootstrap(
  AccountState accountState, {
  required bool privacyModeEnabled,
  required bool passwordRotationRecoveryFailed,
}) {
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: accountState,
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: defaultRpcEndpointConfig('main'),
    themeMode: ThemeMode.system,
    privacyModeEnabled: privacyModeEnabled,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: passwordRotationRecoveryFailed,
  );
}

SyncState _homeSyncState({
  required String? accountUuid,
  required HomeBalanceAmount balance,
  required HomeActivityFeed activity,
  required HomeSyncProgress sync,
  required HomeNetworkRoute network,
  required HomeNoticeKind notice,
  required HomeShieldAction shieldAction,
}) {
  var state = sync.isImporting
      // No account-scoped data yet is what both home screens read as
      // "we are still importing this wallet".
      ? SyncState(
          accountUuid: accountUuid,
          isSyncing: true,
          percentage: sync.percentage,
        )
      : _homeSyncedState(
          accountUuid: accountUuid,
          balance: balance,
          activity: activity,
          shieldAction: shieldAction,
        );

  state = switch (network) {
    HomeNetworkRoute.direct => state,
    // Preflight has no progress of its own, so an importing wallet keeps the
    // percentage the Sync axis chose; only a synced wallet needs a stand-in.
    HomeNetworkRoute.torConnecting => state.copyWith(
      isSyncing: true,
      phase: kSyncPhasePreflight,
      percentage: sync.isImporting ? sync.percentage : 0.01,
    ),
    HomeNetworkRoute.torBlocked => state.copyWith(
      failure: classifySyncFailure(
        'network: network privacy blocked lightwalletd: Tor connection failed',
      ),
    ),
  };

  if (notice == HomeNoticeKind.syncFailure ||
      notice == HomeNoticeKind.syncFailureEndpointSettings) {
    state = state.copyWith(
      failure: SyncFailure(
        kind: SyncFailureKind.network,
        rawMessage: 'network failed',
        userMessage: 'Network connection lost.',
        showSettingsAction:
            notice == HomeNoticeKind.syncFailureEndpointSettings,
      ),
    );
  }
  return state;
}

SyncState _homeSyncedState({
  required String? accountUuid,
  required HomeBalanceAmount balance,
  required HomeActivityFeed activity,
  required HomeShieldAction shieldAction,
}) {
  final orchard = switch (balance) {
    HomeBalanceAmount.zero => BigInt.zero,
    HomeBalanceAmount.funded ||
    HomeBalanceAmount.fundedTransparent => BigInt.from(14_323_000_000),
    HomeBalanceAmount.large => BigInt.from(1_234_567_890_000),
  };
  final ironwood = balance == HomeBalanceAmount.large
      ? BigInt.from(5_240_000_000)
      : BigInt.zero;
  final transparent = balance == HomeBalanceAmount.fundedTransparent
      ? BigInt.from(1_412_000_000)
      : BigInt.zero;
  return SyncState(
    accountUuid: accountUuid,
    hasAccountScopedData: true,
    isSyncComplete: true,
    percentage: 1,
    scannedHeight: 3_428_143,
    chainTipHeight: 3_428_143,
    orchardBalance: orchard,
    ironwoodBalance: ironwood,
    transparentBalance: transparent,
    canShieldTransparentBalance:
        transparent > BigInt.zero && shieldAction == HomeShieldAction.enabled,
    spendableBalance: orchard + ironwood,
    totalBalance: orchard + ironwood + transparent,
    recentTransactions: _homeTransactions(activity),
  );
}

List<rust_sync.TransactionInfo> _homeTransactions(HomeActivityFeed activity) {
  return switch (activity) {
    HomeActivityFeed.empty => const [],
    HomeActivityFeed.oneRow => [_homeTx(1)],
    HomeActivityFeed.threeRows => [_homeTx(1), _homeTx(2), _homeTx(3)],
    HomeActivityFeed.fiveRows => [
      _homeTx(1),
      _homeTx(2),
      _homeTx(3),
      _homeTx(4),
      _homeTx(5),
    ],
    HomeActivityFeed.giftCards => [
      _homeGiftCardTx(txidHex: _homeRedeemedGiftCardTxid, kind: 'received'),
      _homeGiftCardTx(txidHex: _homeCreatedGiftCardTxid, kind: 'sent'),
    ],
  };
}

rust_sync.TransactionInfo _homeTx(int index) {
  final seconds = BigInt.from(1800000000 + index);
  return rust_sync.TransactionInfo(
    txidHex: 'home-gallery-tx-$index',
    minedHeight: BigInt.from(1000 + index),
    expiredUnmined: false,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    blockTime: seconds,
    isTransparent: false,
    txKind: index.isEven ? 'sent' : 'received',
    displayAmount: BigInt.from(index) * BigInt.from(100000000),
    displayPool: 'shielded',
    createdTime: seconds,
  );
}

const _homeCreatedGiftCardTxid = 'home-gallery-gift-card-created';
const _homeRedeemedGiftCardTxid = 'home-gallery-gift-card-redeemed';

rust_sync.TransactionInfo _homeGiftCardTx({
  required String txidHex,
  required String kind,
}) {
  final timestamp = BigInt.from(kind == 'sent' ? 1800000010 : 1800000011);
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: BigInt.from(2000),
    expiredUnmined: false,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    blockTime: timestamp,
    isTransparent: false,
    txKind: kind,
    displayAmount: BigInt.from(3_110_000_000),
    displayPool: 'shielded',
    createdTime: timestamp,
  );
}

GiftCardActivityIndex _homeGiftCardActivityIndex() {
  return GiftCardActivityIndex(
    createdTxids: const {_homeCreatedGiftCardTxid},
    redeemedTxids: const {_homeRedeemedGiftCardTxid},
    createdMetadataByTxid: {
      _homeCreatedGiftCardTxid: GiftCardActivityMetadata(
        claimFeeReserveZatoshi: BigInt.from(10000),
        kind: GiftCardActivityKind.created,
        amountZatoshi: BigInt.from(100000000),
        artworkId: 'ruby',
        message: 'Happy birthday!',
      ),
    },
    redeemedMetadataByTxid: {
      _homeRedeemedGiftCardTxid: GiftCardActivityMetadata(
        kind: GiftCardActivityKind.redeemed,
        amountZatoshi: BigInt.from(100000000),
        artworkId: 'crystal',
        message: null,
      ),
    },
  );
}

// --- Harnesses -------------------------------------------------------------

class _HomeDesktopHarness extends StatefulWidget {
  const _HomeDesktopHarness({
    this.windowSize = const Size(kWbDesktopWindowWidth, kWbDesktopWindowHeight),
  });

  /// The desktop window this preview lays out in; the compact option shrinks
  /// the window itself rather than squeezing a full-height one.
  final Size windowSize;

  @override
  State<_HomeDesktopHarness> createState() => _HomeDesktopHarnessState();
}

class _HomeDesktopHarnessState extends State<_HomeDesktopHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => HomeScreen(
            transactionDetailLoader: (_, _) async => null,
            releaseNotesLauncher: () async {},
          ),
        ),
        for (final path in const [
          '/send',
          '/receive',
          '/pay',
          '/activity',
          '/settings',
          '/settings/endpoint',
          '/migration',
          '/swap',
          '/voting',
          '/accounts',
          '/add-account',
          '/unlock',
        ])
          GoRoute(path: path, builder: (_, _) => _HomeRoutePlaceholder(path)),
        GoRoute(
          path: '/activity/tx/:txid',
          builder: (_, state) => _HomeRoutePlaceholder(
            '/activity/tx/${state.pathParameters['txid']}',
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WbDesktopWindowBox(
      size: widget.windowSize,
      child: ColoredBox(
        color: context.colors.macosUtility.window,
        child: Router.withConfig(config: _router),
      ),
    );
  }
}

class _HomeMobileHarness extends StatefulWidget {
  const _HomeMobileHarness({required this.accountsSheetOpen});

  final bool accountsSheetOpen;

  @override
  State<_HomeMobileHarness> createState() => _HomeMobileHarnessState();
}

class _HomeMobileHarnessState extends State<_HomeMobileHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => AppMobileShell(
            body: _HomeMobileBody(accountsSheetOpen: widget.accountsSheetOpen),
            tabBar: AppMobileTabBar(
              items: _homeMobileTabItems,
              currentIndex: 0,
              onSelect: (_) {},
            ),
          ),
        ),
        for (final path in const [
          '/send',
          '/receive',
          '/swap',
          '/pay',
          '/voting',
          '/activity',
          '/settings',
          '/accounts',
          '/add-account',
          '/home/keystone-shield',
        ])
          GoRoute(path: path, builder: (_, _) => _HomeRoutePlaceholder(path)),
        GoRoute(
          path: '/activity/tx/:txid',
          builder: (_, state) => _HomeRoutePlaceholder(
            '/activity/tx/${state.pathParameters['txid']}',
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Router.withConfig(config: _router);
}

class _HomeMobileBody extends StatefulWidget {
  const _HomeMobileBody({required this.accountsSheetOpen});

  final bool accountsSheetOpen;

  @override
  State<_HomeMobileBody> createState() => _HomeMobileBodyState();
}

class _HomeMobileBodyState extends State<_HomeMobileBody> {
  var _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opened || !widget.accountsSheetOpen) return;
    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showMobileAccountsSheet(context);
    });
  }

  @override
  Widget build(BuildContext context) => MobileHomeScreen(
    transactionDetailLoader: (_, _) async => null,
    releaseNotesLauncher: () async {},
  );
}

const _homeMobileTabItems = [
  AppMobileTabItem(iconName: AppIcons.home, label: 'Home'),
  AppMobileTabItem(iconName: AppIcons.swapArrows, label: 'Swap'),
  AppMobileTabItem(iconName: AppIcons.history, label: 'Activity'),
  AppMobileTabItem(iconName: AppIcons.cog, label: 'Settings'),
];

class _HomeMobileFrame extends StatelessWidget {
  const _HomeMobileFrame({
    required this.child,
    required this.constrainToDesignSize,
  });

  final Widget child;
  final bool constrainToDesignSize;

  static const _size = Size(393, 852);
  static const _safeAreaPadding = EdgeInsets.only(top: 55, bottom: 24);

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final frame = ClipRect(
      child: MediaQuery(
        data: mediaQuery.copyWith(
          size: constrainToDesignSize ? _size : mediaQuery.size,
          padding: _safeAreaPadding,
          viewPadding: _safeAreaPadding,
        ),
        child: child,
      ),
    );
    if (!constrainToDesignSize) return frame;
    return Center(
      child: WbScaleDownBox(
        size: _size,
        child: SizedBox.fromSize(size: _size, child: frame),
      ),
    );
  }
}

class _HomeRoutePlaceholder extends StatelessWidget {
  const _HomeRoutePlaceholder(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Navigated to $label'));
  }
}

// --- Preview notifiers -----------------------------------------------------

/// Home only prepares a simulated Pay entry and navigates to a placeholder.
/// Never initialize the production composer's storage or network listeners.
class _HomePayNotifier extends SwapNotifier {
  @override
  SwapState build() => const SwapState(
    direction: SwapDirection.zecToExternal,
    amountText: '',
    receiveAmountText: '',
    destinationText: '',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: [],
  );

  @override
  Future<SwapAsset?> resolvePaySelectedAssetForEntry({
    required String accountUuid,
  }) async => SwapAsset.usdc;

  @override
  bool preparePayFromShieldedZec({
    SwapAsset? preferredAsset,
    String? expectedAccountUuid,
  }) {
    state = state.copyWith(
      payMode: true,
      externalAsset: preferredAsset ?? SwapAsset.usdc,
    );
    return true;
  }
}

class _HomeNoOpLayoutNotifier extends AppLayoutNotifier {
  @override
  AppLayoutState build() => const AppLayoutState(AppLayoutMode.large);

  // `setMode` would reshape the native window, which the dev tool owns.
  @override
  Future<void> setMode(AppLayoutMode mode) async {}
}

class _HomeAccountNotifier extends AccountNotifier {
  _HomeAccountNotifier(this.initialState);

  final AccountState initialState;

  @override
  FutureOr<AccountState> build() => initialState;

  @override
  Future<void> switchAccount(String uuid) async {
    final prev = state.value ?? initialState;
    state = AsyncData(prev.copyWith(activeAccountUuid: uuid));
  }
}

class _HomeSyncNotifier extends SyncNotifier {
  _HomeSyncNotifier(this.initialState);

  final SyncState initialState;

  @override
  Future<SyncState> build() async => initialState;

  // Retry only clears the fixture failure; never start Rust sync or polling.
  @override
  void startSync({int? latestTipHeight}) {
    state = AsyncData(
      (state.value ?? initialState).copyWith(clearFailure: true, clearError: true),
    );
  }

  @override
  Future<void> refreshAfterSend() async {}

  @override
  Future<void> refreshAfterAccountSwitch() async {}

  @override
  Future<WalletMutationSyncPause> pauseForWalletMutation({
    FutureOr<void> Function()? onStoppingSync,
  }) async {
    return const WalletMutationSyncPause(
      hadActiveSync: false,
      hadPolling: false,
      hadMempoolObserver: false,
    );
  }

  @override
  void resumeAfterWalletMutation(WalletMutationSyncPause pause) {}

  @override
  Future<void> clearSensitiveStateForLock() async {}
}

class _HomeWalletNotifier extends WalletNotifier {
  _HomeWalletNotifier(this.status);

  final HomeWalletState status;

  @override
  FutureOr<WalletState> build() {
    if (status == HomeWalletState.error) {
      throw StateError('Preview wallet load failure');
    }
    // Never completes: the pane's loading branch without a timer.
    return Completer<WalletState>().future;
  }
}

class _HomeSyncKeepAwakeNotifier extends SyncKeepAwakeNotifier {
  @override
  SyncKeepAwakeSettings build() =>
      const SyncKeepAwakeSettings(enabled: false, promptSeen: false);

  @override
  Future<void> markPromptSeen() async {}

  @override
  Future<void> setEnabled(bool enabled, {bool markPromptSeen = true}) async {}
}

class _HomePrivacyModeNotifier extends PrivacyModeNotifier {
  @override
  Future<void> set(bool enabled) async {
    state = enabled;
  }
}

class _HomeNetworkPrivacyNotifier extends NetworkPrivacyNotifier {
  _HomeNetworkPrivacyNotifier(this.initialState);

  final NetworkPrivacyState initialState;

  @override
  NetworkPrivacyState build() => initialState;

  @override
  Future<void> setTorEnabled(bool enabled) async {}
}

class _HomeMigrationCoordinator extends IronwoodMigrationCoordinator {
  @override
  IronwoodMigrationCoordinatorState build() {
    return const IronwoodMigrationCoordinatorState();
  }

  @override
  Future<void> recover(String accountUuid) async {}
}

class _HomeZecMarketDataSource implements ZecMarketDataSource {
  const _HomeZecMarketDataSource(this.data);

  final ZecMarketData? data;

  @override
  Future<ZecMarketData?> fetchMarketData() async => data;
}

/// Empty voting config storage: the notifier resolves to its default source
/// without touching the secure-storage platform channel.
class _HomeVotingConfigSourceStore implements VotingConfigSourceStore {
  const _HomeVotingConfigSourceStore();

  @override
  Future<String?> readSourceUrl() async => null;

  @override
  Future<void> writeSourceUrl(String sourceUrl) async {}

  @override
  Future<void> resetSourceUrl() async {}

  @override
  Future<String?> readSavedSourcesJson() async => null;

  @override
  Future<void> writeSavedSourcesJson(String savedSourcesJson) async {}
}

class _HomeReceiveAddressService implements ReceiveAddressService {
  const _HomeReceiveAddressService();

  @override
  String? getCachedTransparentAddress(String accountUuid) =>
      't1WidgetbookTransparentAddress';

  @override
  Future<String> loadShieldedAddress({
    required String accountUuid,
    String? currentShieldedAddress,
  }) async {
    return currentShieldedAddress?.isNotEmpty == true
        ? currentShieldedAddress!
        : 'u1widgetbookhomeaddress';
  }

  @override
  Future<String> loadTransparentReceiveAddress({
    required String accountUuid,
  }) async {
    return 't1WidgetbookTransparentAddress';
  }

  @override
  Future<String> reserveOrchardAddress({required String accountUuid}) async {
    return 'u1widgetbookhomereservedaddress';
  }

  @override
  Future<String> renewShieldedAddress({required String accountUuid}) async {
    return 'u1widgetbookhomerenewedaddress';
  }
}

// --- Activity axes ---------------------------------------------------------

/// What the activity list is doing. `noAccount` is the desktop screen's
/// null-uuid branch; the phone renders that as an empty feed.
enum ActivityScreenState { rows, loading, empty, error, noAccount }

/// What a loaded feed holds. One axis: the transaction set and the swap rows
/// layered over it are the same "what is in the list" question.
enum ActivityRowSet { transactions, giftCards, withSwapRows, swapLegAbsorbed }

/// What a transaction receipt is for. `receiving` is not an option: it is
/// [TxStatusKind.received] at [TxStatusPhase.pending].
enum TxStatusKind { sent, received, shielded, migration, giftCard }

enum TxStatusPhase { pending, succeeded, failed }

/// Who the receipt names in its From / To row. `unknown` and `shieldedSender`
/// have no address at all, which on a sent receipt is the no-recipient state.
enum TxStatusCounterparty {
  contact,
  ownAccount,
  rawAddress,
  unknown,
  shieldedSender,
}

/// What the receipt's own refresh finds. `loading` and `failed` both arrive
/// with no transaction in the args, which is the only state either message
/// renders in.
enum TxStatusLoad { loaded, loading, failed }

// --- Activity screen -------------------------------------------------------

/// `ActivityScreen` in a minimal router, with its only Rust seam
/// (`historyLoader`) driving the loading / empty / error branches.
Widget activityDesktopFixture({
  ActivityScreenState state = ActivityScreenState.rows,
  ActivityRowSet rows = ActivityRowSet.transactions,
  bool swapFeatureEnabled = true,
  bool privacyMode = false,
}) {
  return ProviderScope(
    overrides: _activityOverrides(
      state: state,
      rows: rows,
      swapFeatureEnabled: swapFeatureEnabled,
      privacyMode: privacyMode,
    ),
    child: _ActivityDesktopHarness(
      historyLoader: _activityHistoryLoader(state, rows),
    ),
  );
}

/// `MobileActivityScreen` in the mobile shell and a phone frame.
Widget activityMobileFixture({
  ActivityScreenState state = ActivityScreenState.rows,
  ActivityRowSet rows = ActivityRowSet.transactions,
  bool swapFeatureEnabled = true,
  bool privacyMode = false,
}) {
  return ProviderScope(
    overrides: _activityOverrides(
      state: state,
      rows: rows,
      swapFeatureEnabled: swapFeatureEnabled,
      privacyMode: privacyMode,
    ),
    child: _HomeMobileFrame(
      constrainToDesignSize: true,
      child: _ActivityMobileHarness(
        historyLoader: _activityHistoryLoader(state, rows),
      ),
    ),
  );
}

// --- Transaction status ----------------------------------------------------

/// `MobileTransactionStatusScreen` on its own route, fed by the args the
/// tapped row hands it plus the two injectable loaders.
Widget mobileTransactionStatusFixture({
  TxStatusKind kind = TxStatusKind.sent,
  TxStatusPhase phase = TxStatusPhase.succeeded,
  TxStatusCounterparty counterparty = TxStatusCounterparty.rawAddress,
  bool message = false,
  bool messageExpanded = false,
  bool refreshFailed = false,
  bool privacyMode = false,
}) {
  final transaction = _txStatusTransaction(kind: kind, phase: phase);
  final detail = _txStatusDetail(
    kind: kind,
    counterparty: counterparty,
    message: message,
  );
  final giftCard = kind == TxStatusKind.giftCard
      ? GiftCardActivityMetadata(
          kind: GiftCardActivityKind.created,
          amountZatoshi: BigInt.from(445000000),
          artworkId: 'ruby',
          message: message ? _txStatusMemo : null,
          claimFeeReserveZatoshi: BigInt.from(10000),
          fiatSnapshot: const PaymentLinkFiatSnapshot(amount: 142.23),
        )
      : null;
  final accountState = _homeAccountState(HomeAccountKind.software);
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _homeBootstrap(
          accountState,
          privacyModeEnabled: privacyMode,
          passwordRotationRecoveryFailed: false,
        ),
      ),
      accountProvider.overrideWith(() => _HomeAccountNotifier(accountState)),
      syncProvider.overrideWith(
        () => _HomeSyncNotifier(
          _homeSyncedState(
            accountUuid: accountState.activeAccountUuid,
            balance: HomeBalanceAmount.funded,
            activity: HomeActivityFeed.empty,
            shieldAction: HomeShieldAction.hidden,
          ),
        ),
      ),
      privacyModeProvider.overrideWith(_HomePrivacyModeNotifier.new),
      swapFeatureEnabledProvider.overrideWithValue(true),
      addressBookProvider.overrideWith(_ActivityAddressBookNotifier.new),
      ownAccountAddressesProvider.overrideWith(
        (ref) async => {
          _txStatusOwnAccountAddress: accountState.accounts.first,
        },
      ),
      giftCardActivityIndexProvider.overrideWith(
        (ref, accountUuid) async => GiftCardActivityIndex.empty,
      ),
    ],
    child: _HomeMobileFrame(
      constrainToDesignSize: true,
      child: _ActivityExpandMessageOnMount(
        enabled: message && messageExpanded,
        child: _TxStatusHarness(
          args: MobileTransactionStatusArgs(
            txidHex: _txStatusTxid,
            txKind: transaction.txKind,
            initialTransaction: transaction,
            initialDetail: detail,
            giftCard: giftCard,
          ),
          // The refresh is the only load the screen runs itself, so a
          // throwing history loader is the error line's only source.
          historyLoader: refreshFailed
              ? (_) async => throw StateError('Preview refresh failure')
              : (_) async => [transaction],
          detailLoader: (_, _) async => detail,
        ),
      ),
    ),
  );
}

/// `ActivityTransactionStatusScreen` in the desktop shell, on the same args
/// and loader seams as its mobile sibling.
///
/// A refresh failure over a loaded receipt is not a [TxStatusLoad] option. It
/// is not a no-op: the screen clears `_detail` alongside the `_error` it never
/// prints over an existing transaction (activity_transaction_status_screen
/// .dart:212-217, :610), so the receipt silently drops to the fallback card.
/// That silent loss is a screen defect, not a state worth previewing.
Widget activityTransactionStatusDesktopFixture({
  TxStatusKind kind = TxStatusKind.sent,
  TxStatusPhase phase = TxStatusPhase.succeeded,
  TxStatusCounterparty counterparty = TxStatusCounterparty.rawAddress,
  TxStatusLoad load = TxStatusLoad.loaded,
  bool message = false,
  bool messageExpanded = false,
  bool privacyMode = false,
}) {
  final transaction = _txStatusTransaction(kind: kind, phase: phase);
  final detail = _txStatusDetail(
    kind: kind,
    counterparty: counterparty,
    message: message,
  );
  final giftCard = kind == TxStatusKind.giftCard
      ? GiftCardActivityMetadata(
          kind: GiftCardActivityKind.created,
          amountZatoshi: BigInt.from(445000000),
          artworkId: 'ruby',
          message: message ? _txStatusMemo : null,
          claimFeeReserveZatoshi: BigInt.from(10000),
          fiatSnapshot: const PaymentLinkFiatSnapshot(amount: 142.23),
        )
      : null;
  final loaded = load == TxStatusLoad.loaded;
  final accountState = _homeAccountState(HomeAccountKind.software);
  return ProviderScope(
    overrides: [
      // The screen sits in the sidebar shell, so it needs the same home
      // providers the desktop Activity screen does.
      ..._homeOverrides(
        accountState: accountState,
        balance: HomeBalanceAmount.funded,
        activity: HomeActivityFeed.empty,
        sync: HomeSyncProgress.synced,
        network: HomeNetworkRoute.direct,
        notice: HomeNoticeKind.none,
        shieldAction: HomeShieldAction.hidden,
        priceChange: HomePriceChange.hidden,
        swapEnabled: true,
        privacyMode: privacyMode,
      ),
      ironwoodMigrationCoordinatorProvider.overrideWith(
        _HomeMigrationCoordinator.new,
      ),
      addressBookProvider.overrideWith(_ActivityAddressBookNotifier.new),
      ownAccountAddressesProvider.overrideWith(
        (ref) async => {
          _txStatusOwnAccountAddress: accountState.accounts.first,
        },
      ),
    ],
    child: _ActivityExpandReviewMessageOnMount(
      // Every axis seeds state at mount (args in `initState`, the toggle from
      // a post-frame callback), so the subtree remounts per knob change.
      key: ValueKey(
        'wb_tx_status_desktop_${kind.name}_${phase.name}_'
        '${counterparty.name}_${load.name}_${message}_$messageExpanded',
      ),
      enabled:
          loaded &&
          message &&
          messageExpanded &&
          _txStatusDesktopHasMessageRow(kind, counterparty),
      child: _TxStatusDesktopHarness(
        args: ActivityTransactionStatusArgs(
          txidHex: _txStatusTxid,
          txKind: transaction.txKind,
          initialTransaction: loaded ? transaction : null,
          initialDetail: loaded ? detail : null,
          giftCard: loaded ? giftCard : null,
        ),
        historyLoader: switch (load) {
          TxStatusLoad.loaded => (_) async => [transaction],
          // Never completes: the screen's own 'Loading transaction…' line.
          TxStatusLoad.loading =>
            (_) => Completer<List<rust_sync.TransactionInfo>>().future,
          TxStatusLoad.failed => (_) async => throw StateError(
            'Preview history failure',
          ),
        },
        detailLoader: (_, _) async => detail,
      ),
    ),
  );
}

/// Whether this combination even has a Message row to expand: a migration
/// receipt and a sent receipt with no resolved recipient both land on the
/// fallback card, which carries no message.
bool _txStatusDesktopHasMessageRow(
  TxStatusKind kind,
  TxStatusCounterparty counterparty,
) {
  return switch (kind) {
    TxStatusKind.sent =>
      counterparty != TxStatusCounterparty.unknown &&
          counterparty != TxStatusCounterparty.shieldedSender,
    TxStatusKind.received ||
    TxStatusKind.shielded ||
    TxStatusKind.giftCard => true,
    TxStatusKind.migration => false,
  };
}

// --- Activity fixture state ------------------------------------------------

const _activitySentTxid = 'activity-gallery-sent';
const _activityReceivedTxid = 'activity-gallery-received';
const _activityEarlierTxid = 'activity-gallery-earlier';
const _activitySwapPayoutTxid = 'activity-gallery-swap-payout';
const _activitySwapIntentId = 'activity-gallery-swap-intent';

// Fixed past epochs: section titles come from the timestamps, and only a
// stable month keeps '<Month> <Year>' out of the clock's hands.
const _activityApril12Epoch = 1744452000;
const _activityApril11Epoch = 1744362000;
const _activityApril10Epoch = 1744272000;

ActivityHistoryLoader _activityHistoryLoader(
  ActivityScreenState state,
  ActivityRowSet rows,
) {
  return switch (state) {
    // Never completes: the feed's loading branch without a timer.
    ActivityScreenState.loading =>
      (_) => Completer<List<rust_sync.TransactionInfo>>().future,
    ActivityScreenState.error => (_) async => throw StateError(
      'Preview history failure',
    ),
    ActivityScreenState.empty ||
    ActivityScreenState.noAccount => (_) async => const [],
    ActivityScreenState.rows => (_) async => _activityTransactions(rows),
  };
}

List<rust_sync.TransactionInfo> _activityTransactions(ActivityRowSet rows) {
  return switch (rows) {
    ActivityRowSet.transactions || ActivityRowSet.withSwapRows => [
      _activitySentTx(),
      _activityReceivedTx(),
      _activityEarlierTx(),
    ],
    ActivityRowSet.giftCards => [
      _activityGiftCardTx(
        txidHex: _homeRedeemedGiftCardTxid,
        kind: 'received',
        seconds: _activityApril12Epoch,
      ),
      _activityGiftCardTx(
        txidHex: _homeCreatedGiftCardTxid,
        kind: 'sent',
        seconds: _activityApril11Epoch,
      ),
      _activityEarlierTx(),
    ],
    // The payout row has to be in the history for its absorption into the
    // swap group to be visible at all.
    ActivityRowSet.swapLegAbsorbed => [
      _activitySentTx(),
      _activitySwapPayoutTx(),
      _activityEarlierTx(),
    ],
  };
}

List<SwapActivityRowItem> _activitySwapRowItems(ActivityRowSet rows) {
  return switch (rows) {
    ActivityRowSet.withSwapRows => [_activitySwapRowItem()],
    ActivityRowSet.swapLegAbsorbed => [
      _activitySwapRowItem(receiveTxidHex: _activitySwapPayoutTxid),
    ],
    _ => const [],
  };
}

SwapActivityRowItem _activitySwapRowItem({String? receiveTxidHex}) {
  final completedAt = DateTime.fromMillisecondsSinceEpoch(
    _activityApril11Epoch * 1000,
    isUtc: true,
  );
  return SwapActivityRowItem(
    intentId: _activitySwapIntentId,
    providerLabel: 'Preview',
    sellAmountText: '26.60 USDC',
    receiveEstimateText: '12.13 ZEC',
    status: SwapIntentStatus.complete,
    direction: SwapDirection.externalToZec,
    externalAsset: SwapAsset.usdc,
    activityTimestamp: completedAt,
    completedAt: completedAt,
    receiveWalletTxidHex: receiveTxidHex,
  );
}

rust_sync.TransactionInfo _activitySentTx() {
  return _activityTx(
    txidHex: _activitySentTxid,
    kind: 'sent',
    seconds: _activityApril12Epoch,
    zatoshi: BigInt.from(412000000),
  );
}

rust_sync.TransactionInfo _activityReceivedTx() {
  return _activityTx(
    txidHex: _activityReceivedTxid,
    kind: 'received',
    seconds: _activityApril10Epoch,
    zatoshi: BigInt.from(540000000),
  );
}

rust_sync.TransactionInfo _activitySwapPayoutTx() {
  return _activityTx(
    txidHex: _activitySwapPayoutTxid,
    kind: 'received',
    seconds: _activityApril11Epoch,
    zatoshi: BigInt.from(1213000000),
  );
}

/// Mined, but with no recorded block or creation time: the feed's 'Earlier'
/// section is exactly the rows it cannot date.
rust_sync.TransactionInfo _activityEarlierTx() {
  return _activityTx(
    txidHex: _activityEarlierTxid,
    kind: 'shielded',
    seconds: 0,
    zatoshi: BigInt.from(30000000),
  );
}

rust_sync.TransactionInfo _activityTx({
  required String txidHex,
  required String kind,
  required int seconds,
  required BigInt zatoshi,
}) {
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: BigInt.from(2100000),
    expiredUnmined: false,
    accountBalanceDelta: 0,
    fee: BigInt.from(10000),
    blockTime: BigInt.from(seconds),
    isTransparent: false,
    txKind: kind,
    displayAmount: zatoshi,
    displayPool: 'shielded',
    createdTime: BigInt.zero,
  );
}

rust_sync.TransactionInfo _activityGiftCardTx({
  required String txidHex,
  required String kind,
  required int seconds,
}) {
  return _activityTx(
    txidHex: txidHex,
    kind: kind,
    seconds: seconds,
    zatoshi: BigInt.from(3110000000),
  );
}

List<Override> _activityOverrides({
  required ActivityScreenState state,
  required ActivityRowSet rows,
  required bool swapFeatureEnabled,
  required bool privacyMode,
}) {
  final accountState = state == ActivityScreenState.noAccount
      ? const AccountState()
      : _homeAccountState(HomeAccountKind.software);
  return [
    ..._homeOverrides(
      accountState: accountState,
      balance: HomeBalanceAmount.funded,
      activity: HomeActivityFeed.empty,
      sync: HomeSyncProgress.synced,
      network: HomeNetworkRoute.direct,
      notice: HomeNoticeKind.none,
      shieldAction: HomeShieldAction.hidden,
      priceChange: HomePriceChange.hidden,
      swapEnabled: swapFeatureEnabled,
      privacyMode: privacyMode,
      swapRowItems: _activitySwapRowItems(rows),
      giftCardIndex: rows == ActivityRowSet.giftCards
          ? _homeGiftCardActivityIndex()
          : GiftCardActivityIndex.empty,
    ),
    ironwoodMigrationCoordinatorProvider.overrideWith(
      _HomeMigrationCoordinator.new,
    ),
  ];
}

// --- Transaction status fixture state --------------------------------------

const _txStatusTxid =
    'f154a1c1b2d3e4f5061728394a5b6c7d8e9f00112233445566778899aabbcc81';
const _txStatusContactAddress = 'u1contactgallerytransactionstatusaddress';
const _txStatusOwnAccountAddress = 'u1ownaccountgallerytransactionstatusaddr';
const _txStatusRawAddress = 'u1rawgallerytransactionstatusaddresssample';
const _txStatusReceivingAddress = 'u1receivinggallerytransactionstatusaddress';
const _txStatusMemo = 'Thanks for lunch, see you next week!';

String _txStatusTxKind(TxStatusKind kind) {
  return switch (kind) {
    TxStatusKind.sent || TxStatusKind.giftCard => 'sent',
    TxStatusKind.received => 'received',
    TxStatusKind.shielded => 'shielded',
    TxStatusKind.migration => 'migration',
  };
}

rust_sync.TransactionInfo _txStatusTransaction({
  required TxStatusKind kind,
  required TxStatusPhase phase,
}) {
  final mined = phase == TxStatusPhase.succeeded;
  return rust_sync.TransactionInfo(
    txidHex: _txStatusTxid,
    minedHeight: mined ? BigInt.from(2100000) : BigInt.zero,
    expiredUnmined: phase == TxStatusPhase.failed,
    accountBalanceDelta: 0,
    fee: BigInt.from(10000),
    blockTime: mined ? BigInt.from(_activityApril12Epoch) : BigInt.zero,
    isTransparent: false,
    txKind: _txStatusTxKind(kind),
    displayAmount: BigInt.from(445000000),
    displayPool: 'shielded',
    createdTime: BigInt.from(_activityApril12Epoch),
  );
}

rust_sync.TransactionDetail _txStatusDetail({
  required TxStatusKind kind,
  required TxStatusCounterparty counterparty,
  required bool message,
}) {
  final address = switch (counterparty) {
    TxStatusCounterparty.contact => _txStatusContactAddress,
    TxStatusCounterparty.ownAccount => _txStatusOwnAccountAddress,
    TxStatusCounterparty.rawAddress => _txStatusRawAddress,
    TxStatusCounterparty.unknown || TxStatusCounterparty.shieldedSender => null,
  };
  final incoming = kind == TxStatusKind.received;
  return rust_sync.TransactionDetail(
    txidHex: _txStatusTxid,
    txKind: _txStatusTxKind(kind),
    primaryAddress: incoming ? null : address,
    sourceAddress: incoming ? address : null,
    // The source pool is what names an unresolvable sender: a shielded sender
    // is hidden by the protocol, a transparent one is merely unknown.
    sourcePool: counterparty == TxStatusCounterparty.shieldedSender
        ? 'shielded'
        : 'transparent',
    memo: message ? _txStatusMemo : null,
    outputs: incoming
        ? [
            rust_sync.TransactionDetailOutput(
              address: _txStatusReceivingAddress,
              amountZatoshi: BigInt.from(445000000),
              pool: 'shielded',
            ),
          ]
        : const [],
  );
}

class _ActivityAddressBookNotifier extends AddressBookNotifier {
  @override
  FutureOr<AddressBookState> build() {
    return const AddressBookState(
      contacts: [
        AddressBookContact(
          id: 'activity-gallery-contact',
          label: 'Mike',
          network: AddressBookNetwork.zcash,
          address: _txStatusContactAddress,
          profilePictureId: 'pfp-03',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
      ],
    );
  }
}

/// Swap activity is read from secure storage in production; the previews keep
/// the periodic status refresh inert instead of hitting a platform channel.
class _ActivityNoopSwapActivityStore implements SwapActivityStore {
  const _ActivityNoopSwapActivityStore();

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async {
    return const [];
  }

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {}

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {}
}

// --- Activity harnesses ----------------------------------------------------

class _ActivityDesktopHarness extends StatefulWidget {
  const _ActivityDesktopHarness({required this.historyLoader});

  final ActivityHistoryLoader historyLoader;

  @override
  State<_ActivityDesktopHarness> createState() =>
      _ActivityDesktopHarnessState();
}

class _ActivityDesktopHarnessState extends State<_ActivityDesktopHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/activity',
      routes: [
        GoRoute(
          path: '/activity',
          builder: (_, _) => ActivityScreen(
            historyLoader: widget.historyLoader,
            transactionDetailLoader: _previewActivityTransactionDetail,
          ),
        ),
        ..._activityPlaceholderRoutes(),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WbDesktopWindowBox(
      child: ColoredBox(
        color: context.colors.macosUtility.window,
        child: Router.withConfig(config: _router),
      ),
    );
  }
}

class _ActivityMobileHarness extends StatefulWidget {
  const _ActivityMobileHarness({required this.historyLoader});

  final MobileActivityHistoryLoader historyLoader;

  @override
  State<_ActivityMobileHarness> createState() => _ActivityMobileHarnessState();
}

class _ActivityMobileHarnessState extends State<_ActivityMobileHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/activity',
      routes: [
        GoRoute(
          path: '/activity',
          builder: (_, _) => AppMobileShell(
            body: MobileActivityScreen(
              historyLoader: widget.historyLoader,
              transactionDetailLoader: _previewActivityTransactionDetail,
            ),
            tabBar: AppMobileTabBar(
              items: _homeMobileTabItems,
              currentIndex: 2,
              onSelect: (_) {},
            ),
          ),
        ),
        ..._activityPlaceholderRoutes(),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Router.withConfig(config: _router);
}

Future<rust_sync.TransactionDetail?> _previewActivityTransactionDetail(
  rust_sync.TransactionInfo transaction,
) async => null;

class _TxStatusHarness extends StatefulWidget {
  const _TxStatusHarness({
    required this.args,
    required this.historyLoader,
    required this.detailLoader,
  });

  final MobileTransactionStatusArgs args;
  final MobileTxHistoryLoader historyLoader;
  final MobileTxDetailLoader detailLoader;

  @override
  State<_TxStatusHarness> createState() => _TxStatusHarnessState();
}

class _TxStatusHarnessState extends State<_TxStatusHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/activity/tx/${widget.args.txidHex}',
      routes: [
        GoRoute(
          path: '/activity',
          builder: (_, _) => const _HomeRoutePlaceholder('/activity'),
        ),
        GoRoute(
          path: '/activity/tx/:txid',
          builder: (_, _) => MobileTransactionStatusScreen(
            args: widget.args,
            historyLoader: widget.historyLoader,
            detailLoader: widget.detailLoader,
            explorerLauncher: (_) async => true,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Router.withConfig(config: _router);
}

class _TxStatusDesktopHarness extends StatefulWidget {
  const _TxStatusDesktopHarness({
    required this.args,
    required this.historyLoader,
    required this.detailLoader,
  });

  final ActivityTransactionStatusArgs args;
  final ActivityTxHistoryLoader historyLoader;
  final ActivityTxDetailLoader detailLoader;

  @override
  State<_TxStatusDesktopHarness> createState() =>
      _TxStatusDesktopHarnessState();
}

class _TxStatusDesktopHarnessState extends State<_TxStatusDesktopHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/activity/tx/${widget.args.txidHex}',
      routes: [
        GoRoute(
          path: '/activity/tx/:txid',
          builder: (_, _) => ActivityTransactionStatusScreen(
            args: widget.args,
            historyLoader: widget.historyLoader,
            detailLoader: widget.detailLoader,
            explorerLauncher: (_) async => true,
          ),
        ),
        for (final path in wbSidebarPaths)
          GoRoute(path: path, builder: (_, _) => _HomeRoutePlaceholder(path)),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WbDesktopWindowBox(
      child: ColoredBox(
        color: context.colors.macosUtility.window,
        child: Router.withConfig(config: _router),
      ),
    );
  }
}

/// Fires the desktop receipt's own Message row once it is on screen: the
/// expansion lives in private screen state, so invoking the row's handler is
/// the only way a preview reaches the expanded message.
class _ActivityExpandReviewMessageOnMount extends StatefulWidget {
  const _ActivityExpandReviewMessageOnMount({
    required this.enabled,
    required this.child,
    super.key,
  });

  final bool enabled;
  final Widget child;

  @override
  State<_ActivityExpandReviewMessageOnMount> createState() =>
      _ActivityExpandReviewMessageOnMountState();
}

class _ActivityExpandReviewMessageOnMountState
    extends State<_ActivityExpandReviewMessageOnMount> {
  static const _maxAttempts = 12;
  var _attempts = 0;
  var _done = false;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _expand());
  }

  void _expand() {
    if (_done || !mounted) return;
    final onPressed = _messageRowCallback();
    if (onPressed == null) {
      if (++_attempts >= _maxAttempts) {
        // Debug-only, so a fixture whose expanded message never arrives fails
        // in the widgetbook and in tests instead of previewing a collapsed one.
        assert(false, 'The receipt never showed an expandable Message row.');
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _expand());
      // A post-frame callback only runs if another frame is produced, and a
      // settled receipt animates nothing.
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    _done = true;
    onPressed();
  }

  /// The row's own `onPressed`, not a synthetic pointer: hit-testing from the
  /// root would be intercepted by anything the widgetbook chrome overlays.
  VoidCallback? _messageRowCallback() {
    VoidCallback? onPressed;
    void findRow(Element element) {
      if (onPressed != null) return;
      final widget = element.widget;
      if (widget is ReviewListRow &&
          widget.label == 'Message' &&
          widget.onPressed != null) {
        onPressed = widget.onPressed;
        return;
      }
      element.visitChildren(findRow);
    }

    context.visitChildElements(findRow);
    return onPressed;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

List<GoRoute> _activityPlaceholderRoutes() {
  return [
    for (final path in wbSidebarPaths.where((path) => path != '/activity'))
      GoRoute(path: path, builder: (_, _) => _HomeRoutePlaceholder(path)),
    GoRoute(
      path: '/activity/tx/:txid',
      builder: (_, state) =>
          _HomeRoutePlaceholder('/activity/tx/${state.pathParameters['txid']}'),
    ),
    GoRoute(
      path: '/activity/swap/:intentId',
      builder: (_, state) => _HomeRoutePlaceholder(
        '/activity/swap/${state.pathParameters['intentId']}',
      ),
    ),
  ];
}

/// Fires the receipt's own message toggle once it is on screen: the screen
/// keeps its expansion in private state, so invoking the toggle is the only
/// way a preview reaches the expanded message without a production seam.
class _ActivityExpandMessageOnMount extends StatefulWidget {
  const _ActivityExpandMessageOnMount({
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  State<_ActivityExpandMessageOnMount> createState() =>
      _ActivityExpandMessageOnMountState();
}

class _ActivityExpandMessageOnMountState
    extends State<_ActivityExpandMessageOnMount> {
  static const _toggleKey = ValueKey('mobile_tx_status_message_toggle');
  static const _maxAttempts = 8;
  var _attempts = 0;
  var _done = false;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _expand());
  }

  void _expand() {
    if (_done || !mounted) return;
    final onTap = _toggleCallback();
    if (onTap == null) {
      if (++_attempts >= _maxAttempts) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _expand());
      return;
    }
    _done = true;
    onTap();
  }

  /// The toggle's own `onTap`, not a synthetic pointer: hit-testing from the
  /// root would be intercepted by anything the widgetbook chrome overlays.
  VoidCallback? _toggleCallback() {
    Element? toggle;
    void findToggle(Element element) {
      if (toggle != null) return;
      if (element.widget.key == _toggleKey) {
        toggle = element;
        return;
      }
      element.visitChildren(findToggle);
    }

    context.visitChildElements(findToggle);
    if (toggle == null) return null;

    VoidCallback? onTap;
    void findDetector(Element element) {
      if (onTap != null) return;
      final widget = element.widget;
      if (widget is GestureDetector && widget.onTap != null) {
        onTap = widget.onTap;
        return;
      }
      element.visitChildren(findDetector);
    }

    toggle!.visitChildren(findDetector);
    return onTap;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// --- Activity feed axes ----------------------------------------------------

/// Which feed widget hosts the rows: the `Column` the mobile screen builds, or
/// the sliver the desktop `ActivityScreen` puts in its scroll view.
enum ActivityFeedHost { column, sliver }

/// What the feed body shows. Loading / empty / error are only reachable with
/// no sections, which is how both screens drive them.
enum ActivityFeedBodyState { rows, loading, empty, error }

/// The `cardWidth` prop: the 396px desktop card, or null so the card stretches
/// to the parent the way the mobile screen passes it.
enum ActivityFeedWidth { desktopCard, fullWidth }

/// What the single section holds. Three rows is what covers the sliver's
/// first / middle / last card segments.
enum ActivityFeedRowShape { single, threeRows, withChildRow }

// --- Activity row axes -----------------------------------------------------

enum ActivityRowInteraction { rest, selected, nonInteractive }

/// `ActivityFeedRow.compact`. Only reachable on a standalone row: the group
/// pins its parent row to the regular height and its children to compact.
enum ActivityRowDensity { regular, compact }

/// What the amount block carries beside the value.
enum ActivityRowTrailing { amount, refund, timeout }

enum ActivityRowStatus { completed, inProgress, failed }

/// `ActivityRowData.backgroundColor`: unset (transparent) or a filled row.
enum ActivityRowBackground { transparent, filled }

// --- Transaction row axes --------------------------------------------------

enum ActivityTxRowKind {
  received,
  receiving,
  sent,
  shielded,
  migration,
  giftCardCreated,
  giftCardRedeemed,
  unknown,
}

enum ActivityTxRowStatus { completed, inProgress, failed }

enum ActivityTxRowPool { transparent, shielded, ironwood, mixed, none }

/// Amount carried by the transaction; a zero delta maps to '--'.
enum ActivityTxRowAmount { value, zero }

// --- Swap row axes ---------------------------------------------------------

enum ActivitySwapRowMode { swap, pay }

enum ActivitySwapRowDirection { zecToAsset, assetToZec }

/// Whether the absorbed on-chain payout amount is handed to the mapper, which
/// is what turns the settled child leg into a tappable row with a real amount.
enum ActivitySwapRowReceivedLeg { absent, present }

// --- Activity feed ---------------------------------------------------------

/// The real `ActivityFeed` / `ActivityFeedSliver` driven only through props.
Widget activityFeedFixture({
  ActivityFeedHost host = ActivityFeedHost.column,
  ActivityFeedBodyState state = ActivityFeedBodyState.rows,
  ActivityFeedRowShape rows = ActivityFeedRowShape.threeRows,
  ActivityFeedWidth width = ActivityFeedWidth.desktopCard,
  bool showHeader = true,
}) {
  return _ActivityFeedPlayground(
    host: host,
    state: state,
    rows: rows,
    width: width,
    showHeader: showHeader,
  );
}

class _ActivityFeedPlayground extends StatelessWidget {
  const _ActivityFeedPlayground({
    required this.host,
    required this.state,
    required this.rows,
    required this.width,
    required this.showHeader,
  });

  static const _hostWidth = 560.0;
  static const _hostHeight = 660.0;

  final ActivityFeedHost host;
  final ActivityFeedBodyState state;
  final ActivityFeedRowShape rows;
  final ActivityFeedWidth width;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final sections = state == ActivityFeedBodyState.rows
        ? [
            ActivityFeedSectionData(
              title: 'April 2026',
              rows: _activityFeedPlaygroundRows(context, rows),
            ),
          ]
        : const <ActivityFeedSectionData>[];
    final isLoading = state == ActivityFeedBodyState.loading;
    final errorText = state == ActivityFeedBodyState.error
        ? 'Activity could not be loaded.'
        : null;

    return ColoredBox(
      color: context.colors.background.window,
      child: Center(
        child: SizedBox(
          width: _hostWidth,
          height: _hostHeight,
          // The sliver has no header or width prop of its own — it always
          // draws the title and its fixed 396/420 cards.
          child: host == ActivityFeedHost.sliver
              ? CustomScrollView(
                  slivers: [
                    ActivityFeedSliver(
                      sections: sections,
                      isLoading: isLoading,
                      errorText: errorText,
                      rowKeyPrefix: 'activity_feed_playground',
                    ),
                  ],
                )
              : SingleChildScrollView(
                  child: ActivityFeed(
                    sections: sections,
                    isLoading: isLoading,
                    errorText: errorText,
                    showHeader: showHeader,
                    cardWidth: width == ActivityFeedWidth.desktopCard
                        ? 396
                        : null,
                    rowKeyPrefix: 'activity_feed_playground',
                  ),
                ),
        ),
      ),
    );
  }
}

List<ActivityRowData> _activityFeedPlaygroundRows(
  BuildContext context,
  ActivityFeedRowShape shape,
) {
  final colors = context.colors;
  final sent = _galleryActivityRow(
    context,
    title: 'Sent',
    subtitle: 'Shielded',
    subtitleIconName: AppIcons.shieldKeyholeOutline,
    amountText: '-4.12 ZEC',
    onTap: _galleryNoop,
  );
  return switch (shape) {
    ActivityFeedRowShape.single => [sent],
    ActivityFeedRowShape.threeRows => [
      _galleryActivityRow(
        context,
        title: 'Received',
        iconName: AppIcons.arrowDownCircle,
        subtitle: 'Shielded',
        subtitleIconName: AppIcons.shieldKeyholeOutline,
        amountText: '+5.40 ZEC',
        amountColor: colors.text.positiveStrong,
        onTap: _galleryNoop,
      ),
      sent,
      _galleryActivityRow(
        context,
        title: 'Shielded',
        iconName: AppIcons.shieldKeyholeOutline,
        amountText: '0.30 ZEC',
        onTap: _galleryNoop,
      ),
    ],
    ActivityFeedRowShape.withChildRow => [
      _galleryActivityRow(
        context,
        title: 'Swapped',
        iconName: AppIcons.swapArrows,
        subtitle: 'USDC on Ethereum',
        amountText: '-26.60 USDC',
        onTap: _galleryNoop,
        childRows: [
          _galleryActivityRow(
            context,
            title: 'Received ZEC',
            iconName: AppIcons.swapArrows,
            amountText: '+12.13 ZEC',
            statusText: '',
            onTap: _galleryNoop,
          ),
        ],
      ),
    ],
  };
}

// --- Activity row ----------------------------------------------------------

/// A single `ActivityFeedRowGroup` / `ActivityFeedRow` on the feed's card
/// surface, driven only by `ActivityRowData` and the row's own two flags.
Widget activityRowFixture({
  ActivityRowInteraction interaction = ActivityRowInteraction.rest,
  ActivityRowDensity density = ActivityRowDensity.regular,
  ActivityRowTrailing trailing = ActivityRowTrailing.amount,
  ActivityRowStatus status = ActivityRowStatus.completed,
  bool childRow = false,
  bool privacyMode = false,
  ActivityRowBackground background = ActivityRowBackground.transparent,
}) {
  return Builder(
    builder: (context) {
      final colors = context.colors;
      final row = _galleryActivityRow(
        context,
        title: 'Sent',
        iconName: status == ActivityRowStatus.inProgress
            ? AppIcons.loader
            : AppIcons.plane,
        subtitle: 'Shielded',
        subtitleIconName: AppIcons.shieldKeyholeOutline,
        amountText: hideAmountIfPrivacyMode(
          '-4.12 ZEC',
          privacyModeEnabled: privacyMode,
          maskLength: 3,
        ),
        amountColor: status == ActivityRowStatus.failed
            ? colors.text.accent
            : null,
        // Matches the swap row mapper: a refund is the u-turn icon on the
        // amount, and `amountSubtitle` carries only the timeout wording.
        amountIconName: trailing == ActivityRowTrailing.refund
            ? AppIcons.uturnUp
            : null,
        amountSubtitle: trailing == ActivityRowTrailing.timeout
            ? 'Timeout'
            : null,
        amountSubtitleIconName: trailing == ActivityRowTrailing.timeout
            ? AppIcons.time
            : null,
        statusText: switch (status) {
          ActivityRowStatus.completed => 'Completed',
          ActivityRowStatus.inProgress => 'In progress',
          ActivityRowStatus.failed => 'Failed',
        },
        statusIconName: status == ActivityRowStatus.failed
            ? AppIcons.skull
            : null,
        statusColor: status == ActivityRowStatus.failed
            ? colors.text.destructive
            : null,
        backgroundColor: background == ActivityRowBackground.filled
            ? colors.background.neutralSubtleOpacity
            : null,
        selected: interaction == ActivityRowInteraction.selected,
        childRows: childRow
            ? [
                _galleryActivityRow(
                  context,
                  title: 'Received ZEC',
                  iconName: AppIcons.swapArrows,
                  amountText: '+12.13 ZEC',
                  statusText: '',
                ),
              ]
            : const [],
        onTap: interaction == ActivityRowInteraction.nonInteractive
            ? null
            : _galleryNoop,
      );

      return ColoredBox(
        color: colors.background.window,
        child: Center(
          child: SizedBox(
            width: 396,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background.ground,
                borderRadius: BorderRadius.circular(AppRadii.large),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: density == ActivityRowDensity.compact
                    ? ActivityFeedRow(row: row, compact: true)
                    : ActivityFeedRowGroup(row: row),
              ),
            ),
          ),
        ),
      );
    },
  );
}

// --- Transaction row mapper ------------------------------------------------

/// `buildTransactionActivityRow` over a fixed `TransactionInfo`, rendered in
/// the real feed card. Desktop and mobile differ inside the mapper itself
/// (`kAppFormFactor` timestamp format and pending-title spacing), so the
/// compiled lane decides that half and there is no Layout knob.
Widget transactionActivityRowFixture({
  ActivityTxRowKind kind = ActivityTxRowKind.sent,
  ActivityTxRowStatus status = ActivityTxRowStatus.completed,
  ActivityTxRowPool pool = ActivityTxRowPool.shielded,
  ActivityTxRowAmount amount = ActivityTxRowAmount.value,
  bool privacyMode = false,
}) {
  return Builder(
    builder: (context) {
      final row = buildTransactionActivityRow(
        context: context,
        transaction: _transactionRowFixtureTx(
          kind: kind,
          status: status,
          pool: pool,
          amount: amount,
        ),
        giftCardKind: switch (kind) {
          ActivityTxRowKind.giftCardCreated => GiftCardActivityKind.created,
          ActivityTxRowKind.giftCardRedeemed => GiftCardActivityKind.redeemed,
          _ => null,
        },
        privacyModeEnabled: privacyMode,
        onTap: _galleryNoop,
      );
      return _galleryMappedRowFrame(context, row: row);
    },
  );
}

rust_sync.TransactionInfo _transactionRowFixtureTx({
  required ActivityTxRowKind kind,
  required ActivityTxRowStatus status,
  required ActivityTxRowPool pool,
  required ActivityTxRowAmount amount,
}) {
  final mined = status == ActivityTxRowStatus.completed;
  return rust_sync.TransactionInfo(
    txidHex: 'activity-row-mapper-gallery',
    minedHeight: mined ? BigInt.from(2100000) : BigInt.zero,
    expiredUnmined: status == ActivityTxRowStatus.failed,
    accountBalanceDelta: 0,
    fee: BigInt.from(10000),
    blockTime: BigInt.from(_activityApril12Epoch),
    isTransparent: pool == ActivityTxRowPool.transparent,
    txKind: switch (kind) {
      ActivityTxRowKind.received => 'received',
      ActivityTxRowKind.receiving => 'receiving',
      ActivityTxRowKind.sent || ActivityTxRowKind.giftCardCreated => 'sent',
      ActivityTxRowKind.shielded => 'shielded',
      ActivityTxRowKind.migration => 'migration',
      ActivityTxRowKind.giftCardRedeemed => 'received',
      ActivityTxRowKind.unknown => 'unrecognized',
    },
    displayAmount: amount == ActivityTxRowAmount.zero
        ? BigInt.zero
        : BigInt.from(412000000),
    displayPool: switch (pool) {
      ActivityTxRowPool.transparent => 'transparent',
      ActivityTxRowPool.shielded => 'shielded',
      ActivityTxRowPool.ironwood => 'ironwood',
      ActivityTxRowPool.mixed => 'mixed',
      ActivityTxRowPool.none => '',
    },
    createdTime: BigInt.zero,
  );
}

// --- Swap row mapper -------------------------------------------------------

/// `buildSwapActivityRow` over a fixed `SwapActivityRowItem`, rendered in the
/// real feed card. This mapper has no `kAppFormFactor` branch, so one case
/// covers both lanes.
Widget swapActivityRowFixture({
  SwapIntentStatus status = SwapIntentStatus.complete,
  ActivitySwapRowMode mode = ActivitySwapRowMode.swap,
  ActivitySwapRowDirection direction = ActivitySwapRowDirection.zecToAsset,
  ActivitySwapRowReceivedLeg receivedLeg = ActivitySwapRowReceivedLeg.absent,
  bool privacyMode = false,
}) {
  return Builder(
    builder: (context) {
      final sendsZec = direction == ActivitySwapRowDirection.zecToAsset;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        _activityApril11Epoch * 1000,
        isUtc: true,
      );
      final row = buildSwapActivityRow(
        context: context,
        item: SwapActivityRowItem(
          intentId: 'swap-row-mapper-gallery',
          providerLabel: 'Preview',
          sellAmountText: sendsZec ? '1.25 ZEC' : '26.60 USDC',
          receiveEstimateText: sendsZec ? '85.40 USDC' : '12.13 ZEC',
          status: status,
          direction: sendsZec
              ? SwapDirection.zecToExternal
              : SwapDirection.externalToZec,
          externalAsset: SwapAsset.usdc,
          activityTimestamp: timestamp,
          completedAt: timestamp,
          payMode: mode == ActivitySwapRowMode.pay,
        ),
        privacyModeEnabled: privacyMode,
        receivedAmountText: receivedLeg == ActivitySwapRowReceivedLeg.present
            ? '+12.05 ZEC'
            : null,
        onReceivedLegTap: receivedLeg == ActivitySwapRowReceivedLeg.present
            ? _galleryNoop
            : null,
        onTap: _galleryNoop,
      );
      return _galleryMappedRowFrame(context, row: row);
    },
  );
}

// --- Shared row fixture helpers --------------------------------------------

/// One mapped row on the feed's desktop card, so a mapper preview is read in
/// the surface the mapper actually feeds.
Widget _galleryMappedRowFrame(
  BuildContext context, {
  required ActivityRowData row,
}) {
  return ColoredBox(
    color: context.colors.background.window,
    child: Center(
      child: SizedBox(
        width: 460,
        child: ActivityFeed(
          sections: [
            ActivityFeedSectionData(title: 'April 2026', rows: [row]),
          ],
          showHeader: false,
          rowKeyPrefix: 'activity_row_mapper',
        ),
      ),
    ),
  );
}

ActivityRowData _galleryActivityRow(
  BuildContext context, {
  required String title,
  required String amountText,
  String iconName = AppIcons.plane,
  String? subtitle,
  String? subtitleIconName,
  String? amountIconName,
  String? amountSubtitle,
  String? amountSubtitleIconName,
  Color? amountColor,
  String statusText = 'Completed',
  String? statusIconName,
  Color? statusColor,
  Color? backgroundColor,
  bool selected = false,
  List<ActivityRowData> childRows = const [],
  VoidCallback? onTap,
}) {
  final colors = context.colors;
  return ActivityRowData(
    title: title,
    leadingIconName: iconName,
    leadingBackgroundColor: colors.background.neutralSubtleOpacity,
    leadingIconColor: colors.icon.regular,
    subtitle: subtitle,
    subtitleIconName: subtitleIconName,
    amountText: amountText,
    amountIconName: amountIconName,
    amountIconColor: amountIconName == null ? null : colors.icon.regular,
    amountColor: amountColor ?? colors.text.primary,
    amountSubtitle: amountSubtitle,
    amountSubtitleIconName: amountSubtitleIconName,
    amountSubtitleIconColor: amountSubtitleIconName == null
        ? null
        : colors.text.secondary,
    statusText: statusText,
    statusIconName: statusIconName,
    statusColor: statusColor ?? colors.text.secondary,
    backgroundColor: backgroundColor,
    selected: selected,
    timestampText: 'Apr 12, 13:11',
    childRows: childRows,
    onTap: onTap,
  );
}

void _galleryNoop() {}

// --- Swap detail screens ---------------------------------------------------

/// The intent statuses the two swap-detail hosts title differently.
enum SwapDetailStatus { awaitingDeposit, processing, complete, expired, failed }

/// A pay intent titles its own way; a swap intent follows the status
/// presentation.
enum SwapDetailMode { swap, payment }

/// Whether the routed intent id is in the swap state; a miss leaves the host
/// chrome around the "couldn't load this swap" panel.
enum SwapDetailIntentCase { present, missing }

const _swapDetailIntentId = 'home-gallery-swap-intent';
const _swapDetailMissingIntentId = 'home-gallery-swap-intent-missing';
const _swapDetailDepositAddress = 'u1widgetbookswapdetaildeposit';
const _swapDetailRecipient = '0x9e4c1f2a7b3d5e6f8a0b2c4d6e8f0a2b4c6d8e00';
const _swapDetailSpendableZatoshi = 1400000000;

/// Fixed timestamps — the detail rows date the swap, so a `now()` would make
/// the preview drift.
final _swapDetailCreatedAt = DateTime.utc(2026, 5, 14, 9, 41);
final _swapDetailCompletedAt = DateTime.utc(2026, 5, 14, 9, 58);

/// `SwapActivityDetailScreen` / `MobileSwapActivityDetailScreen`: the two
/// hosts around the shared `SwapActivityDetailSurface`.
///
/// The surface's own axes (deposit pages, notices, hardware routing) are
/// registered once under Screens > Swap; what these cases add is the chrome
/// the hosts own — the desktop sidebar shell and the mobile back nav whose
/// title `mobileSwapActivityTitle` derives from the intent status and mode.
Widget swapDetailScreenFixture({
  WbLayout layout = WbLayout.desktop,
  SwapDetailStatus status = SwapDetailStatus.processing,
  SwapDetailMode mode = SwapDetailMode.swap,
  SwapDetailIntentCase intentCase = SwapDetailIntentCase.present,
}) {
  final accountState = _homeAccountState(HomeAccountKind.software);
  final intent = _swapDetailIntent(status: status, mode: mode);
  return ProviderScope(
    overrides: [
      ..._homeOverrides(
        accountState: accountState,
        balance: HomeBalanceAmount.funded,
        activity: HomeActivityFeed.threeRows,
        sync: HomeSyncProgress.synced,
        network: HomeNetworkRoute.direct,
        notice: HomeNoticeKind.none,
        shieldAction: HomeShieldAction.enabled,
        priceChange: HomePriceChange.up,
        swapEnabled: true,
        privacyMode: false,
      ),
      ironwoodHomeBalancePresentationProvider.overrideWithValue(
        IronwoodHomeBalancePresentationMode.allShielded,
      ),
      ironwoodMigrationCoordinatorProvider.overrideWith(
        _HomeMigrationCoordinator.new,
      ),
      ironwoodMigrationAwareDisplaySpendableProvider.overrideWith(
        (ref, accountUuid) => BigInt.from(_swapDetailSpendableZatoshi),
      ),
      addressBookProvider.overrideWith(_ActivityAddressBookNotifier.new),
      swapStateProvider.overrideWith(
        () => _SwapDetailNotifier(_swapDetailState(intent)),
      ),
    ],
    child: _SwapDetailHarness(
      layout: layout,
      intentId: intentCase == SwapDetailIntentCase.present
          ? _swapDetailIntentId
          : _swapDetailMissingIntentId,
    ),
  );
}

SwapIntentStatus _swapDetailIntentStatus(SwapDetailStatus status) {
  return switch (status) {
    SwapDetailStatus.awaitingDeposit => SwapIntentStatus.awaitingDeposit,
    SwapDetailStatus.processing => SwapIntentStatus.processing,
    SwapDetailStatus.complete => SwapIntentStatus.complete,
    SwapDetailStatus.expired => SwapIntentStatus.expired,
    SwapDetailStatus.failed => SwapIntentStatus.failed,
  };
}

/// `depositDeadline` stays null so the deposit page's countdown never ticks.
SwapIntent _swapDetailIntent({
  required SwapDetailStatus status,
  required SwapDetailMode mode,
}) {
  return SwapIntent(
    id: _swapDetailIntentId,
    pair: 'ZEC -> USDC',
    sellAmount: '1.12 ZEC',
    receiveEstimate: '78.59 USDC',
    provider: 'NEAR Intents',
    status: _swapDetailIntentStatus(status),
    nextAction: 'Waiting for the provider',
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    accountUuid: _homeAccountUuid,
    depositAddress: _swapDetailDepositAddress,
    totalFeesText: '0.0012 ZEC',
    realisedSlippageText: '0.12%',
    oneClickRecipient: _swapDetailRecipient,
    oneClickRefundTo: 'u1widgetbookhomeaddress',
    createdAt: _swapDetailCreatedAt,
    completedAt: status == SwapDetailStatus.complete
        ? _swapDetailCompletedAt
        : null,
    payMode: mode == SwapDetailMode.payment,
  );
}

SwapState _swapDetailState(SwapIntent intent) {
  return SwapState(
    direction: SwapDirection.zecToExternal,
    amountText: '1.12',
    receiveAmountText: '78.59',
    destinationText: _swapDetailRecipient,
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: [intent],
    payMode: intent.payMode,
  );
}

/// Pins the swap state and neutralises the detail surface's actions: the real
/// ones reach the status client, the intent store and `DateTime.now()`.
/// `selectIntent` stays live — it only moves state, and the surface needs it
/// to pick its intent at all.
class _SwapDetailNotifier extends SwapNotifier {
  _SwapDetailNotifier(this._state);

  final SwapState _state;

  @override
  SwapState build() => _state;

  @override
  Future<void> refreshSelectedIntentStatus() async {}

  @override
  Future<void> markSelectedDepositClaimed() async {}

  @override
  Future<void> submitSelectedDepositTransaction() async {}

  @override
  void prepareRetryFromSelectedIntent() {}

  @override
  Future<void> removeIntent(String intentId) async {}
}

class _SwapDetailHarness extends StatefulWidget {
  const _SwapDetailHarness({required this.layout, required this.intentId});

  final WbLayout layout;
  final String intentId;

  @override
  State<_SwapDetailHarness> createState() => _SwapDetailHarnessState();
}

class _SwapDetailHarnessState extends State<_SwapDetailHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final mobile = widget.layout == WbLayout.mobile;
    _router = GoRouter(
      initialLocation: '/activity/swap/${widget.intentId}',
      routes: [
        GoRoute(
          path: '/activity/swap/:intentId',
          builder: (_, state) {
            final intentId = state.pathParameters['intentId']!;
            return mobile
                ? MobileSwapActivityDetailScreen(
                    swapIntentId: intentId,
                    launchExternalUri: (_) async {},
                  )
                : SwapActivityDetailScreen(
                    swapIntentId: intentId,
                    launchExternalUri: (_) async {},
                  );
          },
        ),
        for (final path in wbSidebarPaths)
          GoRoute(path: path, builder: (_, _) => _HomeRoutePlaceholder(path)),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = Router.withConfig(config: _router);
    if (widget.layout == WbLayout.mobile) {
      return _HomeMobileFrame(constrainToDesignSize: true, child: router);
    }
    return WbDesktopWindowBox(
      child: ColoredBox(
        color: context.colors.macosUtility.window,
        child: router,
      ),
    );
  }
}

// --- Shielding messages ----------------------------------------------------

/// Every message the shielding flow can put in front of the user.
///
/// Each option runs the production mapper rather than restating its copy, so
/// a reworded message shows up here. The vessel is the mobile toast; the
/// desktop home shows the same message set as a notice card driven by the
/// screen-local `_shieldBalanceError` (home_screen.dart:77, :399-400), which
/// no provider override can reach, so that shape stays uncovered.
enum HomeShieldMessage {
  noActiveAccount,
  passphraseUnavailable,
  syncRequired,
  balanceTooSmall,
  broadcastFailed,
  genericFailure,
  queuedForRetry,
  hardwareBroadcastUnknown,
  hardwareStorageFailed,
  hardwareStatusUncertain,
}

String homeShieldMessageText(HomeShieldMessage message) {
  return switch (message) {
    // The one literal: the screen raises it before any mapper runs.
    HomeShieldMessage.noActiveAccount => 'No active account.',
    HomeShieldMessage.passphraseUnavailable => friendlyShieldBalanceError(
      Exception('mnemonic missing for account'),
    ),
    HomeShieldMessage.syncRequired => friendlyShieldBalanceError(
      Exception('sync in progress'),
    ),
    HomeShieldMessage.balanceTooSmall => friendlyShieldBalanceError(
      Exception('insufficient transparent funds'),
    ),
    HomeShieldMessage.broadcastFailed => friendlyShieldBalanceError(
      Exception('SendTransaction rejected'),
    ),
    HomeShieldMessage.genericFailure => friendlyShieldBalanceError(
      Exception('unexpected fault'),
    ),
    HomeShieldMessage.queuedForRetry => shieldBalanceBroadcastStatusMessage(
      _homeShieldPendingResult,
    )!,
    HomeShieldMessage.hardwareBroadcastUnknown =>
      shieldPcztBroadcastStatusMessage(
        _homeShieldPcztResult('broadcast_unknown'),
      ),
    HomeShieldMessage.hardwareStorageFailed => shieldPcztBroadcastStatusMessage(
      _homeShieldPcztResult('broadcasted_storage_failed'),
    ),
    // The mapper's fallback branch: any status the broadcast reports that is
    // neither of the two named ones.
    HomeShieldMessage.hardwareStatusUncertain =>
      shieldPcztBroadcastStatusMessage(_homeShieldPcztResult('unknown')),
  };
}

/// The shielding toast as the mobile home raises it.
Widget homeShieldMessageFixture({required HomeShieldMessage message}) {
  return WbFrame(
    layout: WbLayout.mobile,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: AppToast(
          message: homeShieldMessageText(message),
          iconName: AppIcons.warning,
        ),
      ),
    ),
  );
}

final _homeShieldPendingResult = rust_sync.ShieldTransparentResult(
  txids: '',
  status: 'pending',
  broadcastedCount: 0,
  totalCount: 1,
  feeZatoshi: BigInt.from(10000),
  shieldedZatoshi: BigInt.from(1412000000),
);

rust_sync.ExtractAndBroadcastPcztResult _homeShieldPcztResult(String status) {
  return rust_sync.ExtractAndBroadcastPcztResult(
    txid: 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
    status: status,
  );
}

// --- Keystone shielding ----------------------------------------------------

/// Stages of the desktop shield signing overlay a preview can reach through
/// its preparation seam.
///
/// `broadcasting` and `broadcastWarning` are not options: the overlay only
/// enters them after a device scan returns signatures (`_getSignature` ->
/// `_broadcast`), which no preparation seam stands in for. The proving-params
/// prompt is inside the preparer the seam replaces, so it is out of reach too.
enum HomeKeystoneShieldDesktopStage { preparing, qrReady, failed }

/// Stages of the mobile shield signing screen a preview can reach.
///
/// Same broadcast limit as the desktop overlay; `scanning` is reachable
/// because the screen enters it from its own 'Next step' button.
enum HomeKeystoneShieldMobileStage { preparing, qrReady, scanning, failed }

/// `KeystoneShieldSigningOverlay` over an empty desktop pane.
///
/// The overlay is the whole surface here: a modal preview sits on a plain
/// frame rather than over a live home screen.
Widget homeKeystoneShieldDesktopFixture({
  HomeKeystoneShieldDesktopStage stage = HomeKeystoneShieldDesktopStage.qrReady,
}) {
  return ProviderScope(
    // The overlay widens the window on mount; the real notifier drives
    // `window_manager`.
    overrides: [appLayoutProvider.overrideWith(_HomeNoOpLayoutNotifier.new)],
    child: WbFrame(
      layout: WbLayout.desktop,
      child: KeystoneShieldSigningOverlay(
        // Preparation runs from `initState`, so the stage only changes on a
        // remount.
        key: ValueKey('wb_home_keystone_shield_desktop_${stage.name}'),
        onCancel: _shieldNoop,
        onComplete: _shieldNoop,
        preparePczt: switch (stage) {
          // Never completes: the overlay's own preparing phase.
          HomeKeystoneShieldDesktopStage.preparing =>
            () => Completer<KeystoneShieldPreparedPczt?>().future,
          HomeKeystoneShieldDesktopStage.qrReady =>
            () async => KeystoneShieldPreparedPczt(
              urParts: _shieldPreviewUrParts(),
              pcztWithProofs: const [],
              saplingParams: _shieldPreviewSaplingParams,
              needsSaplingParams: false,
            ),
          // The copy is the overlay's own mapping of a Rust failure.
          HomeKeystoneShieldDesktopStage.failed => () async => throw Exception(
            'transparent balance too small to shield',
          ),
        },
      ),
    ),
  );
}

/// `MobileKeystoneShieldScreen` in a phone frame.
Widget homeKeystoneShieldMobileFixture({
  HomeKeystoneShieldMobileStage stage = HomeKeystoneShieldMobileStage.qrReady,
}) {
  final scanning = stage == HomeKeystoneShieldMobileStage.scanning;
  if (scanning) {
    // The scanning stage mounts a real `MobileScanner`; these are the camera
    // and UR-decode stand-ins every scanner surface previews against. The fake
    // is a process-wide singleton, so pin the live feed here instead of
    // inheriting whatever a Scanner case configured earlier in the session.
    WbFakeMobileScannerPlatform.ensureInstalled().configure(
      startResult: WbFakeScannerStart.running,
      cameras: const [kWbFakeBackCamera],
    );
    WbFakeUrScanRustApi.install();
  }
  return ProviderScope(
    child: _HomeMobileFrame(
      constrainToDesignSize: true,
      child: _HomeShieldNextStepOnMount(
        key: ValueKey('wb_home_keystone_shield_mobile_${stage.name}'),
        enabled: scanning,
        child: _ShieldMobileHarness(
          preparePczt: switch (stage) {
            HomeKeystoneShieldMobileStage.preparing =>
              () => Completer<MobileKeystoneShieldPreparedPczt?>().future,
            HomeKeystoneShieldMobileStage.qrReady ||
            HomeKeystoneShieldMobileStage.scanning =>
              () async => MobileKeystoneShieldPreparedPczt(
                urParts: _shieldPreviewUrParts(),
                saplingParams: _shieldPreviewSaplingParams,
                needsSaplingParams: false,
                addProofs: () async => Uint8List(0),
              ),
            HomeKeystoneShieldMobileStage.failed => () async => throw Exception(
              'transparent balance too small to shield',
            ),
          },
        ),
      ),
    ),
  );
}

/// `MobileKeystoneShieldScreen` under the home route it is pushed from: its
/// terminal 'Back to wallet' calls `context.pop()`, which needs a router.
class _ShieldMobileHarness extends StatefulWidget {
  const _ShieldMobileHarness({required this.preparePczt});

  final MobileKeystoneShieldPcztPreparer preparePczt;

  @override
  State<_ShieldMobileHarness> createState() => _ShieldMobileHarnessState();
}

class _ShieldMobileHarnessState extends State<_ShieldMobileHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/home/keystone-shield',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const _HomeRoutePlaceholder('/home'),
          routes: [
            GoRoute(
              path: 'keystone-shield',
              builder: (_, _) =>
                  MobileKeystoneShieldScreen(preparePczt: widget.preparePczt),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Router.withConfig(config: _router);
}

void _shieldNoop() {}

const _shieldPreviewSaplingParams = SaplingParamsStatus(
  spendPath: '/widgetbook/sapling-spend.params',
  outputPath: '/widgetbook/sapling-output.params',
  spendExists: true,
  outputExists: true,
);

/// A 12-part `zcash-pczt` UR, so the QR animates the way a real shield PCZT
/// does without any Rust encoding.
List<String> _shieldPreviewUrParts() {
  const payload =
      'lpadaxcsfwdmfwfwhdcxhdcxfwcxhdcxhdcxfwcxhdcxhdcxfwcxhdcxhdcxfwcx'
      'hdcxhdcxfwcxhdcxhdcxfwcxhdcxhdcxfwcxhdcxhdcxfwcxhdcxhdcxfwcxhdcx';
  return [
    for (var i = 1; i <= 12; i++)
      'ur:zcash-pczt/$i-12/$payload${i.toString().padLeft(2, '0')}',
  ];
}

/// Presses the mobile shield screen's own 'Next step' button once the QR is
/// on screen: the scanning stage lives in private state behind that button.
class _HomeShieldNextStepOnMount extends StatefulWidget {
  const _HomeShieldNextStepOnMount({
    required this.enabled,
    required this.child,
    super.key,
  });

  final bool enabled;
  final Widget child;

  @override
  State<_HomeShieldNextStepOnMount> createState() =>
      _HomeShieldNextStepOnMountState();
}

class _HomeShieldNextStepOnMountState
    extends State<_HomeShieldNextStepOnMount> {
  static const _maxAttempts = 12;
  var _attempts = 0;
  var _done = false;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _press());
  }

  void _press() {
    if (_done || !mounted) return;
    final onPressed = _nextStepCallback();
    if (onPressed == null) {
      if (++_attempts >= _maxAttempts) {
        // Debug-only, so a fixture stuck before the QR fails in the widgetbook
        // and in tests instead of previewing the wrong stage.
        assert(false, 'The shield screen never enabled its Next step button.');
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _press());
      // A post-frame callback only runs if another frame is produced.
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    _done = true;
    onPressed();
  }

  /// The button's own `onPressed`; it is null until preparation lands, which
  /// is exactly when the stage may advance.
  VoidCallback? _nextStepCallback() {
    VoidCallback? onPressed;
    void findButton(Element element) {
      if (onPressed != null) return;
      final widget = element.widget;
      if (widget is AppButton && widget.onPressed != null) {
        final label = widget.child;
        if (label is Text && label.data == 'Next step') {
          onPressed = widget.onPressed;
          return;
        }
      }
      element.visitChildren(findButton);
    }

    context.visitChildElements(findButton);
    return onPressed;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
