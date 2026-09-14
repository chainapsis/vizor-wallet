# Send proposal ownership

Read when creating or handing off a Send/Donation proposal or changing its account and flow identity.

Shared proposal ownership, Review/signing handoff, and broadcast execution for
[Send](../../domains/send/index.md) and [Donation](../../domains/donation/index.md). Each domain owns its inputs and
navigation. [Shielding](../../domains/shielding/flow.md), [Swap/Pay](../swaps/index.md), and
[Gift Cards](../../domains/gift-cards/index.md) have separate execution adapters; do not assume
that every spend uses these Dart helpers.

- Dart orchestration: [`send_flow.dart`](../../../../lib/src/features/send/services/send_flow.dart)
  (`SendReviewArgs`, `proposeSendTransfer`, `discardSendProposal`, `runSendBroadcast`).

`proposeSendTransfer` waits for authoritative spendable state, creates a Rust
proposal, and returns `proposalId`, `sendFlowId`, proposal account, amount, fee,
address type, and Sapling-parameter requirement. Keep its account and both IDs
together through review, signing, cleanup, and status; the active account can
change independently.

Rust stores proposals in memory and locks selected wallet inputs in SQLite.
Software execution and PCZT creation consume the proposal on entry; its
owner-scoped input lock remains until completion or explicit cleanup.

## Verification

- [`send_proposal_release_test.dart`](../../../../test/features/send/send_proposal_release_test.dart):
  retry, refresh, owner identity, and lock-release behavior.

## Related changes

- When changing cancellation or cleanup results, read [proposal release](proposal-release.md).
- When changing authoritative spendable gating, read [account balances](../sync/account-balances.md).
