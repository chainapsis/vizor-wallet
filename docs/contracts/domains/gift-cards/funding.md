# Gift Card funding and sender recovery

Read when changing Gift Card funding quotes, recovery drafts, sharing, or cancellation.

- Funding and claim orchestration: [`payment_link_service.dart`](../../../../lib/src/features/payment_links/services/payment_link_service.dart).
- Sender and receiver persistence: [`payment_link_recovery_store.dart`](../../../../lib/src/features/payment_links/services/payment_link_recovery_store.dart)
  and [`payment_link_received_store.dart`](../../../../lib/src/features/payment_links/services/payment_link_received_store.dart).

Funding sends the requested amount plus a fixed claim-fee reserve to one new
shielded account. Quotes separate recipient amount, funding fee, and
claim reserve. Persist the link's recovery draft before proposing, before any proposal
crosses the signing/broadcast boundary.

Software funding records submission start before broadcast. Hardware funding
also records the prepared txid and expiry after proofs, before broadcast and before showing completion.
Failures retain drafts once submission may have started, as retrying could
duplicate value. Funded cards stay protected until marked shared; source-account
deletion checks unshared funded cards. After an uncertain hardware response,
sharing requires sufficient mined evidence.

Keystone funding follows [hardware signing](../../references/signing/pczt-protocol-selection.md). Cancellation
must release the proposal before removing an unbroadcast draft. Proposal release
or authoritative balance-refresh failures keep cancellation/retry incomplete.
Draft removal is best-effort: failure retains the record but alone does not block
returning to Review.

## Verification

- [`payment_link_service_test.dart`](../../../../test/features/payment_links/payment_link_service_test.dart):
  funding boundaries and retained recovery drafts.

## Related changes

- When changing PCZT proofs or finalization, read [PCZT finalization](../../references/signing/pczt-finalization.md).
- When changing source-account deletion protections, read [account deletion](../accounts/delete.md).
- When changing secret persistence, read [secret sessions](../../references/storage/secret-sessions.md).
