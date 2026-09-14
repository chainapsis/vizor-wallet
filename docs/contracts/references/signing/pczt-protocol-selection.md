# PCZT protocol selection

Read when choosing compact batches or full PCZTs, or changing supported signing inputs.

Keystone is a QR-only signer holding the spending key and returning
authorization signatures. Vizor owns proposal construction, proof
generation, transaction validation, broadcast, and local persistence.

- Rust PCZT roles and completion: [`pczt.rs`](../../../../rust/src/wallet/sync/pczt.rs).

The compact response carries only Orchard and Ironwood spend-authorization
signatures. Before showing QR, reject transparent inputs, Sapling spends,
transactions without signable actions, and more than 96 required signatures.
Callers must surface actionable smaller-amount or unsupported-input errors,
never silently switch to a less constrained protocol.

Ordinary Send, ZEC Swap/Pay deposits, and Gift Card funding use compact batches.
Send-to-TEX is the current compatibility exception: its two dependent
transactions use full redacted PCZTs because batch responses cannot represent
transparent-input signatures. Both rounds must validate; round two must spend
round one's exact output.

The Swap hardware adapter rejects TEX deposit addresses before proposing;
ordinary Send's TEX support does not extend to Swap/Pay.
[Transparent shielding](../../domains/shielding/flow.md) retains its full-PCZT path.

## Verification

- Rust tests in [`pczt.rs`](../../../../rust/src/wallet/sync/pczt.rs): signature caps,
  compact/full equivalence, TEX dependencies, and expiry.

## Related changes

- When changing compact QR envelopes, read [batch correlation](keystone-batch-correlation.md).
- When changing proof parameters or finalization, read [PCZT finalization](pczt-finalization.md).
