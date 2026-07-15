import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_service.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'status resolves wallet db path before calling Rust status API',
    () async {
      String? seenDbPath;
      String? seenNetwork;
      String? seenAccountUuid;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          seenDbPath = dbPath;
          seenNetwork = network;
          seenAccountUuid = accountUuid;
          return Future.value(_migrationStatus());
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(null);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
      );

      await service.status(network: 'test', accountUuid: 'account-1');

      expect(seenDbPath, '/tmp/wallet.db');
      expect(seenNetwork, 'test');
      expect(seenAccountUuid, 'account-1');
    },
  );

  test(
    'privatePlan resolves wallet db path before calling Rust plan API',
    () async {
      String? seenDbPath;
      String? seenNetwork;
      String? seenAccountUuid;
      final expected = rust_sync.OrchardMigrationPrivatePlan(
        targetValuesZatoshi: frb.Uint64List.fromList([100000000]),
        totalInputZatoshi: BigInt.from(100020000),
        totalMigratableZatoshi: BigInt.from(100000000),
        denominationSplitFeeZatoshi: BigInt.from(10000),
        migrationFeeZatoshi: BigInt.from(10000),
        estimatedTotalFeeZatoshi: BigInt.from(20000),
        plannedBatchCount: 1,
        denominationSplitStageCount: 1,
        signingBatchLimit: 50,
        broadcastWindowSeconds: BigInt.from(180),
        maxPreparedNotesPerRun: 64,
      );
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(_migrationStatus());
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              seenDbPath = dbPath;
              seenNetwork = network;
              seenAccountUuid = accountUuid;
              return Future.value(expected);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
      );

      final plan = await service.privatePlan(
        network: 'test',
        accountUuid: 'account-1',
      );

      expect(plan, expected);
      expect(seenDbPath, '/tmp/wallet.db');
      expect(seenNetwork, 'test');
      expect(seenAccountUuid, 'account-1');
    },
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
