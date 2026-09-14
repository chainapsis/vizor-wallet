# Donation Review and status

Read when changing Donation Review, cancellation, or status presentation.

[`SendReviewScreen`](../../../../lib/src/features/send/screens/send_review_screen.dart)
selects Donation presentation from `flowKind`.

- Review shows **Review Amount**, the Vizor recipient, and **Confirm donation**
  or **Confirm with Keystone**. The dedicated Donation review has no generic
  Cancel button. **Support Vizor** goes back to the existing composer when it
  can pop, otherwise to `/donation`, after the shared release boundary succeeds.
- While Keystone signing is open, Back cancels signing and recovers Review
  rather than leaving Donation. Preserve the shared
  [Keystone review recovery rules](../../references/signing/desktop-review-recovery.md).
- Confirmation uses the shared status route and retains the donation flow kind.
  Compose, Review, Keystone scanning, and status suppress sidebar selection.
  Pending/failure status keeps the Vizor recipient and Donation wording;
  success shows the dedicated thank-you view. Done and status Back go to `/home`,
  clearing the retained status route payload.

## Related changes

- When changing execution outcomes, read [Send broadcast outcomes](../../references/transactions/send-broadcast.md).
- When changing exit cleanup, read [proposal release](../../references/transactions/proposal-release.md).
