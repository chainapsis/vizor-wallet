# Swap and Pay quote amounts

Read when changing quote mode, amount asset, precision, or executable deposit values.

- Domain requests/results: [`swap_provider_contract.dart`](../../../../lib/src/features/swap/domain/swap_provider_contract.dart)
  and [`swap_quote.dart`](../../../../lib/src/features/swap/domain/swap_quote.dart).

`SwapQuoteRequest.amountAsset` is the sell asset for input modes and the
receive asset for exact output. Do not read `sellAmount` for an exact-output
request. Preserve provider base units and precise text; UI rounding, fiat labels,
and parsed doubles are not executable deposit amounts.

The deposit amount comes only from positive `sellAmountBaseUnits`.

## Verification

- [`swap_contract_test.dart`](../../../../test/features/swap/swap_contract_test.dart)
  and [`swap_provider_contract_test.dart`](../../../../test/features/swap/swap_provider_contract_test.dart):
  request and domain semantics.
- [`swap_deposit_amount_test.dart`](../../../../test/features/swap/swap_deposit_amount_test.dart):
  base-unit execution and display disagreement.

## Related changes

- When changing quote lifetime or invalidation, read [quote validity](quote-validity.md).
