# End-to-end tests

## Running regtest safely

Run regtest/integration scenarios only when explicitly requested. They are slow,
reset shared Docker chain/wallet state, and must run serially when sharing the
same stack. Docker Desktop / `docker compose` is required; `grpcurl` improves
readiness checks, with TCP checks as the fallback. Use release builds for
representative cryptographic performance; debug proving/scanning is much slower.

macOS runners hide their app window by default. Set
`VIZOR_E2E_HIDDEN_WINDOW=false` only when a visible window is needed to debug or
verify the scenario.

### App network and cleanup

- Select regtest with `--dart-define=ZCASH_DEFAULT_NETWORK=regtest`; the old
  `ZCASH_USE_E2E_STORAGE` path is not the storage switch. Secure storage and DB
  names are network-scoped.
- `ZCASH_E2E_LIGHTWALLETD_URL` only overrides the endpoint. Keep Rust API network
  arguments consistent with `kZcashDefaultNetworkName`.
- Cleanup must guard on
  `kZcashDefaultNetworkName == ZcashNetwork.regtest.name`, stop Rust work, resolve
  `getWalletDbName()` before deleting storage, and delete that DB plus its
  `-shm`/`-wal` files. Do not turn test cleanup into a network-independent wipe.
- True inbound mempool discovery uses external zcashd/lightwalletd funding.
  Sending between two accounts in the same app does not prove that path.
  To exercise it during active sync, pre-mine enough blocks and use the
  debug-only Rust `ZCASH_E2E_SYNC_BATCH_SIZE` and
  `ZCASH_E2E_SYNC_BATCH_DELAY_MS` environment overrides inline.

### iOS simulator lane

- The full runner is
  [`flutter-ios-regtest-mobile-full.sh`](flutter-ios-regtest-mobile-full.sh);
  per-scenario runners use `flutter-ios-regtest-mobile-*.sh`.
- [`lib-mobile.sh`](lib-mobile.sh) normally injects `VIZOR_FORM_FACTOR=mobile`,
  `ZCASH_DEFAULT_NETWORK=regtest`, and `ZCASH_E2E_LIGHTWALLETD_URL`.
  Endpoint-failover scenarios deliberately omit the last define with
  `E2E_SKIP_LWD_OVERRIDE=1` so bootstrap does not replace their proxy preset.
- `SIMULATOR_UDID` wins; otherwise exactly one simulator must be booted. The
  runner refuses to choose among multiple devices. Host loopback `127.0.0.1`
  works on iOS Simulator; Android emulators would need `10.0.2.2` and a separate
  runner.
- Mobile tests share
  [`mobile_regtest_flow.dart`](../../integration_test/support/mobile_regtest_flow.dart).
  Keep its flow helpers separate from the desktop tests' per-file helpers.
- Each mobile test invocation reinstalls the app. The DB container is disposable
  while Keychain survives; call `cleanupE2eWalletState()` at both start and
  teardown. Do not assume wallet reuse across invocations.
- Gift Card tests also call `cleanupMobileE2ePaymentLinkClaimWallets()`. The
  support directory contains claim wallets from multiple networks, so that sweep
  must stay regtest-scoped. Clear a populated pasteboard in teardown too; it
  outlives the app container.

### Rust runners and local chain

[`run-regtest-rust-tests.sh`](../../run-regtest-rust-tests.sh) tears down existing
containers and resets `.regtest/` before running, then does a final down/reset
by default. `--keep` skips the final cleanup for inspection. Logs remain in
`.regtest-logs/regtest-rust-tests.log`, outside the reset directory. Sapling
parameters remain cached in `~/.zcash-params`; override the location with
`SAPLING_PARAMS_DIR=/custom/path ./run-regtest-rust-tests.sh`.

For a single scenario, start with `scripts/regtest/up.sh`, then run from `rust/`:
`cargo test --test regtest_receive_sync -- --ignored --nocapture --test-threads=1`.
Other targets include `regtest_send`, `regtest_import`, and `regtest_multi_account`.
Stop the stack with `scripts/regtest/down.sh`.

[`scripts/regtest/`](../regtest) also provides `reset.sh` (destroys chain/volume
state), `mine.sh <count>`, and
`fund-wallet.sh <unified_address> <amount_zec> [confirmations]`. Source `lib.sh`
from scripts; it is not a standalone command. Inspect the current scenario
runners for coverage instead of assuming every desktop scenario has a mobile
counterpart.

## Gift Cards

The macOS regtest runners cover the Gift Card (payment-link) flows. They
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

# Competition, lost-response recovery, and archive/restore (three scenarios).
scripts/e2e/flutter-macos-regtest-gift-card-outcomes.sh
```

The outcomes runner uses four process phases for three scenarios: competition
leaves a real losing card archived, the next process restores it, and a separate
prepare/resume pair recovers a transaction whose accepted response was dropped.
It checks five versus six confirmations, winner/loser balances, a fresh
observer's spend evidence, retained secrets and claim databases, and zero
transmissions during a manual status check. A fully spent competing card resolves
to `Already claimed`; `Claim failed` is reserved for other settled failures.
Automatic claim recovery is gated only during the manual-check measurement,
then released to execute the production recovery path.

Run this suite serially: it uses the shared Docker regtest chain and resets it
between the competition/archive and response-loss scenarios by default. The
fault proxy and node are pinned to local ports 19068 and 18232. macOS windows
remain hidden by default. Logs are saved to `.regtest-logs/gift-card-outcomes.log`;
the chain remains available for inspection afterward. As with the other runners,
run it only when regtest execution is intended.

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
