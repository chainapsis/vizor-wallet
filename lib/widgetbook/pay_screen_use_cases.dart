// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/config/swap_feature_config.dart';
import '../src/core/layout/app_layout.dart';
import '../src/core/profile_pictures.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/address_book/models/address_book_contact.dart';
import '../src/features/address_book/providers/address_book_provider.dart';
import '../src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import '../src/features/pay/screens/mobile/mobile_pay_screen.dart';
import '../src/features/pay/screens/mobile/mobile_pay_submitted_screen.dart';
import '../src/features/pay/screens/pay_screen.dart';
import '../src/features/pay/models/pay_recent_recipients.dart';
import '../src/features/swap/screens/mobile/mobile_swap_review_screen.dart';
import '../src/features/activity/screens/swap_activity_detail_screen.dart';
import '../src/features/activity/screens/mobile/mobile_swap_activity_detail_screen.dart';
import '../src/features/swap/models/swap_activity_navigation.dart';
import '../src/features/send/services/send_proving_key_warmup.dart';
import '../src/features/swap/models/swap_models.dart';
import '../src/features/swap/providers/swap_activity_store.dart'
    show swapActivityRecordsProvider;
import '../src/features/swap/providers/pay_selected_asset_store.dart';
import '../src/features/swap/providers/swap_composer_preferences_store.dart';
import '../src/features/swap/providers/swap_state_provider.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/network_privacy_provider.dart';
import '../src/providers/privacy_mode_provider.dart';
import '../src/providers/zec_price_change_provider.dart';
import '../src/providers/sync_provider.dart';
import 'support/wb_layout.dart';
import 'support/wb_sidebar.dart';
import 'support/wb_address_book_repository.dart';

const _payShellAccountUuid = 'widgetbook-pay-screen-account';
const _payShellContactAddress = '0x52908400098527886E0F7030069857D2E4169EE7';
const _payShellWindowSize = Size(1080, 720);
const _payShellPhoneSize = Size(393, 852);
const _payShellPhoneSafeArea = EdgeInsets.only(top: 55, bottom: 24);

/// The composer state the real screens receive from `SwapNotifier` once Pay
/// has been prepared from shielded ZEC: an exact-output USDC amount with the
/// indicative ZEC spend already derived.
const _payShellState = SwapState(
  direction: SwapDirection.zecToExternal,
  quoteMode: SwapQuoteMode.exactOutput,
  amountText: '2.251',
  receiveAmountText: '990',
  receiveFiatText: '990.00',
  destinationText: '',
  externalAsset: SwapAsset.usdc,
  supportedExternalAssets: [SwapAsset.usdc],
  reviewVisible: false,
  intents: [],
  payMode: true,
);

const _payShellPricingLoadingState = SwapState(
  direction: SwapDirection.zecToExternal,
  quoteMode: SwapQuoteMode.exactOutput,
  amountText: '',
  receiveAmountText: '990',
  receiveFiatText: '',
  destinationText: '',
  externalAsset: SwapAsset.usdc,
  supportedExternalAssets: [SwapAsset.usdc],
  reviewVisible: false,
  intents: [],
  pricingLoading: true,
  payMode: true,
);

/// Deterministic service outcomes for the actual Pay screen preview. The
/// screen and its routes are production widgets; only quote/start calls are
/// simulated in memory.
enum PayScreenSimulationScenario {
  happyPath,
  unavailableQuote,
  invalidRecipient,
  expiredQuote,
}

String payScreenSimulationScenarioLabel(
  PayScreenSimulationScenario value,
) => switch (value) {
  PayScreenSimulationScenario.happyPath => 'Happy path',
  PayScreenSimulationScenario.unavailableQuote => 'Unavailable quote and retry',
  PayScreenSimulationScenario.invalidRecipient => 'Invalid recipient',
  PayScreenSimulationScenario.expiredQuote => 'Expired quote',
};

SwapState _payInteractiveState({required bool pricingLoading}) => SwapState(
  direction: SwapDirection.zecToExternal,
  quoteMode: SwapQuoteMode.exactOutput,
  amountText: '',
  receiveAmountText: '',
  destinationText: '',
  externalAsset: SwapAsset.usdc,
  supportedExternalAssets: const [SwapAsset.usdc, SwapAsset.eth, SwapAsset.btc],
  reviewVisible: false,
  intents: const [],
  pricingLoading: pricingLoading,
  payMode: true,
  indicativeExternalPerZec: {SwapAsset.usdc: 70},
  indicativeUsdPrices: {SwapAsset.usdc: 1},
);

final _payShellAccountState = AccountState(
  accounts: const [
    AccountInfo(
      uuid: _payShellAccountUuid,
      name: 'Account Name',
      order: 0,
      isSeedAnchor: true,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: _payShellAccountUuid,
  activeAddress: 'u1widgetbookpayscreenaddress',
);

final _payShellSyncState = SyncState(
  accountUuid: _payShellAccountUuid,
  hasAccountScopedData: true,
  isSyncComplete: true,
  percentage: 1,
  scannedHeight: 3428143,
  chainTipHeight: 3428143,
  orchardBalance: BigInt.from(14223000000),
  spendableBalance: BigInt.from(14223000000),
  totalBalance: BigInt.from(14223000000),
);

const _payShellContacts = AddressBookState(
  contacts: [
    AddressBookContact(
      id: 'widgetbook-pay-screen-mike',
      label: 'Mike',
      network: AddressBookNetwork.ethereum,
      address: _payShellContactAddress,
      profilePictureId: 'pfp-01',
      createdAtMs: 0,
      updatedAtMs: 0,
    ),
  ],
);

final _payShellBootstrap = AppBootstrapState(
  initialLocation: '/pay',
  initialAccountState: _payShellAccountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

/// Wraps [child] in every provider override a real Pay-feature screen and its
/// `AppMainSidebar` need. Shared with the Donation screen fixture, which sits
/// behind the same shell.
Widget payPreviewShellScope({
  required Widget child,
  SwapState swapState = _payShellState,
  SwapNotifier Function()? swapNotifierBuilder,
  double? zecUsdPrice = 70,
}) {
  const migration = IronwoodHomeMigrationCtaState.hidden();
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_payShellBootstrap),
      // `AppLayoutNotifier.setMode` reshapes the native window through
      // `window_manager`, which belongs to the dev tool in a preview.
      appLayoutProvider.overrideWith(_PayPreviewLayoutNotifier.new),
      sendProvingKeyWarmupProvider.overrideWithValue(() {}),
      accountProvider.overrideWith(
        () => _PayPreviewAccountNotifier(_payShellAccountState),
      ),
      syncProvider.overrideWith(
        () => _PayPreviewSyncNotifier(_payShellSyncState),
      ),
      addressBookRepositoryProvider.overrideWith(
        (ref) => WbAddressBookRepository(),
      ),
      wbSidebarActions,
      addressBookProvider.overrideWith(
        () => _PayPreviewAddressBookNotifier(_payShellContacts),
      ),
      swapStateProvider.overrideWith(
        swapNotifierBuilder ?? () => _PayPreviewSwapNotifier(swapState),
      ),
      paySelectedAssetStoreProvider.overrideWithValue(
        _WidgetbookPaySelectedAssetStore(),
      ),
      swapComposerPreferencesStoreProvider.overrideWithValue(
        _WidgetbookSwapComposerPreferencesStore(),
      ),
      swapActivityRecordsProvider.overrideWith(
        (ref, accountUuid) async => const <SwapIntentRecord>[],
      ),
      privacyModeProvider.overrideWith(_PayPreviewPrivacyModeNotifier.new),
      networkPrivacyProvider.overrideWith(
        _PayPreviewNetworkPrivacyNotifier.new,
      ),
      swapFeatureEnabledProvider.overrideWithValue(true),
      zecLiveUsdUnitPriceProvider.overrideWithValue(zecUsdPrice),
      ironwoodHomeMigrationCtaProvider.overrideWith((ref) async => migration),
      ironwoodHomeMigrationPresentationProvider.overrideWithValue(migration),
      ironwoodMigrationAnnouncementProvider.overrideWith(
        (ref) async => const IronwoodMigrationAnnouncementState.hidden(),
      ),
    ],
    child: child,
  );
}

/// The real `PayScreen` / `MobilePayScreen` on the amount step.
Widget payWizardShellFixture({
  bool mobile = false,
  bool pricingLoading = false,
}) {
  return payPreviewShellScope(
    swapState: pricingLoading ? _payShellPricingLoadingState : _payShellState,
    child: _PayScreenHarness(mobile: mobile),
  );
}

/// The primary gallery entry. It mounts the actual Pay screen rather than a
/// separate visual flow layered over a snapshot.
Widget payInteractiveScreenFixture({
  required bool mobile,
  required bool pricingLoading,
  required PayScreenSimulationScenario scenario,
}) {
  final state = _payInteractiveState(pricingLoading: pricingLoading);
  return payPreviewShellScope(
    swapState: state,
    swapNotifierBuilder: () => _PayInteractiveSwapNotifier(state, scenario),
    child: _PayScreenHarness(mobile: mobile, interactive: true),
  );
}

Widget buildPayWizardShellUseCase(BuildContext context) =>
    payWizardShellFixture();

Widget buildPayWizardShellPricingLoadingUseCase(BuildContext context) =>
    payWizardShellFixture(pricingLoading: true);

Widget buildMobilePayWizardShellUseCase(BuildContext context) =>
    payWizardShellFixture(mobile: true);

Widget buildMobilePayWizardShellPricingLoadingUseCase(BuildContext context) =>
    payWizardShellFixture(mobile: true, pricingLoading: true);

/// `AppMainSidebar` and `AppPaneToolbar` resolve their active item and back
/// label through `GoRouterState.of`, which needs a real matched route rather
/// than a detached `InheritedGoRouter`.
class _PayScreenHarness extends StatefulWidget {
  const _PayScreenHarness({required this.mobile, this.interactive = false});

  final bool mobile;
  final bool interactive;

  @override
  State<_PayScreenHarness> createState() => _PayScreenHarnessState();
}

class _PayScreenHarnessState extends State<_PayScreenHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/pay',
      routes: [
        GoRoute(
          path: '/pay',
          builder:
              (_, _) =>
                  widget.mobile
                      ? MobilePayScreen(
                        preservePreparedComposer: widget.interactive,
                      )
                      : PayScreen(preservePreparedComposer: widget.interactive),
        ),
        GoRoute(
          path: '/pay/review',
          builder:
              (_, state) => MobileSwapReviewScreen(
                payMode: true,
                recipientSelection:
                    state.extra is PayRecipientSelection
                        ? state.extra! as PayRecipientSelection
                        : null,
              ),
        ),
        GoRoute(
          path: '/pay/submitted/:intentId',
          builder:
              (_, state) => MobilePaySubmittedScreen(
                intentId: state.pathParameters['intentId'] ?? '',
              ),
        ),
        GoRoute(
          path: '/activity/swap/:swapId',
          builder:
              (_, state) =>
                  widget.mobile
                      ? MobileSwapActivityDetailScreen(
                        swapIntentId: state.pathParameters['swapId'] ?? '',
                        returnTarget: SwapActivityReturnTarget.pay,
                        launchExternalUri: (_) async {},
                      )
                      : SwapActivityDetailScreen(
                        swapIntentId: state.pathParameters['swapId'] ?? '',
                        returnTarget: SwapActivityReturnTarget.pay,
                        launchExternalUri: (_) async {},
                      ),
        ),
        for (final path in wbSidebarPaths)
          if (path != '/pay')
            GoRoute(path: path, builder: (_, _) => wbSidebarDestination(path)),
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
    // IgnorePointer keeps it a static gallery snapshot: sidebar and back taps
    // navigate to routes this preview router does not carry.
    final router =
        widget.interactive
            ? Router.withConfig(config: _router)
            : IgnorePointer(child: Router.withConfig(config: _router));
    if (!widget.mobile) {
      return Center(
        child: WbDesktopWindowBox(
          size: _payShellWindowSize,
          child: ColoredBox(
            color: context.colors.macosUtility.window,
            child: router,
          ),
        ),
      );
    }
    final mediaQuery = MediaQuery.of(context);
    return Center(
      child: WbScaleDownBox(
        size: _payShellPhoneSize,
        child: SizedBox.fromSize(
          size: _payShellPhoneSize,
          child: ClipRect(
            child: MediaQuery(
              data: mediaQuery.copyWith(
                size: _payShellPhoneSize,
                padding: _payShellPhoneSafeArea,
                viewPadding: _payShellPhoneSafeArea,
              ),
              child: router,
            ),
          ),
        ),
      ),
    );
  }
}

/// The real `SwapNotifier.build` loads supported assets over the network and
/// restores persisted composer state, and the screens call
/// `preparePayFromShieldedZec` on their first frame.
class _PayPreviewSwapNotifier extends SwapNotifier {
  _PayPreviewSwapNotifier(this.initialState);

  final SwapState initialState;

  @override
  SwapState build() => initialState;

  @override
  bool preparePayFromShieldedZec({
    SwapAsset? preferredAsset,
    String? expectedAccountUuid,
  }) => true;
}

/// Preview-only stores ensure inherited SwapNotifier setters cannot reach
/// AppSecureStore while an actual Pay screen is being interacted with.
class _WidgetbookPaySelectedAssetStore implements PaySelectedAssetStore {
  final Map<String, SwapAsset> _assets = {};

  @override
  Future<SwapAsset?> loadSelectedAsset({required String accountUuid}) async =>
      _assets[accountUuid];

  @override
  Future<void> saveSelectedAsset({
    required String accountUuid,
    required SwapAsset asset,
  }) async {
    _assets[accountUuid] = asset;
  }
}

class _WidgetbookSwapComposerPreferencesStore
    implements SwapComposerPreferencesStore {
  final Map<String, SwapComposerPreferences> _preferences = {};

  @override
  Future<SwapComposerPreferences?> loadPreferences({
    required String accountUuid,
  }) async => _preferences[accountUuid];

  @override
  Future<void> savePreferences({
    required String accountUuid,
    required SwapComposerPreferences preferences,
  }) async {
    _preferences[accountUuid] = preferences;
  }
}

class _PayInteractiveSwapNotifier extends _PayPreviewSwapNotifier {
  _PayInteractiveSwapNotifier(super.initialState, this.scenario);

  final PayScreenSimulationScenario scenario;
  var _quoteFailedOnce = false;

  @override
  Future<void> showReview({bool preserveCurrentReview = false}) async {
    if (!state.canReviewQuote) return;
    if (scenario == PayScreenSimulationScenario.invalidRecipient) {
      state = state.copyWith(
        quoteError: 'Enter a valid recipient.',
        reviewVisible: false,
        clearReview: true,
      );
      return;
    }
    if (scenario == PayScreenSimulationScenario.unavailableQuote &&
        !_quoteFailedOnce) {
      _quoteFailedOnce = true;
      state = state.copyWith(
        quoteError: 'No quote is available. Try again.',
        reviewVisible: false,
        clearReview: true,
      );
      return;
    }
    final quote = SwapQuote.estimate(
      direction: state.direction,
      mode: state.quoteMode,
      externalAsset: state.externalAsset,
      amount: state.quoteAmount!,
      externalPerZec: state.indicativeExternalPerZec[state.externalAsset],
      slippageBps: state.slippageBps,
      expiryLabel:
          scenario == PayScreenSimulationScenario.expiredQuote
              ? 'Quote expired'
              : '1:30',
    );
    state = state.copyWith(
      reviewVisible: true,
      reviewQuote: quote,
      reviewAddressPlan: state.draftAddressPlan,
      reviewAccountUuid: _payShellAccountUuid,
      quoteExpired: scenario == PayScreenSimulationScenario.expiredQuote,
      clearQuoteError: true,
    );
  }

  @override
  Future<SwapStartResult?> startIntent() async {
    final quote = state.reviewQuote;
    if (quote == null ||
        state.reviewAddressPlan == null ||
        state.quoteExpired) {
      return null;
    }
    const id = 'widgetbook-pay-simulated';
    final intent = SwapIntent(
      id: id,
      pair: quote.pairText,
      sellAmount: quote.sellAmountText,
      receiveEstimate: quote.receiveEstimateText,
      provider: 'Simulated Widgetbook',
      status: SwapIntentStatus.complete,
      nextAction: 'Complete',
      direction: quote.direction,
      externalAsset: quote.externalAsset,
      oneClickRecipient: state.destinationText,
      accountUuid: _payShellAccountUuid,
      payMode: true,
      depositTxHash: 'simulated-payment-tx',
      createdAt: DateTime.utc(2026, 9, 14),
      completedAt: DateTime.utc(2026, 9, 14),
    );
    state = state.copyWith(
      intents: [intent],
      selectedIntentId: id,
      startSubmitting: false,
    );
    return const SwapStartedActivity(id);
  }
}

class _PayPreviewAccountNotifier extends AccountNotifier {
  _PayPreviewAccountNotifier(this.initialState);

  final AccountState initialState;

  @override
  FutureOr<AccountState> build() => initialState;
}

class _PayPreviewSyncNotifier extends SyncNotifier {
  _PayPreviewSyncNotifier(this.initialState);

  final SyncState initialState;

  @override
  Future<SyncState> build() async => initialState;
}

class _PayPreviewAddressBookNotifier extends AddressBookNotifier {
  _PayPreviewAddressBookNotifier(this.initialState);

  final AddressBookState initialState;

  @override
  Future<AddressBookState> build() async => initialState;
}

class _PayPreviewPrivacyModeNotifier extends PrivacyModeNotifier {
  @override
  Future<void> set(bool enabled) async {
    state = enabled;
  }
}

class _PayPreviewLayoutNotifier extends AppLayoutNotifier {
  @override
  AppLayoutState build() => const AppLayoutState(AppLayoutMode.large);

  @override
  Future<void> setMode(AppLayoutMode mode) async {}
}

class _PayPreviewNetworkPrivacyNotifier extends NetworkPrivacyNotifier {
  @override
  NetworkPrivacyState build() => const NetworkPrivacyState.off();

  @override
  Future<void> setTorEnabled(bool enabled) async {}
}
