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
      _migrationOptionsHarness(initialLocation: '/migration/review'),
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

rust_sync.MigrationStatus _migrationStatus() {
  return rust_sync.MigrationStatus(
    phase: 'ready_to_prepare',
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
