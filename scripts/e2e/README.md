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

# Answer a zcash: payment URI from the mobile payment-request card.
scripts/e2e/flutter-ios-regtest-mobile-payment-uri-send.sh
```

Both are part of `scripts/e2e/flutter-ios-regtest-mobile-full.sh` and follow
the mobile lane rules: `run_mobile_e2e` injects `VIZOR_FORM_FACTOR=mobile`,
`ZCASH_DEFAULT_NETWORK=regtest`, and `ZCASH_E2E_LIGHTWALLETD_URL`, and the
Gift Card runner adds `VIZOR_PAYMENT_LINK_REGTEST_ENABLED=true` plus
`VIZOR_DEEPLINK_BASE_URL`. Set `SIMULATOR_UDID` when more than one simulator
is booted.

Both flows use the app's **Redeem a card → Paste card link** path.
Neither macOS nor the simulator registers a mobile universal-link handler,
and a local mock server is not sufficient for association testing either,
because iOS and Android retrieve the association files from a publicly
reachable HTTPS origin.

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
