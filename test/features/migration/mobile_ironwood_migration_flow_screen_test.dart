@Tags(['mobile'])
library;

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
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/screens/ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/features/migration/screens/mobile/mobile_ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

final _data = IronwoodMigrationFlowData(
  amountZatoshi: BigInt.from(14_224_000_000),
  accountName: 'Wallet 1',
  profilePictureId: 'default',
);

rust_sync.OrchardMigrationPrivatePlan get _plan =>
    rust_sync.OrchardMigrationPrivatePlan(
      targetValuesZatoshi: frb.Uint64List.fromList([]),
      totalInputZatoshi: BigInt.from(14_224_000_000),
      totalMigratableZatoshi: BigInt.from(14_223_900_000),
      orchardChangeZatoshi: BigInt.from(90_000),
      denominationSplitFeeZatoshi: BigInt.from(20_000),
      migrationFeeZatoshi: BigInt.from(14_400_000),
      estimatedTotalFeeZatoshi: BigInt.from(14_420_000),
      plannedBatchCount: 12,
      denominationSplitStageCount: 1,
      signingBatchLimit: 12,
      broadcastWindowSeconds: BigInt.from(172_800),
      maxPreparedNotesPerRun: 12,
    );

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
    broadcastWindowSeconds: BigInt.from(172_800),
    maxPreparedNotesPerRun: 12,
    scheduledBroadcasts: const [],
  );
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/migration/private/review',
  initialAccountState: AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Wallet 1',
        order: 0,
        profilePictureId: kDefaultProfilePictureId,
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
}) {
  late final GoRouter router;
  MobileIronwoodMigrationFlowScreen screen(MobileIronwoodMigrationStep value) {
    return MobileIronwoodMigrationFlowScreen(
      step: value,
      previewData: _data,
      previewPrivatePlan: _plan,
      previewArrivalLabel: 'July 18, 12:00 (~2days)',
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
        builder: (_, _) =>
            screen(MobileIronwoodMigrationStep.passcodeWhileSyncing),
      ),
    ],
  );

  return ProviderScope(
    child: AppTheme(
      data: theme,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

Widget _productionApp({
  required String initialLocation,
  required IronwoodMigrationService migrationService,
  rust_sync.MigrationStatus? status,
  rust_sync.MigrationStatus? startedStatus,
  IronwoodHomeMigrationCtaState Function()? ctaBuilder,
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
        path: '/migration/private/review',
        builder: (_, _) => const MobileIronwoodMigrationFlowScreen(
          step: MobileIronwoodMigrationStep.privateReview,
        ),
      ),
      GoRoute(
        path: '/migration/private/status',
        builder: (_, _) => const MobileIronwoodMigrationPrivateStatusScreen(),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
        ),
      ),
      ironwoodMigrationFlowDataProvider.overrideWith((ref) async => _data),
      ironwoodMigrationPrivatePlanProvider.overrideWith((ref) async => _plan),
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
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

IronwoodMigrationService _migrationService({
  Future<rust_sync.IronwoodMigrationResult> Function(String accountUuid)?
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
        }) => onStart?.call(accountUuid) ?? Future.value(_migrationResult()),
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

void _useMobileViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
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
    expect(find.text('How the migration works'), findsOneWidget);

    await tester.tap(find.text('How the migration works'));
    await tester.pumpAndSettle();

    expect(find.text('How Migration Works'), findsOneWidget);
    expect(find.text('Split funds'), findsOneWidget);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Sign once'), findsOneWidget);
  });

  testWidgets('shows the production migration type choice and private route', (
    tester,
  ) async {
    await tester.pumpWidget(_app(step: MobileIronwoodMigrationStep.options));
    await tester.pumpAndSettle();

    expect(find.text('Choose How to Migrate\nyour 142.24 ZEC'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    expect(find.text('Immediate'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_immediate_unavailable')),
      findsOneWidget,
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
    expect(find.text('July 18, 12:00 (~2days)'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
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
    expect(find.text('Authorise anyway'), findsOneWidget);
  });

  testWidgets('renders the preparing migration state', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(_app(step: MobileIronwoodMigrationStep.preparing));
    await tester.pumpAndSettle();

    expect(find.text('Preparing...'), findsOneWidget);
    expect(find.text('142.24 ZEC'), findsOneWidget);
    expect(find.text('Transaction splits submitted'), findsOneWidget);
    expect(find.text('Waiting for confirmation ...'), findsOneWidget);
    expect(find.text('Migration schedule'), findsOneWidget);
    expect(find.text('Back home'), findsOneWidget);
  });

  testWidgets('opens and closes the migrating batch plan', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(_app(step: MobileIronwoodMigrationStep.migrating));
    await tester.pumpAndSettle();

    expect(find.text('Migrating...'), findsOneWidget);
    expect(find.text('142.24 ZEC'), findsOneWidget);
    expect(find.text('12 planned batches'), findsOneWidget);
    expect(find.text('Current batch'), findsOneWidget);
    expect(find.text('Confirming...'), findsOneWidget);
    expect(find.text('July 18, 12:00'), findsOneWidget);

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

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('12 batches'), findsNothing);
  });

  testWidgets('renders passcode while migration keeps running', (tester) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _app(step: MobileIronwoodMigrationStep.passcodeWhileSyncing),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Migrating...'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('starts a software migration and opens the status route', (
    tester,
  ) async {
    _useMobileViewport(tester);
    String? startedAccountUuid;
    var started = false;
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(
          onStart: (accountUuid) async {
            startedAccountUuid = accountUuid;
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

    final continueButton = find.text('Continue');
    expect(continueButton, findsOneWidget);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(startedAccountUuid, 'account-1');
    expect(find.text('Preparing...'), findsOneWidget);
  });

  testWidgets('keeps review visible when start has no durable run', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _productionApp(
        initialLocation: '/migration/private/review',
        migrationService: _migrationService(
          onStart: (_) async => _migrationResult(),
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
    expect(find.text('Waiting for confirmation ...'), findsOneWidget);
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
    expect(find.text('33% DONE'), findsOneWidget);
    expect(find.text('4.12 ZEC'), findsOneWidget);
    expect(find.text('Schedule pending'), findsOneWidget);

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.text('3 batches'), findsOneWidget);
    expect(find.text('Pending'), findsNWidgets(3));
  });
}
