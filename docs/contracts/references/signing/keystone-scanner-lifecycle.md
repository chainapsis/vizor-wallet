# Keystone scanner lifecycle

Read when changing the shared signing widget, scanner Back/Cancel, or finalization guards.

- Shared mobile QR/scanner state machine:
  [`mobile_keystone_pczt_signing_flow.dart`](../../../../lib/src/features/keystone/widgets/mobile_keystone_pczt_signing_flow.dart).

The shared mobile signing widget owns only presentation and scanning; its caller
owns PCZT creation, proofs, response decoding, broadcast, and domain cleanup.
"Back to QR code" resets the scanner session; Cancel exits signing. The reset leaves the send intact. Both actions are disabled during signature
decoding (`_decoding`) or finalization to prevent signed callbacks racing navigation.

## Verification

- [`mobile_keystone_pczt_signing_flow_test.dart`](../../../../test/features/keystone/mobile_keystone_pczt_signing_flow_test.dart):
  scan recovery, cancel, and finalization guards.

## Related changes

- When changing compact response correlation, read [batch correlation](keystone-batch-correlation.md).
