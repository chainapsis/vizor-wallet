# Wallet Link transfer format

Use when changing encrypted package or QR fields, account recovery metadata, or compatibility.

- [`WalletLinkController._createUpload`](../../../../lib/src/features/wallet_link/providers/wallet_link_provider.dart)
  uploads an AES-256-GCM envelope and the completion token's SHA-256 hash. The
  random 32-byte encryption key and original completion token travel in the QR;
  account secrets and contacts stay inside the encrypted payload.

- [`WalletLinkQrPayload.parse`](../../../../lib/src/features/wallet_link/models/wallet_link_models.dart)
  accepts `vizor://wallet-link/v1`, a UUID-v4 package ID, and 32-byte key/token
  values. QR fields cannot select a relay endpoint. The build-time
  `VIZOR_WALLET_LINK_BACKEND_URL` in
  [`wallet_link_config.dart`](../../../../lib/src/features/wallet_link/wallet_link_config.dart)
  selects the relay; [`WalletLinkApiClient`](../../../../lib/src/features/wallet_link/services/wallet_link_api_client.dart)
  uses the shared HTTP transport governed by [network route policy](../../references/network/route-policy.md).

- [`_buildTransferPayload`](../../../../lib/src/features/wallet_link/providers/wallet_link_provider.dart)
  exports recovery birthday and ZIP 32 account index from Rust. Software
  accounts require their stored recovery secret; hardware accounts require
  UFVK, seed fingerprint, and derivation metadata.

- [`WalletLinkTransferAccount`](../../../../lib/src/features/wallet_link/models/wallet_link_models.dart)
  requires birthday/index for import and currently supports Keystone hardware
  only, with nonempty UFVK and a 32-byte fingerprint. Legacy hardware records
  without `hardwareKind` resolve to Keystone.

- A nonempty BIP 39 passphrase is preserved exactly in versioned
  `softwareSecret`, with legacy `mnemonic` set to null so older mobile builds
  cannot derive a different wallet using an empty passphrase. A present but
  malformed/unsupported envelope is non-importable; never downgrade it to the
  legacy mnemonic. Mnemonic-only payloads remain readable.

## Verification

- Format, compatibility, TTL, duplicate selection, and completion encryption:
  [`wallet_link_models_test.dart`](../../../../test/features/wallet_link/wallet_link_models_test.dart)

## Related changes

For relay routing changes, read [network route policy](../../references/network/route-policy.md).
