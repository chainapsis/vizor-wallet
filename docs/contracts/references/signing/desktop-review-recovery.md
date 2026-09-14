# Desktop Review recovery and status handoff

Read when changing shared Send/Donation Review signing cancellation or transfer to status.

- Shared desktop Review: [`send_review_screen.dart`](../../../../lib/src/features/send/screens/send_review_screen.dart).

- Software Send passes `SendReviewArgs` to the status route for execution and
  broadcast.
- Hardware Send creates and proves PCZTs, obtains Keystone signatures, and
  passes `KeystoneBroadcastArgs` to status. A signature is not a broadcast receipt.
- Desktop Keystone cancel releases and refreshes, then reproposes the same
  address, amount, memo, request framing, and `sendFlowId`. The user remains on
  Review with a fresh fee and proposal. Failed recovery leaves Review inactive
  with cancellation available again.


## Verification

- [`send_review_screen_test.dart`](../../../../test/features/send/send_review_screen_test.dart):
  cancellation, re-proposal, disposal, and status handoff.

## Related changes

- When changing release success or retry, read [proposal release](../transactions/proposal-release.md).
- When changing scanner Back/Cancel guards, read [Keystone scanner lifecycle](keystone-scanner-lifecycle.md).
- When changing status execution, read [Send broadcast outcomes](../transactions/send-broadcast.md).
- When changing delivery holds around active wallet work, read [payment URI busy holds](../navigation/payment-uri-holds.md).
