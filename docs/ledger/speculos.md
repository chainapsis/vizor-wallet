# Ledger Speculos E2E

Run from the repository root with Docker running. The runner builds a Zcash Nano
S+ ELF and creates one fresh, headless Speculos instance per scenario.

## Requirements

- Bash, Docker, Git, curl, jq.
- Signing smoke: Cargo and a supported desktop host.
- Flutter E2E: Cargo, `fvm`, base64, gzip; mobile also needs `FLUTTER_DEVICE`.
- Android: an unlocked emulator and Android SDK `platform-tools` (`adb`) on `PATH`.

## Run

```bash
# Build ELF, check emulator startup, then clean up.
scripts/e2e/ledger-speculos-docker.sh smoke

# Export UFVK and sign/finalize a PCZT on the same emulator, without Flutter UI.
scripts/e2e/ledger-speculos-docker.sh signing-smoke

# All default desktop scenarios; macOS windows are hidden by default.
scripts/e2e/ledger-speculos-docker.sh desktop

# One scenario.
VIZOR_LEDGER_E2E_SCENARIO='shields transparent balance with Ledger through Speculos' \
  scripts/e2e/ledger-speculos-docker.sh desktop

# Mobile; the runner supplies the mobile design-token define.
FLUTTER_DEVICE='<simulator-device-id>' scripts/e2e/ledger-speculos-docker.sh mobile

# Reuse an existing Nano S+ ELF instead of rebuilding it.
VIZOR_LEDGER_SPECULOS_ELF='/absolute/path/zcash-nanosplus.elf' \
  scripts/e2e/ledger-speculos-docker.sh signing-smoke
```

## Environment and results

- App: Zcash 3.9.4, `LedgerHQ/app-zcash` commit
  `1a0f6495458ecb77abf97c8cff25b0a1a344daaa`.
- Official builder and Speculos image digests are pinned in
  [`ledger-speculos-docker.sh`](../../scripts/e2e/ledger-speculos-docker.sh).
  Overrides: `VIZOR_LEDGER_BUILDER_IMAGE`, `VIZOR_LEDGER_SPECULOS_IMAGE`.
- Build: `cargo ledger build nanosplus`, with a Docker volume at `/app/target`.
  Speculos uses `--model nanosp`, headless mode, and its default test seed.
- Both `VIZOR_LEDGER_SPECULOS_UFVK_API_URL` and
  `VIZOR_LEDGER_SPECULOS_SIGNING_API_URL` point to the same dynamic loopback port.
  Existing Flutter runners also accept externally managed endpoints.
- Mobile requires an exact connected iOS simulator or Android emulator ID.
  Android uses device-scoped `adb reverse` for each scenario's loopback port;
  existing mappings are preserved, and the runner removes only its own mapping.
- The printed artifact directory retains `build.log`, scenario logs,
  `results.tsv` (exit codes), `versions.txt`, source, and ELF. Wallet fixture
  paths appear in scenario logs. The runner removes its containers and volume.
- Scenario failures do not stop remaining scenarios; any failure makes the final
  exit code nonzero. Build/startup failures stop immediately.

## Test boundaries

- UFVK export needs a four-second status-screen wait in the Rust harness and
  Flutter import/send scenario. This adds no delay to production UFVK handling.
- The synthetic DB includes a transparent UTXO and completed external/change
  discovery checkpoints (`complete=2`). Preparation checks the production
  shielding-progress API for one shieldable input; it does not run live discovery.
- `VIZOR_LEDGER_RUN_ORCHARD_TO_IRONWOOD_CANARY=true` adds the compatibility canary.
  Zcash 3.9.4 has not been run against it; retain the production compatibility guard.
- Voting builds two real SDK `PreparedDelegationBundle::keystone_request`
  requests from synthetic eligible Ironwood notes. It verifies the zero-value
  foreign-hotkey output, then signs the SDK-redacted bytes through the production
  desktop/mobile signer. Ledger-only SDK compatibility enables account-OVK
  recovery and printable ASCII memos; software/Keystone retain SDK defaults.
  This covers SDK setup/request generation and device signing, not snapshot
  discovery, PIR/proving, vote-session orchestration or chain submission.
- Saved signing contexts are reused unchanged; enabling output review does not
  repair an old failed PCZT. Account-OVK holders can recover the hotkey output
  and memo from published effects when Ledger output review is enabled.
- Speculos validates device-app/APDU behavior, not physical USB/Bluetooth or
  production broadcast. Externally managed mobile endpoints need their own
  forwarding; the Docker runner keeps APIs on host loopback, not the LAN.
- Custom images/ELFs and other host architectures require separate validation.

### Desktop voting through final tally

Run `scripts/e2e/ledger-speculos-docker.sh voting-tally` with Docker and the
regtest voting prerequisites available. This lane builds the pinned app with
`--features testnet` and changes its install paths to `44'/1'` and `32'/1'` in a
disposable checkout. `VIZOR_LEDGER_SPECULOS_TESTNET_ELF` can reuse that build;
the mainnet `VIZOR_LEDGER_SPECULOS_ELF` is not used by this lane.

The distributed Zcash app uses coin type 133. Its source has a testnet feature
for coin type 1, but the install paths do not change automatically. Vizor's
production mainnet restriction remains in place. This test variant is not an
officially distributed testnet app.

The lane runs software and Ledger accounts against separate fresh local chains
using the same public disposable mnemonic, funded notes, four proposals and
decision 0. The helper exports the real device UFVK at coin type 1 and re-encodes
it from testnet to regtest without changing its keys. The Ledger case imports it
as a hardware account with no mnemonic stored in Vizor. Funding and migration
are prepared with the software fixture before this import; this lane does not
test Ledger shielding.

Only the test's Ledger signer provider is replaced: it invokes a Rust helper
that uses the production APDU transport and signature verification against the
simulator. A loopback HTTP bridge lets the sandboxed macOS app call the helper. This bypasses the product API's mainnet account gate; the existing
mainnet signing scenarios cover that wrapper separately. SDK delegation,
proof generation, vote submission, share processing and final tally stay real.
Each run waits for `FINALIZED` and checks all 64 revealed shares, one ballot for
each selected option and zero for every other option.

`E2E_LEDGER_VOTING=true` or `false` selects one account type when rerunning a
failed case; the default runs both. `E2E_VOTE_WINDOW_SECS` defaults to 300; increase it on slower hosts. Results and
device logs are retained in the printed Speculos artifact directory.
