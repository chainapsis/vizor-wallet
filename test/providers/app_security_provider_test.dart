import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/features/migration/models/ironwood_migration_phases.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'password preflight checks current DB accounts even when bootstrap has no wallet',
    () async {
      var listedAccounts = false;
      var checkedStatus = false;

      Future<List<rust_wallet.AccountInfo>> listAccounts({
        required String dbPath,
        required String network,
      }) async {
        listedAccounts = true;
        expect(dbPath, '/tmp/wallet.db');
        expect(network, 'main');
        return const [
          rust_wallet.AccountInfo(
            uuid: 'account-1',
            name: 'Account 1',
            unifiedAddress: 'u1test',
            isSeedAnchor: true,
            isHardware: false,
          ),
        ];
      }

      Future<rust_sync.MigrationStatus> getStatus({
        required String dbPath,
        required String network,
        required String accountUuid,
      }) async {
        checkedStatus = true;
        expect(dbPath, '/tmp/wallet.db');
        expect(network, 'main');
        expect(accountUuid, 'account-1');
        return _migrationStatus(phase: kIronwoodMigrationReadyToMigratePhase);
      }

      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          passwordChangeWalletDbPathProvider.overrideWithValue(
            () async => '/tmp/wallet.db',
          ),
          passwordChangeAccountListerProvider.overrideWithValue(listAccounts),
          passwordChangeMigrationStatusProvider.overrideWithValue(getStatus),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(passwordChangePreflightProvider)(),
        throwsA(isA<IronwoodMigrationPasswordChangeBlockedException>()),
      );
      expect(listedAccounts, isTrue);
      expect(checkedStatus, isTrue);
    },
  );
}

rust_sync.MigrationStatus _migrationStatus({required String phase}) {
  return rust_sync.MigrationStatus(
    phase: phase,
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
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    maxPreparedNotesPerRun: 64,
    scheduledBroadcasts: const [],
    parts: const [],
  );
}
