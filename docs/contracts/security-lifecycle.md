# Security lifecycle contract

## Scope

Use this contract for wallet password setup, mobile passcodes, unlock,
confirmation, password rotation, lock, reset, and secret-session invalidation.
Account persistence is in [account-storage.md](account-storage.md); downstream
sync clearing and recovery are in [lock-sync.md](lock-sync.md).

## Credential policy

- Desktop wallet passwords accept only printable ASCII bytes `0x21` through
  `0x7e` and have an eight-character minimum.
- Do not normalize IME or keyboard-layout input. Password comparison uses the
  exact submitted string.
- Reuse `validateRequiredWalletPassword` from
  [`password_policy.dart`](../../lib/src/core/security/password_policy.dart).
  The charset message remains `Use only English letters, numbers, and symbols.`
- Mobile uses exactly six digits in its passcode UI. The digit string is still
  the wallet password stored through the same security provider and secure-store
  path; there is no second credential model.
- The mobile keypad help action that resets a forgotten wallet belongs only to
  the app-start `/unlock` surface.

## Setup transaction

- [`AppSecurityNotifier`](../../lib/src/providers/app_security_provider.dart)
  separates password setup into `preparePasswordSetup`, account creation/import,
  and `commitPasswordSetup`.
- Prepare validates the password, persists the verifier, and opens the secure
  storage session so the following account operation can encrypt its secret.
  It does not publish configured/unlocked provider state yet.
- Commit publishes configured state only for the prepared attempt. If the
  session was locked after preparation, commit must not reopen it.
- A caller that abandons setup before account creation completes uses
  `rollbackPasswordSetup`; setup screens own that compensation path.

## Session generations

- `AppSecureStore.sessionGeneration` is the authority for secret-operation
  freshness on platforms that enforce it. Opening, clearing, or explicitly
  invalidating the session changes the generation.
- Security provider request generations decide which unlock or confirmation is
  latest. Lifecycle generation prevents completions from a disposed provider.
- Async authentication and secret reads must capture the relevant generations,
  recheck after suspension points, and fail with
  `SecureStorageSessionChangedException` when ownership changed.
- Account selection and destructive operations call
  `invalidatePendingSecretOperations` so late secret reads cannot cross account
  or wallet identity boundaries.
- `confirmPassword` validates the password without opening a session.
  `unlock` may install the session password and publish unlocked state.

## Lock, reset, and rotation

- `lock()` invalidates unlock and confirmation requests, clears the session
  password, and publishes locked state. Callers then clear account and sync
  sensitive state; `lock()` alone does not perform those provider operations.
- `reset()` invalidates pending authentication, clears prepared setup and the
  session password, and publishes an unconfigured locked state. Durable wallet
  deletion is owned by the account reset flow.
- Password rotation requires an unlocked wallet and a different valid password.
  The migration/password-change preflight must finish before the secure store
  rotates encrypted payloads and updates its verifier.
- A rotation that commits after a concurrent lock still succeeds durably but
  must leave the provider locked. Never use successful storage completion as
  authority to reopen a newer lifecycle.
- Native code that needs the current wallet credential must obtain it through
  `requireSessionPasswordForNativeSecretUse`; it must not persist an extra
  plaintext credential model.

## Secret handling

- Software mnemonic plus optional BIP 39 passphrase uses the versioned
  `SoftwareWalletSecret` envelope. Legacy mnemonic-only payloads remain readable
  through the secure-store migration path.
- Prefer byte-oriented mnemonic reads for Rust calls and zero the caller-owned
  buffer after the Rust future has captured it.
- A locked session returns no account mnemonic. Hardware accounts have no local
  mnemonic by design.

## Verification anchors

- Session races and password rotation:
  [`app_secure_store_session_test.dart`](../../test/core/storage/app_secure_store_session_test.dart)
- Password rules are exercised through the shared helper in
  [`app_secure_store_session_test.dart`](../../test/core/storage/app_secure_store_session_test.dart)
- Locked account metadata behavior:
  [`account_metadata_session_test.dart`](../../test/providers/account_metadata_session_test.dart)
- Unlock orchestration:
  [`unlock_screen.dart`](../../lib/src/features/onboarding/unlock_screen.dart)
