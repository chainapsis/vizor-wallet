# Gift Card claim outcomes

A claim's transaction lifecycle and a card's availability are separate. Opening
or checking a link does not reserve its funds. Competition is settled by the
chain, not by the order of taps in Vizor.

- Empty history or balance is not proof of a failed broadcast or an external
  claim. Saved bearer links remain in secure storage.
- A server rejection is distinct from an unknown response, but neither proves
  that every server rejected the transaction. Pending and partially submitted
  claims remain protected until every transaction is terminal: expired,
  conflicted with a spend covered by six scanned confirmations, or itself
  covered by six scanned confirmations. Mixed outcomes settle as failed only
  when at least one leg failed.
- A card is labelled `Already claimed` only when all its observed shielded
  outputs have settled spends outside its locally created/recorded claims.
  Unspent positive-value top-ups prevent that conclusion; zero-value change
  outputs do not represent remaining funds. Pending scan ranges limit the
  confirmation height. `sent_notes` plus the local `transactions.created`
  marker identifies transactions eligible for metadata recovery. OVK-recovered
  outgoing notes alone cannot distinguish competitors sharing the card's keys.
  Each attempt persists the prior
  local transaction IDs before submission, so restart recovery includes failed
  legs and excludes older attempts.
- `Check status` scans without retransmitting. Foreground background recovery
  may retry eligible transactions; confirmed input conflicts are excluded even
  after restart. A cancelled scan cannot produce a completed status check.
- Failed claims return to a `Claim failed` state, not an unconditional `Claim`.
  A new claim always prepares again. Settling a transaction compares the recorded
  attempt before writing so a late check cannot overwrite a newer submission.
  Manual/background checks serialize; recovery skips live submissions.
- Only active claims count toward account-deletion protection. A settled failed
  claim clears the destination binding while retaining the bearer link. Hiding
  a card changes only its visibility; archived cards can be restored. Active
  claims cannot be hidden.

## Existing development data

The three outcome fields are optional when reading older records from
`zcash_gift_card_received_v1` (payload version remains 1):

- Missing/null `availability` defaults to `unchecked` for ready cards,
  `checking` for submitting cards, and `available` for receiving/received cards
  (their existing transaction lifecycle still controls the displayed status).
- Missing/null `archived` defaults to `false`.
- Missing/null `claimPriorTxids` remains **unknown**, distinct from a known empty
  list. Loading, copying, and saving the card must preserve that distinction.
  Starting a new claim captures a fresh baseline before submission.

Existing ready cards can be checked and claimed normally. Existing receiving
cards with saved claim transaction IDs continue receipt/reorg recovery without
requiring the baseline. An old `submitting` card with neither transaction IDs
nor a baseline remains `Checking result`: automatic/manual checks do not adopt
older transactions, retransmit them, or release account-deletion protection.
Its bearer link and retained claim database remain available for manual
investigation. Adding an empty baseline by hand is not a safe recovery step.

No reset is needed solely because these three fields are absent. Present but
malformed fields still fail decoding. This is not a general migration for older
incompatible formats: the existing timestamp, transaction-ID, link, and other
record validations remain in force.

For developers switching branches: an older app may discard new fields when it
writes records. This version can read the result, but cannot recover lost archive
or outcome metadata; a lost submitting baseline again requires manual review.
Keep separate development data or backups when switching versions. This change
does not make older apps understand the new statuses, or remove the requirement
to rebuild Dart and Rust together for the preceding FRB changes. No additional
Rust API or database schema change is introduced by optional-field support.

The separate sender-side ambiguous draft export/account-deletion flow remains
outside this change.

## Validation

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
