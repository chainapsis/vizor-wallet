# Gift Card outcomes validation

Use when verifying settlement and recovery scenarios; regtest execution requires an explicit request.

Unit/widget coverage includes conflict finality, incomplete scans, top-ups,
local receipt identity, reorgs, stale checks, secret retention, archive/restore,
read-only status checks, partial submissions, and desktop/mobile outcomes.
Capture scenarios: `gift-card-claimed-elsewhere`, `gift-card-claim-failed`, and
`gift-card-claim-checking` (both form factors).

The macOS outcomes E2E runner covers three scenarios with real Rust wallets and
regtest transactions: competing claims, accepted-response loss and restart
recovery, and archived-card restoration after restart. Run
`scripts/e2e/flutter-macos-regtest-gift-card-outcomes.sh` explicitly; it uses the
shared local Docker chain. See `scripts/e2e/README.md` for phases and logs.

The explicit two-wallet competition scenario is compiled by:

```sh
cargo test --manifest-path rust/Cargo.toml --test regtest_payment_link_competition --no-run
```

Run it only when regtest execution is explicitly requested (it uses the shared
Docker regtest services and mines blocks):

```sh
cargo test --manifest-path rust/Cargo.toml --test regtest_payment_link_competition -- --ignored --nocapture --test-threads=1
```
