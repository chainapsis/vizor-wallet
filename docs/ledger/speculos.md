# Ledger Speculos E2E

Run from the repository root with Docker running. The managed runner builds the
Ledger Zcash app, starts two headless Nano S+ emulators, and runs each selected
journey with a fresh pair. It removes its own containers and build volume on exit
(including failures and signals). Logs, source checkout, and ELF are retained in
the temporary artifact directory printed at startup. Existing E2E runners retain
their wallet fixtures separately and print those paths in the scenario logs.

```bash
# Build the ELF and verify emulator startup without launching Flutter.
scripts/e2e/ledger-speculos-docker.sh smoke

# All desktop journeys, with hidden macOS windows by default.
scripts/e2e/ledger-speculos-docker.sh desktop

# One journey.
VIZOR_LEDGER_E2E_SCENARIO='signs sequential voting bundles with Ledger through Speculos' \
  scripts/e2e/ledger-speculos-docker.sh desktop

# Mobile: select a Flutter test device; the existing runner sets mobile tokens.
FLUTTER_DEVICE='<device-id>' scripts/e2e/ledger-speculos-docker.sh mobile
```

Requirements: Bash, Docker, Git, curl, jq. E2E also requires the existing Flutter
and Rust toolchains (`fvm`, Cargo), base64, and gzip. The first build downloads
sources and images and may take several minutes. Follow `build.log` in the printed
artifact directory. `results.tsv` records each scenario's exit status; failures
are collected while remaining scenarios continue, and the runner exits nonzero
if any scenario failed. Startup/build failures stop immediately.

## Pinned environment

- App: `LedgerHQ/app-zcash` commit
  `22dc38537f9a84b31b938e3ca95434595ef378d3` (Zcash 3.9.3).
- Builder: `ghcr.io/ledgerhq/ledger-app-builder/ledger-app-builder`, digest
  `sha256:2e085afbe636098763e34ef6eca6069ea1a0f702805f6b14870c0f952262da6d`.
- Speculos: `ghcr.io/ledgerhq/speculos`, digest
  `sha256:6ed9eefd51cddd862b746719af4cd7a3265fe43d0588c388359753cab8d46d11`.
- Build: `cargo ledger build nanosplus`, with a Docker volume mounted at
  `/app/target`. This avoids the Apple Silicon bind-mounted target build failure
  observed during the original run. The executable is `target/nanosplus/release/zcash`.
- Emulation: `--model nanosp --display headless --api-port 5000`, using the
  emulator's default test seed for both instances. Never use a real wallet seed.

The digests preserve the locally tested image versions rather than following
`latest`. Overrides are `VIZOR_LEDGER_BUILDER_IMAGE` and
`VIZOR_LEDGER_SPECULOS_IMAGE`; the selected references are saved in `versions.txt`.
Compatibility of overrides and other host architectures must be verified.

Reuse an already built Nano S+ ELF to skip the build:

```bash
VIZOR_LEDGER_SPECULOS_ELF='/absolute/path/zcash-nanosplus.elf' \
  scripts/e2e/ledger-speculos-docker.sh smoke
```

An external ELF replaces the pinned app build; its version is the caller's
responsibility. The original file is copied and not modified.

## Connection and scope

Each emulator publishes REST port 5000 on a dynamically assigned **127.0.0.1**
port. The runner checks `/events?currentscreenonly=true` for the ready screen and
exports `VIZOR_LEDGER_SPECULOS_UFVK_API_URL` and
`VIZOR_LEDGER_SPECULOS_SIGNING_API_URL` to the existing E2E runner. UFVK export and
signing use separate instances because the post-UFVK session rejected PCZT
initialization during the original validation. Both instances are recreated
before each journey, including fixture preparation.

The existing `flutter-macos-ledger-speculos.sh` and
`flutter-mobile-ledger-speculos.sh` still support externally managed endpoints.
Their scenario lists are shared in `ledger-speculos-scenarios.sh`.

`VIZOR_LEDGER_RUN_ORCHARD_TO_IRONWOOD_CANARY=true` includes the opt-in compatibility
canary. Zcash 3.9.3 does not establish Orchard-to-Ironwood support; a canary failure
must not be interpreted as permission to remove the production guard.

Speculos checks device-app/APDU behavior, not real USB/Bluetooth connectivity,
physical-device approval, or production broadcast. `smoke` verifies only emulator
startup and cleanup. Mobile tests must be able to reach the host endpoints; this
runner does not configure device port forwarding or expose the APIs on the LAN.
