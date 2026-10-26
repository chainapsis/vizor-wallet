# Network upgrades

Common schedules each upgrade's activation height. NU7 also changes the block
spacing, which only NU7 code handles.

## NU7 block spacing

Block spacing drops from 75 to 25 seconds at NU7. Every estimate splits each
span at activation:

- `block_times.rs` for birthday and date conversion. The mainnet table updater
  accepts 25-second averages, so it keeps running after activation.
- `BlockSpacing` and `blockSpacingProvider` in Dart for wait-time text. They
  read `get_block_spacing_schedule`, which takes the 25-second value from
  Common's spacing ratio.

If the schedule cannot be read, Dart falls back to 75-second spacing, which
only affects estimates.

## When the next upgrade is scheduled

- **Block spacing.** If it changes again, update `block_times.rs` and Dart
  `BlockSpacing`.
