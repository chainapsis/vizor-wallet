# Hardware signing contract

## Scope and entry points

Vizor uses Keystone as a QR-only signer. The phone owns proposal construction,
proof generation, transaction validation, broadcast, and local persistence;
Keystone holds the spending key and returns authorization signatures.

- Shared Dart batch envelope: [`keystone_batch_signing.dart`](../../lib/src/features/keystone/services/keystone_batch_signing.dart).
- Shared mobile QR/scanner state machine:
  [`mobile_keystone_pczt_signing_flow.dart`](../../lib/src/features/keystone/widgets/mobile_keystone_pczt_signing_flow.dart).
- Rust PCZT roles and completion: [`pczt.rs`](../../rust/src/wallet/sync/pczt.rs).
- Send, Swap, and Gift Card adapters live in their respective feature folders.

## Normal signatures-only flow

1. Rust consumes a stored proposal and creates an IO-finalized base PCZT.
2. The phone independently adds Orchard/Ironwood proofs and any required
   Sapling output proofs to its wallet-owned copy.
3. `preparePcztForKeystoneBatch` produces a redacted signer view and expected
   signature count. Dart binds the request ID, ordered message IDs, and counts
   into a `zcash-sign-batch` UR request.
4. Keystone returns `zcash-batch-sig-result`. Dart requires the request ID,
   message set, and per-message counts to match before encoding signature blobs.
5. Rust applies and verifies every compact signature against the wallet-owned
   PCZT, finalizes every transaction, broadcasts in dependency order, and
   persists the accepted or ambiguous prefix.

The compact response carries Orchard and Ironwood spend-authorization
signatures only. It rejects transparent inputs, Sapling spends, a transaction
with no signable action, and more than 96 required signatures before the QR is
shown. Callers surface an actionable smaller-amount or unsupported-input error;
they must not silently switch to a less constrained signing protocol.

## Protocol exceptions

Ordinary Send, ZEC Swap/Pay deposits, and Gift Card funding use the compact
batch flow. Send-to-TEX is the current compatibility exception: it creates two
dependent transactions and uses full redacted PCZTs because the batch response
cannot represent the transparent-input signature. Both rounds must validate,
and round two must spend the exact output from round one.

The Swap hardware adapter rejects a TEX deposit address before proposing; TEX
support in ordinary Send does not imply that Swap/Pay may use that route.
Transparent shielding also retains its full-PCZT path outside these feature
contracts.

Sapling parameters have two consumers. They must be passed to both
`addProofsToPczt` and the final store/broadcast call whenever the PCZT contains
a Sapling bundle. Proof creation needs the local prover, while final validation
and storage need its verifying keys.

## Ownership, cancellation, and errors

PCZT creation consumes the replayable in-memory proposal but deliberately
retains its wallet input lock. Before broadcast ownership transfers, the
feature adapter must discard the draft on cancellation or failure and wait for
confirmed release before allowing another attempt. Once the broadcast service
takes the draft, UI disposal must not race it with a second release.

The shared mobile signing widget owns only presentation and scanning. Its
caller owns PCZT creation, proof work, response decoding, broadcast, and
domain-specific cleanup. "Back to QR code" resets the scanner session. Cancel
leaves the whole signing flow. While `_decoding` is true, both paths are
disabled so the signed callback cannot race navigation.

Rust validates all correlated proof/signature payloads before network or DB
effects. Broadcast happens before persistence, so a definite rejection leaves
the transaction out of the wallet DB. Accepted or ambiguous transactions are
persisted for recovery. If rich PCZT-aware storage fails after broadcast, Rust
uses its transaction fallback where possible and returns an explicit
post-broadcast storage status rather than inviting a blind resend.

## Domain-specific additions

- Send transfers signed payload ownership to its status route; see
  [send](send.md).
- Swap/Pay clears its draft reference before awaiting network I/O and records a
  txid even for an uncertain broadcast so provider status can recover; see
  [Swap and Pay](swap-pay.md).
- Gift Card funding persists the bearer-secret draft before proposing and its
  prepared txid/expiry before broadcast; see [payment links](payment-links.md).

## Verification map

- [`keystone_batch_signing_test.dart`](../../test/features/keystone/keystone_batch_signing_test.dart):
  request/message correlation and signature counts.
- [`mobile_keystone_pczt_signing_flow_test.dart`](../../test/features/keystone/mobile_keystone_pczt_signing_flow_test.dart):
  scan recovery, cancel, and finalization guards.
- Rust tests in [`pczt.rs`](../../rust/src/wallet/sync/pczt.rs): signature caps,
  compact/full equivalence, correlation, TEX dependencies, expiry, and
  broadcast/store outcomes.
- Feature tests under
  [`test/features/send`](../../test/features/send),
  [`test/features/swap`](../../test/features/swap), and
  [`test/features/payment_links`](../../test/features/payment_links) pin each
  adapter's ownership and navigation behavior.
