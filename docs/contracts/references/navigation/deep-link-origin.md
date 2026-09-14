# Incoming deep-link origin

Read when changing the claimed HTTPS origin, path classification, or Android/iOS host binding.

- [`VizorDeepLink`](../../../../lib/src/core/navigation/vizor_deep_link.dart) reads
  `VIZOR_DEEPLINK_BASE_URL`, defaulting to `https://link.vizor.cash`.
  [`classifyIncomingLink`](../../../../lib/src/core/navigation/incoming_link_dispatch.dart)
  classifies paths: bare origin and `/` without query/fragment open
  Home; `/payment-links/open` carries Gift Cards. Unknown paths on this origin
  stop without ZIP-321 parsing or logging bearer data.
- Android derives its manifest host and native allowlist from the same Flutter
  dart-define in [`build.gradle.kts`](../../../../android/app/build.gradle.kts). Do not
  add an independent Gradle/environment knob. Direct Gradle uses the default host.
- iOS separately uses `VIZOR_DEEPLINK_HOST` in
  [`ios/Flutter/`](../../../../ios/Flutter) xcconfigs for its plist and entitlements.
  Change it with the Dart origin. Mobile universal-link verification requires
  public HTTPS association files; see test recipes in the
  [E2E guide](../../../../scripts/e2e/README.md#gift-cards).

## Related changes

- When changing Gift Card URI payload validation, read [Gift Card bearer payload](../../domains/gift-cards/payload.md).
- When changing Zcash payment-request parsing, read [ZIP-321 codec](../zcash/zip321-codec.md).
