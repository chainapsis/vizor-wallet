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
Recovery runs for every software account, including a fresh seed restore with both
switches off. NEAR address recovery always uses receiver PIR and Enhance PIR for
matching note data. Ordinary transaction and memo retrieval follows the general
Private queries setting. Already received notes remain spendable and change
returns to the ordinary internal key.
A quote already issued keeps its reserved address and funding recovery memo.

Receiver discovery, its common witness file and swap note enhancement use the
same route-aware HTTPS transport as ordinary Enhance PIR. They honor Tor and
cancellation without a direct fallback. An unavailable private service leaves
recovery pending without failing ordinary sync.

The dependencies use exact Git revisions and published PIR math crates. No sibling
compatibility checkout or compile-time privacy environment variable is needed.
The legacy `swap-receiving-poc` Cargo feature remains accepted by old build scripts
but does not turn the setting on.

Generate the bridge with `scripts/generate-rust-bridge.sh`. Then use the normal
Flutter build workflow with an isolated bundle, wallet database, and Keychain
service. Native Rust mnemonic lookup and Dart storage must use the same service.
Do not reuse the installed app's wallet identity for this test.

See [private recovery](near-swap-private-recovery-poc.md) for the directory protocol
and the 48-hour, three-reservation, and 30-slot incoming-address policy.

## Wallet flow

1. The first quote obtains the live chain height without updating the wallet tip
   or starting sync. A new reservation requires contiguous scanning within ten
   blocks of the newer RPC/DB tip and no pending transaction enhancement. It
   recovers confirmed funding records, then reserves the next index, scanning it
   from the first unscanned block until its swap closes. This is a near-tip
   policy, not a guarantee that an independently restored wallet has discovered
   allocations in the tail.
   Refunds and incoming payments use independent sequences. Quote errors, amount
   edits, and refreshes retain the same reservation for the current account and
   direction, including while address preparation is in flight. Starting a swap,
   requesting a quote for another account/direction, or restarting the app
   requires a new reservation.
   Existing reservations remain scanned; errors never roll back a key that may
   already have been sent to the provider. A retained address does not require
   another sync readiness check for each quote.
2. Outgoing fee estimation and funding use the same normal proposal pipeline with
   a binary recovery memo on ordinary internal Ironwood change. The proposal must
   include that memo in the transaction paying the deposit address. A zero-value
   change note is valid. Multi-step funding, non-transparent deposit addresses and
   deposit instructions requiring a separate memo are rejected in this POC.
3. Every software restore registers 30 incoming lookahead keys from the account
   birthday or Ironwood activation, whichever is later. Confirmed internal funding memos register refund
   keys only when the same account supplied an input to the transaction.
4. After ordinary scanning, restored refund keys and incoming lookahead each get
   one PIR sweep. Payments extend incoming lookahead until 30 consecutive indices
   are empty. Finish the extended window before reporting recovery complete. Each
   sweep keeps a fixed target, so new blocks do not restart completed sweeps.
   Funding memos also restore NEAR status polling for the deposit address, which
   comes from the funding transaction's transparent output. After its sweep, a
   refund key scans new blocks until it closes, and an unpaid incoming key for
   24 hours. Vizor checks NEAR status during sync, at most once per minute per
   pending refund. Failures, `FAILED` and unknown statuses keep a key scanning up
   to the seven-day limit. Reopening preserves polling times and observations.
5. Received notes retain their derived key for reconstruction and software spending.
   Change returns to the ordinary internal key.

Software accounts temporarily retain Ironwood spend evidence already downloaded
by normal compact scanning. Recovery releases old unrelated evidence after funding
memos, lookahead, sweeps and note imports complete. Other pools keep
ordinary retention. Interrupted recovery keeps its cache across restarts. A long
restore or stalled operation can still need a large temporary cache.

An included note discovered after pruning remains uncredited while the wallet
replays the account's public Ironwood recovery interval. Receiver discovery and
matching note enhancement still use PIR. No nullifier service is required.

Incoming seed recovery has a bounded gap limit. It does not guarantee discovery
beyond 30 consecutive unpaid indices. Incoming recovery cannot reconstruct a
provider association without its deposit address. Restored refund polling does
not recreate the full UI activity record or infer funds from provider status.

Wallet handles explicitly retain the existing public transparent-discovery mode
required by the latest library base. The shielded privacy switches do not select
a transparent PIR policy.

## Validation

The shared-library tests cover zero-value funding records, seed restore, a refund
whose block was already scanned, incoming payments outside the initial window,
close/reopen, and mixed-input spending into ordinary change. Library tests cover
compact scanning and private insertion. Vizor tests verify
that disabling both settings still prepares receiver PIR discovery without queuing
a historical block replay.
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
- Restore the seed into another fresh wallet with a birthday before funding and
  NEAR swap privacy off. Test once with Private queries on and once with it off.
  Confirm both runs use receiver PIR and recover the same notes without duplicates.
  Follow the tip afterward and confirm completed sweeps are not repeated.
- Spend recovered notes together with ordinary funds. Confirm the spend mines and
  the change is found by the ordinary internal key.
- Confirm hardware accounts continue to use their existing address flow.
- Check both settings default off. Enable Private queries, then NEAR swap privacy.
  Restart and confirm both choices persist. Disable Private queries and confirm
  the child stays off after re-enabling the parent.
- Turn NEAR swap privacy off during a pending software swap. Its refund must still
  be found, and its received note must remain spendable.

Passing the automated checks does not substitute for this signed-app exercise.
