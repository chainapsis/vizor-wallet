# End-to-end and regtest tests

How to run and write the Flutter and Rust regtest scenarios. The runner and
every scenario are described in `scripts/e2e/README.md`. These runs are slow
and heavy: start them only when the user explicitly asks for regtest or E2E
execution.

## Running on macOS

Unless the task explicitly requires a visible window, run macOS E2E with the
app window hidden. The scripts do this by default; opt out only when the window
is needed for debugging or visual verification.

```bash
VIZOR_E2E_HIDDEN_WINDOW=false scripts/e2e/flutter-macos-regtest-import-sync.sh
```

## Flutter regtest E2E

- Integration tests: `fvm flutter test integration_test/` (requires device/simulator)
- Every `scripts/e2e/flutter-*.sh` regtest runner runs its scenarios on direct Zakura fixtures through `scripts/e2e/zakura-run.py`; the catalog is `scripts/e2e/zakura_flutter.py` and the details are in `scripts/e2e/README.md`.
- Run app tests with `--dart-define=ZCASH_DEFAULT_NETWORK=regtest`; do not use the old `ZCASH_USE_E2E_STORAGE` path. Secure storage and wallet DB names are network-scoped.
- Cleanup code should guard on `kZcashDefaultNetworkName == ZcashNetwork.regtest.name`, then delete `getWalletDbName()` plus its `-shm` / `-wal` files.
- Use `ZCASH_E2E_LIGHTWALLETD_URL` only as the endpoint override, and keep Rust API calls on the same network as `kZcashDefaultNetworkName`.
- Mempool receive E2E should use external funding from the fixture's control when testing true inbound tx discovery, not another in-app account.
- To prove mempool behavior while sync is active, pre-mine enough regtest blocks and pass the debug-only Rust throttle env vars inline: `ZCASH_E2E_SYNC_BATCH_SIZE` and `ZCASH_E2E_SYNC_BATCH_DELAY_MS`.

## Mobile (iOS simulator) regtest E2E

- One-shot runner: `./scripts/e2e/flutter-ios-regtest-mobile-full.sh`; per-scenario runners are `scripts/e2e/flutter-ios-regtest-mobile-*.sh`. Same heaviness rule as desktop: do not run unless explicitly asked.
- Tests live in `integration_test/regtest_mobile_*_test.dart` and share `integration_test/support/mobile_regtest_flow.dart` (pump/tap helpers, regtest-guarded cleanup, mobile flow primitives). Desktop regtest tests keep their per-file helpers; do not merge them.
- Mobile runs need `VIZOR_FORM_FACTOR=mobile` and `ZCASH_DEFAULT_NETWORK=regtest`, plus `ZCASH_E2E_LIGHTWALLETD_URL` where the scenario overrides the endpoint; `zakura-run.py` passes them from the catalog. Gift Card scenarios also need `VIZOR_PAYMENT_LINK_REGTEST_ENABLED=true` (payment links stay gated off without it) and `VIZOR_DEEPLINK_BASE_URL`.
- Device: each run creates its own simulator (`Vizor Zakura E2E <run id>`, iPhone 16, the newest iOS runtime unless `--ios-runtime` names one) and deletes it at the end. It never uses an already booted simulator.
- Each `flutter test integration_test` invocation reinstalls the app: the wallet DB dies with the container while the iOS Keychain persists until the reinstalled app's first launch clears it, so in-test `cleanupE2eWalletState()` (deleteAll + db files, regtest-guarded) runs at test start AND teardown. Cross-invocation wallet reuse needs `--no-uninstall`: the Ironwood restart runners pass it to their prepare phase so the resume phase reopens the same install. Gift Card scenarios pair it with `cleanupMobileE2ePaymentLinkClaimWallets()`, the regtest-guarded claim-wallet sweep — claim wallets from every network share one support directory, so the sweep is scoped to regtest names. Scenarios that leave the pasteboard populated clear it in teardown too; the simulator pasteboard outlives the app container.
- The simulator shares the host loopback: `127.0.0.1` URLs, the in-test lightwalletd proxy, and the fixture's control all work unchanged. Android emulators would need `10.0.2.2` and are out of scope.
- Desktop scenarios without mobile counterparts (feature gaps, add when the features land): custom-endpoint privacy (no mobile endpoint settings UI), mempool during-sync / expiry variants.
- Payment-request round trip and payment-URI locked-send: desktop runners only. The mobile receive pane has its own request sheet, so this is a harness gap rather than a feature gap.
- Gift Card restart recovery and reorg retry: desktop runners only. The Gift Card round trip has a mobile counterpart driving the **Redeem a card → Paste card link** path; mobile claiming over a universal link still needs a publicly reachable HTTPS origin — see `scripts/e2e/README.md`. The payment-URI send also has a mobile counterpart, which instead pushes an `onUris` call over the `com.zcash.wallet/payment_uri` MethodChannel to raise the payment-request card.

## Zcash regtest Rust integration tests

- One-shot runner from repo root: `./run-regtest-rust-tests.sh` runs every Rust scenario; `./run-regtest-rust-tests.sh rust.import rust.send.basic` selects scenario IDs or dotted prefixes. List them with `python3 scripts/e2e/zakura-run.py --list`.
- Each test runs alone against its own fresh direct Zakura fixture: the pinned Zakura node and lightwalletd containers, the lightwalletd shim and an HTTP control (`scripts/e2e/zakura-run.py`). Tests never share chain or wallet state.
- Ironwood (NU6.3) is active from height 1, except in the `rust.ironwood.*` scenarios, which fund Orchard before activating Ironwood at height 500.
- Funding is signed offline from a public test-only coinbase key (`rust/examples/regtest_direct_funder.rs`); there is no node wallet.
- The signer and the test executables are built once per run from the committed `rust/` tree. The runner refuses to start while `rust/` has uncommitted changes.
- Prerequisites: Python 3.11+, Docker, `grpcurl`, the fvm-pinned Flutter SDK after `fvm flutter pub get` (the lightwalletd shim runs on its Dart), and Cargo dependencies already fetched (`cargo fetch --locked` in `rust/`; the build runs offline).
- The runner streams its output to the terminal and saves a copy to `.regtest-logs/regtest-rust-tests.log`. Each run also writes `.regtest-logs/zakura-<run id>/report.json` and per-test logs.
- Passing tests are always cleaned up, and the run's build output (several GB) is removed when it ends. `./run-regtest-rust-tests.sh --keep` keeps the stopped containers and wallet files of failed tests; the report lists their Docker IDs for removal.
- Sapling proving params are cached at `~/.zcash-params` by default. Override with `SAPLING_PARAMS_DIR=/custom/path ./run-regtest-rust-tests.sh` if needed.
- These regtest scenarios are slow and heavy. Do not run them unless the user explicitly asks for regtest/integration execution.

## Legacy zcashd stack (`scripts/regtest/`)

`zakura-run.py` does not use these scripts.

- `up.sh` — starts the Dockerized `zcashd + lightwalletd` regtest stack, waits for both services to become ready, and ensures the faucet state exists.
- `down.sh` — stops the regtest Docker compose stack.
- `reset.sh` — destroys the regtest containers/volumes and clears `.regtest/` state, then recreates a clean local chain on the next `up.sh`.
- `mine.sh <count>` — mines `<count>` new regtest blocks through `zcash-cli`.
- `fund-wallet.sh <unified_address> <amount_zec> [confirmations]` — sends shielded funds from the local faucet to the given UA, then mines enough blocks for confirmation. Example: `./scripts/regtest/fund-wallet.sh <ua> 1.25 10`
- `lib.sh` — shared helper functions used by the other regtest scripts; source it from scripts, do not run it directly.

Prerequisites:

- Docker Desktop / `docker compose` must be available.
- `grpcurl` is optional but recommended. If installed, the scripts use it to wait for `lightwalletd` gRPC readiness and chain-tip propagation; otherwise they fall back to a simpler TCP port check.
