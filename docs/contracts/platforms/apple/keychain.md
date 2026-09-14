# Apple Keychain access

Read when changing iOS/macOS Keychain accessibility or the separate macOS mnemonic service.

## Accessibility policy

- [AppSecureStore](../../../../lib/src/core/storage/app_secure_store.dart) configures
  Apple Keychain accessibility per storage purpose. iOS uses
  `first_unlock_this_device`; macOS metadata uses `first_unlock` while the
  separate mnemonic service normally uses `unlocked`. The debug-only
  `ZCASH_E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN` override relaxes only that macOS
  mnemonic setting. OS accessibility does not replace the wallet password/session.

## Related changes

- When changing wallet-level credential freshness, preserve [secret sessions](../../references/storage/secret-sessions.md).
