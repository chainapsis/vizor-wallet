# Gift Card bearer payload

Read when changing Gift Card URI format, secret fields, or presentation-only metadata.

A Vizor Gift Card is a bearer payment link containing a generated temporary
wallet's mnemonic in its fragment. Treat its URI and every persisted recovery
record as secrets. Opening or checking a link reserves no funds; the chain
resolves competing claims. ZIP-321 payment requests have separate
[intake and lifetime rules](../payment-requests/intake.md).

- Payload validation: [`vizor_payment_link.dart`](../../../../lib/src/features/payment_links/models/vizor_payment_link.dart).

Version 1 accepts the Vizor payment-link endpoint, a fragment-only `v1=`
payload, supported network, positive amount, recovery phrase, positive birthday
height, valid timestamp, and bounded presentation fields. The fiat snapshot is
display-only, never used in funding or claim math.

## Verification

- [`vizor_payment_link_test.dart`](../../../../test/features/payment_links/vizor_payment_link_test.dart):
  payload rejection and canonical identity.

## Related changes

- When changing link host or platform registration, read [deep-link origin](../../references/navigation/deep-link-origin.md).
- When changing duplicate delivery or queue retention, read [Gift Card intake](intake.md).
