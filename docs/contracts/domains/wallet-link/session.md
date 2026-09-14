# Wallet Link session ownership

Use when changing authentication, QR visibility, upload freshness, regeneration, expiry, or revocation.

- [`WalletLinkDesktopScreen`](../../../../lib/src/features/wallet_link/screens/wallet_link_desktop_screen.dart)
  requires password confirmation before exposing the live controller. It holds
  the payment-URI busy surface for its entire mounted lifetime so an incoming
  payment request cannot cover the pairing QR.

- The desktop controller owns the package, key reference, timer, and request
  epoch. Restart/regeneration invalidates older work and attempts to revoke the
  previously tracked package. Poll results may publish only for the current
  epoch while the phase is `ready`.
- Upload preparation uses `LinuxSecretOperationGuard`, including a final check
  immediately before sending recovery material. On Linux, a changed session or
  account invalidates delayed work; invalidation during an already-started
  upload prevents its QR from being published but cannot unsend that upload.
- `walletLinkDisplayLifetime` caps the displayed QR lifetime at the smaller of
  the local one-minute default and the relay's returned TTL. Nonpositive TTL
  fails preparation. The mobile downloader separately checks `expiresAt`.
- Local timer expiry attempts remote revocation. Polling HTTP 404/410 expires
  the local session without another revoke. Other polling failures leave it
  retryable until the timer expires.
- Explicit `expire()` and provider disposal invalidate local work and clear key
  references without remote revocation. Revoke itself is best-effort, accepts
  HTTP 404/410, and relies on backend TTL when cleanup cannot reach the relay.

## Verification

- Linux delayed-secret and in-flight upload invalidation:
  [`linux_secret_consumers_test.dart`](../../../../test/core/storage/linux_secret_consumers_test.dart)

- Revoke transport and missing/expired responses:
  [`wallet_link_api_client_test.dart`](../../../../test/features/wallet_link/wallet_link_api_client_test.dart)

- Payment-URI interruption boundary:
  [`wallet_link_desktop_screen_busy_surface_test.dart`](../../../../test/features/wallet_link/wallet_link_desktop_screen_busy_surface_test.dart)

## Related changes

For delayed Linux secret access, read [keyring recovery](../../platforms/linux/keyring.md). For session invalidation changes, read [secret sessions](../../references/storage/secret-sessions.md).
