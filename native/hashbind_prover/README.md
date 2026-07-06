# vizor_hashbind_prover

On-device ProveKit hashbind prover for the zwap b2z/z2b swap directions.
The wallet's
spend-auth scalar `k_a` enters `vizor_hashbind_prove()` in-process and never
leaves the device; the regtest HTTP prove helper
(`ZWAP_HASHBIND_PROVER_URL`) remains available in debug builds only.

## What it is

A nightly-Rust cdylib wrapping upstream `provekit-ffi` pinned to the SAME
provekit rev + `provekit_ntt` config the solver verifies with
(`shielded-zwap-e2z-proxy/rust/solverd-v2/Cargo.toml`, currently
`cc391c8`). Witness generation is `src/hashbind_core.rs`, a verbatim vendored
copy of the proxy's `rust/hashbind-core` crate; the golden-fixture test fails
if it drifts.

Proof output is provekit's `.np` (postcard) binary format — what the
solver's native `ProofEngine` verifies, and the §3.3 wire discriminator
between native (Vizor) proofs and the browser FE's JSON (wasm) proofs.

## Layout

- `src/lib.rs` — the C ABI (`vizor_hashbind_{init,ready,prove,verify,last_error,free_buf}`), header in `include/vizor_hashbind.h`.
- `src/hashbind_core.rs` — vendored witness math (do not edit).
- `fixtures/pallas.pkv` — verifying key for the round-trip test (sha256 `50151b33…`, test-only). The proving key is NOT duplicated here: the test reads the app asset `assets/zwap/pallas.pkp` (sha256 `cca9d3a0…`, byte-identical to the solver key, hash pinned in `zwap_hashbind_native.dart`).
- `fixtures/hashbind_inputs_golden.json` — inputs.json for the fixture scalar, generated from the proxy repo's `hashbind-core` crate.
- `apple/` — podspec; `VizorHashbindProver.xcframework` lands here (gitignored).

## Build

```bash
scripts/build-hashbind-prover.sh   # from the repo root
(cd ios && pod install)
(cd macos && pod install)
```

Slices: ios-arm64, ios-arm64-simulator, macos-arm64+x86_64. rustup picks the
pinned nightly from `rust-toolchain.toml` automatically. Without the
xcframework the app still builds; the zwap b2z/z2b flow throws a clear
"prover unavailable" error and the Podfiles print the build command.

**Android**: the crate compiles for `aarch64-linux-android`, but packaging
needs an NDK lane (cargo-ndk → `android/app/src/main/jniLibs/`); the Dart
bridge already dlopens `libvizor_hashbind_prover.so` when present. Follow-up.

## Tests

```bash
cargo test                                    # fast: golden parity + ABI error paths
cargo test --release -- --ignored --nocapture # full prove→verify round-trip vs solver keys
```

Round-trip on an M-series host (release): pkp load ~0.35s, prove ~5.8s
(~2.8 MB proof), verify ~0.5s, tampered proof rejected.

## Version-bump checklist (solver rev / key regen, e.g. proxy WP1)

1. Bump both provekit `rev`s in `Cargo.toml` to the solver's new pin; keep `provekit_ntt`.
2. Re-copy `assets/zwap/pallas.pkp` and `fixtures/pallas.pkv` from the solver's assets; update `kZwapHashbindPkpSha256` in `zwap_hashbind_native.dart`.
3. Regenerate `fixtures/hashbind_inputs_golden.json` from the proxy's `hashbind-core` if the circuit changed; re-vendor `src/hashbind_core.rs` if the witness math changed.
4. `cargo test --release -- --ignored` must pass (prove→verify against the new pkv).
5. Rebuild the xcframework + `pod install`.
