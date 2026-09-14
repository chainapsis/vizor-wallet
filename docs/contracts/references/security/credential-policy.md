# Wallet credential policy

Read when changing password/passcode validation or reuse of the shared credential model.

## Credential policy

- Desktop wallet passwords require at least eight characters, all printable
  ASCII bytes `0x21` through `0x7e`.

- Compare the exact submitted string; do not normalize IME or keyboard-layout
  input.

- Reuse `validateRequiredWalletPassword` from
  [`password_policy.dart`](../../../../lib/src/core/security/password_policy.dart).
  The charset message remains `Use only English letters, numbers, and symbols.`

- Mobile passcode UI requires exactly six digits. That string is stored as the
  wallet password through the same security provider and secure-store path, with
  no second credential model.

- The mobile keypad help action for a forgotten-wallet reset belongs only on
  app-start `/unlock`.

## Verification anchors

- Password rules are exercised through the shared helper in
  [`app_secure_store_session_test.dart`](../../../../test/core/storage/app_secure_store_session_test.dart)

## Related changes

- When credential setup surrounds account creation/import, follow [setup transaction](../../domains/security/setup.md).
