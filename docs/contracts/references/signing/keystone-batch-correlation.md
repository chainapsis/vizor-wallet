# Keystone batch correlation

Read when encoding a compact signing QR or accepting a batch signature response.

- Shared Dart batch envelope: [`keystone_batch_signing.dart`](../../../../lib/src/features/keystone/services/keystone_batch_signing.dart).

- For PCZT callers, `preparePcztForKeystoneBatch` produces a redacted signer view and expected
   signature count. Dart binds the request ID, ordered message IDs, and counts
   in a `zcash-sign-batch` UR request.
- Keystone returns `zcash-batch-sig-result`. Dart requires matching request ID,
   message set, and per-message counts before encoding signature blobs.

## Verification

- [`keystone_batch_signing_test.dart`](../../../../test/features/keystone/keystone_batch_signing_test.dart):
  request/message correlation and signature counts.

## Related changes

- When changing allowed PCZT inputs or protocol limits, read [protocol selection](pczt-protocol-selection.md).
- When changing application or final verification of PCZT signatures, read [PCZT finalization](pczt-finalization.md).
