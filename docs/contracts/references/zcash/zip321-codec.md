# ZIP-321 codec

Read when changing request parsing, URI generation, or wire-level amount and memo rules.

- Syntax: [`zip321_payment_request.dart`](../../../../lib/src/core/zcash/zip321_payment_request.dart)
  and [`zip321_payment_request_builder.dart`](../../../../lib/src/core/zcash/zip321_payment_request_builder.dart).

- Bound input to 16,384 UTF-8 bytes. Reject duplicate recognized parameters,
  unknown required parameters, malformed encoding, and a memo on a transparent
  address. Address syntax alone is not network validation; precheck asks Rust
  using the currently selected endpoint's network.

Memos are unpadded base64url, at most 512 UTF-8 bytes, and readable by anyone
with the link. Builder output must round-trip through the parser without
changing its payment.

## Verification

- [`zip321_payment_request_builder_test.dart`](../../../../test/core/zcash/zip321_payment_request_builder_test.dart)
  and [`zip321_payment_request_test.dart`](../../../../test/features/send/zip321_payment_request_test.dart):
  memo rules and parser/builder round-trips. Choose the parser or builder tests
  for the changed direction; see [Test execution](../../guides/testing.md) for commands.

## Related changes

- When changing product acceptance or invalid-link messages, read [request intake](../../domains/payment-requests/intake.md).
- When changing local amount snapshots or draft sanitization, read [Receive request draft](../../domains/receive/request-draft.md).
