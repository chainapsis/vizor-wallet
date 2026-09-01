# End-to-end tests

## Gift Card round trip

Run the macOS regtest flow with the public development deeplink origin:

```bash
VIZOR_E2E_HIDDEN_WINDOW=true \
  scripts/e2e/flutter-macos-regtest-payment-link.sh
```

The script defaults `VIZOR_DEEPLINK_BASE_URL` to
`https://link-dev.vizor.cash`. Override it explicitly when testing another
deployment:

```bash
VIZOR_DEEPLINK_BASE_URL=https://example.vizor.cash \
  scripts/e2e/flutter-macos-regtest-payment-link.sh
```

This flow uses the desktop app's **Redeem a card → Paste card link** path.
macOS does not register the mobile universal-link handler. A local mock server
is also not sufficient for mobile association testing because iOS and Android
retrieve the association files from a publicly reachable HTTPS origin.

For a mobile development build, keep the Dart and native values aligned:

- Pass `--dart-define=VIZOR_DEEPLINK_BASE_URL=https://link-dev.vizor.cash` to
  Flutter so generated and accepted links use the development origin.
- Android reads the same `VIZOR_DEEPLINK_BASE_URL` environment variable (or
  Gradle property) and injects its host into the manifest and native allowlist.
- iOS defaults `VIZOR_DEEPLINK_HOST` to `link.vizor.cash`; set the Xcode build
  setting to `link-dev.vizor.cash` for the development-signed build so its
  associated-domain entitlement and native allowlist match the Dart value.

Verify the public association files before a device run:

```bash
curl -fsS https://link-dev.vizor.cash/.well-known/apple-app-site-association
curl -fsS https://link-dev.vizor.cash/.well-known/assetlinks.json
```
