import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_view_state.dart';

void main() {
  test('hardware account shows softwareRequired', () {
    expect(
      migrationViewState(
        isHardware: true,
        hasPendingMigration: true,
        hasCompletedMigration: false,
        orchardBalance: BigInt.from(1),
        ironwoodBalance: BigInt.zero,
      ),
      MigrationViewState.softwareRequired,
    );
  });

  test('software account with no migration shows idle', () {
    expect(
      migrationViewState(
        isHardware: false,
        hasPendingMigration: false,
        hasCompletedMigration: false,
        orchardBalance: BigInt.from(1),
        ironwoodBalance: BigInt.zero,
      ),
      MigrationViewState.idle,
    );
  });

  test('software account with a pending migration shows inProgress', () {
    expect(
      migrationViewState(
        isHardware: false,
        hasPendingMigration: true,
        hasCompletedMigration: false,
        orchardBalance: BigInt.zero,
        ironwoodBalance: BigInt.zero,
      ),
      MigrationViewState.inProgress,
    );
  });

  test('software account with a mined migration shows complete', () {
    expect(
      migrationViewState(
        isHardware: false,
        hasPendingMigration: false,
        hasCompletedMigration: true,
        orchardBalance: BigInt.zero,
        ironwoodBalance: BigInt.from(1),
      ),
      MigrationViewState.complete,
    );
  });

  test('software account with migrated ironwood balance shows complete', () {
    expect(
      migrationViewState(
        isHardware: false,
        hasPendingMigration: false,
        hasCompletedMigration: false,
        orchardBalance: BigInt.zero,
        ironwoodBalance: BigInt.from(1),
      ),
      MigrationViewState.complete,
    );
  });

  test(
    'software account with remaining orchard funds stays idle after completion',
    () {
      expect(
        migrationViewState(
          isHardware: false,
          hasPendingMigration: false,
          hasCompletedMigration: true,
          orchardBalance: BigInt.from(1),
          ironwoodBalance: BigInt.from(1),
        ),
        MigrationViewState.idle,
      );
    },
  );
}
