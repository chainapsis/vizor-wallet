# Swap and Pay software deposit

Read when changing software ZEC intent start, deposit broadcast, or its local checkpoint.

- Software deposit sender: [`swap_deposit_sender.dart`](../../../../lib/src/features/swap/providers/swap_deposit_sender.dart).

Software start persists/selects the intent before asynchronously sending ZEC.

The sender checkpoints the tx hash and broadcast status before notifying the
provider.

## Verification

- [`swap_screen_test.dart`](../../../../test/features/swap/swap_screen_test.dart):
  persistence and post-broadcast failures.

## Related changes

- When changing deposit amount selection, read [quote amounts](quote-amounts.md).
- When changing post-deposit provider retries, read [provider recovery](provider-recovery.md).
- When changing start expiry or wallet-fee guards, read [quote validity](quote-validity.md).
