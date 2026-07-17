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

  testWidgets('does not auto-continue a hardware account', (tester) async {
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
        hardware: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(continueCount, 0);
  });

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
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _bootstrap(unlocked: unlocked, hardware: hardware),
      ),
      ironwoodMigrationRouteCtaProvider.overrideWith(
        (ref) async => IronwoodHomeMigrationCtaState.resume(
          network: 'main',
          accountUuid: _accountUuid,
          status: status,
        ),
      ),
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
    broadcastWindowSeconds: BigInt.zero,
    maxPreparedNotesPerRun: 0,
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
    migratedZatoshi: BigInt.from(1_000_000),
  );
}
