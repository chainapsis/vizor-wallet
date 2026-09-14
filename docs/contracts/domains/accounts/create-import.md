# Account creation and import

Read when changing account creation/import entry behavior, birthday selection, or persisted network selection.

## Creation and import

- Correct recovery depends on birthday selection. Fresh creation requires a
  current lightwalletd height; import may use a caller-supplied birthday or
  discovery.

- Persist the network when the first account succeeds. Existing-wallet imports
  use the wallet's stored network rather than a newly selected endpoint network.

## Verification anchors

- Account removal/reset surfaces:
  [`account_provider_test.dart`](../../../../test/providers/account_provider_test.dart)

- Rust account deletion and scan-range repair:
  tests beside [`wallet/keys.rs`](../../../../rust/src/wallet/keys.rs)

## Related changes

- Before changing first/additional account or Keystone import behavior, read [account model](../../references/accounts/account-model.md).
- When setup also configures a password, preserve [setup ordering](../security/setup.md).
- When changing mutation pause or resume around an import, read [mutation barrier](../../references/wallet/mutation-barrier.md).
