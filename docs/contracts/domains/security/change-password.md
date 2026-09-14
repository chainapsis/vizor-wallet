# Wallet password change

Read when changing encrypted-secret rotation, its migration preflight, or completion after a concurrent lock.

## Rotation transaction

- Password rotation requires an unlocked wallet and a different valid password.
  The migration/password-change preflight must finish before the secure store
  rotates encrypted payloads and updates its verifier.

- Rotation committed after a concurrent lock succeeds durably but must leave
  the provider locked. Storage success must not reopen a newer lifecycle.

## Migration preflight

- Block password change while migration preflight reports unsafe encrypted-state rotation.

## Verification anchors

- Session races and password rotation:
  [`app_secure_store_session_test.dart`](../../../../test/core/storage/app_secure_store_session_test.dart)

## Related changes

- When changing the accepted replacement password, read [credential policy](../../references/security/credential-policy.md).
- When changing encrypted-session ownership, read [secret sessions](../../references/storage/secret-sessions.md).
- When changing unsafe migration state, read [migration lifecycle](../migration/run-lifecycle.md).
