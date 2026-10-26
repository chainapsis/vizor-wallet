import 'dart:math' as math;

/// Target block spacing on one network, split at NU7 activation (ZIP 218).
class BlockSpacing {
  const BlockSpacing({
    required this.preNu7BlockSeconds,
    required this.nu7BlockSeconds,
    this.nu7ActivationHeight,
  });

  /// 75-second blocks with no scheduled upgrade, for previews and tests.
  static const preNu7 = BlockSpacing(
    preNu7BlockSeconds: 75,
    nu7BlockSeconds: 25,
  );

  final int? nu7ActivationHeight;
  final int preNu7BlockSeconds;
  final int nu7BlockSeconds;

  /// Estimates the blocks after [fromHeight] up to and including [toHeight].
  int secondsBetween(int fromHeight, int toHeight) {
    if (toHeight <= fromHeight) return 0;
    final blocks = toHeight - fromHeight;
    final activation = nu7ActivationHeight;
    final preNu7Blocks = activation == null
        ? blocks
        : (math.min(toHeight, activation - 1) - fromHeight).clamp(0, blocks);
    return preNu7Blocks * preNu7BlockSeconds +
        (blocks - preNu7Blocks) * nu7BlockSeconds;
  }

  /// Blocks that one ZIP 318 reference block, a 75-second block, spans at
  /// [height]: 1 before NU7 activation and 3 from it.
  int blocksPerReferenceBlock(int height) {
    final activation = nu7ActivationHeight;
    return activation != null && height >= activation
        ? preNu7BlockSeconds ~/ nu7BlockSeconds
        : 1;
  }

  /// Estimates measured from the chain tip at [tipHeight] (0 when unknown).
  BlockTimeEstimate fromTip(int tipHeight) =>
      BlockTimeEstimate(spacing: this, tipHeight: tipHeight);
}

/// Block-count time estimates measured from a known chain tip.
class BlockTimeEstimate {
  const BlockTimeEstimate({required this.spacing, required this.tipHeight});

  /// Pre-NU7 spacing from an unknown tip, for previews and tests.
  static const preNu7 = BlockTimeEstimate(
    spacing: BlockSpacing.preNu7,
    tipHeight: 0,
  );

  final BlockSpacing spacing;
  final int tipHeight;

  /// Seconds until the next [blocks] blocks after the tip are mined.
  int secondsForBlocks(int blocks) =>
      spacing.secondsBetween(tipHeight, tipHeight + blocks);

  /// Seconds from [fromHeight] to [toHeight].
  int secondsBetween(int fromHeight, int toHeight) =>
      spacing.secondsBetween(fromHeight, toHeight);

  /// Target spacing of the next block after the tip.
  int get secondsPerBlock => secondsForBlocks(1);
}
