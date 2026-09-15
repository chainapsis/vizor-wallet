import '../../src/core/storage/app_secure_store.dart';
import '../../src/features/migration/services/ironwood_migration_service.dart';
import '../../src/rust/api/sync.dart' as rust_sync;

/// Static migration galleries never prepare or submit real transactions.
class WbMigrationService extends IronwoodMigrationService {
  WbMigrationService()
    : super(
        getWalletDbPath: () async =>
            throw StateError('Migration is preview-only.'),
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                throw StateError('Migration is preview-only.'),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.instance,
      );

  @override
  Future<rust_sync.IronwoodMigrationResult> startSoftwareImmediateMigration({
    required String accountUuid,
    required rust_sync.OrchardMigrationImmediatePlan approvedPlan,
  }) async => throw StateError('Migration is preview-only.');

  @override
  Future<void> discardKeystonePrivateMigrationRequest({
    required String accountUuid,
    required String requestId,
  }) async {}
}
