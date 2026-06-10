import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_step_state.dart';
import 'package:zcash_wallet/src/features/migration/providers/migration_run_controller.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

rust_sync.IronwoodMigrationResult _result(
  String status, {
  int broadcastedCount = 0,
  String? message,
}) {
  return rust_sync.IronwoodMigrationResult(
    txids: '',
    status: status,
    broadcastedCount: broadcastedCount,
    totalCount: 8,
    message: message,
    feeZatoshi: BigInt.zero,
    migratedZatoshi: BigInt.zero,
  );
}

void main() {
  test('stage outcomes that advanced the run count as success', () {
    expect(migrationRunAdvanced(_result('broadcasted')), isTrue);
    expect(
      migrationRunAdvanced(
        _result('waiting_denom_confirmations', message: 'sync more'),
      ),
      isTrue,
    );
    expect(
      migrationRunAdvanced(_result('waiting_migration_confirmations')),
      isTrue,
    );
    expect(
      migrationRunAdvanced(_result('partial_broadcast', broadcastedCount: 2)),
      isTrue,
    );
  });

  test('failures and empty partial broadcasts are not success', () {
    expect(migrationRunAdvanced(_result('failed_recoverable')), isFalse);
    expect(migrationRunAdvanced(_result('pending_broadcast')), isFalse);
    expect(
      migrationRunAdvanced(
        _result('partial_broadcast', broadcastedCount: 2, message: 'lwd down'),
      ),
      isFalse,
    );
    expect(
      migrationRunAdvanced(_result('partial_broadcast', broadcastedCount: 0)),
      isFalse,
    );
  });

  test('run state defaults are inert', () {
    const state = MigrationRunState();
    expect(state.intent, MigrationRunIntent.none);
    expect(state.inFlight, isFalse);
    expect(state.error, isNull);
    expect(state.errorIntent, isNull);
  });
}
