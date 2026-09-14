# Payment URI busy holds

Read when changing the points where active wallet work blocks or resumes incoming payment-request delivery.

- Parking and routing: [`payment_uri_prefill_provider.dart`](../../../../lib/src/providers/payment_uri_prefill_provider.dart)
  and [`payment_uri_drain_policy.dart`](../../../../lib/src/core/navigation/payment_uri_drain_policy.dart).

- Hold delivery while a busy surface is mounted or another proposal owns inputs,
  or while a broadcast runs on `/send/status`. Route location alone does not
  block a draft without a proposal. Resume after the hold ends, within the TTL.

Review and signing hold payment-URI intake until after proposal release, so a
parked request cannot pre-check or propose against the abandoned send's inputs.

## Verification

- [`payment_uri_drain_policy_test.dart`](../../../../test/core/navigation/payment_uri_drain_policy_test.dart):
  busy holds and route/proposal delivery policy.

- [`send_review_screen_test.dart`](../../../../test/features/send/send_review_screen_test.dart):
  proposal release and Review/signing handoff.

## Related changes

- When changing release success, read [proposal release](../transactions/proposal-release.md).
- When changing parked-request expiry or lock/reset retention, read [request intake](../../domains/payment-requests/intake.md).
