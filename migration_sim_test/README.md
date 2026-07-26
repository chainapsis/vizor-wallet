# Migration local simulation

This directory runs the real macOS app against the repository's local
Ironwood-enabled `zcashd` and `lightwalletd`. It is intended for observing
migration timing and state transitions without depending on public testnet
miners.

The scenario implementation lives here. A two-line adapter under
`integration_test/` is required so Flutter packages the macOS app and its Rust
framework instead of treating the scenario as a host-only Dart test.

## Prepare / note-split scenario

```bash
migration_sim_test/run_prepare_note_split.sh
```

The scenario:

1. resets and starts the local regtest Docker stack;
2. funds the deterministic software wallet with `12.82182 TAZ` in one Orchard
   note, producing the same six migration denominations used in the manual
   testnet investigation;
3. activates NU6.3 at height 500;
4. launches the real macOS Flutter app with
   `ZCASH_FAST_TESTNET_MIGRATION=true`;
5. starts a private migration through the desktop UI;
6. mines one block every six seconds, waiting for the wallet to synchronize
   after each block;
7. succeeds only after the denomination transaction is mined and reaches the
   wallet's trusted confirmation depth.

The fast flag deliberately maps regtest to the fast-testnet timing policy for
this opt-in build: preparation delay mean/max `4/16` blocks, transfer delay
mean/max `12/48` blocks, and a 12-block anchor bucket. Regtest without the flag
retains its original `1/4`-block E2E timing.

At the default six-second cadence, one preparation stage normally takes tens
of seconds to roughly two minutes after proving, depending on its sampled
delay. The wallet's trusted confirmation target is currently three blocks and
is read from the status API rather than hard-coded by the test.

Useful overrides:

```bash
E2E_MIGRATION_SIM_BLOCK_INTERVAL_MS=10000 \
E2E_MIGRATION_SIM_MAX_BLOCKS=50 \
migration_sim_test/run_prepare_note_split.sh
```

The app window is hidden by default. Set
`VIZOR_E2E_HIDDEN_WINDOW=false` when UI interaction needs to be visible.

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
- prepared-note and signed-child counts.

The run table's persisted `phase` can lag the status API's computed phase until
the next advance call. For preparation completion, use the denomination
stage's `confirmed` status together with the prepared-note count; the console
test also requires the status API to reach its trusted confirmation target.

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
migration-sim PREPARE_COMPLETE
```

The test intentionally stops after note preparation is confirmed. It does not
advance or broadcast the Orchard-to-Ironwood child schedule.
