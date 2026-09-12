# Swap and Pay contract

## Scope and entry points

Swap and Pay share `SwapNotifier`, the NEAR Intents provider contract, deposit
sending, activity persistence, and status recovery. Pay is the ZEC-to-external
exact-output presentation: the entered amount is the recipient's payout, while
the provider computes the required ZEC input.

- Domain requests/results: [`swap_provider_contract.dart`](../../lib/src/features/swap/domain/swap_provider_contract.dart)
  and [`swap_quote.dart`](../../lib/src/features/swap/domain/swap_quote.dart).
- State orchestration: [`swap_state_provider.dart`](../../lib/src/features/swap/providers/swap_state_provider.dart).
- Software deposit sender: [`swap_deposit_sender.dart`](../../lib/src/features/swap/providers/swap_deposit_sender.dart).
- Hardware deposit adapter: [`swap_hardware_signing_service.dart`](../../lib/src/features/swap/providers/swap_hardware_signing_service.dart).
- Pay entry surfaces: [`pay_screen.dart`](../../lib/src/features/pay/screens/pay_screen.dart)
  and [`mobile_pay_screen.dart`](../../lib/src/features/pay/screens/mobile/mobile_pay_screen.dart).

## Quote inputs and review validity

`SwapQuoteRequest.amountAsset` is the sell asset for input modes and the
receive asset for exact output. Do not read `sellAmount` for an exact-output
request. Preserve provider-supplied base units and precise text: UI rounding,
fiat labels, and parsed doubles are not executable deposit amounts.

`showReview` captures the active account, direction, mode, amount, destination,
and a newly prepared ZEC staging address. Generation and account checks prevent
a stale quote from replacing a newer composer or another account's review.
Changing an amount, asset, direction, destination, or slippage clears review.

The action deadline is provider quote expiry minus a five-second start buffer;
a deposit-only deadline has no extra subtraction. `startIntent` rechecks time,
the review account, and the in-flight flag. The countdown is presentation, not
the authority. Expiry leaves Review visible for refresh; an account mismatch
invalidates it.

## Starting and depositing

For ZEC-outgoing routes, a live wallet fee estimate succeeds before provider
`startSwap`. Failure creates no provider intent and broadcasts no deposit.
Software start then persists/selects the intent before asynchronously sending
the ZEC deposit. The deposit amount comes only from positive
`sellAmountBaseUnits`.

The sender checkpoints a tx hash and broadcast status before notifying the
provider. A provider submission or status failure after broadcast cannot undo
the ZEC transaction and must not trigger an automatic second deposit. An
uncertain broadcast remains locally tracked and skips provider submission until
recovery has enough evidence.

Status errors are operation-specific. Quote failures can ask for a new quote;
status 404 means the deposit may not be indexed yet; submit 400/404/422 means
the provider rejected the deposit record. Status timeouts and service failures
retain the intent for automatic refresh.

## Pay-specific state

`preparePayFromShieldedZec` selects ZEC-to-external exact output, restores the
account's remembered payout asset when supported, and clears amount and
recipient state. Pay persists its asset separately from the ordinary Swap pair;
slippage is shared. Changing to another external chain clears a stale recipient
when the Pay surface opts into that behavior.

Retries from Pay restore the original dynamic asset, payout amount, and
recipient only when that asset remains supported. A normal Pay or Swap review
cancel clears the quote and returns to its composer. Starting either flow clears
composer inputs. The next Review always obtains a new quote.

## Keystone deposits and cancellation

Hardware ZEC start creates a pending signing intent but does not add it to
persisted activity. The signing route creates a fresh send proposal/PCZT using
the intent's base-unit amount. Normal Swap/Pay deposits use the compact Keystone
batch protocol and reject TEX deposit addresses.

If signing is cancelled, draft cleanup finishes before navigation. The pending
intent is dropped, composer inputs remain cleared, and the user must compose and
quote again. If broadcast returns any usable txid, `recordKeystoneDepositBroadcast`
promotes the intent into persisted activity and records the broadcast status;
success navigates Pay to its submitted screen and Swap to activity detail.

## Verification map

- [`swap_contract_test.dart`](../../test/features/swap/swap_contract_test.dart)
  and [`swap_provider_contract_test.dart`](../../test/features/swap/swap_provider_contract_test.dart):
  request and domain semantics.
- [`swap_deposit_amount_test.dart`](../../test/features/swap/swap_deposit_amount_test.dart):
  base-unit execution and display disagreement.
- [`swap_screen_test.dart`](../../test/features/swap/swap_screen_test.dart):
  expiry gates, account races, persistence, post-broadcast failures, Pay
  restoration, and hardware cancellation.
- [`swap_failure_policy_test.dart`](../../test/features/swap/swap_failure_policy_test.dart):
  operation-specific recovery messages.
- [`mobile_swap_keystone_signing_test.dart`](../../test/features/swap/mobile_swap_keystone_signing_test.dart)
  and [`mobile_pay_review_screen_test.dart`](../../test/features/pay/mobile_pay_review_screen_test.dart):
  mobile signing routes and review expiry.

See [hardware signing](hardware-signing.md) for the shared PCZT boundary and
[sync/network](sync-network.md) for endpoint and status-refresh behavior.
