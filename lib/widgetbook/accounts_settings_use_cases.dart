// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:async';

import 'package:flutter/material.dart'
    show Colors, Material, MaterialType, ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/config/zcash_explorer.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/layout/mobile/app_mobile_shell.dart';
import '../src/core/layout/mobile/app_mobile_tab_bar.dart';
import '../src/core/privacy/sensitive_privacy_overlay.dart';
import '../src/core/profile_pictures.dart';
import '../src/core/security/password_policy.dart';
import '../src/core/security/software_wallet_secret.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_button.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/mobile/mobile_list_row.dart';
import '../src/features/about/screens/about_screen.dart';
import '../src/features/about/screens/mobile/mobile_about_screens.dart';
import '../src/features/accounts/screens/accounts_screen.dart';
import '../src/features/accounts/screens/mobile/mobile_accounts_screen.dart';
import '../src/features/accounts/widgets/account_edit_modal.dart';
import '../src/features/accounts/widgets/account_modal_card.dart';
import '../src/features/accounts/widgets/account_profile_picture_modal.dart';
import '../src/features/accounts/widgets/account_remove_modal.dart';
import '../src/features/accounts/widgets/mobile/account_edit_sheets.dart';
import '../src/features/accounts/widgets/mobile/mobile_accounts_sheet.dart';
import '../src/features/migration/models/ironwood_migration_phases.dart';
import '../src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import '../src/features/payment_links/services/payment_link_received_store.dart';
import '../src/features/payment_links/services/payment_link_recovery_reconciler.dart';
import '../src/features/onboarding/mobile/mobile_passcode_screen.dart'
    show kMobilePasscodeLength;
import '../src/features/settings/screens/mobile/mobile_change_passcode_screen.dart';
import '../src/features/settings/screens/mobile/mobile_endpoint_screen.dart';
import '../src/features/settings/screens/mobile/mobile_seed_phrase_screen.dart';
import '../src/features/settings/screens/mobile/mobile_settings_screen.dart';
import '../src/features/settings/screens/mobile/mobile_viewing_key_screen.dart';
import '../src/features/settings/screens/settings_endpoint_screen.dart';
import '../src/features/settings/screens/settings_screen.dart';
import '../src/features/settings/screens/settings_seed_phrase_screen.dart';
import '../src/features/settings/screens/settings_uninstall_screen.dart';
import '../src/features/settings/widgets/confirm_access_card.dart';
import '../src/features/settings/widgets/custom_endpoint_settings_panel.dart';
import '../src/features/settings/widgets/mobile/mobile_network_privacy_card.dart';
import '../src/features/settings/widgets/network_privacy_control.dart';
import '../src/features/settings/widgets/settings_new_badge.dart';
import '../src/features/settings/widgets/settings_pane_backdrop.dart';
import '../src/features/settings/widgets/windows_update_download_flow.dart';
import '../src/features/swap/providers/swap_activity_store.dart';
import '../src/features/wallet_link/models/wallet_link_models.dart';
import '../src/features/wallet_link/screens/wallet_link_desktop_screen.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/app_security_provider.dart';
import '../src/providers/biometric_unlock_provider.dart';
import '../src/providers/network_privacy_provider.dart';
import '../src/providers/receive_address_provider.dart';
import '../src/providers/rpc_endpoint_latency_provider.dart';
import '../src/providers/rpc_endpoint_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/providers/sync_keep_awake_provider.dart';
import '../src/providers/theme_mode_provider.dart';
import '../src/providers/zcash_explorer_provider.dart';
import '../src/providers/windows_update_provider.dart';
import '../src/rust/api/sync.dart' as rust_sync;
import 'support/wb_layout.dart';
import 'support/wb_platform_override.dart';

/// Accounts fixtures for the knob-driven gallery.
///
/// Deliberately separate from `screen_use_cases.dart`: those builders are a
/// const contract for figma_compare, so the parameterized previews the gallery
/// needs live here with their own preview providers.

// --- Account states --------------------------------------------------------

const accountsPreviewCurrentUuid = 'preview-account-1';
const accountsPreviewKeystoneUuid = 'preview-account-2';
const accountsPreviewOtherUuid = 'preview-account-3';

/// The four-account Figma state: software anchor, Keystone, two software.
final AccountState accountsPreviewDesignState = AccountState(
  accounts: const [
    AccountInfo(
      uuid: accountsPreviewCurrentUuid,
      name: 'Account Name',
      order: 0,
      isSeedAnchor: true,
      profilePictureId: kDefaultProfilePictureId,
    ),
    AccountInfo(
      uuid: accountsPreviewKeystoneUuid,
      name: 'Account Name',
      order: 1,
      isHardware: true,
      profilePictureId: 'pfp-01',
    ),
    AccountInfo(
      uuid: accountsPreviewOtherUuid,
      name: 'Account Name',
      order: 2,
      profilePictureId: 'pfp-02',
    ),
    AccountInfo(
      uuid: 'preview-account-4',
      name: 'Account Name',
      order: 3,
      profilePictureId: 'pfp-01',
    ),
  ],
  activeAccountUuid: accountsPreviewCurrentUuid,
  activeAddress: 'u1widgetbookaccountsaddress',
);

/// One account: removing it is a full Vizor reset, not an account removal.
final AccountState accountsPreviewSingleState = AccountState(
  accounts: const [
    AccountInfo(
      uuid: accountsPreviewCurrentUuid,
      name: 'Primary Vault',
      order: 0,
      isSeedAnchor: true,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: accountsPreviewCurrentUuid,
  activeAddress: 'u1widgetbookaccountsaddress',
);

/// Twenty accounts: the list scrolls and the sheet hits its 216px cap.
final AccountState accountsPreviewManyState = AccountState(
  accounts: [
    const AccountInfo(
      uuid: accountsPreviewCurrentUuid,
      name: 'Primary Vault',
      order: 0,
      isSeedAnchor: true,
      profilePictureId: kDefaultProfilePictureId,
    ),
    for (var index = 2; index <= 20; index += 1)
      AccountInfo(
        uuid: 'preview-account-$index',
        name: index == 2 ? 'Keystone Vault' : 'Account $index',
        order: index - 1,
        isHardware: index == 2,
        profilePictureId: index.isEven ? 'pfp-02' : 'pfp-01',
      ),
  ],
  activeAccountUuid: accountsPreviewCurrentUuid,
  activeAddress: 'u1widgetbookaccountsaddress',
);

/// No accounts at all: both the current-account surface and the list go away.
const AccountState accountsPreviewEmptyState = AccountState();

/// Switcher-sheet state: [otherAccountCount] rows under the active account.
AccountState accountsPreviewSwitcherState({
  required int otherAccountCount,
  required bool activeIsHardware,
}) {
  return AccountState(
    accounts: [
      AccountInfo(
        uuid: accountsPreviewCurrentUuid,
        name: activeIsHardware ? 'Keystone Vault' : 'Primary Vault',
        order: 0,
        isHardware: activeIsHardware,
        isSeedAnchor: !activeIsHardware,
        profilePictureId: kDefaultProfilePictureId,
      ),
      for (var index = 1; index <= otherAccountCount; index += 1)
        AccountInfo(
          uuid: 'preview-switcher-$index',
          name: 'Account ${index + 1}',
          order: index,
          isHardware: index == 2,
          profilePictureId: index.isEven ? 'pfp-02' : 'pfp-01',
        ),
    ],
    activeAccountUuid: accountsPreviewCurrentUuid,
    activeAddress: 'u1widgetbookaccountsaddress',
  );
}

// --- Screens ---------------------------------------------------------------

/// Desktop accounts screen with its list size, overlay and remove-blocker
/// axes driven independently.
///
/// The three block counts are provider families the remove modal watches; a
/// `checking` flag leaves the future pending, which is the modal's loading
/// copy.
Widget accountsDesktopScreenFixture({
  required AccountState accountState,
  String? initialOpenMenuAccountUuid,
  String? initialModalAccountUuid,
  AccountsScreenInitialModal? initialModal,
  int pendingSwapCount = 0,
  bool checkingPendingSwaps = false,
  int receivingGiftCardCount = 0,
  bool checkingReceivingGiftCards = false,
  int unsharedGiftCardCount = 0,
  bool checkingUnsharedGiftCards = false,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _accountsPreviewBootstrap(accountState),
      ),
      accountProvider.overrideWith(
        () => _AccountsPreviewAccountNotifier(accountState),
      ),
      syncProvider.overrideWith(
        () => _AccountsPreviewSyncNotifier(accountState.activeAccountUuid),
      ),
      receiveAddressServiceProvider.overrideWithValue(
        const _AccountsPreviewReceiveAddressService(),
      ),
      swapPendingIntentCountProvider.overrideWith(
        (ref, _) => _previewCount(pendingSwapCount, checkingPendingSwaps),
      ),
      paymentLinkReceivingCountProvider.overrideWith(
        (ref, _) =>
            _previewCount(receivingGiftCardCount, checkingReceivingGiftCards),
      ),
      paymentLinkUnsharedFundedCountProvider.overrideWith(
        (ref, _) =>
            _previewCount(unsharedGiftCardCount, checkingUnsharedGiftCards),
      ),
      _accountsPreviewIdleMigrationOverride(),
    ],
    child: _AccountsPreviewHarness(
      initialOpenMenuAccountUuid: initialOpenMenuAccountUuid,
      initialModalAccountUuid: initialModalAccountUuid,
      initialModal: initialModal,
    ),
  );
}

/// Mobile accounts screen in a phone frame, with its sheets, row menu and
/// the active-migration remove copy as independent axes.
Widget accountsMobileScreenFixture({
  required AccountState accountState,
  String? initialSheetAccountUuid,
  MobileAccountsInitialSheet? initialSheet,
  String? initialOpenMenuAccountUuid,
  bool migrationActive = false,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _accountsPreviewBootstrap(accountState),
      ),
      accountProvider.overrideWith(
        () => _AccountsPreviewAccountNotifier(accountState),
      ),
      receiveAddressServiceProvider.overrideWithValue(
        const _AccountsPreviewReceiveAddressService(),
      ),
      syncProvider.overrideWith(
        () => _AccountsPreviewSyncNotifier(accountState.activeAccountUuid),
      ),
      ironwoodMigrationCoordinatorProvider.overrideWith(
        () => _AccountsPreviewMigrationCoordinator(
          accountUuid: migrationActive ? initialSheetAccountUuid : null,
          status: migrationActive ? _accountsPreviewMigrationStatus() : null,
        ),
      ),
    ],
    child: WbFrame(
      layout: WbLayout.mobile,
      child: _MobileAccountsPreviewHarness(
        initialSheetAccountUuid: initialSheetAccountUuid,
        initialSheet: initialSheet,
        initialOpenMenuAccountUuid: initialOpenMenuAccountUuid,
      ),
    ),
  );
}

// --- Sheets ----------------------------------------------------------------

/// The home accounts switcher, rendered in its sheet card on a plain phone
/// frame rather than over a live home screen.
Widget accountsSwitcherSheetFixture({
  required int otherAccountCount,
  required bool activeIsHardware,
}) {
  final accountState = accountsPreviewSwitcherState(
    otherAccountCount: otherAccountCount,
    activeIsHardware: activeIsHardware,
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _accountsPreviewBootstrap(accountState),
      ),
      accountProvider.overrideWith(
        () => _AccountsPreviewAccountNotifier(accountState),
      ),
      syncProvider.overrideWith(
        () => _AccountsPreviewSyncNotifier(accountState.activeAccountUuid),
      ),
      receiveAddressServiceProvider.overrideWithValue(
        const _AccountsPreviewReceiveAddressService(),
      ),
    ],
    child: WbFrame(
      layout: WbLayout.mobile,
      child: const _AccountsSheetHost(child: MobileAccountsSheet()),
    ),
  );
}

/// The mobile profile-picture picker, opened through its real public entry
/// point so the private sheet renders exactly as the edit flow shows it.
///
/// No width axis: the sheet body is private and `showProfilePictureSheet`
/// presents on the root navigator, so the grid always gets the gallery canvas
/// and its narrow-width column collapse cannot be previewed from here.
Widget accountsProfilePictureSheetFixture({required String selectedId}) {
  return _ProfilePictureSheetOpener(selectedId: selectedId);
}

// --- Modals ----------------------------------------------------------------

/// Remove-account modal on a plain desktop frame. The counts and `checking`
/// flags are the props behind every warning-panel variant.
Widget accountsRemoveModalFixture({
  required bool isLastAccount,
  int pendingSwapCount = 0,
  bool checkingPendingSwaps = false,
  bool pendingSwapCheckFailed = false,
  int receivingGiftCardCount = 0,
  bool checkingReceivingGiftCards = false,
  int unsharedGiftCardCount = 0,
  bool checkingUnsharedGiftCards = false,
  bool receivingGiftCardCheckFailed = false,
  bool unsharedGiftCardCheckFailed = false,
}) {
  return _accountsModalFrame(
    AccountRemoveModal(
      accountName: isLastAccount ? 'Primary Vault' : 'Account Name',
      profilePictureId: kDefaultProfilePictureId,
      isLastAccount: isLastAccount,
      pendingSwapCount: pendingSwapCount,
      checkingPendingSwaps: checkingPendingSwaps,
      pendingSwapCheckFailed: pendingSwapCheckFailed,
      receivingGiftCardCount: receivingGiftCardCount,
      checkingReceivingGiftCards: checkingReceivingGiftCards,
      receivingGiftCardCheckFailed: receivingGiftCardCheckFailed,
      unsharedGiftCardCount: unsharedGiftCardCount,
      checkingUnsharedGiftCards: checkingUnsharedGiftCards,
      unsharedGiftCardCheckFailed: unsharedGiftCardCheckFailed,
      onCancel: _noop,
      onConfirmPassword: _previewConfirmPassword,
      onRemove: _previewRemove,
    ),
  );
}

/// Edit-account modal on a plain desktop frame.
Widget accountsEditModalFixture({
  required String initialName,
  required bool profilePictureChanged,
}) {
  return _accountsModalFrame(
    AccountEditModal(
      // A key per combination: the field text is seeded in `initState`, so a
      // knob change has to remount the modal to be visible.
      key: ValueKey(
        'accounts_edit_modal_${initialName}_$profilePictureChanged',
      ),
      accountUuid: accountsPreviewCurrentUuid,
      accountName: 'Account Name',
      initialName: initialName,
      profilePictureId: profilePictureChanged
          ? 'pfp-08'
          : kDefaultProfilePictureId,
      profilePictureChanged: profilePictureChanged,
      onEditProfilePicture: _noop,
      onNameChanged: _ignoreName,
      onCancel: _noop,
      onUpdate: _previewUpdateName,
    ),
  );
}

/// Profile-picture picker modal on a plain desktop frame.
Widget accountsProfilePictureModalFixture({
  required String currentProfilePictureId,
}) {
  return _accountsModalFrame(
    AccountProfilePictureModal(
      currentProfilePictureId: currentProfilePictureId,
      onCancel: _noop,
      onUpdate: _previewUpdatePicture,
    ),
  );
}

/// The shared modal chrome on its own, so the card and its action row can be
/// reviewed without going through one of the three screen modals.
Widget accountsModalCardFixture({
  required bool destructiveAction,
  required bool trashIcon,
  required bool cancelEnabled,
  required bool actionEnabled,
}) {
  return _accountsModalFrame(
    AccountModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Builder(
            builder: (context) => Text(
              'Modal body copy sits here.',
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.accent,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AccountModalActions(
            onCancel: cancelEnabled ? _noop : null,
            actionLabel: destructiveAction ? 'Remove' : 'Update',
            onAction: actionEnabled ? _noop : null,
            actionVariant: destructiveAction
                ? AppButtonVariant.destructive
                : AppButtonVariant.primary,
            actionLeading: trashIcon
                ? const AppIcon(AppIcons.trash, size: AppIconSize.medium)
                : null,
          ),
        ],
      ),
    ),
  );
}

// --- Fixture plumbing ------------------------------------------------------

/// Idle migration coordinator for every preview that mounts the desktop
/// sidebar: the real one asks Rust for the chain tip on mount, and the
/// widgetbook binary never initialises Rust.
Override _accountsPreviewIdleMigrationOverride() {
  return ironwoodMigrationCoordinatorProvider.overrideWith(
    () => _AccountsPreviewMigrationCoordinator(accountUuid: null),
  );
}

Widget _accountsModalFrame(Widget modal) {
  return WbFrame(
    layout: WbLayout.desktop,
    child: Center(
      child: Material(type: MaterialType.transparency, child: modal),
    ),
  );
}

Future<int> _previewCount(int value, bool checking) {
  // A pending future is the modal's "still checking" state; it never settles,
  // which is exactly what that preview shows.
  return checking ? Completer<int>().future : Future.value(value);
}

void _noop() {}

void _ignoreName(String _) {}

Future<bool> _previewConfirmPassword(String _) async => false;

Future<void> _previewRemove(AccountRemoveProgressCallback _) async {}

Future<void> _previewUpdateName(String _) async {}

Future<void> _previewUpdatePicture(String _) async {}

AppBootstrapState _accountsPreviewBootstrap(
  AccountState accountState, {
  String initialLocation = '/accounts',
  ThemeMode themeMode = ThemeMode.system,
  bool syncKeepAwakeEnabled = false,
  RpcEndpointConfig? rpcEndpointConfig,
}) {
  return AppBootstrapState(
    initialLocation: initialLocation,
    initialAccountState: accountState,
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: rpcEndpointConfig ?? defaultRpcEndpointConfig('main'),
    explorerUrlTemplate: '',
    themeMode: themeMode,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
    syncKeepAwakeEnabled: syncKeepAwakeEnabled,
    syncKeepAwakePromptSeen: true,
  );
}

/// Minimal in-progress migration: `activeRunId` alone is what the remove
/// sheet reads to switch to its migration copy.
rust_sync.MigrationStatus _accountsPreviewMigrationStatus() {
  return rust_sync.MigrationStatus(
    phase: kIronwoodMigrationWaitingConfirmationsPhase,
    activeRunId: 'preview-accounts-run',
    targetValuesZatoshi: frb.Uint64List.fromList(const [1_000_000_000]),
    preparedNoteCount: 1,
    denominationConfirmationCount: 1,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 0,
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
    scheduleMaxDelayBlocks: 576,
    scheduledBroadcasts: const [],
    parts: const [],
  );
}

/// Hosts a sheet body inside the phone frame with its own navigator, so the
/// production close/pop callbacks land here instead of on the gallery root.
class _AccountsSheetHost extends StatelessWidget {
  const _AccountsSheetHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) => PageRouteBuilder<void>(
        settings: settings,
        opaque: false,
        pageBuilder: (_, _, _) => Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            type: MaterialType.transparency,
            child: MobileModalCard(child: child),
          ),
        ),
      ),
    );
  }
}

/// Opens the real picker from a post-frame callback. `showAppMobileSheet`
/// presents on the root navigator, so the sheet lands on the gallery canvas
/// (Material caps it at the bottom-sheet width) rather than inside a frame.
class _ProfilePictureSheetOpener extends StatefulWidget {
  const _ProfilePictureSheetOpener({required this.selectedId});

  final String selectedId;

  @override
  State<_ProfilePictureSheetOpener> createState() =>
      _ProfilePictureSheetOpenerState();
}

class _ProfilePictureSheetOpenerState
    extends State<_ProfilePictureSheetOpener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        showProfilePictureSheet(context, selectedId: widget.selectedId),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: context.colors.background.window);
  }
}

class _AccountsPreviewHarness extends StatefulWidget {
  const _AccountsPreviewHarness({
    this.initialOpenMenuAccountUuid,
    this.initialModalAccountUuid,
    this.initialModal,
  });

  final String? initialOpenMenuAccountUuid;
  final String? initialModalAccountUuid;
  final AccountsScreenInitialModal? initialModal;

  @override
  State<_AccountsPreviewHarness> createState() =>
      _AccountsPreviewHarnessState();
}

class _AccountsPreviewHarnessState extends State<_AccountsPreviewHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/accounts',
      routes: [
        GoRoute(
          path: '/accounts',
          builder: (_, _) => AccountsScreen(
            initialOpenMenuAccountUuid: widget.initialOpenMenuAccountUuid,
            initialModalAccountUuid: widget.initialModalAccountUuid,
            initialModal: widget.initialModal,
          ),
        ),
        for (final path in const [
          '/add-account',
          '/home',
          '/send',
          '/receive',
          '/activity',
          '/settings',
          '/settings/secret-passphrase',
        ])
          GoRoute(
            path: path,
            builder: (_, _) => _AccountsPreviewPlaceholder(label: path),
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
    return WbDesktopWindowBox(child: Router.withConfig(config: _router));
  }
}

class _MobileAccountsPreviewHarness extends StatefulWidget {
  const _MobileAccountsPreviewHarness({
    this.initialSheetAccountUuid,
    this.initialSheet,
    this.initialOpenMenuAccountUuid,
  });

  final String? initialSheetAccountUuid;
  final MobileAccountsInitialSheet? initialSheet;
  final String? initialOpenMenuAccountUuid;

  @override
  State<_MobileAccountsPreviewHarness> createState() =>
      _MobileAccountsPreviewHarnessState();
}

class _MobileAccountsPreviewHarnessState
    extends State<_MobileAccountsPreviewHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/accounts',
      routes: [
        GoRoute(
          path: '/accounts',
          builder: (_, _) => MobileAccountsScreen(
            initialSheetAccountUuid: widget.initialSheetAccountUuid,
            initialSheet: widget.initialSheet,
            initialOpenMenuAccountUuid: widget.initialOpenMenuAccountUuid,
          ),
        ),
        for (final path in const [
          '/add-account',
          '/send',
          '/settings/seed-phrase',
          '/settings/viewing-key',
        ])
          GoRoute(
            path: path,
            builder: (_, _) => _AccountsPreviewPlaceholder(label: path),
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

class _AccountsPreviewPlaceholder extends StatelessWidget {
  const _AccountsPreviewPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Navigated to $label'));
  }
}

class _AccountsPreviewAccountNotifier extends AccountNotifier {
  _AccountsPreviewAccountNotifier(this.initialState);

  final AccountState initialState;

  @override
  FutureOr<AccountState> build() => initialState;

  @override
  Future<SoftwareWalletSecret?> getSoftwareWalletSecretForAccount(
    String uuid,
  ) async =>
      const SoftwareWalletSecret(mnemonic: settingsPreviewMnemonic24Words);

  @override
  Future<void> switchAccount(String uuid) async {
    final prev = state.value ?? initialState;
    state = AsyncData(prev.copyWith(activeAccountUuid: uuid));
  }

  @override
  Future<void> renameAccount(String uuid, String newName) async {
    final prev = state.value ?? initialState;
    state = AsyncData(
      prev.copyWith(
        accounts: [
          for (final account in prev.accounts)
            if (account.uuid == uuid)
              account.copyWith(name: newName)
            else
              account,
        ],
      ),
    );
  }

  @override
  Future<void> updateProfilePicture(
    String uuid,
    String profilePictureId,
  ) async {
    final prev = state.value ?? initialState;
    state = AsyncData(
      prev.copyWith(
        accounts: [
          for (final account in prev.accounts)
            if (account.uuid == uuid)
              account.copyWith(profilePictureId: profilePictureId)
            else
              account,
        ],
      ),
    );
  }

  @override
  Future<void> removeAccount(String uuid) async {
    final prev = state.value ?? initialState;
    state = AsyncData(
      prev.copyWith(
        accounts: [
          for (final account in prev.accounts)
            if (account.uuid != uuid) account,
        ],
      ),
    );
  }

  @override
  Future<void> resetWallet() async {
    state = const AsyncData(AccountState());
  }
}

class _AccountsPreviewSyncNotifier extends SyncNotifier {
  _AccountsPreviewSyncNotifier(this.activeAccountUuid);

  final String? activeAccountUuid;

  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: activeAccountUuid,
    hasAccountScopedData: activeAccountUuid != null,
    isSyncing: true,
    percentage: 0.34,
    totalBalance: BigInt.from(14223000000),
  );

  @override
  Future<void> refreshAfterSend() async {}

  @override
  Future<void> refreshAfterAccountSwitch() async {}

  @override
  Future<void> restartSync() async {}

  @override
  Future<void> restartSyncAfterTransportChange(
    Future<void> Function() updateTransport, {
    bool failIfNotQuiescent = true,
  }) async {}

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

class _AccountsPreviewMigrationCoordinator
    extends IronwoodMigrationCoordinator {
  _AccountsPreviewMigrationCoordinator({
    required this.accountUuid,
    this.status,
  });

  final String? accountUuid;
  final rust_sync.MigrationStatus? status;

  @override
  IronwoodMigrationCoordinatorState build() {
    final uuid = accountUuid;
    final previewStatus = status;
    return IronwoodMigrationCoordinatorState(
      statuses: uuid == null || previewStatus == null
          ? const {}
          : {uuid: previewStatus},
    );
  }

  @override
  Future<void> recover(String accountUuid) async {}
}

class _AccountsPreviewReceiveAddressService implements ReceiveAddressService {
  const _AccountsPreviewReceiveAddressService();

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
        : 'u1widgetbookaccountsaddress';
  }

  @override
  Future<String> loadTransparentReceiveAddress({
    required String accountUuid,
  }) async {
    return 't1WidgetbookTransparentAddress';
  }

  @override
  Future<String> reserveOrchardAddress({required String accountUuid}) async {
    return 'u1widgetbookaccountsreservedaddress';
  }

  @override
  Future<String> renewShieldedAddress({required String accountUuid}) async {
    return 'u1widgetbookaccountsrenewedaddress';
  }
}

// --- Settings account states -----------------------------------------------

/// The design state with the Keystone account active: the secret-passphrase
/// row has no seed behind it and goes non-interactive.
final AccountState accountsPreviewKeystoneActiveState =
    accountsPreviewDesignState.copyWith(
      activeAccountUuid: accountsPreviewKeystoneUuid,
    );

// --- Settings screens ------------------------------------------------------

/// Which overlay the desktop settings preview opens on.
///
/// The updater's own download dialogs are not here: they are presented with
/// `showDialog(useRootNavigator: true)`, and [AppTheme] is a plain
/// `InheritedWidget` that neither `InheritedTheme.capture` nor the widgetbook
/// root carries, so they assert before they can paint. They preview through
/// [settingsUpdateDialogFixture] instead.
enum SettingsPreviewDesktopModal { none, theme, updates }

/// Desktop settings screen with its account, theme, Tor, scroll and overlay
/// axes driven independently.
///
/// `themeMode` reaches the Theme row through `themeModeProvider`, which reads
/// the bootstrap snapshot; it names the stored preference and does not repaint
/// the preview, whose theme stays on the Theme addon.
Widget settingsDesktopScreenFixture({
  required AccountState accountState,
  required ThemeMode themeMode,
  required NetworkPrivacyState networkPrivacyState,
  double initialScrollOffset = 0,
  SettingsPreviewDesktopModal modal = SettingsPreviewDesktopModal.none,
  WindowsUpdateState updater = settingsPreviewWindowsUpdateState,
  Map<String, WidgetBuilder> routeBuilders = const {},
  RpcEndpointConfig? rpcEndpointConfig,
  RpcEndpointLatencyState? endpointLatency,
  String? explorerUrlTemplate,
  AppSecurityState? appSecurityState,
}) {
  // The updater row is gated on `defaultTargetPlatform`, so the Windows-only
  // overlay previews by swapping it for the subtree.
  final needsWindows = modal == SettingsPreviewDesktopModal.updates;
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _accountsPreviewBootstrap(
          accountState,
          initialLocation: '/settings',
          themeMode: themeMode,
        ),
      ),
      accountProvider.overrideWith(
        () => _AccountsPreviewAccountNotifier(accountState),
      ),
      syncProvider.overrideWith(
        () => _AccountsPreviewSyncNotifier(accountState.activeAccountUuid),
      ),
      receiveAddressServiceProvider.overrideWithValue(
        const _AccountsPreviewReceiveAddressService(),
      ),
      networkPrivacyProvider.overrideWith(
        () => _SettingsPreviewNetworkPrivacyNotifier(networkPrivacyState),
      ),
      themeModeProvider.overrideWith(
        () => _SettingsPreviewThemeModeNotifier(themeMode),
      ),
      if (rpcEndpointConfig != null)
        rpcEndpointProvider.overrideWith(
          () => _SettingsPreviewRpcEndpointNotifier(rpcEndpointConfig),
        ),
      if (endpointLatency != null)
        rpcEndpointLatencyProvider.overrideWith(
          () => _SettingsPreviewEndpointLatencyNotifier(endpointLatency),
        ),
      if (explorerUrlTemplate != null)
        zcashExplorerProvider.overrideWith(
          () => _SettingsPreviewExplorerNotifier(explorerUrlTemplate),
        ),
      if (appSecurityState != null)
        appSecurityProvider.overrideWith(
          () => _SettingsPreviewAppSecurityNotifier(appSecurityState),
        ),
      windowsUpdateProvider.overrideWith(
        () => _SettingsPreviewWindowsUpdateNotifier(updater),
      ),
      _accountsPreviewIdleMigrationOverride(),
    ],
    child: WbPlatformOverride(
      platform: needsWindows ? TargetPlatform.windows : null,
      child: _SettingsPreviewHarness(
        initialScrollOffset: initialScrollOffset,
        modal: modal,
        routeBuilders: routeBuilders,
      ),
    ),
  );
}

/// Which Windows update download dialog the preview shows.
///
/// One option per production call site, because the copy is what separates
/// them: [WindowsUpdateErrorDialog] carries only a title and a message.
enum SettingsPreviewUpdateDialog {
  privacyChoice,
  torRouteBlocked,
  torStillOn,
  updatesUnavailable,
  downloadNotStarted,
  downloadNotReady,
  updaterOffTor,
}

/// One Windows update dialog with the copy its call site in
/// `windows_update_download_flow.dart` passes, on the `showDialog` barrier.
Widget settingsUpdateDialogFixture({
  required SettingsPreviewUpdateDialog dialog,
}) {
  return WbFrame(
    layout: WbLayout.desktop,
    child: _SettingsUpdateDialogHost(
      // The host's navigator builds its page once, so the knob only reaches
      // the live widgetbook on a remount.
      key: ValueKey('wb_settings_update_dialog_${dialog.name}'),
      child: switch (dialog) {
        SettingsPreviewUpdateDialog.privacyChoice =>
          const WindowsUpdatePrivacyChoiceDialog(),
        SettingsPreviewUpdateDialog.torRouteBlocked =>
          const WindowsUpdateErrorDialog(
            title: 'Software updates unavailable over Tor',
            message:
                'Vizor kept direct requests blocked. Retry updates in Settings, '
                'or turn off Tor and try the download again.',
          ),
        SettingsPreviewUpdateDialog.torStillOn => const WindowsUpdateErrorDialog(
          title: "Couldn't turn off Tor",
          message:
              'Tor remains on, so Vizor kept the update blocked. Try again, or '
              'turn off Tor in Settings before downloading.',
        ),
        SettingsPreviewUpdateDialog.updatesUnavailable =>
          const WindowsUpdateErrorDialog(
            title: 'Software updates unavailable',
            message:
                'Tor is off, but software updates are still unavailable. Retry '
                'updates in Settings before downloading.',
          ),
        // The three download-result options share the title and differ only in
        // the message the notifier reports.
        SettingsPreviewUpdateDialog.downloadNotStarted =>
          const WindowsUpdateErrorDialog(
            title: kSettingsPreviewUpdateDownloadErrorTitle,
            message: kWindowsUpdateGenericFailureMessage,
          ),
        SettingsPreviewUpdateDialog.downloadNotReady =>
          const WindowsUpdateErrorDialog(
            title: kSettingsPreviewUpdateDownloadErrorTitle,
            message:
                'This update is no longer ready to download. Check for updates '
                'again.',
          ),
        SettingsPreviewUpdateDialog.updaterOffTor =>
          const WindowsUpdateErrorDialog(
            title: kSettingsPreviewUpdateDownloadErrorTitle,
            message: kWindowsTorUpdateRouteUnavailableMessage,
          ),
      },
    ),
  );
}

/// Title `startWindowsUpdateDownload` gives every failed download result.
const kSettingsPreviewUpdateDownloadErrorTitle = "Couldn't start the update";

/// Hosts a dialog in its own navigator so the production Cancel/Close pops
/// land here instead of on the gallery root.
class _SettingsUpdateDialogHost extends StatelessWidget {
  const _SettingsUpdateDialogHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) => PageRouteBuilder<void>(
        settings: settings,
        pageBuilder: (context, _, _) => ColoredBox(
          color: context.colors.background.window,
          // `showDialog`'s default barrier, which is what the updater uses.
          child: ColoredBox(color: Colors.black54, child: child),
        ),
      ),
    );
  }
}

/// Where the mobile settings list is parked.
enum MobileSettingsScrollTarget { top, explorerRow, footer }

/// Which mobile settings sheet the preview opens on.
enum SettingsPreviewMobileSheet { none, theme, disableBiometric }

/// Mobile settings screen inside the tab shell, with account, biometric,
/// keep-awake, theme, Tor, scroll position and sheet as independent axes.
Widget settingsMobileScreenFixture({
  required AccountState accountState,
  required ThemeMode themeMode,
  required NetworkPrivacyState networkPrivacyState,
  required BiometricUnlockState biometricState,
  required bool keepAwakeEnabled,
  required MobileSettingsScrollTarget scroll,
  SettingsPreviewMobileSheet sheet = SettingsPreviewMobileSheet.none,
  bool interactive = false,
  Map<String, WidgetBuilder> routeBuilders = const {},
  RpcEndpointConfig? rpcEndpointConfig,
  RpcEndpointLatencyState? endpointLatency,
  String? explorerUrlTemplate,
  AppSecurityState? appSecurityState,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _accountsPreviewBootstrap(
          accountState,
          initialLocation: '/settings',
          themeMode: themeMode,
          syncKeepAwakeEnabled: keepAwakeEnabled,
        ),
      ),
      accountProvider.overrideWith(
        () => _AccountsPreviewAccountNotifier(accountState),
      ),
      syncProvider.overrideWith(
        () => _AccountsPreviewSyncNotifier(accountState.activeAccountUuid),
      ),
      receiveAddressServiceProvider.overrideWithValue(
        const _AccountsPreviewReceiveAddressService(),
      ),
      networkPrivacyProvider.overrideWith(
        () => _SettingsPreviewNetworkPrivacyNotifier(networkPrivacyState),
      ),
      biometricUnlockProvider.overrideWith(
        () => _SettingsPreviewBiometricNotifier(biometricState),
      ),
      themeModeProvider.overrideWith(
        () => _SettingsPreviewThemeModeNotifier(themeMode),
      ),
      syncKeepAwakeProvider.overrideWith(
        () => _SettingsPreviewSyncKeepAwakeNotifier(keepAwakeEnabled),
      ),
      if (rpcEndpointConfig != null)
        rpcEndpointProvider.overrideWith(
          () => _SettingsPreviewRpcEndpointNotifier(rpcEndpointConfig),
        ),
      if (endpointLatency != null)
        rpcEndpointLatencyProvider.overrideWith(
          () => _SettingsPreviewEndpointLatencyNotifier(endpointLatency),
        ),
      if (explorerUrlTemplate != null)
        zcashExplorerProvider.overrideWith(
          () => _SettingsPreviewExplorerNotifier(explorerUrlTemplate),
        ),
      if (appSecurityState != null)
        appSecurityProvider.overrideWith(
          () => _SettingsPreviewAppSecurityNotifier(appSecurityState),
        ),
    ],
    child: _MobileSettingsPreviewFrame(
      child: interactive
          ? _InteractiveMobileSettingsPreview(
              scroll: scroll,
              sheet: sheet,
              routeBuilders: routeBuilders,
            )
          : IgnorePointer(
              child: _MobileSettingsPreview(scroll: scroll, sheet: sheet),
            ),
    ),
  );
}

/// Settings sub-screen scaffolding: the desktop link-mobile session.
Widget settingsWalletLinkScreenFixture({
  required WalletLinkState previewState,
}) {
  return _settingsSubScreenFixture(
    '/settings/link-mobile',
    WalletLinkDesktopScreen(previewState: previewState),
  );
}

/// Settings sub-screen scaffolding: the uninstall flow at one of its stages.
Widget settingsUninstallScreenFixture({required SettingsUninstallStage stage}) {
  return _settingsSubScreenFixture(
    '/settings/uninstall',
    SettingsUninstallScreen(initialStage: stage),
  );
}

// --- Settings components ---------------------------------------------------

/// Desktop Tor control over the full provider-state matrix.
Widget settingsNetworkPrivacyControlFixture({
  required NetworkPrivacyState state,
  required bool showSurface,
}) {
  return _networkPrivacyScope(
    state,
    WbFrame(
      layout: WbLayout.desktop,
      child: Center(
        child: SizedBox(
          width: 420,
          child: NetworkPrivacyControl(showSurface: showSurface),
        ),
      ),
    ),
  );
}

/// Mobile Tor card over the same provider-state matrix.
Widget settingsMobileNetworkPrivacyCardFixture({
  required NetworkPrivacyState state,
}) {
  return _networkPrivacyScope(
    state,
    WbFrame(
      layout: WbLayout.mobile,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: const Align(
          alignment: Alignment.topCenter,
          child: Material(
            type: MaterialType.transparency,
            child: MobileNetworkPrivacyCard(),
          ),
        ),
      ),
    ),
  );
}

/// The shared password gate behind five settings flows.
///
/// `autofocus` is off: the preview must not take the keyboard away from the
/// gallery's own knob panel.
Widget settingsConfirmAccessCardFixture({
  required String subtitle,
  required String? errorText,
  required String password,
  required bool isSubmitting,
}) {
  return WbFrame(
    layout: WbLayout.desktop,
    child: Center(
      child: _ConfirmAccessCardPreview(
        // The controller text is seeded once per mount, so a knob change has
        // to remount the preview to be visible.
        key: ValueKey('settings_confirm_access_$password'),
        subtitle: subtitle,
        errorText: errorText,
        password: password,
        isSubmitting: isSubmitting,
      ),
    ),
  );
}

/// The etched settings backdrop on its own, including the `vault` art that
/// has no production caller yet.
Widget settingsPaneBackdropFixture({required SettingsBackdropArt art}) {
  return WbFrame(
    layout: WbLayout.desktop,
    child: SettingsPaneBackdrop(art: art),
  );
}

// --- Settings fixture plumbing ---------------------------------------------

Widget _networkPrivacyScope(NetworkPrivacyState state, Widget child) {
  return ProviderScope(
    overrides: [
      networkPrivacyProvider.overrideWith(
        () => _SettingsPreviewNetworkPrivacyNotifier(state),
      ),
    ],
    child: child,
  );
}

Widget _settingsSubScreenFixture(
  String path,
  Widget screen, {
  RpcEndpointConfig? rpcEndpointConfig,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _accountsPreviewBootstrap(
          accountsPreviewDesignState,
          initialLocation: path,
          rpcEndpointConfig: rpcEndpointConfig,
        ),
      ),
      accountProvider.overrideWith(
        () => _AccountsPreviewAccountNotifier(accountsPreviewDesignState),
      ),
      syncProvider.overrideWith(
        () => _AccountsPreviewSyncNotifier(
          accountsPreviewDesignState.activeAccountUuid,
        ),
      ),
      receiveAddressServiceProvider.overrideWithValue(
        const _AccountsPreviewReceiveAddressService(),
      ),
      _accountsPreviewIdleMigrationOverride(),
      ...overrides,
    ],
    child: _SettingsSubScreenPreviewHarness(path: path, screen: screen),
  );
}

const _settingsPreviewTabItems = [
  AppMobileTabItem(iconName: AppIcons.home, label: 'Home'),
  AppMobileTabItem(iconName: AppIcons.swapArrows, label: 'Swap'),
  AppMobileTabItem(iconName: AppIcons.history, label: 'Activity'),
  AppMobileTabItem(iconName: AppIcons.cog, label: 'Settings'),
];

class _ConfirmAccessCardPreview extends StatefulWidget {
  const _ConfirmAccessCardPreview({
    required this.subtitle,
    required this.errorText,
    required this.password,
    required this.isSubmitting,
    super.key,
  });

  final String subtitle;
  final String? errorText;
  final String password;
  final bool isSubmitting;

  @override
  State<_ConfirmAccessCardPreview> createState() =>
      _ConfirmAccessCardPreviewState();
}

class _ConfirmAccessCardPreviewState extends State<_ConfirmAccessCardPreview> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.password,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConfirmAccessCard(
      subtitle: widget.subtitle,
      controller: _controller,
      errorText: widget.errorText,
      isSubmitting: widget.isSubmitting,
      canSubmit: isWalletPasswordValid(widget.password),
      onChanged: _noop,
      onSubmit: _noop,
      autofocus: false,
    );
  }
}

/// The frame the three registered mobile-settings builders already use
/// (`_MobilePreviewFrame(constrainToDesignSize: false)`): the host canvas with
/// the phone's safe-area insets. Matching it keeps a knob change a state
/// change and never a frame change.
class _MobileSettingsPreviewFrame extends StatelessWidget {
  const _MobileSettingsPreviewFrame({required this.child});

  final Widget child;

  static const _safeAreaPadding = EdgeInsets.only(top: 55, bottom: 24);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(padding: _safeAreaPadding, viewPadding: _safeAreaPadding),
        child: child,
      ),
    );
  }
}

class _MobileSettingsPreview extends StatefulWidget {
  const _MobileSettingsPreview({required this.scroll, required this.sheet});

  final MobileSettingsScrollTarget scroll;
  final SettingsPreviewMobileSheet sheet;

  @override
  State<_MobileSettingsPreview> createState() => _MobileSettingsPreviewState();
}

class _MobileSettingsPreviewState extends State<_MobileSettingsPreview> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.sheet == SettingsPreviewMobileSheet.none) return;
    // Both sheets are private and open from their row's `onTap`, so the
    // preview fires the row the user would tap.
    final key = widget.sheet == SettingsPreviewMobileSheet.theme
        ? const ValueKey('mobile_settings_theme_row')
        : const ValueKey('mobile_settings_biometric_row');
    _openSheetWhenLaidOut(key);
  }

  void _openSheetWhenLaidOut(Key key, [int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _tapMobileListRow(context, key) ||
          attempt >= _previewOpenAttempts) {
        return;
      }
      _openSheetWhenLaidOut(key, attempt + 1);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _park() {
    switch (widget.scroll) {
      case MobileSettingsScrollTarget.top:
        return;
      case MobileSettingsScrollTarget.footer:
        // ListView refines its extent as lazy children lay out, so follow the
        // updates until the preview settles at the actual list end.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_controller.hasClients) return;
          final position = _controller.position;
          if (position.pixels != position.maxScrollExtent) {
            _controller.jumpTo(position.maxScrollExtent);
          }
        });
      case MobileSettingsScrollTarget.explorerRow:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Element? found;
          void visitor(Element element) {
            if (found != null) return;
            if (element.widget.key ==
                const ValueKey('mobile_settings_explorer_row')) {
              found = element;
              return;
            }
            element.visitChildren(visitor);
          }

          context.visitChildElements(visitor);
          final rowContext = found;
          if (rowContext == null) return;
          Scrollable.ensureVisible(rowContext, alignment: 0.4);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppMobileShell(
      body: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _park();
          return false;
        },
        child: PrimaryScrollController(
          controller: _controller,
          child: const MobileSettingsScreen(),
        ),
      ),
      tabBar: AppMobileTabBar(
        items: _settingsPreviewTabItems,
        currentIndex: 3,
        onSelect: _ignoreTab,
      ),
    );
  }
}

/// Router-backed settings preview. It keeps production navigation inside the
/// preview's in-memory ProviderScope while preserving the selected list state.
class _InteractiveMobileSettingsPreview extends StatefulWidget {
  const _InteractiveMobileSettingsPreview({
    required this.scroll,
    required this.sheet,
    required this.routeBuilders,
  });

  final MobileSettingsScrollTarget scroll;
  final SettingsPreviewMobileSheet sheet;
  final Map<String, WidgetBuilder> routeBuilders;

  @override
  State<_InteractiveMobileSettingsPreview> createState() =>
      _InteractiveMobileSettingsPreviewState();
}

class _InteractiveMobileSettingsPreviewState
    extends State<_InteractiveMobileSettingsPreview> {
  late final GoRouter _router;
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.sheet != SettingsPreviewMobileSheet.none) {
      final key = widget.sheet == SettingsPreviewMobileSheet.theme
          ? const ValueKey('mobile_settings_theme_row')
          : const ValueKey('mobile_settings_biometric_row');
      _openSheetWhenLaidOut(key);
    }
    _router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (_, _) => NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              _park();
              return false;
            },
            child: PrimaryScrollController(
              controller: _controller,
              child: const MobileSettingsScreen(),
            ),
          ),
        ),
        for (final path in const [
          '/settings/endpoint',
          '/settings/explorer',
          '/settings/seed-phrase',
          '/settings/viewing-key',
          '/settings/change-password',
          '/settings/address-book',
          '/voting',
          '/payment-links',
          '/about',
          '/home',
          '/unlock',
        ])
          GoRoute(
            path: path,
            builder: (context, _) =>
                widget.routeBuilders[path]?.call(context) ??
                _AccountsPreviewPlaceholder(label: path),
          ),
      ],
    );
  }

  void _openSheetWhenLaidOut(Key key, [int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tapMobileListRow(context, key) || attempt >= 8) return;
      _openSheetWhenLaidOut(key, attempt + 1);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _park() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final position = _controller.position;
      switch (widget.scroll) {
        case MobileSettingsScrollTarget.top:
          return;
        case MobileSettingsScrollTarget.footer:
          if (position.pixels != position.maxScrollExtent) {
            _controller.jumpTo(position.maxScrollExtent);
          }
        case MobileSettingsScrollTarget.explorerRow:
          final row = _findPreviewElement(
            context,
            (widget) =>
                widget.key == const ValueKey('mobile_settings_explorer_row'),
          );
          if (row != null) Scrollable.ensureVisible(row, alignment: 0.4);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppMobileShell(
    body: Router.withConfig(config: _router),
    tabBar: AppMobileTabBar(
      items: _settingsPreviewTabItems,
      currentIndex: 3,
      onSelect: _ignoreTab,
    ),
  );
}

/// Updater snapshot behind the desktop Updates modal.
const WindowsUpdateState settingsPreviewWindowsUpdateState = WindowsUpdateState(
  supported: true,
  status: WindowsUpdateStatus.available,
  currentVersion: '1.4.1',
  appId: 'cash.vizor.desktop',
  repoUrl: 'https://example.invalid/vizor',
  availableVersion: '1.4.2',
  downloadProgress: 0,
  pendingRestart: false,
  torProxyReady: true,
  message: '',
);

/// The updater snapshot for one status: the modal's info rows, status line,
/// progress bar and primary action all read off this one state.
WindowsUpdateState settingsPreviewWindowsUpdateStateFor(
  WindowsUpdateStatus status, {
  bool supported = true,
  // Empty leaves the modal on its own copy; a service message overrides it.
  String message = '',
}) {
  return WindowsUpdateState(
    supported: supported,
    status: status,
    currentVersion: settingsPreviewWindowsUpdateState.currentVersion,
    appId: settingsPreviewWindowsUpdateState.appId,
    repoUrl: settingsPreviewWindowsUpdateState.repoUrl,
    // Only a status that knows the next version names one.
    availableVersion: switch (status) {
      WindowsUpdateStatus.available ||
      WindowsUpdateStatus.downloading ||
      WindowsUpdateStatus.ready ||
      WindowsUpdateStatus.applying =>
        settingsPreviewWindowsUpdateState.availableVersion,
      _ => '',
    },
    downloadProgress: status == WindowsUpdateStatus.downloading ? 42 : 0,
    pendingRestart: status == WindowsUpdateStatus.ready,
    torProxyReady: true,
    message: message,
  );
}

class _SettingsPreviewWindowsUpdateNotifier extends WindowsUpdateNotifier {
  _SettingsPreviewWindowsUpdateNotifier(this.initialState);

  final WindowsUpdateState initialState;

  @override
  WindowsUpdateState build() => initialState;

  @override
  Future<void> checkForUpdates() async {}

  @override
  Future<void> applyUpdateAndRestart() async {}

  // No installer behind a preview, so the download reports the failure the
  // error dialog exists to show.
  @override
  Future<WindowsUpdateDownloadResult> downloadUpdate() async =>
      const WindowsUpdateDownloadResult.failed(
        'The update package could not be downloaded. Try again.',
      );
}

class _SettingsPreviewThemeModeNotifier extends ThemeModeNotifier {
  _SettingsPreviewThemeModeNotifier(this.initialMode);

  final ThemeMode initialMode;

  @override
  ThemeMode build() => initialMode;

  @override
  Future<void> set(ThemeMode mode) async {
    state = mode;
  }
}

class _SettingsPreviewAppSecurityNotifier extends AppSecurityNotifier {
  _SettingsPreviewAppSecurityNotifier(this.initialState);

  final AppSecurityState initialState;

  @override
  AppSecurityState build() => initialState;

  @override
  void lock() => state = state.copyWith(isUnlocked: false);

  @override
  void reset() => state = const AppSecurityState(
    isPasswordConfigured: false,
    isUnlocked: false,
  );

  @override
  String requireSessionPasswordForNativeSecretUse() => '123456';

  @override
  Future<bool> confirmPassword(String password) async =>
      _isPreviewPasscode(password);

  @override
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (!_isPreviewPasscode(currentPassword) ||
        !_isPreviewPasscode(newPassword) ||
        currentPassword == newPassword) {
      return false;
    }
    state = state.copyWith(isPasswordConfigured: true, isUnlocked: true);
    return true;
  }

  bool _isPreviewPasscode(String value) =>
      value.length == kMobilePasscodeLength &&
      value.codeUnits.every((codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39);
}

class _SettingsPreviewRpcEndpointNotifier extends RpcEndpointNotifier {
  _SettingsPreviewRpcEndpointNotifier(this.initialState);

  final RpcEndpointConfig initialState;

  @override
  RpcEndpointConfig build() => initialState;

  @override
  Future<void> setPreset(RpcEndpointPreset preset) async {
    state = state.copyWith(lightwalletdUrl: preset.url, presetId: preset.id);
  }

  @override
  Future<void> setCustom(String input) async {
    state = state.copyWith(
      lightwalletdUrl: normalizeRpcEndpointUrl(input, allowDefaultPort: true),
      presetId: kCustomRpcEndpointPresetId,
    );
  }
}

class _SettingsPreviewExplorerNotifier extends ZcashExplorerNotifier {
  _SettingsPreviewExplorerNotifier(this.initialState);

  final String initialState;

  @override
  String build() => initialState;

  @override
  Future<void> setCustom(String input) async {
    state = normalizeExplorerUrlTemplate(input);
  }

  @override
  Future<void> resetToDefault() async => state = '';
}

class _SettingsPreviewSyncKeepAwakeNotifier extends SyncKeepAwakeNotifier {
  _SettingsPreviewSyncKeepAwakeNotifier(this.enabled);

  final bool enabled;

  @override
  SyncKeepAwakeSettings build() =>
      SyncKeepAwakeSettings(enabled: enabled, promptSeen: true);

  @override
  Future<void> setEnabled(bool enabled, {bool markPromptSeen = true}) async {
    state = state.copyWith(enabled: enabled, promptSeen: markPromptSeen);
  }
}

/// Opens a desktop settings pane modal after the first frame: the modal is
/// private screen state, so the preview fires the row the user would click.
class _SettingsModalOpener extends StatefulWidget {
  const _SettingsModalOpener({required this.modal, required this.child});

  final SettingsPreviewDesktopModal modal;
  final Widget child;

  @override
  State<_SettingsModalOpener> createState() => _SettingsModalOpenerState();
}

class _SettingsModalOpenerState extends State<_SettingsModalOpener> {
  @override
  void initState() {
    super.initState();
    switch (widget.modal) {
      case SettingsPreviewDesktopModal.none:
        return;
      case SettingsPreviewDesktopModal.theme:
        _openWhenLaidOut(() => _tapSettingsRow(context, 'Theme'));
      case SettingsPreviewDesktopModal.updates:
        _openWhenLaidOut(() => _tapSettingsRow(context, 'Updates'));
    }
  }

  void _openWhenLaidOut(bool Function() open, [int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || open() || attempt >= _previewOpenAttempts) return;
      _openWhenLaidOut(open, attempt + 1);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A row can be a frame or two late when its provider is still loading, so a
/// preview opener retries before giving up.
const _previewOpenAttempts = 4;

/// Fires the settings row whose label is [label] through the `GestureDetector`
/// it wraps its content in.
bool _tapSettingsRow(BuildContext context, String label) {
  final element = _findPreviewElement(
    context,
    (widget) => widget is Text && widget.data == label,
  );
  if (element == null) return false;
  VoidCallback? onTap;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is GestureDetector && widget.onTap != null) {
      onTap = widget.onTap;
      return false;
    }
    return true;
  });
  final callback = onTap;
  if (callback == null) return false;
  callback();
  return true;
}

/// Fires the `onTap` of the [MobileListRow] carrying [key].
bool _tapMobileListRow(BuildContext context, Key key) {
  final element = _findPreviewElement(context, (widget) => widget.key == key);
  final row = element?.widget;
  if (row is! MobileListRow) return false;
  final onTap = row.onTap;
  if (onTap == null) return false;
  onTap();
  return true;
}

Element? _findPreviewElement(
  BuildContext context,
  bool Function(Widget widget) test,
) {
  Element? found;
  void visit(Element element) {
    if (found != null) return;
    if (test(element.widget)) {
      found = element;
      return;
    }
    element.visitChildren(visit);
  }

  context.visitChildElements(visit);
  return found;
}

class _SettingsPreviewHarness extends StatefulWidget {
  const _SettingsPreviewHarness({
    required this.initialScrollOffset,
    required this.modal,
    this.routeBuilders = const {},
  });

  final double initialScrollOffset;
  final SettingsPreviewDesktopModal modal;
  final Map<String, WidgetBuilder> routeBuilders;

  @override
  State<_SettingsPreviewHarness> createState() =>
      _SettingsPreviewHarnessState();
}

class _SettingsPreviewHarnessState extends State<_SettingsPreviewHarness> {
  late final GoRouter _router;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: widget.initialScrollOffset,
    );
    _router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (_, _) => _SettingsModalOpener(
            modal: widget.modal,
            child: SettingsScreen(scrollController: _scrollController),
          ),
        ),
        for (final path in const [
          '/settings/secret-passphrase',
          '/settings/viewing-key',
          '/settings/change-password',
          '/settings/endpoint',
          '/settings/explorer',
          '/settings/link-mobile',
          '/settings/uninstall',
          '/address-book',
          '/payment-links',
          '/donation',
          '/about',
          '/privacy',
          '/terms',
          '/home',
          '/send',
          '/receive',
          '/activity',
          '/accounts',
          '/unlock',
        ])
          GoRoute(
            path: path,
            builder: (context, _) =>
                widget.routeBuilders[path]?.call(context) ??
                _AccountsPreviewPlaceholder(label: path),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mirror the app-level opaque window underlay so transparent shells do
    // not show the gallery chrome.
    return WbDesktopWindowBox(
      child: ColoredBox(
        color: context.colors.macosUtility.window,
        child: Router.withConfig(config: _router),
      ),
    );
  }
}

class _SettingsSubScreenPreviewHarness extends StatefulWidget {
  const _SettingsSubScreenPreviewHarness({
    required this.path,
    required this.screen,
  });

  final String path;
  final Widget screen;

  @override
  State<_SettingsSubScreenPreviewHarness> createState() =>
      _SettingsSubScreenPreviewHarnessState();
}

class _SettingsSubScreenPreviewHarnessState
    extends State<_SettingsSubScreenPreviewHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: widget.path,
      routes: [
        GoRoute(path: widget.path, builder: (_, _) => widget.screen),
        for (final path in const [
          '/settings',
          '/home',
          '/welcome',
          '/unlock',
          '/accounts',
        ])
          GoRoute(
            path: path,
            builder: (_, _) => _AccountsPreviewPlaceholder(label: path),
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

class _SettingsPreviewNetworkPrivacyNotifier extends NetworkPrivacyNotifier {
  _SettingsPreviewNetworkPrivacyNotifier(this.initialState);

  final NetworkPrivacyState initialState;

  @override
  NetworkPrivacyState build() => initialState;

  @override
  Future<void> setTorEnabled(bool enabled) async {
    state = enabled
        ? NetworkPrivacyState(
            torEnabled: true,
            status: NetworkPrivacyConnectionStatus.connected,
            softwareUpdatesAvailable: state.softwareUpdatesAvailable,
          )
        : NetworkPrivacyState(
            torEnabled: false,
            status: NetworkPrivacyConnectionStatus.off,
            softwareUpdatesAvailable: state.softwareUpdatesAvailable,
          );
  }

  @override
  Future<void> retry() async {}

  @override
  Future<void> retrySoftwareUpdates() async {}
}

class _SettingsPreviewBiometricNotifier extends BiometricUnlockNotifier {
  _SettingsPreviewBiometricNotifier(this.initialState);

  final BiometricUnlockState initialState;

  @override
  Future<BiometricUnlockState> build() async => initialState;

  @override
  Future<void> enable(String passcode) async {
    state = AsyncData((state.value ?? initialState).copyWith(enabled: true));
  }

  @override
  Future<void> disable() async {
    state = AsyncData((state.value ?? initialState).copyWith(enabled: false));
  }

  @override
  Future<String?> readPasscode({required String reason}) async => null;
}

void _ignoreTab(int _) {}

// --- Secret passphrase / viewing key ---------------------------------------

/// Default 24-word phrase behind the desktop reveal.
const settingsPreviewMnemonic24Words =
    'caution dream solar agent witness logic hurdle focus benefit rough index '
    'genuine puzzle sudden modify active effort merit fossil carbon drift '
    'narrow across raise';

/// Same phrase truncated to the 12-word length a shorter seed produces.
const settingsPreviewMnemonic12Words =
    'caution dream solar agent witness logic hurdle focus benefit rough index '
    'genuine';

const settingsPreviewBip39Passphrase = '123CAsd#41 recovery phrase 123CAsd#41';

/// Birthday the reveal shows when both lookups succeed.
const kSettingsPreviewBirthdayHeight = 3428019;
const kSettingsPreviewBirthdayBlockTime = 1785196800;

/// Placeholder viewing key: long enough to wrap the card, not a real UFVK.
const settingsPreviewUfvk =
    'uview1qthqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq'
    'qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq'
    'qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq'
    'previewonly';

/// Desktop secret-passphrase reveal. A height or block time of 0 is what the
/// screen renders as the '-' row with its copy button hidden.
Widget settingsSeedPhraseRevealFixture({
  required String mnemonic,
  String? bip39Passphrase,
  int birthdayHeight = kSettingsPreviewBirthdayHeight,
  int birthdayBlockTime = kSettingsPreviewBirthdayBlockTime,
}) {
  return _settingsSubScreenFixture(
    '/settings/secret-passphrase',
    SettingsSeedPhraseRevealPreview(
      mnemonic: mnemonic,
      bip39Passphrase: bip39Passphrase,
      birthdayHeight: birthdayHeight,
      birthdayBlockTime: birthdayBlockTime,
    ),
  );
}

/// Mobile secret-passphrase gate. The reveal stage is deliberately out of
/// reach: it only opens behind a real passcode or biometric confirmation.
Widget settingsMobileSeedPhraseGateFixture({
  required BiometricUnlockState biometricState,
}) {
  return _mobileSubScreenFixture(
    path: '/settings/secret-passphrase',
    biometricState: biometricState,
    builder: (controller) => MobileSeedPhraseScreen(
      // No platform screenshot channel and no birthday lookup in a preview.
      screenshotStream: const Stream<void>.empty(),
      loadBirthday: false,
      privacyOverlayController: controller,
    ),
  );
}

/// Mobile viewing-key gate; the reveal has its own registered fixture.
Widget settingsMobileViewingKeyGateFixture({
  required BiometricUnlockState biometricState,
}) {
  return _mobileSubScreenFixture(
    path: '/settings/viewing-key',
    biometricState: biometricState,
    builder: (controller) => MobileViewingKeyScreen(
      privacyOverlayController: controller,
      ufvkLoader: _settingsPreviewUfvkLoader,
    ),
  );
}

Future<String> _settingsPreviewUfvkLoader(String accountUuid) async =>
    settingsPreviewUfvk;

// --- Endpoint ---------------------------------------------------------------

/// The shipped default preset.
final RpcEndpointConfig settingsPreviewDefaultEndpoint =
    defaultRpcEndpointConfig('main');

/// A host outside the preset list: no preset card is selected and the current
/// endpoint line loses its '(Default)' suffix.
const RpcEndpointConfig settingsPreviewCustomEndpoint = RpcEndpointConfig(
  networkName: 'main',
  lightwalletdUrl: 'https://lwd.example.org:9067',
  presetId: kCustomRpcEndpointPresetId,
);

/// Fixed latency samples for every preset plus the custom host, so the
/// endpoint screens show their latency lines without measuring anything.
RpcEndpointLatencyState settingsPreviewEndpointLatencyState() {
  const latenciesMs = [42, 118, 133, 187, 210, 264, 301, 355];
  final presets = rpcEndpointPresetsForNetwork('main');
  var state = const RpcEndpointLatencyState();
  for (var i = 0; i < presets.length; i += 1) {
    state = state.copyWithSample(
      presets[i].url,
      RpcEndpointLatencySample.available(
        Duration(milliseconds: latenciesMs[i % latenciesMs.length]),
      ),
    );
  }
  return state.copyWithSample(
    settingsPreviewCustomEndpoint.lightwalletdUrl,
    const RpcEndpointLatencySample.available(Duration(milliseconds: 96)),
  );
}

/// Desktop endpoint list tab.
Widget settingsEndpointScreenFixture({
  required RpcEndpointConfig endpoint,
  required RpcEndpointLatencyState latency,
}) {
  return _settingsSubScreenFixture(
    '/settings/endpoint',
    const SettingsEndpointScreen(),
    rpcEndpointConfig: endpoint,
    overrides: _endpointLatencyOverrides(latency),
  );
}

/// Mobile endpoint list tab, with the floating update bar.
Widget settingsMobileEndpointScreenFixture({
  required RpcEndpointConfig endpoint,
  required RpcEndpointLatencyState latency,
}) {
  return _mobileSubScreenFixture(
    path: '/settings/endpoint',
    rpcEndpointConfig: endpoint,
    overrides: _endpointLatencyOverrides(latency),
    builder: (_) => const MobileEndpointScreen(),
  );
}

List<Override> _endpointLatencyOverrides(RpcEndpointLatencyState latency) {
  return [
    rpcEndpointLatencyProvider.overrideWith(
      () => _SettingsPreviewEndpointLatencyNotifier(latency),
    ),
  ];
}

// --- Change passcode --------------------------------------------------------

/// Mobile passcode change. Only the verify phase is reachable: the later
/// phases are behind a real passcode check inside the screen's state.
Widget settingsMobileChangePasscodeFixture() {
  return _mobileSubScreenFixture(
    path: '/settings/change-passcode',
    withParentRoute: true,
    builder: (_) => const MobileChangePasscodeScreen(),
  );
}

// --- About and legal --------------------------------------------------------

/// Desktop About / Terms / Privacy at [path] ('/about', '/terms', '/privacy').
///
/// `hasWallet` decides between the sidebar shell and the bare pane;
/// `forceFullPane` is the onboarding entry. [AboutScreen] ignores both because
/// it always renders inside the shell.
Widget utilityDocumentScreenFixture({
  required String path,
  required bool hasWallet,
  required bool forceFullPane,
}) {
  final accountState = hasWallet
      ? accountsPreviewDesignState
      : const AccountState();
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _accountsPreviewBootstrap(accountState, initialLocation: path),
      ),
      accountProvider.overrideWith(
        () => _AccountsPreviewAccountNotifier(accountState),
      ),
      syncProvider.overrideWith(
        () => _AccountsPreviewSyncNotifier(accountState.activeAccountUuid),
      ),
      _accountsPreviewIdleMigrationOverride(),
    ],
    child: _SettingsSubScreenPreviewHarness(
      path: path,
      screen: _utilityDocumentScreen(path, forceFullPane: forceFullPane),
    ),
  );
}

Widget _utilityDocumentScreen(String path, {required bool forceFullPane}) {
  return switch (path) {
    '/terms' => TermsScreen(forceFullPane: forceFullPane),
    '/privacy' => PrivacyPolicyScreen(forceFullPane: forceFullPane),
    _ => AboutScreen(urlLauncher: _noopAboutUrl),
  };
}

/// Mobile About / Terms / Privacy; both screens need only a router to pop.
Widget utilityMobileDocumentScreenFixture({required String path}) {
  return _mobileSubScreenFixture(
    path: path,
    builder: (_) => switch (path) {
      '/terms' => const MobileLegalScreen(title: 'Terms of Use'),
      '/privacy' => const MobileLegalScreen(title: 'Privacy Policy'),
      _ => MobileAboutScreen(urlLauncher: _noopAboutUrl),
    },
  );
}

Future<void> _noopAboutUrl(String _) async {}

// --- Mobile sub-screen plumbing ---------------------------------------------

Widget _mobileSubScreenFixture({
  required String path,
  required Widget Function(SensitivePrivacyOverlayController controller)
  builder,
  BiometricUnlockState biometricState = BiometricUnlockState.initial,
  RpcEndpointConfig? rpcEndpointConfig,
  bool withParentRoute = false,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _accountsPreviewBootstrap(
          accountsPreviewDesignState,
          initialLocation: path,
          rpcEndpointConfig: rpcEndpointConfig,
        ),
      ),
      accountProvider.overrideWith(
        () => _AccountsPreviewAccountNotifier(accountsPreviewDesignState),
      ),
      syncProvider.overrideWith(
        () => _AccountsPreviewSyncNotifier(
          accountsPreviewDesignState.activeAccountUuid,
        ),
      ),
      biometricUnlockProvider.overrideWith(
        () => _SettingsPreviewBiometricNotifier(biometricState),
      ),
      appSecurityProvider.overrideWith(
        () => _SettingsPreviewAppSecurityNotifier(
          const AppSecurityState(isPasswordConfigured: true, isUnlocked: true),
        ),
      ),
      ...overrides,
    ],
    child: _MobileSubScreenPreviewHarness(
      path: path,
      builder: builder,
      withParentRoute: withParentRoute,
    ),
  );
}

/// Phone frame plus a detached router, so `context.pop` inside the previewed
/// screen lands here instead of on the gallery root.
class _MobileSubScreenPreviewHarness extends StatefulWidget {
  const _MobileSubScreenPreviewHarness({
    required this.path,
    required this.builder,
    this.withParentRoute = false,
  });

  final String path;
  final Widget Function(SensitivePrivacyOverlayController controller) builder;
  final bool withParentRoute;

  @override
  State<_MobileSubScreenPreviewHarness> createState() =>
      _MobileSubScreenPreviewHarnessState();
}

class _MobileSubScreenPreviewHarnessState
    extends State<_MobileSubScreenPreviewHarness> {
  // The plain controller keeps the preview off the window and lifecycle
  // listeners the production environment controller attaches.
  final _privacyController = SensitivePrivacyOverlayController();
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: widget.withParentRoute ? '/preview/screen' : widget.path,
      routes: [
        if (widget.withParentRoute)
          GoRoute(
            path: '/preview',
            builder: (_, _) =>
                const _AccountsPreviewPlaceholder(label: '/preview'),
            routes: [
              GoRoute(
                path: 'screen',
                builder: (_, _) => widget.builder(_privacyController),
              ),
            ],
          ),
        GoRoute(
          path: widget.path,
          builder: (_, _) => widget.builder(_privacyController),
        ),
        for (final path in const [
          '/settings',
          '/home',
          '/welcome',
          '/unlock',
          '/accounts',
        ])
          if (path != widget.path)
            GoRoute(
              path: path,
              builder: (_, _) => _AccountsPreviewPlaceholder(label: path),
            ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    _privacyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WbFrame(
      layout: WbLayout.mobile,
      child: Router.withConfig(config: _router),
    );
  }
}

class _SettingsPreviewEndpointLatencyNotifier
    extends RpcEndpointLatencyNotifier {
  _SettingsPreviewEndpointLatencyNotifier(this.initialState);

  final RpcEndpointLatencyState initialState;

  @override
  RpcEndpointLatencyState build() => initialState;

  @override
  Future<void> refresh(String networkName) async {}
}

// --- Custom endpoint panel -------------------------------------------------

/// Whether the wallet is on a shipped preset or a host the user typed.
enum SettingsCustomEndpointPreset { defaultPreset, custom }

/// The latency line `CurrentEndpointText` appends to the current endpoint.
enum SettingsCustomEndpointLatency { none, checking, measured, unavailable }

const settingsPreviewCustomEndpointUrl = 'https://lwd.example.invalid:9067';

RpcEndpointConfig settingsPreviewEndpointConfig(
  SettingsCustomEndpointPreset preset,
) {
  return preset == SettingsCustomEndpointPreset.custom
      ? const RpcEndpointConfig(
          networkName: 'main',
          lightwalletdUrl: settingsPreviewCustomEndpointUrl,
          presetId: kCustomRpcEndpointPresetId,
        )
      : defaultRpcEndpointConfig('main');
}

/// `CustomEndpointSettingsPanel` with its two provider inputs as axes.
///
/// The panel's own submitting / submit-error states are set inside its State
/// after a tap, so they stay out of reach of a static fixture.
Widget settingsCustomEndpointPanelFixture({
  required SettingsCustomEndpointPreset preset,
  required SettingsCustomEndpointLatency latency,
  required NetworkPrivacyState networkPrivacyState,
  required bool closable,
}) {
  final config = settingsPreviewEndpointConfig(preset);
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _accountsPreviewBootstrap(
          accountsPreviewDesignState,
          initialLocation: '/settings/endpoint',
          rpcEndpointConfig: config,
        ),
      ),
      networkPrivacyProvider.overrideWith(
        () => _SettingsPreviewNetworkPrivacyNotifier(networkPrivacyState),
      ),
      ..._endpointLatencyOverrides(
        _settingsPreviewLatencyState(config, latency),
      ),
    ],
    child: WbFrame(
      layout: WbLayout.desktop,
      child: Center(
        child: CustomEndpointSettingsPanel(
          onClose: closable ? _settingsPreviewNoop : null,
          restartSyncAfterUpdate: false,
        ),
      ),
    ),
  );
}

/// The message line `CustomEndpointSettingsPanel._customMessageText` prints
/// for one field value, derived from the same production normalizer so the
/// gallery can never show copy the app does not have.
String? settingsPreviewEndpointMessage(String text) {
  if (text.trim().isEmpty) return null;
  try {
    normalizeRpcEndpointUrl(text, allowDefaultPort: true);
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

/// `CustomEndpointForm` on its own props: the message line only the form
/// renders, which the panel cannot show because it seeds its field from an
/// already-normalized endpoint.
Widget settingsCustomEndpointFormFixture({required String text}) {
  return WbFrame(
    layout: WbLayout.desktop,
    child: Center(
      child: SizedBox(
        width: 352,
        child: _CustomEndpointFormPreview(
          // The controller text is seeded once per mount, so a knob change has
          // to remount the preview to be visible.
          key: ValueKey('settings_custom_endpoint_form_$text'),
          text: text,
          messageText: settingsPreviewEndpointMessage(text),
        ),
      ),
    ),
  );
}

/// `SettingsNewBadge`, the pill the Gift cards row carries until the feature
/// stops being new. One class with no form-factor branch, so there is nothing
/// for a layout axis to swap.
Widget settingsNewBadgeFixture() {
  return const WbFrame(
    layout: WbLayout.desktop,
    child: Center(child: SettingsNewBadge()),
  );
}

RpcEndpointLatencyState _settingsPreviewLatencyState(
  RpcEndpointConfig config,
  SettingsCustomEndpointLatency latency,
) {
  final sample = switch (latency) {
    SettingsCustomEndpointLatency.none => null,
    SettingsCustomEndpointLatency.checking =>
      const RpcEndpointLatencySample.checking(),
    SettingsCustomEndpointLatency.measured =>
      const RpcEndpointLatencySample.available(Duration(milliseconds: 42)),
    SettingsCustomEndpointLatency.unavailable =>
      const RpcEndpointLatencySample.unavailable(),
  };
  if (sample == null) return const RpcEndpointLatencyState();
  return const RpcEndpointLatencyState().copyWithSample(
    config.normalizedLightwalletdUrl,
    sample,
  );
}

class _CustomEndpointFormPreview extends StatefulWidget {
  const _CustomEndpointFormPreview({
    required this.text,
    required this.messageText,
    super.key,
  });

  final String text;
  final String? messageText;

  @override
  State<_CustomEndpointFormPreview> createState() =>
      _CustomEndpointFormPreviewState();
}

class _CustomEndpointFormPreviewState
    extends State<_CustomEndpointFormPreview> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomEndpointForm(
      controller: _controller,
      messageText: widget.messageText,
      onChanged: _settingsPreviewIgnoreText,
      onSubmit: _settingsPreviewAsyncNoop,
    );
  }
}

void _settingsPreviewNoop() {}

Future<void> _settingsPreviewAsyncNoop() async {}

void _settingsPreviewIgnoreText(String _) {}
