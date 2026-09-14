# Swap and Pay hardware deposit

Read when changing pending Keystone intents, signing cancellation, or broadcast handoff to activity.

- Hardware deposit adapter: [`swap_hardware_signing_service.dart`](../../../../lib/src/features/swap/providers/swap_hardware_signing_service.dart).

Hardware ZEC start creates a pending signing intent outside persisted activity.
The signing route creates a fresh send proposal/PCZT from the intent's base-unit
amount. Normal Swap/Pay deposits use compact Keystone batches and reject TEX
deposit addresses.

Signing cancellation finishes draft cleanup before navigation, drops the pending
intent, and leaves composer inputs cleared; users must compose and quote again.
For any usable broadcast txid, `recordKeystoneDepositBroadcast` persists the
intent in activity and records broadcast status. Success opens Pay's submitted
screen or Swap's activity detail.

Swap/Pay clears its draft reference before awaiting network I/O and records
even an uncertain broadcast's txid for provider status recovery.

## Verification

- [`swap_screen_test.dart`](../../../../test/features/swap/swap_screen_test.dart):
  hardware cancellation.
- [`mobile_swap_keystone_signing_test.dart`](../../../../test/features/swap/mobile_swap_keystone_signing_test.dart):
  mobile signing routes.

## Related changes

- When changing amount interpretation, read [quote amounts](quote-amounts.md).
- When changing provider start or wallet-fee guards, read [quote validity](quote-validity.md).
- When changing PCZT input support, read [protocol selection](../signing/pczt-protocol-selection.md).
- When changing signature validation or broadcast/store ordering, read [PCZT finalization](../signing/pczt-finalization.md).
- When changing post-broadcast provider retry, read [provider recovery](provider-recovery.md).
