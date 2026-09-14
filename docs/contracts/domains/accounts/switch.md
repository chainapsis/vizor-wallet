# Account switching

Read when changing active-account selection, address publication, or account-scoped refresh after a switch.

## Secret ownership

- Switching accounts invalidates pending secret operations before resolving the
  new address. An older secure-storage session's completion must not publish an
  address into the current session.

## Active refresh target

- Account switching changes the active target and refreshes account-scoped state
  without restarting the wallet-wide Rust scan.

## Verification anchors

- Account/session behavior:
  [`account_metadata_session_test.dart`](../../../../test/providers/account_metadata_session_test.dart)

## Related changes

- When changing late secret reads across a switch, read [secret sessions](../../references/storage/secret-sessions.md).
- When changing the account-switch cache or refreshed balances, read [account balances](../../references/sync/account-balances.md).
