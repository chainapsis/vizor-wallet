@Tags(['mobile'])
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/screens/ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/features/migration/screens/mobile/mobile_ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_service.dart';
import 'package:zcash_wallet/src/features/migration/widgets/ironwood_migration_shimmer_text.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import '../../fakes/fake_sync_notifier.dart';

class _RustApiFake implements RustLibApi {
  @override
  void crateApiKeystoneResetUrSession() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _data = IronwoodMigrationFlowData(
  amountZatoshi: BigInt.from(14_224_000_000),
  accountName: 'Wallet 1',
  profilePictureId: 'default',
);

rust_sync.OrchardMigrationPrivatePlan _planWith({
  int plannedBatchCount = 12,
  int denominationSplitStageCount = 1,
  int signingBatchLimit = 12,
}) => rust_sync.OrchardMigrationPrivatePlan(
  targetValuesZatoshi: frb.Uint64List.fromList([]),
  totalInputZatoshi: BigInt.from(14_224_000_000),
  totalMigratableZatoshi: BigInt.from(14_223_900_000),
  orchardChangeZatoshi: BigInt.from(90_000),
  denominationSplitFeeZatoshi: BigInt.from(20_000),
  migrationFeeZatoshi: BigInt.from(14_400_000),
  estimatedTotalFeeZatoshi: BigInt.from(14_420_000),
  plannedBatchCount: plannedBatchCount,
  denominationSplitStageCount: denominationSplitStageCount,
  signingBatchLimit: signingBatchLimit,
  scheduleMeanDelayBlocks: 144,
  scheduleMaxDelayBlocks: 576,
  maxPreparedNotesPerRun: 12,
  scheduledTransfers: [
    for (var i = 0; i < plannedBatchCount; i++)
      rust_sync.MigrationScheduledTransfer(
        valueZatoshi: BigInt.from(100_000_000),
        blockOffset: (i + 1) * 144,
      ),
  ],
);

rust_sync.OrchardMigrationPrivatePlan get _plan => _planWith();

rust_sync.MigrationStatus _status({
  required String phase,
  String? activeRunId = 'run-1',
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    activeRunId: activeRunId,
    targetValuesZatoshi: frb.Uint64List.fromList([
      412_000_000,
      412_000_000,
      412_000_000,
    ]),
    preparedNoteCount: 3,
    denominationConfirmationCount: 2,
    denominationConfirmationTarget: 10,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 3,
    pendingTxCount: 2,
    broadcastedTxCount: 1,
    confirmedTxCount: 1,
    totalCount: 3,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 2,
    canAbandon: false,
    signingBatchLimit: 12,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    maxPreparedNotesPerRun: 12,
    scheduledBroadcasts: const [],
  );
}

rust_sync.MigrationStatus _visualMigrationStatus() {
  final scheduledAt = DateTime(2026, 7, 18, 12).millisecondsSinceEpoch;
  return rust_sync.MigrationStatus(
    phase: kIronwoodMigrationWaitingConfirmationsPhase,
    activeRunId: 'visual-run',
    targetValuesZatoshi: frb.Uint64List.fromList([
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
    ]),
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
      for (var i = 0; i < 12; i++)
        rust_sync.MigrationScheduledBroadcast(
          txidHex: 'visual-$i',
          valueZatoshi: BigInt.from(412_000_000),
          scheduledAtMs: scheduledAt,
          scheduledHeight: 3_000_000 + (i + 1) * 144,
          status: 'scheduled',
        ),
    ],
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
}) {
  late final GoRouter router;
  MobileIronwoodMigrationFlowScreen screen(MobileIronwoodMigrationStep value) {
    return MobileIronwoodMigrationFlowScreen(
      step: value,
      previewData: _data,
      previewPrivatePlan: _plan,
      previewStatus: previewStatus,
    );
  }

  router = GoRouter(
    initialLocation: switch (step) {
      MobileIronwoodMigrationStep.intro => '/migration/intro',
      MobileIronwoodMigrationStep.howItWorks => '/migration/how-it-works',
      MobileIronwoodMigrationStep.options => '/migration/options',
      MobileIronwoodMigrationStep.privateReview => '/migration/private/review',
      MobileIronwoodMigrationStep.fastReview => '/migration/fast/review',
      MobileIronwoodMigrationStep.preparing => '/migration/private/preparing',
      MobileIronwoodMigrationStep.migrating => '/migration/private/status',
      MobileIronwoodMigrationStep.passcodeWhileSyncing =>
        '/migration/private/unlock',
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
      GoRoute(
        path: '/migration/private/unlock',
        builder:
            (_, _) => screen(MobileIronwoodMigrationStep.passcodeWhileSyncing),
      ),
    ],
  );

  return ProviderScope(
    child: AppTheme(
      data: theme,
      child: MaterialApp.router(
        routerConfig: router,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
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
  IronwoodHomeMigrationCtaState Function()? ctaBuilder,
  bool hardware = false,
  rust_sync.OrchardMigrationPrivatePlan? privatePlan,
}) {
  final cta =
      status == null
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
        path: '/migration/private/review',
        builder:
            (_, _) => const MobileIronwoodMigrationFlowScreen(
              step: MobileIronwoodMigrationStep.privateReview,
            ),
      ),
      GoRoute(
        path: '/migration/private/status',
        builder: (_, _) => const MobileIronwoodMigrationPrivateStatusScreen(),
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
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
        ),
      ),
      ironwoodMigrationFlowDataProvider.overrideWith((ref) async => _data),
      ironwoodMigrationPrivatePlanProvider.overrideWith(
        (ref) async => privatePlan ?? _plan,
      ),
      ironwoodMigrationRouteCtaProvider.overrideWith(
        (ref) async => ctaBuilder?.call() ?? cta,
      ),
      ironwoodMigrationStatusProvider.overrideWith(
        (ref, request) async =>
            startedStatus ??
            status ??
            _status(phase: kIronwoodMigrationWaitingDenomConfirmationsPhase),
      ),
      ironwoodMigrationServiceProvider.overrideWithValue(migrationService),
    ],
    child: AppTheme(
      data: AppThemeData.light,
      child: MaterialApp.router(
        routerConfig: router,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
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
}) {
  return IronwoodMigrationService(
    getWalletDbPath: () async => '/tmp/wallet.db',
    getStatus:
        ({required dbPath, required network, required accountUuid}) async =>
            _status(phase: kIronwoodMigrationWaitingDenomConfirmationsPhase),
    getPrivatePlan:
        ({required dbPath, required network, required accountUuid}) async =>
            _plan,
    secureStore: AppSecureStore.testing(storage: const FlutterSecureStorage()),
    getEndpoint: () => defaultRpcEndpointConfig('main'),
    getSessionPassword: () => 'test-password',
    getMnemonicBytesForAccount: (_) async => [1, 2, 3],
    isMacOS: () => false,
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
    expect(find.text('How the migration works'), findsOneWidget);

    await tester.tap(find.text('How the migration works'));
    await tester.pumpAndSettle();

    expect(find.text('How Migration Works'), findsOneWidget);
    expect(find.text('Split funds'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_process_split_icon')),
      findsOneWidget,
    );
    expect(find.textContaining('1 split transaction'), findsOneWidget);
    expect(find.textContaining('12 migration batches'), findsOneWidget);
    expect(find.text('Schedule'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_process_schedule_icon')),
      findsOneWidget,
    );
    expect(find.text('Sign once'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_process_sign_icon')),
      findsOneWidget,
    );
  });

  testWidgets('shows the production migration type choice and private route', (
    tester,
  ) async {
    await tester.pumpWidget(_app(step: MobileIronwoodMigrationStep.options));
    await tester.pumpAndSettle();

    expect(find.text('Choose How to Migrate\nyour 142.24 ZEC'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_recommended_badge')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Sends independent parts over time windows. Slower, harder to track.',
      ),
      findsOneWidget,
    );
    expect(find.text('Immediate'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_immediate_unavailable')),
      findsOneWidget,
    );
    final immediateDescription = tester.widget<Text>(
      find.text(
        'Sends now in one step. Amount and timing are easier to associate.',
      ),
    );
    expect(immediateDescription.style?.color, const Color(0xFF626767));
    expect(immediateDescription.style?.fontWeight, FontWeight.w500);

    final unselectedRadio = tester.widget<Container>(
      find.byKey(const ValueKey('mobile_ironwood_unselected_radio')),
    );
    expect(
      (unselectedRadio.decoration! as BoxDecoration).color,
      const Color(0x33B8B8B8),
    );

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Review Migration Plan'), findsOneWidget);
  });

  testWidgets('renders the private migration review plan', (tester) async {
    await tester.pumpWidget(
      _app(step: MobileIronwoodMigrationStep.privateReview),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review Migration Plan'), findsOneWidget);
    expect(find.text('142.24 ZEC'), findsOneWidget);
    expect(find.text('12 planned batches'), findsOneWidget);
    expect(find.text('~ Arrival time'), findsOneWidget);
    expect(find.text('~1728 blocks'), findsOneWidget);
    expect(find.text('Per batch, ~0.012 ZEC'), findsOneWidget);
    expect(find.text('<0.001 ZEC'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(
      find.text(
        'Separate windows reduce correlation — the total crossing amount '
        'stays publicly visible. Sending is best effort, not a delivery time.',
      ),
      findsOneWidget,
    );
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
      172,
    );
    expect(find.text('<0.001 ZEC'), findsOneWidget);
    expect(find.text('Authorise anyway'), findsOneWidget);
  });

  testWidgets('renders the preparing migration state', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(_app(step: MobileIronwoodMigrationStep.preparing));
    await tester.pumpAndSettle();

    expect(find.text('Preparing...'), findsOneWidget);
    expect(find.byType(IronwoodMigrationShimmerText), findsOneWidget);
    expect(find.text('142.24 ZEC'), findsOneWidget);
    expect(find.text('Transaction splits submitted'), findsOneWidget);
    expect(find.text('Waiting for confirmation...'), findsOneWidget);
    expect(find.text('Migration schedule'), findsOneWidget);
    expect(find.text('Back home'), findsOneWidget);
  });

  testWidgets('opens and closes the migrating batch plan', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        step: MobileIronwoodMigrationStep.migrating,
        previewStatus: _visualMigrationStatus(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Migrating...'), findsOneWidget);
    final remainingAmount = tester.widget<Text>(
      find.byKey(const ValueKey('mobile_ironwood_remaining_amount')),
    );
    expect(remainingAmount.textSpan?.toPlainText(), '131.12 ZEC');
    expect(find.text('Left to transfer'), findsOneWidget);
    expect(find.bySemanticsLabel('9% done'), findsOneWidget);
    expect(find.text('12 planned batches'), findsOneWidget);
    expect(find.text('Current batch'), findsOneWidget);
    expect(find.text('Confirming...'), findsOneWidget);
    expect(find.text('4.12 ZEC'), findsOneWidget);
    expect(find.text('Estimated arrival time'), findsOneWidget);
    expect(find.text('July 18, 12:00'), findsOneWidget);
    expect(find.text('Wallet 1').hitTestable(), findsOneWidget);
    expect(
      find.text('You can leave this screen.').hitTestable(),
      findsOneWidget,
    );
    expect(
      find.text('But keep Vizor open & running.').hitTestable(),
      findsOneWidget,
    );
    expect(find.text('Back home').hitTestable(), findsOneWidget);

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();

    expect(find.text('12 batches'), findsOneWidget);
    expect(find.text('ETA: Jul 18, 12:00'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('migration_batch_scrollbar')),
      findsOneWidget,
    );
    expect(find.text('Close'), findsOneWidget);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_ironwood_batch_modal_card')),
      ),
      const Size(361, 480),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('mobile_ironwood_batch_modal_header')),
          )
          .height,
      46,
    );

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('12 batches'), findsNothing);
  });

  testWidgets('keeps migration status actions reachable on compact screens', (
    tester,
  ) async {
    _useMobileViewport(tester, size: const Size(320, 568));
    await tester.pumpWidget(_app(step: MobileIronwoodMigrationStep.preparing));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Back home'),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Back home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders passcode while migration keeps running', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _app(step: MobileIronwoodMigrationStep.passcodeWhileSyncing),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Migrating...'), findsOneWidget);
    expect(find.bySemanticsLabel('10% done'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
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
        ctaBuilder:
            () =>
                started
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

    final continueButton = find.text('Continue');
    expect(continueButton, findsOneWidget);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(startedAccountUuid, 'account-1');
    expect(startedSchedule, _plan.scheduledTransfers);
    expect(find.text('Preparing...'), findsOneWidget);
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
    expect(find.text('Sign private split'), findsOneWidget);
    expect(find.text('2 split transactions to sign'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_keystone_qr')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(
        const ValueKey('mobile_ironwood_keystone_scan_signature_button'),
      ),
    );
    await tester.pump();

    expect(find.text('Step 2/2'), findsOneWidget);
    expect(
      find.text('Scan the signed migration QR shown on Keystone.'),
      findsOneWidget,
    );
    expect(find.text('Back to QR'), findsOneWidget);
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

  testWidgets('routes a Keystone ready state to migration batch signing', (
    tester,
  ) async {
    _useMobileViewport(tester, size: const Size(320, 568));
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/status',
        migrationService: _migrationService(),
        status: _status(phase: kIronwoodMigrationReadyToMigratePhase),
        hardware: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ready for Keystone'), findsOneWidget);
    expect(find.text('3 migration transactions ready to sign'), findsOneWidget);
    final signButton = find.byKey(
      const ValueKey('mobile_ironwood_keystone_batch_sign_button'),
    );
    await tester.ensureVisible(signButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(signButton);
    await tester.pumpAndSettle();

    expect(find.text('keystone batch sign route'), findsOneWidget);
  });

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

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't start migration. Try again."), findsOneWidget);
    expect(find.text('Preparing...'), findsNothing);
  });

  testWidgets('maps a live denomination status to Preparing', (tester) async {
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

    expect(find.text('Preparing...'), findsOneWidget);
    expect(find.text('Waiting for confirmation...'), findsOneWidget);
    expect(find.text('Split 2 of 3, 2 of 10 confirmations'), findsOneWidget);
    expect(find.text('Transaction splits submitted'), findsOneWidget);
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

    expect(find.text('Migrating...'), findsOneWidget);
    expect(find.text('3 planned batches'), findsOneWidget);
    expect(find.bySemanticsLabel('33% done'), findsOneWidget);
    final remainingAmount = tester.widget<Text>(
      find.byKey(const ValueKey('mobile_ironwood_remaining_amount')),
    );
    expect(remainingAmount.textSpan?.toPlainText(), '8.24 ZEC');
    expect(find.text('4.12 ZEC'), findsOneWidget);
    expect(find.text('Migration status'), findsOneWidget);
    expect(find.text('Confirming...'), findsOneWidget);

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.text('3 batches'), findsOneWidget);
    expect(find.text('Pending'), findsNWidgets(3));
  });
}
