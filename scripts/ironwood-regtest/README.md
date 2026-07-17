# Ironwood migration regtest

This stack exercises the real Orchard-to-Ironwood transaction path against a
local chain. It starts with Orchard active and NU6.3 inactive, funds arbitrary
regtest unified addresses in Orchard, and activates NU6.3 only when the test
mines the configured activation block.

## Pinned components

- zcashd: Shielded Labs Zero v15, pinned by OCI digest. Upstream zcashd releases
  currently stop at NU6.2 and cannot validate Ironwood transactions.
- lightwalletd: `zcash/lightwalletd` Ironwood PR 567, pinned to commit
  `54c6277ad0fce0a8bbed598c207b2ed1caf58d11`.
- NU6.3 consensus branch: `37a5165b`.

The default activation height is 500. Override it consistently with
`IRONWOOD_ACTIVATION_HEIGHT`; values below 150 are rejected so the faucet can
mature coinbase funds while the chain is still pre-Ironwood. The first `up.sh`
pins the chosen height into the chain state. Changing it for an existing chain
is rejected; reset or restore a checkpoint created with the desired height.

## Full migration E2E

Run the real Flutter desktop app on macOS:

```bash
scripts/e2e/flutter-macos-ironwood-migration.sh
```

This runner resets the chain, derives and funds the deterministic E2E wallet,
starts a small local chain-control driver, and launches the Flutter integration
test on the macOS device. It verifies all of the following through the app UI:

- migration UI stays hidden before activation;
- live NU6.3 activation is detected without restarting the app;
- the announcement can be dismissed and the home CTA still starts migration;
- unavailable migration options cannot continue;
- denomination preparation broadcasts a real Orchard transaction;
- locking and unlocking preserves and resumes the active migration run;
- confirmed denominations advance to the scheduled Ironwood broadcast;
- confirmation completes the run, creates spendable Ironwood funds, and removes
  the home migration CTA.

Test recovery across a real Flutter process restart and a lightwalletd outage:

```bash
scripts/e2e/flutter-macos-ironwood-migration-restart.sh
```

The first app process activates Ironwood, stops lightwalletd immediately before
authorization, and persists an active run with an encrypted denomination
transaction that could not be broadcast. A second app process starts from the
same wallet database, unlocks the wallet, restarts lightwalletd, rebroadcasts
the pending transaction through the normal migration status flow, and completes
the migration.

Test migration isolation between two accounts in the same wallet database:

```bash
scripts/e2e/flutter-macos-ironwood-migration-multi-account.sh
```

This scenario imports two software accounts, funds only the first account,
starts its migration, and switches accounts while the run is active. It verifies
that the unfunded account has no migration CTA or active run, then returns to the
funded account, resumes the same run, and checks the final balances of both
accounts independently.

Test both denomination and final Ironwood transaction reorg recovery:

```bash
scripts/e2e/flutter-macos-ironwood-migration-reorg.sh
```

The runner replaces the chain after denomination confirmation and verifies that
the same migration run returns to denomination preparation, then rebuilds its
Ironwood child. It mines that child below trusted depth, replaces the chain
again, verifies the child becomes broadcastable, and completes the original run.
The reusable `reorg.sh` primitive holds transactions displaced by the old chain
out of replacement blocks until `release-reorg-transactions.sh` is called.

Test a large balance that requires multiple denomination stages and migration
transactions:

```bash
scripts/e2e/flutter-macos-ironwood-migration-large-balance.sh
```

This funds the deterministic wallet with 99.0002 ZEC, verifies the exact
two-stage padded denomination plan and 18 migration batches, observes partial
split and transfer progress, and checks the exact ZIP 317 fee delta after all
transactions confirm. The base runner accepts `E2E_ORCHARD_FUNDING_AMOUNT`,
`E2E_ORCHARD_PREFUND_BLOCKS`, and `E2E_ORCHARD_FUNDING_COINBASE_LIMIT` so other
large-balance scenarios can reuse the same setup.

Test a wallet with many independent Orchard notes:

```bash
scripts/e2e/flutter-macos-ironwood-migration-many-notes.sh
```

This creates 20 Orchard notes whose values sum to 10.0002 ZEC, verifies that
the wallet scans the full balance, and checks the exact two-stage denomination
chain, migration batches, fees, and final pool balances. Set
`E2E_ORCHARD_FUNDING_NOTE_COUNT` on the base runner to reuse this multi-note
funding path with another scenario.

Test uneven Orchard notes received across multiple transactions:

```bash
scripts/e2e/flutter-macos-ironwood-migration-mixed-notes.sh
```

This spreads 20 notes across four funding transactions with transaction totals
weighted 1:2:3:4. It verifies all four receive transactions, distinct txids and
amounts, the chained denomination plan, migration fees, and final balances. Set
`E2E_ORCHARD_FUNDING_TX_COUNT` to partition another scenario's addresses and
total amount across multiple weighted funding transactions.

The base runner accepts `E2E_TEST_FILE` and `E2E_DRIVER_PORT` overrides so new
single-process scenarios can reuse chain reset, deterministic Orchard funding,
driver startup, and Flutter launch without duplicating the harness.

Run the lower-level Rust migration path independently:

```bash
scripts/e2e/ironwood-regtest-migration.sh
```

The test imports a deterministic wallet, sends 1.0002 TAZ to its Orchard
receiver, verifies that Ironwood is empty, activates NU6.3, runs the real
migration pipeline, confirms both transaction stages, and verifies spendable
Ironwood balance and a completed migration record.

## Reusable scenario commands

```bash
scripts/ironwood-regtest/reset.sh
scripts/ironwood-regtest/up.sh

# Derive an address with the existing helper, then fund it before activation.
cd rust
cargo run --quiet --example regtest_wallet_addresses -- "<mnemonic>"
cd ..
scripts/ironwood-regtest/fund-orchard.sh "<uregtest-address>" 1.0002 10 1 1

scripts/ironwood-regtest/status.sh
scripts/ironwood-regtest/checkpoint.sh save orchard-funded
scripts/ironwood-regtest/activate-ironwood.sh
scripts/ironwood-regtest/checkpoint.sh restore orchard-funded
scripts/ironwood-regtest/up.sh

# Replace the chain after a fork height while holding displaced transactions.
scripts/ironwood-regtest/reorg.sh 500
scripts/ironwood-regtest/release-reorg-transactions.sh "<txid>"
```

`mine.sh`, `rpc.sh`, `status.sh`, and named checkpoints are intentionally
independent building blocks for additional account, reorg, interrupted
migration, hardware-wallet, and retry scenarios.

## Flutter E2E configuration

The wallet must use the same activation height as zcashd:

```bash
fvm flutter test integration_test/<test>.dart -d macos \
  --dart-define=ZCASH_DEFAULT_NETWORK=regtest \
  --dart-define=ZCASH_REGTEST_IRONWOOD_ACTIVATION_HEIGHT=500 \
  --dart-define=ZCASH_E2E_LIGHTWALLETD_URL=http://127.0.0.1:19067
```

Normal builds omit the new define and retain the existing regtest behavior
(all upgrades active at height 1). The Ironwood stack defaults to host ports
`19232` (zcashd RPC) and `19067` (lightwalletd), so it can run alongside the
legacy regtest stack. Override them with `IRONWOOD_ZCASHD_RPC_PORT` and
`IRONWOOD_LIGHTWALLETD_PORT` when a scenario needs different ports.
