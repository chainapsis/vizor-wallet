# Swap and Pay provider recovery

Read when changing recovery from quote, submission, or provider status errors.

- Domain requests/results: [`swap_provider_contract.dart`](../../../../lib/src/features/swap/domain/swap_provider_contract.dart)
  and [`swap_quote.dart`](../../../../lib/src/features/swap/domain/swap_quote.dart).
- State orchestration: [`swap_state_provider.dart`](../../../../lib/src/features/swap/providers/swap_state_provider.dart).

Post-broadcast provider submission or status failures cannot undo ZEC
transactions and must not trigger automatic second deposits. Track uncertain
broadcasts locally without provider submission until recovery has enough evidence.

Errors are operation-specific: quote failures can request a new quote; status
404 may mean the deposit is not yet indexed; submit 400/404/422 means the provider
rejected the deposit record. Status timeouts and service failures retain the
intent for automatic refresh.

## Verification

- [`swap_failure_policy_test.dart`](../../../../test/features/swap/swap_failure_policy_test.dart):
  operation-specific recovery messages.

## Related changes

- When changing software broadcast checkpoints, read [software deposit lifecycle](software-deposit.md).
- When changing hardware txid retention, read [hardware deposit lifecycle](hardware-deposit.md).
- When changing status transport routing, read [network route policy](../network/route-policy.md).
