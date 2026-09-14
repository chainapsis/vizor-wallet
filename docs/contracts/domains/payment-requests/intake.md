# Payment request intake

Read when changing supported incoming requests, parking, expiry, or delivery holds.

ZIP-321 `zcash:` requests ask the current wallet to pay a recipient. Receive
creates those requests; incoming links and scanned requests enter a payment
card before Send. A card may reserve inputs by proposing, but never broadcasts.
Gift Cards claim funds elsewhere and retain their separate [intake contract](../gift-cards/intake.md).

- Parking and routing: [`payment_uri_prefill_provider.dart`](../../../../lib/src/providers/payment_uri_prefill_provider.dart)
  and [`payment_uri_drain_policy.dart`](../../../../lib/src/core/navigation/payment_uri_drain_policy.dart).

- Accept one recipient, optional ZEC amount, text memo, and requester context. Parsing
  can recognize multiple recipients, binary memos, and custom assets, but intake
  refuses them as unsupported. Malformed requests get a distinct invalid-link
  message; parser diagnostics must not become user-facing copy.

- Keep one in-memory prefill: latest wins, including duplicate deliveries.
  Replacing a parked or visible request is disclosed. A prefill older than ten
  minutes is dropped with an expiry message; exactly ten minutes is still fresh.
  `takeIfFresh` claims and clears atomically, including expired entries.
- Wallet reset silently drops the parked spending request. Gift Cards instead
  use a FIFO without expiry and survive reset; do not merge the stores.
- Drain age first, then storage/wallet failures. Wait while wallet existence is
  loading; drop during onboarding/import/add-account without interrupting setup.
  With no wallet outside setup, route to Welcome and explain the requirement.
- Locked wallets keep the prefill through Unlock. Even after unlocking, the
  unlock screen owns its claim until it leaves `/unlock`. Evaluate the migration
  send gate only after this boundary; lock-cleared balances are not gate evidence.
- Otherwise present the card over the current screen. Merely opening or
  dismissing it must not replace the underlying route or its draft.

## Verification

- [`payment_uri_prefill_provider_test.dart`](../../../../test/core/navigation/payment_uri_prefill_provider_test.dart),
  [`payment_uri_drain_policy_test.dart`](../../../../test/core/navigation/payment_uri_drain_policy_test.dart),
  and [`payment_uri_migration_gate_test.dart`](../../../../test/core/navigation/payment_uri_migration_gate_test.dart): parking, TTL, holds, and unlock gating.

## Related changes

- When changing URI parsing, read [ZIP-321 codec](../../references/zcash/zip321-codec.md).
- When changing card proposals or asynchronous navigation, read [request-card handoff](card-handoff.md).
- When changing delivery holds around active wallet work, read [payment URI busy holds](../../references/navigation/payment-uri-holds.md).
