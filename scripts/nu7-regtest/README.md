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
  above NU6.3, but the Rust scenarios and the macOS E2E need a wider gap and
  refuse heights they cannot use.
- Funding pays block coinbase to the address with `generatetoaddress`: Orchard
  before NU6.3, Ironwood from it. Coinbase needs 100 confirmations.
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

Run the Rust scenario with `scripts/nu7-regtest/run-rust-test.sh`, the
macOS app scenario with `scripts/e2e/flutter-macos-nu7-migration-stop.sh`, and
its iOS simulator counterpart with
`scripts/e2e/flutter-ios-regtest-mobile-nu7-migration-stop.sh` (one booted
simulator, or `SIMULATOR_UDID`).
