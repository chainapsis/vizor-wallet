# NU7 regtest

A local Zebra 7.0.0 and lightwalletd v0.5.4 chain on which both NU6.3
(Ironwood) and NU7 activate at controlled heights. The Ironwood stack in
`scripts/ironwood-regtest/` runs zcashd, which cannot activate NU7.

```sh
scripts/nu7-regtest/reset.sh
NU7_REGTEST_NU63_HEIGHT=300 NU7_REGTEST_NU7_HEIGHT=600 scripts/nu7-regtest/up.sh
scripts/nu7-regtest/fund.sh <uregtest1 address> 2   # coinbase of 2 blocks
scripts/nu7-regtest/mine.sh 100
scripts/nu7-regtest/status.sh
scripts/nu7-regtest/rpc.sh getrawtransaction '["<txid>", 1]'
scripts/nu7-regtest/down.sh
```

- Heights default to NU6.3 at 300 and NU7 at 600. The first `up.sh` pins them
  in `.nu7-regtest/`; reset before changing them. The stack accepts any NU7
  above NU6.3, but the Rust scenarios need a wider gap and refuse heights they cannot use.
- Funding pays block coinbase to the address with `generatetoaddress`: Orchard
  before NU6.3, Ironwood from it. Coinbase needs 100 confirmations.
- `fund-orchard.py` funds exact Orchard amounts before NU6.3, one note per
  address, which Zebra cannot do without a wallet. It mines coinbase to the
  offline signer in `rust/examples/regtest-orchard-funder` (taken from the Zakura E2E
  branch), which pins NU6.3 at 500, so the chain must use that height.
- Ports bind loopback only: Zebra RPC on 48232 (`NU7_REGTEST_RPC_PORT`) and
  lightwalletd on 49067 (`NU7_REGTEST_LIGHTWALLETD_PORT`). RPC auth is off.
- `down.sh` and `reset.sh` touch only the `vizor-nu7-regtest` compose project.
- Wallets must use the same heights: the Rust tests call
  `configure_regtest_ironwood_activation_height` and
  `configure_regtest_nu7_activation_height`; app builds pass
  `ZCASH_REGTEST_IRONWOOD_ACTIVATION_HEIGHT` and
  `ZCASH_REGTEST_NU7_ACTIVATION_HEIGHT`.
- Zebra regtest reports a meaningless `estimatedheight`, so the app's stalled
  endpoint checks treat a custom endpoint on this chain as stalled.

Run the Rust scenario with `scripts/nu7-regtest/run-rust-test.sh`.

The iOS full regtest suite runs both mobile migration scenarios on a booted
simulator. Set `SIMULATOR_UDID` to select a specific simulator.

- `scripts/e2e/flutter-ios-regtest-mobile-ironwood-migration-nu7.sh` funds
  0.0105 ZEC on Zebra and mines through NU6.3 at 500 and NU7 at 520 while
  the app is open.
- `scripts/e2e/flutter-ios-regtest-mobile-ironwood-background-restart.sh`
  checks that iOS can broadcast persisted proofs after relaunch on zcashd.

The macOS fee regression runs with
`scripts/e2e/flutter-macos-ironwood-migration-nu7.sh`. It migrates the same
0.0105 ZEC fixture on Zebra through the desktop Home screen.

To watch a many-note migration on macOS, run
`migration_sim_test/run_full_migration.sh` from the repository root. This
manual scenario funds 20 Orchard notes with 10.0002 regtest ZEC in total on
the same Zebra stack. The desktop window stays visible through preparation,
scheduled transfers and confirmation, then shows the migration in Activity
for 15 seconds. The runner prints the directory under
`migration_sim_test/artifacts/` containing the run log. The log records the
regtest wallet DB path, transfer progress and final pool balances. Both
full-suite runners omit this scenario.
