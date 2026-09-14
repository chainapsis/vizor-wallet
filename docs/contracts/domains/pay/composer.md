# Pay composer

Read when changing Pay exact-output entry, remembered asset, or retry restoration.

Pay presents ZEC-to-external exact output: the entered amount is the recipient's
payout; the provider computes the required ZEC input.

- Pay entry surfaces: [`pay_screen.dart`](../../../../lib/src/features/pay/screens/pay_screen.dart)
  and [`mobile_pay_screen.dart`](../../../../lib/src/features/pay/screens/mobile/mobile_pay_screen.dart).

`preparePayFromShieldedZec` selects ZEC-to-external exact output, restores the
account's remembered payout asset if supported, and clears amount and recipient.
Pay persists its asset separately from the ordinary Swap pair; slippage is
shared. External-chain changes clear stale recipients when the Pay surface opts
in.

Pay retries restore the original dynamic asset, payout amount, and recipient
only if that asset remains supported.

## Verification

- [`swap_screen_test.dart`](../../../../test/features/swap/swap_screen_test.dart):
  Pay restoration and hardware cancellation.

## Related changes

- When changing amount mode or executable values, read [quote amounts](../../references/swaps/quote-amounts.md).
- When changing Review cancellation or starting a new quote, read [quote validity](../../references/swaps/quote-validity.md).
- When changing software deposits, read [software deposit lifecycle](../../references/swaps/software-deposit.md).
- When changing hardware draft cleanup, read [hardware deposit lifecycle](../../references/swaps/hardware-deposit.md).
