# Wallet Link completion

Use when changing completion authorization, encrypted counts, or acknowledgement after local processing.

- Completion sends the original token as authorization plus encrypted counts.
  [`wallet_link_completion_crypto.dart`](../../../../lib/src/features/wallet_link/services/wallet_link_completion_crypto.dart)
  derives a separate completion key using `vizor-wallet-link-completion-v1` and
  pads the plaintext to 256 bytes, keeping ciphertext size independent of counts.

- [`completeWalletLinkPackageBestEffort`](../../../../lib/src/features/wallet_link/services/wallet_link_completion.dart)
  acknowledges completed local processing, including zero imports when nothing
  remains to import. Its bounded request updates desktop confirmation; a relay
  failure must not roll back successful local imports.
- Desktop enters `linked` only after relay status is completed. It reports
  actual import counts only when the encrypted completion summary is readable;
  absent or unreadable summaries produce generic confirmation, not claimed
  counts from the original export.

## Verification

- Format, compatibility, TTL, duplicate selection, and completion encryption:
  [`wallet_link_models_test.dart`](../../../../test/features/wallet_link/wallet_link_models_test.dart)

- Selection/completion UI and contacts-only network validation:
  [`mobile_wallet_link_screens_test.dart`](../../../../test/features/onboarding/mobile_wallet_link_screens_test.dart)
