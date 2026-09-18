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

- App: Zcash 3.9.3, `LedgerHQ/app-zcash` commit
  `22dc38537f9a84b31b938e3ca95434595ef378d3`.
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
  Zcash 3.9.3 does not establish support; retain the production compatibility guard.
- Speculos validates device-app/APDU behavior, not physical USB/Bluetooth or
  production broadcast. Externally managed mobile endpoints need their own
  forwarding; the Docker runner keeps APIs on host loopback, not the LAN.
- Custom images/ELFs and other host architectures require separate validation.
