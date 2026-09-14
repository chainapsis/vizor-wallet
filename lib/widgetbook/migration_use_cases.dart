// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/config/swap_feature_config.dart';
import '../src/core/profile_pictures.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/storage/app_secure_store.dart';
import '../src/core/widgets/app_button.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/app_toast.dart';
import '../src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import '../src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import '../src/features/migration/screens/ironwood_migration_flow_screen.dart';
import '../src/features/migration/screens/mobile/mobile_ironwood_migration_flow_screen.dart';
import '../src/features/migration/services/ironwood_migration_service.dart';
import '../src/features/migration/widgets/ironwood_migration_privacy_lock_host.dart';
import '../src/features/migration/widgets/mobile/mobile_ironwood_keystone_signing_view.dart';
import '../src/features/onboarding/unlock_screen.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/app_security_provider.dart';
import '../src/providers/privacy_mode_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/rust/api/sync.dart' as rust_sync;
import 'support/wb_layout.dart';

/// Which of the four Keystone migration signing screens a preview renders.
///
/// Every one of them is the same private `_IronwoodMigrationKeystonePrivate
/// SignScreen` behind a different public wrapper, so one fixture covers all
/// eight desktop/mobile classes.
enum MigrationKeystoneSignStep { combined, immediate, denomination, batch }

/// Where a Keystone signing session is when the preview opens.
///
/// [scanning] is the one stage this fixture does not build: it needs the camera
/// fake, so `migrationKeystoneScanFixture` in `scanner_use_cases.dart` serves
/// it and the gallery routes that option there.
enum MigrationKeystoneSignStage { preparing, requestQr, failed, scanning }

/// One of the eight Keystone migration signing screens, driven only through
/// its public props and provider overrides.
///
/// [multiRound] splits the preview request into two signing rounds, which is
/// what produces the 'Round 1 of 2' badge and the per-round transaction count.
Widget migrationKeystoneSignFixture({
  required MigrationKeystoneSignStep step,
  required WbLayout layout,
  required MigrationKeystoneSignStage stage,
  bool multiRound = true,
}) {
  final request = stage == MigrationKeystoneSignStage.requestQr
      ? _previewSigningRequest(step: step, multiRound: multiRound)
      : null;
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _keystoneSignBootstrap(_keystoneSignAccountState),
      ),
      accountProvider.overrideWith(
        () => _KeystoneSignAccountNotifier(_keystoneSignAccountState),
      ),
      syncProvider.overrideWith(
        () => _KeystoneSignSyncNotifier(
          _keystoneSignAccountState.activeAccountUuid,
        ),
      ),
      privacyModeProvider.overrideWith(_KeystoneSignPrivacyModeNotifier.new),
      swapFeatureEnabledProvider.overrideWithValue(true),
      ironwoodMigrationCoordinatorProvider.overrideWith(
        () => _KeystoneSignMigrationCoordinator(
          _keystoneSignAccountState.activeAccountUuid,
        ),
      ),
      // Without a preview request the screen runs its real prepare path, so
      // the service is the seam that holds it in Preparing or fails it.
      ironwoodMigrationServiceProvider.overrideWithValue(
        _keystoneSignPreviewService(stage),
      ),
    ],
    child: _MigrationKeystoneSignHarness(
      step: step,
      layout: layout,
      request: request,
      urParts: request == null ? const [] : _previewUrParts,
    ),
  );
}

// --- Harness ---------------------------------------------------------------

/// Routes the signing screen reaches from its back link and its completion
/// handler, so neither throws while the preview is open.
class _MigrationKeystoneSignHarness extends StatefulWidget {
  const _MigrationKeystoneSignHarness({
    required this.step,
    required this.layout,
    required this.request,
    required this.urParts,
  });

  final MigrationKeystoneSignStep step;
  final WbLayout layout;
  final rust_sync.KeystoneMigrationSigningRequest? request;
  final List<String> urParts;

  @override
  State<_MigrationKeystoneSignHarness> createState() =>
      _MigrationKeystoneSignHarnessState();
}

class _MigrationKeystoneSignHarnessState
    extends State<_MigrationKeystoneSignHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: _signRoute(widget.step),
      routes: [
        GoRoute(path: _signRoute(widget.step), builder: (_, _) => _screen()),
        for (final path in const [
          '/home',
          '/migration/options',
          '/migration/fast/review',
          '/migration/immediate/review',
          '/migration/private/review',
          '/migration/private/status',
        ])
          GoRoute(
            path: path,
            builder: (_, _) => _KeystoneSignRoutePlaceholder(label: path),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  Widget _screen() {
    final request = widget.request;
    final urParts = widget.urParts;
    return switch ((widget.layout, widget.step)) {
      (WbLayout.desktop, MigrationKeystoneSignStep.combined) =>
        IronwoodMigrationKeystoneCombinedSignScreen(
          approvedSchedule: const [],
          previewRequest: request,
          previewUrParts: urParts,
          onOpenFirmware: _noopReleaseNotes,
        ),
      (WbLayout.mobile, MigrationKeystoneSignStep.combined) =>
        MobileIronwoodMigrationKeystoneCombinedSignScreen(
          approvedSchedule: const [],
          previewRequest: request,
          previewUrParts: urParts,
          onOpenFirmware: _noopReleaseNotes,
        ),
      (WbLayout.desktop, MigrationKeystoneSignStep.immediate) =>
        IronwoodMigrationKeystoneImmediateSignScreen(
          approvedPlan: _previewImmediatePlan(),
          previewRequest: request,
          previewUrParts: urParts,
          onOpenFirmware: _noopReleaseNotes,
        ),
      (WbLayout.mobile, MigrationKeystoneSignStep.immediate) =>
        MobileIronwoodMigrationKeystoneImmediateSignScreen(
          approvedPlan: _previewImmediatePlan(),
          previewRequest: request,
          previewUrParts: urParts,
          onOpenFirmware: _noopReleaseNotes,
        ),
      // The desktop denomination and batch screens take no preview request, so
      // a Request QR there would need a real Rust prepare; they stay on the
      // preparing spinner instead.
      (WbLayout.desktop, MigrationKeystoneSignStep.denomination) =>
        const IronwoodMigrationKeystoneDenominationSignScreen(
          onOpenFirmware: _noopReleaseNotes,
        ),
      (WbLayout.mobile, MigrationKeystoneSignStep.denomination) =>
        MobileIronwoodMigrationKeystoneDenominationSignScreen(
          previewRequest: request,
          previewUrParts: urParts,
          onOpenFirmware: _noopReleaseNotes,
        ),
      (WbLayout.desktop, MigrationKeystoneSignStep.batch) =>
        const IronwoodMigrationKeystoneBatchSignScreen(
          onOpenFirmware: _noopReleaseNotes,
        ),
      (WbLayout.mobile, MigrationKeystoneSignStep.batch) =>
        MobileIronwoodMigrationKeystoneBatchSignScreen(
          previewRequest: request,
          previewUrParts: urParts,
          onOpenFirmware: _noopReleaseNotes,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final router = Router.withConfig(config: _router);
    if (widget.layout == WbLayout.mobile) {
      return WbFrame(layout: WbLayout.mobile, child: router);
    }
    // The desktop classes carry their own backdrop shell, so the fixture only
    // supplies the opaque window the shell is painted on.
    return WbDesktopWindowBox(
      child: ColoredBox(
        color: context.colors.macosUtility.window,
        child: router,
      ),
    );
  }
}

String _signRoute(MigrationKeystoneSignStep step) => switch (step) {
  MigrationKeystoneSignStep.combined => '/migration/private/keystone/sign',
  MigrationKeystoneSignStep.immediate => '/migration/immediate/keystone/sign',
  MigrationKeystoneSignStep.denomination =>
    '/migration/private/keystone/denominations/sign',
  MigrationKeystoneSignStep.batch => '/migration/private/keystone/batch/sign',
};

class _KeystoneSignRoutePlaceholder extends StatelessWidget {
  const _KeystoneSignRoutePlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Navigated to $label'));
  }
}

// --- Deterministic preview data --------------------------------------------

final _keystoneSignAccountState = AccountState(
  accounts: const [
    AccountInfo(
      uuid: 'preview-keystone-migration-account',
      name: 'Keystone Vault',
      order: 0,
      isHardware: true,
      profilePictureId: 'pfp-02',
    ),
  ],
  activeAccountUuid: 'preview-keystone-migration-account',
  activeAddress: 'u1widgetbookkeystonemigrationaddress',
);

AppBootstrapState _keystoneSignBootstrap(AccountState accountState) {
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: accountState,
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: defaultRpcEndpointConfig('main'),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}

const _previewUrParts = <String>[
  'ur:zcash-sign-request/preview-migration-round-1',
];

/// `signingBatchLimit: 1` puts one transaction in each round, so the message
/// count is the round count the 'Round 1 of 2' badge reads.
rust_sync.KeystoneMigrationSigningRequest _previewSigningRequest({
  required MigrationKeystoneSignStep step,
  required bool multiRound,
}) {
  return rust_sync.KeystoneMigrationSigningRequest(
    requestId: 'preview-${step.name}',
    messages: [
      rust_sync.KeystoneMigrationMessage(
        id: 'preview-${step.name}-1',
        redactedPczt: Uint8List.fromList(const [1, 2, 3]),
        expectedSignatureCount: 0,
      ),
      if (multiRound)
        rust_sync.KeystoneMigrationMessage(
          id: 'preview-${step.name}-2',
          redactedPczt: Uint8List.fromList(const [4, 5, 6]),
          expectedSignatureCount: 0,
        ),
    ],
    signingBatchLimit: 1,
  );
}

rust_sync.OrchardMigrationImmediatePlan _previewImmediatePlan() {
  return rust_sync.OrchardMigrationImmediatePlan(
    totalInputZatoshi: BigInt.from(14223060000),
    feeZatoshi: BigInt.from(60000),
    migratedZatoshi: BigInt.from(14223000000),
    inputNoteCount: 12,
  );
}

// --- Preview services and notifiers ----------------------------------------

/// A migration service whose wallet-DB lookup either never completes (the
/// screen stays on Preparing) or fails (the screen shows its failure content),
/// so neither stage reaches storage or Rust.
IronwoodMigrationService _keystoneSignPreviewService(
  MigrationKeystoneSignStage stage,
) {
  return IronwoodMigrationService(
    getWalletDbPath: stage == MigrationKeystoneSignStage.failed
        ? _failingWalletDbPath
        : _pendingWalletDbPath,
    getStatus: _unusedMigrationStatus,
    getPrivatePlan: _unusedPrivatePlan,
    secureStore: AppSecureStore.instance,
  );
}

Future<String> _pendingWalletDbPath() => Completer<String>().future;

Future<String> _failingWalletDbPath() => Future<String>.error(
  StateError('Preview Keystone signing could not be prepared.'),
);

Future<rust_sync.MigrationStatus> _unusedMigrationStatus({
  required String dbPath,
  required String network,
  required String accountUuid,
}) => Future<rust_sync.MigrationStatus>.error(
  StateError('Preview migration status is not available.'),
);

Future<rust_sync.OrchardMigrationPrivatePlan?> _unusedPrivatePlan({
  required String dbPath,
  required String network,
  required String accountUuid,
}) async => null;

class _KeystoneSignAccountNotifier extends AccountNotifier {
  _KeystoneSignAccountNotifier(this.initialState);

  final AccountState initialState;

  @override
  FutureOr<AccountState> build() => initialState;
}

class _KeystoneSignSyncNotifier extends SyncNotifier {
  _KeystoneSignSyncNotifier(this.activeAccountUuid);

  final String? activeAccountUuid;

  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: activeAccountUuid,
    hasAccountScopedData: activeAccountUuid != null,
    isSyncComplete: true,
    percentage: 1,
    totalBalance: BigInt.from(14223000000),
    orchardBalance: BigInt.from(14223000000),
    spendableBalance: BigInt.from(14223000000),
  );
}

class _KeystoneSignPrivacyModeNotifier extends PrivacyModeNotifier {
  @override
  Future<void> set(bool enabled) async {
    state = enabled;
  }
}

class _KeystoneSignMigrationCoordinator extends IronwoodMigrationCoordinator {
  _KeystoneSignMigrationCoordinator(this.accountUuid);

  final String? accountUuid;

  @override
  IronwoodMigrationCoordinatorState build() =>
      const IronwoodMigrationCoordinatorState(statuses: {});
}

// ===========================================================================
// Desktop migration routes
// ===========================================================================

/// Outcome the `/migration/prepare` gate resolves to.
enum MigrationPrepareGateCase {
  syncing,
  notAvailable,
  syncFailed,
  statusError,
  notNeeded,
  resume,
  start,
}

/// What a status-backed desktop screen has to render while its status future
/// resolves.
enum MigrationStatusDataCase { status, loading, unavailable }

/// Async states of the migration schedule screen.
enum MigrationScheduleDataCase { schedule, loading, unavailable }

/// Async states of the preparation schedule screen, plus the round-less run
/// the screen has to hold before Rust has planned any split.
enum MigrationPreparationDataCase { schedule, empty, loading, unavailable }

/// State every row of the migration schedule carries, or the mixed run the
/// schedule normally shows.
enum MigrationSchedulePartCase {
  mixed,
  scheduled,
  broadcasting,
  confirming,
  completed,
  needsSignature,
}

/// State every preparation split carries, or the mixed run.
enum MigrationPreparationTxCase {
  mixed,
  awaitingInputs,
  scheduled,
  broadcasting,
  confirming,
  completed,
}

/// Where each preparation split sends its outputs.
enum MigrationPreparationOutputCase { mixed, migration, change, continuation }

/// The `/migration/prepare` gate: the loading shell plus whichever toast and
/// redirect its inputs produce.
Widget migrationPrepareGateFixture({required MigrationPrepareGateCase gate}) {
  return _migrationDesktopScope(
    inputs: _migrationInputs(
      ironwoodActiveAtTip: gate != MigrationPrepareGateCase.notAvailable,
      isSyncing: gate == MigrationPrepareGateCase.syncing,
      hasSyncFailure: gate == MigrationPrepareGateCase.syncFailed,
    ),
    statusGetter: switch (gate) {
      MigrationPrepareGateCase.statusError => _failingMigrationStatus,
      MigrationPrepareGateCase.notNeeded => _noOrchardFundsMigrationStatus,
      MigrationPrepareGateCase.resume => _resumableMigrationStatus,
      _ => _startableMigrationStatus,
    },
    child: const _MigrationDesktopRouteHarness(
      location: '/migration/prepare',
      screen: IronwoodMigrationPrepareScreen(),
    ),
  );
}

/// The private status screen while its status future is still pending or has
/// failed; [MigrationStatusDataCase.status] is covered by the phase fixtures.
Widget migrationPrivateStatusAsyncFixture({
  required MigrationStatusDataCase data,
}) {
  return _migrationDesktopScope(
    inputs: _migrationInputs(),
    statusGetter: data == MigrationStatusDataCase.unavailable
        ? _failingMigrationStatus
        : _pendingMigrationStatus,
    child: const _MigrationDesktopRouteHarness(
      location: '/migration/private/status',
      screen: IronwoodMigrationPrivateStatusScreen(),
    ),
  );
}

/// The migration schedule screen driven by its public preview props.
Widget migrationScheduleFixture({
  MigrationScheduleDataCase data = MigrationScheduleDataCase.schedule,
  MigrationSchedulePartCase rowStatus = MigrationSchedulePartCase.mixed,
  IronwoodMigrationSchedulePreviewOverlay? overlay,
  bool canStop = false,
}) {
  final status = data == MigrationScheduleDataCase.schedule
      ? _migrationSchedulePreviewStatus(rowStatus)
      : null;
  return _migrationDesktopScope(
    inputs: _migrationInputs(),
    statusGetter: data == MigrationScheduleDataCase.unavailable
        ? _failingMigrationStatus
        : _pendingMigrationStatus,
    child: _MigrationDesktopRouteHarness(
      location: '/migration/private/schedule',
      screen: IronwoodMigrationScheduleScreen(
        previewStatus: status,
        previewOverlay: overlay,
        previewCanStop: canStop,
      ),
    ),
  );
}

/// The preparation schedule screen driven by its public preview props.
Widget migrationPreparationScheduleFixture({
  MigrationPreparationDataCase data = MigrationPreparationDataCase.schedule,
  MigrationPreparationTxCase txStatus = MigrationPreparationTxCase.mixed,
  MigrationPreparationOutputCase output = MigrationPreparationOutputCase.mixed,
}) {
  final status = switch (data) {
    MigrationPreparationDataCase.schedule => _migrationPreparationPreviewStatus(
      txStatus: txStatus,
      output: output,
    ),
    MigrationPreparationDataCase.empty => _migrationPreparationPreviewStatus(
      txStatus: txStatus,
      output: output,
      transactions: const [],
    ),
    _ => null,
  };
  return _migrationDesktopScope(
    inputs: _migrationInputs(),
    statusGetter: data == MigrationPreparationDataCase.unavailable
        ? _failingMigrationStatus
        : _pendingMigrationStatus,
    child: _MigrationDesktopRouteHarness(
      location: '/migration/private/preparation-schedule',
      screen: IronwoodMigrationPreparationScheduleScreen(previewStatus: status),
    ),
  );
}

/// The virtual unlock screen behind the migration privacy lock.
///
/// `disableAnimations` is the only seam that freezes the badge's loader, which
/// is what the reduced-motion preview needs.
Widget migrationVirtualUnlockFixture({
  required bool showMigrationInProgress,
  required bool reducedMotion,
}) {
  return ProviderScope(
    child: Builder(
      builder: (BuildContext context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: WbDesktopWindowBox(
          child: IronwoodMigrationVirtualUnlockScreen(
            showMigrationInProgress: showMigrationInProgress,
          ),
        ),
      ),
    ),
  );
}

/// One step of the desktop flow shell.
///
/// [fallbackData] drops the account out of the inputs, which is what makes
/// `ironwoodMigrationFlowDataProvider` return null and the screen fall back to
/// its 0 ZEC / 'Username' data.
Widget migrationFlowStepFixture({
  required IronwoodMigrationFlowStep step,
  bool fallbackData = false,
}) {
  return _migrationDesktopScope(
    inputs: _migrationInputs(
      accountUuid: fallbackData ? null : _migrationPreviewAccountUuid,
    ),
    child: _MigrationDesktopRouteHarness(
      location: '/migration/flow',
      screen: IronwoodMigrationFlowScreen(
        step: step,
        previewData: fallbackData ? null : _migrationFlowData(),
        onOpenReleaseNotesOverride: _noopReleaseNotes,
      ),
    ),
  );
}

void _noopReleaseNotes() {}

// --- Desktop harness -------------------------------------------------------

/// Hosts one desktop migration screen on the route it really lives on, with
/// visible placeholders for every route it can leave to.
class _MigrationDesktopRouteHarness extends StatefulWidget {
  const _MigrationDesktopRouteHarness({
    required this.location,
    required this.screen,
  });

  final String location;
  final Widget screen;

  @override
  State<_MigrationDesktopRouteHarness> createState() =>
      _MigrationDesktopRouteHarnessState();
}

class _MigrationDesktopRouteHarnessState
    extends State<_MigrationDesktopRouteHarness> {
  static const _exitRoutes = [
    '/home',
    '/migration/intro',
    '/migration/options',
    '/migration/private/status',
    '/migration/private/schedule',
    '/migration/private/preparation-schedule',
    '/migration/immediate/review',
    '/activity',
    '/settings',
  ];

  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: widget.location,
      routes: [
        GoRoute(path: widget.location, builder: (_, _) => widget.screen),
        for (final path in _exitRoutes)
          if (path != widget.location)
            GoRoute(
              path: path,
              builder: (_, _) => _KeystoneSignRoutePlaceholder(label: path),
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
    // The migration screens paint their own backdrop shell, so the fixture
    // only supplies the opaque window it sits on.
    return WbDesktopWindowBox(
      child: ColoredBox(
        color: context.colors.macosUtility.window,
        child: AppToastHost(child: Router.withConfig(config: _router)),
      ),
    );
  }
}

// --- Desktop provider scope ------------------------------------------------

Widget _migrationDesktopScope({
  required Widget child,
  required IronwoodMigrationInputs inputs,
  OrchardMigrationStatusGetter? statusGetter,
  IronwoodMigrationCoordinator Function()? coordinator,
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _keystoneSignBootstrap(_migrationAccountState),
      ),
      accountProvider.overrideWith(
        () => _KeystoneSignAccountNotifier(_migrationAccountState),
      ),
      syncProvider.overrideWith(_MigrationSyncNotifier.new),
      privacyModeProvider.overrideWith(_KeystoneSignPrivacyModeNotifier.new),
      swapFeatureEnabledProvider.overrideWithValue(true),
      ironwoodMigrationCoordinatorProvider.overrideWith(
        coordinator ?? _MigrationPreviewCoordinator.new,
      ),
      ironwoodMigrationInputsProvider.overrideWithValue(inputs),
      walletDbPathGetterProvider.overrideWithValue(_previewWalletDbPath),
      orchardMigrationStatusGetterProvider.overrideWithValue(
        statusGetter ?? _pendingMigrationStatus,
      ),
      // Appended last; must not repeat a provider overridden above — Riverpod 3
      // rejects a duplicate override. Replace one through a parameter instead
      // (see [coordinator]).
      ...extraOverrides,
    ],
    child: child,
  );
}

const _migrationPreviewAccountUuid = 'preview-migration-account';

final _migrationAccountState = AccountState(
  accounts: const [
    AccountInfo(
      uuid: _migrationPreviewAccountUuid,
      name: 'Username',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: _migrationPreviewAccountUuid,
  activeAddress: 'u1widgetbookmigrationpreviewaddress',
);

IronwoodMigrationInputs _migrationInputs({
  bool ironwoodActiveAtTip = true,
  bool isSyncing = false,
  bool hasSyncFailure = false,
  String? accountUuid = _migrationPreviewAccountUuid,
}) {
  return IronwoodMigrationInputs(
    ironwoodActiveAtTip: ironwoodActiveAtTip,
    network: 'main',
    accountUuid: accountUuid,
    accountName: 'Username',
    profilePictureId: kDefaultProfilePictureId,
    hasAccountScopedData: true,
    isSyncing: isSyncing,
    isBackgroundMode: false,
    isSyncComplete: !isSyncing,
    hasSyncFailure: hasSyncFailure,
    orchardBalance: BigInt.from(14223000000),
    orchardPendingBalance: BigInt.zero,
    ironwoodBalance: BigInt.zero,
    ironwoodPendingBalance: BigInt.zero,
  );
}

IronwoodMigrationFlowData _migrationFlowData() {
  return IronwoodMigrationFlowData(
    amountZatoshi: BigInt.from(14223000000),
    accountName: 'Username',
    profilePictureId: kDefaultProfilePictureId,
  );
}

Future<String> _previewWalletDbPath() async => '/preview/wallet.db';

Future<rust_sync.MigrationStatus> _pendingMigrationStatus({
  required String dbPath,
  required String network,
  required String accountUuid,
}) => Completer<rust_sync.MigrationStatus>().future;

Future<rust_sync.MigrationStatus> _failingMigrationStatus({
  required String dbPath,
  required String network,
  required String accountUuid,
}) async => throw StateError('Preview migration status is unavailable.');

Future<rust_sync.MigrationStatus> _startableMigrationStatus({
  required String dbPath,
  required String network,
  required String accountUuid,
}) async => migrationPreviewStatus(phase: kIronwoodMigrationReadyPhase);

Future<rust_sync.MigrationStatus> _noOrchardFundsMigrationStatus({
  required String dbPath,
  required String network,
  required String accountUuid,
}) async =>
    migrationPreviewStatus(phase: kIronwoodMigrationNoOrchardFundsPhase);

Future<rust_sync.MigrationStatus> _resumableMigrationStatus({
  required String dbPath,
  required String network,
  required String accountUuid,
}) async => migrationPreviewStatus(
  phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
  activeRunId: 'preview-migration-run',
);

class _MigrationSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: _migrationAccountState.activeAccountUuid,
    hasAccountScopedData: true,
    isSyncComplete: true,
    percentage: 1,
    scannedHeight: 3000000,
    chainTipHeight: 3000000,
    totalBalance: BigInt.from(14223000000),
    orchardBalance: BigInt.from(14223000000),
    spendableBalance: BigInt.from(14223000000),
  );
}

class _MigrationPreviewCoordinator extends IronwoodMigrationCoordinator {
  @override
  IronwoodMigrationCoordinatorState build() =>
      const IronwoodMigrationCoordinatorState();
}

// --- Deterministic status data ---------------------------------------------

/// One `MigrationStatus` builder for every desktop migration preview, so the
/// struct's 30 fields are spelled out once.
rust_sync.MigrationStatus migrationPreviewStatus({
  required String phase,
  String? activeRunId,
  List<int> targetValues = const [],
  List<rust_sync.MigrationPartStatus> parts = const [],
  List<rust_sync.MigrationPreparationTransactionStatus>?
  preparationTransactions,
  bool canAbandon = false,
  String? message,
  int broadcastedTxCount = 0,
  int confirmedTxCount = 0,
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    activeRunId: activeRunId,
    targetValuesZatoshi: frb.Uint64List.fromList(targetValues),
    preparedNoteCount: parts.length,
    denominationConfirmationCount: 3,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 1,
    pendingTxCount: 0,
    message: message,
    broadcastedTxCount: broadcastedTxCount,
    confirmedTxCount: confirmedTxCount,
    totalCount: parts.length,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: canAbandon,
    signingBatchLimit: 8,
    scheduleMeanDelayBlocks: 108,
    scheduleMaxDelayBlocks: 432,
    preparationMeanDelayBlocks: 24,
    scheduledBroadcasts: const [],
    preparationTransactions: preparationTransactions,
    parts: parts,
  );
}

const _migrationPreviewPartValues = <int>[
  4000000000,
  1000000000,
  3500000000,
  400000000,
  585000000,
];

rust_sync.MigrationStatus _migrationSchedulePreviewStatus(
  MigrationSchedulePartCase rowStatus,
) {
  final parts = [
    for (var index = 0; index < _migrationPreviewPartValues.length; index++)
      _migrationPreviewPart(
        index,
        _migrationPreviewPartValues[index],
        rowStatus == MigrationSchedulePartCase.mixed
            ? _mixedSchedulePartState(index)
            : _schedulePartState(rowStatus),
      ),
  ];
  return migrationPreviewStatus(
    phase: kIronwoodMigrationBroadcastScheduledPhase,
    activeRunId: 'preview-migration-run',
    targetValues: _migrationPreviewPartValues,
    parts: parts,
  );
}

/// The pending flavour of the same schedule: the run is waiting on
/// confirmations and its tail has no broadcast height assigned yet.
rust_sync.MigrationStatus _migrationSchedulePendingPreviewStatus(
  MigrationSchedulePartCase rowStatus,
) {
  final parts = [
    for (var index = 0; index < _migrationPreviewPartValues.length; index++)
      _migrationPreviewPart(
        index,
        _migrationPreviewPartValues[index],
        rowStatus == MigrationSchedulePartCase.mixed
            ? _pendingSchedulePartState(index)
            : _schedulePartState(rowStatus),
        unscheduled: index >= 3,
      ),
  ];
  return migrationPreviewStatus(
    phase: kIronwoodMigrationWaitingConfirmationsPhase,
    activeRunId: 'preview-migration-pending-run',
    targetValues: _migrationPreviewPartValues,
    parts: parts,
    broadcastedTxCount: 3,
    confirmedTxCount: 2,
  );
}

rust_sync.MigrationPartState _pendingSchedulePartState(int index) =>
    switch (index) {
      0 || 1 => rust_sync.MigrationPartState.completed,
      2 => rust_sync.MigrationPartState.confirming,
      3 => rust_sync.MigrationPartState.scheduled,
      _ => rust_sync.MigrationPartState.preparing,
    };

rust_sync.MigrationPartState _mixedSchedulePartState(int index) =>
    switch (index) {
      0 => rust_sync.MigrationPartState.completed,
      1 => rust_sync.MigrationPartState.confirming,
      2 => rust_sync.MigrationPartState.migrating,
      _ => rust_sync.MigrationPartState.scheduled,
    };

rust_sync.MigrationPartState _schedulePartState(
  MigrationSchedulePartCase rowStatus,
) => switch (rowStatus) {
  MigrationSchedulePartCase.mixed ||
  MigrationSchedulePartCase.scheduled => rust_sync.MigrationPartState.scheduled,
  MigrationSchedulePartCase.broadcasting =>
    rust_sync.MigrationPartState.migrating,
  MigrationSchedulePartCase.confirming =>
    rust_sync.MigrationPartState.confirming,
  MigrationSchedulePartCase.completed => rust_sync.MigrationPartState.completed,
  MigrationSchedulePartCase.needsSignature =>
    rust_sync.MigrationPartState.needsInput,
};

rust_sync.MigrationPartStatus _migrationPreviewPart(
  int index,
  int valueZatoshi,
  rust_sync.MigrationPartState state, {
  bool unscheduled = false,
}) {
  final completed = state == rust_sync.MigrationPartState.completed;
  return rust_sync.MigrationPartStatus(
    partIndex: index,
    scheduleOrder: index,
    valueZatoshi: BigInt.from(valueZatoshi),
    state: state,
    scheduledHeight: unscheduled ? null : 3000144 + index * 18,
    minedHeight: completed ? 2999900 + index * 18 : null,
    confirmationCount: completed
        ? 3
        : state == rust_sync.MigrationPartState.confirming
        ? 1
        : 0,
    confirmationTarget: 3,
  );
}

const _migrationPreparationPreviewValues = <int>[
  14220000000,
  8000000000,
  4000000000,
];

rust_sync.MigrationStatus _migrationPreparationPreviewStatus({
  required MigrationPreparationTxCase txStatus,
  required MigrationPreparationOutputCase output,
  List<rust_sync.MigrationPreparationTransactionStatus>? transactions,
}) {
  return migrationPreviewStatus(
    phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
    activeRunId: 'preview-migration-run',
    targetValues: _migrationPreparationPreviewValues,
    preparationTransactions:
        transactions ??
        [
          for (
            var index = 0;
            index < _migrationPreparationPreviewValues.length;
            index++
          )
            _migrationPreviewPreparationTransaction(
              index,
              _migrationPreparationPreviewValues[index],
              txStatus == MigrationPreparationTxCase.mixed
                  ? _mixedPreparationState(index)
                  : _preparationState(txStatus),
              output,
            ),
        ],
  );
}

rust_sync.MigrationPreparationTransactionState _mixedPreparationState(
  int index,
) => switch (index) {
  0 => rust_sync.MigrationPreparationTransactionState.completed,
  1 => rust_sync.MigrationPreparationTransactionState.confirming,
  _ => rust_sync.MigrationPreparationTransactionState.scheduled,
};

rust_sync.MigrationPreparationTransactionState _preparationState(
  MigrationPreparationTxCase txStatus,
) => switch (txStatus) {
  MigrationPreparationTxCase.mixed ||
  MigrationPreparationTxCase.awaitingInputs =>
    rust_sync.MigrationPreparationTransactionState.awaitingInputs,
  MigrationPreparationTxCase.scheduled =>
    rust_sync.MigrationPreparationTransactionState.scheduled,
  MigrationPreparationTxCase.broadcasting =>
    rust_sync.MigrationPreparationTransactionState.broadcasted,
  MigrationPreparationTxCase.confirming =>
    rust_sync.MigrationPreparationTransactionState.confirming,
  MigrationPreparationTxCase.completed =>
    rust_sync.MigrationPreparationTransactionState.completed,
};

rust_sync.MigrationPreparationTransactionStatus
_migrationPreviewPreparationTransaction(
  int index,
  int valueZatoshi,
  rust_sync.MigrationPreparationTransactionState state,
  MigrationPreparationOutputCase output,
) {
  final completed =
      state == rust_sync.MigrationPreparationTransactionState.completed;
  final projectedHeight = 3000144 + index * 24;
  return rust_sync.MigrationPreparationTransactionStatus(
    stageIndex: index,
    approximateValueZatoshi: BigInt.from(valueZatoshi),
    round: index == 0 ? 1 : 2,
    feeZatoshi: BigInt.from(10000),
    plannedHeight: projectedHeight,
    projectedHeight: projectedHeight,
    projectedCompletionHeight: projectedHeight + 3,
    outputs: _migrationPreviewPreparationOutputs(valueZatoshi, output, index),
    state: state,
    scheduledHeight: projectedHeight,
    minedHeight: completed ? 2999900 + index * 24 : null,
    confirmationCount: completed
        ? 3
        : state == rust_sync.MigrationPreparationTransactionState.confirming
        ? 2
        : 0,
    confirmationTarget: 3,
  );
}

List<rust_sync.MigrationPreparationOutputStatus>
_migrationPreviewPreparationOutputs(
  int valueZatoshi,
  MigrationPreparationOutputCase output,
  int index,
) {
  final kind = switch (output) {
    MigrationPreparationOutputCase.mixed =>
      index.isEven
          ? rust_sync.MigrationPreparationOutputKind.migration
          : rust_sync.MigrationPreparationOutputKind.change,
    MigrationPreparationOutputCase.migration =>
      rust_sync.MigrationPreparationOutputKind.migration,
    MigrationPreparationOutputCase.change =>
      rust_sync.MigrationPreparationOutputKind.change,
    MigrationPreparationOutputCase.continuation =>
      rust_sync.MigrationPreparationOutputKind.continuation,
  };
  return [
    rust_sync.MigrationPreparationOutputStatus(
      valueZatoshi: BigInt.from(valueZatoshi - 10000),
      kind: kind,
      nextRound: kind == rust_sync.MigrationPreparationOutputKind.continuation
          ? index + 2
          : null,
    ),
  ];
}

// ===========================================================================
// Mobile migration routes
// ===========================================================================

/// Durable phases the mobile private status route has a panel for, in the
/// order a run walks them.
enum MigrationMobileStatusPhaseCase {
  awaitingPreparation,
  confirmingSplits,
  readyToMigrate,
  broadcastScheduled,
  broadcasting,
  confirmingMigration,
  needsRecovery,
  paused,
  complete,
}

/// Which account owns the run; only a Keystone run needs the device.
enum MigrationMobileAccountCase { software, keystone }

/// What the status route resolves to before a phase panel is chosen at all.
enum MigrationMobileStatusRouteCase {
  status,
  loading,
  redirectHome,
  redirectStart,
}

/// The two live steps of the mobile flow shell.
enum MigrationMobileLiveStepCase { preparing, migrating }

/// Whether the migrating step carries the coordinator error that offers
/// credential recovery.
enum MigrationMobileRecoveryCase { none, credentialRecovery }

const _migrationMobileRunId = 'preview-mobile-migration-run';
const _migrationMobileKeystoneAccountUuid = 'preview-mobile-keystone-account';

/// The error text `ironwoodMigrationNeedsCredentialRecovery` matches.
const _migrationMobileCredentialRecoveryError =
    'Ironwood migration credential is missing for the active run.';

/// The mobile private status route, driven the way production drives it: a
/// route CTA carrying one durable status plus the service probes the screen
/// must resolve before it leaves its sync skeleton.
Widget migrationMobileStatusFixture({
  required MigrationMobileStatusPhaseCase phase,
  MigrationMobileAccountCase account = MigrationMobileAccountCase.software,
  bool notificationsAuthorized = true,
  bool backgroundTrackingSupported = true,
  MigrationMobileStatusRouteCase route = MigrationMobileStatusRouteCase.status,
}) {
  final accountState = _migrationMobileAccountState(account);
  final accountUuid = accountState.activeAccountUuid!;
  final status = migrationMobileStatusFor(phase);
  final cta = switch (route) {
    MigrationMobileStatusRouteCase.redirectHome =>
      const IronwoodHomeMigrationCtaState.hidden(),
    MigrationMobileStatusRouteCase.redirectStart =>
      IronwoodHomeMigrationCtaState.start(
        network: 'main',
        accountUuid: accountUuid,
        status: status,
      ),
    _ => IronwoodHomeMigrationCtaState.resume(
      network: 'main',
      accountUuid: accountUuid,
      status: status,
    ),
  };
  return ProviderScope(
    overrides: [
      ..._migrationMobileOverrides(accountState),
      ironwoodMigrationFlowDataProvider.overrideWith(
        (ref) => _migrationFlowData(),
      ),
      // The complete surface marks its result seen on entry; both seams are
      // redirected so no preview reaches shared preferences or Rust.
      ironwoodMigrationCompletionProvider.overrideWith(
        (ref) async => const IronwoodMigrationCompletionState.hidden(),
      ),
      ironwoodMigrationCompletionStoreProvider.overrideWithValue(
        const _MigrationPreviewCompletionStore(),
      ),
      ironwoodMigrationRouteCtaProvider.overrideWith(
        (ref) => route == MigrationMobileStatusRouteCase.loading
            ? Completer<IronwoodHomeMigrationCtaState>().future
            : Future<IronwoodHomeMigrationCtaState>.value(cta),
      ),
      ironwoodMigrationServiceProvider.overrideWithValue(
        _migrationMobilePreviewService(
          notificationsAuthorized: notificationsAuthorized,
          backgroundTrackingSupported: backgroundTrackingSupported,
        ),
      ),
    ],
    child: const _MigrationMobileRouteHarness(
      location: '/migration/private/status',
      screen: MobileIronwoodMigrationPrivateStatusScreen(),
    ),
  );
}

/// One live step of the mobile flow shell.
///
/// A Keystone run drops `previewData` and reads the flow-data provider
/// instead: preview mode pins `isHardware` to false, so the device copy is
/// only reachable through the live path.
Widget migrationMobileLiveStepFixture({
  required MigrationMobileLiveStepCase step,
  MigrationMobileAccountCase account = MigrationMobileAccountCase.software,
  MobileIronwoodMigrationPartStatus partStatus =
      MobileIronwoodMigrationPartStatus.active,
  MigrationMobileRecoveryCase recovery = MigrationMobileRecoveryCase.none,
}) {
  final accountState = _migrationMobileAccountState(account);
  final keystone = account == MigrationMobileAccountCase.keystone;
  return ProviderScope(
    overrides: _migrationMobileOverrides(
      accountState,
      coordinator: recovery == MigrationMobileRecoveryCase.credentialRecovery
          ? IronwoodMigrationCoordinatorState(
              errors: {
                accountState.activeAccountUuid!:
                    _migrationMobileCredentialRecoveryError,
              },
            )
          : const IronwoodMigrationCoordinatorState(),
      flowData: _migrationFlowData(),
    ),
    child: _MigrationMobileRouteHarness(
      // Production has no route for these two legacy steps; they are reached
      // as widget states, so the preview hosts them on their own path.
      location: '/migration/private/live',
      screen: MobileIronwoodMigrationFlowScreen(
        step: step == MigrationMobileLiveStepCase.preparing
            ? MobileIronwoodMigrationStep.preparing
            : MobileIronwoodMigrationStep.migrating,
        previewData: keystone ? null : _migrationFlowData(),
        previewPrivatePlan: _migrationMobilePrivatePlan(),
        previewParts: step == MigrationMobileLiveStepCase.migrating
            ? _migrationMobilePartPresentations(partStatus)
            : null,
      ),
    ),
  );
}

/// One of the two mobile schedule screens, driven by its preview status or by
/// the async states the status provider puts it in.
Widget migrationMobileScheduleFixture({
  required bool preparation,
  bool pending = false,
  MigrationScheduleDataCase data = MigrationScheduleDataCase.schedule,
  MigrationSchedulePartCase rowStatus = MigrationSchedulePartCase.mixed,
  MigrationPreparationTxCase txStatus = MigrationPreparationTxCase.mixed,
  MigrationPreparationOutputCase output = MigrationPreparationOutputCase.mixed,
}) {
  final status = data != MigrationScheduleDataCase.schedule
      ? null
      : preparation
      ? _migrationPreparationPreviewStatus(txStatus: txStatus, output: output)
      : pending
      ? _migrationSchedulePendingPreviewStatus(rowStatus)
      : _migrationSchedulePreviewStatus(rowStatus);
  return ProviderScope(
    overrides: _migrationMobileOverrides(
      _migrationMobileAccountState(MigrationMobileAccountCase.software),
      statusGetter: data == MigrationScheduleDataCase.unavailable
          ? _failingMigrationStatus
          : _pendingMigrationStatus,
    ),
    child: _MigrationMobileRouteHarness(
      location: preparation
          ? '/migration/private/preparation-schedule'
          : '/migration/private/schedule',
      screen: preparation
          ? MobileIronwoodMigrationPreparationScheduleScreen(
              previewStatus: status,
            )
          : MobileIronwoodMigrationScheduleScreen(previewStatus: status),
    ),
  );
}

/// The mobile Keystone signing shell, driven only by its public props.
///
/// Kept on the same bare phone box the existing signing fixtures use so every
/// option of the gallery case is framed identically.
Widget migrationMobileKeystoneSigningFixture({
  required MobileIronwoodKeystoneSigningViewState state,
  required MobileIronwoodKeystoneSigningRound round,
  bool multiRound = true,
  bool scanProgress = true,
  String? scannerMessage,
  bool scannerMessageIsError = false,
}) {
  // Production only knows the round split and message count once the request
  // is encoded, so the loading state carries neither.
  final loading = state == MobileIronwoodKeystoneSigningViewState.loading;
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
        child: MobileIronwoodKeystoneSigningView(
          state: state,
          round: round,
          signingRoundLabel: loading || !multiRound ? null : 'Round 1 of 2',
          signingMessageCountLabel: loading
              ? null
              : multiRound
              ? 'Signs 26 of 51 transactions'
              : 'Signs 51 transactions',
          scanProgress:
              state == MobileIronwoodKeystoneSigningViewState.scanner &&
                  scanProgress
              ? 0.42
              : null,
          scannerMessage: scannerMessage,
          scannerMessageIsError: scannerMessageIsError,
          qrCode: const _MigrationMobileQrPreview(),
          camera: const _MigrationMobileCameraPreview(),
          onNext: () {},
          onCancel: () {},
          onToggleFlashlight: () {},
          onShowRequestQr: () {},
          onShowScanHelp: () {},
        ),
      ),
    ),
  );
}

// --- Mobile harness --------------------------------------------------------

/// Hosts one mobile migration screen on a route, with visible placeholders for
/// every route it can leave to.
class _MigrationMobileRouteHarness extends StatefulWidget {
  const _MigrationMobileRouteHarness({
    required this.location,
    required this.screen,
  });

  final String location;
  final Widget screen;

  @override
  State<_MigrationMobileRouteHarness> createState() =>
      _MigrationMobileRouteHarnessState();
}

class _MigrationMobileRouteHarnessState
    extends State<_MigrationMobileRouteHarness> {
  static const _exitRoutes = [
    '/home',
    '/migration/intro',
    '/migration/private/status',
    '/migration/private/schedule',
    '/migration/private/preparation-schedule',
    '/migration/private/keystone/denominations/sign',
    '/migration/private/keystone/batch/sign',
  ];

  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: widget.location,
      routes: [
        GoRoute(path: widget.location, builder: (_, _) => widget.screen),
        for (final path in _exitRoutes)
          if (path != widget.location)
            GoRoute(
              path: path,
              builder: (_, _) => _KeystoneSignRoutePlaceholder(label: path),
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
    return WbFrame(
      layout: WbLayout.mobile,
      child: Router.withConfig(config: _router),
    );
  }
}

// --- Mobile provider scope -------------------------------------------------

List<Override> _migrationMobileOverrides(
  AccountState accountState, {
  IronwoodMigrationCoordinatorState coordinator =
      const IronwoodMigrationCoordinatorState(),
  OrchardMigrationStatusGetter? statusGetter,
  IronwoodMigrationFlowData? flowData,
}) {
  final accountUuid = accountState.activeAccountUuid;
  return [
    appBootstrapProvider.overrideWithValue(
      _keystoneSignBootstrap(accountState),
    ),
    accountProvider.overrideWith(
      () => _KeystoneSignAccountNotifier(accountState),
    ),
    syncProvider.overrideWith(() => _MigrationMobileSyncNotifier(accountUuid)),
    privacyModeProvider.overrideWith(_KeystoneSignPrivacyModeNotifier.new),
    swapFeatureEnabledProvider.overrideWithValue(true),
    ironwoodMigrationCoordinatorProvider.overrideWith(
      () => _MigrationMobileCoordinator(coordinator),
    ),
    ironwoodMigrationInputsProvider.overrideWithValue(
      _migrationInputs(accountUuid: accountUuid),
    ),
    walletDbPathGetterProvider.overrideWithValue(_previewWalletDbPath),
    orchardMigrationStatusGetterProvider.overrideWithValue(
      statusGetter ?? _pendingMigrationStatus,
    ),
    if (flowData != null)
      ironwoodMigrationFlowDataProvider.overrideWith((ref) => flowData),
  ];
}

AccountState _migrationMobileAccountState(MigrationMobileAccountCase account) {
  if (account == MigrationMobileAccountCase.software) {
    return _migrationAccountState;
  }
  return _migrationMobileKeystoneAccountState;
}

final _migrationMobileKeystoneAccountState = AccountState(
  accounts: const [
    AccountInfo(
      uuid: _migrationMobileKeystoneAccountUuid,
      name: 'Username',
      order: 0,
      isHardware: true,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: _migrationMobileKeystoneAccountUuid,
  activeAddress: 'u1widgetbookmobilekeystonemigrationaddress',
);

class _MigrationMobileSyncNotifier extends SyncNotifier {
  _MigrationMobileSyncNotifier(this.activeAccountUuid);

  final String? activeAccountUuid;

  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: activeAccountUuid,
    hasAccountScopedData: true,
    isSyncComplete: true,
    percentage: 1,
    scannedHeight: 3000000,
    chainTipHeight: 3000000,
    totalBalance: BigInt.from(14223000000),
    orchardBalance: BigInt.from(9000000000),
    ironwoodBalance: BigInt.from(5223000000),
    spendableBalance: BigInt.from(14223000000),
  );
}

/// A coordinator that publishes a fixed state and performs no work, so a
/// preview never advances, retries, or recovers a real run.
class _MigrationMobileCoordinator extends IronwoodMigrationCoordinator {
  _MigrationMobileCoordinator(this.initialState);

  final IronwoodMigrationCoordinatorState initialState;

  @override
  IronwoodMigrationCoordinatorState build() => initialState;

  @override
  Future<void> refreshNow({bool forceAdvance = false}) async {}

  @override
  Future<void> resumeSoftwarePreparation({
    required String accountUuid,
    required rust_sync.MigrationStatus status,
  }) async {}

  @override
  Future<void> retry(
    String accountUuid, {
    rust_sync.MigrationStatus? status,
  }) async {}

  @override
  Future<void> recover(String accountUuid) async {}
}

class _MigrationPreviewCompletionStore
    implements IronwoodMigrationCompletionStore {
  const _MigrationPreviewCompletionStore();

  @override
  Future<bool> isSeen({
    required String network,
    required String accountUuid,
    required String completionId,
  }) async => false;

  @override
  Future<void> markSeen({
    required String network,
    required String accountUuid,
    required String completionId,
  }) async {}
}

/// A migration service whose native-lane probes are pure functions.
///
/// `isIOS` / `isAndroid` are pinned because the notification and preparation
/// probes below are gated on the native lane, which only iOS has.
IronwoodMigrationService _migrationMobilePreviewService({
  required bool notificationsAuthorized,
  required bool backgroundTrackingSupported,
}) {
  return IronwoodMigrationService(
    getWalletDbPath: _previewWalletDbPath,
    getStatus: _unusedMigrationStatus,
    getPrivatePlan: _unusedPrivatePlan,
    secureStore: AppSecureStore.instance,
    isIOS: () => true,
    isAndroid: () => false,
    isMobile: () => true,
    getEndpoint: () => defaultRpcEndpointConfig('main'),
    getNotificationAuthorizationStatus: () async => notificationsAuthorized
        ? IronwoodMigrationNotificationAuthorizationStatus.authorized
        : IronwoodMigrationNotificationAuthorizationStatus.denied,
    supportsBackgroundPreparationTracking: () async =>
        backgroundTrackingSupported,
    getPreparationRuntimeState:
        ({
          required String network,
          required String accountUuid,
          required String runId,
        }) async => IronwoodMigrationPreparationRuntimeState.scheduled,
  );
}

// --- Mobile preview data ---------------------------------------------------

const _migrationMobilePartValues = <int>[
  4000000000,
  3500000000,
  3000000000,
  2200000000,
  1523000000,
];

/// The durable status behind each phase of the mobile status route.
///
/// The four phases that host the preparation-complete modal deliberately carry
/// no run id: the modal records itself in shared preferences the first time it
/// appears, which would make the preview differ between runs.
rust_sync.MigrationStatus migrationMobileStatusFor(
  MigrationMobileStatusPhaseCase phase,
) {
  List<rust_sync.MigrationPartStatus> parts(
    rust_sync.MigrationPartState Function(int index) stateFor,
  ) => [
    for (var index = 0; index < _migrationMobilePartValues.length; index++)
      _migrationPreviewPart(
        index,
        _migrationMobilePartValues[index],
        stateFor(index),
      ),
  ];

  return switch (phase) {
    MigrationMobileStatusPhaseCase.awaitingPreparation =>
      migrationPreviewStatus(
        phase: kIronwoodMigrationAwaitingPreparationPhase,
        activeRunId: _migrationMobileRunId,
        targetValues: _migrationMobilePartValues,
      ),
    MigrationMobileStatusPhaseCase.confirmingSplits => migrationPreviewStatus(
      phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
      activeRunId: _migrationMobileRunId,
      targetValues: _migrationMobilePartValues,
    ),
    MigrationMobileStatusPhaseCase.readyToMigrate => migrationPreviewStatus(
      phase: kIronwoodMigrationReadyToMigratePhase,
      targetValues: _migrationMobilePartValues,
      parts: parts((_) => rust_sync.MigrationPartState.scheduled),
    ),
    MigrationMobileStatusPhaseCase.broadcastScheduled => migrationPreviewStatus(
      phase: kIronwoodMigrationBroadcastScheduledPhase,
      targetValues: _migrationMobilePartValues,
      parts: parts(
        (index) => index == 0
            ? rust_sync.MigrationPartState.completed
            : rust_sync.MigrationPartState.scheduled,
      ),
      confirmedTxCount: 1,
    ),
    MigrationMobileStatusPhaseCase.broadcasting => migrationPreviewStatus(
      phase: kIronwoodMigrationBroadcastingPhase,
      targetValues: _migrationMobilePartValues,
      parts: parts(
        (index) => switch (index) {
          0 => rust_sync.MigrationPartState.completed,
          1 => rust_sync.MigrationPartState.migrating,
          _ => rust_sync.MigrationPartState.scheduled,
        },
      ),
      confirmedTxCount: 1,
    ),
    MigrationMobileStatusPhaseCase.confirmingMigration =>
      migrationPreviewStatus(
        phase: kIronwoodMigrationWaitingConfirmationsPhase,
        targetValues: _migrationMobilePartValues,
        parts: parts(
          (index) => switch (index) {
            0 || 1 => rust_sync.MigrationPartState.completed,
            2 => rust_sync.MigrationPartState.confirming,
            _ => rust_sync.MigrationPartState.scheduled,
          },
        ),
        broadcastedTxCount: 1,
        confirmedTxCount: 2,
      ),
    MigrationMobileStatusPhaseCase.needsRecovery => migrationPreviewStatus(
      phase: kIronwoodMigrationFailedRecoverablePhase,
      activeRunId: _migrationMobileRunId,
      targetValues: _migrationMobilePartValues,
      parts: parts(
        (index) => index == 0
            ? rust_sync.MigrationPartState.completed
            : rust_sync.MigrationPartState.scheduled,
      ),
      message: "Couldn't continue this migration. Try again.",
      confirmedTxCount: 1,
    ),
    MigrationMobileStatusPhaseCase.paused => migrationPreviewStatus(
      phase: kIronwoodMigrationPausedPhase,
      activeRunId: _migrationMobileRunId,
      targetValues: _migrationMobilePartValues,
      parts: parts(
        (index) => index < 2
            ? rust_sync.MigrationPartState.completed
            : rust_sync.MigrationPartState.scheduled,
      ),
      message: 'Migration stopped before its next transaction.',
      confirmedTxCount: 2,
    ),
    MigrationMobileStatusPhaseCase.complete => migrationPreviewStatus(
      phase: kIronwoodMigrationCompletePhase,
      targetValues: _migrationMobilePartValues,
      parts: parts((_) => rust_sync.MigrationPartState.completed),
      confirmedTxCount: _migrationMobilePartValues.length,
    ),
  };
}

rust_sync.OrchardMigrationPrivatePlan _migrationMobilePrivatePlan() {
  return rust_sync.OrchardMigrationPrivatePlan(
    targetValuesZatoshi: frb.Uint64List.fromList(_migrationMobilePartValues),
    totalInputZatoshi: BigInt.from(14223060000),
    totalMigratableZatoshi: BigInt.from(14223000000),
    denominationSplitFeeZatoshi: BigInt.from(30000),
    migrationFeeZatoshi: BigInt.from(30000),
    estimatedTotalFeeZatoshi: BigInt.from(60000),
    plannedBatchCount: _migrationMobilePartValues.length,
    denominationSplitStageCount: 2,
    denominationSplitLayerCount: 1,
    signingBatchLimit: 8,
    scheduleMeanDelayBlocks: 108,
    scheduleMaxDelayBlocks: 432,
    proofReadinessDelayBlocks: 24,
    estimatedProofReadyHeight: 3000240,
    scheduledTransfers: [
      for (var index = 0; index < _migrationMobilePartValues.length; index++)
        rust_sync.MigrationScheduledTransfer(
          partIndex: index,
          valueZatoshi: BigInt.from(_migrationMobilePartValues[index]),
          blockOffset: 18 * (index + 1),
        ),
    ],
  );
}

/// Migrating-step rows where the first row carries [status] and the rest walk
/// the normal run, so one row state is readable next to its neighbours.
List<MobileIronwoodMigrationPartPresentation> _migrationMobilePartPresentations(
  MobileIronwoodMigrationPartStatus status,
) {
  const labels = ['In 1 hour', 'In 2 hours', 'In 4 hours', 'In 6 hours'];
  return [
    for (var index = 0; index < _migrationMobilePartValues.length; index++)
      MobileIronwoodMigrationPartPresentation(
        label: 'Part ${index + 1}',
        status: index == 0
            ? status
            : index == 1
            ? MobileIronwoodMigrationPartStatus.complete
            : MobileIronwoodMigrationPartStatus.pending,
        detail:
            '${(_migrationMobilePartValues[index] / 100000000).toStringAsFixed(2)} ZEC',
        eta: index == 0 ? null : labels[(index - 1) % labels.length],
        valueZatoshi: BigInt.from(_migrationMobilePartValues[index]),
      ),
  ];
}

class _MigrationMobileQrPreview extends StatelessWidget {
  const _MigrationMobileQrPreview();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFFFFFFF),
      child: Center(child: AppIcon(AppIcons.qr, size: 128)),
    );
  }
}

class _MigrationMobileCameraPreview extends StatelessWidget {
  const _MigrationMobileCameraPreview();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Color(0xFF111111));
  }
}

// ===========================================================================
// Desktop private review, options selection and virtual unlock
// ===========================================================================

/// What the desktop private review step's plan resolves to, and what the
/// Start button does with it.
///
/// A missing plan and a failing plan render the same `_PrivateReviewUnavailable`
/// panel (`private_review.dart:156-168`), so they share one option.
enum MigrationPrivateReviewDataCase { unavailable, startFailure }

/// Which migration option the desktop options step has selected.
enum MigrationOptionSelectionCase { private, immediate }

/// Where the virtual unlock screen is in a password submit.
enum MigrationVirtualUnlockCase { idle, submitting, wrongPassword, policyError }

const _migrationPreviewUnlockPassword = 'preview-password-1';

/// The ASCII-only policy rejects this before the security provider is called,
/// which is the only state that reaches the charset message.
const _migrationPreviewNonAsciiPassword = '비밀번호';

/// The private review step driven by its plan provider instead of the
/// harness's canned plan.
Widget migrationPrivateReviewDataFixture({
  required MigrationPrivateReviewDataCase data,
}) {
  final startFailure = data == MigrationPrivateReviewDataCase.startFailure;
  return _migrationDesktopScope(
    inputs: _migrationInputs(),
    // `activeRunId` stays null, so the start path's "did it start anyway?"
    // check answers no and the error reaches the screen.
    statusGetter: _startableMigrationStatus,
    extraOverrides: [
      ironwoodMigrationAnalyzingMinimumDurationProvider.overrideWithValue(
        Duration.zero,
      ),
      if (!startFailure)
        ironwoodMigrationPrivatePlanProvider.overrideWith((ref) async => null),
    ],
    coordinator: startFailure ? _MigrationFailingStartCoordinator.new : null,
    child: _MigrationTapOnMount(
      keys: startFailure
          ? const [ValueKey('ironwood_migration_authorize_start_button')]
          : const [],
      child: _MigrationDesktopRouteHarness(
        location: '/migration/private/review',
        screen: IronwoodMigrationFlowScreen(
          step: IronwoodMigrationFlowStep.review,
          previewData: _migrationFlowData(),
          previewPrivatePlan: startFailure
              ? _migrationMobilePrivatePlan()
              : null,
          onOpenReleaseNotesOverride: _noopReleaseNotes,
        ),
      ),
    ),
  );
}

/// The options step with [selection] chosen; Immediate is reached by the
/// card's own tap callback, the only thing that moves the selection.
Widget migrationOptionsSelectionFixture({
  required MigrationOptionSelectionCase selection,
}) {
  return _migrationDesktopScope(
    inputs: _migrationInputs(),
    child: _MigrationTapOnMount(
      keys: selection == MigrationOptionSelectionCase.immediate
          ? const [ValueKey('ironwood_migration_fast_option')]
          : const [],
      child: _MigrationDesktopRouteHarness(
        location: '/migration/options',
        screen: IronwoodMigrationFlowScreen(
          step: IronwoodMigrationFlowStep.options,
          previewData: _migrationFlowData(),
          onOpenReleaseNotesOverride: _noopReleaseNotes,
        ),
      ),
    ),
  );
}

/// The virtual unlock screen mid-submit or after a rejected password.
///
/// The password field and submit callback are only reachable through
/// `DesktopUnlockContent`'s own props, so the driver fills the controller the
/// screen owns and calls its `onSubmit` rather than typing.
Widget migrationVirtualUnlockSubmitFixture({
  required MigrationVirtualUnlockCase state,
}) {
  return ProviderScope(
    overrides: [
      appSecurityProvider.overrideWith(
        () => _MigrationUnlockSecurityNotifier(
          confirms: state == MigrationVirtualUnlockCase.submitting
              // Never completes: the screen stays in its submitting state.
              ? Completer<bool>().future
              : Future<bool>.value(false),
        ),
      ),
    ],
    child: _MigrationUnlockSubmitOnMount(
      enabled: state != MigrationVirtualUnlockCase.idle,
      password: state == MigrationVirtualUnlockCase.policyError
          ? _migrationPreviewNonAsciiPassword
          : _migrationPreviewUnlockPassword,
      child: const WbDesktopWindowBox(
        child: IronwoodMigrationVirtualUnlockScreen(
          showMigrationInProgress: true,
        ),
      ),
    ),
  );
}

class _MigrationFailingStartCoordinator extends IronwoodMigrationCoordinator {
  @override
  IronwoodMigrationCoordinatorState build() =>
      const IronwoodMigrationCoordinatorState();

  @override
  Future<void> startSoftwareMigration({
    required String accountUuid,
    required List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
  }) async {
    throw StateError('Preview migration start failed.');
  }
}

class _MigrationUnlockSecurityNotifier extends AppSecurityNotifier {
  _MigrationUnlockSecurityNotifier({required this.confirms});

  final Future<bool> confirms;

  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: false);

  @override
  Future<bool> confirmPassword(String password) => confirms;
}

/// Invokes the keyed triggers' own callbacks one frame apart, which is how a
/// selection or a submit with no preview prop is reached.
class _MigrationTapOnMount extends StatefulWidget {
  const _MigrationTapOnMount({required this.keys, required this.child});

  final List<Key> keys;
  final Widget child;

  @override
  State<_MigrationTapOnMount> createState() => _MigrationTapOnMountState();
}

class _MigrationTapOnMountState extends State<_MigrationTapOnMount> {
  // The review step plays its analyzing-to-review transition first, so the
  // Start button only exists several frames in.
  static const _maxAttempts = 40;
  var _index = 0;
  var _attempts = 0;

  @override
  void initState() {
    super.initState();
    if (widget.keys.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _tapNext());
  }

  void _tapNext() {
    if (!mounted || _index >= widget.keys.length) return;
    final onTap = _callbackFor(widget.keys[_index]);
    if (onTap == null) {
      if (++_attempts >= _maxAttempts) return;
      // Nothing repainted, so the retry has to ask for the frame it waits on.
      WidgetsBinding.instance.addPostFrameCallback((_) => _tapNext());
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    _index++;
    _attempts = 0;
    onTap();
    if (_index >= widget.keys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _tapNext());
  }

  VoidCallback? _callbackFor(Key key) {
    final target = _findByKey(context, key);
    if (target == null) return null;
    final self = target.widget;
    if (self is GestureDetector && self.onTap != null) return self.onTap;
    if (self is AppButton) return self.onPressed;

    VoidCallback? onTap;
    void findDetector(Element element) {
      if (onTap != null) return;
      final child = element.widget;
      if (child is AppButton && child.onPressed != null) {
        onTap = child.onPressed;
        return;
      }
      if (child is GestureDetector && child.onTap != null) {
        onTap = child.onTap;
        return;
      }
      element.visitChildren(findDetector);
    }

    target.visitChildren(findDetector);
    return onTap;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Fills the unlock screen's own password controller and calls its submit.
class _MigrationUnlockSubmitOnMount extends StatefulWidget {
  const _MigrationUnlockSubmitOnMount({
    required this.enabled,
    required this.password,
    required this.child,
  });

  final bool enabled;
  final String password;
  final Widget child;

  @override
  State<_MigrationUnlockSubmitOnMount> createState() =>
      _MigrationUnlockSubmitOnMountState();
}

class _MigrationUnlockSubmitOnMountState
    extends State<_MigrationUnlockSubmitOnMount> {
  static const _maxAttempts = 8;
  var _attempts = 0;
  var _done = false;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
  }

  void _submit() {
    if (_done || !mounted) return;
    DesktopUnlockContent? content;
    void find(Element element) {
      if (content != null) return;
      final child = element.widget;
      if (child is DesktopUnlockContent) {
        content = child;
        return;
      }
      element.visitChildren(find);
    }

    context.visitChildElements(find);
    final found = content;
    if (found == null) {
      if (++_attempts >= _maxAttempts) return;
      // Nothing repainted, so the retry has to ask for the frame it waits on.
      WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    _done = true;
    found.passwordController.text = widget.password;
    found.onChanged();
    unawaited(found.onSubmit());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Element? _findByKey(BuildContext context, Key key) {
  Element? target;
  void visit(Element element) {
    if (target != null) return;
    if (element.widget.key == key) {
      target = element;
      return;
    }
    element.visitChildren(visit);
  }

  context.visitChildElements(visit);
  return target;
}
