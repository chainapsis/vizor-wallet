// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:async';

import 'package:flutter/material.dart' show Material, MaterialType, ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/config/swap_feature_config.dart';
import '../src/core/formatting/zec_amount.dart';
import '../src/core/layout/app_layout.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_back_link.dart';
import '../src/core/widgets/app_button.dart';
import '../src/features/address_book/models/address_book_contact.dart';
import '../src/features/address_book/providers/address_book_provider.dart';
import '../src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import '../src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import '../src/features/send/models/send_prefill_args.dart';
import '../src/features/send/screens/mobile/mobile_keystone_sign_screen.dart';
import '../src/features/send/screens/mobile/mobile_send_screen.dart'
    show
        MobileSaplingParamsSheet,
        MobileSendAmountInputMode,
        MobileSendFeeEstimator,
        MobileSendScreen;
import '../src/features/send/screens/mobile/mobile_send_status_screen.dart';
import '../src/features/send/screens/send_review_screen.dart';
import '../src/features/send/screens/send_screen.dart';
import '../src/features/send/screens/send_status_screen.dart';
import '../src/features/send/services/send_flow.dart';
import '../src/features/send/services/send_proving_key_warmup.dart';
import '../src/features/send/widgets/sapling_params_prompt.dart';
import '../src/features/send/widgets/send_recipient_resolver.dart';
import '../src/features/send/widgets/send_status_content_view.dart';
import '../src/features/send/widgets/send_verify_address_overlay.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/privacy_mode_provider.dart';
import '../src/providers/receive_address_provider.dart';
import '../src/providers/sync_display_progress_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/providers/wallet_provider.dart';
import '../src/providers/zec_price_change_provider.dart';
import '../src/rust/api/sync.dart' as rust_sync;
import 'support/wb_layout.dart';
import 'support/wb_sidebar.dart';
import 'send_review_status_use_cases.dart';
import 'send_use_cases.dart'
    show
        kMobileSendSaplingAddress,
        kMobileSendUnifiedAddress,
        kMobileSendWrongNetworkAddress;

// --- Shared preview data ----------------------------------------------------

const _accountUuid = 'widgetbook-send-screen';
const _keystoneAccountUuid = 'widgetbook-send-screen-keystone';

/// Raw shielded recipient: in neither the address book nor the own-account map.
const kSendScreenFixtureAddress =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';

/// Shielded recipient the fixture's address book labels.
const kSendScreenFixtureContactAddress =
    'u1c0nta3ct5183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a37'
    '02b73d57f73c6dc05121591a83861cd190592';

/// Shielded recipient the fixture reports as one of the wallet's own accounts.
const kSendScreenFixtureOwnAccountAddress =
    'u10wn4cc0unt83f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a37'
    '02b73d57f73c6dc05121591a83861cd190593';

/// Transparent recipient; also carried by the same contact / own-account maps
/// so the pool axis stays orthogonal to the recipient-identity axis.
const kSendScreenFixtureTransparentAddress =
    't1aWwWwqk3jYGkZc7nLGuTvuM8hDywMZCo';
const kSendScreenFixtureTransparentContactAddress =
    't1c0ntactWwqk3jYGkZc7nLGuTvuM8hDywM';
const kSendScreenFixtureTransparentOwnAccountAddress =
    't10wnaccountqk3jYGkZc7nLGuTvuM8hDyw';

/// TEX recipient: the address type that splits a Keystone send into two
/// signing rounds.
const kSendScreenFixtureTexAddress =
    'tex1s2rt77ggv6q989lr23rrx8mzva7gnzqsurw2jw';

const _softwareAccount = AccountInfo(
  uuid: _accountUuid,
  name: 'Account 1',
  order: 0,
  isSeedAnchor: true,
  profilePictureId: 'pfp-01',
);

const _keystoneAccount = AccountInfo(
  uuid: _keystoneAccountUuid,
  name: 'Keystone',
  order: 1,
  isHardware: true,
  profilePictureId: 'pfp-04',
);

const _ownAccount = AccountInfo(
  uuid: 'widgetbook-send-screen-savings',
  name: 'Savings',
  order: 2,
  profilePictureId: 'pfp-05',
);

const _contacts = [
  AddressBookContact(
    id: 'send-screen-contact',
    label: 'Blue Door Coffee',
    network: AddressBookNetwork.zcash,
    address: kSendScreenFixtureContactAddress,
    profilePictureId: 'pfp-02',
    createdAtMs: 1,
    updatedAtMs: 1,
  ),
  AddressBookContact(
    id: 'send-screen-contact-transparent',
    label: 'Blue Door Coffee',
    network: AddressBookNetwork.zcash,
    address: kSendScreenFixtureTransparentContactAddress,
    profilePictureId: 'pfp-02',
    createdAtMs: 2,
    updatedAtMs: 2,
  ),
];

const _ownAccountAddresses = {
  kSendScreenFixtureOwnAccountAddress: _ownAccount,
  kSendScreenFixtureTransparentOwnAccountAddress: _ownAccount,
};

AccountState _accountState({bool hardware = false}) {
  return AccountState(
    accounts: const [_softwareAccount, _keystoneAccount, _ownAccount],
    activeAccountUuid: hardware ? _keystoneAccountUuid : _accountUuid,
    activeAddress: kSendScreenFixtureAddress,
  );
}

AppBootstrapState _bootstrap({
  required AccountState accountState,
  required bool privacyMode,
}) {
  return AppBootstrapState(
    initialLocation: '/send',
    initialAccountState: accountState,
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: defaultRpcEndpointConfig('main'),
    themeMode: ThemeMode.system,
    privacyModeEnabled: privacyMode,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}

SyncState _syncState({
  required String accountUuid,
  BigInt? orchardBalance,
  BigInt? ironwoodBalance,
}) {
  final orchard = orchardBalance ?? BigInt.zero;
  final ironwood = ironwoodBalance ?? BigInt.zero;
  return SyncState(
    accountUuid: accountUuid,
    hasAccountScopedData: true,
    isSyncComplete: true,
    percentage: 1,
    scannedHeight: 3_428_143,
    chainTipHeight: 3_428_143,
    orchardBalance: orchard,
    ironwoodBalance: ironwood,
    spendableBalance: orchard + ironwood,
    totalBalance: orchard + ironwood,
  );
}

/// Minimal in-flight migration run: only `mode == resume` reaches the send
/// composer, which swaps the spendable balance for the Ironwood one.
rust_sync.MigrationStatus _resumeMigrationStatus() {
  return rust_sync.MigrationStatus(
    phase: 'waiting_confirmations',
    activeRunId: 'widgetbook-send-run',
    targetValuesZatoshi: frb.Uint64List.fromList(const [2_000_000_000]),
    preparedNoteCount: 1,
    denominationConfirmationCount: 3,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 1,
    pendingTxCount: 1,
    broadcastedTxCount: 0,
    confirmedTxCount: 0,
    totalCount: 1,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 35,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 960,
    scheduledBroadcasts: const [],
    parts: const [],
  );
}

// --- Shared scope + router harness ------------------------------------------

/// ProviderScope every desktop send screen fixture renders inside.
///
/// `AppMainSidebar` (the shell the send screens mount) reads the account,
/// sync, privacy, swap-flag and Ironwood providers as well, so they are all
/// seeded here rather than per fixture.
Widget _sendScreenScope({
  required Widget child,
  required AccountState accountState,
  SyncState? syncState,
  IronwoodHomeMigrationCtaState migrationCta =
      const IronwoodHomeMigrationCtaState.hidden(),
  WalletNotifier Function()? wallet,
  bool privacyMode = false,
  List<AddressBookContact> contacts = _contacts,
  Map<String, AccountInfo> ownAccountAddresses = _ownAccountAddresses,
  double? zecUsdUnitPrice = 70,
}) {
  final accountUuid = accountState.activeAccountUuid!;
  return ProviderScope(
    // Riverpod 3 retries a failed provider on a backoff timer, which would
    // bounce the error preview back to a spinner (and leave a timer running).
    retry: (_, _) => null,
    overrides: [
      sendPreviousTransactionCountLoaderProvider.overrideWithValue(
        ({required network, required accountUuid, required address}) async => 0,
      ),
      appBootstrapProvider.overrideWithValue(
        _bootstrap(accountState: accountState, privacyMode: privacyMode),
      ),
      sendWalletDbPathProvider.overrideWithValue(
        () async => '/tmp/widgetbook-zcash-wallet.db',
      ),
      accountProvider.overrideWith(
        () => _SendPreviewAccountNotifier(accountState),
      ),
      if (wallet != null) walletProvider.overrideWith(wallet),
      syncProvider.overrideWith(
        () => _SendPreviewSyncNotifier(
          syncState ??
              _syncState(
                accountUuid: accountUuid,
                orchardBalance: BigInt.from(14_312_120_000),
              ),
        ),
      ),
      syncDisplayWholePercentageProvider.overrideWithValue(100),
      privacyModeProvider.overrideWith(_SendPreviewPrivacyModeNotifier.new),
      appLayoutProvider.overrideWith(_SendPreviewLayoutNotifier.new),
      sendProvingKeyWarmupProvider.overrideWithValue(() {}),
      wbSidebarActions,
      receiveAddressServiceProvider.overrideWithValue(
        const _SendPreviewReceiveAddressService(),
      ),
      addressBookRepositoryProvider.overrideWithValue(
        _SendPreviewAddressBookRepository(contacts),
      ),
      ownAccountAddressesProvider.overrideWith(
        (ref) async => ownAccountAddresses,
      ),
      // Null is the live price still in flight, which is what puts the
      // composer's conversion line on its loading placeholder.
      zecLiveUsdUnitPriceProvider.overrideWithValue(zecUsdUnitPrice),
      zecHomeUsdUnitPriceProvider.overrideWithValue(zecUsdUnitPrice),
      zecPriceChange24hPctProvider.overrideWithValue(13.12),
      swapFeatureEnabledProvider.overrideWithValue(false),
      ironwoodHomeMigrationCtaProvider.overrideWith(
        (ref) async => migrationCta,
      ),
      ironwoodHomeMigrationPresentationProvider.overrideWithValue(migrationCta),
      ironwoodHomeBalancePresentationProvider.overrideWithValue(
        migrationCta.mode == IronwoodHomeMigrationCtaMode.resume
            ? IronwoodHomeBalancePresentationMode.ironwoodOnly
            : IronwoodHomeBalancePresentationMode.allShielded,
      ),
      ironwoodMigrationCoordinatorProvider.overrideWith(
        _SendPreviewMigrationCoordinator.new,
      ),
    ],
    child: child,
  );
}

/// Address operations stay inside the seeded accounts, including the inactive
/// account whose address is not cached in AccountState.
class _SendPreviewReceiveAddressService implements ReceiveAddressService {
  const _SendPreviewReceiveAddressService();

  @override
  String getCachedTransparentAddress(String accountUuid) =>
      accountUuid == _ownAccount.uuid
          ? kSendScreenFixtureTransparentOwnAccountAddress
          : kSendScreenFixtureTransparentAddress;

  @override
  Future<String> loadShieldedAddress({
    required String accountUuid,
    String? currentShieldedAddress,
  }) async => accountUuid == _ownAccount.uuid
      ? kSendScreenFixtureOwnAccountAddress
      : kSendScreenFixtureAddress;

  @override
  Future<String> loadTransparentReceiveAddress({
    required String accountUuid,
  }) async => getCachedTransparentAddress(accountUuid);

  @override
  Future<String> reserveOrchardAddress({required String accountUuid}) =>
      loadShieldedAddress(accountUuid: accountUuid);

  @override
  Future<String> renewShieldedAddress({required String accountUuid}) =>
      loadShieldedAddress(accountUuid: accountUuid);
}

/// Router the desktop send screens need: `AppMainSidebar` reads
/// `GoRouterState.of(context)` during build, so an `InheritedGoRouter` alone
/// is not enough — the screen has to be a route of a live `GoRouter`.
class _SendScreenRouterHarness extends StatefulWidget {
  const _SendScreenRouterHarness({
    required this.screen,
    this.simulateResult = false,
    this.standaloneReview = false,
  });

  final WidgetBuilder screen;
  final bool simulateResult;
  final bool standaloneReview;

  @override
  State<_SendScreenRouterHarness> createState() =>
      _SendScreenRouterHarnessState();
}

class _SendScreenRouterHarnessState extends State<_SendScreenRouterHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: widget.standaloneReview ? '/send/review' : '/send',
      routes: [
        GoRoute(
          path: '/send',
          builder: (context, _) => widget.standaloneReview
              ? wbSidebarDestination('/send')
              : widget.screen(context),
        ),
        GoRoute(
          path: '/send/review',
          builder: (context, state) {
            if (widget.standaloneReview) return widget.screen(context);
            final args = state.extra! as SendReviewArgs;
            return sendReviewContentFixture(
              amountText: ZecAmount.fromZatoshi(
                args.amountZatoshi,
              ).activityDetail.toString(),
              feeText: ZecAmount.fromZatoshi(args.feeZatoshi).fee.toString(),
              fiatText: null,
              recipientAddress: args.address,
              isShieldedRecipient: args.isShielded,
              recipientAddressType: args.addressType,
              memoText: args.memo,
              isPaymentRequest: args.isPaymentRequest,
              requestedAmountText: args.requestedAmountZatoshi == null
                  ? null
                  : ZecAmount.fromZatoshi(
                      args.requestedAmountZatoshi!,
                    ).activityDetail.toString(),
              confirmEnabled: widget.simulateResult,
              onCancel: () => context.pop(),
              onConfirm: widget.simulateResult
                  ? () => context.push('/send/result', extra: args)
                  : null,
            );
          },
        ),
        GoRoute(
          path: '/send/result',
          builder: (context, state) {
            final args = state.extra! as SendReviewArgs;
            return Column(
              children: [
                Expanded(
                  child: sendStatusContentFixture(
                    phase: SendStatusPhase.completed,
                    amountText: ZecAmount.fromZatoshi(
                      args.amountZatoshi,
                    ).activityDetail.toString(),
                    memoText: args.memo,
                  ),
                ),
                AppBackLink(
                  label: 'Back to review',
                  onTap: () => context.pop(),
                ),
                const _SimulatedSendResultNotice(),
              ],
            );
          },
        ),
        for (final path in const [
          '/home',
          '/receive',
          '/swap',
          '/pay',
          '/voting',
          '/activity',
          '/accounts',
          '/add-account',
          '/settings',
          '/send/status',
          '/send/keystone/scan',
          '/unlock',
          '/donation',
        ])
          GoRoute(
            path: path,
            builder: (context, _) => _SendPreviewRoutePlaceholder(
              label: path,
              onBack: () => context.go('/send'),
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
      child: ColoredBox(
        color: context.colors.macosUtility.window,
        child: Router.withConfig(config: _router),
      ),
    );
  }
}

class _SendPreviewRoutePlaceholder extends StatelessWidget {
  const _SendPreviewRoutePlaceholder({required this.label, this.onBack});

  final String label;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.background.window,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            const SizedBox(height: 16),
            AppBackLink(
              label: 'Back to send preview',
              onTap: onBack ?? () => context.pop(),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Desktop send compose ---------------------------------------------------

/// Spendable balance the composer is seeded with: 143.1212 ZEC.
const _sendScreenSpendableZatoshi = 14_312_120_000;

/// An amount inside the seeded balance, and one past it. The second is what
/// puts the amount field on its insufficient-balance error.
const kSendScreenFixtureAmountText = '12.5';
const kSendScreenFixtureOverBalanceAmountText = '500';

/// The real [SendScreen] in its desktop shell.
///
/// [walletLoading] / [walletFailed] drive `walletProvider`, which is the pane's
/// loading / error / composer switch.
///
/// The prefix the contact-suggestion option types into the address field:
/// enough of 'Blue Door Coffee' to match the fixture's contacts.
const kSendScreenFixtureContactQuery = 'Blue';

/// [recipientPrefilled] fills the address field the way the address book's
/// "Send" action does, and [contactSearch] fills it with a contact-name
/// prefix and focuses it, which is what opens the autocomplete list.
///
Widget sendScreenFixture({
  bool walletLoading = false,
  bool walletFailed = false,
  bool emptyBalance = false,
  bool ironwoodResume = false,
  bool privacyMode = false,
  bool recipientPrefilled = false,
  bool contactSearch = false,
  String? amountText,
  bool priceLoading = false,
  bool listContacts = true,
  bool contactPickerOpen = false,
  bool simulateResult = false,
}) {
  final accountState = _accountState();
  final addressText = contactSearch
      ? kSendScreenFixtureContactQuery
      : recipientPrefilled
      ? kSendScreenFixtureContactAddress
      : '';
  final prefill = (addressText.isNotEmpty || amountText != null)
      ? SendPrefillArgs(
          id: 'widgetbook-send-screen-prefill',
          source: 'address-book',
          address: addressText,
          amountText: amountText,
        )
      : null;
  final migrationCta = ironwoodResume
      ? IronwoodHomeMigrationCtaState.resume(
          network: 'main',
          accountUuid: _accountUuid,
          status: _resumeMigrationStatus(),
        )
      : const IronwoodHomeMigrationCtaState.hidden();
  return _sendScreenScope(
    accountState: accountState,
    privacyMode: privacyMode,
    migrationCta: migrationCta,
    contacts: listContacts ? _contacts : const [],
    zecUsdUnitPrice: priceLoading ? null : 70,
    syncState: _syncState(
      accountUuid: _accountUuid,
      orchardBalance: emptyBalance
          ? BigInt.zero
          : BigInt.from(_sendScreenSpendableZatoshi),
      // Mid-migration most of the wallet already sits in the Ironwood pool,
      // and that is the balance the composer spends from while the run is
      // resumable.
      ironwoodBalance: ironwoodResume
          ? BigInt.from(100_000_000_000)
          : BigInt.zero,
    ),
    wallet: () => _SendPreviewWalletNotifier(
      loading: walletLoading,
      failed: walletFailed,
      accountState: accountState,
    ),
    // A knob change rebuilds this fixture in place, so the screen and the
    // mount driver would keep their State: the driver's `initState` would not
    // re-run and `SendScreen` would keep its retained prefill. Keying on every
    // screen-level input forces a remount instead.
    child: KeyedSubtree(
      key: ValueKey(
        '$recipientPrefilled|$contactSearch|$amountText|$priceLoading'
        '|$listContacts|$contactPickerOpen',
      ),
      child: _SendComposeActionOnMount(
        openContactPicker: contactPickerOpen,
        focusAddressField: contactSearch,
        child: _SendScreenRouterHarness(
          simulateResult: simulateResult,
          screen: (_) => SendScreen(
            prefill: prefill,
            validateAddress: _previewValidateAddress,
            estimateFee: _previewEstimateFee,
            estimateMax: _previewEstimateMax,
            prepareReview: _previewPrepareReview,
            discardPreparedReview: (_) async {},
          ),
        ),
      ),
    ),
  );
}

Future<rust_sync.AddressValidationResult> _previewValidateAddress({
  required String address,
  required String network,
}) async {
  // A deterministic allowlist keeps the preview independent from Rust without
  // implying that an arbitrary string is valid just because its prefix looks
  // like a Zcash address.
  const transparentAddresses = {
    kSendScreenFixtureTransparentAddress,
    kSendScreenFixtureTransparentContactAddress,
    kSendScreenFixtureTransparentOwnAccountAddress,
  };
  const shieldedAddresses = {
    kSendScreenFixtureAddress,
    kSendScreenFixtureContactAddress,
    kSendScreenFixtureOwnAccountAddress,
  };
  final addressType = transparentAddresses.contains(address)
      ? 'transparent'
      : shieldedAddresses.contains(address)
      ? 'unified'
      : null;
  return rust_sync.AddressValidationResult(
    isValid: addressType != null,
    addressType: addressType ?? '',
    wrongNetwork: false,
  );
}

Future<BigInt> _previewEstimateFee({
  required String dbPath,
  required String network,
  required String accountUuid,
  required String toAddress,
  required BigInt amountZatoshi,
  String? memo,
}) async => BigInt.from(1_000_000);

Future<rust_sync.SendMaxEstimateResult> _previewEstimateMax({
  required String dbPath,
  required String network,
  required String accountUuid,
  required String toAddress,
  String? memo,
}) async => rust_sync.SendMaxEstimateResult(
  amountZatoshi: BigInt.from(14_302_120_000),
  feeZatoshi: BigInt.from(1_000_000),
  needsSaplingParams: false,
);

Future<SendReviewArgs> _previewPrepareReview({
  required String accountUuid,
  required String sendFlowId,
  required String address,
  required String addressType,
  required BigInt amountZatoshi,
  String? memo,
  required bool isPaymentRequest,
  String? requestedBy,
  BigInt? requestedAmountZatoshi,
}) async => SendReviewArgs(
  proposalId: BigInt.from(42),
  sendFlowId: sendFlowId,
  proposalAccountUuid: accountUuid,
  address: address,
  addressType: addressType,
  amountZatoshi: amountZatoshi,
  feeZatoshi: BigInt.from(1_000_000),
  needsSaplingParams: false,
  memo: memo,
  isPaymentRequest: isPaymentRequest,
  requestedBy: requestedBy,
  requestedAmountZatoshi: requestedAmountZatoshi,
);

/// Drives the two composer states that only a pointer reaches: the contact
/// picker (tap Contacts) and the address autocomplete (focus the field a
/// contact-name prefix is already in).
///
/// The widgets' own callbacks are used rather than synthetic pointers: hit
/// testing from the root would be intercepted by the widgetbook chrome.
class _SendComposeActionOnMount extends StatefulWidget {
  const _SendComposeActionOnMount({
    required this.openContactPicker,
    required this.focusAddressField,
    required this.child,
  });

  final bool openContactPicker;
  final bool focusAddressField;
  final Widget child;

  @override
  State<_SendComposeActionOnMount> createState() =>
      _SendComposeActionOnMountState();
}

class _SendComposeActionOnMountState extends State<_SendComposeActionOnMount> {
  static const _contactsButtonKey = ValueKey('send_contacts_button');
  static const _addressFieldKey = ValueKey('send_address_field');
  static const _maxAttempts = 8;
  var _attempts = 0;
  var _done = false;

  @override
  void initState() {
    super.initState();
    if (!widget.openContactPicker && !widget.focusAddressField) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _drive());
  }

  void _drive() {
    if (_done || !mounted) return;
    final openPicker = widget.openContactPicker
        ? _callbackOf(_contactsButtonKey)
        : null;
    final addressFocus = widget.focusAddressField
        ? _focusNodeOf(_addressFieldKey)
        : null;
    final ready =
        (!widget.openContactPicker || openPicker != null) &&
        (!widget.focusAddressField || addressFocus != null);
    if (!ready) {
      if (++_attempts >= _maxAttempts) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _drive());
      return;
    }
    _done = true;
    addressFocus?.requestFocus();
    openPicker?.call();
  }

  Element? _elementWithKey(Key key) {
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget.key == key) {
        found = element;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

  VoidCallback? _callbackOf(Key key) {
    final target = _elementWithKey(key)?.widget;
    return target is GestureDetector ? target.onTap : null;
  }

  /// The field's own focus node, taken from the [EditableText] it builds, so
  /// the autocomplete sees the same focus a click would give it.
  FocusNode? _focusNodeOf(Key key) {
    final field = _elementWithKey(key);
    if (field == null) return null;
    FocusNode? node;
    void visit(Element element) {
      if (node != null) return;
      final target = element.widget;
      if (target is EditableText) {
        node = target.focusNode;
        return;
      }
      element.visitChildren(visit);
    }

    field.visitChildren(visit);
    return node;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// --- Desktop send review ----------------------------------------------------

/// The real [SendReviewScreen] in its desktop shell.
Widget sendReviewScreenFixture({
  SendFlowKind flowKind = SendFlowKind.send,
  bool hardwareAccount = false,
  bool contactRecipient = false,
  bool ownAccountRecipient = false,
  bool transparentRecipient = false,
  bool paymentRequest = false,
  bool differingRequestedAmount = false,
  bool memo = false,
}) {
  final accountState = _accountState(hardware: hardwareAccount);
  final accountUuid = accountState.activeAccountUuid!;
  final address = transparentRecipient
      ? (contactRecipient
            ? kSendScreenFixtureTransparentContactAddress
            : ownAccountRecipient
            ? kSendScreenFixtureTransparentOwnAccountAddress
            : kSendScreenFixtureTransparentAddress)
      : (contactRecipient
            ? kSendScreenFixtureContactAddress
            : ownAccountRecipient
            ? kSendScreenFixtureOwnAccountAddress
            : kSendScreenFixtureAddress);
  final args = SendReviewArgs(
    proposalId: BigInt.from(42),
    sendFlowId: 'widgetbook-send-flow',
    proposalAccountUuid: accountUuid,
    address: address,
    addressType: transparentRecipient ? 'transparent' : 'unified',
    amountZatoshi: BigInt.from(12_312_000_000),
    feeZatoshi: BigInt.from(1_200_000),
    needsSaplingParams: false,
    memo: memo ? 'Zcash is a privacy-focused digital currency' : null,
    isPaymentRequest: paymentRequest,
    requestedBy: paymentRequest ? 'Blue Door Coffee' : null,
    requestedAmountZatoshi: paymentRequest && differingRequestedAmount
        ? BigInt.from(50_000_000)
        : null,
    flowKind: flowKind,
  );
  return _sendScreenScope(
    accountState: accountState,
    child: _SendScreenRouterHarness(
      screen: (_) => SendReviewScreen(
        args: args,
        proposalDisposer: (_) async => true,
        // This review fixture has no PCZT preparation/signing simulation.
        confirmationEnabled: !hardwareAccount,
      ),
      standaloneReview: true,
    ),
  );
}

// --- Desktop send status ----------------------------------------------------

/// Notice copy the status fixture puts under the receipt rows.
const kSendStatusScreenBroadcastGuidance =
    'Still reaching the network. Keep Vizor open and check back in a moment.';
const kSendStatusScreenFailureReason =
    "Transaction couldn't be sent. Go back to your wallet and check the "
    'latest status.';

/// Broadcast outcomes the status fixture can land on; `null` holds the
/// screen on its sending phase.
SendStatusBroadcastRunner _staticRunner(SendBroadcastOutcome? outcome) {
  return ({
    required ref,
    required args,
    keystone,
    required confirmSaplingParamsDownload,
    shouldAbort,
  }) {
    // A never-completing broadcast is how the sending phase is held: the
    // screen owns the proposal for as long as it is running, so unmounting
    // mid-flight never reaches Rust's discard path either.
    if (outcome == null) return Completer<SendBroadcastOutcome>().future;
    return Future<SendBroadcastOutcome>.value(outcome);
  };
}

/// The real [SendStatusScreen], driven through its `broadcastRunner` seam.
///
/// Not pixel-deterministic: the receipt time comes from `DateTime.now()` inside
/// the screen, so this fixture stays out of figma_compare until production
/// takes a clock seam.
Widget sendStatusScreenFixture({
  SendBroadcastPhase? phase,
  bool hardwareAccount = false,
  bool transactionHash = false,
  String? statusMessage,
  String? failureReason,
}) {
  final accountState = _accountState(hardware: hardwareAccount);
  final accountUuid = accountState.activeAccountUuid!;
  final args = SendReviewArgs(
    proposalId: BigInt.from(43),
    sendFlowId: 'widgetbook-send-status-flow',
    proposalAccountUuid: accountUuid,
    address: kSendScreenFixtureAddress,
    addressType: 'unified',
    amountZatoshi: BigInt.from(12_312_000_000),
    feeZatoshi: BigInt.from(1_200_000),
    needsSaplingParams: false,
  );
  return _sendScreenScope(
    accountState: accountState,
    child: _SendScreenRouterHarness(
      screen: (_) => SendStatusScreen(
        args: args,
        keystone: hardwareAccount
            ? KeystoneBroadcastArgs(
                reviewArgs: args,
                pcztWithProofs: const [],
                pcztWithSignatures: const [],
              )
            : null,
        // `proposalConsumed: true` so leaving the preview never calls Rust's
        // discard path.
        broadcastRunner: _staticRunner(
          phase == null
              ? null
              : SendBroadcastOutcome(
                  phase: phase,
                  proposalConsumed: true,
                  txid: transactionHash
                      ? '0f3ca1d9b7e24c8a5d6019f4b3c7e28a1d5f90b6'
                            'c4a37e82d195f06b3a7c48e2'
                      : null,
                  statusMessage: statusMessage,
                  error: failureReason,
                ),
        ),
      ),
    ),
  );
}

// `KeystoneSendScanScreen` is previewed in `scanner_use_cases.dart` instead:
// it mounts a live `MobileScannerController` and calls
// `rust_keystone.resetUrSession()`, which only the camera and UR-decode fakes
// in `support/wb_fake_scanner_platform.dart` stand in for.

// --- Verify address overlay -------------------------------------------------

/// Which identity the fixture's address book and own-account map resolve the
/// overlay's recipient to.
enum SendVerifyOverlayRecipient { address, contact, ownAccount }

/// The address each recipient/pool pair uses. Both pools carry the same three
/// identities, so the two axes stay orthogonal.
String sendVerifyOverlayAddressFor({
  required SendVerifyOverlayRecipient recipient,
  required bool shielded,
}) {
  if (shielded) {
    return switch (recipient) {
      SendVerifyOverlayRecipient.address => kSendScreenFixtureAddress,
      SendVerifyOverlayRecipient.contact => kSendScreenFixtureContactAddress,
      SendVerifyOverlayRecipient.ownAccount =>
        kSendScreenFixtureOwnAccountAddress,
    };
  }
  return switch (recipient) {
    SendVerifyOverlayRecipient.address => kSendScreenFixtureTransparentAddress,
    SendVerifyOverlayRecipient.contact =>
      kSendScreenFixtureTransparentContactAddress,
    SendVerifyOverlayRecipient.ownAccount =>
      kSendScreenFixtureTransparentOwnAccountAddress,
  };
}

/// The real [SendVerifyAddressOverlay] as the review and status screens
/// present it — over the pane, in its own scrim.
///
/// The contact's "N previous transactions" sub-line stays absent: the scope
/// supplies a deterministic zero without opening the wallet DB. Counted
/// variants are on the `Verify address > Desktop modal` case instead.
Widget sendVerifyAddressOverlayFixture({
  SendVerifyOverlayRecipient recipient = SendVerifyOverlayRecipient.address,
  bool shielded = true,
}) {
  final accountState = _accountState();
  return _sendScreenScope(
    accountState: accountState,
    child: _SendOverlayPaneFrame(
      child: SendVerifyAddressOverlay(
        accountUuid: accountState.activeAccountUuid!,
        address: sendVerifyOverlayAddressFor(
          recipient: recipient,
          shielded: shielded,
        ),
        isShieldedAddress: shielded,
        onClose: _sendPreviewNoop,
      ),
    ),
  );
}

// --- Sapling params prompt --------------------------------------------------

/// The real [SaplingParamsPrompt] (desktop) / [MobileSaplingParamsSheet]
/// (mobile). Both are pure, so the preview only supplies the frame.
Widget saplingParamsPromptFixture({bool mobile = false}) {
  if (mobile) return const _SendSaplingParamsSheetFrame();
  return const _SendOverlayPaneFrame(
    child: SaplingParamsPrompt(
      onDownload: _sendPreviewNoop,
      onCancel: _sendPreviewNoop,
    ),
  );
}

void _sendPreviewNoop() {}

/// Trailing-pane stand-in for the overlays the desktop send screens stack over
/// their content: window backdrop, pane-radius surface, expanded stack — the
/// same arrangement `send_review_screen.dart` builds.
class _SendOverlayPaneFrame extends StatelessWidget {
  const _SendOverlayPaneFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return WbDesktopWindowBox(
      child: ColoredBox(
        color: colors.background.window,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colors.background.base,
              borderRadius: BorderRadius.circular(AppWindowSizing.paneRadius),
            ),
            child: Stack(fit: StackFit.expand, children: [child]),
          ),
        ),
      ),
    );
  }
}

/// Phone frame for the mobile download sheet.
///
/// Its own navigator: the sheet's Download / Cancel call `Navigator.pop`, and
/// that must land here rather than on the widgetbook root.
class _SendSaplingParamsSheetFrame extends StatelessWidget {
  const _SendSaplingParamsSheetFrame();

  @override
  Widget build(BuildContext context) {
    return WbScaleDownBox(
      size: const Size(393, 852),
      child: SizedBox(
        width: 393,
        height: 852,
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(393, 852),
            viewPadding: EdgeInsets.only(top: 55, bottom: 34),
          ),
          child: ColoredBox(
            color: context.colors.background.neutralScrim,
            child: Navigator(
              onGenerateRoute: (settings) => PageRouteBuilder<void>(
                settings: settings,
                opaque: false,
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
                pageBuilder: (_, _, _) => const SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Material(
                      type: MaterialType.transparency,
                      child: MobileModalCard(child: MobileSaplingParamsSheet()),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Mobile send status -----------------------------------------------------

/// Phone box the mobile send fixtures render in, matching the 393x852 +
/// 55px status-bar convention the other mobile fixtures use.
class _MobileSendScreenFrame extends StatelessWidget {
  const _MobileSendScreenFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return WbScaleDownBox(
      size: const Size(393, 852),
      child: SizedBox(
        width: 393,
        height: 852,
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(393, 852),
            viewPadding: EdgeInsets.only(top: 55),
          ),
          child: ColoredBox(
            color: context.colors.background.window,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Owns navigation per mounted preview (also isolates Compare panes).
/// Status uses its `/home` fallback; signing needs a parent to pop back to.
class _MobileSendPreviewRouter extends StatefulWidget {
  const _MobileSendPreviewRouter({required this.child, this.hasParent = false});

  final Widget child;
  final bool hasParent;

  @override
  State<_MobileSendPreviewRouter> createState() =>
      _MobileSendPreviewRouterState();
}

class _MobileSendPreviewRouterState extends State<_MobileSendPreviewRouter> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final location = widget.hasParent ? '/home/preview' : '/preview';
    final preview = GoRoute(
      path: widget.hasParent ? 'preview' : '/preview',
      pageBuilder: (_, state) =>
          NoTransitionPage<void>(key: state.pageKey, child: widget.child),
    );
    _router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) => NoTransitionPage<void>(
            key: state.pageKey,
            child: _SendPreviewRoutePlaceholder(
              label: '/home',
              onBack: () => context.go(location),
            ),
          ),
          routes: [if (widget.hasParent) preview],
        ),
        if (!widget.hasParent) preview,
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

/// Broadcast outcomes the mobile receipt can land on; `null` holds it on the
/// sending phase.
MobileSendBroadcastRunner _staticMobileRunner(SendBroadcastOutcome? outcome) {
  return ({
    required ref,
    required args,
    keystone,
    required confirmSaplingParamsDownload,
    shouldAbort,
  }) {
    if (outcome == null) return Completer<SendBroadcastOutcome>().future;
    return Future<SendBroadcastOutcome>.value(outcome);
  };
}

/// The real [MobileSendStatusScreen], driven through its `broadcastRunner`
/// seam.
Widget mobileSendStatusFixture({
  SendBroadcastPhase? phase,
  String? statusMessage,
  bool hardwareAccount = false,
}) {
  final accountState = _accountState(hardware: hardwareAccount);
  final accountUuid = accountState.activeAccountUuid!;
  final args = SendReviewArgs(
    proposalId: BigInt.from(44),
    sendFlowId: 'widgetbook-mobile-send-status-flow',
    proposalAccountUuid: accountUuid,
    address: kSendScreenFixtureAddress,
    addressType: 'unified',
    amountZatoshi: BigInt.from(12_312_000_000),
    feeZatoshi: BigInt.from(1_200_000),
    needsSaplingParams: false,
  );
  return _sendScreenScope(
    accountState: accountState,
    child: _MobileSendScreenFrame(
      child: _MobileSendPreviewRouter(
        child: MobileSendStatusScreen(
          args: args,
          keystone: hardwareAccount
              ? KeystoneBroadcastArgs(
                  reviewArgs: args,
                  pcztWithProofs: const [],
                  pcztWithSignatures: const [],
                )
              : null,
          // `proposalConsumed: true` so leaving the preview never calls
          // Rust's discard path.
          broadcastRunner: _staticMobileRunner(
            phase == null
                ? null
                : SendBroadcastOutcome(
                    phase: phase,
                    proposalConsumed: true,
                    statusMessage: statusMessage,
                  ),
          ),
        ),
      ),
    ),
  );
}

/// A complete, in-memory mobile send journey for the Screen preview.
///
/// The composer and receipt are the production mobile screens. Address
/// validation, fee estimation, proposal preparation and broadcast are all
/// supplied by deterministic preview seams, so this never reaches Rust,
/// storage, or the network.
///
/// The optional initial values are for state inspection in the one Screen
/// entry. Their defaults keep the empty composer that existing callers use;
/// unlike standalone snapshot fixtures, every seeded state can still continue
/// through the real compose, review, and receipt navigation.
Widget mobileSendFlowFixture({
  bool fails = false,
  List<AddressBookContact> contacts = const [],
  Map<String, AccountInfo> ownAccountAddresses = const {},
  String? initialRecipient,
  String? initialAddressType,
  String? initialAmount,
  String? initialFiatAmount,
  MobileSendAmountInputMode initialAmountInputMode =
      MobileSendAmountInputMode.zec,
  String? initialAmountError,
  bool initialAmountReady = false,
  bool initialReview = false,
  BigInt? initialFeeZatoshi,
  bool refreshReviewFeeOnInit = false,
  String? initialMemo,
  String? initialContactLabel,
  String? initialContactPictureId,
  bool initialRecipientFocused = false,
  bool isPaymentRequest = false,
  String? paymentRequestLabel,
  BigInt? requestedAmountZatoshi,
  MobileSendFeeEstimator? estimateFee,
}) {
  // Widgetbook rebuilds a case in place when a knob changes. The production
  // screen intentionally owns these as init-only draft values, so remount on
  // a seeded-state change; ordinary typing and navigation do not alter this
  // key and keep the in-memory journey intact.
  return KeyedSubtree(
    key: ValueKey(
      '$fails|${contacts.map((contact) => contact.id).join(',')}'
      '|${ownAccountAddresses.keys.join(',')}|$initialRecipient'
      '|$initialAddressType|$initialAmount|$initialFiatAmount'
      '|$initialAmountInputMode|$initialAmountError|$initialAmountReady'
      '|$initialReview|$initialFeeZatoshi|$refreshReviewFeeOnInit'
      '|$initialMemo|$initialContactLabel|$initialContactPictureId'
      '|$initialRecipientFocused|$isPaymentRequest|$paymentRequestLabel'
      '|$requestedAmountZatoshi|${estimateFee.hashCode}',
    ),
    child: _MobileSendFlowHarness(
      fails: fails,
      contacts: contacts,
      ownAccountAddresses: ownAccountAddresses,
      initialRecipient: initialRecipient,
      initialAddressType: initialAddressType,
      initialAmount: initialAmount,
      initialFiatAmount: initialFiatAmount,
      initialAmountInputMode: initialAmountInputMode,
      initialAmountError: initialAmountError,
      initialAmountReady: initialAmountReady,
      initialReview: initialReview,
      initialFeeZatoshi: initialFeeZatoshi,
      refreshReviewFeeOnInit: refreshReviewFeeOnInit,
      initialMemo: initialMemo,
      initialContactLabel: initialContactLabel,
      initialContactPictureId: initialContactPictureId,
      initialRecipientFocused: initialRecipientFocused,
      isPaymentRequest: isPaymentRequest,
      paymentRequestLabel: paymentRequestLabel,
      requestedAmountZatoshi: requestedAmountZatoshi,
      estimateFee: estimateFee,
    ),
  );
}

class _MobileSendFlowHarness extends StatefulWidget {
  const _MobileSendFlowHarness({
    required this.fails,
    required this.contacts,
    required this.ownAccountAddresses,
    this.initialRecipient,
    this.initialAddressType,
    this.initialAmount,
    this.initialFiatAmount,
    required this.initialAmountInputMode,
    this.initialAmountError,
    required this.initialAmountReady,
    required this.initialReview,
    this.initialFeeZatoshi,
    required this.refreshReviewFeeOnInit,
    this.initialMemo,
    this.initialContactLabel,
    this.initialContactPictureId,
    required this.initialRecipientFocused,
    required this.isPaymentRequest,
    this.paymentRequestLabel,
    this.requestedAmountZatoshi,
    this.estimateFee,
  });

  final bool fails;
  final List<AddressBookContact> contacts;
  final Map<String, AccountInfo> ownAccountAddresses;
  final String? initialRecipient;
  final String? initialAddressType;
  final String? initialAmount;
  final String? initialFiatAmount;
  final MobileSendAmountInputMode initialAmountInputMode;
  final String? initialAmountError;
  final bool initialAmountReady;
  final bool initialReview;
  final BigInt? initialFeeZatoshi;
  final bool refreshReviewFeeOnInit;
  final String? initialMemo;
  final String? initialContactLabel;
  final String? initialContactPictureId;
  final bool initialRecipientFocused;
  final bool isPaymentRequest;
  final String? paymentRequestLabel;
  final BigInt? requestedAmountZatoshi;
  final MobileSendFeeEstimator? estimateFee;

  @override
  State<_MobileSendFlowHarness> createState() => _MobileSendFlowHarnessState();
}

class _MobileSendFlowHarnessState extends State<_MobileSendFlowHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/send',
      routes: [
        GoRoute(
          path: '/send',
          builder: (_, _) => MobileSendScreen(
            initialSendFlowId: 'widgetbook-mobile-send-flow',
            initialRecipient: widget.initialRecipient,
            initialAddressType: widget.initialAddressType,
            initialAmount: widget.initialAmount,
            initialFiatAmount: widget.initialFiatAmount,
            initialAmountInputMode: widget.initialAmountInputMode,
            initialAmountError: widget.initialAmountError,
            initialAmountReady: widget.initialAmountReady,
            initialReview: widget.initialReview,
            initialFeeZatoshi: widget.initialFeeZatoshi,
            refreshReviewFeeOnInit: widget.refreshReviewFeeOnInit,
            initialMemo: widget.initialMemo,
            initialContactLabel: widget.initialContactLabel,
            initialContactPictureId: widget.initialContactPictureId,
            initialRecipientFocused: widget.initialRecipientFocused,
            isPaymentRequest: widget.isPaymentRequest,
            paymentRequestLabel: widget.paymentRequestLabel,
            requestedAmountZatoshi: widget.requestedAmountZatoshi,
            loadWalletDbPath: () async => '/tmp/widgetbook-zcash-wallet.db',
            validateAddress: _previewMobileValidateAddress,
            estimateFee: widget.estimateFee ?? _previewEstimateFee,
            estimateMax: _previewEstimateMax,
            prepareReview:
                ({
                  required accountUuid,
                  required sendFlowId,
                  required address,
                  required addressType,
                  required amountZatoshi,
                  memo,
                }) => _previewPrepareReview(
                  accountUuid: accountUuid,
                  sendFlowId: sendFlowId,
                  address: address,
                  addressType: addressType,
                  amountZatoshi: amountZatoshi,
                  memo: memo,
                  isPaymentRequest: false,
                ),
            discardPreparedReview: (_) async => true,
            openScanner: (_, {required networkName}) async => null,
          ),
        ),
        GoRoute(
          path: '/send/status',
          builder: (_, state) {
            final args = state.extra! as SendReviewArgs;
            return Stack(
              children: [
                MobileSendStatusScreen(
                  args: args,
                  broadcastRunner: _staticMobileRunner(
                    SendBroadcastOutcome(
                      phase: widget.fails
                          ? SendBroadcastPhase.failed
                          : SendBroadcastPhase.succeeded,
                      proposalConsumed: true,
                      error: widget.fails
                          ? "Preview: transaction couldn't be sent."
                          : null,
                    ),
                  ),
                ),
                const Positioned(
                  left: AppSpacing.md,
                  right: AppSpacing.md,
                  bottom: AppSpacing.xl,
                  child: _SimulatedSendResultNotice(),
                ),
              ],
            );
          },
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => Center(
            child: AppButton(
              key: const ValueKey('mobile_send_flow_reset'),
              onPressed: () => _router.go('/send'),
              variant: AppButtonVariant.secondary,
              child: const Text('Start over'),
            ),
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
    return _sendScreenScope(
      accountState: _accountState(),
      contacts: widget.contacts,
      ownAccountAddresses: widget.ownAccountAddresses,
      child: _MobileSendScreenFrame(child: Router.withConfig(config: _router)),
    );
  }
}

Future<rust_sync.AddressValidationResult> _previewMobileValidateAddress({
  required String address,
  required String network,
}) async {
  if (address == kMobileSendWrongNetworkAddress) {
    return const rust_sync.AddressValidationResult(
      isValid: false,
      addressType: '',
      wrongNetwork: true,
    );
  }
  const addressTypes = {
    kSendScreenFixtureAddress: 'unified',
    kSendScreenFixtureContactAddress: 'unified',
    kSendScreenFixtureOwnAccountAddress: 'unified',
    kMobileSendUnifiedAddress: 'unified',
    kMobileSendSaplingAddress: 'sapling',
    kSendScreenFixtureTransparentAddress: 'transparent',
    kSendScreenFixtureTransparentContactAddress: 'transparent',
    kSendScreenFixtureTransparentOwnAccountAddress: 'transparent',
    kSendScreenFixtureTexAddress: 'tex',
  };
  final type = addressTypes[address];
  return rust_sync.AddressValidationResult(
    isValid: type != null,
    addressType: type ?? '',
    wrongNetwork: false,
  );
}

class _SimulatedSendResultNotice extends StatelessWidget {
  const _SimulatedSendResultNotice();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.background.raised,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Text(
          'Simulated result · no transaction was sent',
          key: const ValueKey('send_simulated_result_notice'),
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

/// Server-supplied subtitle the queued receipt shows instead of its default.
const kMobileSendStatusServerMessage =
    'The network is busy. Your transaction is queued and will be submitted '
    'automatically.';

// --- Mobile Keystone sign ---------------------------------------------------

/// Why the Keystone signing preparation failed, as the screen's
/// `_friendlyError` branches read it.
enum MobileKeystoneSignFailure {
  expiredProposal,
  batchSigning,
  provingParameters,
  generic,
}

/// The message each failure reaches `_friendlyError` with.
String _keystoneSignFailureMessage(MobileKeystoneSignFailure failure) {
  return switch (failure) {
    MobileKeystoneSignFailure.expiredProposal => 'Proposal not found',
    MobileKeystoneSignFailure.batchSigning =>
      'Keystone batch signing supports at most 96 signatures',
    MobileKeystoneSignFailure.provingParameters =>
      'Sapling parameter download failed',
    MobileKeystoneSignFailure.generic => 'Could not reach the wallet database',
  };
}

/// The real [MobileKeystoneSignScreen], held on the signing flow's preparing
/// stage or pushed into its error stage through the `loadWalletDbPath` seam
/// that `_preparePczt` awaits first.
Widget mobileKeystoneSignFixture({
  MobileKeystoneSignFailure? failure,
  bool texSend = false,
}) {
  final accountState = _accountState(hardware: true);
  final args = SendReviewArgs(
    proposalId: BigInt.from(45),
    sendFlowId: 'widgetbook-mobile-keystone-sign-flow',
    proposalAccountUuid: accountState.activeAccountUuid!,
    address: texSend ? kSendScreenFixtureTexAddress : kSendScreenFixtureAddress,
    addressType: texSend ? 'tex' : 'unified',
    amountZatoshi: BigInt.from(12_312_000_000),
    feeZatoshi: BigInt.from(1_200_000),
    needsSaplingParams: false,
  );
  return _sendScreenScope(
    accountState: accountState,
    child: _MobileSendScreenFrame(
      child: _MobileSendPreviewRouter(
        hasParent: true,
        child: MobileKeystoneSignScreen(
          args: args,
          proposalDisposer: (_) async => true,
          loadWalletDbPath: failure == null
              // A never-completing load holds the preparing stage; the QR and
              // scanner stages need real PCZT bytes and are registered under
              // Screens > Onboarding > Mobile Keystone instead.
              ? () => Completer<String>().future
              : () async =>
                    throw Exception(_keystoneSignFailureMessage(failure)),
        ),
      ),
    ),
  );
}

// --- Preview notifiers ------------------------------------------------------

class _SendPreviewAccountNotifier extends AccountNotifier {
  _SendPreviewAccountNotifier(this.initialState);

  final AccountState initialState;

  @override
  FutureOr<AccountState> build() => initialState;

  @override
  Future<void> switchAccount(String uuid) async {
    final prev = state.value ?? initialState;
    state = AsyncData(prev.copyWith(activeAccountUuid: uuid));
  }
}

class _SendPreviewWalletNotifier extends WalletNotifier {
  _SendPreviewWalletNotifier({
    required this.loading,
    required this.failed,
    required this.accountState,
  });

  final bool loading;
  final bool failed;
  final AccountState accountState;

  @override
  FutureOr<WalletState> build() {
    if (loading) return Completer<WalletState>().future;
    if (failed) throw const _SendPreviewWalletFailure();
    return WalletState(
      hasWallet: true,
      unifiedAddress: accountState.activeAddress,
      activeAccountUuid: accountState.activeAccountUuid,
    );
  }
}

/// Deterministic failure text: the pane prints `Details: $err`.
class _SendPreviewWalletFailure implements Exception {
  const _SendPreviewWalletFailure();

  @override
  String toString() => 'wallet data unavailable';
}

class _SendPreviewSyncNotifier extends SyncNotifier {
  _SendPreviewSyncNotifier(this.initialState);

  final SyncState initialState;

  @override
  Future<SyncState> build() async => initialState;

  @override
  Future<void> refreshAfterSend() async {}

  @override
  Future<void> refreshAfterAccountSwitch() async {}

  @override
  Future<void> refreshAfterProposalRelease(String accountUuid) async {}

  @override
  Future<void> clearSensitiveStateForLock() async {}
}

class _SendPreviewPrivacyModeNotifier extends PrivacyModeNotifier {
  @override
  Future<void> set(bool enabled) async {
    state = enabled;
  }
}

class _SendPreviewLayoutNotifier extends AppLayoutNotifier {
  @override
  AppLayoutState build() => const AppLayoutState(AppLayoutMode.large);

  @override
  Future<void> setMode(AppLayoutMode mode) async {
    // Intentional no-op: the real call reshapes the native window through
    // `window_manager`, which belongs to the Widgetbook host.
  }
}

class _SendPreviewMigrationCoordinator extends IronwoodMigrationCoordinator {
  @override
  IronwoodMigrationCoordinatorState build() =>
      const IronwoodMigrationCoordinatorState();
}

class _SendPreviewAddressBookRepository implements AddressBookRepository {
  const _SendPreviewAddressBookRepository(this.contacts);

  final List<AddressBookContact> contacts;

  @override
  Future<List<AddressBookContact>> loadContacts() async => contacts;

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}
