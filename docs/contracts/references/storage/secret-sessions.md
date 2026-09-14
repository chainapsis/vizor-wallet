# Secret sessions and handoff

Read when changing asynchronous authentication, secret-read freshness, native credential use, or mnemonic byte ownership.

## Session generations

- `AppSecureStore.sessionGeneration` governs secret-operation freshness on
  platforms that enforce it. Opening, clearing, or explicitly invalidating the
  session changes its generation.

- Security provider request generations identify the latest unlock or
  confirmation; lifecycle generation prevents completions from disposed providers.

- Async authentication and secret reads must capture the relevant generations,
  recheck after suspension points, and fail with
  `SecureStorageSessionChangedException` if ownership changed.

- Account selection and destructive operations call
  `invalidatePendingSecretOperations` to prevent late secret reads across account
  or wallet identities.

- `confirmPassword` validates without opening a session. `unlock` may install
  the session password and publish unlocked state.

## Secret handling

- Software mnemonic plus optional BIP 39 passphrase uses the versioned
  `SoftwareWalletSecret` envelope. Legacy mnemonic-only payloads remain readable
  through the secure-store migration path.

- Prefer byte-oriented mnemonic reads for Rust calls; zero the caller-owned
  buffer after the Rust future captures it.

- Locked sessions return no account mnemonic. Hardware accounts have none
  locally by design.

## Native credentials

- Native code must obtain the current wallet credential through
  `requireSessionPasswordForNativeSecretUse`, without persisting an extra
  plaintext credential model.

## Verification anchors

- Session races and password rotation:
  [`app_secure_store_session_test.dart`](../../../../test/core/storage/app_secure_store_session_test.dart)

- Locked account metadata behavior:
  [`account_metadata_session_test.dart`](../../../../test/providers/account_metadata_session_test.dart)

## Related changes

- For the complete user lock/unlock transition, follow [lock and unlock](../../domains/wallet/lock-unlock.md).
- When changing Linux keyring waits and generation enforcement, read [Linux keyring](../../platforms/linux/keyring.md).
- When changing Apple Keychain accessibility, read [Apple Keychain](../../platforms/apple/keychain.md).
