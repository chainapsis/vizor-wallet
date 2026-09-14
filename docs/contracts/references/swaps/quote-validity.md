# Swap and Pay quote validity

Read when changing Review snapshots, quote invalidation, deadlines, or start guards.

- State orchestration: [`swap_state_provider.dart`](../../../../lib/src/features/swap/providers/swap_state_provider.dart).

`showReview` captures the active account, direction, mode, amount, destination,
and a fresh ZEC staging address. Generation and account checks keep stale quotes
from replacing a newer composer or another account's review. Amount, asset,
direction, destination, or slippage changes clear review.

The action deadline is provider quote expiry minus five seconds; deposit-only
deadlines have no start buffer. `startIntent` rechecks time, review account, and
the in-flight flag; the countdown is only presentation. Expiry leaves Review
visible for refresh; account mismatch invalidates it.

ZEC-outgoing routes require a successful live wallet fee estimate before provider
`startSwap`; failure creates no intent or deposit broadcast.

Normal Pay or Swap review cancel clears the quote and returns to the composer.
Starting either flow clears composer inputs. The next Review always obtains a
new quote.

## Verification

- [`swap_screen_test.dart`](../../../../test/features/swap/swap_screen_test.dart):
  expiry gates and account races.
- [`mobile_pay_review_screen_test.dart`](../../../../test/features/pay/mobile_pay_review_screen_test.dart):
  mobile review expiry.

## Related changes

- When changing executable amounts, read [quote amounts](quote-amounts.md).
- When changing hardware signing cancellation after start, read [hardware deposit lifecycle](hardware-deposit.md).
