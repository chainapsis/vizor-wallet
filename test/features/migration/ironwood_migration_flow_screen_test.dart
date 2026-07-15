import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/screens/ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  setUpAll(() async {
    const fonts = <String, List<String>>{
      'Geist': [
        'assets/fonts/Geist-Regular.ttf',
        'assets/fonts/Geist-Medium.ttf',
        'assets/fonts/Geist-SemiBold.ttf',
        'assets/fonts/Geist-Bold.ttf',
      ],
      'Young Serif': ['assets/fonts/YoungSerif-Regular.ttf'],
    };
    for (final entry in fonts.entries) {
      final loader = FontLoader(entry.key);
      for (final asset in entry.value) {
        loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('option selection does not move card content', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_migrationOptionsHarness());
    await tester.pumpAndSettle();

    final privateTitle = find.text('Private Migration');
    final fastTitle = find.text('Fast Migration');
    expect(privateTitle, findsOneWidget);
    expect(fastTitle, findsOneWidget);

    final privateTitleInitialTopLeft = tester.getTopLeft(privateTitle);
    final fastTitleInitialTopLeft = tester.getTopLeft(fastTitle);

    await tester.tap(fastTitle);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(privateTitle), privateTitleInitialTopLeft);
    expect(tester.getTopLeft(fastTitle), fastTitleInitialTopLeft);

    await tester.tap(privateTitle);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(privateTitle), privateTitleInitialTopLeft);
    expect(tester.getTopLeft(fastTitle), fastTitleInitialTopLeft);
  });

  testWidgets('private selection opens review screen', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_migrationOptionsHarness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select & Review'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Review Private Migration'), findsOneWidget);
    expect(find.text('Move to Ironwood'), findsOneWidget);
    expect(find.text('Prepare migration'), findsOneWidget);
  });

  testWidgets('private review shows plan without preparing a transaction', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _migrationOptionsHarness(initialLocation: '/migration/private/review'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Move to Ironwood'), findsOneWidget);
    expect(find.text('0.10 ZEC'), findsWidgets);
    expect(find.text('Estimated fee'), findsOneWidget);
    expect(find.text('0.0001 ZEC'), findsOneWidget);
    expect(
      find.textContaining(
        'No transaction is broadcast from this review screen',
      ),
      findsOneWidget,
    );
  });

  testWidgets('private review starts software migration and opens status', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? startedAccountUuid;
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus: ({required dbPath, required network, required accountUuid}) {
        return Future.value(_status());
      },
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) {
            return Future.value(_privatePlan());
          },
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      getEndpoint: () => defaultRpcEndpointConfig('main'),
      getSessionPassword: () => 'test-password',
      getMnemonicBytesForAccount: (_) async => [1, 2, 3, 4],
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
          }) {
            startedAccountUuid = accountUuid;
            return Future.value(_migrationResult());
          },
    );

    await tester.pumpWidget(
      _migrationOptionsHarness(
        initialLocation: '/migration/private/review',
        migrationService: service,
      ),
    );
    await tester.pumpAndSettle();

    final prepareButton = find.widgetWithText(AppButton, 'Prepare migration');
    expect(prepareButton, findsOneWidget);
    expect(tester.widget<AppButton>(prepareButton).onPressed, isNotNull);

    await tester.tap(prepareButton);
    await tester.pumpAndSettle();

    expect(startedAccountUuid, 'account-1');
    expect(find.text('Confirming Private Split'), findsOneWidget);
  });

  testWidgets('legacy review route redirects to private review', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _migrationOptionsHarness(initialLocation: '/migration/review'),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Review Private Migration'), findsOneWidget);
    expect(find.text('Move to Ironwood'), findsOneWidget);
  });

  testWidgets('private status shows resume progress state', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _migrationOptionsHarness(initialLocation: '/migration/private/status'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirming Private Split'), findsOneWidget);
    expect(find.text('Split progress'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('Waiting for confirmations'), findsOneWidget);
  });

  testWidgets('private status continues due software migration', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? continuedAccountUuid;
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus: ({required dbPath, required network, required accountUuid}) {
        return Future.value(_status());
      },
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) {
            return Future.value(_privatePlan());
          },
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      getEndpoint: () => defaultRpcEndpointConfig('main'),
      getSessionPassword: () => 'test-password',
      broadcastDueMigration:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required password,
            required saltBase64,
          }) {
            continuedAccountUuid = accountUuid;
            return Future.value(_migrationResult());
          },
    );

    await tester.pumpWidget(
      _migrationEntryHarness(
        ctaState: IronwoodHomeMigrationCtaState.resume(
          network: 'main',
          accountUuid: 'account-1',
          status: _migrationStatus(
            phase: kIronwoodMigrationReadyToMigratePhase,
            activeRunId: 'run-1',
          ),
        ),
        initialLocation: '/migration/private/status',
        realStatusRoute: true,
        migrationService: service,
      ),
    );
    await tester.pumpAndSettle();

    final continueButton = find.widgetWithText(AppButton, 'Continue migration');
    expect(continueButton, findsOneWidget);
    expect(tester.widget<AppButton>(continueButton).onPressed, isNotNull);

    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(continuedAccountUuid, 'account-1');
  });

  testWidgets('migration entry routes start state to intro', (tester) async {
    await tester.pumpWidget(
      _migrationEntryHarness(
        ctaState: IronwoodHomeMigrationCtaState.start(
          network: 'test',
          accountUuid: 'account-1',
          status: _migrationStatus(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('intro-route'), findsOneWidget);
  });

  testWidgets('migration entry routes resume state to private status', (
    tester,
  ) async {
    await tester.pumpWidget(
      _migrationEntryHarness(
        ctaState: IronwoodHomeMigrationCtaState.resume(
          network: 'test',
          accountUuid: 'account-1',
          status: _migrationStatus(
            phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
            activeRunId: 'run-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('private-status-route'), findsOneWidget);
  });

  testWidgets('migration entry routes hidden state home', (tester) async {
    await tester.pumpWidget(
      _migrationEntryHarness(
        ctaState: const IronwoodHomeMigrationCtaState.hidden(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('home-route'), findsOneWidget);
  });

  testWidgets('private status fails closed when status lookup fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      _migrationEntryHarness(
        ctaState: const IronwoodHomeMigrationCtaState.hidden(),
        initialLocation: '/migration/private/status',
        routeError: Exception('status unavailable'),
        realStatusRoute: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Migration status unavailable'), findsOneWidget);
    expect(find.text('intro-route'), findsNothing);
    expect(find.text('home-route'), findsNothing);
  });

  test(
    'private plan provider calls the migration service for active inputs',
    () async {
      String? seenNetwork;
      String? seenAccountUuid;
      final expected = _privatePlan();
      final container = ProviderContainer(
        overrides: [
          ironwoodMigrationFlowDataProvider.overrideWith(
            (ref) async => IronwoodMigrationFlowData(
              amountZatoshi: BigInt.from(10_000_000),
              accountName: 'Account 1',
              profilePictureId: kDefaultProfilePictureId,
            ),
          ),
          ironwoodMigrationInputsProvider.overrideWithValue(
            IronwoodMigrationInputs(
              ironwoodActiveAtTip: true,
              network: 'test',
              accountUuid: 'account-1',
              accountName: 'Account 1',
              profilePictureId: kDefaultProfilePictureId,
              hasAccountScopedData: true,
              isSyncing: false,
              isBackgroundMode: false,
              hasSyncFailure: false,
              orchardBalance: BigInt.from(10_000_000),
              orchardPendingBalance: BigInt.zero,
            ),
          ),
          ironwoodMigrationServiceProvider.overrideWithValue(
            IronwoodMigrationService(
              getWalletDbPath: () async => '/tmp/wallet.db',
              getStatus:
                  ({required dbPath, required network, required accountUuid}) {
                    return Future.value(_migrationStatus());
                  },
              getPrivatePlan:
                  ({required dbPath, required network, required accountUuid}) {
                    seenNetwork = network;
                    seenAccountUuid = accountUuid;
                    return Future.value(expected);
                  },
              secureStore: AppSecureStore.testing(
                storage: const FlutterSecureStorage(),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final plan = await container.read(
        ironwoodMigrationPrivatePlanProvider.future,
      );

      expect(plan, expected);
      expect(seenNetwork, 'test');
      expect(seenAccountUuid, 'account-1');
    },
  );
}

Widget _migrationOptionsHarness({
  String initialLocation = '/migration/options',
  IronwoodMigrationService? migrationService,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/migration/options',
        builder: (_, _) => IronwoodMigrationFlowScreen(
          step: IronwoodMigrationFlowStep.options,
          previewData: IronwoodMigrationFlowData(
            amountZatoshi: BigInt.from(10_000_000),
            accountName: 'Account 1',
            profilePictureId: kDefaultProfilePictureId,
          ),
        ),
      ),
      GoRoute(
        path: '/migration/review',
        redirect: (_, _) => '/migration/private/review',
      ),
      GoRoute(
        path: '/migration/private/review',
        builder: (_, _) => IronwoodMigrationFlowScreen(
          step: IronwoodMigrationFlowStep.review,
          previewData: IronwoodMigrationFlowData(
            amountZatoshi: BigInt.from(10_000_000),
            accountName: 'Account 1',
            profilePictureId: kDefaultProfilePictureId,
          ),
          previewPrivatePlan: _privatePlan(),
        ),
      ),
      GoRoute(
        path: '/migration/private/status',
        builder: (_, _) =>
            IronwoodMigrationPrivateStatusScreen(previewStatus: _status()),
      ),
      GoRoute(
        path: '/migration/how-it-works',
        builder: (_, _) => const Text('how it works'),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home')),
      GoRoute(path: '/swap', builder: (_, _) => const Text('swap')),
      GoRoute(path: '/voting', builder: (_, _) => const Text('voting')),
      GoRoute(path: '/activity', builder: (_, _) => const Text('activity')),
      GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
      GoRoute(path: '/accounts', builder: (_, _) => const Text('accounts')),
      GoRoute(
        path: '/add-account',
        builder: (_, _) => const Text('add account'),
      ),
      GoRoute(path: '/unlock', builder: (_, _) => const Text('unlock')),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      syncProvider.overrideWith(() => _FakeSyncNotifier(_syncedSyncState)),
      swapFeatureEnabledProvider.overrideWithValue(true),
      if (migrationService != null)
        ironwoodMigrationServiceProvider.overrideWithValue(migrationService),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: true, textScaler: TextScaler.noScaling),
        child: AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
}

Widget _migrationEntryHarness({
  required IronwoodHomeMigrationCtaState ctaState,
  String initialLocation = '/migration',
  Object? routeError,
  bool realStatusRoute = false,
  IronwoodMigrationService? migrationService,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/migration',
        builder: (_, _) => const IronwoodMigrationEntryScreen(),
      ),
      GoRoute(
        path: '/migration/intro',
        builder: (_, _) => const Text('intro-route'),
      ),
      GoRoute(
        path: '/migration/private/status',
        builder: (_, _) => realStatusRoute
            ? const IronwoodMigrationPrivateStatusScreen()
            : const Text('private-status-route'),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home-route')),
    ],
  );

  return ProviderScope(
    overrides: [
      ironwoodMigrationRouteCtaProvider.overrideWith((ref) async {
        final error = routeError;
        if (error != null) throw error;
        return ctaState;
      }),
      appBootstrapProvider.overrideWithValue(_bootstrap),
      syncProvider.overrideWith(() => _FakeSyncNotifier(_syncedSyncState)),
      swapFeatureEnabledProvider.overrideWithValue(true),
      if (migrationService != null)
        ironwoodMigrationServiceProvider.overrideWithValue(migrationService),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) =>
          AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/migration/options',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Account 1',
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

final _syncedSyncState = SyncState(
  accountUuid: 'account-1',
  hasAccountScopedData: true,
);

class _FakeSyncNotifier extends SyncNotifier {
  _FakeSyncNotifier(this.initialState);

  final SyncState initialState;

  @override
  Future<SyncState> build() async => initialState;
}

rust_sync.OrchardMigrationPrivatePlan _privatePlan() {
  return rust_sync.OrchardMigrationPrivatePlan(
    targetValuesZatoshi: frb.Uint64List.fromList([10_000_000]),
    totalInputZatoshi: BigInt.from(10_010_000),
    totalMigratableZatoshi: BigInt.from(10_000_000),
    denominationSplitFeeZatoshi: BigInt.from(5_000),
    migrationFeeZatoshi: BigInt.from(5_000),
    estimatedTotalFeeZatoshi: BigInt.from(10_000),
    plannedBatchCount: 1,
    denominationSplitStageCount: 0,
    signingBatchLimit: 50,
    broadcastWindowSeconds: BigInt.from(180),
    maxPreparedNotesPerRun: 64,
  );
}

rust_sync.MigrationStatus _migrationStatus({
  String phase = kIronwoodMigrationReadyPhase,
  String? activeRunId,
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    activeRunId: activeRunId,
    targetValuesZatoshi: frb.Uint64List.fromList([]),
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
    signingBatchLimit: 50,
    broadcastWindowSeconds: BigInt.from(180),
    maxPreparedNotesPerRun: 64,
    scheduledBroadcasts: const [],
  );
}

rust_sync.MigrationStatus _status() {
  return rust_sync.MigrationStatus(
    phase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
    activeRunId: 'run-1',
    targetValuesZatoshi: frb.Uint64List.fromList([10_000_000]),
    preparedNoteCount: 1,
    denominationConfirmationCount: 2,
    denominationConfirmationTarget: 10,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 3,
    pendingTxCount: 0,
    broadcastedTxCount: 1,
    confirmedTxCount: 0,
    totalCount: 3,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 2,
    canAbandon: false,
    signingBatchLimit: 50,
    broadcastWindowSeconds: BigInt.from(180),
    maxPreparedNotesPerRun: 64,
    scheduledBroadcasts: const [],
  );
}

rust_sync.IronwoodMigrationResult _migrationResult() {
  return rust_sync.IronwoodMigrationResult(
    txids: 'txid',
    status: 'broadcasted',
    broadcastedCount: 1,
    totalCount: 1,
    feeZatoshi: BigInt.from(10_000),
    migratedZatoshi: BigInt.from(10_000_000),
  );
}
