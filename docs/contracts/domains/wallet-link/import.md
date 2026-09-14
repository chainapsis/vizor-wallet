# Wallet Link import

Use when changing account selection, duplicate handling, or network checks before account/contact import.

- [`MobileWalletLinkController`](../../../../lib/src/features/wallet_link/providers/mobile_wallet_link_provider.dart)
  checks supported package/payload versions, decrypts, and preselects importable
  entries excluding known duplicates. Duplicate preflight is best-effort;
  [`AccountNotifier.importLinkedWalletAccounts`](../../../../lib/src/providers/account_provider.dart)
  owns actual account import and duplicate handling.

- Import validates the linked network against the existing wallet's stored
  network, or the current app network for a fresh wallet. The contacts-only path
  in [`mobile_wallet_link_screens.dart`](../../../../lib/src/features/onboarding/mobile/mobile_wallet_link_screens.dart)
  must also validate the network before mutating contacts.

## Verification

- Import network and duplicate-error handling:
  [`account_provider_test.dart`](../../../../test/providers/account_provider_test.dart)

- Selection/completion UI and contacts-only network validation:
  [`mobile_wallet_link_screens_test.dart`](../../../../test/features/onboarding/mobile_wallet_link_screens_test.dart)

## Related changes

For payload compatibility, read [transfer format](transfer-format.md). For reporting successful local work, read [completion](completion.md).
