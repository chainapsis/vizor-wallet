# Gift Card intake

Read when changing Gift Card queue identity, capacity, reset retention, or delivery deferral.

- Incoming queue: [`payment_link_intake_provider.dart`](../../../../lib/src/features/payment_links/providers/payment_link_intake_provider.dart).

Incoming links use a 16-item in-memory FIFO without expiry, surviving wallet
reset because they claim funds outside this wallet. Identical canonical payloads
coalesce; matching account/birthday alone does not establish duplicates.
Malformed or overflow links never clear a queued bearer secret. Defer navigation
during onboarding, unlock-sensitive tasks, Send, Swap, Pay, migration, voting,
and a live ZIP-321 request card.

## Verification

- [`payment_link_intake_provider_test.dart`](../../../../test/features/payment_links/payment_link_intake_provider_test.dart):
  canonical identity, FIFO, and capacity.

## Related changes

- When changing canonical payload validation, read [Gift Card bearer payload](payload.md).
- When changing incoming origin classification, read [deep-link origin](../../references/navigation/deep-link-origin.md).
