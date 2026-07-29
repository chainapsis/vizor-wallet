# Migration local simulation

This directory runs the real macOS app against the repository's local
Ironwood-enabled `zcashd` and `lightwalletd`. It is intended for observing
migration timing and state transitions without depending on public testnet
miners.

The scenario implementation lives here. A two-line adapter under
`integration_test/` is required so Flutter packages the macOS app and its Rust
framework instead of treating the scenario as a host-only Dart test.

## Full migration scenario

```bash
migration_sim_test/run_full_migration.sh
```

The scenario:

1. resets and starts the local regtest Docker stack;
2. funds the deterministic software wallet with `99.0002 TAZ` split across 20
   Orchard notes and four differently sized funding transactions;
3. activates NU6.3 at height 500;
4. launches the real macOS Flutter app with
   `ZCASH_FAST_TESTNET_MIGRATION=true`;
5. starts a private migration through the desktop UI;
6. mines preparation and confirmation blocks at a three-second cadence,
   waiting for the wallet to synchronize after each batch, while skipping
   empty ranges up to the next scheduled action;
7. follows every denomination stage and scheduled Orchard-to-Ironwood
   transfer;
8. succeeds only after every transfer reaches the wallet's trusted
   confirmation depth and the final Orchard/Ironwood balances match the plan;
9. opens Activity, verifies the private migration transfers are visible, and
   leaves the normal, fully-live app window visible for 15 seconds.

The fast flag deliberately maps regtest to the fast-testnet timing policy for
this opt-in build: preparation delay mean/max `4/16` blocks, transfer delay
mean/max `12/48` blocks, and a 12-block anchor bucket. Regtest without the flag
retains its original `1/4`-block E2E timing.

At the default three-second cadence, the full run takes several minutes,
depending on the randomly sampled preparation and transfer heights and local
proof-generation time. The wallet's trusted confirmation target is read from
the status API rather than hard-coded by the test.

Useful overrides:

```bash
E2E_MIGRATION_SIM_BLOCK_INTERVAL_MS=10000 \
E2E_MIGRATION_SIM_MAX_BLOCKS=200 \
migration_sim_test/run_full_migration.sh
```

The balance and input shape can also be overridden together:

```bash
E2E_ORCHARD_FUNDING_AMOUNT=50.0002 \
E2E_ORCHARD_FUNDING_ZATOSHI=5000020000 \
E2E_ORCHARD_FUNDING_NOTE_COUNT=20 \
E2E_ORCHARD_FUNDING_TX_COUNT=4 \
migration_sim_test/run_full_migration.sh
```

The app window is visible by default so the migration can be observed. Set
`VIZOR_E2E_HIDDEN_WINDOW=true` for an unattended hidden-window run.
Unlike deterministic integration tests, this observable scenario uses
Flutter's fully-live frame policy so animations and app-requested frames render
at the normal application cadence.
After completion, the scenario opens Activity and keeps the window open for
15 seconds. Override this with
`E2E_MIGRATION_SIM_HOME_HOLD_MS=30000`, for example.

The local HTTP driver serializes all chain-mutating requests. Concurrent
`/mine`, activation, reorg, and node lifecycle requests wait their turn, so a
later request cannot advance the tip while an earlier request is waiting for
lightwalletd to observe its result.

## Virtual unlock full migration scenario

```bash
migration_sim_test/run_virtual_unlock_full_migration.sh
```

This runs the same full many-note migration with the debug-only
`VIZOR_IRONWOOD_MIGRATION_PRIVACY_LOCK=true` define. It verifies that the
virtual unlock does not appear after more than one idle minute without an
active migration, appears after one idle minute during migration, rejects an
incorrect password, and continues blocking interaction while the migration
advances to completion. At completion the progress badge must disappear while
the unlock screen remains, and only the correct wallet password may dismiss
it.

Artifacts use the
`migration_sim_test/artifacts/virtual-unlock-full-<timestamp>*` prefix. The
window is hidden by default; set `VIZOR_E2E_HIDDEN_WINDOW=false` to observe the
run.

If Rust migration sources changed after a macOS app was already built, run
`fvm flutter clean` once before the scenario. This prevents Xcode from reusing
an older embedded Rust framework.

The runner resets the local chain and the regtest wallet state. It does not
delete mainnet or testnet wallet database files, but it uses the same macOS app
container and should not run alongside another Vizor process.

## Inspecting the chain and wallet DB

The integration test prints its exact database path. Pass it to:

```bash
migration_sim_test/inspect.sh "/absolute/path/to/zcash_wallet_....db"
migration_sim_test/watch.sh "/absolute/path/to/zcash_wallet_....db"
```

Without an argument, `inspect.sh` selects the most recently modified Vizor
wallet DB. It reports:

- zcashd and lightwalletd heights;
- mempool txids;
- wallet scanned height and migration phase;
- persisted timing policies and last error;
- denomination stage schedule, txid, fee and mined height;
- prepared-note and signed-child counts;
- scheduled, broadcasted and confirmed migration transactions.

The run table's persisted `phase` can lag the status API's computed phase until
the next advance call. Use the denomination and pending-transaction rows when
debugging individual steps; the console test only succeeds after the status
API reports full completion and final balances match the approved plan.

For Rust logs:

```bash
migration_sim_test/logs.sh follow
migration_sim_test/logs.sh recent
```

Important messages include `resubmit:`, `sync:`, denomination state changes,
DB lock durations, gRPC failures and migration errors.

## Artifacts

Every run writes ignored artifacts under `migration_sim_test/artifacts/`:

- Flutter/integration-test console log;
- local chain-driver log;
- filtered macOS Rust log;
- SQLite backup of the completed wallet;
- final human-readable DB/chain snapshot.

The success marker in the console log is:

```text
migration-sim FULL_MIGRATION_COMPLETE
```

## Full migration with the live schedule open

```bash
migration_sim_test/run_schedule_migration.sh
```

This separate visible scenario uses the same funded wallet, private migration
plan, block cadence, final balance checks, and Activity verification as the
full migration scenario. After denomination preparation finishes, it opens
**View Schedule** and keeps that screen open while every scheduled transfer is
broadcast and confirmed. It verifies that:

- the schedule contains one keyed row for every real migration part;
- every persisted part remains represented while its state changes;
- no schedule loading/error surface replaces the live run;
- all rows reach `Completed`;
- the schedule back action returns to the migration completion screen.

Artifacts use the `migration_sim_test/artifacts/schedule-<timestamp>*` prefix.
The schedule-specific success markers are:

```text
migration-sim-schedule SCHEDULE_OPENED
migration-sim-schedule SCHEDULE_COMPLETED_AND_RETURNED
```

## Immediate migration scenario

```bash
migration_sim_test/run_immediate_migration.sh
```

This uses the same visible macOS app, local Ironwood chain, `99.0002 TAZ`
balance, and 20-note/four-funding-transaction shape as the full scenario.
Instead of preparing denominations and following a private schedule, it:

1. selects **Immediate** in the desktop migration UI;
2. validates that the reviewed plan consumes all 20 Orchard notes in one
   transaction and that `input - fee = migrated`;
3. leaves the review screen visible for five seconds;
4. authorizes the software-wallet transaction and verifies exactly one
   transaction reaches the local mempool;
5. mines ten confirmations at a three-second visible cadence;
6. verifies Orchard is empty and the exact planned amount is available in
   Ironwood;
7. opens Activity, verifies the migration entry is visible, and leaves that
   screen visible for 15 seconds.

Useful timing overrides:

```bash
E2E_MIGRATION_SIM_REVIEW_HOLD_MS=10000 \
E2E_MIGRATION_SIM_BLOCK_INTERVAL_MS=5000 \
E2E_MIGRATION_SIM_HOME_HOLD_MS=30000 \
migration_sim_test/run_immediate_migration.sh
```

Artifacts use the `migration_sim_test/artifacts/immediate-<timestamp>*`
prefix. The success marker is:

```text
migration-sim-immediate IMMEDIATE_MIGRATION_COMPLETE
```
