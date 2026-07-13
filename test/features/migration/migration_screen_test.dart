import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show Uint64List;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/migration/providers/migration_expected_transfer_count_provider.dart';
import 'package:zcash_wallet/src/features/migration/providers/orchard_migration_status_provider.dart';
import 'package:zcash_wallet/src/features/migration/screens/migration_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'progress poll refreshes migration status when settled sync is unchanged',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final initialSync = _settledSyncState();
      final sync = _FakeSyncNotifier(initialSync);
      var statusBuildCount = 0;
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap),
          syncProvider.overrideWith(() => sync),
          migrationExpectedTransferCountProvider.overrideWith(
            _FakeMigrationExpectedTransferCountNotifier.new,
          ),
          activeOrchardMigrationStatusProvider.overrideWith((_) async {
            statusBuildCount += 1;
            return _completeStatus;
          }),
        ],
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/migration',
        routes: [
          GoRoute(
            path: '/migration',
            builder: (_, _) => const MigrationScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);

      await container.read(accountProvider.future);
      await container.read(syncProvider.future);
      await container.read(activeOrchardMigrationStatusProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            builder: (_, child) =>
                AppTheme(data: AppThemeData.light, child: child!),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await container.read(activeOrchardMigrationStatusProvider.future);
      await tester.pump();

      // Ignore the immediate post-frame poll and measure one periodic interval.
      final refreshBaseline = sync.refreshCount;
      final statusBuildBaseline = statusBuildCount;
      final settledFingerprint = settledSyncFingerprint(initialSync);
      expect(refreshBaseline, greaterThanOrEqualTo(1));
      expect(statusBuildBaseline, greaterThanOrEqualTo(1));
      expect(settledFingerprint, isNotNull);

      await tester.pump(const Duration(seconds: 4));
      await tester.pump();

      expect(sync.refreshCount, refreshBaseline);
      expect(statusBuildCount, statusBuildBaseline);
      expect(container.read(syncProvider).value, same(initialSync));
      expect(
        settledSyncFingerprint(container.read(syncProvider).value),
        settledFingerprint,
      );

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(sync.refreshCount, refreshBaseline + 1);
      expect(statusBuildCount, statusBuildBaseline + 1);
      expect(container.read(syncProvider).value, same(initialSync));
      expect(
        settledSyncFingerprint(container.read(syncProvider).value),
        settledFingerprint,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'uses exact run txids when same-block history sorts first tx first',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const firstTxid =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const secondTxid =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      final now = DateTime.now();
      final sync = _FakeSyncNotifier(
        _settledSyncState(
          recentTransactions: [
            _migrationTransaction(firstTxid, BigInt.from(100000000)),
            _migrationTransaction(secondTxid, BigInt.from(100000000)),
            _migrationTransaction(
              'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
              BigInt.from(900000000),
            ),
          ],
        ),
      );
      final expectedCount = MigrationExpectedTransferCount(
        count: 30,
        firstTxid: firstTxid,
        startedAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      );
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap),
          syncProvider.overrideWith(() => sync),
          migrationExpectedTransferCountProvider.overrideWith(
            () => _FakeMigrationExpectedTransferCountNotifier({
              'account-1': expectedCount,
            }),
          ),
          activeOrchardMigrationStatusProvider.overrideWith(
            (_) async => _waitingStatus(firstTxid, secondTxid),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/migration',
        routes: [
          GoRoute(
            path: '/migration',
            builder: (_, _) => const MigrationScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);

      await container.read(accountProvider.future);
      await container.read(syncProvider.future);
      await container.read(activeOrchardMigrationStatusProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            builder: (_, child) =>
                AppTheme(data: AppThemeData.light, child: child!),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('2 of 30 confirmed'), findsOneWidget);
      expect(find.text('Migrating 2 ZEC'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

class _FakeSyncNotifier extends SyncNotifier {
  _FakeSyncNotifier(this.initialState);

  final SyncState initialState;
  int refreshCount = 0;

  @override
  Future<SyncState> build() async => initialState;

  @override
  Future<void> refreshAfterSend({
    int transactionHistoryLimit = defaultRecentTransactionHistoryLimit,
  }) async {
    refreshCount += 1;
  }

  @override
  Future<void> startSyncAnyway() async {}
}

class _FakeMigrationExpectedTransferCountNotifier
    extends MigrationExpectedTransferCountNotifier {
  _FakeMigrationExpectedTransferCountNotifier([this.initial = const {}]);

  final Map<String, MigrationExpectedTransferCount> initial;

  @override
  Map<String, MigrationExpectedTransferCount> build() => initial;
}

SyncState _settledSyncState({
  List<rust_sync.TransactionInfo>? recentTransactions,
}) {
  return SyncState(
    accountUuid: 'account-1',
    hasAccountScopedData: true,
    scannedHeight: 9429,
    chainTipHeight: 9429,
    percentage: 1,
    recentTransactions:
        recentTransactions ??
        [
          rust_sync.TransactionInfo(
            txidHex:
                '0000000000000000000000000000000000000000000000000000000000000001',
            minedHeight: BigInt.zero,
            expiredUnmined: false,
            accountBalanceDelta: 0,
            fee: BigInt.zero,
            blockTime: BigInt.zero,
            isTransparent: false,
            txKind: 'migration',
            displayAmount: BigInt.one,
            displayPool: 'ironwood',
            createdTime: BigInt.zero,
          ),
        ],
  );
}

rust_sync.TransactionInfo _migrationTransaction(String txid, BigInt amount) {
  return rust_sync.TransactionInfo(
    txidHex: txid,
    minedHeight: BigInt.from(9439),
    expiredUnmined: false,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    blockTime: BigInt.zero,
    isTransparent: false,
    txKind: 'migration',
    displayAmount: amount,
    displayPool: 'ironwood',
    createdTime: BigInt.zero,
  );
}

rust_sync.MigrationStatus _waitingStatus(String firstTxid, String secondTxid) {
  return rust_sync.MigrationStatus(
    phase: 'waiting_migration_confirmations',
    activeRunId: 'run-1',
    targetValuesZatoshi: Uint64List(0),
    preparedNoteCount: 0,
    denominationConfirmationCount: 3,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 3,
    denominationSplitTotalCount: 3,
    pendingTxCount: 0,
    broadcastedTxCount: 28,
    confirmedTxCount: 2,
    totalCount: 30,
    signedChildPcztCount: 0,
    pendingPrepTxCount: 0,
    canAbandon: false,
    signingBatchLimit: 8,
    broadcastWindowSeconds: BigInt.from(180),
    maxPreparedNotesPerRun: 64,
    scheduledBroadcasts: [
      rust_sync.MigrationScheduledBroadcast(
        txidHex: firstTxid,
        scheduledAtMs: 1,
        status: 'confirmed',
      ),
      rust_sync.MigrationScheduledBroadcast(
        txidHex: secondTxid,
        scheduledAtMs: 2,
        status: 'confirmed',
      ),
    ],
  );
}

final _completeStatus = rust_sync.MigrationStatus(
  phase: 'complete',
  targetValuesZatoshi: Uint64List(0),
  preparedNoteCount: 0,
  denominationConfirmationCount: 3,
  denominationConfirmationTarget: 3,
  denominationSplitCompletedCount: 3,
  denominationSplitTotalCount: 3,
  pendingTxCount: 0,
  broadcastedTxCount: 0,
  confirmedTxCount: 1,
  totalCount: 1,
  signedChildPcztCount: 0,
  pendingPrepTxCount: 0,
  canAbandon: false,
  signingBatchLimit: 8,
  broadcastWindowSeconds: BigInt.from(60),
  maxPreparedNotesPerRun: 64,
  scheduledBroadcasts: const [],
);

final _bootstrap = AppBootstrapState(
  initialLocation: '/migration',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Primary Vault',
        order: 0,
        profilePictureId: kDefaultProfilePictureId,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1migrationaddress',
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
