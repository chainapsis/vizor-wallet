# Swap receiving software-wallet POC

This build exercises derived refund and incoming keys through normal Vizor scanning,
transaction enhancement, restore, and software spending. Receiver-directory PIR,
key retirement, and Keystone are later milestones. All registered keys stay active
in this POC, including after NEAR reports a terminal state.

## Build

The Rust feature `swap-receiving-poc` enables address issuance and recovery orchestration.
It is off by default. Dart reads the Rust feature state, so there is no second feature flag.
Hardware and viewing-only accounts cannot issue these addresses.

For a local debug app, create an uncommitted `rust/cargokit.yaml`:

```yaml
cargo:
  debug:
    extra_flags: ["--features", "swap-receiving-poc"]
```

The local dependency overrides expect the wallet-libraries checkout beside this
checkout. Backend, SQLite, and PCZT resolve to that checkout. Keep the overrides
local until the library changes are published.

Generate the bridge with `scripts/generate-rust-bridge.sh`. Its existing cargo-expand
shim handles syntax that the pinned bridge generator cannot parse. Then use the
normal Flutter build workflow with an isolated bundle, wallet database, and Keychain
service. Native Rust mnemonic lookup and Dart storage must use the same service.
Do not reuse the installed app's wallet identity for this test.

## Wallet flow

1. A quote obtains the live chain height. Issuance waits for scanning and memo
   enhancement, recovers confirmed funding records, then reserves the next index.
   Refunds and incoming payments use independent sequences. Quote retries retain
   their reservation.
2. Outgoing fee estimation and funding use the same normal proposal pipeline with
   a binary recovery memo on ordinary internal Ironwood change. The proposal must
   include that memo in the transaction paying the deposit address. A zero-value
   change note is valid. Multi-step funding and deposit instructions requiring a
   separate memo are rejected in this POC.
3. Sync registers 20 incoming lookahead keys from the account birthday or Ironwood
   activation, whichever is later. Confirmed internal funding memos register refund
   keys only when the same account supplied an input to the transaction.
4. New keys queue missing history. Sync checks again after enhancement and before
   completing, so a newly recovered key cannot be skipped just because ordinary
   account scanning already reached the tip. Payments extend the incoming window
   and queue replay for the added keys.
5. Received notes retain their derived key for reconstruction and software spending.
   Change returns to the ordinary internal key.

Incoming seed recovery has a bounded gap limit. It does not guarantee discovery
beyond 20 consecutive unpaid indices. Provider-status history reconstruction from
recovered deposit addresses remains a later integration task.

## Validation

The shared-library tests cover zero-value funding records, seed restore, a refund
whose block was already scanned, incoming payments outside the initial window,
close/reopen, and mixed-input spending into ordinary change. Recovery tests run
with receiver PIR and Enhance PIR disabled as well as with library PIR support enabled.
Vizor tests cover reserved refund-key validation, restart, lookahead preparation,
issuance during incomplete sync, direction mapping, and rejection without falling
back to an ordinary address.

```sh
cargo test --manifest-path rust/Cargo.toml --features swap-receiving-poc wallet::swap_receiving::tests --lib
fvm flutter test test/features/swap/swap_zec_staging_address_service_test.dart test/features/swap/swap_address_plan_test.dart test/features/swap/swap_deposit_amount_test.dart
```

## Manual milestone checks

Use a disposable software wallet. Live funding is a separate, explicitly authorized
exercise. Record the funding and payout transaction IDs and scan heights.

- Exercise both an outgoing swap refund and an incoming Zcash payout.
- Close before settlement, reopen after it, and confirm catch-up finds the payment.
- Restore the seed into another fresh wallet with a birthday before funding.
  Confirm recovery finds the same notes and does not duplicate the balance.
- Spend recovered notes together with ordinary funds. Confirm the spend mines and
  the change is found by the ordinary internal key.
- Confirm hardware accounts are blocked before the quote exposes an address.

Passing the automated checks does not substitute for this signed-app exercise.
