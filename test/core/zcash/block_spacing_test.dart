import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/zcash/block_spacing.dart';

void main() {
  const spacing = BlockSpacing(
    nu7ActivationHeight: 1_010,
    preNu7BlockSeconds: 75,
    nu7BlockSeconds: 25,
  );

  test('uses one spacing when no upgrade is scheduled', () {
    expect(BlockSpacing.preNu7.secondsBetween(1_000, 1_020), 20 * 75);
    expect(BlockSpacing.preNu7.secondsBetween(1_020, 1_000), 0);
  });

  test('splits a span at the NU7 activation height', () {
    // Blocks 1_001..1_009 keep 75 seconds; 1_010..1_020 use 25.
    expect(spacing.secondsBetween(1_000, 1_020), 9 * 75 + 11 * 25);
    expect(spacing.secondsBetween(900, 1_000), 100 * 75);
    expect(spacing.secondsBetween(1_010, 1_030), 20 * 25);
  });

  test('measures block counts from the chain tip', () {
    expect(spacing.fromTip(1_000).secondsForBlocks(20), 9 * 75 + 11 * 25);
    expect(spacing.fromTip(1_000).secondsPerBlock, 75);
    expect(spacing.fromTip(1_009).secondsPerBlock, 25);
    expect(BlockTimeEstimate.preNu7.secondsForBlocks(4), 4 * 75);
  });

  test('scales 75-second reference blocks from NU7 activation', () {
    expect(spacing.blocksPerReferenceBlock(1_009), 1);
    expect(spacing.blocksPerReferenceBlock(1_010), 3);
    expect(BlockSpacing.preNu7.blocksPerReferenceBlock(1_010), 1);
  });
}
