# iOS background transport exception

Read when changing native background migration confirmation or staged signed-outbox networking.

The [lightwalletd transport module](../../../../rust/src/wallet/sync_engine/lwd.rs)
owns `open_background_direct_lwd_channel` and its focused tests;
the [iOS C adapter](../../../../rust/src/ffi.rs) contains its native callers.

## Pinned Direct opener

- iOS background migration confirmation and signed-outbox transport use
  `open_background_direct_lwd_channel`, an exception disclosed in mobile settings.

- That opener is pinned Direct and must stay out of foreground wallet flows.
  Background confirmation observes exact txids and chain state; it does not
  borrow the foreground Tor client or silently bootstrap Tor.

## Related changes

- For foreground privacy transport, preserve [foreground route policy](../../references/network/route-policy.md).
- For read-only task scope, read [iOS confirmation](../../domains/migration/ios-confirmation.md).
- For the permitted staged-byte submission lane, read [signed outbox](../../domains/migration/signed-outbox.md).
