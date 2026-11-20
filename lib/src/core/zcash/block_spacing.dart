/// Target block spacing on one network. Time estimates use the NU7 spacing
/// (ZIP 218); ZIP 318 reference blocks keep the pre-NU7 one.
class BlockSpacing {
  const BlockSpacing({
    required this.preNu7BlockSeconds,
    required this.nu7BlockSeconds,
    this.nu7ActivationHeight,
  });

  /// No NU7 activation height, as on default regtest, for previews and tests.
  static const nu7Unscheduled = BlockSpacing(
    preNu7BlockSeconds: 75,
    nu7BlockSeconds: 25,
  );

  final int? nu7ActivationHeight;
  final int preNu7BlockSeconds;
  final int nu7BlockSeconds;

  /// Estimates the blocks after [fromHeight] up to and including [toHeight].
  /// Every estimate starts at a tip past mainnet and testnet activation;
  /// default regtest mines its 75-second blocks on demand.
  int secondsBetween(int fromHeight, int toHeight) =>
      toHeight <= fromHeight ? 0 : (toHeight - fromHeight) * nu7BlockSeconds;

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

  /// [BlockSpacing.nu7Unscheduled] from an unknown tip, for previews and tests.
  static const nu7Unscheduled = BlockTimeEstimate(
    spacing: BlockSpacing.nu7Unscheduled,
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
