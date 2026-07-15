import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
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

  test(
    'startSoftwarePrivateMigration reuses pending tx salt and zeroizes mnemonic bytes',
    () async {
      final returnedMnemonicBytes = <Uint8List>[];
      final seenSalts = <String>[];
      final seenMnemonicPayloads = <List<int>>[];
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(_migrationStatus());
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(null);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        getEndpoint: () => const RpcEndpointConfig(
          networkName: 'test',
          lightwalletdUrl: 'https://lwd.example:443',
        ),
        getSessionPassword: () => 'test-password',
        getMnemonicBytesForAccount: (_) async {
          final bytes = Uint8List.fromList([1, 2, 3, 4]);
          returnedMnemonicBytes.add(bytes);
          return bytes;
        },
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
              seenSalts.add(saltBase64);
              seenMnemonicPayloads.add(List<int>.from(mnemonicBytes));
              return Future.value(_migrationResult());
            },
      );

      await service.startSoftwarePrivateMigration(accountUuid: 'account-1');
      await service.startSoftwarePrivateMigration(accountUuid: 'account-1');

      expect(seenSalts, hasLength(2));
      expect(seenSalts[1], seenSalts[0]);
      expect(seenMnemonicPayloads, [
        [1, 2, 3, 4],
        [1, 2, 3, 4],
      ]);
      expect(returnedMnemonicBytes, hasLength(2));
      for (final bytes in returnedMnemonicBytes) {
        expect(bytes, everyElement(0));
      }
    },
  );

  test(
    'startSoftwarePrivateMigration uses macOS stored mnemonic path',
    () async {
      String? seenPassword;
      String? seenSalt;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(_migrationStatus());
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(null);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        getEndpoint: () => const RpcEndpointConfig(
          networkName: 'test',
          lightwalletdUrl: 'https://lwd.example:443',
        ),
        getSessionPassword: () => 'test-password',
        getMnemonicBytesForAccount: (_) =>
            throw StateError('mnemonic bytes should not be read on macOS'),
        isMacOS: () => true,
        startMacosSoftwareMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) {
              seenPassword = password;
              seenSalt = saltBase64;
              return Future.value(_migrationResult());
            },
        startSoftwareMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required mnemonicBytes,
              required password,
              required saltBase64,
            }) => throw StateError('in-memory mnemonic path should not run'),
      );

      await service.startSoftwarePrivateMigration(accountUuid: 'account-1');

      expect(seenPassword, 'test-password');
      expect(seenSalt, isNotEmpty);
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

rust_sync.IronwoodMigrationResult _migrationResult() {
  return rust_sync.IronwoodMigrationResult(
    txids: 'txid',
    status: 'broadcasted',
    broadcastedCount: 1,
    totalCount: 1,
    feeZatoshi: BigInt.from(10_000),
    migratedZatoshi: BigInt.from(100_000_000),
  );
}
