@Tags(['mobile'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:zcash_wallet/src/core/widgets/app_profile_picture.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/migration/models/mobile_ironwood_migration_attention_state.dart';
import 'package:zcash_wallet/src/features/migration/screens/ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/features/migration/screens/mobile/mobile_ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/rust/wallet/keystone.dart'
    as rust_keystone_wallet;

import '../../fakes/fake_sync_notifier.dart';

class _RustApiFake implements RustLibApi {
  @override
  void crateApiKeystoneResetUrSession() {}

  @override
  Future<List<String>> crateApiKeystoneEncodeZcashSignBatchUrParts({
    required String requestId,
    required List<rust_keystone_wallet.ZcashBatchMessageInput> messages,
    required BigInt maxFragmentLen,
  }) async => ['UR:ZCASH-SIGN-BATCH/$requestId'];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HardwareAccountNotifier extends AccountNotifier {
  @override
  Future<AccountState> build() async =>
      _bootstrap(hardware: true).initialAccountState;
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
  Future<void> retry(String accountUuid) async {
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
  Future<void> retry(String accountUuid) async {
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

class _DurablePhaseRetryTestMigrationCoordinator
    extends IronwoodMigrationCoordinator {
  int retryCount = 0;

  @override
  IronwoodMigrationCoordinatorState build() {
    return const IronwoodMigrationCoordinatorState();
  }

  @override
  Future<void> retry(String accountUuid) async {
    retryCount++;
  }
}

class _RecordingIronwoodMigrationCompletionStore
    implements IronwoodMigrationCompletionStore {
  int markCount = 0;
  String? markedNetwork;
  String? markedAccountUuid;
  String? markedCompletionId;

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
    markCount++;
    markedNetwork = network;
    markedAccountUuid = accountUuid;
    markedCompletionId = completionId;
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
  int signingBatchLimit = 12,
  int blockOffsetAdjustment = 0,
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
  signingBatchLimit: signingBatchLimit,
  scheduleMeanDelayBlocks: 144,
  scheduleMaxDelayBlocks: 576,
  proofReadinessDelayBlocks: 146,
  maxPreparedNotesPerRun: 12,
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
  int? estimatedCompletionHeight,
  int? nextActionPartIndex,
  int pendingTxCount = 2,
  int signedChildPcztCount = 0,
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
    broadcastedTxCount: 1,
    confirmedTxCount: 1,
    totalCount: 3,
    signedChildPcztCount: signedChildPcztCount,
    pendingSplitStageCount: 2,
    canAbandon: false,
    signingBatchLimit: 12,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    maxPreparedNotesPerRun: 12,
    nextActionHeight: nextActionHeight,
    estimatedCompletionHeight: estimatedCompletionHeight,
    nextActionPartIndex: nextActionPartIndex,
    message: message,
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
    maxPreparedNotesPerRun: 12,
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
  initialLocation: '/migration/private/review',
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
  MobileIronwoodMigrationReviewPreviewStage previewReviewStage =
      MobileIronwoodMigrationReviewPreviewStage.review,
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
      previewReviewStage: previewReviewStage,
      previewSurface: previewSurface,
    );
  }

  router = GoRouter(
    initialLocation: switch (step) {
      MobileIronwoodMigrationStep.intro => '/migration/intro',
      MobileIronwoodMigrationStep.howItWorks => '/migration/how-it-works',
      MobileIronwoodMigrationStep.options => '/migration/options',
      MobileIronwoodMigrationStep.notifications =>
        '/migration/private/notifications',
      MobileIronwoodMigrationStep.privateReview => '/migration/private/review',
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
        path: '/migration/private/review',
        builder: (_, _) => screen(MobileIronwoodMigrationStep.privateReview),
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
  bool hardware = false,
  rust_sync.OrchardMigrationPrivatePlan? privatePlan,
  Future<rust_sync.OrchardMigrationPrivatePlan?>? privatePlanFuture,
  Future<rust_sync.OrchardMigrationPrivatePlan?> Function()? privatePlanLoader,
  SyncState? syncState,
  FakeSyncNotifier? syncNotifier,
  IronwoodMigrationCoordinator Function()? migrationCoordinator,
  IronwoodMigrationCompletionStore? completionStore,
  bool disableAnimations = true,
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
        path: '/migration/private/review',
        builder: (_, _) => const MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.privateReview,
        ),
      ),
      GoRoute(
        path: '/migration/private/notifications',
        builder: (_, _) => const MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.notifications,
        ),
      ),
      GoRoute(
        path: '/migration/fast/review',
        builder: (_, _) => const MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.fastReview,
        ),
      ),
      GoRoute(
        path: '/migration/private/status',
        builder: (_, _) => MobileIronwoodMigrationPrivateStatusScreen(
          approvedPlan: privatePlan,
        ),
      ),
      GoRoute(
        path: '/migration/private/keystone/denominations/sign',
        builder: (_, _) => const Text('keystone denomination sign route'),
      ),
      GoRoute(
        path: '/migration/private/keystone/batch/sign',
        builder: (_, _) => const Text('keystone batch sign route'),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
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
      ironwoodMigrationRouteCtaProvider.overrideWith(
        (ref) async => ctaBuilder?.call() ?? cta,
      ),
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
      if (completionStore != null)
        ironwoodMigrationCompletionStoreProvider.overrideWithValue(
          completionStore,
        ),
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

IronwoodMigrationService _migrationService({
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
}) {
  return IronwoodMigrationService(
    getWalletDbPath: () async => '/tmp/wallet.db',
    getStatus:
        ({required dbPath, required network, required accountUuid}) async =>
            _status(phase: kIronwoodMigrationWaitingDenomConfirmationsPhase),
    getPrivatePlan:
        ({required dbPath, required network, required accountUuid}) async =>
            _plan,
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
  setUpAll(() {
    RustLib.initMock(api: _RustApiFake());
  });

  tearDownAll(RustLib.dispose);

  setUp(() {
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

  testWidgets('does not offer Immediate migration to Keystone accounts', (
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
    expect(tester.widget<GestureDetector>(immediateGesture).onTap, isNull);
    await tester.tap(immediateOption);
    await tester.pump();
    expect(
      find.descendant(
        of: immediateOption,
        matching: find.byKey(const ValueKey('mobile_ironwood_selected_radio')),
      ),
      findsNothing,
    );
  });

  testWidgets('renders the private migration review plan', (tester) async {
    await tester.pumpWidget(
      _app(step: MobileIronwoodMigrationStep.privateReview),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review Migration Plan'), findsOneWidget);
    expect(find.text('Migration 12 notes'), findsOneWidget);
    expect(find.text('142.20 ZEC'), findsOneWidget);
    expect(find.text('Est. completion'), findsOneWidget);
    final completionText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(
          const ValueKey('mobile_ironwood_review_value_Est. completion'),
        ),
        matching: find.byType(Text),
      ),
    );
    expect(completionText.data, contains(':'));
    expect(completionText.data, isNot('~37 hrs'));
    expect(completionText.data, isNot(contains('blocks')));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_ironwood_part_status_cell_0')),
        matching: find.text('~4 hrs'),
      ),
      findsOneWidget,
    );
    expect(find.text('Fees (estimate)'), findsOneWidget);
    expect(find.text('0.1442 ZEC'), findsOneWidget);
    expect(find.text('Start migration'), findsOneWidget);
  });

  testWidgets('scrolls migration parts only when the review overflows', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.privateReview,
        previewPlan: _planWith(plannedBatchCount: 6),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getCenter(find.text('Review Migration Plan')).dx,
      closeTo(393 / 2, 0.5),
    );
    final labelCell = tester.getRect(
      find.byKey(const ValueKey('mobile_ironwood_part_label_cell_0')),
    );
    final valueCell = tester.getRect(
      find.byKey(const ValueKey('mobile_ironwood_part_value_cell_0')),
    );
    final statusCell = tester.getRect(
      find.byKey(const ValueKey('mobile_ironwood_part_status_cell_0')),
    );
    expect(labelCell.left, 16);
    expect(labelCell.width, 70);
    expect(labelCell.height, 24);
    expect(valueCell.left, closeTo(101.5, 0.5));
    expect(valueCell.width, 130);
    expect(statusCell.right, 377);
    expect(statusCell.width, 130);
    expect(
      tester
          .getRect(find.byKey(const ValueKey('mobile_ironwood_part_bar_5')))
          .right,
      closeTo(377, 0.5),
    );
    expect(
      tester
          .getRect(
            find.byKey(
              const ValueKey('mobile_ironwood_review_value_Est. completion'),
            ),
          )
          .right,
      373,
    );

    var partListPosition = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const ValueKey('mobile_ironwood_part_list')),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    expect(partListPosition.maxScrollExtent, 0);
    var railPosition = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const ValueKey('mobile_ironwood_part_bar_scroll')),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    expect(railPosition.maxScrollExtent, 0);

    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.privateReview,
        previewPlan: _planWith(plannedBatchCount: 50, signingBatchLimit: 50),
      ),
    );
    await tester.pumpAndSettle();

    partListPosition = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const ValueKey('mobile_ironwood_part_list')),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    expect(partListPosition.maxScrollExtent, greaterThan(0));
    await tester.drag(
      find.byKey(const ValueKey('mobile_ironwood_part_list')),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(partListPosition.pixels, greaterThan(0));
    railPosition = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const ValueKey('mobile_ironwood_part_bar_scroll')),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    expect(railPosition.maxScrollExtent, greaterThan(0));
    await tester.drag(
      find.byKey(const ValueKey('mobile_ironwood_part_bar_scroll')),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();
    expect(railPosition.pixels, greaterThan(0));
  });

  testWidgets('splits the analysis bar before staggering the part rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.privateReview,
        disableAnimations: false,
      ),
    );
    await tester.pump();

    final firstBar = find.byKey(const ValueKey('mobile_ironwood_part_bar_0'));
    final lastBar = find.byKey(const ValueKey('mobile_ironwood_part_bar_11'));
    final firstRow = find.byKey(
      const ValueKey('mobile_ironwood_part_row_reveal_0'),
    );
    final lastVisibleRow = find.byKey(
      const ValueKey('mobile_ironwood_part_row_reveal_1'),
    );
    final singleTrack = find.byKey(
      const ValueKey('mobile_ironwood_part_bar_single_track'),
    );

    final initialBarSpan =
        tester.getRect(lastBar).right - tester.getRect(firstBar).left;
    expect(initialBarSpan, closeTo(196, 0.5));
    expect(tester.widget<Opacity>(singleTrack).opacity, 1);
    expect(tester.widget<FadeTransition>(firstRow).opacity.value, 0);

    await tester.pump(const Duration(milliseconds: 1200));

    final splitBarSpan =
        tester.getRect(lastBar).right - tester.getRect(firstBar).left;
    expect(splitBarSpan, greaterThan(initialBarSpan));
    expect(tester.widget<Opacity>(singleTrack).opacity, 0);
    expect(tester.widget<FadeTransition>(firstRow).opacity.value, 0);

    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.widget<FadeTransition>(firstRow).opacity.value,
      greaterThan(tester.widget<FadeTransition>(lastVisibleRow).opacity.value),
    );

    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.widget<FadeTransition>(lastVisibleRow).opacity.value, 1);
  });

  testWidgets('holds the analyzing preview at the Figma progress value', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.privateReview,
        previewReviewStage: MobileIronwoodMigrationReviewPreviewStage.analyzing,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mobile_ironwood_migration_analyzing')),
      findsOneWidget,
    );
    final progress = tester.widget<FractionallySizedBox>(
      find.descendant(
        of: find.byKey(
          const ValueKey('mobile_ironwood_migration_analysis_progress'),
        ),
        matching: find.byType(FractionallySizedBox),
      ),
    );
    expect(progress.widthFactor, closeTo(72 / 196, 0.001));
    expect(
      tester.getSize(
        find.byKey(
          const ValueKey('mobile_ironwood_migration_analysis_progress_fill'),
        ),
      ),
      const Size(72, 12),
    );
    expect(find.text('Analyzing your balance...'), findsOneWidget);
  });

  testWidgets('advances the animated analyzing preview over time', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.privateReview,
        previewReviewStage:
            MobileIronwoodMigrationReviewPreviewStage.animatedAnalyzing,
        disableAnimations: false,
      ),
    );
    await tester.pump();

    final progressFinder = find.descendant(
      of: find.byKey(
        const ValueKey('mobile_ironwood_migration_analysis_progress'),
      ),
      matching: find.byType(FractionallySizedBox),
    );
    final initialProgress = tester
        .widget<FractionallySizedBox>(progressFinder)
        .widthFactor!;

    await tester.pump(const Duration(milliseconds: 500));

    final advancedProgress = tester
        .widget<FractionallySizedBox>(progressFinder)
        .widthFactor!;
    expect(advancedProgress, greaterThan(initialProgress));
    expect(advancedProgress, lessThan(0.97));
  });

  testWidgets('waits for the plan before completing analysis', (tester) async {
    _useMobileViewport(tester);
    final planCompleter = Completer<rust_sync.OrchardMigrationPrivatePlan?>();
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(),
        privatePlanFuture: planCompleter.future,
        disableAnimations: false,
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 2746));
    var progress = tester.widget<FractionallySizedBox>(
      find.descendant(
        of: find.byKey(
          const ValueKey('mobile_ironwood_migration_analysis_progress'),
        ),
        matching: find.byType(FractionallySizedBox),
      ),
    );
    expect(progress.widthFactor, closeTo(0.97, 0.001));
    expect(find.text('Review Migration Plan'), findsNothing);

    planCompleter.complete(_plan);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 256));

    progress = tester.widget<FractionallySizedBox>(
      find.descendant(
        of: find.byKey(
          const ValueKey('mobile_ironwood_migration_analysis_progress'),
        ),
        matching: find.byType(FractionallySizedBox),
      ),
    );
    expect(progress.widthFactor, closeTo(1, 0.001));
    expect(find.text('Your migration plan is ready'), findsOneWidget);
    expect(find.text('Review Migration Plan'), findsNothing);

    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));

    expect(find.text('Review Migration Plan'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_migration_analyzing')),
      findsNothing,
    );
  });

  testWidgets('keeps the review visible while its plan refreshes', (
    tester,
  ) async {
    final refreshCompleter =
        Completer<rust_sync.OrchardMigrationPrivatePlan?>();
    var loadCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(),
        privatePlanLoader: () {
          loadCount++;
          return loadCount == 1 ? Future.value(_plan) : refreshCompleter.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.text('Review Migration Plan')),
    );
    container.invalidate(ironwoodMigrationPrivatePlanProvider);
    await tester.pump();

    expect(find.text('Review Migration Plan'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_migration_analyzing')),
      findsNothing,
    );

    refreshCompleter.complete(_plan);
    await tester.pumpAndSettle();
  });

  testWidgets('does not announce a ready plan when analysis fails', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(),
        privatePlanFuture: Future.value(),
        disableAnimations: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2746));
    await tester.pump(const Duration(milliseconds: 256));

    expect(find.text('Your migration plan is ready'), findsNothing);
    expect(find.text("Couldn't prepare your migration plan"), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));
    expect(
      find.textContaining('Vizor needs an up-to-date balance'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('keeps review visible when foreground sync finishes', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var planLoadCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(),
        privatePlanLoader: () async {
          planLoadCount++;
          return planLoadCount == 1 ? null : _plan;
        },
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncing: true,
          isSyncComplete: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('Review Migration Plan'), findsOneWidget);
    expect(find.text('Syncing...'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.text('Review Migration Plan')),
    );
    final syncNotifier =
        container.read(syncProvider.notifier) as FakeSyncNotifier;
    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncComplete: true,
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(planLoadCount, 2);
    expect(find.text('Review Migration Plan'), findsOneWidget);
    expect(
      find.textContaining('Vizor needs an up-to-date balance'),
      findsNothing,
    );
  });

  testWidgets('does not reactivate a stale plan while sync refreshes it', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final refreshedPlan = Completer<rust_sync.OrchardMigrationPrivatePlan?>();
    var planLoadCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(),
        privatePlanLoader: () {
          planLoadCount++;
          return planLoadCount == 1
              ? Future.value(_plan)
              : refreshedPlan.future;
        },
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncComplete: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start migration').hitTestable(), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.text('Review Migration Plan')),
    );
    final syncNotifier =
        container.read(syncProvider.notifier) as FakeSyncNotifier;
    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncing: true,
        isSyncComplete: false,
      ),
    );
    await tester.pump();
    expect(find.text('Review Migration Plan'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_migration_analyzing')),
      findsNothing,
    );
    expect(find.text('Syncing...'), findsOneWidget);
    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncComplete: true,
      ),
    );
    await tester.pump();

    expect(planLoadCount, greaterThanOrEqualTo(2));
    expect(
      find.byKey(const ValueKey('mobile_ironwood_migration_analyzing')),
      findsNothing,
    );
    expect(find.text('Review Migration Plan'), findsOneWidget);
    expect(find.text('Updating plan...'), findsOneWidget);
    expect(find.text('Start migration').hitTestable(), findsNothing);

    refreshedPlan.complete(_planWith(blockOffsetAdjustment: 75));
    await tester.pumpAndSettle();

    expect(find.text('Review Migration Plan'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_ironwood_part_status_cell_0')),
        matching: find.text('~4 hrs'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Migration plan updated'), findsNothing);
    expect(find.text('Start migration').hitTestable(), findsOneWidget);
  });

  testWidgets('routes private migration by actual notification authorization', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var authorization = IronwoodMigrationNotificationAuthorizationStatus.denied;
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
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Review Migration Plan'), findsOneWidget);
  });

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
    expect(find.text('Review Migration Plan'), findsOneWidget);
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
    expect(find.text('Review Migration Plan'), findsOneWidget);
  });

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

  testWidgets('does not reactivate a stale plan after refresh fails', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var planLoadCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(),
        privatePlanLoader: () {
          planLoadCount++;
          return planLoadCount == 1
              ? Future.value(_plan)
              : Future.error(StateError('plan refresh failed'));
        },
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncComplete: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start migration').hitTestable(), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.text('Review Migration Plan')),
    );
    final syncNotifier =
        container.read(syncProvider.notifier) as FakeSyncNotifier;
    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncing: true,
        isSyncComplete: false,
      ),
    );
    await tester.pump();
    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncComplete: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2746));
    await tester.pump(const Duration(milliseconds: 256));
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));

    expect(planLoadCount, greaterThanOrEqualTo(2));
    expect(
      find.byKey(const ValueKey('mobile_ironwood_migration_analyzing')),
      findsNothing,
    );
    final startButton = tester.widget<AppButton>(
      find.descendant(
        of: find.byKey(
          const ValueKey('mobile_ironwood_authorize_start_button'),
        ),
        matching: find.byType(AppButton),
      ),
    );
    expect(startButton.onPressed, isNotNull);
    expect(
      find.textContaining("Couldn't update the migration plan after sync"),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('does not reactivate a stale plan after sync fails', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var planLoadCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(),
        privatePlanLoader: () async {
          planLoadCount++;
          return _plan;
        },
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncComplete: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start migration').hitTestable(), findsOneWidget);
    final initialPlanLoadCount = planLoadCount;

    final container = ProviderScope.containerOf(
      tester.element(find.text('Review Migration Plan')),
    );
    final syncNotifier =
        container.read(syncProvider.notifier) as FakeSyncNotifier;
    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncing: true,
        isSyncComplete: false,
      ),
    );
    await tester.pump();
    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncComplete: false,
        error: 'sync failed',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2746));
    await tester.pump(const Duration(milliseconds: 256));
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));

    expect(planLoadCount, initialPlanLoadCount);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_migration_analyzing')),
      findsNothing,
    );
    final startButton = tester.widget<AppButton>(
      find.descendant(
        of: find.byKey(
          const ValueKey('mobile_ironwood_authorize_start_button'),
        ),
        matching: find.byType(AppButton),
      ),
    );
    expect(startButton.onPressed, isNotNull);
    expect(find.textContaining("Sync didn't finish"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('keeps review visible when sync updates the plan', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final refreshedPlan = Completer<rust_sync.OrchardMigrationPrivatePlan?>();
    var planLoadCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(),
        privatePlanLoader: () {
          planLoadCount++;
          return planLoadCount == 1
              ? Future.value(_plan)
              : refreshedPlan.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.text('Review Migration Plan')),
    );
    final syncNotifier =
        container.read(syncProvider.notifier) as FakeSyncNotifier;
    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncing: true,
        isSyncComplete: false,
      ),
    );
    await tester.pump();
    syncNotifier.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncComplete: true,
      ),
    );
    await tester.pump();

    refreshedPlan.complete(_planWith(plannedBatchCount: 6));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile_ironwood_migration_analyzing')),
      findsNothing,
    );
    expect(find.text('Migration 6 notes'), findsOneWidget);
    expect(
      find.textContaining('Migration plan updated after sync'),
      findsOneWidget,
    );
    expect(find.text('Start migration').hitTestable(), findsOneWidget);
  });

  testWidgets('keeps the migration review usable at 320 by 568', (
    tester,
  ) async {
    _useMobileViewport(tester, size: const Size(320, 568));
    await tester.pumpWidget(
      _app(step: MobileIronwoodMigrationStep.privateReview),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review Migration Plan'), findsOneWidget);
    expect(find.text('Start migration').hitTestable(), findsOneWidget);
  });

  testWidgets('keeps review summary clear at the Widgetbook viewport', (
    tester,
  ) async {
    _useMobileViewport(tester, size: const Size(393, 720));
    await tester.pumpWidget(
      _app(step: MobileIronwoodMigrationStep.privateReview),
    );
    await tester.pumpAndSettle();

    final feeRow = tester.getRect(find.text('Fees (estimate)'));
    final startButton = tester.getRect(find.text('Start migration'));
    expect(
      startButton.top - feeRow.bottom,
      greaterThanOrEqualTo(AppSpacing.sm),
    );
    expect(find.text('Start migration').hitTestable(), findsOneWidget);
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

  testWidgets('starts a software migration and opens the status route', (
    tester,
  ) async {
    _useMobileViewport(tester);
    String? startedAccountUuid;
    List<rust_sync.MigrationScheduledTransfer>? startedSchedule;
    var started = false;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(
          onStart: (accountUuid, approvedSchedule) async {
            startedAccountUuid = accountUuid;
            startedSchedule = approvedSchedule;
            started = true;
            return _migrationResult();
          },
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

    final startButton = find.text('Start migration');
    expect(startButton, findsOneWidget);
    await tester.tap(startButton);
    await tester.pumpAndSettle();

    expect(startedAccountUuid, 'account-1');
    expect(startedSchedule, _plan.scheduledTransfers);
    expect(find.text('Preparing your migration'), findsOneWidget);
  });

  testWidgets('routes a Keystone account to split signing from review', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var softwareStartCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(
          onStart: (_, _) async {
            softwareStartCount += 1;
            return _migrationResult();
          },
        ),
        hardware: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue with Keystone'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_authorize_start_button')),
    );
    await tester.pumpAndSettle();

    expect(softwareStartCount, 0);
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
      signingBatchLimit: 50,
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
    expect(
      find.byKey(const ValueKey('mobile_ironwood_keystone_qr')),
      findsOneWidget,
    );
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
    expect(find.textContaining('Scan the QR code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blocks an oversized Keystone signing plan before QR', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(),
        hardware: true,
        privatePlan: _planWith(
          denominationSplitStageCount: 13,
          signingBatchLimit: 12,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This migration needs more transactions than one Keystone signing '
        'request supports.',
      ),
      findsOneWidget,
    );
    final button = tester.widget<AppButton>(
      find.descendant(
        of: find.byKey(
          const ValueKey('mobile_ironwood_authorize_start_button'),
        ),
        matching: find.byType(AppButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('accepts exactly 50 transactions in each Keystone round', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(),
        hardware: true,
        privatePlan: _planWith(
          denominationSplitStageCount: 50,
          plannedBatchCount: 50,
          signingBatchLimit: 50,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<AppButton>(
      find.descendant(
        of: find.byKey(
          const ValueKey('mobile_ironwood_authorize_start_button'),
        ),
        matching: find.byType(AppButton),
      ),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('blocks 51 transactions in either Keystone round', (
    tester,
  ) async {
    _useMobileViewport(tester);
    for (final plan in [
      _planWith(
        denominationSplitStageCount: 51,
        plannedBatchCount: 50,
        signingBatchLimit: 50,
      ),
      _planWith(
        denominationSplitStageCount: 50,
        plannedBatchCount: 51,
        signingBatchLimit: 50,
      ),
    ]) {
      await tester.pumpWidget(
        _productionApp(
          initialLocation: '/migration/private/review',
          migrationService: _migrationService(),
          hardware: true,
          privatePlan: plan,
        ),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<AppButton>(
        find.descendant(
          of: find.byKey(
            const ValueKey('mobile_ironwood_authorize_start_button'),
          ),
          matching: find.byType(AppButton),
        ),
      );
      expect(button.onPressed, isNull);
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
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1/2 Batch'), findsOneWidget);
    expect(find.text('Batch #2'), findsOneWidget);
    expect(find.text('2 ZEC (20%)'), findsOneWidget);
    expect(find.text('Sign batch #2'), findsOneWidget);
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
      for (var index = 0; index < 8; index++) index,
    });
    expect(painter.highlightedSegments, {8, 9});
    expect(painter.visibleSegmentGap, 4);
    expect(tester.getCenter(find.text('2 ZEC (20%)')).dx, greaterThan(250));
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

      expect(find.text('Waiting for your confirmation'), findsOneWidget);
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

  testWidgets('acknowledges the completion receipt before Done returns home', (
    tester,
  ) async {
    _useMobileViewport(tester);
    final completionStore = _RecordingIronwoodMigrationCompletionStore();
    final status = _status(
      phase: kIronwoodMigrationCompletePhase,
      targetValues: const [412_000_000],
    );
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: status,
        completionStore: completionStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You’re all set!'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('home route'), findsOneWidget);
    expect(completionStore.markCount, 1);
    expect(completionStore.markedNetwork, 'main');
    expect(completionStore.markedAccountUuid, 'account-1');
    expect(
      completionStore.markedCompletionId,
      ironwoodMigrationCompletionId(status),
    );
  });

  testWidgets('retries a late Keystone broadcast without opening QR', (
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
    await tester.tap(action);
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

  testWidgets('keeps review visible when start has no durable run', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(
          onStart: (_, _) async => _migrationResult(),
        ),
        startedStatus: _status(
          phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
          activeRunId: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start migration'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't start migration. Try again."), findsOneWidget);
    expect(find.text('Preparing...'), findsNothing);
  });

  testWidgets('opens status when start reports an error after creating a run', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var started = false;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(
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

    await tester.tap(find.text('Start migration'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't start migration. Try again."), findsNothing);
    expect(find.text('Preparing your migration'), findsOneWidget);
  });

  testWidgets('opens status when post-start verification is unavailable', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var started = false;
    var statusReadCount = 0;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(
          onStart: (_, _) async {
            started = true;
            return _migrationResult();
          },
        ),
        statusLoader: () async {
          statusReadCount++;
          throw StateError('temporary status failure');
        },
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

    await tester.tap(find.text('Start migration'));
    await tester.pumpAndSettle();

    expect(statusReadCount, 1);
    expect(find.text("Couldn't start migration. Try again."), findsNothing);
    expect(find.text('Preparing your migration'), findsOneWidget);
  });

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
    expect(
      find.text('Preparation was paused because you left.'),
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
    'shows the preparation sync surface only when wallet sync stays active',
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
      expect(find.text('Preparing your migration'), findsOneWidget);
      expect(find.text('Syncing your wallet…'), findsNothing);
      expect(find.text('Preparation will\ntake 10–20 min'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 850));

      expect(find.text('Syncing your wallet…'), findsOneWidget);
      expect(find.text('Migration in progress…'), findsNothing);
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
      expect(find.text('Preparation will\ntake 10–20 min'), findsOneWidget);
    },
  );

  testWidgets(
    'maps denomination confirmation progress into the preparation ring',
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

      final ring = tester.widget<CustomPaint>(
        find.byKey(const ValueKey('mobile_ironwood_preparation_progress_ring')),
      );
      final painter = ring.painter as dynamic;
      expect(painter.progress as double, closeTo(5 / 9, 0.0001));
      expect(painter.visibleSegmentGap as double, 4);
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
    'delays the migration sync surface until the sync is perceptible',
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

      expect(find.text('Migration in progress…'), findsOneWidget);
      expect(find.text('Syncing the migration progress.'), findsNothing);

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

      expect(find.text('Preparation will\ntake 10–20 min'), findsOneWidget);
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
      expect(find.text('Preparation will\ntake 10–20 min'), findsOneWidget);
      expect(find.text('Continue preparation'), findsNothing);
    },
  );

  testWidgets('keeps the handoff token when automatic continuation fails', (
    tester,
  ) async {
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
    expect(acknowledgementCount, 0);
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

    expect(find.text('Migration in progress…'), findsOneWidget);
    expect(find.text('4.12'), findsOneWidget);
    expect(find.text('/12.36 ZEC'), findsOneWidget);
    expect(find.text('0/1 Batch'), findsOneWidget);
    expect(find.text('Available in Ironwood'), findsOneWidget);
    expect(find.text('Waiting for confirmations'), findsWidgets);
    expect(
      find.textContaining('Confirmations are still arriving'),
      findsOneWidget,
    );
    expect(find.textContaining('Signing window expected'), findsNothing);
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
      expect(find.text('Migration in progress…'), findsOneWidget);
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

      expect(find.textContaining('We will notify you'), findsOneWidget);
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
      expect(find.textContaining('We will notify you'), findsNothing);
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

  testWidgets('shows the next signing window while broadcasting', (
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

    expect(find.text('All is well. Broadcasting notes…'), findsWidgets);
    expect(find.textContaining('Signing window expected'), findsOneWidget);
    expect(
      find.textContaining('We will notify you when it’s ready.'),
      findsOneWidget,
    );
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

    expect(find.text('Migration in progress…'), findsOneWidget);
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
    expect(find.text('Migration in progress…'), findsNothing);
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

    expect(find.text('4.12'), findsOneWidget);
    expect(find.text('/12.36 ZEC'), findsOneWidget);
    expect(find.text('0/1 Batch'), findsOneWidget);
    expect(find.text('Available in Ironwood'), findsOneWidget);
    expect(find.text('1 ZEC'), findsOneWidget);
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

    expect(find.text('0/1 Batch'), findsOneWidget);
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
    expect(find.text('0/1 Batch'), findsOneWidget);
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
    expect(find.text('Waiting for signing window'), findsOneWidget);
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

    expect(find.text('0/6 ZEC'), findsOneWidget);
    expect(find.text('0/1 Batch'), findsOneWidget);
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

    expect(find.text('Migration in progress…'), findsOneWidget);
    expect(find.text('Migration complete'), findsNothing);
    expect(find.text('0/1 Batch'), findsOneWidget);
  });
}
