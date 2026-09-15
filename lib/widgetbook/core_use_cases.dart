// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/swap_feature_config.dart';
import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/layout/app_main_sidebar.dart';
import '../src/core/layout/app_pane_scroll_scaffold.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/layout/mobile/app_mobile_shell.dart';
import '../src/core/layout/mobile/app_mobile_tab_bar.dart';
import '../src/core/layout/mobile/mobile_top_nav.dart';
import '../src/core/layout/mobile/mobile_top_nav_account.dart';
import '../src/core/profile_pictures.dart';
import '../src/core/storage/linux_keyring_coordinator.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_button.dart';
import '../src/core/widgets/app_decorative_divider.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/app_modal_card.dart';
import '../src/core/widgets/app_pane_modal_overlay.dart';
import '../src/core/widgets/app_profile_picture.dart';
import '../src/core/widgets/app_profile_picture_picker_modal.dart';
import '../src/core/widgets/app_tooltip.dart';
import '../src/core/widgets/linux_keyring_gate.dart';
import '../src/core/widgets/mobile/mobile_transaction_progress_screen.dart';
import '../src/core/widgets/mobile/mobile_tx_fee_info_sheet.dart';
import '../src/core/widgets/mobile/sync_keep_awake_privacy_lock_host.dart';
import '../src/core/widgets/mobile/unsupported_sheet.dart';
import '../src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import '../src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/app_security_provider.dart';
import '../src/providers/biometric_unlock_provider.dart';
import '../src/providers/network_privacy_provider.dart';
import '../src/providers/privacy_mode_provider.dart';
import '../src/providers/sync_display_progress_provider.dart';
import '../src/providers/sync_keep_awake_provider.dart';
import '../src/providers/sync_failure.dart';
import '../src/providers/sync_provider.dart';
import '../src/rust/api/sync.dart' as rust_sync;
import '../src/services/biometric_unlock.dart';
import 'support/wb_layout.dart';
import 'support/wb_platform_override.dart';

// Preview the mobile fixtures here with the mobile token lane for true metrics:
// fvm flutter run -t lib/widgetbook.dart --dart-define=VIZOR_FORM_FACTOR=mobile

const String _coreSoftwareAccountUuid = 'core-preview-software';
const String _coreKeystoneAccountUuid = 'core-preview-keystone';

// --- Shared preview state ---------------------------------------------------

/// Which account the provider-bound core surfaces present.
enum CoreAccountCase { none, software, keystone }

/// Sync status the shared fakes reproduce, matching `SyncStatusLabel`'s three
/// kinds.
enum CoreSyncCase { synced, syncing, failed }

const List<AccountInfo> _coreAccounts = [
  AccountInfo(
    uuid: _coreSoftwareAccountUuid,
    name: 'Account 1',
    order: 0,
    isSeedAnchor: true,
    profilePictureId: 'pfp-01',
  ),
  AccountInfo(
    uuid: _coreKeystoneAccountUuid,
    name: 'Keystone 1',
    order: 1,
    isHardware: true,
    profilePictureId: 'pfp-04',
  ),
];

AccountState coreAccountState(CoreAccountCase account) {
  return switch (account) {
    CoreAccountCase.none => const AccountState(),
    CoreAccountCase.software => const AccountState(
      accounts: _coreAccounts,
      activeAccountUuid: _coreSoftwareAccountUuid,
    ),
    CoreAccountCase.keystone => const AccountState(
      accounts: _coreAccounts,
      activeAccountUuid: _coreKeystoneAccountUuid,
    ),
  };
}

SyncState coreSyncState(CoreSyncCase sync, {String? accountUuid}) {
  final balances = {
    'total': BigInt.from(14223000000),
    'orchard': BigInt.from(9223000000),
    'ironwood': BigInt.from(5000000000),
  };
  return switch (sync) {
    CoreSyncCase.synced => SyncState(
      accountUuid: accountUuid,
      hasAccountScopedData: accountUuid != null,
      isSyncComplete: true,
      percentage: 1,
      scannedHeight: 3000000,
      chainTipHeight: 3000000,
      orchardBalance: balances['orchard'],
      ironwoodBalance: balances['ironwood'],
      displayOrchardBalance: balances['orchard'],
      displayIronwoodBalance: balances['ironwood'],
      totalBalance: balances['total'],
      displayTotalBalance: balances['total'],
    ),
    CoreSyncCase.syncing => SyncState(
      accountUuid: accountUuid,
      hasAccountScopedData: accountUuid != null,
      isSyncing: true,
      percentage: 0.34,
      scannedHeight: 2800000,
      chainTipHeight: 3000000,
      orchardBalance: balances['orchard'],
      ironwoodBalance: balances['ironwood'],
      displayOrchardBalance: balances['orchard'],
      displayIronwoodBalance: balances['ironwood'],
      totalBalance: balances['total'],
      displayTotalBalance: balances['total'],
    ),
    CoreSyncCase.failed => SyncState(
      accountUuid: accountUuid,
      hasAccountScopedData: accountUuid != null,
      percentage: 0.34,
      failure: const SyncFailure(
        kind: SyncFailureKind.network,
        rawMessage: 'preview',
        userMessage: 'Network error',
        showSettingsAction: false,
      ),
      orchardBalance: balances['orchard'],
      ironwoodBalance: balances['ironwood'],
      displayOrchardBalance: balances['orchard'],
      displayIronwoodBalance: balances['ironwood'],
      totalBalance: balances['total'],
      displayTotalBalance: balances['total'],
    ),
  };
}

/// Deterministic stand-ins for the four providers every provider-bound core
/// surface reads. Re-declared here because the `screen_use_cases.dart` copies
/// are private to that file.
class CorePreviewAccountNotifier extends AccountNotifier {
  CorePreviewAccountNotifier(this.initialState);

  final AccountState initialState;

  @override
  FutureOr<AccountState> build() => initialState;

  @override
  Future<void> switchAccount(String uuid) async {
    final previous = state.value ?? initialState;
    state = AsyncData(previous.copyWith(activeAccountUuid: uuid));
  }
}

class CorePreviewSyncNotifier extends SyncNotifier {
  CorePreviewSyncNotifier(this.initialState);

  final SyncState initialState;

  @override
  Future<SyncState> build() async => initialState;

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

class CorePreviewNetworkPrivacyNotifier extends NetworkPrivacyNotifier {
  CorePreviewNetworkPrivacyNotifier(this.initialState);

  final NetworkPrivacyState initialState;

  @override
  NetworkPrivacyState build() => initialState;

  @override
  Future<void> setTorEnabled(bool enabled) async {}
}

class CorePreviewPrivacyModeNotifier extends PrivacyModeNotifier {
  CorePreviewPrivacyModeNotifier(this.initialEnabled);

  final bool initialEnabled;

  @override
  bool build() => initialEnabled;

  @override
  Future<void> set(bool enabled) async {
    state = enabled;
  }
}

/// Pins the interpolated sync ring/percentage so no 20 ms UI timer runs and
/// the label is the same on every frame.
class CorePreviewSyncDisplayPercentageNotifier
    extends SyncDisplayPercentageNotifier {
  CorePreviewSyncDisplayPercentageNotifier(this.value);

  final double value;

  @override
  double build() => value;
}

class CorePreviewSecurityNotifier extends AppSecurityNotifier {
  @override
  Future<bool> confirmPassword(String password) async => false;
}

class CorePreviewBiometricUnlockNotifier extends BiometricUnlockNotifier {
  CorePreviewBiometricUnlockNotifier(this.initialState);

  final BiometricUnlockState initialState;

  @override
  Future<BiometricUnlockState> build() async => initialState;

  @override
  Future<String?> readPasscode({required String reason}) async => null;
}

class CorePreviewMigrationCoordinator extends IronwoodMigrationCoordinator {
  CorePreviewMigrationCoordinator({this.accountUuid, this.status});

  final String? accountUuid;
  final rust_sync.MigrationStatus? status;

  @override
  IronwoodMigrationCoordinatorState build() {
    final uuid = accountUuid;
    final value = status;
    return IronwoodMigrationCoordinatorState(
      statuses: uuid == null || value == null ? const {} : {uuid: value},
    );
  }
}

rust_sync.MigrationStatus _coreMigrationStatus(String phase) {
  return rust_sync.MigrationStatus(
    phase: phase,
    activeRunId: 'core-preview-run',
    targetValuesZatoshi: frb.Uint64List(0),
    preparedNoteCount: 0,
    denominationConfirmationCount: 0,
    denominationConfirmationTarget: 0,
    denominationSplitCompletedCount: 0,
    denominationSplitTotalCount: 0,
    pendingTxCount: 0,
    broadcastedTxCount: 0,
    confirmedTxCount: 0,
    totalCount: 0,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 0,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    scheduledBroadcasts: const [],
    parts: const [],
  );
}

/// Phone box on `background.window`, with the height the screen's own
/// short-screen branch reads from `MediaQuery.sizeOf`.
Widget _corePhoneFrame(
  BuildContext context, {
  required double height,
  required Widget child,
  // Defaults reproduce the status-bar-only phone every other core fixture
  // gets; the mobile-modal cases feed their own keyboard / nav-bar insets.
  EdgeInsets viewPadding = const EdgeInsets.only(top: 55),
  EdgeInsets viewInsets = EdgeInsets.zero,
}) {
  final size = Size(393, height);
  return Center(
    child: WbScaleDownBox(
      size: size,
      child: SizedBox.fromSize(
        size: size,
        child: ColoredBox(
          color: context.colors.background.window,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: size,
              viewPadding: viewPadding,
              padding: EdgeInsets.zero,
              viewInsets: viewInsets,
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}

// --- Sync keep-awake privacy lock -------------------------------------------

/// Which unlock glyph the lock screen's button carries.
enum CoreBiometricCase { faceId, touchId, fingerprint, passcodeOnly }

BiometricUnlockState coreBiometricState(CoreBiometricCase biometric) {
  final kind = switch (biometric) {
    CoreBiometricCase.faceId => BiometricKind.face,
    CoreBiometricCase.touchId => BiometricKind.touchId,
    CoreBiometricCase.fingerprint => BiometricKind.fingerprint,
    CoreBiometricCase.passcodeOnly => BiometricKind.none,
  };
  return BiometricUnlockState(
    availability: BiometricAvailability(
      supported: biometric != CoreBiometricCase.passcodeOnly,
      enrolled: biometric != CoreBiometricCase.passcodeOnly,
      kind: kind,
    ),
    enabled: biometric != CoreBiometricCase.passcodeOnly,
  );
}

/// The keep-awake privacy lock screen driven by its real `mode` prop.
///
/// The passcode confirm sub-screen is private `State` reached by tapping
/// 'Unlock Vizor' with the passcode-only option; the fake security notifier
/// always answers "wrong passcode" so nothing touches storage.
Widget syncKeepAwakeLockFixture(
  BuildContext context, {
  required SyncKeepAwakePrivacyLockMode mode,
  required CoreBiometricCase biometric,
  required double progress,
  required double screenHeight,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      appSecurityProvider.overrideWith(CorePreviewSecurityNotifier.new),
      biometricUnlockProvider.overrideWith(
        () => CorePreviewBiometricUnlockNotifier(coreBiometricState(biometric)),
      ),
      syncDisplayPercentageProvider.overrideWith(
        () => CorePreviewSyncDisplayPercentageNotifier(progress),
      ),
    ],
    child: _corePhoneFrame(
      context,
      height: screenHeight,
      child: SyncKeepAwakePrivacyLockScreen(mode: mode),
    ),
  );
}

// --- Mobile transaction progress --------------------------------------------

/// How many action buttons the progress screen offers below its body copy.
enum CoreTransactionProgressActions { none, primaryOnly, primaryAndSecondary }

/// The shared mobile transaction-progress page, fully prop-driven.
Widget mobileTransactionProgressFixture(
  BuildContext context, {
  required MobileTransactionProgressPhase phase,
  required CoreTransactionProgressActions actions,
  required bool canPop,
}) {
  final showPrimary = actions != CoreTransactionProgressActions.none;
  final showSecondary =
      actions == CoreTransactionProgressActions.primaryAndSecondary;
  final (title, body) = switch (phase) {
    MobileTransactionProgressPhase.inProgress => (
      'Sending',
      'Your transaction is being submitted to the network.',
    ),
    MobileTransactionProgressPhase.pending => (
      'Pending',
      'Waiting for the network to confirm your transaction.',
    ),
    MobileTransactionProgressPhase.succeeded => (
      'Sent',
      'Your transaction was broadcast successfully.',
    ),
    MobileTransactionProgressPhase.failed => (
      'Send failed',
      'Your funds were not sent. Try again.',
    ),
  };

  return _corePhoneFrame(
    context,
    height: 852,
    child: MobileTransactionProgressScreen(
      phase: phase,
      title: title,
      body: body,
      canPop: canPop,
      onPopBlocked: () {},
      primaryActionLabel: showPrimary ? 'Done' : null,
      onPrimaryAction: showPrimary ? () {} : null,
      secondaryActionLabel: showSecondary ? 'View details' : null,
      onSecondaryAction: showSecondary ? () {} : null,
    ),
  );
}

/// The status badge on its own: the circle, glyph, success ripple and
/// failure shake the progress page composes.
Widget mobileTransactionProgressBadgeFixture(
  BuildContext context, {
  required MobileTransactionProgressPhase phase,
  required bool terminalAnimationEnabled,
  required bool tintedInProgressColors,
}) {
  return ColoredBox(
    color: context.colors.background.window,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: MobileTransactionProgressBadge(
          phase: phase,
          terminalAnimationEnabled: terminalAnimationEnabled,
          inProgressCircleColor: tintedInProgressColors
              ? context.colors.background.inverse
              : null,
          inProgressIconColor: tintedInProgressColors
              ? context.colors.icon.warning
              : null,
        ),
      ),
    ),
  );
}

// --- Linux keyring ----------------------------------------------------------

/// Blocking states the keyring gate renders. `hasPendingMutation` is internal
/// to the coordinator and cannot be driven from outside, so the Cancel knob
/// covers only the `canCancel` + `requestId` half of that condition.
enum CoreLinuxKeyringCase {
  retrying,
  keyringLocked,
  serviceUnavailable,
  storageCorrupt,
  outcomeUnknown,
}

LinuxKeyringPhase _coreLinuxKeyringPhase(CoreLinuxKeyringCase state) {
  return switch (state) {
    CoreLinuxKeyringCase.retrying => LinuxKeyringPhase.retrying,
    CoreLinuxKeyringCase.keyringLocked => LinuxKeyringPhase.keyringLocked,
    CoreLinuxKeyringCase.serviceUnavailable =>
      LinuxKeyringPhase.serviceUnavailable,
    CoreLinuxKeyringCase.storageCorrupt => LinuxKeyringPhase.storageCorrupt,
    CoreLinuxKeyringCase.outcomeUnknown => LinuxKeyringPhase.outcomeUnknown,
  };
}

/// [LinuxKeyringGate] over a static pane, driven by an injected coordinator.
Widget linuxKeyringGateFixture(
  BuildContext context, {
  required CoreLinuxKeyringCase state,
  required bool canCancel,
}) {
  return _coreDesktopWindow(
    context,
    child: _LinuxKeyringGatePreview(state: state, canCancel: canCancel),
  );
}

class _LinuxKeyringGatePreview extends StatefulWidget {
  const _LinuxKeyringGatePreview({
    required this.state,
    required this.canCancel,
  });

  final CoreLinuxKeyringCase state;
  final bool canCancel;

  @override
  State<_LinuxKeyringGatePreview> createState() =>
      _LinuxKeyringGatePreviewState();
}

class _LinuxKeyringGatePreviewState extends State<_LinuxKeyringGatePreview> {
  // Dev-only preview: the coordinator exposes no other way to stage a phase.
  // ignore: invalid_use_of_visible_for_testing_member
  final _coordinator = LinuxKeyringCoordinator.testing();

  @override
  void initState() {
    super.initState();
    _applyState();
  }

  @override
  void didUpdateWidget(_LinuxKeyringGatePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state ||
        oldWidget.canCancel != widget.canCancel) {
      _applyState();
    }
  }

  void _applyState() {
    // ignore: invalid_use_of_visible_for_testing_member
    _coordinator.setStateForTesting(
      LinuxKeyringState(
        phase: _coreLinuxKeyringPhase(widget.state),
        canCancel: widget.canCancel,
        requestId: widget.canCancel ? 1 : null,
      ),
    );
  }

  @override
  void dispose() {
    _coordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LinuxKeyringGate(
      coordinator: _coordinator,
      child: _corePanePlaceholder(context, 'Wallet content'),
    );
  }
}

/// How the startup host's injected `loadApp` resolves.
enum CoreLinuxStartupCase { pending, loaded, failed }

/// [LinuxKeyringStartupHost] with a deterministic bootstrap future. The host
/// builds its own `MaterialApp` + `AppTheme`, so it gets no extra wrapper.
Widget linuxKeyringStartupFixture(
  BuildContext context, {
  required CoreLinuxStartupCase bootstrap,
}) {
  return _coreDesktopWindow(
    context,
    child: _LinuxKeyringStartupPreview(bootstrap: bootstrap),
  );
}

class _LinuxKeyringStartupPreview extends StatelessWidget {
  const _LinuxKeyringStartupPreview({required this.bootstrap});

  final CoreLinuxStartupCase bootstrap;

  @override
  Widget build(BuildContext context) {
    return LinuxKeyringStartupHost(
      // A new key per option so the host re-runs its one-shot bootstrap.
      key: ValueKey(bootstrap),
      loadApp: switch (bootstrap) {
        CoreLinuxStartupCase.pending => () => Completer<Widget>().future,
        CoreLinuxStartupCase.loaded => () async => _corePanePlaceholder(
          context,
          'Vizor',
        ),
        CoreLinuxStartupCase.failed => () async => throw StateError(
          'preview bootstrap failure',
        ),
      },
    );
  }
}

// --- Mobile top nav account -------------------------------------------------

/// [MobileTopNavAccount] bound to the shared account / sync / privacy fakes.
Widget mobileTopNavAccountFixture(
  BuildContext context, {
  required CoreAccountCase account,
  required CoreSyncCase sync,
  required bool showSyncStatus,
}) {
  final accountState = coreAccountState(account);
  return _coreAccountScope(
    accountState: accountState,
    sync: sync,
    privacyMode: false,
    child: Center(
      child: SizedBox(
        width: 393,
        child: ColoredBox(
          color: context.colors.background.window,
          child: MobileTopNavAccount(
            showSyncStatus: showSyncStatus,
            onAccountTap: () {},
          ),
        ),
      ),
    ),
  );
}

/// The account / sync / privacy scope every provider-bound core surface needs.
/// `riverpod` does not export `Override`, so callers that need extra overrides
/// nest a second [ProviderScope] inside this one rather than appending to a
/// typed list.
Widget _coreAccountScope({
  required AccountState accountState,
  required CoreSyncCase sync,
  required bool privacyMode,
  required Widget child,
}) {
  final progress = switch (sync) {
    CoreSyncCase.synced => 1.0,
    CoreSyncCase.syncing => 0.34,
    CoreSyncCase.failed => 0.34,
  };
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      accountProvider.overrideWith(
        () => CorePreviewAccountNotifier(accountState),
      ),
      syncProvider.overrideWith(
        () => CorePreviewSyncNotifier(
          coreSyncState(sync, accountUuid: accountState.activeAccountUuid),
        ),
      ),
      networkPrivacyProvider.overrideWith(
        () =>
            CorePreviewNetworkPrivacyNotifier(const NetworkPrivacyState.off()),
      ),
      privacyModeProvider.overrideWith(
        () => CorePreviewPrivacyModeNotifier(privacyMode),
      ),
      syncDisplayPercentageProvider.overrideWith(
        () => CorePreviewSyncDisplayPercentageNotifier(progress),
      ),
    ],
    child: child,
  );
}

// --- Desktop main sidebar ---------------------------------------------------

/// Route the sidebar highlights; the harness router starts on it and
/// `GoRouterState.matchedLocation` is what the sidebar actually reads.
enum CoreSidebarRoute { home, activity, settings }

/// Which Ironwood block the sidebar's home slot renders.
enum CoreSidebarMigrationCase { none, splitRows, needsInput }

String coreSidebarRoutePath(CoreSidebarRoute route) {
  return switch (route) {
    CoreSidebarRoute.home => '/home',
    CoreSidebarRoute.activity => '/activity',
    CoreSidebarRoute.settings => '/settings',
  };
}

/// The real [AppMainSidebar] inside a desktop shell, a `GoRouter` whose
/// initial location drives the active row, and the provider fakes it reads.
Widget mainSidebarFixture(
  BuildContext context, {
  required CoreAccountCase account,
  required CoreSidebarRoute route,
  required CoreSyncCase sync,
  required bool privacyMode,
  required bool swapEnabled,
  required CoreSidebarMigrationCase migration,
  required TargetPlatform platform,
}) {
  final accountState = coreAccountState(account);
  final uuid = accountState.activeAccountUuid;
  final migrationStatus = switch (migration) {
    CoreSidebarMigrationCase.none => null,
    CoreSidebarMigrationCase.splitRows => _coreMigrationStatus(
      kIronwoodMigrationWaitingConfirmationsPhase,
    ),
    CoreSidebarMigrationCase.needsInput => _coreMigrationStatus(
      kIronwoodMigrationReadyToMigratePhase,
    ),
  };

  // Desktop-only: `_SidebarAccountHeader` overflows its 36px row under the
  // mobile type tokens, so the mobile binary cannot render it correctly.
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: _coreAccountScope(
      accountState: accountState,
      sync: sync,
      privacyMode: privacyMode,
      child: ProviderScope(
        overrides: [
          swapFeatureEnabledProvider.overrideWithValue(swapEnabled),
          ironwoodPostMigrationStateProvider.overrideWith(
            (ref) => const IronwoodPostMigrationState.inactive(),
          ),
          ironwoodHomeMigrationPresentationProvider.overrideWithValue(
            const IronwoodHomeMigrationCtaState.hidden(),
          ),
          ironwoodMigrationCoordinatorProvider.overrideWith(
            () => CorePreviewMigrationCoordinator(
              accountUuid: uuid,
              status: migrationStatus,
            ),
          ),
        ],
        child: WbPlatformOverride(
          platform: platform,
          child: _coreDesktopWindow(
            context,
            child: _CoreSidebarRouterHarness(route: route),
          ),
        ),
      ),
    ),
  );
}

class _CoreSidebarRouterHarness extends StatefulWidget {
  const _CoreSidebarRouterHarness({required this.route});

  final CoreSidebarRoute route;

  @override
  State<_CoreSidebarRouterHarness> createState() =>
      _CoreSidebarRouterHarnessState();
}

class _CoreSidebarRouterHarnessState extends State<_CoreSidebarRouterHarness> {
  late GoRouter _router = _buildRouter();

  // The sidebar reads `GoRouterState.of(context).matchedLocation`, so a
  // detached `InheritedGoRouter` is not enough — it needs a real route match.
  GoRouter _buildRouter() {
    return GoRouter(
      initialLocation: coreSidebarRoutePath(widget.route),
      routes: [
        for (final path in const [
          '/home',
          '/activity',
          '/settings',
          '/swap',
          '/pay',
          '/voting',
          '/accounts',
          '/add-account',
          '/migration/private/status',
        ])
          GoRoute(
            path: path,
            builder: (context, state) => AppDesktopShell(
              sidebar: const AppMainSidebar(),
              pane: _corePanePlaceholder(context, state.matchedLocation),
            ),
          ),
      ],
    );
  }

  @override
  void didUpdateWidget(_CoreSidebarRouterHarness oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route != widget.route) {
      _router.dispose();
      _router = _buildRouter();
    }
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
    );
  }
}

// --- Shared desktop frame ---------------------------------------------------

Widget _coreDesktopWindow(BuildContext context, {required Widget child}) {
  return Center(
    child: SizedBox(
      width: kWbDesktopWindowWidth,
      height: kWbDesktopWindowHeight,
      child: ColoredBox(
        color: context.colors.macosUtility.window,
        child: child,
      ),
    ),
  );
}

// --- Mobile sheets ----------------------------------------------------------

/// Which copy the network-fee sheet carries.
enum CoreTxFeeSheetCopy { zip317, custom }

/// Which gap the unsupported sheet names. `showUnsupportedSheet` has no call
/// sites in `lib/src` yet, so the two custom options use the features its own
/// doc comment names.
enum CoreUnsupportedSheetCopy { inProgress, keystoneConnect, biometricUnlock }

/// Alternative copy proving `title` / `description` are real parameters.
const String kCoreTxFeeCustomTitle = 'Estimated network fee';
const String kCoreTxFeeCustomDescription =
    'This send pays 0.0001 ZEC to the Zcash network. Vizor keeps none of it.';

const String kCoreUnsupportedKeystoneMessage =
    'Connecting a Keystone device is still in progress on mobile.';
const String kCoreUnsupportedBiometricMessage =
    'Biometric unlock is still in progress on mobile.';

/// The real ZIP-317 fee sheet, presented through `showAppMobileSheet`.
Widget mobileTxFeeInfoSheetFixture(
  BuildContext context, {
  required CoreTxFeeSheetCopy copy,
}) {
  return _coreSheetPreview(
    context,
    optionKey: 'tx-fee|${copy.name}',
    label: 'Open fee sheet',
    present: (sheetContext) => switch (copy) {
      CoreTxFeeSheetCopy.zip317 => showMobileTxFeeInfoSheet(sheetContext),
      CoreTxFeeSheetCopy.custom => showMobileTxFeeInfoSheet(
        sheetContext,
        title: kCoreTxFeeCustomTitle,
        description: kCoreTxFeeCustomDescription,
      ),
    },
  );
}

/// The real "Not available yet" sheet, presented through `showAppMobileSheet`.
Widget unsupportedSheetFixture(
  BuildContext context, {
  required CoreUnsupportedSheetCopy copy,
}) {
  return _coreSheetPreview(
    context,
    optionKey: 'unsupported|${copy.name}',
    label: 'Open sheet',
    present: (sheetContext) => showUnsupportedSheet(
      sheetContext,
      message: switch (copy) {
        CoreUnsupportedSheetCopy.inProgress => null,
        CoreUnsupportedSheetCopy.keystoneConnect =>
          kCoreUnsupportedKeystoneMessage,
        CoreUnsupportedSheetCopy.biometricUnlock =>
          kCoreUnsupportedBiometricMessage,
      },
    ),
  );
}

/// Phone frame that auto-presents a real mobile sheet and keeps a button to
/// reopen it.
///
/// `showAppMobileSheet` pushes on the root navigator, so the card spans the
/// widgetbook canvas rather than this 393px frame — the same presentation
/// `buildMobileSheetUseCase` already has.
Widget _coreSheetPreview(
  BuildContext context, {
  required String optionKey,
  required String label,
  required Future<void> Function(BuildContext context) present,
}) {
  return _corePhoneFrame(
    context,
    height: 852,
    child: _CoreSheetPreview(
      optionKey: optionKey,
      label: label,
      present: present,
    ),
  );
}

class _CoreSheetPreview extends StatefulWidget {
  const _CoreSheetPreview({
    required this.optionKey,
    required this.label,
    required this.present,
  });

  final String optionKey;
  final String label;
  final Future<void> Function(BuildContext context) present;

  @override
  State<_CoreSheetPreview> createState() => _CoreSheetPreviewState();
}

class _CoreSheetPreviewState extends State<_CoreSheetPreview> {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _schedulePresent();
  }

  @override
  void didUpdateWidget(_CoreSheetPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.optionKey != widget.optionKey) _schedulePresent();
  }

  void _schedulePresent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _present();
    });
  }

  void _present() {
    if (!mounted) return;
    // `maybePop`, never `pop`: the open sheet is the only route this preview
    // may unwind, and the widgetbook root must survive an empty history.
    if (_open) Navigator.of(context, rootNavigator: true).maybePop();
    _open = true;
    widget.present(context).whenComplete(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Center(
        child: AppButton(
          variant: AppButtonVariant.secondary,
          onPressed: _present,
          child: Text(widget.label),
        ),
      ),
    );
  }
}

// --- Tooltip ----------------------------------------------------------------

/// How the bubble opens: the hover option is forced visible so the gallery
/// shows the bubble without a pointer.
enum CoreTooltipTrigger { hover, tap }

/// The plain-message option's copy.
const String kCoreTooltipPlainMessage =
    'Only you can see this balance. Vizor never sends it anywhere.';

/// Flattened text of the rich-span option, for finders.
const String kCoreTooltipRichMessage = 'Requested by Alice · 12 payments';

/// Label on the anchor; kept distinct from both messages so a finder for the
/// bubble cannot match the anchor.
const String kCoreTooltipAnchorLabel = 'Fee details';

/// One [AppTooltip] centred on a fixed pane, so `preferBelow` has room on
/// both sides of the anchor.
Widget appTooltipFixture(
  BuildContext context, {
  required bool rich,
  required bool preferBelow,
  required CoreTooltipTrigger trigger,
}) {
  return Center(
    child: SizedBox(
      width: 520,
      height: 320,
      child: ColoredBox(
        color: context.colors.background.base,
        child: _CoreTooltipPreview(
          rich: rich,
          preferBelow: preferBelow,
          trigger: trigger,
        ),
      ),
    ),
  );
}

class _CoreTooltipPreview extends StatefulWidget {
  const _CoreTooltipPreview({
    required this.rich,
    required this.preferBelow,
    required this.trigger,
  });

  final bool rich;
  final bool preferBelow;
  final CoreTooltipTrigger trigger;

  @override
  State<_CoreTooltipPreview> createState() => _CoreTooltipPreviewState();
}

class _CoreTooltipPreviewState extends State<_CoreTooltipPreview> {
  final GlobalKey _anchorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scheduleShow();
  }

  @override
  void didUpdateWidget(_CoreTooltipPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rich != widget.rich ||
        oldWidget.preferBelow != widget.preferBelow ||
        oldWidget.trigger != widget.trigger) {
      _scheduleShow();
    }
  }

  void _scheduleShow() {
    if (widget.trigger != CoreTooltipTrigger.hover) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureVisible();
    });
  }

  // `AppTooltip` exposes no key for the `Tooltip` it wraps, so the bubble is
  // forced open through the inner `TooltipState` found under the anchor.
  void _ensureVisible() {
    final anchor = _anchorKey.currentContext;
    if (anchor == null) return;
    TooltipState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is TooltipState) {
        found = element.state as TooltipState;
        return;
      }
      element.visitChildElements(visit);
    }

    anchor.visitChildElements(visit);
    found?.ensureTooltipVisible();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final richMessage = TextSpan(
      children: [
        const TextSpan(text: 'Requested by '),
        const TextSpan(
          text: 'Alice',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const TextSpan(text: ' · 12 payments'),
      ],
    );

    return Center(
      child: AppTooltip(
        key: _anchorKey,
        message: widget.rich ? null : kCoreTooltipPlainMessage,
        richMessage: widget.rich ? richMessage : null,
        preferBelow: widget.preferBelow,
        tapToShow: widget.trigger == CoreTooltipTrigger.tap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: colors.surface.card,
            borderRadius: BorderRadius.circular(AppRadii.full),
            border: Border.all(color: colors.border.subtle),
          ),
          child: Text(
            kCoreTooltipAnchorLabel,
            style: AppTypography.labelSmall.copyWith(color: colors.text.accent),
          ),
        ),
      ),
    );
  }
}

Widget _corePanePlaceholder(BuildContext context, String label) {
  return AppDesktopPane(
    padding: EdgeInsets.zero,
    child: Center(
      child: Text(
        label,
        style: AppTypography.bodyMedium.copyWith(
          color: context.colors.text.secondary,
        ),
      ),
    ),
  );
}

// --- Desktop modal card -----------------------------------------------------

/// Card body: 'Scrolling' is a fixed-height list inside the card, which is how
/// the taller pickers keep the card from growing past the pane.
enum CoreModalCardBody { short, scrolling }

/// The wider card the asset / network pickers ask for.
const double kCoreModalCardWideWidth = 420;

const String kCoreModalCardTitle = 'Remove this account?';
const String kCoreModalCardBodyText =
    'The account is removed from this device. You can import it again with '
    'its recovery phrase.';

/// Row label prefix of the scrolling body, so a finder can reach one row.
const String kCoreModalCardRowPrefix = 'Account ';

/// [AppModalCard] on a plain desktop pane — never over a live composer.
Widget appModalCardFixture(
  BuildContext context, {
  required bool highlight,
  required double width,
  required CoreModalCardBody body,
  required double bottomPadding,
}) {
  final colors = context.colors;
  return WbFrame(
    layout: WbLayout.desktop,
    child: Center(
      child: AppModalCard(
        width: width,
        highlight: highlight,
        bottomPadding: bottomPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              kCoreModalCardTitle,
              textAlign: TextAlign.center,
              style: AppTypography.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (body == CoreModalCardBody.short)
              Text(
                kCoreModalCardBodyText,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              )
            else
              SizedBox(
                height: 240,
                child: ListView.builder(
                  itemCount: 12,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Text(
                      '$kCoreModalCardRowPrefix${index + 1}',
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.primary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// [AppModalActions] inside the card it always sits at the bottom of.
Widget appModalActionsFixture(
  BuildContext context, {
  required AppButtonVariant actionVariant,
  required bool actionEnabled,
  required bool cancelEnabled,
  required bool actionLeadingIcon,
}) {
  final colors = context.colors;
  return WbFrame(
    layout: WbLayout.desktop,
    child: Center(
      child: AppModalCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              kCoreModalCardTitle,
              textAlign: TextAlign.center,
              style: AppTypography.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppModalActions(
              // A disabled button is a null callback, exactly how the
              // production modals express "nothing to confirm yet".
              onCancel: cancelEnabled ? () {} : null,
              actionLabel: 'Confirm',
              onAction: actionEnabled ? () {} : null,
              actionVariant: actionVariant,
              actionLeading: actionLeadingIcon
                  ? const AppIcon(AppIcons.trash, size: AppIconSize.medium)
                  : null,
            ),
          ],
        ),
      ),
    ),
  );
}

// --- Pane modal overlay -----------------------------------------------------

/// Where the overlay parks its card.
enum CorePaneModalAlignment { center, top, bottom }

/// [AppPaneModalOverlay] over a static pane list.
Widget appPaneModalOverlayFixture(
  BuildContext context, {
  required CorePaneModalAlignment alignment,
  required bool customScrim,
  required bool largeRadius,
}) {
  final colors = context.colors;
  return WbFrame(
    layout: WbLayout.desktop,
    child: Stack(
      fit: StackFit.expand,
      children: [
        _coreModalBackdrop(context),
        AppPaneModalOverlay(
          alignment: switch (alignment) {
            CorePaneModalAlignment.center => Alignment.center,
            CorePaneModalAlignment.top => Alignment.topCenter,
            CorePaneModalAlignment.bottom => Alignment.bottomCenter,
          },
          scrimColor: customScrim ? colors.background.brandCrimsonAlpha : null,
          borderRadius: largeRadius
              ? const BorderRadius.all(Radius.circular(AppRadii.xLarge))
              : AppPaneModalOverlay.defaultBorderRadius,
          // Static preview: dismissing would leave the case empty, so the
          // scrim tap and Escape are no-ops here.
          onDismiss: () {},
          child: AppModalCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  kCoreModalCardTitle,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppModalActions(
                  onCancel: () {},
                  actionLabel: 'Confirm',
                  onAction: () {},
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// Static pane content behind a modal, so the scrim has something to dim.
Widget _coreModalBackdrop(BuildContext context) {
  final colors = context.colors;
  return Padding(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < 8; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s),
            child: Text(
              '$kCoreModalCardRowPrefix${index + 1}',
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
      ],
    ),
  );
}

// --- Profile picture picker -------------------------------------------------

/// How the injected `onUpdate` resolves; the reviewer reaches the in-flight
/// and error states by picking another avatar and pressing Update.
enum CoreProfilePickerOutcome { succeeds, inFlight, fails }

const String kCoreProfilePickerTitle = 'Select profile picture';

/// The non-default "current picture" option.
const String kCoreProfilePickerAlternateId = 'pfp-08';

/// Copy the modal shows when `onUpdate` throws.
const String kCoreProfilePickerError = "Couldn't update profile picture.";

/// [AppProfilePicturePickerModal] on a plain desktop pane.
Widget appProfilePicturePickerFixture(
  BuildContext context, {
  required CoreProfilePickerOutcome outcome,
  required bool alternateCurrentPicture,
  required AppProfilePictureSize optionSize,
}) {
  return WbFrame(
    layout: WbLayout.desktop,
    child: Center(
      child: AppProfilePicturePickerModal(
        // A fresh key per option so the modal's private selection and submit
        // state reset instead of carrying over from the previous knob value.
        key: ValueKey('$outcome|$alternateCurrentPicture|$optionSize'),
        title: kCoreProfilePickerTitle,
        currentProfilePictureId: alternateCurrentPicture
            ? kCoreProfilePickerAlternateId
            : kDefaultProfilePictureId,
        optionSize: optionSize,
        onCancel: () {},
        onUpdate: (_) => switch (outcome) {
          CoreProfilePickerOutcome.succeeds => Future<void>.value(),
          CoreProfilePickerOutcome.inFlight => Completer<void>().future,
          CoreProfilePickerOutcome.fails => Future<void>.error(
            StateError('preview update failure'),
          ),
        },
      ),
    ),
  );
}

// --- Mobile modal -----------------------------------------------------------

/// What the scaffold's title row shows.
enum CoreMobileModalTitle { shown, hidden, longWrapping }

/// The optional slot left of the title.
enum CoreMobileModalLeading { none, icon, avatar }

/// Body size. It carries `constrainBody` with it: the flag changes nothing
/// until the body is taller than the card's room, and an unconstrained tall
/// body overflows the phone instead of scrolling.
enum CoreMobileModalBody { short, long }

const String kCoreMobileModalTitle = 'Verify address';
const String kCoreMobileModalLongTitle =
    'Verify the full address on your Keystone device before you send';
const String kCoreMobileModalBodyText =
    'Check that every line matches the address on your device.';

/// First and last rows of the long body, so a finder can prove it scrolls.
const String kCoreMobileModalFirstRow = 'Chunk 1';
const String kCoreMobileModalLastRow = 'Chunk 30';

/// [MobileModalScaffold] inside the card it always ships in.
Widget mobileModalScaffoldFixture(
  BuildContext context, {
  required CoreMobileModalTitle title,
  required bool showClose,
  required CoreMobileModalLeading leading,
  required CoreMobileModalBody body,
}) {
  final colors = context.colors;
  return _corePhoneFrame(
    context,
    height: 852,
    child: Align(
      alignment: Alignment.bottomCenter,
      child: MobileModalCard(
        child: Builder(
          builder: (cardContext) => MobileModalScaffold(
            title: title == CoreMobileModalTitle.longWrapping
                ? kCoreMobileModalLongTitle
                : kCoreMobileModalTitle,
            titleMaxLines: title == CoreMobileModalTitle.longWrapping ? 2 : 1,
            showTitle: title != CoreMobileModalTitle.hidden,
            showClose: showClose,
            constrainBody: body == CoreMobileModalBody.long,
            leading: switch (leading) {
              CoreMobileModalLeading.none => null,
              CoreMobileModalLeading.icon => const AppIcon(
                AppIcons.shieldKeyhole,
                size: AppIconSize.large,
              ),
              CoreMobileModalLeading.avatar => const AppProfilePicture(
                profilePictureId: 'pfp-04',
                size: AppProfilePictureSize.large,
              ),
            },
            // `maybePop`, never `pop`: the widgetbook root must survive a
            // close tap with nothing to unwind.
            onClose: () => Navigator.of(cardContext).maybePop(),
            child: body == CoreMobileModalBody.short
                ? Text(
                    kCoreMobileModalBodyText,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var index = 0; index < 30; index++)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.s,
                                  ),
                                  child: Text(
                                    'Chunk ${index + 1}',
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: colors.text.primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppButton(
                        size: AppButtonSize.large,
                        onPressed: () {},
                        child: const Text('Copy address'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    ),
  );
}

/// What sits behind the mobile modal card.
enum CoreMobileModalBackground { screen, blank }

/// Key on the card's body, so a test can measure the gap below it.
const Key kCoreMobileModalBodyKey = ValueKey('core_mobile_modal_body');

/// [MobileModalCard] over a scrim, with the keyboard and platform insets that
/// decide its bottom gap.
///
/// The opaque option goes through [MobileModalOverlay], which owns exactly
/// that background + scrim + bottom-card composition; the transparent option
/// stacks the same three layers itself, because the overlay has no
/// `transparentBackground` of its own.
Widget mobileModalCardFixture(
  BuildContext context, {
  required bool transparentBackground,
  required bool keyboardOpen,
  required TargetPlatform platform,
  required CoreMobileModalBackground background,
}) {
  final colors = context.colors;
  final body = SizedBox(
    key: kCoreMobileModalBodyKey,
    width: double.infinity,
    height: 200,
    child: Center(
      child: Text(
        kCoreMobileModalBodyText,
        textAlign: TextAlign.center,
        style: AppTypography.bodyMedium.copyWith(color: colors.text.secondary),
      ),
    ),
  );
  final backdrop = background == CoreMobileModalBackground.screen
      ? _coreMobileShellBackdrop(context)
      : ColoredBox(color: colors.background.window);

  return WbPlatformOverride(
    platform: platform,
    child: _corePhoneFrame(
      context,
      height: 852,
      // 34 is the Android navigation-bar inset; iOS deliberately ignores it.
      viewPadding: const EdgeInsets.only(top: 55, bottom: 34),
      viewInsets: EdgeInsets.only(bottom: keyboardOpen ? 300 : 0),
      child: transparentBackground
          ? Stack(
              fit: StackFit.expand,
              children: [
                backdrop,
                ColoredBox(color: colors.background.neutralScrim),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: MobileModalCard(
                    transparentBackground: true,
                    child: body,
                  ),
                ),
              ],
            )
          : MobileModalOverlay(background: backdrop, child: body),
    ),
  );
}

/// A static mobile shell — top nav, content, tab bar — for a modal to sit on.
Widget _coreMobileShellBackdrop(BuildContext context) {
  return AppMobileShell(
    body: Column(
      children: [
        MobileTopNav.account(
          accountName: 'Account 1',
          syncLabel: 'Vizor is synced',
        ),
        Expanded(
          child: Center(
            child: Text(
              'Home',
              style: AppTypography.headlineMedium.copyWith(
                color: context.colors.text.accent,
              ),
            ),
          ),
        ),
      ],
    ),
    tabBar: AppMobileTabBar(
      items: const [
        AppMobileTabItem(iconName: AppIcons.home, label: 'Home'),
        AppMobileTabItem(iconName: AppIcons.swapArrows, label: 'Swap'),
        AppMobileTabItem(iconName: AppIcons.history, label: 'Activity'),
        AppMobileTabItem(iconName: AppIcons.cog, label: 'Settings'),
      ],
      currentIndex: 0,
      onSelect: (_) {},
    ),
  );
}

// --- Decorative divider -----------------------------------------------------

/// Widths [AppDecorativeDivider] is drawn at.
enum CoreDividerWidth { calendar, wide }

/// The real [AppDecorativeDivider] on a plain ground: two rails and the SVG
/// centre mark, which only the width axis changes.
Widget decorativeDividerFixture(
  BuildContext context, {
  required CoreDividerWidth width,
}) {
  return ColoredBox(
    color: context.colors.background.base,
    child: Center(
      child: AppDecorativeDivider(
        width: switch (width) {
          CoreDividerWidth.calendar => 256,
          CoreDividerWidth.wide => 420,
        },
      ),
    ),
  );
}

// --- Pane scroll scaffold ---------------------------------------------------

/// Whether the pane content is tall enough to scroll under the toolbar band.
enum CorePaneScaffoldContent { fits, scrolls }

/// Key on the first content row, so a test can measure it against the pinned
/// 48px toolbar band.
const Key kCorePaneScaffoldFirstRowKey = ValueKey('core_pane_scaffold_row_0');

/// The real [AppPaneSliverScrollScaffold] in a desktop pane, laid out the way
/// the Activity screen uses it: pinned toolbar, slivers scrolling underneath.
Widget paneSliverScrollScaffoldFixture(
  BuildContext context, {
  required CorePaneScaffoldContent content,
}) {
  final colors = context.colors;
  final rowCount = content == CorePaneScaffoldContent.fits ? 3 : 24;

  return WbFrame(
    layout: WbLayout.desktop,
    child: AppPaneSliverScrollScaffold(
      toolbar: AppPaneToolbar(
        leading: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Activity',
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.primary,
            ),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      slivers: [
        SliverList.builder(
          itemCount: rowCount,
          itemBuilder: (context, index) => Padding(
            key: index == 0 ? kCorePaneScaffoldFirstRowKey : null,
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Container(
              height: 56,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.surface.card,
                borderRadius: BorderRadius.circular(AppRadii.medium),
              ),
              child: Text(
                'Row ${index + 1}',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.primary,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
