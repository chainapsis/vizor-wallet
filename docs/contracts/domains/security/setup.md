# Wallet security setup

Read when changing the prepare/account-operation/commit transaction or rollback of abandoned wallet setup.

## Setup transaction

- [`AppSecurityNotifier`](../../../../lib/src/providers/app_security_provider.dart)
  separates password setup into `preparePasswordSetup`, account creation/import,
  and `commitPasswordSetup`.

- Prepare validates the password, persists the verifier, and opens the secure
  storage session so the account operation can encrypt its secret. It does not
  yet publish configured/unlocked provider state.

- Commit publishes configured state only for the prepared attempt. If the
  session was locked after preparation, commit must not reopen it.

- Callers abandoning setup before account creation completes use
  `rollbackPasswordSetup`; setup screens own that compensation.

## Verification anchors

- Session races and password rotation:
  [`app_secure_store_session_test.dart`](../../../../test/core/storage/app_secure_store_session_test.dart)

## Related changes

- When changing accepted credentials, preserve [credential policy](../../references/security/credential-policy.md).
- When changing session freshness across setup awaits, read [secret sessions](../../references/storage/secret-sessions.md).
- When changing the intervening account operation, read [account creation/import](../accounts/create-import.md).
