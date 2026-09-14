# Desktop migration scheduling

Read when changing wallet-open epochs, overdue-transfer fallback, sleep/lock timing, or visibility-driven scheduling.

## Desktop wallet-open epoch

- `DesktopOpenMigrationFallbackGate` allows one wallet-global fallback for
  transfers overdue at epoch entry. It requires an authoritative entry height
  and freezes each account's first successful status snapshot. Missing either
  blocks only that account's scheduled transfers.

- Epochs follow process activity. Hidden/minimized windows keep polling, and
  newly due transfers remain ordinary scheduled work. Suspension or wallet reset
  re-arms the allowance and requires fresh entry-height/account snapshots;
  window visibility alone does neither.

- Activity and lock observers use `kDesktopMigrationEpochSuspensionGap` (three
  minutes). Wall-minus-monotonic time detects macOS/Linux sleep, even mid-sweep;
  their idle-gap check excludes awake sweep duration. Windows counts monotonic
  gaps at every observation because its clock advances through sleep, accepting
  that long sweeps can also restart the epoch.

- Separate lock timing prevents a finishing sweep from erasing an overlapping
  lock gap. Unlock after the threshold restarts the epoch before queuing refresh.

## Verification anchors

- Desktop allowance, per-account snapshots, and acceptance:
  [`desktop_open_migration_fallback_gate_test.dart`](../../../../test/features/migration/desktop_open_migration_fallback_gate_test.dart).

- Visibility, sleep during/between sweeps, Windows clock behavior, and locks
  overlapping active sweeps:
  [`desktop_migration_epoch_coordinator_test.dart`](../../../../test/features/migration/desktop_migration_epoch_coordinator_test.dart).

## Related changes

- When changing durable run progression or per-account permits, read [migration lifecycle](run-lifecycle.md).
