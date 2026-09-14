# Send proposal release

Read when changing cancellation, cleanup retry, or the release result used to permit another send.

- Dart orchestration: [`send_flow.dart`](../../../../lib/src/features/send/services/send_flow.dart)
  (`SendReviewArgs`, `proposeSendTransfer`, `discardSendProposal`, `runSendBroadcast`).

Every exit before execution takes ownership must call idempotent
`discardSendProposal`: retry Rust release three times, then refresh the proposal
account's balance. `true` confirms both completed. `false` must keep send retry
unavailable; discard itself can be retried, with height expiry as the final
lock-release fallback.

## Verification

- [`send_proposal_release_test.dart`](../../../../test/features/send/send_proposal_release_test.dart):
  retry, refresh, owner identity, and lock-release behavior.

## Related changes

- When changing which proposal or account is released, read [proposal ownership](proposal-ownership.md).
- When changing refresh internals or coalescing, read [account balances](../sync/account-balances.md).
- When changing mobile request-card handoff, read its exception in [request-card handoff](../../domains/payment-requests/card-handoff.md).
