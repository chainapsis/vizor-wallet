# Send navigation and mobile cancellation

Read when changing Send Review exits or mobile signing cancellation.

- Desktop Review: [`send_review_screen.dart`](../../../../lib/src/features/send/screens/send_review_screen.dart).
- Mobile composer and Review: [`mobile_send_screen.dart`](../../../../lib/src/features/send/screens/mobile/mobile_send_screen.dart).

- Desktop Review cancel releases the proposal before returning to `/send`.
- Mobile Keystone cancel returns a null signing result. The composer preserves
  its recipient, amount, memo, contact, and review step, waits for release and
  balance refresh, invalidates Max and fee snapshots, then refreshes the review
  fee before Confirm becomes available.

## Verification

- [`send_review_screen_test.dart`](../../../../test/features/send/send_review_screen_test.dart):
  desktop cancellation, re-proposal, disposal, and status handoff.
- [`mobile_send_screen_test.dart`](../../../../test/features/send/mobile_send_screen_test.dart):
  preserved review inputs, cancellation ordering, refreshed fees, and busy surfaces.

## Related changes

- When changing desktop Keystone recovery or status handoff, read [desktop Review recovery](../../references/signing/desktop-review-recovery.md).
- When changing proposal cleanup, read [proposal release](../../references/transactions/proposal-release.md).
