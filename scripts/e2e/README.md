# End-to-end tests

## Gift Cards

Three macOS regtest runners cover the Gift Card (payment-link) flows. They
share `scripts/e2e/lib-payment-link.sh`, which starts the regtest stack, funds
the sender account, and passes the regtest + payment-link defines every phase
needs:

```bash
# Create, open, and claim a card between two accounts.
scripts/e2e/flutter-macos-regtest-payment-link-round-trip.sh

# Prepare two claims, restart the process, and recover them.
scripts/e2e/flutter-macos-regtest-payment-link.sh

# Retry a failed claim broadcast and survive a reorg.
scripts/e2e/flutter-macos-regtest-payment-link-recovery.sh
```

The runners default `VIZOR_DEEPLINK_BASE_URL` to
`https://link-dev.vizor.cash`. Override it explicitly when testing another
deployment:

```bash
VIZOR_DEEPLINK_BASE_URL=https://example.vizor.cash \
  scripts/e2e/flutter-macos-regtest-payment-link-round-trip.sh
```

The iOS simulator runs the round trip too, against the mobile Settings ›
My Gift Cards surface:

```bash
# Create, open, and claim a card between two accounts, on the simulator.
scripts/e2e/flutter-ios-regtest-mobile-payment-link-round-trip.sh
```

It is part of `scripts/e2e/flutter-ios-regtest-mobile-full.sh` and follows
the mobile lane rules: `run_mobile_e2e` injects `VIZOR_FORM_FACTOR=mobile`,
`ZCASH_DEFAULT_NETWORK=regtest`, and `ZCASH_E2E_LIGHTWALLETD_URL`, and the
runner passes `VIZOR_PAYMENT_LINK_REGTEST_ENABLED=true` — without which
payment links stay gated off — plus `VIZOR_DEEPLINK_BASE_URL`. Set
`SIMULATOR_UDID` when more than one simulator is booted.

Both the desktop and simulator Gift Card runs drive the app's **Redeem a
card → Paste card link** path rather than opening a universal link. macOS
does not register the mobile universal-link handler at all, and the
simulator follows one only when the associated domain's AASA is served from
a publicly reachable HTTPS origin — a local mock server is not enough,
because iOS and Android fetch the association files themselves.

For a mobile development build, keep the Dart and native values aligned:

- Pass `--dart-define=VIZOR_DEEPLINK_BASE_URL=https://link-dev.vizor.cash` to
  Flutter so generated and accepted links use the development origin. This is
  the only knob Android has: `android/app/build.gradle.kts` decodes the same
  define out of Flutter's `dart-defines` Gradle property and injects its host
  into the manifest and native allowlist, so there is no separate environment
  variable or Gradle property to set. Without the define, Android falls back to
  the production origin.
- iOS defaults `VIZOR_DEEPLINK_HOST` to `link.vizor.cash`; set the Xcode build
  setting to `link-dev.vizor.cash` for the development-signed build so its
  associated-domain entitlement and native allowlist match the Dart value.

Verify the public association files before a device run:

```bash
curl -fsS https://link-dev.vizor.cash/.well-known/apple-app-site-association
curl -fsS https://link-dev.vizor.cash/.well-known/assetlinks.json
```

## Payment URIs

One iOS-simulator regtest runner covers the ZIP-321 `zcash:` payment-URI
flow end to end, alongside the macOS runners:

```bash
# Answer a zcash: URI from the mobile payment-request card and send it.
scripts/e2e/flutter-ios-regtest-mobile-payment-uri-send.sh

# The desktop counterparts.
scripts/e2e/flutter-macos-regtest-payment-uri-send.sh
scripts/e2e/flutter-macos-regtest-payment-uri-locked-send.sh
```

The mobile scenario delivers the URI by pushing an `onUris` call over the
`com.zcash.wallet/payment_uri` MethodChannel — the same contract the
macOS/Windows/Linux/Android/iOS runners implement — so the payment-request
card is raised the way a real deep link raises it. It then answers the card
through Review and broadcasts a real regtest transaction. It needs only the
three defines `run_mobile_e2e` already injects; no payment-link or deeplink
define applies.
