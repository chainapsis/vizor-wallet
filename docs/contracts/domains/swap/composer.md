# Swap composer

Read when changing ordinary Swap composition or returning from Review.

Swap and Pay share `SwapNotifier`, the NEAR Intents provider contract, deposit
sending, activity persistence, and status recovery.

- State orchestration: [`swap_state_provider.dart`](../../../../lib/src/features/swap/providers/swap_state_provider.dart).

## Related changes

- When changing amount mode or executable values, read [quote amounts](../../references/swaps/quote-amounts.md).
- When changing Review creation, cancellation, or expiry, read [quote validity](../../references/swaps/quote-validity.md).
- When changing software deposits, read [software deposit lifecycle](../../references/swaps/software-deposit.md).
- When changing Keystone deposits, read [hardware deposit lifecycle](../../references/swaps/hardware-deposit.md).
