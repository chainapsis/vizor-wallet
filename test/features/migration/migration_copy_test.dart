import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/migration_copy.dart';

void main() {
  test('migration window text reads naturally at common windows', () {
    expect(MigrationCopy.migrationWindowText(60), 'about one minute');
    expect(MigrationCopy.migrationWindowText(45), 'about 45 seconds');
    expect(MigrationCopy.migrationWindowText(180), 'about 3 minutes');
  });

  test('split progress uses natural singular and plural copy', () {
    expect(
      MigrationCopy.splitTransactionsPrepared(1),
      '1 split transaction prepared',
    );
    expect(
      MigrationCopy.splitTransactionsPrepared(3),
      '3 split transactions prepared',
    );
    expect(MigrationCopy.confirmTitle(0), 'Confirm split');
    expect(MigrationCopy.confirmTitle(1), 'Confirm split');
    expect(MigrationCopy.confirmTitle(3), 'Confirm splits');
    expect(MigrationCopy.splitProgress(0, 0), 'No splits needed');
    expect(
      MigrationCopy.splitProgress(0, 1),
      '0 of 1 split complete · 1 split remaining',
    );
    expect(
      MigrationCopy.splitProgress(1, 3),
      '1 of 3 splits complete · 2 splits remaining',
    );
    expect(MigrationCopy.splitProgress(3, 3), '3 of 3 splits complete');
    expect(MigrationCopy.confirmDone(0, 0), 'Confirmed');
  });

  test('current confirmation round copy includes its depth', () {
    expect(
      MigrationCopy.currentSplitConfirmations(1, 3),
      'Current confirmation round · 1 of 3 confirmations',
    );
    expect(
      MigrationCopy.currentSplitConfirmations(1, 1),
      'Current confirmation round · 1 of 1 confirmation',
    );
  });
}
