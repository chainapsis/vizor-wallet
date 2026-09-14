# Send composer

Read when changing ordinary Send amount entry or fee validation.

Ordinary desktop/mobile transfers to a recipient: amount and fee validation.

- Desktop composer: [`send_screen.dart`](../../../../lib/src/features/send/screens/send_screen.dart).
- Mobile composer and Review: [`mobile_send_screen.dart`](../../../../lib/src/features/send/screens/mobile/mobile_send_screen.dart).

- Parse decimal input with
  [`parseZecAmount`](../../../../lib/src/core/formatting/zec_amount.dart) into integer
  zatoshi (`BigInt`), accepting at most eight fractional digits. Never execute
  amounts derived from floating-point values or rounded display text.
- Desktop/mobile composers estimate fees on input changes and reject stale
  estimates by input generation. Validate amount plus fee against usable
  spendable funds before Review; Rust proposal creation is the final authority.

## Verification

- [`mobile_send_screen_test.dart`](../../../../test/features/send/mobile_send_screen_test.dart):
  preserved review inputs, cancellation ordering, refreshed fees, and busy surfaces.

## Related changes

- When changing proposal creation, read [proposal ownership](../../references/transactions/proposal-ownership.md).
- When changing request-prefilled values, read [request-card handoff](../payment-requests/card-handoff.md).
