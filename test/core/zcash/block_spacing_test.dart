import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/zcash/block_spacing.dart';
import 'package:zcash_wallet/src/features/migration/models/ironwood_migration_phases.dart';

void main() {
  const spacing = BlockSpacing(
    nu7ActivationHeight: 1_010,
    preNu7BlockSeconds: 75,
    nu7BlockSeconds: 25,
  );

  test('estimates every span at the NU7 spacing', () {
    expect(spacing.secondsBetween(1_000, 1_020), 20 * 25);
    expect(spacing.secondsBetween(1_020, 1_000), 0);
    expect(BlockSpacing.nu7Unscheduled.secondsBetween(1_000, 1_020), 20 * 25);
  });

  test('measures block counts from the chain tip', () {
    expect(spacing.fromTip(1_000).secondsForBlocks(20), 20 * 25);
    expect(spacing.fromTip(1_000).secondsPerBlock, 25);
    // A tip that is still unknown reads no differently.
    expect(spacing.fromTip(0).secondsForBlocks(4), 4 * 25);
    expect(BlockTimeEstimate.nu7Unscheduled.secondsForBlocks(4), 4 * 25);
  });

  test('scales 75-second reference blocks from NU7 activation', () {
    expect(spacing.blocksPerReferenceBlock(1_009), 1);
    expect(spacing.blocksPerReferenceBlock(1_010), 3);
    expect(BlockSpacing.nu7Unscheduled.blocksPerReferenceBlock(1_010), 1);
    // The two-hour late grace stays two hours either side of activation.
    expect(ironwoodMigrationLateHeight(900, spacing), 900 + 96);
    expect(ironwoodMigrationLateHeight(1_010, spacing), 1_010 + 288);
  });
}
