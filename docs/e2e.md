# End-to-end and regtest tests

How to run and write the Flutter and Rust regtest scenarios, and what to clean
up after a run. The runner and every scenario are described in
`scripts/e2e/README.md`. These runs are slow and heavy: start them only when
the user explicitly asks for regtest or E2E execution.

## Running on macOS

Unless the task explicitly requires a visible window, run macOS E2E with the
app window hidden. The scripts do this by default; opt out only when the window
is needed for debugging or visual verification.

```bash
VIZOR_E2E_HIDDEN_WINDOW=false scripts/e2e/flutter-macos-regtest-import-sync.sh
```

A hidden window still runs in the user's session, so the Mac must stay
unlocked: the runner stops a Flutter run while the session is locked instead of
letting its cases hang.

## Flutter regtest E2E

- Integration tests: `fvm flutter test integration_test/` (requires device/simulator)
- Every `scripts/e2e/flutter-*.sh` regtest runner runs its scenarios on Zakura regtest chains through `scripts/e2e/zakura-run.py`; the catalog is `scripts/e2e/zakura_flutter.py` and the details are in `scripts/e2e/README.md`.
- Run app tests with `--dart-define=ZCASH_DEFAULT_NETWORK=regtest`; do not use the old `ZCASH_USE_E2E_STORAGE` path. Secure storage and wallet DB names are network-scoped.
- Cleanup code should guard on `kZcashDefaultNetworkName == ZcashNetwork.regtest.name`, then delete `getWalletDbName()` plus its `-shm` / `-wal` files.
- Use `ZCASH_E2E_LIGHTWALLETD_URL` only as the endpoint override, and keep Rust API calls on the same network as `kZcashDefaultNetworkName`.
- Mempool receive E2E should use external funding from the regtest control when testing true inbound tx discovery, not another in-app account.
- To prove mempool behavior while sync is active, pre-mine enough regtest blocks and pass the debug-only Rust throttle env vars inline: `ZCASH_E2E_SYNC_BATCH_SIZE` and `ZCASH_E2E_SYNC_BATCH_DELAY_MS`.

## Mobile (iOS simulator) regtest E2E

- One-shot runner: `./scripts/e2e/flutter-ios-regtest-mobile-full.sh`; per-scenario runners are `scripts/e2e/flutter-ios-regtest-mobile-*.sh`. Same heaviness rule as desktop: do not run unless explicitly asked.
- Tests live in `integration_test/regtest_mobile_*_test.dart` and share `integration_test/support/mobile_regtest_flow.dart` (pump/tap helpers, regtest-guarded cleanup, mobile flow primitives). Desktop regtest tests keep their per-file helpers; do not merge them.
- Mobile runs need `VIZOR_FORM_FACTOR=mobile` and `ZCASH_DEFAULT_NETWORK=regtest`, plus `ZCASH_E2E_LIGHTWALLETD_URL` where the scenario overrides the endpoint; `zakura-run.py` passes them from the catalog. Gift Card scenarios also need `VIZOR_PAYMENT_LINK_REGTEST_ENABLED=true` (payment links stay gated off without it) and `VIZOR_DEEPLINK_BASE_URL`.
- Device: each run creates its own simulator (`Vizor Zakura E2E <run id>`, iPhone 16, the newest iOS runtime unless `--ios-runtime` names one) and deletes it at the end. It never uses an already booted simulator.
- Each `flutter test integration_test` invocation reinstalls the app: the wallet DB dies with the container while the iOS Keychain persists until the reinstalled app's first launch clears it, so in-test `cleanupE2eWalletState()` (deleteAll + db files, regtest-guarded) runs at test start AND teardown. Cross-invocation wallet reuse needs `--no-uninstall`: the Ironwood restart runners pass it to their prepare phase so the resume phase reopens the same install. Gift Card scenarios pair it with `cleanupMobileE2ePaymentLinkClaimWallets()`, the regtest-guarded claim-wallet sweep — claim wallets from every network share one support directory, so the sweep is scoped to regtest names. Scenarios that leave the pasteboard populated clear it in teardown too; the simulator pasteboard outlives the app container.
- The simulator shares the host loopback: `127.0.0.1` URLs, the in-test lightwalletd proxy, and the regtest control all work unchanged. Android emulators would need `10.0.2.2` and are out of scope.
- Desktop scenarios without mobile counterparts (feature gaps, add when the features land): custom-endpoint privacy (no mobile endpoint settings UI), shield-transparent ×2 (no mobile transparent balance / shield UI), mempool during-sync / expiry variants.
- Payment-request round trip and payment-URI locked-send: desktop runners only. The mobile receive pane has its own request sheet, so this is a harness gap rather than a feature gap.
- Gift Card restart recovery and reorg retry: desktop runners only. The Gift Card round trip has a mobile counterpart driving the **Redeem a card → Paste card link** path; mobile claiming over a universal link still needs a publicly reachable HTTPS origin — see `scripts/e2e/README.md`. The payment-URI send also has a mobile counterpart, which instead pushes an `onUris` call over the `com.zcash.wallet/payment_uri` MethodChannel to raise the payment-request card.

## Zcash regtest Rust integration tests

- One-shot runner from repo root: `./run-regtest-rust-tests.sh` runs every Rust scenario; `./run-regtest-rust-tests.sh rust.import rust.send.basic` selects scenario IDs or dotted prefixes. List them with `python3 scripts/e2e/zakura-run.py --list`.
- Each test runs alone against its own fresh Zakura regtest chain: a Zakura node and lightwalletd in Docker, the lightwalletd shim and an HTTP control (`scripts/e2e/zakura-run.py`). Tests never share chain or wallet state.
- Ironwood (NU6.3) is active from height 1, except in the `rust.ironwood.*` scenarios, which fund Orchard before activating Ironwood at height 500.
- Funding is signed offline from a public test-only coinbase key (`rust/examples/regtest_direct_funder.rs`); there is no node wallet.
- The signer and the test executables are built once per run from the committed `rust/` tree. The runner refuses to start while `rust/` has uncommitted changes.
- Prerequisites: Python 3.11+, Docker, `grpcurl`, the fvm-pinned Flutter SDK after `fvm flutter pub get` (the lightwalletd shim runs on its Dart), and Cargo dependencies already fetched (`cargo fetch --locked` in `rust/`; the build runs offline).
- The runner streams its output to the terminal and saves a copy to `.regtest-logs/regtest-rust-tests.log`. Each run also writes `.regtest-logs/zakura-<run id>/report.json` and per-test logs.
- Passing tests are always cleaned up, and the run's build output (several GB) is removed when it ends. `./run-regtest-rust-tests.sh --keep` keeps the stopped containers and wallet files of failed tests; the report lists their Docker IDs for removal.
- Sapling proving params are cached at `~/.zcash-params` by default. Override with `SAPLING_PARAMS_DIR=/custom/path ./run-regtest-rust-tests.sh` if needed.
- These regtest scenarios are slow and heavy. Do not run them unless the user explicitly asks for regtest/integration execution.

## Cleaning up after a run

Agents start most of these runs, so the agent that started a run removes what
it left once nobody needs it. Remove only what you can tie to your own run id.
If you cannot tell whether something is yours, leave it and say so in your
report.

The runner already removes each scenario's chain, wallet files and port
locks, each voting case's regenerated data, the run's build output and the
run's simulator. What stays behind:

- `--keep-failed` keeps a failed scenario's stopped containers, network,
  volume and wallet files, and the run's simulator. A scenario whose cleanup
  failed also lists what remains under `retained` in `report.json`.
- A run killed before it could clean up (SIGKILL, a closed session, a reboot)
  leaves its containers running, its simulator booted, case processes on the
  fixed ports, and `builds/` in its run folder.
- Caches outside the run folder stay: the worktree's `build/`, `.dart_tool/`
  (Flutter keeps one build cache per configuration and never prunes them) and
  `rust/target/`, and the Xcode DerivedData folder of the worktree's iOS
  workspace. One full 85-scenario run left about 88 GB there.
- The Ledger lane keeps the `vizor-speculos.*` folder it prints (app clone,
  logs, ELF).
- `.regtest-logs/build-cache/` keeps the built signer and Rust test
  executables for later runs, about 500 MB per entry.

### What you may remove

Your run id is the suffix of `.regtest-logs/zakura-<run id>/`.

- Docker containers, networks and volumes labelled for your run. Match the
  whole `vizor_<run id>_` prefix, never anything broader. Then delete the
  run's simulator by its exact name:

  ```bash
  run_id=<run id>
  ns="vizor_${run_id}_"
  label=com.keplr.vizor.e2e.namespace
  docker ps -a --filter "label=$label" --format "{{.Label \"$label\"}} {{.ID}}" |
    awk -v p="$ns" 'index($1, p) == 1 { print $2 }' | xargs docker rm -f
  docker network ls --filter "label=$label" --format "{{.Label \"$label\"}} {{.ID}}" |
    awk -v p="$ns" 'index($1, p) == 1 { print $2 }' | xargs docker network rm
  docker volume ls --filter "label=$label" --format "{{.Label \"$label\"}} {{.Name}}" |
    awk -v p="$ns" 'index($1, p) == 1 { print $2 }' | xargs docker volume rm
  udid=$(xcrun simctl list devices | grep -F "Vizor Zakura E2E $run_id (" |
    sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
  if [ -n "$udid" ]; then
    xcrun simctl shutdown "$udid" 2>/dev/null || true
    xcrun simctl delete "$udid"
  fi
  ```

- If the next run refuses a fixed port (`port N is in use`), find the listener
  with `lsof -nP -iTCP:N -sTCP:LISTEN`. Stop it only if your run started it;
  otherwise report it.
- Your run folder, `.regtest-logs/zakura-<run id>/`, once the result is
  reported and you have copied what you still need. While a failure is
  unresolved, keep the folder and its kept chain, and say so.
- The `vizor-speculos.*` folder the Ledger lane printed for your run.
- Old build cache entries, through `python3 scripts/e2e/prune-build-cache.py
  --apply`. It keeps each kind's two newest entries and skips any that a
  running run holds. Never delete the cache folder by hand.
- Build caches of a worktree you created for this task, once nothing runs
  there: `build/`, `.dart_tool/` and `rust/target/`, each only after
  `git check-ignore -q <dir>` succeeds and `lsof -nP -Fn | grep -F "$PWD/<dir>/"`
  prints nothing. Its iOS DerivedData folder is the one this prints, run from
  the worktree root:

  ```bash
  ws=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$PWD/ios/Runner.xcworkspace")
  for d in $(find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -type d -name 'Runner-*'); do
    p=$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$d/info.plist" 2>/dev/null) || continue
    [ "$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$p")" = "$ws" ] && echo "$d"
  done
  ```

### Never

- Run `docker system prune`, `docker volume prune` or `docker image prune`,
  remove containers by a name pattern, or remove pulled images. Never
  force-quit Docker Desktop.
- Delete or erase any simulator but your run's (`xcrun simctl delete all`,
  `xcrun simctl erase all`). The user's own simulators stay.
- Delete `~/Library/Developer/Xcode/DerivedData` or another workspace's folder
  in it.
- Run `flutter clean` or delete build caches in a worktree you did not create,
  or one another agent or session is using.
- Remove shared caches: `.regtest-voting/deps` (reused by every voting run),
  `~/.zcash-params`, `~/.pub-cache`, `~/.cargo`, `~/.gradle`, SwiftPM caches
  or simulator runtimes.
- Touch Docker resources without your run's label, including other compose
  stacks, or stop processes you did not start.

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
