# Swap receiving software-wallet POC

This build exercises separate refund and incoming receiving keys, private recovery,
and software spending. Existing swaps keep their recovery records and spending keys.
Hardware accounts continue to use their existing swap addresses.

## Settings and build

On mainnet, turn on **Private queries**, then **NEAR swap privacy** in Settings.
NEAR swap privacy defaults off and is saved for this installation. Turning Private
queries off also saves NEAR swap privacy as off. Turning Private queries back on
does not re-enable it. Desktop and mobile use the same preference and runtime guard.

NEAR swap privacy controls new private addresses. Turning it off does not discard
existing reservations, funding memos, keys, notes, or provider status tracking.
Existing private recovery continues while Private queries is on. With Private
queries off, queued private discovery waits for it to be enabled again. Already
received notes remain spendable and change returns to the ordinary internal key.
A quote already issued keeps its reserved address and funding recovery memo.

The receiver client currently requires Tor off. New private reservations fail
before exposure when Tor is selected. Existing private discovery is deferred
without bypassing Tor or blocking ordinary scanning.

The dependencies use exact Git revisions and published PIR math crates. No sibling
compatibility checkout or compile-time privacy environment variable is needed.
The legacy `swap-receiving-poc` Cargo feature remains accepted by old build scripts
but does not turn the setting on.

Generate the bridge with `scripts/generate-rust-bridge.sh`. Then use the normal
Flutter build workflow with an isolated bundle, wallet database, and Keychain
service. Native Rust mnemonic lookup and Dart storage must use the same service.
Do not reuse the installed app's wallet identity for this test.

See [private recovery](near-swap-private-recovery-poc.md) for the directory protocol
and the 48-hour, three-reservation, and 50-slot incoming-address policy.

## Wallet flow

1. The first quote obtains the live chain height without updating the wallet tip
   or starting sync. A new reservation requires contiguous scanning within ten
   blocks of the newer RPC/DB tip and no pending transaction enhancement. It
   recovers confirmed funding records, then reserves the next index, watching
   from the first unscanned block. This is a near-tip policy, not a guarantee
   that an independently restored wallet has discovered allocations in the tail.
   Refunds and incoming payments use independent sequences. Quote errors, amount
   edits, and refreshes retain the same reservation for the current account and
   direction, including while address preparation is in flight. Starting a swap,
   requesting a quote for another account/direction, or restarting the app
   requires a new reservation.
   Existing reservations remain watched; errors never roll back a key that may
   already have been sent to the provider. A retained address does not require
   another sync readiness check for each quote.
2. Outgoing fee estimation and funding use the same normal proposal pipeline with
   a binary recovery memo on ordinary internal Ironwood change. The proposal must
   include that memo in the transaction paying the deposit address. A zero-value
   change note is valid. Multi-step funding and deposit instructions requiring a
   separate memo are rejected in this POC.
3. With NEAR swap privacy enabled, sync registers 50 incoming lookahead keys from the account birthday or Ironwood
   activation, whichever is later. Confirmed internal funding memos register refund
   keys only when the same account supplied an input to the transaction.
4. After ordinary scanning, registered keys use receiver PIR to find payments and
   Enhance PIR to retrieve encrypted note data. Payments extend incoming lookahead.
   Pending swaps also add their key to ordinary trial decryption for a bounded watch.
5. Received notes retain their derived key for reconstruction and software spending.
   Change returns to the ordinary internal key.

Incoming seed recovery has a bounded gap limit. It does not guarantee discovery
beyond 50 consecutive unpaid indices. Provider-status history reconstruction from
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
- Confirm hardware accounts continue to use their existing address flow.
- Check both settings default off. Enable Private queries, then NEAR swap privacy.
  Restart and confirm both choices persist. Disable Private queries and confirm
  the child stays off after re-enabling the parent.
- Turn NEAR swap privacy off during a pending software swap. Its refund must still
  be found, and its received note must remain spendable.

Passing the automated checks does not substitute for this signed-app exercise.
