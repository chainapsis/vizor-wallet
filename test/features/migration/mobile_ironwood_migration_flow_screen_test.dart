@Tags(['mobile'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_loading_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_profile_picture.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/migration/models/mobile_ironwood_migration_attention_state.dart';
import 'package:zcash_wallet/src/features/migration/screens/ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/features/migration/screens/mobile/mobile_ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_background_credential_store.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_service.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_pczt_qr_stage.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_qr_scanner_card.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/keystone.dart' as rust_keystone;
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/rust/wallet/keystone.dart'
    as rust_keystone_wallet;
import 'package:zcash_wallet/src/services/qr_scanner.dart';

import '../../fakes/fake_sync_notifier.dart';

final _rustApiFake = _RustApiFake();

class _RustApiFake implements RustLibApi {
  final encodedRequestIds = <String>[];
  final encodedMaxFragmentLengths = <BigInt>[];
  final decodedRequestIds = <String>[];

  void reset() {
    encodedRequestIds.clear();
    encodedMaxFragmentLengths.clear();
    decodedRequestIds.clear();
  }

  @override
  void crateApiKeystoneResetUrSession() {}

  @override
  Future<List<String>> crateApiKeystoneEncodeZcashSignBatchUrParts({
    required String requestId,
    required List<rust_keystone_wallet.ZcashBatchMessageInput> messages,
    required BigInt maxFragmentLen,
  }) async {
    encodedRequestIds.add(requestId);
    encodedMaxFragmentLengths.add(maxFragmentLen);
    return ['UR:ZCASH-SIGN-BATCH/$requestId'];
  }

  @override
  Future<rust_keystone.KeystoneSigResult>
  crateApiKeystoneDecodeZcashBatchSignResponse({
    required List<int> cbor,
    required String expectedRequestId,
    required List<String> messageIds,
  }) async {
    decodedRequestIds.add(expectedRequestId);
    return rust_keystone.KeystoneSigResult(
      firmwareVersion: Uint8List.fromList([1, 0, 0]),
      requestId: Uint8List.fromList(utf8.encode(expectedRequestId)),
      results: [
        for (final messageId in messageIds)
          rust_keystone.KeystoneMsgSig(
            messageId: Uint8List.fromList(utf8.encode(messageId)),
            sigs: [
              rust_keystone.KeystoneActionSig(
                pool: 0,
                actionIndex: 0,
                sig: Uint8List(64),
              ),
            ],
          ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingBindCredentialStore
    extends IronwoodMigrationBackgroundCredentialStore {
  _FailingBindCredentialStore({
    required this.failAtBindCall,
    String? initialRunId,
  }) : _manifest = _manifestFor(initialRunId);

  final int failAtBindCall;
  IronwoodMigrationBackgroundCredentialManifest _manifest;
  int bindCallCount = 0;

  static IronwoodMigrationBackgroundCredentialManifest _manifestFor(
    String? runId,
  ) {
    return IronwoodMigrationBackgroundCredentialManifest(
      version: 1,
      network: 'main',
      accountUuid: 'account-1',
      dbPath: '/tmp/wallet.db',
      lightwalletdUrl: defaultRpcEndpointConfig(
        'main',
      ).normalizedLightwalletdUrl,
      credentialHex: List.filled(64, '0').join(),
      saltBase64: 'AAAAAAAAAAAAAAAAAAAAAA==',
      expectedRunId: runId,
    );
  }

  @override
  Future<IronwoodMigrationBackgroundCredentialManifest> prepare({
    required String network,
    required String accountUuid,
    required String dbPath,
    required String lightwalletdUrl,
  }) async {
    _manifest = _manifestFor(null);
    return _manifest;
  }

  @override
  Future<IronwoodMigrationBackgroundCredentialManifest?> read({
    required String network,
    required String accountUuid,
  }) async {
    return _manifest;
  }

  @override
  Future<bool> bindExpectedRunId({
    required String network,
    required String accountUuid,
    required String expectedRunId,
  }) async {
    bindCallCount++;
    if (bindCallCount == failAtBindCall) {
      throw StateError('Injected credential reconciliation failure.');
    }
    if (_manifest.expectedRunId == expectedRunId) return false;
    _manifest = _manifest.bindToRun(expectedRunId);
    return true;
  }
}

class _HardwareAccountNotifier extends AccountNotifier {
  @override
  Future<AccountState> build() async =>
      _bootstrap(hardware: true).initialAccountState;
}

class _StartScreenTestMigrationCoordinator
    extends IronwoodMigrationCoordinator {
  _StartScreenTestMigrationCoordinator(this.onStart);

  final Future<void> Function(
    String accountUuid,
    List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
  )
  onStart;

  @override
  IronwoodMigrationCoordinatorState build() =>
      const IronwoodMigrationCoordinatorState();

  @override
  Future<void> startSoftwareMigration({
    required String accountUuid,
    required List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
  }) => onStart(accountUuid, approvedSchedule);

  @override
  Future<void> refreshNow({bool forceAdvance = false}) async {}
}

class _RecoveryScreenTestMigrationCoordinator
    extends IronwoodMigrationCoordinator {
  int recoveryCount = 0;

  @override
  IronwoodMigrationCoordinatorState build() {
    return const IronwoodMigrationCoordinatorState(
      errors: {
        'account-1':
            'Bad state: Ironwood migration credential is missing for the '
            'active run. Vizor will only continue transactions preserved in '
            'the verified iOS outbox.',
      },
    );
  }

  @override
  Future<void> recover(String accountUuid) async {
    recoveryCount++;
    state = state.copyWith(
      errors: Map<String, String>.from(state.errors)..remove(accountUuid),
    );
  }

  @override
  Future<void> refreshNow({bool forceAdvance = false}) async {}
}

class _ErrorScreenTestMigrationCoordinator
    extends IronwoodMigrationCoordinator {
  int retryCount = 0;

  @override
  IronwoodMigrationCoordinatorState build() {
    return const IronwoodMigrationCoordinatorState(
      errors: {'account-1': 'Temporary migration failure.'},
    );
  }

  @override
  Future<void> retry(
    String accountUuid, {
    rust_sync.MigrationStatus? status,
  }) async {
    retryCount++;
    state = state.copyWith(
      errors: Map<String, String>.from(state.errors)..remove(accountUuid),
    );
  }

  @override
  Future<void> refreshNow({bool forceAdvance = false}) async {}
}

class _EntrySyncErrorTestMigrationCoordinator
    extends IronwoodMigrationCoordinator {
  int synchronizeCount = 0;
  int refreshCount = 0;

  @override
  IronwoodMigrationCoordinatorState build() {
    return const IronwoodMigrationCoordinatorState();
  }

  @override
  Future<void> synchronizeAndReconcileAfterReentry() async {
    synchronizeCount++;
    throw StateError('Foreground migration sync failed.');
  }

  @override
  Future<void> refreshNow({bool forceAdvance = false}) async {
    refreshCount++;
  }
}

class _SuccessfulEntrySyncTestMigrationCoordinator
    extends IronwoodMigrationCoordinator {
  int synchronizeCount = 0;
  int refreshCount = 0;

  @override
  IronwoodMigrationCoordinatorState build() {
    return const IronwoodMigrationCoordinatorState();
  }

  @override
  Future<void> synchronizeAndReconcileAfterReentry() async {
    synchronizeCount++;
  }

  @override
  Future<void> refreshNow({bool forceAdvance = false}) async {
    refreshCount++;
  }
}

class _ProofPermitTestMigrationCoordinator
    extends IronwoodMigrationCoordinator {
  int refreshCount = 0;

  IronwoodMigrationCoordinatorState get exposedState => state;

  @override
  IronwoodMigrationCoordinatorState build() {
    return const IronwoodMigrationCoordinatorState(
      foregroundProgressPermits: {'account-1'},
      childProofBatchPermits: {'account-1'},
    );
  }

  @override
  Future<void> refreshNow({bool forceAdvance = false}) async {
    refreshCount++;
  }
}

class _ControlledRefreshTestMigrationCoordinator
    extends IronwoodMigrationCoordinator {
  final List<Completer<void>> refreshes = [];

  @override
  IronwoodMigrationCoordinatorState build() {
    return const IronwoodMigrationCoordinatorState();
  }

  @override
  Future<void> refreshNow({bool forceAdvance = false}) async {
    final refresh = Completer<void>();
    refreshes.add(refresh);
    await refresh.future;
    if (ref.mounted) {
      ref.invalidate(ironwoodMigrationRouteCtaProvider);
    }
  }
}

class _PreparationHandoffTestMigrationCoordinator
    extends IronwoodMigrationCoordinator {
  _PreparationHandoffTestMigrationCoordinator({this.failRetry = false});

  final bool failRetry;
  int retryCount = 0;

  @override
  IronwoodMigrationCoordinatorState build() {
    return const IronwoodMigrationCoordinatorState();
  }

  @override
  Future<void> retry(
    String accountUuid, {
    rust_sync.MigrationStatus? status,
  }) async {
    retryCount++;
    if (failRetry) {
      state = state.copyWith(
        errors: {...state.errors, accountUuid: 'Foreground handoff failed.'},
      );
      return;
    }
    state = state.copyWith(
      foregroundProgressPermits: {
        ...state.foregroundProgressPermits,
        accountUuid,
      },
      errors: Map<String, String>.from(state.errors)..remove(accountUuid),
    );
  }
}

/// A coordinator that reports an advance already in flight for the test
/// account, so the status screen renders its "keep Vizor open" state.
class _AdvancingTestMigrationCoordinator extends IronwoodMigrationCoordinator {
  @override
  IronwoodMigrationCoordinatorState build() {
    return const IronwoodMigrationCoordinatorState(
      advancingAccounts: {'account-1'},
    );
  }
}

class _DurablePhaseRetryTestMigrationCoordinator
    extends IronwoodMigrationCoordinator {
  int retryCount = 0;

  @override
  IronwoodMigrationCoordinatorState build() {
    return const IronwoodMigrationCoordinatorState();
  }

  @override
  Future<void> retry(
    String accountUuid, {
    rust_sync.MigrationStatus? status,
  }) async {
    retryCount++;
  }
}

final _data = IronwoodMigrationFlowData(
  amountZatoshi: BigInt.from(14_223_000_000),
  accountName: 'Wallet 1',
  profilePictureId: 'default',
);

rust_sync.OrchardMigrationPrivatePlan _planWith({
  int plannedBatchCount = 12,
  int denominationSplitStageCount = 1,
  int? denominationSplitLayerCount,
  int signingBatchLimit = 12,
  int blockOffsetAdjustment = 0,
  int proofReadinessDelayBlocks = 146,
  int? estimatedProofReadyHeight = 290,
}) => rust_sync.OrchardMigrationPrivatePlan(
  targetValuesZatoshi: frb.Uint64List.fromList([]),
  totalInputZatoshi: BigInt.from(14_223_000_000),
  totalMigratableZatoshi: BigInt.from(14_220_000_000),
  orchardChangeZatoshi: BigInt.from(90_000),
  denominationSplitFeeZatoshi: BigInt.from(20_000),
  migrationFeeZatoshi: BigInt.from(14_400_000),
  estimatedTotalFeeZatoshi: BigInt.from(14_420_000),
  plannedBatchCount: plannedBatchCount,
  denominationSplitStageCount: denominationSplitStageCount,
  denominationSplitLayerCount:
      denominationSplitLayerCount ?? denominationSplitStageCount,
  signingBatchLimit: signingBatchLimit,
  scheduleMeanDelayBlocks: 144,
  scheduleMaxDelayBlocks: 576,
  proofReadinessDelayBlocks: proofReadinessDelayBlocks,
  estimatedProofReadyHeight: estimatedProofReadyHeight,
  scheduledTransfers: [
    for (var i = 0; i < plannedBatchCount; i++)
      rust_sync.MigrationScheduledTransfer(
        partIndex: i,
        valueZatoshi: BigInt.from(
          i == plannedBatchCount - 1 ? 3_220_000_000 : 1_000_000_000,
        ),
        blockOffset: i == 0 ? 0 : i * 144 + blockOffsetAdjustment,
      ),
  ],
);

rust_sync.OrchardMigrationPrivatePlan get _plan => _planWith();

final _immediatePlan = rust_sync.OrchardMigrationImmediatePlan(
  totalInputZatoshi: BigInt.from(14_223_000_000),
  feeZatoshi: BigInt.from(60_000),
  migratedZatoshi: BigInt.from(14_222_940_000),
  inputNoteCount: 12,
);

rust_sync.MigrationStatus _status({
  required String phase,
  String? activeRunId = 'run-1',
  List<String>? broadcastStatuses,
  List<rust_sync.MigrationPartStatus> parts = const [],
  List<int> targetValues = const [412_000_000, 412_000_000, 412_000_000],
  int? nextActionHeight,
  bool? proofReady = true,
  int? estimatedCompletionHeight,
  int? nextActionPartIndex,
  List<int>? currentSigningPartIndices,
  List<rust_sync.MigrationPreparationTransactionStatus>?
  preparationTransactions,
  int pendingTxCount = 2,
  int broadcastedTxCount = 1,
  int confirmedTxCount = 1,
  int signedChildPcztCount = 0,
  int pendingSplitStageCount = 2,
  String? message,
  List<rust_sync.MigrationScheduledBroadcast>? scheduledBroadcasts,
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    activeRunId: activeRunId,
    targetValuesZatoshi: frb.Uint64List.fromList(targetValues),
    preparedNoteCount: 3,
    denominationConfirmationCount: 2,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 3,
    pendingTxCount: pendingTxCount,
    broadcastedTxCount: broadcastedTxCount,
    confirmedTxCount: confirmedTxCount,
    totalCount: 3,
    signedChildPcztCount: signedChildPcztCount,
    pendingSplitStageCount: pendingSplitStageCount,
    canAbandon: false,
    signingBatchLimit: 12,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    nextActionHeight: nextActionHeight,
    proofReady: proofReady,
    estimatedCompletionHeight: estimatedCompletionHeight,
    nextActionPartIndex: nextActionPartIndex,
    currentSigningPartIndices: currentSigningPartIndices == null
        ? null
        : frb.Uint32List.fromList(currentSigningPartIndices),
    message: message,
    preparationTransactions: preparationTransactions,
    scheduledBroadcasts:
        scheduledBroadcasts ??
        (broadcastStatuses == null
            ? const []
            : [
                for (var index = 0; index < broadcastStatuses.length; index++)
                  rust_sync.MigrationScheduledBroadcast(
                    txidHex: 'tx-$index',
                    valueZatoshi: BigInt.from(412_000_000),
                    scheduledAtMs: DateTime(
                      2026,
                      7,
                      20,
                      10,
                    ).millisecondsSinceEpoch,
                    scheduledHeight: 3_000_000 + index,
                    status: broadcastStatuses[index],
                  ),
              ]),
    parts: parts,
  );
}

rust_sync.MigrationStatus _visualMigrationStatus() {
  final scheduledAt = DateTime(2026, 7, 18, 12).millisecondsSinceEpoch;
  const values = [
    412_000_000,
    412_000_000,
    412_000_000,
    412_000_000,
    412_000_000,
    412_000_000,
    2_000_000_000,
    2_000_000_000,
    2_000_000_000,
    2_000_000_000,
    2_000_000_000,
    1_876_000_000,
  ];
  return rust_sync.MigrationStatus(
    phase: kIronwoodMigrationWaitingConfirmationsPhase,
    activeRunId: 'visual-run',
    targetValuesZatoshi: frb.Uint64List.fromList(values),
    preparedNoteCount: 12,
    denominationConfirmationCount: 3,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 1,
    pendingTxCount: 9,
    broadcastedTxCount: 3,
    confirmedTxCount: 3,
    totalCount: 12,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 12,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    scheduledBroadcasts: [
      for (var i = 0; i < values.length; i++)
        rust_sync.MigrationScheduledBroadcast(
          txidHex: 'visual-$i',
          valueZatoshi: BigInt.from(values[i]),
          scheduledAtMs: scheduledAt,
          scheduledHeight: 3_000_000 + (i + 1) * 144,
          status: switch (i) {
            0 => 'confirmed',
            1 => 'needs_input',
            2 => 'broadcasted',
            _ => 'scheduled',
          },
        ),
    ],
    parts: const [],
  );
}

AppBootstrapState _bootstrap({bool hardware = false}) => AppBootstrapState(
  initialLocation: '/migration/private/status',
  initialAccountState: AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Wallet 1',
        order: 0,
        profilePictureId: kDefaultProfilePictureId,
        isHardware: hardware,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1testaddress',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

Widget _app({
  required MobileIronwoodMigrationStep step,
  AppThemeData theme = AppThemeData.light,
  rust_sync.MigrationStatus? previewStatus,
  rust_sync.OrchardMigrationPrivatePlan? previewPlan,
  rust_sync.OrchardMigrationImmediatePlan? previewImmediatePlan,
  MobileIronwoodMigrationPreviewSurface? previewSurface,
  bool? privateMigrationSupported,
  bool disableAnimations = true,
}) {
  late final GoRouter router;
  MobileIronwoodMigrationFlowScreen screen(MobileIronwoodMigrationStep value) {
    return MobileIronwoodMigrationFlowScreen(
      step: value,
      previewData: _data,
      previewPrivatePlan: previewPlan ?? _plan,
      previewImmediatePlan: previewImmediatePlan ?? _immediatePlan,
      previewStatus: previewStatus,
      previewSurface: previewSurface,
      privateMigrationSupported: privateMigrationSupported,
    );
  }

  router = GoRouter(
    initialLocation: switch (step) {
      MobileIronwoodMigrationStep.intro => '/migration/intro',
      MobileIronwoodMigrationStep.howItWorks => '/migration/how-it-works',
      MobileIronwoodMigrationStep.options => '/migration/options',
      MobileIronwoodMigrationStep.notifications =>
        '/migration/private/notifications',
      MobileIronwoodMigrationStep.fastReview => '/migration/fast/review',
      MobileIronwoodMigrationStep.preparing => '/migration/private/preparing',
      MobileIronwoodMigrationStep.migrating => '/migration/private/status',
    },
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      GoRoute(
        path: '/migration/intro',
        builder: (_, _) => screen(MobileIronwoodMigrationStep.intro),
      ),
      GoRoute(
        path: '/migration/how-it-works',
        builder: (_, _) => screen(MobileIronwoodMigrationStep.howItWorks),
      ),
      GoRoute(
        path: '/migration/options',
        builder: (_, _) => screen(MobileIronwoodMigrationStep.options),
      ),
      GoRoute(
        path: '/migration/private/notifications',
        builder: (_, _) => screen(MobileIronwoodMigrationStep.notifications),
      ),
      GoRoute(
        path: '/migration/fast/review',
        builder: (_, _) => screen(MobileIronwoodMigrationStep.fastReview),
      ),
      GoRoute(
        path: '/migration/private/preparing',
        builder: (_, _) => screen(MobileIronwoodMigrationStep.preparing),
      ),
      GoRoute(
        path: '/migration/private/status',
        builder: (_, _) => screen(MobileIronwoodMigrationStep.migrating),
      ),
      GoRoute(
        path: '/migration/private/schedule',
        builder: (_, _) =>
            MobileIronwoodMigrationScheduleScreen(previewStatus: previewStatus),
      ),
      GoRoute(
        path: '/migration/private/preparation-schedule',
        builder: (_, _) => MobileIronwoodMigrationPreparationScheduleScreen(
          previewStatus: previewStatus,
        ),
      ),
    ],
  );

  return ProviderScope(
    child: AppTheme(
      data: theme,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
      ),
    ),
  );
}

Widget _productionApp({
  required String initialLocation,
  required IronwoodMigrationService migrationService,
  rust_sync.MigrationStatus? status,
  rust_sync.MigrationStatus? startedStatus,
  Future<rust_sync.MigrationStatus> Function()? statusLoader,
  IronwoodHomeMigrationCtaState Function()? ctaBuilder,
  Future<IronwoodHomeMigrationCtaState> Function()? ctaLoader,
  bool hardware = false,
  rust_sync.OrchardMigrationPrivatePlan? privatePlan,
  Future<rust_sync.OrchardMigrationPrivatePlan?>? privatePlanFuture,
  Future<rust_sync.OrchardMigrationPrivatePlan?> Function()? privatePlanLoader,
  SyncState? syncState,
  FakeSyncNotifier? syncNotifier,
  IronwoodMigrationCoordinator Function()? migrationCoordinator,
  bool realKeystoneCombinedRoute = false,
  bool realKeystoneDenominationRoute = false,
  bool realKeystoneBatchRoute = false,
  bool disableAnimations = true,
  VoidCallback? onKeystoneCombinedRouteBuilt,
  VoidCallback? onKeystoneDenominationRouteBuilt,
  List<Override> extraOverrides = const [],
}) {
  final cta = status == null
      ? const IronwoodHomeMigrationCtaState.start(
          network: 'main',
          accountUuid: 'account-1',
        )
      : IronwoodHomeMigrationCtaState.resume(
          network: 'main',
          accountUuid: 'account-1',
          status: status,
        );
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      GoRoute(
        path: '/migration/cta-prime',
        builder: (_, _) => const _RouteCtaPrimeScreen(),
      ),
      GoRoute(
        path: '/migration/intro',
        builder: (_, _) => const Text('intro route'),
      ),
      GoRoute(
        path: '/migration/options',
        builder: (_, _) => const MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.options,
        ),
      ),
      GoRoute(
        path: '/migration/private/notifications',
        builder: (_, state) => MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.notifications,
          previewPrivatePlan: switch (state.extra) {
            rust_sync.OrchardMigrationPrivatePlan plan => plan,
            _ => privatePlan,
          },
        ),
      ),
      GoRoute(
        path: '/migration/private/start',
        builder: (_, state) => MobileIronwoodMigrationStartScreen(
          approvedPlan: switch (state.extra) {
            rust_sync.OrchardMigrationPrivatePlan plan => plan,
            _ => null,
          },
        ),
      ),
      GoRoute(
        path: '/migration/fast/review',
        builder: (_, _) => const MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.fastReview,
        ),
      ),
      GoRoute(
        path: '/migration/immediate/keystone/sign',
        builder: (_, state) {
          final plan = state.extra! as rust_sync.OrchardMigrationImmediatePlan;
          return Text('keystone immediate sign route:${plan.migratedZatoshi}');
        },
      ),
      GoRoute(
        path: '/migration/complete',
        builder: (_, _) => const MobileIronwoodMigrationCompleteScreen(),
      ),
      GoRoute(
        path: '/migration/private/status',
        builder: (_, _) => MobileIronwoodMigrationPrivateStatusScreen(
          approvedPlan: privatePlan,
        ),
      ),
      GoRoute(
        path: '/migration/private/schedule',
        builder: (_, _) =>
            MobileIronwoodMigrationScheduleScreen(previewStatus: status),
      ),
      GoRoute(
        path: '/migration/private/preparation-schedule',
        builder: (_, _) => MobileIronwoodMigrationPreparationScheduleScreen(
          previewStatus: status,
        ),
      ),
      GoRoute(
        path: '/migration/private/keystone/sign',
        builder: (_, state) {
          onKeystoneCombinedRouteBuilt?.call();
          final entry = switch (state.extra) {
            MobileIronwoodMigrationKeystoneCombinedSignEntry value => value,
            _ => null,
          };
          final schedule = switch (state.extra) {
            List<rust_sync.MigrationScheduledTransfer> value => value,
            _ => entry?.approvedSchedule ?? const [],
          };
          return realKeystoneCombinedRoute
              ? MobileIronwoodMigrationKeystoneCombinedSignScreen(
                  approvedSchedule: schedule,
                  initialRequest: entry?.request,
                  initialAccountUuid: entry?.accountUuid,
                )
              : Text('keystone combined sign route:${schedule.length}');
        },
      ),
      GoRoute(
        path: '/migration/private/keystone/denominations/sign',
        builder: (_, state) {
          onKeystoneDenominationRouteBuilt?.call();
          final entry = switch (state.extra) {
            MobileIronwoodMigrationKeystoneDenominationSignEntry value => value,
            _ => null,
          };
          return realKeystoneDenominationRoute
              ? MobileIronwoodMigrationKeystoneDenominationSignScreen(
                  approvedSchedule: switch (state.extra) {
                    List<rust_sync.MigrationScheduledTransfer> schedule =>
                      schedule,
                    _ => entry?.approvedSchedule ?? const [],
                  },
                  initialRequest: entry?.request,
                  initialAccountUuid: entry?.accountUuid,
                )
              : const Text('keystone denomination sign route');
        },
      ),
      GoRoute(
        path: '/migration/private/keystone/batch/sign',
        builder: (_, _) => realKeystoneBatchRoute
            ? const MobileIronwoodMigrationKeystoneBatchSignScreen()
            : const Text('keystone batch sign route'),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      ...extraOverrides,
      appBootstrapProvider.overrideWithValue(_bootstrap(hardware: hardware)),
      if (hardware) accountProvider.overrideWith(_HardwareAccountNotifier.new),
      syncProvider.overrideWith(
        () =>
            syncNotifier ??
            FakeSyncNotifier(
              syncState ??
                  SyncState(
                    accountUuid: 'account-1',
                    hasAccountScopedData: true,
                    isSyncComplete: true,
                  ),
            ),
      ),
      ironwoodMigrationFlowDataProvider.overrideWith((ref) => _data),
      ironwoodMigrationPrivatePlanProvider.overrideWith(
        (ref) =>
            privatePlanLoader?.call() ??
            privatePlanFuture ??
            Future.value(privatePlan ?? _plan),
      ),
      ironwoodMigrationImmediatePlanProvider.overrideWith(
        (ref) => Future.value(_immediatePlan),
      ),
      ironwoodMigrationRouteCtaProvider.overrideWith((ref) async {
        if (ctaLoader != null) return ctaLoader();
        return ctaBuilder?.call() ?? cta;
      }),
      ironwoodMigrationStatusProvider.overrideWith(
        (ref, request) async =>
            await statusLoader?.call() ??
            startedStatus ??
            status ??
            _status(phase: kIronwoodMigrationWaitingDenomConfirmationsPhase),
      ),
      ironwoodMigrationServiceProvider.overrideWithValue(migrationService),
      if (migrationCoordinator != null)
        ironwoodMigrationCoordinatorProvider.overrideWith(migrationCoordinator),
    ],
    child: AppTheme(
      data: AppThemeData.light,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
      ),
    ),
  );
}

class _RouteCtaPrimeScreen extends ConsumerWidget {
  const _RouteCtaPrimeScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cta = ref.watch(ironwoodMigrationRouteCtaProvider);
    return cta.when(
      data: (_) => TextButton(
        key: const ValueKey('open_migration_options'),
        onPressed: () => context.go('/migration/options'),
        child: const Text('Open migration options'),
      ),
      error: (_, _) => const Text('route CTA error'),
      loading: () => const CircularProgressIndicator(),
    );
  }
}

IronwoodMigrationService _migrationService({
  Future<rust_sync.MigrationStatus> Function()? onGetStatus,
  Future<rust_sync.IronwoodMigrationResult> Function(
    String accountUuid,
    List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
  )?
  onStart,
  Future<rust_sync.IronwoodMigrationResult> Function(String accountUuid)?
  onContinue,
  bool ios = false,
  IronwoodMigrationNotificationAuthorizationStatusGetter?
  getNotificationAuthorizationStatus,
  IronwoodMigrationNotificationAuthorizationRequester?
  requestNotificationAuthorization,
  IronwoodMigrationNotificationSettingsOpener? openNotificationSettings,
  IronwoodMigrationPreparationRuntimeStateGetter? getPreparationRuntimeState,
  IronwoodMigrationPreparationForegroundContinuationAcknowledger?
  acknowledgePreparationForegroundContinuation,
  Future<rust_sync.OrchardMigrationPrivatePlan?> Function()? onGetPrivatePlan,
  Future<rust_sync.KeystoneMigrationSigningRequest> Function(
    String accountUuid,
  )?
  onPrepareKeystoneDenominations,
  Future<rust_sync.IronwoodMigrationResult> Function(
    String accountUuid,
    List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
  )?
  onCompleteKeystoneDenominations,
  Future<rust_sync.KeystoneMigrationSigningRequest> Function(
    String accountUuid,
    List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
  )?
  onPrepareKeystoneSingleQr,
  Future<rust_sync.IronwoodMigrationResult> Function(
    String accountUuid,
    String requestId,
  )?
  onCompleteKeystoneSingleQr,
  Future<String> Function(
    String accountUuid,
    List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
  )?
  onCreatePrivateDraft,
}) {
  return IronwoodMigrationService(
    getWalletDbPath: () async => '/tmp/wallet.db',
    getStatus:
        ({required dbPath, required network, required accountUuid}) async =>
            await onGetStatus?.call() ??
            _status(phase: kIronwoodMigrationWaitingDenomConfirmationsPhase),
    getPrivatePlan:
        ({required dbPath, required network, required accountUuid}) async =>
            await onGetPrivatePlan?.call() ?? _plan,
    getImmediatePlan:
        ({required dbPath, required network, required accountUuid}) async =>
            _immediatePlan,
    secureStore: AppSecureStore.testing(storage: const FlutterSecureStorage()),
    getEndpoint: () => defaultRpcEndpointConfig('main'),
    getSessionPassword: () => 'test-password',
    getMnemonicBytesForAccount: (_) async => [1, 2, 3],
    isMacOS: () => false,
    isIOS: () => ios,
    // These screen tests exercise routing and presentation, not the native
    // iOS outbox credential contract. Credential behavior has dedicated
    // service tests.
    isMobile: () => false,
    supportsBackgroundMigration: () => true,
    getNotificationAuthorizationStatus:
        getNotificationAuthorizationStatus ??
        () async => IronwoodMigrationNotificationAuthorizationStatus.denied,
    requestNotificationAuthorization:
        requestNotificationAuthorization ?? () async => false,
    openNotificationSettings: openNotificationSettings ?? () async => false,
    getPreparationRuntimeState:
        getPreparationRuntimeState ??
        ({required network, required accountUuid, required runId}) async =>
            IronwoodMigrationPreparationRuntimeState.idle,
    acknowledgePreparationForegroundContinuation:
        acknowledgePreparationForegroundContinuation ??
        ({required network, required accountUuid, required runId}) async {},
    startSoftwareMigration:
        ({
          required dbPath,
          required lightwalletdUrl,
          required network,
          required accountUuid,
          required mnemonicBytes,
          required password,
          required saltBase64,
          required approvedSchedule,
        }) =>
            onStart?.call(accountUuid, approvedSchedule) ??
            Future.value(_migrationResult()),
    prepareKeystoneDenominationMigration:
        ({required dbPath, required network, required accountUuid}) =>
            onPrepareKeystoneDenominations?.call(accountUuid) ??
            Future.value(_keystoneDenominationRequest()),
    completeKeystoneDenominationMigration:
        ({
          required dbPath,
          required lightwalletdUrl,
          required network,
          required accountUuid,
          required requestId,
          required signedMessages,
          required password,
          required saltBase64,
          required approvedSchedule,
        }) =>
            onCompleteKeystoneDenominations?.call(
              accountUuid,
              approvedSchedule,
            ) ??
            Future.value(_migrationResult()),
    prepareKeystoneSingleQrMigration:
        ({
          required dbPath,
          required network,
          required accountUuid,
          required approvedSchedule,
        }) =>
            onPrepareKeystoneSingleQr?.call(accountUuid, approvedSchedule) ??
            Future.value(_keystoneDenominationRequest()),
    completeKeystoneSingleQrMigration:
        ({
          required dbPath,
          required lightwalletdUrl,
          required network,
          required accountUuid,
          required requestId,
          required signedMessages,
          required password,
          required saltBase64,
        }) =>
            onCompleteKeystoneSingleQr?.call(accountUuid, requestId) ??
            Future.value(_migrationResult()),
    createPrivateMigrationDraft:
        ({
          required dbPath,
          required network,
          required accountUuid,
          required approvedSchedule,
        }) =>
            onCreatePrivateDraft?.call(accountUuid, approvedSchedule) ??
            Future.value('private-draft-run'),
    getKeystoneProofStatus: ({required requestId}) async =>
        const rust_sync.KeystoneMigrationProofStatus(
          readyCount: 1,
          totalCount: 1,
          isReady: true,
          isFailed: false,
        ),
    discardKeystoneMigrationRequest: ({required requestId}) async {},
    broadcastDueMigration:
        ({
          required dbPath,
          required lightwalletdUrl,
          required network,
          required accountUuid,
          required password,
          required saltBase64,
        }) => onContinue?.call(accountUuid) ?? Future.value(_migrationResult()),
    scheduleBackgroundMigration: () async => true,
  );
}

rust_sync.KeystoneMigrationSigningRequest _keystoneDenominationRequest() {
  return rust_sync.KeystoneMigrationSigningRequest(
    requestId: 'denomination-request',
    messages: [
      rust_sync.KeystoneMigrationMessage(
        id: 'split-1',
        redactedPczt: Uint8List.fromList([1, 2, 3]),
      ),
    ],
    signingBatchLimit: 50,
  );
}

rust_sync.IronwoodMigrationResult _migrationResult() {
  return rust_sync.IronwoodMigrationResult(
    txids: 'txid',
    status: 'broadcasted',
    broadcastedCount: 1,
    totalCount: 3,
    feeZatoshi: BigInt.from(10_000),
    migratedZatoshi: BigInt.from(4_120_000_000),
  );
}

void _useMobileViewport(
  WidgetTester tester, {
  Size size = const Size(393, 852),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  test('private migration remains available outside Android', () {
    expect(supportsPrivateMobileIronwoodMigration(isAndroid: false), isTrue);
    expect(supportsPrivateMobileIronwoodMigration(isAndroid: true), isFalse);
  });

  setUpAll(() {
    RustLib.initMock(api: _rustApiFake);
  });

  tearDownAll(RustLib.dispose);

  setUp(() {
    _rustApiFake.reset();
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('connects the About and migration-steps screens', (tester) async {
    await tester.pumpWidget(_app(step: MobileIronwoodMigrationStep.intro));
    await tester.pumpAndSettle();

    expect(find.text('Zcash Network Update'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_wordmark')),
      findsOneWidget,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_ironwood_legacy_connection_dot')),
      ),
      const Size.square(16),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_ironwood_target_connection_dot')),
      ),
      const Size.square(16),
    );
    final profilePictures = find.byType(AppProfilePicture);
    expect(profilePictures, findsNWidgets(2));
    expect(
      tester
              .getCenter(
                find.byKey(
                  const ValueKey('mobile_ironwood_legacy_connection_dot'),
                ),
              )
              .dy -
          tester.getCenter(profilePictures.first).dy,
      5,
    );
    expect(
      tester
              .getCenter(
                find.byKey(
                  const ValueKey('mobile_ironwood_target_connection_dot'),
                ),
              )
              .dy -
          tester.getCenter(profilePictures.last).dy,
      5,
    );
    expect(find.text('A new shielded pool for Zcash.'), findsOneWidget);
    expect(find.text('Official release note'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('How Migration Works'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.textContaining('/3'), findsNothing);
    expect(find.textContaining('Choose how you migrate'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_process_step_1')),
      findsOneWidget,
    );
    expect(find.textContaining('Prepare your balance'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_process_step_2')),
      findsOneWidget,
    );
    expect(find.textContaining('Move to Ironwood'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_process_step_3')),
      findsOneWidget,
    );
    expect(find.text('Spend as funds arrive'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.text('Choose how you migrate'))
          .style
          ?.fontWeight,
      FontWeight.w500,
    );
    expect(tester.widget<Text>(find.text('1')).style?.fontSize, 16);
    expect(
      tester.widget<Text>(find.text('1')).style?.fontWeight,
      FontWeight.w400,
    );
  });

  testWidgets('uses dark semantic colors in the About migration hero', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(step: MobileIronwoodMigrationStep.intro, theme: AppThemeData.dark),
    );
    await tester.pumpAndSettle();

    BoxDecoration decorationFor(String key) {
      final keyed = find.byKey(ValueKey(key));
      final widget = tester.widget(keyed);
      final container = widget is Container
          ? widget
          : tester.widget<Container>(
              find.descendant(of: keyed, matching: find.byType(Container)),
            );
      return container.decoration! as BoxDecoration;
    }

    expect(
      decorationFor('mobile_ironwood_legacy_connection_line').color,
      AppThemeData.dark.colors.border.medium,
    );
    expect(
      decorationFor('mobile_ironwood_target_connection_line').color,
      AppThemeData.dark.colors.icon.success,
    );

    final legacyDot = decorationFor('mobile_ironwood_legacy_connection_dot');
    final targetDot = decorationFor('mobile_ironwood_target_connection_dot');
    expect(legacyDot.color, AppThemeData.dark.colors.border.medium);
    expect(targetDot.color, AppThemeData.dark.colors.icon.success);
    expect(
      (legacyDot.border! as Border).top.color,
      AppThemeData.dark.colors.background.ground,
    );
    expect(
      (targetDot.border! as Border).top.color,
      AppThemeData.dark.colors.background.ground,
    );
    expect(
      tester.widget<Text>(find.text('Migration')).style!.color,
      AppThemeData.dark.colors.text.inverse,
    );
    expect(
      tester.widget<Text>(find.text('Ironwood Pool')).style!.color,
      AppThemeData.dark.colors.text.positiveStrong,
    );
  });

  testWidgets('shows the migration type choice and preview selection', (
    tester,
  ) async {
    await tester.pumpWidget(_app(step: MobileIronwoodMigrationStep.options));
    await tester.pumpAndSettle();

    expect(find.text('Choose How to Migrate'), findsOneWidget);
    expect(find.text('How to Migrate'), findsOneWidget);
    expect(find.textContaining('/3'), findsNothing);
    expect(find.text('Private'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_recommended_badge')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Splits transactions into multiple parts to minimize traceability, '
        'but takes longer.',
      ),
      findsOneWidget,
    );
    expect(find.text('Immediate'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_immediate_option')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Migrates your entire balance in one batch. Fast, but less private.',
      ),
      findsOneWidget,
    );
    expect(find.text('Customise'), findsNothing);
    expect(find.text('Advanced'), findsNothing);

    final subtitle = tester.widget<Text>(
      find.text(
        'Choose between more privacy over time or a faster migration. '
        'You can review the details before anything moves.',
      ),
    );
    expect(subtitle.textAlign, TextAlign.center);
    expect(
      tester.widget<Text>(find.text('Immediate')).style?.fontWeight,
      FontWeight.w600,
    );
    expect(
      tester
          .widget<Text>(
            find.text(
              'Migrates your entire balance in one batch. '
              'Fast, but less private.',
            ),
          )
          .style
          ?.fontWeight,
      FontWeight.w500,
    );
    final immediateIconOpacity = tester.widget<Opacity>(
      find.ancestor(
        of: find.byKey(const ValueKey('mobile_ironwood_immediate_icon')),
        matching: find.byType(Opacity),
      ),
    );
    expect(immediateIconOpacity.opacity, 0.5);
    expect(
      (tester
                  .widget<DecoratedBox>(
                    find.byKey(
                      const ValueKey('mobile_ironwood_recommended_badge'),
                    ),
                  )
                  .decoration
              as BoxDecoration)
          .color,
      const Color(0xFF00A460),
    );

    final unselectedRadio = tester.widget<Container>(
      find.byKey(const ValueKey('mobile_ironwood_unselected_radio')),
    );
    expect(
      (unselectedRadio.decoration! as BoxDecoration).color,
      const Color(0x33B8B8B8),
    );

    final privateOption = find.byKey(
      const ValueKey('mobile_ironwood_private_option'),
    );
    final immediateOption = find.byKey(
      const ValueKey('mobile_ironwood_immediate_option'),
    );
    await tester.tap(immediateOption);
    await tester.pump();
    expect(
      find.descendant(
        of: immediateOption,
        matching: find.byKey(const ValueKey('mobile_ironwood_selected_radio')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: privateOption,
        matching: find.byKey(
          const ValueKey('mobile_ironwood_unselected_radio'),
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(immediateOption);
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Review Migration Plan'), findsOneWidget);
    expect(find.text('Privacy trade-off'), findsOneWidget);
  });

  testWidgets('routes Keystone Immediate migration through mobile signing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/options',
        migrationService: _migrationService(),
        hardware: true,
      ),
    );
    await tester.pumpAndSettle();

    final immediateOption = find.byKey(
      const ValueKey('mobile_ironwood_immediate_option'),
    );
    final immediateGesture = find.descendant(
      of: immediateOption,
      matching: find.byType(GestureDetector),
    );
    expect(tester.widget<GestureDetector>(immediateGesture).onTap, isNotNull);
    await tester.tap(immediateOption);
    await tester.pump();
    expect(
      find.descendant(
        of: immediateOption,
        matching: find.byKey(const ValueKey('mobile_ironwood_selected_radio')),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Review Migration Plan'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_immediate_broadcast_button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'keystone immediate sign route:${_immediatePlan.migratedZatoshi}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('leaves migration choices before preparing the private plan', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final planCompleter = Completer<rust_sync.OrchardMigrationPrivatePlan?>();
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/options',
        migrationService: _migrationService(
          ios: true,
          getNotificationAuthorizationStatus: () async =>
              IronwoodMigrationNotificationAuthorizationStatus.authorized,
        ),
        privatePlanFuture: planCompleter.future,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('mobile_ironwood_migration_start_loading')),
      findsOneWidget,
    );
    expect(find.text('Choose How to Migrate').hitTestable(), findsNothing);

    // Plan resolution and draft creation now belong to the dedicated start
    // route, which remains non-dismissible while work is in flight.
    final lockedPop = tester.widget<PopScope>(
      find
          .ancestor(
            of: find.byKey(
              const ValueKey('mobile_ironwood_migration_start_loading'),
            ),
            matching: find.byType(PopScope),
          )
          .first,
    );
    expect(lockedPop.canPop, isFalse);

    planCompleter.complete(_plan);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('a failed plan is retryable on the preparation screen', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/options',
        migrationService: _migrationService(
          ios: true,
          getNotificationAuthorizationStatus: () async =>
              IronwoodMigrationNotificationAuthorizationStatus.authorized,
        ),
        privatePlanLoader: () =>
            Future<rust_sync.OrchardMigrationPrivatePlan?>.error(
              StateError('plan unavailable'),
            ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.text("Couldn't start migration. Try again."), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('mobile_ironwood_migration_start_retry_button'),
      ),
      findsOneWidget,
    );

    final popScope =
        tester.widget(
              find
                  .ancestor(
                    of: find.byKey(
                      const ValueKey(
                        'mobile_ironwood_migration_start_retry_button',
                      ),
                    ),
                    matching: find.byWidgetPredicate(
                      (widget) => widget is PopScope,
                    ),
                  )
                  .first,
            )
            as PopScope;
    expect(popScope.canPop, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('routes private migration by actual notification authorization', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var authorization = IronwoodMigrationNotificationAuthorizationStatus.denied;
    final planCompleter = Completer<rust_sync.OrchardMigrationPrivatePlan?>();
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/options',
        migrationService: _migrationService(
          ios: true,
          getNotificationAuthorizationStatus: () async => authorization,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Keep your migration on schedule'), findsOneWidget);

    authorization = IronwoodMigrationNotificationAuthorizationStatus.authorized;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/options',
        migrationService: _migrationService(
          ios: true,
          getNotificationAuthorizationStatus: () async => authorization,
        ),
        privatePlanFuture: planCompleter.future,
        hardware: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('mobile_ironwood_migration_start_loading')),
      findsOneWidget,
    );
    expect(find.text('Choose How to Migrate').hitTestable(), findsNothing);
    expect(find.text('Preparing your migration'), findsOneWidget);

    planCompleter.complete(_plan);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.text('Ready to sign'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey('mobile_ironwood_migration_start_continue_button'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'keystone combined sign route:${_plan.scheduledTransfers.length}',
      ),
      findsOneWidget,
    );
    expect(find.text('Review Migration Plan'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'prepares software migration on a dedicated loading screen for at least '
    'three seconds',
    (tester) async {
      _useMobileViewport(tester);
      var startCount = 0;
      var started = false;
      final startedStatus = _status(
        phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
      );
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/options',
          migrationService: _migrationService(
            ios: true,
            getNotificationAuthorizationStatus: () async =>
                IronwoodMigrationNotificationAuthorizationStatus.authorized,
          ),
          startedStatus: startedStatus,
          ctaBuilder: () => started
              ? IronwoodHomeMigrationCtaState.resume(
                  network: 'main',
                  accountUuid: 'account-1',
                  status: startedStatus,
                )
              : const IronwoodHomeMigrationCtaState.start(
                  network: 'main',
                  accountUuid: 'account-1',
                ),
          migrationCoordinator: () => _StartScreenTestMigrationCoordinator((
            accountUuid,
            approvedSchedule,
          ) async {
            startCount += 1;
            started = true;
          }),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('mobile_ironwood_migration_start_loading')),
        findsOneWidget,
      );
      expect(find.text('Choose How to Migrate').hitTestable(), findsNothing);
      expect(startCount, 1);

      await tester.pump(const Duration(milliseconds: 2999));
      expect(
        find.byKey(const ValueKey('mobile_ironwood_migration_start_loading')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(
        find.byType(MobileIronwoodMigrationPrivateStatusScreen),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mobile_ironwood_migration_start_loading')),
        findsNothing,
      );
    },
  );

  testWidgets('rotates shimmering preparation messages while work is pending', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final planCompleter = Completer<rust_sync.OrchardMigrationPrivatePlan?>();
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/start',
        migrationService: _migrationService(ios: true),
        privatePlanFuture: planCompleter.future,
      ),
    );
    await tester.pump();

    expect(find.text('Preparing your migration...'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('mobile_ironwood_migration_start_loading_indicator'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(
        find.byKey(
          const ValueKey('mobile_ironwood_migration_start_loading_indicator'),
        ),
      ),
      const Size(196, 12),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIcon && widget.name == AppIcons.chevronBackward,
      ),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Organizing migration batches...'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('mobile_ironwood_migration_start_loading_indicator'),
      ),
      findsOneWidget,
    );

    // Exhaust the non-cancellable minimum-delay Future before disposing the
    // still-pending plan fixture; the periodic message timer is cancelled by
    // the screen itself.
    await tester.pump(const Duration(milliseconds: 1350));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'prepares Keystone on the loading screen and waits for Continue before '
    'opening signing',
    (tester) async {
      _useMobileViewport(tester);
      var prepareCount = 0;
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/options',
          migrationService: _migrationService(
            ios: true,
            getNotificationAuthorizationStatus: () async =>
                IronwoodMigrationNotificationAuthorizationStatus.authorized,
            onPrepareKeystoneSingleQr: (_, _) async {
              prepareCount += 1;
              return _keystoneDenominationRequest();
            },
          ),
          hardware: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('mobile_ironwood_migration_start_loading')),
        findsOneWidget,
      );
      expect(prepareCount, 1);
      expect(
        find.byKey(
          const ValueKey('mobile_ironwood_migration_start_continue_button'),
        ),
        findsNothing,
      );

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(find.text('Ready to sign'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('mobile_ironwood_migration_start_continue_button'),
        ),
        findsOneWidget,
      );
      expect(find.text('Scan with Keystone'), findsNothing);

      await tester.tap(
        find.byKey(
          const ValueKey('mobile_ironwood_migration_start_continue_button'),
        ),
      );
      await tester.pumpAndSettle();

      expect(prepareCount, 1);
      expect(
        find.text(
          'keystone combined sign route:${_plan.scheduledTransfers.length}',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('starts a direct-note private plan after visible preparation', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final directNotePlan = _planWith(denominationSplitStageCount: 0);
    final readyStatus = _status(
      phase: kIronwoodMigrationReadyToMigratePhase,
      pendingSplitStageCount: 0,
    );
    var started = false;
    var startCount = 0;

    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/options',
        migrationService: _migrationService(
          ios: true,
          onStart: (accountUuid, approvedSchedule) async {
            expect(accountUuid, 'account-1');
            expect(approvedSchedule, directNotePlan.scheduledTransfers);
            started = true;
            startCount++;
            return _migrationResult();
          },
          getNotificationAuthorizationStatus: () async =>
              IronwoodMigrationNotificationAuthorizationStatus.authorized,
        ),
        privatePlan: directNotePlan,
        startedStatus: readyStatus,
        ctaBuilder: () => started
            ? IronwoodHomeMigrationCtaState.resume(
                network: 'main',
                accountUuid: 'account-1',
                status: readyStatus,
              )
            : const IronwoodHomeMigrationCtaState.start(
                network: 'main',
                accountUuid: 'account-1',
              ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_private_option')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Preparing your migration'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(startCount, 1);
    expect(find.text('Preparing your migration'), findsNothing);
    expect(find.text('Ironwood Migration'), findsOneWidget);
  });

  testWidgets('completes a direct-note Keystone draft after visible loading', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final directNotePlan = _planWith(denominationSplitStageCount: 0);
    final readyStatus = _status(
      phase: kIronwoodMigrationReadyToMigratePhase,
      pendingSplitStageCount: 0,
    );
    var completionCount = 0;
    var denominationRouteBuildCount = 0;

    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/options',
        migrationService: _migrationService(
          ios: true,
          getNotificationAuthorizationStatus: () async =>
              IronwoodMigrationNotificationAuthorizationStatus.authorized,
          onPrepareKeystoneDenominations: (_) async =>
              rust_sync.KeystoneMigrationSigningRequest(
                requestId: 'direct-note-request',
                messages: const [],
                signingBatchLimit: 50,
              ),
          onCompleteKeystoneDenominations:
              (accountUuid, approvedSchedule) async {
                expect(accountUuid, 'account-1');
                expect(approvedSchedule, directNotePlan.scheduledTransfers);
                completionCount += 1;
                return _migrationResult();
              },
        ),
        hardware: true,
        privatePlan: directNotePlan,
        status: readyStatus,
        realKeystoneDenominationRoute: true,
        onKeystoneDenominationRouteBuilt: () {
          denominationRouteBuildCount += 1;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Preparing your migration'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(completionCount, 1);
    expect(denominationRouteBuildCount, 0);
    expect(find.byType(KeystoneQrScannerCard), findsNothing);
    expect(find.text('Ironwood Migration'), findsOneWidget);
  });

  testWidgets(
    'does not return to About while the started Keystone status refreshes',
    (tester) async {
      _useMobileViewport(tester);
      final directNotePlan = _planWith(denominationSplitStageCount: 0);
      final readyStatus = _status(
        phase: kIronwoodMigrationReadyToMigratePhase,
        pendingSplitStageCount: 0,
      );
      final refreshedCta = Completer<IronwoodHomeMigrationCtaState>();
      var ctaLoadCount = 0;
      var completionCount = 0;

      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/cta-prime',
          migrationService: _migrationService(
            ios: true,
            getNotificationAuthorizationStatus: () async =>
                IronwoodMigrationNotificationAuthorizationStatus.authorized,
            onPrepareKeystoneDenominations: (_) async =>
                rust_sync.KeystoneMigrationSigningRequest(
                  requestId: 'direct-note-request',
                  messages: const [],
                  signingBatchLimit: 50,
                ),
            onCompleteKeystoneDenominations:
                (accountUuid, approvedSchedule) async {
                  completionCount += 1;
                  return _migrationResult();
                },
          ),
          hardware: true,
          privatePlan: directNotePlan,
          ctaLoader: () {
            ctaLoadCount += 1;
            if (ctaLoadCount == 1) {
              return Future.value(
                const IronwoodHomeMigrationCtaState.start(
                  network: 'main',
                  accountUuid: 'account-1',
                ),
              );
            }
            return refreshedCta.future;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open_migration_options')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
      );

      for (
        var pumpCount = 0;
        completionCount == 0 && pumpCount < 20;
        pumpCount++
      ) {
        await tester.pump();
      }
      expect(completionCount, 1);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(find.text('intro route'), findsNothing);

      refreshedCta.complete(
        IronwoodHomeMigrationCtaState.resume(
          network: 'main',
          accountUuid: 'account-1',
          status: readyStatus,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('intro route'), findsNothing);
      expect(find.text('Ironwood Migration'), findsOneWidget);
    },
  );

  testWidgets('prepares the combined Keystone request on the QR route', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var prepareCount = 0;
    var draftCount = 0;
    var denominationPrepareCount = 0;

    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/options',
        migrationService: _migrationService(
          ios: true,
          getNotificationAuthorizationStatus: () async =>
              IronwoodMigrationNotificationAuthorizationStatus.authorized,
          onPrepareKeystoneSingleQr: (accountUuid, approvedSchedule) async {
            prepareCount += 1;
            expect(accountUuid, 'account-1');
            expect(approvedSchedule, _plan.scheduledTransfers);
            return _keystoneDenominationRequest();
          },
          onPrepareKeystoneDenominations: (_) async {
            denominationPrepareCount += 1;
            return _keystoneDenominationRequest();
          },
          onCreatePrivateDraft: (_, _) async {
            draftCount += 1;
            return 'private-draft-run';
          },
        ),
        hardware: true,
        privatePlan: _plan,
        realKeystoneCombinedRoute: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Preparing your migration'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(prepareCount, 1);
    expect(find.text('Ready to sign'), findsOneWidget);
    // Combined signing must not save a draft first: the combined prepare
    // rejects any already-active run, and the legacy denomination prepare is
    // not part of this flow.
    expect(draftCount, 0);
    expect(denominationPrepareCount, 0);
    await tester.tap(
      find.byKey(
        const ValueKey('mobile_ironwood_migration_start_continue_button'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Scan with Keystone'), findsOneWidget);
  });

  testWidgets(
    'starts a split private plan on the dedicated preparation screen',
    (tester) async {
      _useMobileViewport(tester);
      final startCompleter = Completer<rust_sync.IronwoodMigrationResult>();
      final startedStatus = _status(
        phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
      );
      var started = false;

      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/options',
          migrationService: _migrationService(
            ios: true,
            getNotificationAuthorizationStatus: () async =>
                IronwoodMigrationNotificationAuthorizationStatus.authorized,
          ),
          migrationCoordinator: () => _StartScreenTestMigrationCoordinator((
            accountUuid,
            approvedSchedule,
          ) async {
            expect(accountUuid, 'account-1');
            expect(approvedSchedule, _plan.scheduledTransfers);
            started = true;
            await startCompleter.future;
          }),
          startedStatus: startedStatus,
          ctaBuilder: () => started
              ? IronwoodHomeMigrationCtaState.resume(
                  network: 'main',
                  accountUuid: 'account-1',
                  status: startedStatus,
                )
              : const IronwoodHomeMigrationCtaState.start(
                  network: 'main',
                  accountUuid: 'account-1',
                ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(started, isTrue);
      expect(
        find.byKey(const ValueKey('mobile_ironwood_migration_start_loading')),
        findsOneWidget,
      );
      expect(find.text('Choose How to Migrate').hitTestable(), findsNothing);
      expect(find.text('Preparing your migration'), findsOneWidget);

      startCompleter.complete(_migrationResult());
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'saves a software private draft only after the notification gate',
    (tester) async {
      _useMobileViewport(tester);
      var savedDraftCount = 0;
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/options',
          migrationService: _migrationService(
            onCreatePrivateDraft: (accountUuid, approvedSchedule) async {
              savedDraftCount += 1;
              expect(accountUuid, 'account-1');
              expect(approvedSchedule, _plan.scheduledTransfers);
              return 'software-draft-run';
            },
            getNotificationAuthorizationStatus: () async =>
                IronwoodMigrationNotificationAuthorizationStatus.denied,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
      );
      await tester.pumpAndSettle();

      expect(savedDraftCount, 0);
      expect(find.text('Keep your migration on schedule'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue without notifications'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(savedDraftCount, 1);
      expect(find.text('Preparing your migration'), findsOneWidget);
      expect(
        find.text('Keep your migration on schedule').hitTestable(),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('resumes a saved software draft inside migration status', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final draftStatus = _status(
      phase: kIronwoodMigrationAwaitingPreparationPhase,
    );
    final resumedStatus = _status(
      phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
    );
    var resumed = false;
    var startCount = 0;

    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(
          onGetStatus: () async => resumed ? resumedStatus : draftStatus,
          onStart: (accountUuid, approvedSchedule) async {
            expect(accountUuid, 'account-1');
            expect(approvedSchedule, isEmpty);
            startCount += 1;
            resumed = true;
            return _migrationResult();
          },
        ),
        status: draftStatus,
        startedStatus: resumedStatus,
        ctaBuilder: () => IronwoodHomeMigrationCtaState.resume(
          network: 'main',
          accountUuid: 'account-1',
          status: resumed ? resumedStatus : draftStatus,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(startCount, 1);
    expect(find.text('Preparing your migration'), findsOneWidget);
  });

  testWidgets('retries a failed software draft resume from migration status', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final draftStatus = _status(
      phase: kIronwoodMigrationAwaitingPreparationPhase,
    );
    final resumedStatus = _status(
      phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
    );
    var resumed = false;
    var startCount = 0;

    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(
          onGetStatus: () async => resumed ? resumedStatus : draftStatus,
          onStart: (_, approvedSchedule) async {
            expect(approvedSchedule, isEmpty);
            startCount += 1;
            if (startCount == 1) {
              throw StateError('temporary preparation failure');
            }
            resumed = true;
            return _migrationResult();
          },
        ),
        status: draftStatus,
        startedStatus: resumedStatus,
        ctaBuilder: () => IronwoodHomeMigrationCtaState.resume(
          network: 'main',
          accountUuid: 'account-1',
          status: resumed ? resumedStatus : draftStatus,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(startCount, 1);
    expect(find.text("Couldn't start migration. Try again."), findsOneWidget);
    expect(find.text('Continue preparation'), findsOneWidget);

    await tester.tap(find.text('Continue preparation'));
    await tester.pumpAndSettle();

    expect(startCount, 2);
    expect(find.text("Couldn't start migration. Try again."), findsNothing);
    expect(find.text('Preparing your migration'), findsOneWidget);
  });

  testWidgets(
    'refreshes status without restarting when a saved draft already advanced',
    (tester) async {
      _useMobileViewport(tester);
      final draftStatus = _status(
        phase: kIronwoodMigrationAwaitingPreparationPhase,
      );
      final advancedStatus = _status(
        phase: kIronwoodMigrationReadyToMigratePhase,
        pendingSplitStageCount: 0,
      );
      var advancedObserved = false;
      var startCount = 0;

      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationService: _migrationService(
            onGetStatus: () async {
              advancedObserved = true;
              return advancedStatus;
            },
            onStart: (_, _) async {
              startCount += 1;
              return _migrationResult();
            },
          ),
          status: draftStatus,
          ctaBuilder: () => IronwoodHomeMigrationCtaState.resume(
            network: 'main',
            accountUuid: 'account-1',
            status: advancedObserved ? advancedStatus : draftStatus,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(startCount, 0);
      expect(find.text('Ironwood Migration'), findsOneWidget);
    },
  );

  testWidgets('requests notifications only after the explicit allow action', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var authorization =
        IronwoodMigrationNotificationAuthorizationStatus.notDetermined;
    var requestCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/notifications',
        migrationService: _migrationService(
          ios: true,
          getNotificationAuthorizationStatus: () async => authorization,
          requestNotificationAuthorization: () async {
            requestCount++;
            authorization =
                IronwoodMigrationNotificationAuthorizationStatus.authorized;
            return true;
          },
        ),
        privatePlan: _plan,
        status: _status(
          phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requestCount, 0);
    final allowButton = tester.widget<AppButton>(
      find.ancestor(
        of: find.text('Allow notifications'),
        matching: find.byType(AppButton),
      ),
    );
    expect(allowButton.enabledBackgroundColor, const Color(0xFF052C1B));
    expect(allowButton.pressedBackgroundColor, isNotNull);
    final notNowButton = tester.widget<AppButton>(
      find.ancestor(of: find.text('Not now'), matching: find.byType(AppButton)),
    );
    expect(notNowButton.variant, AppButtonVariant.ghost);
    expect(notNowButton.pressedBackgroundColor, isNotNull);

    await tester.tap(find.text('Allow notifications'));
    await tester.pumpAndSettle();

    expect(requestCount, 1);
    expect(find.text('Preparing your migration'), findsOneWidget);
    expect(find.text('Review Migration Plan'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('requires confirmation before continuing without notifications', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/notifications',
        migrationService: _migrationService(
          ios: true,
          getNotificationAuthorizationStatus: () async =>
              IronwoodMigrationNotificationAuthorizationStatus.denied,
        ),
        privatePlan: _plan,
        status: _status(
          phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Continue without notifications?'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('Continue without notifications?'), findsNothing);
    expect(find.text('Keep your migration on schedule'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue without notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Preparing your migration'), findsOneWidget);
    expect(find.text('Review Migration Plan'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'shows a retry on the start screen when draft persistence fails',
    (tester) async {
      _useMobileViewport(tester);
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/notifications',
          migrationService: _migrationService(
            ios: true,
            getNotificationAuthorizationStatus: () async =>
                IronwoodMigrationNotificationAuthorizationStatus.denied,
            onCreatePrivateDraft: (_, _) async =>
                throw StateError('draft write failed'),
          ),
          privatePlan: _plan,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue without notifications'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Preparing your migration'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(find.text("Couldn't start migration. Try again."), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('mobile_ironwood_migration_start_retry_button'),
        ),
        findsOneWidget,
      );
      expect(find.text('Keep your migration on schedule'), findsNothing);
    },
  );

  testWidgets('keeps design label and opens Settings after denial', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var settingsOpenCount = 0;
    var requestCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/notifications',
        migrationService: _migrationService(
          ios: true,
          getNotificationAuthorizationStatus: () async =>
              IronwoodMigrationNotificationAuthorizationStatus.denied,
          requestNotificationAuthorization: () async {
            requestCount++;
            return false;
          },
          openNotificationSettings: () async {
            settingsOpenCount++;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Allow notifications'), findsOneWidget);
    expect(find.text('Open Settings'), findsNothing);
    expect(
      find.text('Notifications are disabled in iOS Settings.'),
      findsNothing,
    );

    await tester.tap(find.text('Allow notifications'));
    await tester.pumpAndSettle();

    expect(requestCount, 0);
    expect(settingsOpenCount, 1);
  });

  testWidgets('keeps the fast review warning readable in dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.fastReview,
        theme: AppThemeData.dark,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fast Migration'), findsOneWidget);
    expect(find.textContaining('/3'), findsNothing);
    final warning = tester.widget<Text>(find.text('Privacy trade-off'));
    expect(warning.style?.color, AppThemeData.dark.colors.text.homeCard);
    final privacyIcon = tester.widget<AppIcon>(
      find.byKey(const ValueKey('mobile_ironwood_fast_privacy_icon')),
    );
    expect(privacyIcon.name, AppIcons.transparentBalance);
    expect(privacyIcon.size, 20);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('mobile_ironwood_fast_privacy_card')),
          )
          .height,
      189,
    );
    expect(find.text('142.22 ZEC'), findsOneWidget);
    expect(find.text('Migration complete in'), findsOneWidget);
    expect(find.text('~5 mins'), findsOneWidget);
    final continueButton = find.byKey(
      const ValueKey('mobile_ironwood_immediate_broadcast_button'),
    );
    expect(tester.widget<AppButton>(continueButton).onPressed, isNotNull);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_fast_acknowledgement')),
      findsNothing,
    );
    expect(find.text('Continue anyway'), findsOneWidget);
    expect(find.text('Authorise anyway'), findsNothing);
  });

  testWidgets('Android shows Private disabled and selects Immediate', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.options,
        privateMigrationSupported: false,
      ),
    );
    await tester.pumpAndSettle();

    final privateOption = find.byKey(
      const ValueKey('mobile_ironwood_private_option'),
    );
    final immediateOption = find.byKey(
      const ValueKey('mobile_ironwood_immediate_option'),
    );
    expect(find.text('Choose How to Migrate'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);
    expect(find.text('Immediate'), findsOneWidget);
    expect(
      find.text(
        'Private migration is temporarily unavailable on Android. '
        'Choose immediate to continue.',
      ),
      findsOneWidget,
    );
    expect(find.text('Not available on Android.'), findsOneWidget);
    expect(find.text('Recommended'), findsNothing);
    expect(
      find.descendant(
        of: privateOption,
        matching: find.byKey(
          const ValueKey('mobile_ironwood_unselected_radio'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: immediateOption,
        matching: find.byKey(const ValueKey('mobile_ironwood_selected_radio')),
      ),
      findsOneWidget,
    );

    final privateGesture = find.descendant(
      of: privateOption,
      matching: find.byType(GestureDetector),
    );
    expect(tester.widget<GestureDetector>(privateGesture).onTap, isNull);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(
              const ValueKey('mobile_ironwood_private_option_opacity'),
            ),
          )
          .opacity,
      0.5,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(
              const ValueKey('mobile_ironwood_immediate_option_opacity'),
            ),
          )
          .opacity,
      1,
    );

    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fast Migration'), findsOneWidget);
    expect(find.text('Consider another option'), findsOneWidget);
  });

  testWidgets(
    'shows the computed immediate completion estimate in production',
    (tester) async {
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/fast/review',
          migrationService: _migrationService(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Migration complete in'), findsOneWidget);
      expect(find.text('~5 mins'), findsOneWidget);
      expect(find.text('A few minutes'), findsNothing);
    },
  );

  testWidgets('shows the exact immediate plan amount at a rounding boundary', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.fastReview,
        previewImmediatePlan: rust_sync.OrchardMigrationImmediatePlan(
          totalInputZatoshi: BigInt.from(14_222_560_000),
          feeZatoshi: BigInt.from(60_000),
          migratedZatoshi: BigInt.from(14_222_500_000),
          inputNoteCount: 12,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('142.22 ZEC'), findsOneWidget);
    expect(find.text('142.23 ZEC'), findsNothing);
  });

  testWidgets('keeps the syncing skeleton within a 320px mobile viewport', (
    tester,
  ) async {
    _useMobileViewport(tester, size: const Size(320, 568));
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.migrating,
        previewSurface: MobileIronwoodMigrationPreviewSurface.syncing,
      ),
    );
    await tester.pump(const Duration(milliseconds: 32));

    expect(find.text('Syncing the migration progress.'), findsOneWidget);
  });

  testWidgets('uses the Figma state-specific migration backdrop glow', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.migrating,
        theme: AppThemeData.dark,
        previewSurface: MobileIronwoodMigrationPreviewSurface
            .migrationWaitingNotificationsOn,
      ),
    );
    await tester.pump();

    LinearGradient glow() {
      final box = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('mobile_ironwood_migration_backdrop_glow')),
      );
      return (box.decoration as BoxDecoration).gradient! as LinearGradient;
    }

    expect(glow().colors.first.a, 0);
    expect(glow().colors.last.a, closeTo(0.4, 0.001));

    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.migrating,
        theme: AppThemeData.dark,
        previewSurface: MobileIronwoodMigrationPreviewSurface.syncing,
      ),
    );
    await tester.pump();

    expect(glow().colors.first.a, 0);
    expect(glow().colors.last.a, closeTo(0.5, 0.001));
  });

  testWidgets('uses the shared modal layout for Keystone scan help', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.migrating,
        previewSurface: MobileIronwoodMigrationPreviewSurface.keystoneScanHelp,
      ),
    );
    await tester.pump();

    final illustration = tester.widget<Image>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/illustrations/keystone_qr_scan_error.png',
      ),
    );
    expect(illustration.width, 48);
    expect(illustration.height, 48);
    expect(
      find.text('Having issues with scanning the QR code?'),
      findsOneWidget,
    );
    expect(find.text('Ok, I will check'), findsOneWidget);
  });

  testWidgets(
    'rotates the preparation orbit while keeping its center content fixed',
    (tester) async {
      _useMobileViewport(tester);
      await tester.pumpWidget(
        _app(
          step: MobileIronwoodMigrationStep.migrating,
          previewSurface:
              MobileIronwoodMigrationPreviewSurface.preparationCompleteModal,
          disableAnimations: false,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      final orbitFinder = find.byKey(
        const ValueKey('mobile_ironwood_preparation_complete_orbit'),
      );
      final centerFinder = find.byKey(
        const ValueKey('mobile_ironwood_preparation_complete_center'),
      );
      final initialTurns = tester
          .widget<RotationTransition>(orbitFinder)
          .turns
          .value;
      final initialCenter = tester.getCenter(centerFinder);

      await tester.pump(const Duration(milliseconds: 7500));

      final updatedTurns = tester
          .widget<RotationTransition>(orbitFinder)
          .turns
          .value;
      expect(updatedTurns, closeTo(initialTurns + 0.25, 0.01));
      expect(tester.getCenter(centerFinder), initialCenter);
    },
  );

  testWidgets('slides the preparation complete modal up from the bottom', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.migrating,
        previewSurface:
            MobileIronwoodMigrationPreviewSurface.preparationCompleteModal,
        disableAnimations: false,
      ),
    );
    await tester.pump();

    final title = find.text('Preparation is done');
    final initialTop = tester.getTopLeft(title).dy;
    await tester.pump(const Duration(milliseconds: 320));
    final settledTop = tester.getTopLeft(title).dy;

    expect(initialTop, greaterThan(settledTop));
  });

  testWidgets('uses the matching continue icon for each preparation signer', (
    tester,
  ) async {
    _useMobileViewport(tester);
    Future<String> renderedLeadingIcon(
      MobileIronwoodMigrationPreviewSurface surface,
    ) async {
      await tester.pumpWidget(
        _app(
          step: MobileIronwoodMigrationStep.migrating,
          previewSurface: surface,
        ),
      );
      await tester.pump();
      final button = tester.widget<AppButton>(
        find.byKey(
          const ValueKey('mobile_ironwood_preparation_continue_button'),
        ),
      );
      return (button.leading! as AppIcon).name;
    }

    expect(
      await renderedLeadingIcon(
        MobileIronwoodMigrationPreviewSurface.preparationPaused,
      ),
      AppIcons.play,
    );
    expect(
      await renderedLeadingIcon(
        MobileIronwoodMigrationPreviewSurface.preparationPausedKeystone,
      ),
      AppIcons.qr,
    );
  });

  testWidgets('renders the preparing migration state', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(_app(step: MobileIronwoodMigrationStep.preparing));
    await tester.pumpAndSettle();

    expect(find.text('Migration in Progress'), findsOneWidget);
    expect(
      find.text(
        'Preparing your balance for migration. This step usually takes '
        '10-20 mins.',
      ),
      findsOneWidget,
    );
    expect(find.text('142.20 ZEC'), findsOneWidget);
    expect(find.text('Migration 12 notes'), findsOneWidget);
    expect(find.text('Note Split'), findsOneWidget);
    expect(find.text('Split Notes into 12 Migration Parts'), findsOneWidget);
    expect(find.text('Wait for confirmation'), findsOneWidget);
    final connector = find.byKey(
      const ValueKey('mobile_ironwood_waiting_step_connector'),
    );
    final connectorLine = find.byKey(
      const ValueKey('mobile_ironwood_waiting_step_connector_line'),
    );
    final completedStepIcon = find.byWidgetPredicate(
      (widget) => widget is AppIcon && widget.name == AppIcons.check,
    );
    expect(tester.getSize(connector), const Size(24, 34));
    expect(tester.getSize(connectorLine), const Size(2, 20));
    expect(
      tester.getCenter(connector).dx,
      closeTo(tester.getCenter(completedStepIcon).dx, 0.1),
    );
    final loader = tester.widget<AppIcon>(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.loader,
      ),
    );
    expect(loader.animated, isFalse);
    expect(
      find.text(
        'Migration will start automatically once note split is complete.',
      ),
      findsOneWidget,
    );
    expect(find.text('Go home'), findsOneWidget);
  });

  testWidgets('animates the preparing confirmation loader', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.preparing,
        disableAnimations: false,
      ),
    );
    await tester.pump();

    final loader = tester.widget<AppIcon>(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.loader,
      ),
    );
    expect(loader.animated, isTrue);
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders migrating parts inline', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.migrating,
        previewStatus: _visualMigrationStatus(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Migration in Progress'), findsOneWidget);
    expect(find.text('Migration 12 notes'), findsOneWidget);
    expect(find.text('142.20 ZEC'), findsOneWidget);
    expect(find.text('Part 1'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Needs input'), findsOneWidget);
    expect(find.text('Migrating...'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_ironwood_part_row_0')),
        matching: find.text('Completed'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_ironwood_part_row_1')),
        matching: find.text('Needs input'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_ironwood_part_row_2')),
        matching: find.text('Migrating...'),
      ),
      findsOneWidget,
    );
    final rail = find.byKey(
      const ValueKey('mobile_ironwood_status_rail_scroll'),
    );
    final railScrollable = find.descendant(
      of: rail,
      matching: find.byType(Scrollable),
    );
    final railPosition = tester.state<ScrollableState>(railScrollable).position;
    expect(railPosition.maxScrollExtent, greaterThan(0));
    await tester.drag(rail, const Offset(-120, 0));
    await tester.pump();
    expect(railPosition.pixels, greaterThan(0));

    final partList = find.byKey(
      const ValueKey('mobile_ironwood_active_part_list'),
    );
    final listScrollable = find.descendant(
      of: partList,
      matching: find.byType(Scrollable),
    );
    final listPosition = tester.state<ScrollableState>(listScrollable).position;
    expect(listPosition.maxScrollExtent, greaterThan(0));
    await tester.drag(partList, const Offset(0, -120));
    await tester.pump();
    expect(listPosition.pixels, greaterThan(0));
    expect(find.text('Currently spendable balance'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Currently spendable balance'),
        matching: find.byType(FittedBox),
      ),
      findsOneWidget,
    );
    expect(find.text('4.12 ZEC'), findsWidgets);
    expect(
      find.text('Keep Vizor open & unlocked.').hitTestable(),
      findsOneWidget,
    );
    expect(
      find.text('Vizor will retry automatically.').hitTestable(),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Go home'));
    await tester.pumpAndSettle();
    expect(find.text('Go home').hitTestable(), findsOneWidget);
  });

  testWidgets('Android keeps an active Private migration status visible', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.migrating,
        previewStatus: _visualMigrationStatus(),
        privateMigrationSupported: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Migration in Progress'), findsOneWidget);
    expect(find.text('Fast Migration'), findsNothing);
  });

  testWidgets('retries an overdue migration when Needs input is tapped', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var continueCount = 0;
    final overdueStatus = _status(
      phase: kIronwoodMigrationBroadcastScheduledPhase,
      broadcastStatuses: const ['scheduled'],
      targetValues: const [412_000_000],
      parts: [
        rust_sync.MigrationPartStatus(
          partIndex: 0,
          valueZatoshi: BigInt.from(412_000_000),
          state: rust_sync.MigrationPartState.scheduled,
          txidHex: 'tx-0',
          scheduledHeight: 3_000_000,
          confirmationCount: 0,
          confirmationTarget: 3,
        ),
      ],
    );
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(
          onContinue: (_) async {
            continueCount++;
            return _migrationResult();
          },
        ),
        status: overdueStatus,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 3_000_100,
          chainTipHeight: 3_000_100,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Retry broadcast'), findsOneWidget);
    expect(continueCount, 0);

    await tester.tap(find.text('Retry broadcast'));
    await tester.pumpAndSettle();

    expect(continueCount, greaterThanOrEqualTo(1));
  });

  testWidgets('keeps migration status actions reachable on compact screens', (
    tester,
  ) async {
    _useMobileViewport(tester, size: const Size(320, 568));
    await tester.pumpWidget(_app(step: MobileIronwoodMigrationStep.preparing));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Go home'));
    await tester.pumpAndSettle();
    expect(find.text('Go home').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('waits for explicit continuation before Keystone split signing', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var softwareStartCount = 0;
    var keystonePrepareCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(
          onStart: (_, _) async {
            softwareStartCount += 1;
            return _migrationResult();
          },
          onPrepareKeystoneDenominations: (accountUuid) async {
            keystonePrepareCount += 1;
            expect(accountUuid, 'account-1');
            return _keystoneDenominationRequest();
          },
        ),
        hardware: true,
        status: _status(
          phase: kIronwoodMigrationAwaitingDenominationSignaturePhase,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(softwareStartCount, 0);
    expect(keystonePrepareCount, 0);
    expect(find.text('Preparing your migration'), findsOneWidget);
    expect(find.text('Continue with Keystone'), findsOneWidget);
    expect(find.text('keystone denomination sign route'), findsNothing);

    await tester.tap(find.text('Continue with Keystone'));
    await tester.pumpAndSettle();

    expect(find.text('keystone denomination sign route'), findsOneWidget);
  });

  testWidgets('returns home from Keystone private preparation', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        hardware: true,
        status: _status(
          phase: kIronwoodMigrationAwaitingDenominationSignaturePhase,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preparing your migration'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();

    expect(find.text('home route'), findsOneWidget);
  });

  testWidgets(
    'does not show Keystone recovery before a signature is actually required',
    (tester) async {
      _useMobileViewport(tester);
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationService: _migrationService(),
          hardware: true,
          status: _status(phase: kIronwoodMigrationAwaitingPreparationPhase),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Preparing your migration'), findsOneWidget);
      expect(find.text('Continue with Keystone'), findsNothing);
      expect(
        find.text('Preparation needs another Keystone signature.'),
        findsNothing,
      );
    },
  );

  testWidgets('resumes a saved Keystone draft from migration status', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        hardware: true,
        status: _status(
          phase: kIronwoodMigrationAwaitingDenominationSignaturePhase,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preparing your migration'), findsOneWidget);
    expect(find.text('Continue with Keystone'), findsOneWidget);
    expect(
      find.text('Preparation needs another Keystone signature.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Continue with Keystone'));
    await tester.pumpAndSettle();

    expect(find.text('keystone denomination sign route'), findsOneWidget);
  });

  testWidgets('renders the mobile Keystone split signing QR', (tester) async {
    _useMobileViewport(tester, size: const Size(320, 568));
    final request = rust_sync.KeystoneMigrationSigningRequest(
      requestId: 'preview-request',
      messages: [
        rust_sync.KeystoneMigrationMessage(
          id: 'split-1',
          redactedPczt: Uint8List.fromList([1]),
        ),
        rust_sync.KeystoneMigrationMessage(
          id: 'split-2',
          redactedPczt: Uint8List.fromList([2]),
        ),
      ],
      signingBatchLimit: 1,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appBootstrapProvider.overrideWithValue(_bootstrap())],
        child: AppTheme(
          data: AppThemeData.light,
          child: MaterialApp(
            home: MobileIronwoodMigrationKeystoneDenominationSignScreen(
              previewRequest: request,
              previewUrParts: const ['UR:ZCASH-SIGN-BATCH/PREVIEW'],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Step 1/2'), findsOneWidget);
    expect(find.text('Scan with Keystone'), findsOneWidget);
    expect(find.text('Round 1 of 2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_keystone_qr')),
      findsOneWidget,
    );
    final qrStage = tester.widget<KeystonePcztQrStage>(
      find.byKey(const ValueKey('mobile_ironwood_keystone_qr')),
    );
    expect(qrStage.frameInterval, const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);

    final nextButton = find.byKey(
      const ValueKey('mobile_ironwood_keystone_signing_next'),
    );
    await tester.ensureVisible(nextButton);
    await tester.pumpAndSettle();
    await tester.tap(nextButton);
    await tester.pump();

    expect(find.text('Step 2/2'), findsOneWidget);
    expect(find.text('Confirm with Keystone'), findsOneWidget);
    expect(find.text('Round 1 of 2'), findsOneWidget);
    expect(
      find.text('Scan the new signed QR shown on Keystone.'),
      findsOneWidget,
    );
    final signingRoundLabel = find.byKey(
      const ValueKey('mobile_ironwood_keystone_signing_round'),
    );
    final scanTarget = find.byKey(
      const ValueKey('mobile_ironwood_keystone_signing_scan_target'),
    );
    expect(
      tester.getBottomLeft(signingRoundLabel).dy,
      lessThanOrEqualTo(tester.getTopLeft(scanTarget).dy),
    );
    expect(tester.takeException(), isNull);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('Step 1/2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_keystone_qr')),
      findsOneWidget,
    );
  });

  testWidgets('reuses the mobile Keystone flow for Immediate migration', (
    tester,
  ) async {
    _useMobileViewport(tester, size: const Size(393, 852));
    final request = rust_sync.KeystoneMigrationSigningRequest(
      requestId: 'immediate-preview-request',
      messages: [
        rust_sync.KeystoneMigrationMessage(
          id: 'immediate-transaction',
          redactedPczt: Uint8List.fromList([1]),
        ),
      ],
      signingBatchLimit: 1,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appBootstrapProvider.overrideWithValue(_bootstrap())],
        child: AppTheme(
          data: AppThemeData.dark,
          child: MaterialApp(
            home: MobileIronwoodMigrationKeystoneImmediateSignScreen(
              approvedPlan: _immediatePlan,
              previewRequest: request,
              previewUrParts: const ['UR:ZCASH-SIGN-BATCH/IMMEDIATE'],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Step 1/2'), findsOneWidget);
    expect(find.text('Scan with Keystone'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_keystone_qr')),
      findsOneWidget,
    );

    final nextButton = find.byKey(
      const ValueKey('mobile_ironwood_keystone_signing_next'),
    );
    await tester.ensureVisible(nextButton);
    await tester.tap(nextButton);
    await tester.pump();

    expect(find.text('Step 2/2'), findsOneWidget);
    expect(find.text('Confirm with Keystone'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('mobile_ironwood_keystone_signing_scan_target'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'leaves signing after a completion error when the migration was committed',
    (tester) async {
      _useMobileViewport(tester);
      var committed = false;
      var completionCount = 0;
      final coordinator = _ProofPermitTestMigrationCoordinator();
      final credentialStore = _FailingBindCredentialStore(failAtBindCall: 1);
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                committed
                ? _status(
                    phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
                    activeRunId: 'committed-run',
                  )
                : _status(
                    phase: kIronwoodMigrationReadyPhase,
                    activeRunId: null,
                  ),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                _plan,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: credentialStore,
        getEndpoint: () => defaultRpcEndpointConfig('main'),
        getSessionPassword: () => 'test-password',
        isMobile: () => true,
        prepareKeystoneDenominationMigration:
            ({required dbPath, required network, required accountUuid}) async =>
                rust_sync.KeystoneMigrationSigningRequest(
                  requestId: 'partial-success-request',
                  messages: [
                    rust_sync.KeystoneMigrationMessage(
                      id: 'split-1',
                      redactedPczt: Uint8List.fromList([1]),
                    ),
                  ],
                  signingBatchLimit: 35,
                ),
        completeKeystoneDenominationMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required requestId,
              required signedMessages,
              required password,
              required saltBase64,
              required approvedSchedule,
            }) async {
              completionCount++;
              committed = true;
              return _migrationResult();
            },
        getKeystoneProofStatus: ({required requestId}) async =>
            const rust_sync.KeystoneMigrationProofStatus(
              readyCount: 1,
              totalCount: 1,
              isReady: true,
              isFailed: false,
            ),
      );

      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/keystone/denominations/sign',
          migrationService: service,
          migrationCoordinator: () => coordinator,
          hardware: true,
          realKeystoneDenominationRoute: true,
          statusLoader: () async => committed
              ? _status(
                  phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
                  activeRunId: 'committed-run',
                )
              : _status(phase: kIronwoodMigrationReadyPhase, activeRunId: null),
        ),
      );
      await tester.pumpAndSettle();

      final nextButton = find.byKey(
        const ValueKey('mobile_ironwood_keystone_signing_next'),
      );
      await tester.ensureVisible(nextButton);
      await tester.tap(nextButton);
      await tester.pump();
      tester
          .widget<KeystoneQrScannerCard>(find.byType(KeystoneQrScannerCard))
          .onComplete(
            const ScanResult(urType: 'zcash-batch-sig-result', data: [1]),
          );
      await tester.pumpAndSettle();

      expect(completionCount, 1);
      expect(credentialStore.bindCallCount, 1);
      expect(
        coordinator.exposedState.childProofBatchPermits,
        isNot(contains('account-1')),
      );
      expect(
        coordinator.exposedState.foregroundProgressPermits,
        contains('account-1'),
      );
      expect(
        find.byType(MobileIronwoodMigrationKeystoneDenominationSignScreen),
        findsNothing,
      );
      expect(
        find.text('This Keystone signing request expired. Prepare it again.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'leaves batch re-signing after a completion error when parts advanced',
    (tester) async {
      _useMobileViewport(tester);
      var committed = false;
      var completionCount = 0;
      final coordinator = _ProofPermitTestMigrationCoordinator();
      final credentialStore = _FailingBindCredentialStore(
        failAtBindCall: 2,
        initialRunId: 'run-1',
      );
      rust_sync.MigrationStatus status() => committed
          ? _status(
              phase: kIronwoodMigrationBroadcastScheduledPhase,
              activeRunId: 'run-1',
              signedChildPcztCount: 1,
            )
          : _status(
              phase: kIronwoodMigrationReadyToMigratePhase,
              activeRunId: 'run-1',
            );
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                status(),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                _plan,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: credentialStore,
        getEndpoint: () => defaultRpcEndpointConfig('main'),
        getSessionPassword: () => 'test-password',
        isMobile: () => true,
        prepareKeystoneBatchMigration:
            ({required dbPath, required network, required accountUuid}) async =>
                rust_sync.KeystoneMigrationSigningRequest(
                  requestId: 'partial-success-batch-request',
                  messages: [
                    rust_sync.KeystoneMigrationMessage(
                      id: 'child-1',
                      redactedPczt: Uint8List.fromList([1]),
                    ),
                  ],
                  signingBatchLimit: 35,
                ),
        completeKeystoneBatchMigration:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required requestId,
              required signedMessages,
              required password,
              required saltBase64,
            }) async {
              completionCount++;
              committed = true;
              return _migrationResult();
            },
        getKeystoneProofStatus: ({required requestId}) async =>
            const rust_sync.KeystoneMigrationProofStatus(
              readyCount: 1,
              totalCount: 1,
              isReady: true,
              isFailed: false,
            ),
      );

      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/keystone/batch/sign',
          migrationService: service,
          migrationCoordinator: () => coordinator,
          hardware: true,
          realKeystoneBatchRoute: true,
          statusLoader: () async => status(),
        ),
      );
      await tester.pumpAndSettle();

      final nextButton = find.byKey(
        const ValueKey('mobile_ironwood_keystone_signing_next'),
      );
      await tester.ensureVisible(nextButton);
      await tester.tap(nextButton);
      await tester.pump();
      tester
          .widget<KeystoneQrScannerCard>(find.byType(KeystoneQrScannerCard))
          .onComplete(
            const ScanResult(urType: 'zcash-batch-sig-result', data: [1]),
          );
      await tester.pumpAndSettle();

      expect(completionCount, 1);
      expect(credentialStore.bindCallCount, 2);
      expect(coordinator.refreshCount, greaterThanOrEqualTo(1));
      expect(
        coordinator.exposedState.childProofBatchPermits,
        isNot(contains('account-1')),
      );
      expect(
        coordinator.exposedState.foregroundProgressPermits,
        contains('account-1'),
      );
      expect(
        find.byType(MobileIronwoodMigrationKeystoneBatchSignScreen),
        findsNothing,
      );
      expect(
        find.text('This Keystone signing request expired. Prepare it again.'),
        findsNothing,
      );
    },
  );

  testWidgets('accepts a Keystone plan split into bounded signing requests', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/options',
        migrationService: _migrationService(
          ios: true,
          getNotificationAuthorizationStatus: () async =>
              IronwoodMigrationNotificationAuthorizationStatus.authorized,
        ),
        hardware: true,
        privatePlan: _planWith(
          denominationSplitStageCount: 13,
          signingBatchLimit: 12,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.text('Ready to sign'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey('mobile_ironwood_migration_start_continue_button'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('keystone combined sign route:12'), findsOneWidget);
  });

  testWidgets('accepts exactly 40 transactions in each Keystone round', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/options',
        migrationService: _migrationService(
          ios: true,
          getNotificationAuthorizationStatus: () async =>
              IronwoodMigrationNotificationAuthorizationStatus.authorized,
        ),
        hardware: true,
        privatePlan: _planWith(
          denominationSplitStageCount: 40,
          plannedBatchCount: 40,
          signingBatchLimit: 40,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.text('Ready to sign'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey('mobile_ironwood_migration_start_continue_button'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('keystone combined sign route:40'), findsOneWidget);
  });

  testWidgets('supports 41 Keystone transactions across signing requests', (
    tester,
  ) async {
    _useMobileViewport(tester);
    for (final plan in [
      _planWith(
        denominationSplitStageCount: 41,
        plannedBatchCount: 40,
        signingBatchLimit: 40,
      ),
      _planWith(
        denominationSplitStageCount: 40,
        plannedBatchCount: 41,
        signingBatchLimit: 40,
      ),
    ]) {
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/options',
          migrationService: _migrationService(
            ios: true,
            getNotificationAuthorizationStatus: () async =>
                IronwoodMigrationNotificationAuthorizationStatus.authorized,
          ),
          hardware: true,
          privatePlan: plan,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(find.text('Ready to sign'), findsOneWidget);
      await tester.tap(
        find.byKey(
          const ValueKey('mobile_ironwood_migration_start_continue_button'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'keystone combined sign route:${plan.scheduledTransfers.length}',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets(
    'leaving Keystone signing discards the request and reopening prepares a fresh one',
    (tester) async {
      _useMobileViewport(tester, size: const Size(320, 568));
      var prepareCount = 0;
      final discardedRequestIds = <String>[];
      final discardStarted = Completer<void>();
      final finishDiscard = Completer<void>();
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                _status(phase: kIronwoodMigrationReadyPhase),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                _plan,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        getEndpoint: () => defaultRpcEndpointConfig('main'),
        prepareKeystoneDenominationMigration:
            ({required dbPath, required network, required accountUuid}) async {
              prepareCount += 1;
              return rust_sync.KeystoneMigrationSigningRequest(
                requestId: 'request-$prepareCount',
                messages: [
                  rust_sync.KeystoneMigrationMessage(
                    id: 'message-$prepareCount',
                    redactedPczt: Uint8List.fromList([prepareCount]),
                  ),
                ],
                signingBatchLimit: 50,
              );
            },
        getKeystoneProofStatus: ({required requestId}) async =>
            const rust_sync.KeystoneMigrationProofStatus(
              readyCount: 1,
              totalCount: 1,
              isReady: true,
              isFailed: false,
            ),
        discardKeystoneMigrationRequest: ({required requestId}) async {
          discardedRequestIds.add(requestId);
          if (!discardStarted.isCompleted) {
            discardStarted.complete();
          }
          await finishDiscard.future;
        },
      );

      Widget signingApp() => ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap(hardware: true)),
          ironwoodMigrationServiceProvider.overrideWithValue(service),
        ],
        child: AppTheme(
          data: AppThemeData.light,
          child: const MaterialApp(
            home: MobileIronwoodMigrationKeystoneDenominationSignScreen(),
          ),
        ),
      );

      await tester.pumpWidget(signingApp());
      final qr = find.byKey(const ValueKey('mobile_ironwood_keystone_qr'));
      for (var attempt = 0; attempt < 20 && !tester.any(qr); attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(prepareCount, 1);
      expect(qr, findsOneWidget);
      expect(_rustApiFake.encodedMaxFragmentLengths, [BigInt.from(300)]);
      expect(
        tester.widget<KeystonePcztQrStage>(qr).frameInterval,
        const Duration(milliseconds: 200),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await discardStarted.future;
      expect(discardedRequestIds, ['request-1']);

      await tester.pumpWidget(signingApp());
      await tester.pump(const Duration(milliseconds: 100));
      expect(prepareCount, 1);

      finishDiscard.complete();
      for (var attempt = 0; attempt < 20 && !tester.any(qr); attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(prepareCount, 2);
      expect(qr, findsOneWidget);
      expect(_rustApiFake.encodedMaxFragmentLengths, [
        BigInt.from(300),
        BigInt.from(300),
      ]);
    },
  );

  testWidgets('routes a Keystone ready state to migration batch signing', (
    tester,
  ) async {
    _useMobileViewport(tester, size: const Size(320, 568));
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationReadyToMigratePhase,
          targetValues: List<int>.filled(50, 100_000_000),
        ),
        hardware: true,
      ),
    );
    await tester.pumpAndSettle();

    final signButton = find.byKey(
      const ValueKey('mobile_ironwood_keystone_batch_sign_button'),
    );
    expect(find.text('All transactions'), findsOneWidget);
    expect(find.text('50 ZEC (100%)'), findsOneWidget);
    expect(find.text('Sign migration transactions'), findsOneWidget);
    await tester.ensureVisible(signButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(signButton);
    await tester.pumpAndSettle();

    expect(find.text('keystone batch sign route'), findsOneWidget);
  });

  testWidgets('routes a Keystone re-sign state from Needs input', (
    tester,
  ) async {
    _useMobileViewport(tester, size: const Size(320, 568));
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationReadyToMigratePhase,
          parts: [
            rust_sync.MigrationPartStatus(
              partIndex: 0,
              valueZatoshi: BigInt.from(412_000_000),
              state: rust_sync.MigrationPartState.completed,
              txidHex: 'confirmed-tx',
              scheduledHeight: 2_999_900,
              confirmationCount: 3,
              confirmationTarget: 3,
            ),
            rust_sync.MigrationPartStatus(
              partIndex: 1,
              valueZatoshi: BigInt.from(412_000_000),
              state: rust_sync.MigrationPartState.needsInput,
              txidHex: 'expired-tx',
              scheduledHeight: 3_000_000,
              confirmationCount: 0,
              confirmationTarget: 3,
            ),
          ],
        ),
        hardware: true,
      ),
    );
    await tester.pumpAndSettle();

    final signButton = find.byKey(
      const ValueKey('mobile_ironwood_keystone_batch_sign_button'),
    );
    expect(find.text('Transactions needing signature'), findsOneWidget);
    expect(find.text('4.12 ZEC (50%)'), findsOneWidget);
    expect(find.text('Re-sign migration transactions'), findsOneWidget);
    await tester.ensureVisible(signButton);
    await tester.pumpAndSettle();
    await tester.tap(signButton);
    await tester.pumpAndSettle();

    expect(find.text('keystone batch sign route'), findsOneWidget);
  });

  testWidgets('continues a signed Keystone proof step without opening QR', (
    tester,
  ) async {
    _useMobileViewport(tester, size: const Size(320, 568));
    var continueCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(
          onContinue: (_) async {
            continueCount++;
            return _migrationResult();
          },
        ),
        status: _status(
          phase: kIronwoodMigrationReadyToMigratePhase,
          signedChildPcztCount: 1,
          nextActionHeight: 3_000_000,
        ),
        hardware: true,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 3_000_000,
          chainTipHeight: 3_000_000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final action = find.byKey(
      const ValueKey('mobile_ironwood_keystone_batch_sign_button'),
    );
    expect(find.text('Prepare batch #1'), findsOneWidget);
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(continueCount, greaterThanOrEqualTo(1));
    expect(find.text('keystone batch sign route'), findsNothing);
  });

  testWidgets(
    'keeps a height-due Keystone proof gated until preflight passes',
    (tester) async {
      _useMobileViewport(tester, size: const Size(320, 568));
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationService: _migrationService(),
          status: _status(
            phase: kIronwoodMigrationReadyToMigratePhase,
            signedChildPcztCount: 1,
            nextActionHeight: 3_000_000,
            proofReady: false,
          ),
          hardware: true,
          syncState: SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            scannedHeight: 3_000_000,
            chainTipHeight: 3_000_000,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Prepare batch #1'), findsNothing);
      expect(
        find.byKey(
          const ValueKey('mobile_ironwood_keystone_batch_sign_button'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('keeps proof preparation visibly busy until status refresh', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'zcash_ironwood_migration_preparation_complete_seen_run-1': true,
    });
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    _useMobileViewport(tester, size: const Size(320, 568));
    final proofPreparation = Completer<rust_sync.IronwoodMigrationResult>();
    final syncNotifier = FakeSyncNotifier(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        scannedHeight: 3_000_000,
        chainTipHeight: 3_000_000,
      ),
    );
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(
          onContinue: (_) => proofPreparation.future,
        ),
        status: _status(
          phase: kIronwoodMigrationReadyToMigratePhase,
          signedChildPcztCount: 1,
          nextActionHeight: 3_000_000,
        ),
        hardware: true,
        syncNotifier: syncNotifier,
      ),
    );
    await tester.pumpAndSettle();

    final action = find.byKey(
      const ValueKey('mobile_ironwood_keystone_batch_sign_button'),
    );
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pump();

    expect(find.text('Preparing batch #1...'), findsOneWidget);
    expect(
      find.descendant(of: action, matching: find.byType(AppLoadingIcon)),
      findsOneWidget,
    );

    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncing: true,
        scannedHeight: 3_000_000,
        chainTipHeight: 3_000_001,
      ),
    );
    await tester.pump(const Duration(milliseconds: 850));
    expect(find.text('Preparing batch #1...'), findsOneWidget);
    expect(find.text('Syncing migration progress'), findsNothing);

    proofPreparation.complete(_migrationResult());
    await tester.pumpAndSettle();

    expect(find.text('Syncing the migration progress.'), findsOneWidget);

    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncComplete: true,
        scannedHeight: 3_000_001,
        chainTipHeight: 3_000_001,
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('groups migration parts into eight-part action batches', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final parts = [
      for (var index = 0; index < 10; index++)
        rust_sync.MigrationPartStatus(
          partIndex: index,
          scheduleOrder: index == 8 ? 0 : index + 1,
          valueZatoshi: BigInt.from(100_000_000),
          state: index < 8
              ? rust_sync.MigrationPartState.completed
              : rust_sync.MigrationPartState.needsInput,
          confirmationCount: index < 8 ? 3 : 0,
          confirmationTarget: 3,
        ),
    ];
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationReadyToMigratePhase,
          parts: parts,
          targetValues: List<int>.filled(10, 100_000_000),
          currentSigningPartIndices: const [8, 9],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ready to sign'), findsOneWidget);
    expect(find.text('Batch #2'), findsOneWidget);
    expect(find.text('2 ZEC (20%)'), findsOneWidget);
    expect(find.text('Prepare batch #2'), findsOneWidget);
    final ring = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == '_MigrationRingPainter',
      ),
    );
    final painter = ring.painter as dynamic;
    expect(painter.segments, 10);
    expect(painter.completedSegments, {
      for (var index = 1; index <= 8; index++) index,
    });
    expect(painter.highlightedSegments, {0, 9});
    expect(painter.visibleSegmentGap, 4);
    expect(painter.highlightedSegmentOffset, 3.5);
    expect(painter.highlightedOuterOutlineWidth, 18);
    expect(painter.highlightedOutlineWidth, 16);
    expect(tester.getCenter(find.text('2 ZEC (20%)')).dx, greaterThan(250));
  });

  testWidgets('keeps action batch selection in part-index order', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final parts = [
      for (var index = 0; index < 10; index++)
        rust_sync.MigrationPartStatus(
          partIndex: index,
          scheduleOrder: index == 8 ? 0 : index + 1,
          valueZatoshi: BigInt.from(100_000_000),
          state: index == 2 || index == 8
              ? rust_sync.MigrationPartState.needsInput
              : rust_sync.MigrationPartState.scheduled,
          confirmationCount: 0,
          confirmationTarget: 3,
        ),
    ];
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationReadyToMigratePhase,
          parts: parts,
          targetValues: List<int>.filled(10, 100_000_000),
          currentSigningPartIndices: const [2, 8],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Batch #1'), findsOneWidget);
    expect(find.text('8 ZEC (80%)'), findsOneWidget);
    expect(find.text('Prepare batch #1'), findsOneWidget);
  });

  testWidgets('highlights every part in the initial signing request', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final parts = [
      for (var index = 0; index < 10; index++)
        rust_sync.MigrationPartStatus(
          partIndex: index,
          scheduleOrder: index,
          valueZatoshi: BigInt.from(100_000_000),
          state: rust_sync.MigrationPartState.preparing,
          confirmationCount: 0,
          confirmationTarget: 3,
        ),
    ];
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationReadyToMigratePhase,
          parts: parts,
          targetValues: List<int>.filled(10, 100_000_000),
          currentSigningPartIndices: List<int>.generate(10, (index) => index),
        ),
        hardware: true,
      ),
    );
    await tester.pumpAndSettle();

    final ring = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('mobile_ironwood_migration_attention_ring')),
    );
    final painter = ring.painter as dynamic;
    expect(painter.highlightedSegments, {
      for (var index = 0; index < 10; index++) index,
    });
  });

  testWidgets('marks broadcast parts awaiting confirmation on the ring', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final parts = [
      for (var index = 0; index < 4; index++)
        rust_sync.MigrationPartStatus(
          partIndex: index,
          scheduleOrder: index,
          valueZatoshi: BigInt.from(100_000_000),
          state: switch (index) {
            0 => rust_sync.MigrationPartState.completed,
            // Rust reports a broadcast part as migrating until it is mined and
            // confirming until it reaches its target, so the ring has to treat
            // both as awaiting.
            1 => rust_sync.MigrationPartState.migrating,
            2 => rust_sync.MigrationPartState.confirming,
            _ => rust_sync.MigrationPartState.scheduled,
          },
          confirmationCount: index == 0 ? 3 : 0,
          confirmationTarget: 3,
        ),
    ];
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationWaitingConfirmationsPhase,
          parts: parts,
          targetValues: List<int>.filled(4, 100_000_000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final ring = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('mobile_ironwood_migration_attention_ring')),
    );
    final painter = ring.painter as dynamic;
    // A broadcast part reads as a dimmed form of the confirmed colour, never as
    // untouched track: the user just watched those transfers leave.
    expect(painter.completedSegments, {0});
    expect(painter.awaitingSegments, {1, 2});
  });

  testWidgets(
    'highlights only the multiple parts marked for the signing request',
    (tester) async {
      _useMobileViewport(tester);
      final parts = [
        for (var index = 0; index < 12; index++)
          rust_sync.MigrationPartStatus(
            partIndex: index,
            scheduleOrder: index,
            valueZatoshi: BigInt.from(100_000_000),
            state: index == 1 || index == 10
                ? rust_sync.MigrationPartState.needsInput
                : rust_sync.MigrationPartState.scheduled,
            confirmationCount: 0,
            confirmationTarget: 3,
          ),
      ];
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationService: _migrationService(),
          status: _status(
            phase: kIronwoodMigrationReadyToMigratePhase,
            parts: parts,
            targetValues: List<int>.filled(12, 100_000_000),
            currentSigningPartIndices: const [1, 10],
          ),
          hardware: true,
        ),
      );
      await tester.pumpAndSettle();

      final ring = tester.widget<CustomPaint>(
        find.byKey(const ValueKey('mobile_ironwood_migration_attention_ring')),
      );
      final painter = ring.painter as dynamic;
      expect(painter.highlightedSegments, {1, 10});
    },
  );

  testWidgets('pulses only the current migration signing parts', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final parts = [
      for (var index = 0; index < 12; index++)
        rust_sync.MigrationPartStatus(
          partIndex: index,
          scheduleOrder: index,
          valueZatoshi: BigInt.from(100_000_000),
          state: index == 1 || index == 10
              ? rust_sync.MigrationPartState.needsInput
              : rust_sync.MigrationPartState.scheduled,
          confirmationCount: 0,
          confirmationTarget: 3,
        ),
    ];
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationReadyToMigratePhase,
          parts: parts,
          targetValues: List<int>.filled(12, 100_000_000),
          currentSigningPartIndices: const [1, 10],
        ),
        hardware: true,
        disableAnimations: false,
      ),
    );

    final ringFinder = find.byKey(
      const ValueKey('mobile_ironwood_migration_attention_ring'),
    );
    for (var attempt = 0; attempt < 20 && !tester.any(ringFinder); attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    ({Set<int> highlightedSegments, double highlightOpacity}) painter() {
      final customPaint = tester.widget<CustomPaint>(ringFinder);
      final ringPainter = customPaint.painter as dynamic;
      return (
        highlightedSegments: Set<int>.of(
          ringPainter.highlightedSegments as Set<int>,
        ),
        highlightOpacity: ringPainter.highlightOpacity as double,
      );
    }

    expect(painter().highlightedSegments, {1, 10});
    expect(painter().highlightOpacity, closeTo(0.68, 0.0001));

    await tester.pump(const Duration(milliseconds: 900));
    expect(painter().highlightOpacity, closeTo(1, 0.0001));

    await tester.pump(const Duration(milliseconds: 900));
    expect(painter().highlightOpacity, closeTo(0.68, 0.0001));
  });

  testWidgets(
    'keeps migration signing parts fully visible with reduced motion',
    (tester) async {
      _useMobileViewport(tester);
      final parts = [
        for (var index = 0; index < 12; index++)
          rust_sync.MigrationPartStatus(
            partIndex: index,
            scheduleOrder: index,
            valueZatoshi: BigInt.from(100_000_000),
            state: index == 1 || index == 10
                ? rust_sync.MigrationPartState.needsInput
                : rust_sync.MigrationPartState.scheduled,
            confirmationCount: 0,
            confirmationTarget: 3,
          ),
      ];
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationService: _migrationService(),
          status: _status(
            phase: kIronwoodMigrationReadyToMigratePhase,
            parts: parts,
            targetValues: List<int>.filled(12, 100_000_000),
            currentSigningPartIndices: const [1, 10],
          ),
          hardware: true,
        ),
      );
      await tester.pumpAndSettle();

      final ringFinder = find.byKey(
        const ValueKey('mobile_ironwood_migration_attention_ring'),
      );
      double opacity() {
        final customPaint = tester.widget<CustomPaint>(ringFinder);
        final painter = customPaint.painter as dynamic;
        return painter.highlightOpacity as double;
      }

      final ring = tester.widget<CustomPaint>(ringFinder);
      final ringPainter = ring.painter as dynamic;
      expect(ringPainter.highlightedSegments, {1, 10});
      expect(opacity(), 1);
      await tester.pump(const Duration(milliseconds: 800));
      expect(opacity(), 1);
    },
  );

  testWidgets('orders migration ring by current scheduled execution', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final parts = [
      rust_sync.MigrationPartStatus(
        partIndex: 2,
        scheduleOrder: 0,
        scheduledHeight: 3_000_200,
        txidHex: 'bb',
        valueZatoshi: BigInt.from(300_000_000),
        state: rust_sync.MigrationPartState.completed,
        confirmationCount: 3,
        confirmationTarget: 3,
      ),
      rust_sync.MigrationPartStatus(
        partIndex: 0,
        scheduleOrder: 2,
        scheduledHeight: 3_000_100,
        txidHex: 'cc',
        valueZatoshi: BigInt.from(100_000_000),
        state: rust_sync.MigrationPartState.scheduled,
        confirmationCount: 0,
        confirmationTarget: 3,
      ),
      rust_sync.MigrationPartStatus(
        partIndex: 1,
        scheduleOrder: 1,
        scheduledHeight: 3_000_200,
        txidHex: 'aa',
        valueZatoshi: BigInt.from(200_000_000),
        state: rust_sync.MigrationPartState.needsInput,
        confirmationCount: 0,
        confirmationTarget: 3,
      ),
    ];
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationReadyToMigratePhase,
          parts: parts,
          targetValues: const [100_000_000, 200_000_000, 300_000_000],
          currentSigningPartIndices: const [1],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final ring = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == '_MigrationRingPainter',
      ),
    );
    final painter = ring.painter as dynamic;
    final weights = painter.segmentWeights as List<double>;
    expect(weights, hasLength(3));
    expect(weights[0], closeTo(1 / 6, 0.000001));
    expect(weights[1], closeTo(3 / 6, 0.000001));
    expect(weights[2], closeTo(2 / 6, 0.000001));
    expect(weights.reduce((sum, value) => sum + value), closeTo(1, 1e-12));
    expect(painter.completedSegments, {1});
    expect(painter.highlightedSegments, {2});
    expect(painter.highlightedSegmentOffset, 3.5);
  });

  testWidgets('records a Keystone signing action while status is visible', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final status = _status(
      phase: kIronwoodMigrationReadyToMigratePhase,
      nextActionHeight: 3_000_000,
    );
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: status,
        hardware: true,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 3_000_000,
          chainTipHeight: 3_000_000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(
      find.byType(MobileIronwoodMigrationPrivateStatusScreen),
    );
    final container = ProviderScope.containerOf(context);
    final attention = mobileIronwoodMigrationAttention(
      status,
      currentHeight: 3_000_000,
      broadcastHeight: 3_000_000,
      isHardware: true,
    )!;
    final fingerprint = mobileIronwoodMigrationAttentionFingerprint(
      accountUuid: 'account-1',
      runId: status.activeRunId!,
      status: status,
      attention: attention,
    );

    expect(
      container.read(mobileIronwoodMigrationAttentionSessionProvider),
      contains(fingerprint),
    );
  });

  testWidgets('shows durable paused and recoverable failures as actionable', (
    tester,
  ) async {
    _useMobileViewport(tester);

    for (final (phase, message, label) in [
      (
        kIronwoodMigrationPausedPhase,
        'Migration paused after the background task stopped.',
        'Resume',
      ),
      (
        kIronwoodMigrationFailedRecoverablePhase,
        'A temporary migration failure needs your attention.',
        'Retry',
      ),
    ]) {
      final coordinator = _DurablePhaseRetryTestMigrationCoordinator();
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationService: _migrationService(),
          migrationCoordinator: () => coordinator,
          status: _status(phase: phase, message: message),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(find.text(label), findsOneWidget);

      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(coordinator.retryCount, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('marks the displayed account seen, not a stale published one', (
    tester,
  ) async {
    // The completion provider keeps serving its previous value while it
    // reloads, so right after an account switch the published identity can
    // still be the account the user left. Trusting it would mark that account
    // seen while the one on screen stays unseen and keeps being routed back to.
    _useMobileViewport(tester);
    final seen = <String>[];
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationCompletePhase,
          targetValues: const [412_000_000],
        ),
        extraOverrides: [
          ironwoodMigrationCompletionStoreProvider.overrideWithValue(
            _RecordingCompletionStore(seen),
          ),
          ironwoodMigrationCompletionProvider.overrideWith(
            (ref) => IronwoodMigrationCompletionState.visible(
              network: 'main',
              accountUuid: 'account-left-behind',
              completionId: 'stale-completion',
              transferredZatoshi: BigInt.from(412_000_000),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(seen, hasLength(1));
    expect(seen.single, startsWith('main:account-1:'));
  });

  testWidgets('completion route keeps the result after marking it seen', (
    tester,
  ) async {
    // Marking a completion seen invalidates the provider that published it, so
    // `visible` flips to false right after this screen appears. Reading the
    // provider on every build would redirect home and flash the result past —
    // the behaviour this dedicated route exists to remove.
    _useMobileViewport(tester);
    final seen = <String>[];
    final completion = ValueNotifier<IronwoodMigrationCompletionState>(
      IronwoodMigrationCompletionState.visible(
        network: 'main',
        accountUuid: 'account-1',
        completionId: 'completion-1',
        transferredZatoshi: BigInt.from(412_000_000),
      ),
    );
    addTearDown(completion.dispose);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/complete',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationCompletePhase,
          targetValues: const [412_000_000],
        ),
        extraOverrides: [
          ironwoodMigrationCompletionStoreProvider.overrideWithValue(
            _RecordingCompletionStore(seen),
          ),
          ironwoodMigrationCompletionProvider.overrideWith(
            (ref) => completion.value,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You’re all set!'), findsOneWidget);
    expect(seen, hasLength(1));

    completion.value = const IronwoodMigrationCompletionState.hidden();
    await tester.pumpAndSettle();

    expect(find.text('You’re all set!'), findsOneWidget);
    expect(find.text('home route'), findsNothing);
  });

  testWidgets('completion headline never renders a placeholder amount', (
    tester,
  ) async {
    // The preview gallery's sample total must not reach a real user as their
    // migration result, and an absent amount must not leave the headline with
    // a blank line where the total belongs.
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/complete',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationCompletePhase,
          targetValues: const [412_000_000],
        ),
        extraOverrides: [
          ironwoodMigrationCompletionStoreProvider.overrideWithValue(
            _RecordingCompletionStore(<String>[]),
          ),
          ironwoodMigrationCompletionProvider.overrideWith(
            (ref) => IronwoodMigrationCompletionState.visible(
              network: 'main',
              accountUuid: 'account-1',
              completionId: 'completion-1',
              transferredZatoshi: BigInt.from(412_000_000),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('142.992'), findsNothing);
    expect(find.textContaining('4.12 ZEC'), findsOneWidget);
  });

  testWidgets('completion route returns home when nothing completed', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/complete',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationCompletePhase,
          targetValues: const [412_000_000],
        ),
        extraOverrides: [
          ironwoodMigrationCompletionProvider.overrideWith(
            (ref) => const IronwoodMigrationCompletionState.hidden(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You’re all set!'), findsNothing);
    expect(find.text('home route'), findsOneWidget);
  });

  testWidgets('returns home from the full-screen completion state', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final status = _status(
      phase: kIronwoodMigrationCompletePhase,
      targetValues: const [412_000_000],
    );
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: status,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You’re all set!'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('home route'), findsOneWidget);
  });

  testWidgets('retries a late Keystone broadcast without opening QR', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var continueCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(
          onContinue: (_) async {
            continueCount++;
            return _migrationResult();
          },
        ),
        status: _status(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          signedChildPcztCount: 1,
          nextActionHeight: 3_000_000,
          broadcastStatuses: const ['scheduled'],
        ),
        hardware: true,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 3_000_100,
          chainTipHeight: 3_000_100,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final action = find.byKey(
      const ValueKey('mobile_ironwood_keystone_batch_sign_button'),
    );
    expect(find.text('Retry broadcast'), findsOneWidget);
    expect(find.textContaining('Sign batch'), findsNothing);
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    tester.widget<AppButton>(action).onPressed?.call();
    await tester.pumpAndSettle();

    expect(continueCount, greaterThanOrEqualTo(1));
    expect(find.text('keystone batch sign route'), findsNothing);
  });

  testWidgets(
    'uses the due Keystone proof batch before a later scheduled broadcast',
    (tester) async {
      _useMobileViewport(tester, size: const Size(320, 568));
      final parts = [
        for (var index = 0; index < 9; index++)
          rust_sync.MigrationPartStatus(
            partIndex: index,
            valueZatoshi: BigInt.from(100_000_000),
            state: rust_sync.MigrationPartState.scheduled,
            txidHex: index == 0 ? 'tx-0' : 'part-$index',
            scheduledHeight: 3_000_000 + index,
            confirmationCount: 0,
            confirmationTarget: 3,
          ),
      ];
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationService: _migrationService(),
          status: _status(
            phase: kIronwoodMigrationBroadcastScheduledPhase,
            targetValues: List<int>.filled(9, 100_000_000),
            signedChildPcztCount: 9,
            nextActionHeight: 3_000_100,
            nextActionPartIndex: 8,
            scheduledBroadcasts: [
              rust_sync.MigrationScheduledBroadcast(
                txidHex: 'tx-0',
                valueZatoshi: BigInt.from(100_000_000),
                scheduledAtMs: DateTime(2026, 7, 20, 10).millisecondsSinceEpoch,
                scheduledHeight: 3_000_200,
                status: 'scheduled',
              ),
            ],
            parts: parts,
          ),
          hardware: true,
          syncState: SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            scannedHeight: 3_000_100,
            chainTipHeight: 3_000_100,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Prepare batch #2'), findsOneWidget);
      expect(find.text('Batch #2'), findsOneWidget);
      expect(find.text('Retry broadcast'), findsNothing);
    },
  );

  testWidgets('shows a retry when a private draft cannot be saved', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/options',
        migrationService: _migrationService(
          ios: true,
          getNotificationAuthorizationStatus: () async =>
              IronwoodMigrationNotificationAuthorizationStatus.authorized,
          onCreatePrivateDraft: (_, _) async =>
              throw StateError('draft write failed'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.text("Couldn't start migration. Try again."), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('mobile_ironwood_migration_start_retry_button'),
      ),
      findsOneWidget,
    );
    expect(find.text('Choose How to Migrate').hitTestable(), findsNothing);
  });

  testWidgets(
    'opens status when draft persistence reports an error after committing',
    (tester) async {
      _useMobileViewport(tester);
      final draftStatus = _status(
        phase: kIronwoodMigrationAwaitingPreparationPhase,
        activeRunId: 'committed-draft-run',
      );
      var draftCommitted = false;
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/options',
          migrationService: _migrationService(
            ios: true,
            getNotificationAuthorizationStatus: () async =>
                IronwoodMigrationNotificationAuthorizationStatus.authorized,
            onCreatePrivateDraft: (_, _) async {
              draftCommitted = true;
              throw StateError('credential reconciliation failed');
            },
          ),
          ctaBuilder: () => draftCommitted
              ? IronwoodHomeMigrationCtaState.resume(
                  network: 'main',
                  accountUuid: 'account-1',
                  status: draftStatus,
                )
              : const IronwoodHomeMigrationCtaState.start(
                  network: 'main',
                  accountUuid: 'account-1',
                ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't start the migration. Try again."),
        findsNothing,
      );
      expect(find.text('Preparing your migration'), findsOneWidget);
    },
  );

  testWidgets(
    'opens status when fresh preparation errors after saving a draft',
    (tester) async {
      _useMobileViewport(tester);
      var started = false;
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/options',
          migrationService: _migrationService(
            ios: true,
            getNotificationAuthorizationStatus: () async =>
                IronwoodMigrationNotificationAuthorizationStatus.authorized,
            onStart: (_, _) {
              started = true;
              return Future.error(StateError('post-start failure'));
            },
          ),
          startedStatus: _status(
            phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
            activeRunId: 'run-1',
          ),
          ctaBuilder: () => started
              ? IronwoodHomeMigrationCtaState.resume(
                  network: 'main',
                  accountUuid: 'account-1',
                  status: _status(
                    phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
                  ),
                )
              : const IronwoodHomeMigrationCtaState.start(
                  network: 'main',
                  accountUuid: 'account-1',
                ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't start migration. Try again."), findsNothing);
      expect(find.text('Preparing your migration'), findsOneWidget);
    },
  );

  testWidgets('maps a live denomination status to Preparing', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
          parts: [
            rust_sync.MigrationPartStatus(
              partIndex: 0,
              valueZatoshi: BigInt.from(412_000_000),
              state: rust_sync.MigrationPartState.confirming,
              confirmationCount: 2,
              confirmationTarget: 3,
            ),
            rust_sync.MigrationPartStatus(
              partIndex: 1,
              valueZatoshi: BigInt.from(412_000_000),
              state: rust_sync.MigrationPartState.preparing,
              confirmationCount: 0,
              confirmationTarget: 3,
            ),
            rust_sync.MigrationPartStatus(
              partIndex: 2,
              valueZatoshi: BigInt.from(412_000_000),
              state: rust_sync.MigrationPartState.preparing,
              confirmationCount: 0,
              confirmationTarget: 3,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preparing your migration'), findsOneWidget);
    // Notifications are unauthorized in this setup, so the run cannot be
    // tracked in the background at all. The pause copy names that cause
    // instead of implying the user walked away.
    expect(
      find.text(
        'Allow notifications to continue in the background, or keep '
        'Vizor open.',
      ),
      findsOneWidget,
    );
    expect(find.text('Continue preparation'), findsOneWidget);
    final continueButton = tester.widget<AppButton>(
      find.ancestor(
        of: find.text('Continue preparation'),
        matching: find.byType(AppButton),
      ),
    );
    expect(
      continueButton.leading,
      isA<AppIcon>().having((icon) => icon.name, 'icon name', AppIcons.play),
    );
  });

  testWidgets('explains the additional Keystone approval while waiting', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
        ),
        hardware: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preparing your migration'), findsOneWidget);
    expect(find.text('Continue preparation'), findsOneWidget);
  });

  testWidgets(
    'shows the preparation sync surface immediately when entering during sync',
    (tester) async {
      _useMobileViewport(tester);
      final coordinator = _SuccessfulEntrySyncTestMigrationCoordinator();
      final syncNotifier = FakeSyncNotifier(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncing: true,
        ),
      );
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationService: _migrationService(
            ios: true,
            getNotificationAuthorizationStatus: () async =>
                IronwoodMigrationNotificationAuthorizationStatus.authorized,
            getPreparationRuntimeState:
                ({
                  required network,
                  required accountUuid,
                  required runId,
                }) async => IronwoodMigrationPreparationRuntimeState.running,
          ),
          migrationCoordinator: () => coordinator,
          status: _status(
            phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
          ),
          syncNotifier: syncNotifier,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(coordinator.synchronizeCount, 0);
      expect(find.text('Syncing your wallet…'), findsOneWidget);
      expect(find.text('Preparation will\ntake 10–20 min'), findsNothing);

      await tester.pump(const Duration(milliseconds: 850));

      expect(find.text('Syncing your wallet…'), findsOneWidget);
      expect(find.text('Ironwood Migration'), findsNothing);
      expect(find.text('Continue preparation'), findsNothing);
      expect(find.text('Available in Ironwood'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.loader,
        ),
        findsOneWidget,
      );

      syncNotifier.emit(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncing: false,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Syncing your wallet…'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Syncing your wallet…'), findsNothing);
      expect(
        find.text('Confirming in the background. You can close Vizor.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('waits for initial and post-sync migration status refreshes', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final coordinator = _ControlledRefreshTestMigrationCoordinator();
    final status = _status(
      phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
    );
    final cta = IronwoodHomeMigrationCtaState.resume(
      network: 'main',
      accountUuid: 'account-1',
      status: status,
    );
    var ctaLoadCount = 0;
    final ctaRefreshes = <Completer<IronwoodHomeMigrationCtaState>>[];
    final syncNotifier = FakeSyncNotifier(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncComplete: true,
      ),
    );
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        migrationCoordinator: () => coordinator,
        status: status,
        ctaLoader: () {
          ctaLoadCount++;
          if (ctaLoadCount == 1) return Future.value(cta);
          final refresh = Completer<IronwoodHomeMigrationCtaState>();
          ctaRefreshes.add(refresh);
          return refresh.future;
        },
        syncNotifier: syncNotifier,
      ),
    );
    await tester.pump();

    expect(coordinator.refreshes, hasLength(1));
    expect(find.text('Syncing your wallet…'), findsOneWidget);
    expect(find.text('Preparation will\ntake 10–20 min'), findsNothing);

    coordinator.refreshes.first.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(ctaRefreshes, hasLength(1));
    expect(find.text('Syncing your wallet…'), findsOneWidget);

    ctaRefreshes.first.complete(cta);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Syncing your wallet…'), findsNothing);
    expect(find.text('Preparing your migration'), findsOneWidget);

    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncing: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Syncing your wallet…'), findsNothing);

    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Syncing your wallet…'), findsOneWidget);

    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncComplete: true,
      ),
    );
    await tester.pump();

    expect(coordinator.refreshes, hasLength(2));
    expect(find.text('Syncing your wallet…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Syncing your wallet…'), findsOneWidget);

    coordinator.refreshes.last.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(ctaRefreshes, hasLength(2));
    expect(find.text('Syncing your wallet…'), findsOneWidget);

    ctaRefreshes.last.complete(cta);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Syncing your wallet…'), findsNothing);
    expect(find.text('Preparing your migration'), findsOneWidget);
  });

  testWidgets(
    'maps denomination confirmation waiting into the preparation surface',
    (tester) async {
      _useMobileViewport(tester);
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationService: _migrationService(),
          status: _status(
            phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('mobile_ironwood_preparation_ring')),
        findsOneWidget,
      );
      expect(find.text('Preparing your migration'), findsOneWidget);
    },
  );

  testWidgets(
    'keeps the preparation complete modal visible during wallet sync',
    (tester) async {
      _useMobileViewport(tester);
      SharedPreferences.setMockInitialValues({});
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      final coordinator = _SuccessfulEntrySyncTestMigrationCoordinator();
      final syncNotifier = FakeSyncNotifier(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncing: false,
        ),
      );
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationService: _migrationService(),
          migrationCoordinator: () => coordinator,
          status: _status(phase: kIronwoodMigrationReadyToMigratePhase),
          syncNotifier: syncNotifier,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Preparation is done'), findsOneWidget);

      syncNotifier.emit(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncing: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 900));

      expect(find.text('Preparation is done'), findsOneWidget);
      expect(find.text('Syncing the migration progress.'), findsNothing);
    },
  );

  testWidgets(
    'shows migration syncing immediately before the initial status refresh',
    (tester) async {
      _useMobileViewport(tester);
      SharedPreferences.setMockInitialValues({
        'zcash_ironwood_migration_preparation_complete_seen_run-1': true,
      });
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      final coordinator = _SuccessfulEntrySyncTestMigrationCoordinator();
      final syncNotifier = FakeSyncNotifier(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncing: true,
        ),
      );
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationService: _migrationService(),
          migrationCoordinator: () => coordinator,
          status: _status(phase: kIronwoodMigrationWaitingConfirmationsPhase),
          syncNotifier: syncNotifier,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Syncing the migration progress.'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 850));

      expect(find.text('Syncing the migration progress.'), findsOneWidget);
      final ring = tester.widget<CustomPaint>(
        find.byKey(
          const ValueKey('mobile_ironwood_migration_sync_progress_ring'),
        ),
      );
      expect((ring.painter as dynamic).segments, 3);
      expect((ring.painter as dynamic).visibleSegmentGap, 4);
    },
  );

  testWidgets(
    'does not offer manual resume while preparation background work is active',
    (tester) async {
      _useMobileViewport(tester);
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationService: _migrationService(
            ios: true,
            getNotificationAuthorizationStatus: () async =>
                IronwoodMigrationNotificationAuthorizationStatus.authorized,
            getPreparationRuntimeState:
                ({
                  required network,
                  required accountUuid,
                  required runId,
                }) async => IronwoodMigrationPreparationRuntimeState.running,
          ),
          status: _status(
            phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Confirming in the background. You can close Vizor.'),
        findsOneWidget,
      );
      expect(find.text('Continue preparation'), findsNothing);
    },
  );

  testWidgets(
    'tells the user it is safe to leave once tracking is merely scheduled',
    (tester) async {
      _useMobileViewport(tester);
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationService: _migrationService(
            ios: true,
            getNotificationAuthorizationStatus: () async =>
                IronwoodMigrationNotificationAuthorizationStatus.authorized,
            getPreparationRuntimeState:
                ({
                  required network,
                  required accountUuid,
                  required runId,
                }) async => IronwoodMigrationPreparationRuntimeState.scheduled,
          ),
          status: _status(
            phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Confirming in the background. You can close Vizor.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tells the user to keep Vizor open while an advance is in flight',
    (tester) async {
      _useMobileViewport(tester);
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationCoordinator: _AdvancingTestMigrationCoordinator.new,
          migrationService: _migrationService(
            ios: true,
            getNotificationAuthorizationStatus: () async =>
                IronwoodMigrationNotificationAuthorizationStatus.authorized,
            getPreparationRuntimeState:
                ({
                  required network,
                  required accountUuid,
                  required runId,
                }) async => IronwoodMigrationPreparationRuntimeState.running,
          ),
          status: _status(
            phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // An advance holds the foreground permit, so leaving now stalls the run
      // until the next reentry. That must outrank the "safe to leave" copy
      // even though background tracking is also armed.
      expect(
        find.text('Preparing the next transactions. Keep Vizor open.'),
        findsOneWidget,
      );
      expect(
        find.text('Confirming in the background. You can close Vizor.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'names notifications as the reason background tracking cannot run',
    (tester) async {
      _useMobileViewport(tester);
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationService: _migrationService(
            ios: true,
            getNotificationAuthorizationStatus: () async =>
                IronwoodMigrationNotificationAuthorizationStatus.denied,
            getPreparationRuntimeState:
                ({
                  required network,
                  required accountUuid,
                  required runId,
                }) async => IronwoodMigrationPreparationRuntimeState.disabled,
          ),
          status: _status(
            phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Allow notifications to continue in the background, or keep '
          'Vizor open.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Preparation was paused because you left.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'waits for preparation runtime inspection before choosing resume state',
    (tester) async {
      _useMobileViewport(tester);
      final runtimeState =
          Completer<IronwoodMigrationPreparationRuntimeState>();
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationService: _migrationService(
            ios: true,
            getNotificationAuthorizationStatus: () async =>
                IronwoodMigrationNotificationAuthorizationStatus.authorized,
            getPreparationRuntimeState:
                ({required network, required accountUuid, required runId}) =>
                    runtimeState.future,
          ),
          status: _status(
            phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Syncing your wallet…'), findsOneWidget);
      expect(find.text('Continue preparation'), findsNothing);

      runtimeState.complete(IronwoodMigrationPreparationRuntimeState.running);
      await tester.pumpAndSettle();

      expect(
        find.text('Confirming in the background. You can close Vizor.'),
        findsOneWidget,
      );
      expect(find.text('Continue preparation'), findsNothing);
    },
  );

  testWidgets(
    'automatically continues preparation after native background handoff',
    (tester) async {
      _useMobileViewport(tester);
      final coordinator = _PreparationHandoffTestMigrationCoordinator();
      var acknowledgementCount = 0;
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationService: _migrationService(
            ios: true,
            getNotificationAuthorizationStatus: () async =>
                IronwoodMigrationNotificationAuthorizationStatus.authorized,
            getPreparationRuntimeState:
                ({
                  required network,
                  required accountUuid,
                  required runId,
                }) async => IronwoodMigrationPreparationRuntimeState
                    .foregroundContinuationPending,
            acknowledgePreparationForegroundContinuation:
                ({
                  required network,
                  required accountUuid,
                  required runId,
                }) async {
                  expect(coordinator.retryCount, 0);
                  acknowledgementCount++;
                },
          ),
          migrationCoordinator: () => coordinator,
          status: _status(
            phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(coordinator.retryCount, 1);
      expect(acknowledgementCount, 1);
      // The handoff resolves to `idle` with a foreground permit, not to an
      // armed background task, so this keeps the plain active copy.
      expect(find.text('Preparation will\ntake 10–20 min'), findsOneWidget);
      expect(find.text('Continue preparation'), findsNothing);
    },
  );

  testWidgets('releases handoff before failed continuation', (tester) async {
    _useMobileViewport(tester);
    final coordinator = _PreparationHandoffTestMigrationCoordinator(
      failRetry: true,
    );
    var acknowledgementCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(
          ios: true,
          getNotificationAuthorizationStatus: () async =>
              IronwoodMigrationNotificationAuthorizationStatus.authorized,
          getPreparationRuntimeState:
              ({
                required network,
                required accountUuid,
                required runId,
              }) async => IronwoodMigrationPreparationRuntimeState
                  .foregroundContinuationPending,
          acknowledgePreparationForegroundContinuation:
              ({required network, required accountUuid, required runId}) async {
                acknowledgementCount++;
              },
        ),
        migrationCoordinator: () => coordinator,
        status: _status(
          phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(coordinator.retryCount, 1);
    expect(acknowledgementCount, 1);
    expect(find.text('Continue preparation'), findsOneWidget);
  });

  testWidgets('maps live migration progress into the Migrating screen', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(phase: kIronwoodMigrationWaitingConfirmationsPhase),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ironwood Migration'), findsOneWidget);
    expect(find.text('4.12 ZEC'), findsOneWidget);
    expect(find.text('Left to migrate'), findsOneWidget);
    expect(find.text('8.24 ZEC'), findsOneWidget);
    expect(find.text('Est. completion'), findsOneWidget);
    expect(
      find.textContaining('Confirmations are still arriving'),
      findsOneWidget,
    );
    expect(find.textContaining('Signing window expected'), findsNothing);
  });

  testWidgets('does not present prepared denominations as migrated', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationReadyToMigratePhase,
          targetValues: const [1_000_000_000, 200_000_000],
          pendingTxCount: 0,
          broadcastedTxCount: 0,
          confirmedTxCount: 0,
          parts: [
            rust_sync.MigrationPartStatus(
              partIndex: 0,
              valueZatoshi: BigInt.from(1_000_000_000),
              state: rust_sync.MigrationPartState.completed,
              confirmationCount: 0,
              confirmationTarget: 3,
            ),
            rust_sync.MigrationPartStatus(
              partIndex: 1,
              valueZatoshi: BigInt.from(200_000_000),
              state: rust_sync.MigrationPartState.completed,
              confirmationCount: 0,
              confirmationTarget: 3,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Left to migrate'), findsOneWidget);
    expect(find.text('12.00 ZEC'), findsOneWidget);
    final dynamic painter = tester
        .widget<CustomPaint>(
          find.byKey(
            const ValueKey('mobile_ironwood_migration_attention_ring'),
          ),
        )
        .painter;
    expect(painter.completedSegments as Set<int>, isEmpty);
  });

  testWidgets('shows the next migration amount and opens its schedule', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final status = _status(
      phase: kIronwoodMigrationBroadcastScheduledPhase,
      targetValues: const [200_000_000, 400_000_000],
      estimatedCompletionHeight: 3_000_100,
      parts: [
        rust_sync.MigrationPartStatus(
          partIndex: 0,
          scheduleOrder: 0,
          valueZatoshi: BigInt.from(200_000_000),
          state: rust_sync.MigrationPartState.scheduled,
          scheduledHeight: 3_000_020,
          confirmationCount: 0,
          confirmationTarget: 3,
        ),
        rust_sync.MigrationPartStatus(
          partIndex: 1,
          scheduleOrder: 1,
          valueZatoshi: BigInt.from(400_000_000),
          state: rust_sync.MigrationPartState.scheduled,
          scheduledHeight: 3_000_080,
          confirmationCount: 0,
          confirmationTarget: 3,
        ),
      ],
    );
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: status,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 3_000_000,
          chainTipHeight: 3_000_000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Next migration'), findsOneWidget);
    expect(find.text('2 ZEC'), findsOneWidget);
    expect(find.text('3,000,020'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_view_schedule_button')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 800));
    final viewScheduleButton = find.descendant(
      of: find.byKey(const ValueKey('mobile_ironwood_view_schedule_button')),
      matching: find.byType(AppButton),
    );
    expect(viewScheduleButton, findsOneWidget);
    tester.widget<AppButton>(viewScheduleButton).onPressed?.call();
    await tester.pumpAndSettle();

    expect(find.text('Migration Schedule'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_migration_schedule_list')),
      findsOneWidget,
    );
    expect(find.text('Left to migrate'), findsNothing);
    expect(find.textContaining('1. 2 ZEC'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey('mobile_ironwood_migration_schedule_part_0'),
            ),
          )
          .height,
      72,
    );
    expect(find.text('Ironwood spendable'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey('mobile_ironwood_schedule_return_button'),
            ),
          )
          .width,
      greaterThan(300),
    );
  });

  testWidgets('opens the preparation transaction schedule from preparation', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final status = _status(
      phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
      preparationTransactions: [
        rust_sync.MigrationPreparationTransactionStatus(
          stageIndex: 0,
          approximateValueZatoshi: BigInt.from(600_020_000),
          round: 1,
          feeZatoshi: BigInt.from(20_000),
          plannedHeight: 3_000_010,
          projectedHeight: 3_000_010,
          projectedCompletionHeight: 3_000_020,
          outputs: [
            rust_sync.MigrationPreparationOutputStatus(
              valueZatoshi: BigInt.from(200_010_000),
              targetValueZatoshi: BigInt.from(200_000_000),
              kind: rust_sync.MigrationPreparationOutputKind.migration,
            ),
            rust_sync.MigrationPreparationOutputStatus(
              valueZatoshi: BigInt.from(400_000_000),
              kind: rust_sync.MigrationPreparationOutputKind.continuation,
              nextRound: 2,
            ),
          ],
          state: rust_sync.MigrationPreparationTransactionState.awaitingInputs,
          confirmationCount: 0,
          confirmationTarget: 3,
        ),
        rust_sync.MigrationPreparationTransactionStatus(
          stageIndex: 1,
          approximateValueZatoshi: BigInt.from(300_000_000),
          round: 1,
          feeZatoshi: BigInt.from(10_000),
          plannedHeight: 3_000_011,
          projectedHeight: 3_000_011,
          projectedCompletionHeight: 3_000_021,
          outputs: const [],
          state: rust_sync.MigrationPreparationTransactionState.confirming,
          confirmationCount: 2,
          confirmationTarget: 3,
        ),
        rust_sync.MigrationPreparationTransactionStatus(
          stageIndex: 2,
          approximateValueZatoshi: BigInt.from(250_000_000),
          round: 1,
          feeZatoshi: BigInt.from(10_000),
          plannedHeight: 3_000_012,
          projectedHeight: 3_000_012,
          projectedCompletionHeight: 3_000_022,
          outputs: const [],
          state: rust_sync.MigrationPreparationTransactionState.broadcasted,
          confirmationCount: 0,
          confirmationTarget: 3,
        ),
      ],
    );
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: status,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 3_000_000,
          chainTipHeight: 3_000_000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('mobile_ironwood_view_preparation_schedule_button'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preparation Schedule'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_preparation_schedule_list')),
      findsOneWidget,
    );
    expect(find.text('Split round 1'), findsOneWidget);
    expect(find.text('2 ZEC'), findsOneWidget);
    expect(find.text('Round 2'), findsOneWidget);
    expect(find.text('Rounds remaining'), findsOneWidget);
    expect(find.text('3,000,000'), findsOneWidget);

    final valueFinder = find.byKey(
      const ValueKey('mobile_ironwood_preparation_value_0'),
    );
    final valueText = tester.widget<Text>(valueFinder);
    final valueRect = tester.getRect(valueFinder);
    final stateRect = tester.getRect(
      find.byKey(const ValueKey('mobile_ironwood_preparation_state_0')),
    );
    final valueToStateGap = stateRect.left - valueRect.right;
    expect(
      valueText.data,
      matches(RegExp(r'^[\d.]+ ZEC [\d.]+%$')),
      reason:
          'Preparation amount and percentage should read as one left-aligned '
          'group.',
    );
    expect(
      valueToStateGap,
      closeTo(AppSpacing.xxs, 0.5),
      reason: 'The state should remain a separate right-aligned group.',
    );
    for (final label in ['Confirming 2/3', 'Waiting to be mined']) {
      final text = tester.widget<Text>(find.text(label));
      expect(
        text.overflow,
        isNot(TextOverflow.ellipsis),
        reason: '$label should remain fully visible.',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'does not start a wallet sync when the migration page is opened',
    (tester) async {
      _useMobileViewport(tester);
      final coordinator = _EntrySyncErrorTestMigrationCoordinator();
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationService: _migrationService(),
          migrationCoordinator: () => coordinator,
          status: _status(
            phase: kIronwoodMigrationReadyToMigratePhase,
            nextActionHeight: 3_000_000,
            parts: [
              rust_sync.MigrationPartStatus(
                partIndex: 0,
                valueZatoshi: BigInt.from(412_000_000),
                state: rust_sync.MigrationPartState.needsInput,
                confirmationCount: 0,
                confirmationTarget: 3,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(coordinator.synchronizeCount, 0);
      expect(coordinator.refreshCount, 1);
      expect(find.text("Couldn't update migration"), findsNothing);
      expect(find.text('Ironwood Migration'), findsOneWidget);
    },
  );

  testWidgets(
    'fails notification UI closed when authorization refresh fails on resume',
    (tester) async {
      _useMobileViewport(tester);
      SharedPreferences.setMockInitialValues({
        'zcash_ironwood_migration_preparation_complete_seen_run-1': true,
      });
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      final coordinator = _SuccessfulEntrySyncTestMigrationCoordinator();
      var authorizationLookupFails = false;
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationService: _migrationService(
            ios: true,
            getNotificationAuthorizationStatus: () async {
              if (authorizationLookupFails) {
                throw StateError('Notification lookup failed.');
              }
              return IronwoodMigrationNotificationAuthorizationStatus
                  .authorized;
            },
          ),
          migrationCoordinator: () => coordinator,
          status: _status(
            phase: kIronwoodMigrationBroadcastScheduledPhase,
            nextActionHeight: 3_000_100,
          ),
          syncState: SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            scannedHeight: 3_000_000,
            chainTipHeight: 3_000_000,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('We’ll let you know when it’s time to take action'),
        findsOneWidget,
      );
      authorizationLookupFails = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(coordinator.synchronizeCount, 0);
      expect(find.text("Couldn't update migration"), findsNothing);
      expect(find.textContaining('Notifications are disabled'), findsWidgets);
      expect(
        find.textContaining('We’ll let you know when it’s time to take action'),
        findsNothing,
      );
    },
  );

  testWidgets('requires confirmation before rebuilding a missing credential', (
    tester,
  ) async {
    _useMobileViewport(tester, size: const Size(320, 568));
    final coordinator = _RecoveryScreenTestMigrationCoordinator();
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        migrationCoordinator: () => coordinator,
        status: _status(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          activeRunId: 'old-run',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recover'), findsOneWidget);
    expect(coordinator.recoveryCount, 0);

    await tester.tap(find.text('Recover'));
    await tester.pumpAndSettle();
    expect(find.text('Rebuild migration?'), findsOneWidget);
    expect(find.text('Rebuild'), findsOneWidget);
    expect(coordinator.recoveryCount, 0);

    await tester.ensureVisible(find.text('Rebuild'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rebuild'));
    await tester.pumpAndSettle();
    expect(coordinator.recoveryCount, 1);
  });

  testWidgets(
    'does not offer software credential recovery for a Keystone account',
    (tester) async {
      _useMobileViewport(tester, size: const Size(320, 568));
      final coordinator = _RecoveryScreenTestMigrationCoordinator();
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/status',
          migrationService: _migrationService(),
          migrationCoordinator: () => coordinator,
          status: _status(
            phase: kIronwoodMigrationBroadcastScheduledPhase,
            activeRunId: 'old-run',
          ),
          hardware: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recover'), findsNothing);
      expect(find.text('Keystone account required'), findsOneWidget);
      expect(
        find.textContaining('Reconnect or re-import your Keystone account'),
        findsOneWidget,
      );
      expect(find.text('Back to home'), findsOneWidget);
      expect(coordinator.recoveryCount, 0);
    },
  );

  testWidgets('shows the next migration step while broadcasting', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(phase: kIronwoodMigrationBroadcastingPhase),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Next migration'), findsOneWidget);
    expect(find.textContaining('Next migration step expected'), findsOneWidget);
    expect(find.textContaining('Notifications are on'), findsOneWidget);
  });

  testWidgets('keeps coordinator errors on the redesigned retry surface', (
    tester,
  ) async {
    _useMobileViewport(tester, size: const Size(320, 568));
    final coordinator = _ErrorScreenTestMigrationCoordinator();
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        migrationCoordinator: () => coordinator,
        status: _status(phase: kIronwoodMigrationBroadcastScheduledPhase),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ironwood Migration'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_migration_status_migrating')),
      findsNothing,
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(coordinator.retryCount, 1);
  });

  testWidgets('keeps preparation errors on the paused preparation surface', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final coordinator = _ErrorScreenTestMigrationCoordinator();
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        migrationCoordinator: () => coordinator,
        status: _status(
          phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preparing your migration'), findsOneWidget);
    expect(
      find.text('Preparation was paused because you left.'),
      findsOneWidget,
    );
    expect(find.text('Continue preparation'), findsOneWidget);
    expect(find.text('Ironwood Migration'), findsNothing);
    expect(find.text('Retry'), findsNothing);

    await tester.tap(find.text('Continue preparation'));
    await tester.pumpAndSettle();
    expect(coordinator.retryCount, 1);
  });

  testWidgets('uses per-part state and confirmation progress from Rust', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final status = _status(
      phase: kIronwoodMigrationWaitingConfirmationsPhase,
      parts: [
        rust_sync.MigrationPartStatus(
          partIndex: 0,
          valueZatoshi: BigInt.from(412_000_000),
          state: rust_sync.MigrationPartState.completed,
          confirmationCount: 3,
          confirmationTarget: 3,
        ),
        rust_sync.MigrationPartStatus(
          partIndex: 1,
          valueZatoshi: BigInt.from(412_000_000),
          state: rust_sync.MigrationPartState.confirming,
          confirmationCount: 2,
          confirmationTarget: 3,
        ),
        rust_sync.MigrationPartStatus(
          partIndex: 2,
          valueZatoshi: BigInt.from(412_000_000),
          state: rust_sync.MigrationPartState.scheduled,
          scheduleStartHeight: 3_499_900,
          scheduledHeight: 3_500_100,
          confirmationCount: 0,
          confirmationTarget: 3,
        ),
      ],
    );
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: status,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncComplete: true,
          ironwoodBalance: BigInt.from(100_000_000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('4.12 ZEC'), findsOneWidget);
    expect(find.text('Left to migrate'), findsOneWidget);
    expect(find.text('8.24 ZEC'), findsOneWidget);
    expect(find.text('Est. completion'), findsOneWidget);
  });

  testWidgets('does not render synthetic migration values before run data', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final status = _status(
      phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
      targetValues: const [],
      parts: const [],
    );
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: status,
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('Migration 1 notes'), findsNothing);
    expect(find.text('Schedule pending'), findsNothing);
  });

  testWidgets('summarizes confirmed progress without rendering part rows', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationWaitingConfirmationsPhase,
          broadcastStatuses: const ['scheduled', 'confirmed', 'broadcasted'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Next migration'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_part_row_0')),
      findsNothing,
    );
  });

  testWidgets('shows only the next queued migration timing', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          nextActionHeight: 3_000_020,
          estimatedCompletionHeight: 3_000_040,
          nextActionPartIndex: 1,
        ),
        privatePlan: _planWith(plannedBatchCount: 3),
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 3_000_000,
          chainTipHeight: 3_000_000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('~25 minutes'), findsOneWidget);
    expect(find.textContaining('~18:'), findsNothing);
    expect(find.text('4.12 ZEC'), findsOneWidget);
    expect(find.text('3,000,020'), findsOneWidget);
  });

  testWidgets('shows a due scheduled transaction as ready, never Soon', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          broadcastStatuses: const ['scheduled'],
          nextActionHeight: 3_000_000,
          nextActionPartIndex: 0,
        ),
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 3_000_000,
          chainTipHeight: 3_000_000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sending migration'), findsOneWidget);
    expect(find.text('Sending now'), findsOneWidget);
    expect(find.text('Ready now'), findsOneWidget);
    expect(
      find.textContaining('ready for automatic submission'),
      findsOneWidget,
    );
    expect(find.text('soon'), findsNothing);
    expect(find.text('Soon'), findsNothing);
    expect(find.text('Waiting for signing window'), findsNothing);
  });

  testWidgets('shows safe-block timing without a proof label', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationReadyToMigratePhase,
          nextActionHeight: 3_000_020,
          nextActionPartIndex: 1,
          pendingTxCount: 0,
          signedChildPcztCount: 3,
        ),
        hardware: true,
        privatePlan: _planWith(plannedBatchCount: 3),
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 3_000_000,
          chainTipHeight: 3_000_000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('~25 minutes'), findsOneWidget);
    expect(find.textContaining('Proof'), findsNothing);
    expect(find.text('Sign batch #2'), findsNothing);
    expect(find.text('Next migration'), findsOneWidget);
    expect(find.text('3,000,020'), findsOneWidget);
  });

  testWidgets('waits when a signed proof height is still being projected', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'zcash_ironwood_migration_preparation_complete_seen_run-1': true,
    });
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationReadyToMigratePhase,
          pendingTxCount: 0,
          signedChildPcztCount: 3,
        ),
        hardware: true,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 3_000_000,
          chainTipHeight: 3_000_000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Prepare batch #1'), findsNothing);
    expect(find.text('Schedule pending'), findsOneWidget);
  });

  testWidgets('shows the real next block when notifications are disabled', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          nextActionHeight: 3_000_020,
          nextActionPartIndex: 1,
        ),
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 3_000_000,
          chainTipHeight: 3_000_000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Notifications are disabled. Open Vizor after block 3000020',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('around Timing'), findsNothing);
  });

  testWidgets('shows one projected timing for prepared migration parts', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final parts = [
      for (var index = 0; index < 3; index++)
        rust_sync.MigrationPartStatus(
          partIndex: index,
          valueZatoshi: BigInt.from(412_000_000),
          state: rust_sync.MigrationPartState.preparing,
          scheduleStartHeight: 3_000_000,
          scheduledHeight: 3_000_020 + index * 20,
          confirmationCount: 0,
          confirmationTarget: 3,
        ),
    ];
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          parts: parts,
          nextActionHeight: 3_000_020,
          nextActionPartIndex: 0,
        ),
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 3_000_000,
          chainTipHeight: 3_000_000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('~25 minutes'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_part_row_0')),
      findsNothing,
    );
  });

  testWidgets('keeps analyzed values in the aggregate migration total', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final parts = [
      rust_sync.MigrationPartStatus(
        partIndex: 0,
        scheduleOrder: 2,
        valueZatoshi: BigInt.from(100_000_000),
        state: rust_sync.MigrationPartState.scheduled,
        scheduledHeight: 3_000_020,
        confirmationCount: 0,
        confirmationTarget: 3,
      ),
      rust_sync.MigrationPartStatus(
        partIndex: 1,
        scheduleOrder: 0,
        valueZatoshi: BigInt.from(200_000_000),
        state: rust_sync.MigrationPartState.scheduled,
        scheduledHeight: 3_000_020,
        confirmationCount: 0,
        confirmationTarget: 3,
      ),
      rust_sync.MigrationPartStatus(
        partIndex: 2,
        scheduleOrder: 1,
        valueZatoshi: BigInt.from(300_000_000),
        state: rust_sync.MigrationPartState.scheduled,
        scheduledHeight: 3_000_040,
        confirmationCount: 0,
        confirmationTarget: 3,
      ),
    ];
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationBroadcastScheduledPhase,
          parts: parts,
          nextActionHeight: 3_000_020,
          nextActionPartIndex: 1,
        ),
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          scannedHeight: 3_000_000,
          chainTipHeight: 3_000_000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 ZEC'), findsOneWidget);
    expect(find.text('6.00 ZEC'), findsOneWidget);
  });

  testWidgets('keeps an all-confirmed waiting run in progress', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(
          phase: kIronwoodMigrationWaitingConfirmationsPhase,
          broadcastStatuses: const ['confirmed', 'confirmed', 'confirmed'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ironwood Migration'), findsOneWidget);
    expect(find.text('Migration complete'), findsNothing);
    expect(find.text('Finalizing migration'), findsOneWidget);
  });
}

class _RecordingCompletionStore implements IronwoodMigrationCompletionStore {
  _RecordingCompletionStore(this.seen);

  final List<String> seen;

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
  }) async {
    seen.add('$network:$accountUuid:$completionId');
  }
}
