import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show Uint64List;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/migration/providers/migration_run_controller.dart';
import 'package:zcash_wallet/src/features/migration/providers/orchard_migration_status_provider.dart';
import 'package:zcash_wallet/src/features/migration/widgets/global_migration_warning_banner.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'does not overlap migration activity ticks while a broadcast is pending',
    (tester) async {
      final migrationController = _BlockingMigrationRunController();
      final sync = _RecordingSyncNotifier();
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap),
          migrationRunControllerProvider.overrideWith(
            () => migrationController,
          ),
          syncProvider.overrideWith(() => sync),
          activeOrchardMigrationStatusProvider.overrideWith(
            (_) async => _dueBroadcastStatus(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(accountProvider.future);
      await container.read(syncProvider.future);
      container.read(migrationRunControllerProvider);
      await container.read(activeOrchardMigrationStatusProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (_, child) =>
                AppTheme(data: AppThemeData.light, child: child!),
            home: const Scaffold(body: GlobalMigrationWarningBanner()),
          ),
        ),
      );
      await tester.pump();

      expect(migrationController.broadcastCount, 1);
      expect(sync.forcedSyncCount, 0);

      await tester.pump(const Duration(seconds: 10));
      await tester.pump();

      expect(migrationController.broadcastCount, 1);
      expect(sync.forcedSyncCount, 0);

      migrationController.completeBroadcast();
      await tester.pump();
      await tester.pump();

      expect(sync.forcedSyncCount, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('keeps syncing without rebroadcasting already sent children', (
    tester,
  ) async {
    final migrationController = _BlockingMigrationRunController();
    final sync = _RecordingSyncNotifier();
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap),
        migrationRunControllerProvider.overrideWith(() => migrationController),
        syncProvider.overrideWith(() => sync),
        activeOrchardMigrationStatusProvider.overrideWith(
          (_) async => _broadcastedStatus(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(accountProvider.future);
    await container.read(syncProvider.future);
    container.read(migrationRunControllerProvider);
    await container.read(activeOrchardMigrationStatusProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (_, child) =>
              AppTheme(data: AppThemeData.light, child: child!),
          home: const Scaffold(body: GlobalMigrationWarningBanner()),
        ),
      ),
    );
    await tester.pump();

    expect(migrationController.broadcastCount, 0);
    expect(sync.forcedSyncCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('does not read providers after disposal during a broadcast', (
    tester,
  ) async {
    final migrationController = _BlockingMigrationRunController();
    final sync = _RecordingSyncNotifier();
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap),
        migrationRunControllerProvider.overrideWith(() => migrationController),
        syncProvider.overrideWith(() => sync),
        activeOrchardMigrationStatusProvider.overrideWith(
          (_) async => _dueBroadcastStatus(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final messages = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) messages.add(message);
    };

    try {
      await container.read(accountProvider.future);
      await container.read(syncProvider.future);
      container.read(migrationRunControllerProvider);
      await container.read(activeOrchardMigrationStatusProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (_, child) =>
                AppTheme(data: AppThemeData.light, child: child!),
            home: const Scaffold(body: GlobalMigrationWarningBanner()),
          ),
        ),
      );
      await tester.pump();
      expect(migrationController.broadcastCount, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      migrationController.completeBroadcast();
      await tester.pump();
      await tester.pump();

      expect(sync.forcedSyncCount, 0);
      expect(
        messages.where(
          (message) => message.contains('migration activity tick failed'),
        ),
        isEmpty,
      );
    } finally {
      debugPrint = previousDebugPrint;
    }
  });
}

class _BlockingMigrationRunController extends MigrationRunController {
  final Completer<void> _broadcastCompleter = Completer<void>();
  bool _broadcastInFlight = false;
  int broadcastCount = 0;

  @override
  MigrationRunState build() => const MigrationRunState();

  @override
  Future<void> broadcastDueScheduled() {
    broadcastCount += 1;
    if (_broadcastInFlight) return Future<void>.value();
    _broadcastInFlight = true;
    return _broadcastCompleter.future.whenComplete(() {
      _broadcastInFlight = false;
    });
  }

  void completeBroadcast() => _broadcastCompleter.complete();
}

class _RecordingSyncNotifier extends SyncNotifier {
  int forcedSyncCount = 0;

  @override
  Future<SyncState> build() async => SyncState(accountUuid: 'account-1');

  @override
  Future<void> startSyncAnyway() async {
    forcedSyncCount += 1;
  }
}

rust_sync.MigrationStatus _dueBroadcastStatus() {
  return rust_sync.MigrationStatus(
    phase: 'broadcast_scheduled',
    activeRunId: 'run-1',
    targetValuesZatoshi: Uint64List(0),
    preparedNoteCount: 0,
    denominationConfirmationCount: 3,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 3,
    denominationSplitTotalCount: 3,
    pendingTxCount: 1,
    broadcastedTxCount: 0,
    confirmedTxCount: 2,
    totalCount: 30,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 8,
    broadcastWindowSeconds: BigInt.from(180),
    maxPreparedNotesPerRun: 64,
    scheduledBroadcasts: [
      rust_sync.MigrationScheduledBroadcast(
        txidHex:
            '0000000000000000000000000000000000000000000000000000000000000001',
        scheduledAtMs: DateTime.now()
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        status: 'scheduled',
      ),
    ],
  );
}

rust_sync.MigrationStatus _broadcastedStatus() {
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
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 8,
    broadcastWindowSeconds: BigInt.from(180),
    maxPreparedNotesPerRun: 64,
    scheduledBroadcasts: const [
      rust_sync.MigrationScheduledBroadcast(
        txidHex:
            '0000000000000000000000000000000000000000000000000000000000000001',
        scheduledAtMs: 1,
        status: 'broadcasted',
      ),
    ],
  );
}

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
