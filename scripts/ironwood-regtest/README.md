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
scripts/ironwood-regtest/fund-orchard.sh "<uregtest-address>" 1.0002 10

scripts/ironwood-regtest/status.sh
scripts/ironwood-regtest/checkpoint.sh save orchard-funded
scripts/ironwood-regtest/activate-ironwood.sh
scripts/ironwood-regtest/checkpoint.sh restore orchard-funded
scripts/ironwood-regtest/up.sh
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
