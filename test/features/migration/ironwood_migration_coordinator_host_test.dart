import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_service.dart';
import 'package:zcash_wallet/src/features/migration/widgets/ironwood_migration_coordinator_host.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

const _accountUuid = '550e8400-e29b-41d4-a716-446655440000';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('waits until the next scheduled broadcast is due', () {
    final now = DateTime(2026, 7, 17, 12);
    final status = _status(
      phase: kIronwoodMigrationBroadcastScheduledPhase,
      scheduledBroadcasts: [
        rust_sync.MigrationScheduledBroadcast(
          txidHex: 'confirmed',
          valueZatoshi: BigInt.one,
          scheduledAtMs: now
              .subtract(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
          scheduledHeight: 1,
          status: 'confirmed',
        ),
        rust_sync.MigrationScheduledBroadcast(
          txidHex: 'next',
          valueZatoshi: BigInt.one,
          scheduledAtMs: now
              .add(const Duration(seconds: 17))
              .millisecondsSinceEpoch,
          scheduledHeight: 2,
          status: 'scheduled',
        ),
        rust_sync.MigrationScheduledBroadcast(
          txidHex: 'later',
          valueZatoshi: BigInt.one,
          scheduledAtMs: now
              .add(const Duration(seconds: 48))
              .millisecondsSinceEpoch,
          scheduledHeight: 3,
          status: 'scheduled',
        ),
      ],
    );

    expect(
      ironwoodMigrationScheduledAdvanceDelay(status, now: now),
      const Duration(seconds: 17),
    );
  });

  test('advances immediately when a scheduled broadcast is overdue', () {
    final now = DateTime(2026, 7, 17, 12);
    final status = _status(
      phase: kIronwoodMigrationBroadcastScheduledPhase,
      scheduledBroadcasts: [
        rust_sync.MigrationScheduledBroadcast(
          txidHex: 'due',
          valueZatoshi: BigInt.one,
          scheduledAtMs: now
              .subtract(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
          scheduledHeight: 1,
          status: 'scheduled',
        ),
      ],
    );

    expect(
      ironwoodMigrationScheduledAdvanceDelay(status, now: now),
      Duration.zero,
    );
  });

  for (final phase in [
    kIronwoodMigrationWaitingDenomConfirmationsPhase,
    kIronwoodMigrationReadyToMigratePhase,
    kIronwoodMigrationBroadcastScheduledPhase,
  ]) {
    testWidgets('continues $phase without the migration screen mounted', (
      tester,
    ) async {
      var continueCount = 0;
      await tester.pumpWidget(
        _app(
          status: _status(
            phase: phase,
            pendingSplitStageCount:
                phase == kIronwoodMigrationWaitingDenomConfirmationsPhase
                ? 1
                : 0,
          ),
          migrationService: _migrationService(
            onContinue: (_) async {
              continueCount += 1;
              return _migrationResult();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('home surface'), findsOneWidget);
      expect(continueCount, 1);
    });
  }

  testWidgets('does not continue while the wallet is locked', (tester) async {
    var continueCount = 0;
    await tester.pumpWidget(
      _app(
        status: _status(phase: kIronwoodMigrationReadyToMigratePhase),
        migrationService: _migrationService(
          onContinue: (_) async {
            continueCount += 1;
            return _migrationResult();
          },
        ),
        unlocked: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(continueCount, 0);
  });

  testWidgets('waits for a hardware signature when migration is ready', (
    tester,
  ) async {
    var continueCount = 0;
    var statusReadCount = 0;
    await tester.pumpWidget(
      _app(
        status: _status(phase: kIronwoodMigrationReadyToMigratePhase),
        migrationService: _migrationService(
          onContinue: (_) async {
            continueCount += 1;
            return _migrationResult();
          },
        ),
        hardware: true,
        onStatusRead: () => statusReadCount += 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(continueCount, 0);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final readsAfterRefresh = statusReadCount;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(statusReadCount, readsAfterRefresh);
  });

  for (final phase in [
    kIronwoodMigrationWaitingDenomConfirmationsPhase,
    kIronwoodMigrationBroadcastScheduledPhase,
  ]) {
    testWidgets('continues signed hardware work in $phase', (tester) async {
      var continueCount = 0;
      await tester.pumpWidget(
        _app(
          status: _status(
            phase: phase,
            pendingSplitStageCount:
                phase == kIronwoodMigrationWaitingDenomConfirmationsPhase
                ? 1
                : 0,
          ),
          migrationService: _migrationService(
            onContinue: (_) async {
              continueCount += 1;
              return _migrationResult();
            },
          ),
          hardware: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(continueCount, 1);
    });
  }

  testWidgets('keeps automatic continuation single-flight', (tester) async {
    final continuation = Completer<rust_sync.IronwoodMigrationResult>();
    var continueCount = 0;
    await tester.pumpWidget(
      _app(
        status: _status(phase: kIronwoodMigrationReadyToMigratePhase),
        migrationService: _migrationService(
          onContinue: (_) {
            continueCount += 1;
            return continuation.future;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));

    expect(continueCount, 1);

    continuation.complete(_migrationResult());
    await tester.pumpAndSettle();
  });
}

Widget _app({
  required rust_sync.MigrationStatus status,
  required IronwoodMigrationService migrationService,
  bool unlocked = true,
  bool hardware = false,
  VoidCallback? onStatusRead,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _bootstrap(unlocked: unlocked, hardware: hardware),
      ),
      ironwoodMigrationRouteCtaProvider.overrideWith((ref) async {
        onStatusRead?.call();
        return IronwoodHomeMigrationCtaState.resume(
          network: 'main',
          accountUuid: _accountUuid,
          status: status,
        );
      }),
      ironwoodMigrationServiceProvider.overrideWithValue(migrationService),
    ],
    child: const MaterialApp(
      home: IronwoodMigrationCoordinatorHost(
        child: Scaffold(body: Text('home surface')),
      ),
    ),
  );
}

AppBootstrapState _bootstrap({required bool unlocked, required bool hardware}) {
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: AccountState(
      accounts: [
        AccountInfo(
          uuid: _accountUuid,
          name: 'Account 1',
          order: 0,
          isHardware: hardware,
        ),
      ],
      activeAccountUuid: _accountUuid,
      activeAddress: 'u1testaddress',
    ),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: defaultRpcEndpointConfig('main'),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: unlocked,
    passwordRotationRecoveryFailed: false,
  );
}

IronwoodMigrationService _migrationService({
  required Future<rust_sync.IronwoodMigrationResult> Function(
    String accountUuid,
  )
  onContinue,
}) {
  return IronwoodMigrationService(
    getWalletDbPath: () async => '/tmp/wallet.db',
    getStatus:
        ({required dbPath, required network, required accountUuid}) async =>
            _status(phase: kIronwoodMigrationReadyToMigratePhase),
    getPrivatePlan:
        ({required dbPath, required network, required accountUuid}) async =>
            null,
    secureStore: AppSecureStore.testing(storage: const FlutterSecureStorage()),
    getEndpoint: () => defaultRpcEndpointConfig('main'),
    getSessionPassword: () => 'test-password',
    getMnemonicBytesForAccount: (_) async => [1, 2, 3],
    isMacOS: () => false,
    broadcastDueMigration:
        ({
          required dbPath,
          required lightwalletdUrl,
          required network,
          required accountUuid,
          required password,
          required saltBase64,
        }) => onContinue(accountUuid),
  );
}

rust_sync.MigrationStatus _status({
  required String phase,
  int pendingSplitStageCount = 0,
  List<rust_sync.MigrationScheduledBroadcast> scheduledBroadcasts = const [],
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    activeRunId: 'run-1',
    targetValuesZatoshi: frb.Uint64List(0),
    preparedNoteCount: 0,
    denominationConfirmationCount: 0,
    denominationConfirmationTarget: 10,
    denominationSplitCompletedCount: 0,
    denominationSplitTotalCount: 1,
    pendingTxCount: 0,
    broadcastedTxCount: 0,
    confirmedTxCount: 0,
    totalCount: 1,
    signedChildPcztCount: 0,
    pendingSplitStageCount: pendingSplitStageCount,
    canAbandon: false,
    signingBatchLimit: 0,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    maxPreparedNotesPerRun: 0,
    scheduledBroadcasts: scheduledBroadcasts,
  );
}

rust_sync.IronwoodMigrationResult _migrationResult() {
  return rust_sync.IronwoodMigrationResult(
    txids: 'txid',
    status: 'broadcasted',
    broadcastedCount: 1,
    totalCount: 1,
    feeZatoshi: BigInt.from(10_000),
    migratedZatoshi: BigInt.from(1_000_000),
  );
}
