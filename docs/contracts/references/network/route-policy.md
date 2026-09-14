# Foreground network route policy

Read when changing Tor/Direct persistence, foreground HTTP/lightwalletd openers, or transport-switch ordering.

## Route policy

- [`initializeNetworkPrivacyRuntime`](../../../../lib/src/providers/network_privacy_provider.dart)
  applies the persisted route before bootstrap/provider network work.

- Foreground lightwalletd and HTTP clients use policy-aware openers. Tor enable
  installs fail-closed intent synchronously before bootstrap. While Tor starts
  or has failed, requests wait or fail; they never fall back to direct.

- Route toggles quiesce sync, mempool, and direct HTTP work before changing the
  transport. A busy old route blocks a privacy-changing toggle.

- Persisted route state may temporarily be stricter than the live runtime, never
  laxer. Enable persists Tor before changing the runtime; disable persists
  Direct only after the runtime is Direct. The executable ordering rule is
  `networkPrivacyPersistedRouteIsSafe`.

- Recheck toggle generation after every suspension point: an old disable must
  never reopen direct traffic after a newer Tor enable.

- Coordinate native desktop updates separately; their transports do not
  automatically use embedded Tor.

## Transport replacement

- `restartSyncAfterTransportChange` cancels and drains both network lanes before
  applying the route callback. A real transport change fails closed if tasks
  remain active; a same-transport refresh may retain the older start-anyway
  behavior.

## Verification anchors

- Route ordering and failure behavior:
  [`network_privacy_provider_test.dart`](../../../../test/providers/network_privacy_provider_test.dart)

## Related changes

- When changing the lanes being cancelled/drained, read [foreground sync lifecycle](../sync/foreground-lifecycle.md).
- Only for iOS native background confirmation or signed-outbox transport, read [the pinned Direct exception](../../platforms/ios/background-transport.md).
