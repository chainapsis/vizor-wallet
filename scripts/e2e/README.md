# End-to-end tests

## Gift Cards

Sender usage tracking and empty observer DB reuse:

```bash
scripts/e2e/flutter-macos-regtest-gift-card-tracking.sh
```

This runner resets the disposable regtest chain by default, imports the funded
sender, drives creation and receipt in the UI, and checks `Unused`, `Use detected`
at one confirmation, and `Used` plus automatic observer deletion at six. It then
restarts the process after 200 mined blocks, checks persisted usage and the same
empty DB path, and repeats the lifecycle for a new card. It uses the production
tracking timer rather than forcing refreshes. Logs and app-content PNG captures
are written to `.regtest-logs/gift-card-tracking/`. The window stays hidden by
default. Run prepare/resume together: resume requires prepare's retained wallet
and manifest.

The companion Rust scenario verifies the skipped block interval directly with
real shielded notes and a changed tree frontier, then imports an older card:

```bash
cargo test --manifest-path rust/Cargo.toml --test regtest_gift_card_tracking -- --ignored --nocapture --test-threads=1
```

Start a healthy regtest stack first. Do not run this command concurrently with
an app E2E: both mine on the same chain. It uses temporary wallet DBs and does not
inject scan queue rows. The test is excluded from ordinary Rust test runs.


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

# Competition, lost-response recovery, and removal after restart (three scenarios).
scripts/e2e/flutter-macos-regtest-gift-card-outcomes.sh
```

The outcomes runner uses four process phases for three scenarios: competition
leaves a real losing card, the next process removes it, and a separate
prepare/resume pair recovers a transaction whose accepted response was dropped.
It checks five versus six confirmations, winner/loser balances, a fresh
observer's spend evidence, retained secrets and claim databases, and zero
transmissions during a manual status check. A fully spent competing card resolves
to `Claimed elsewhere` and can be removed; `Claim failed` is reserved for other
settled failures.
Automatic claim recovery is gated only during the manual-check measurement,
then released to execute the production recovery path.

Run this suite serially: it uses the shared Docker regtest chain and resets it
between the competition/removal and response-loss scenarios by default. The
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

# First-wallet Gift creation/import, receipt, Home setup, and recipient removal.
scripts/e2e/flutter-ios-regtest-mobile-gift-onboarding.sh
```

It is part of `scripts/e2e/flutter-ios-regtest-mobile-full.sh` and follows
the mobile lane rules: `run_mobile_e2e` injects `VIZOR_FORM_FACTOR=mobile`,
`ZCASH_DEFAULT_NETWORK=regtest`, and `ZCASH_E2E_LIGHTWALLETD_URL`, and the
runner passes `VIZOR_PAYMENT_LINK_REGTEST_ENABLED=true` — without which
payment links stay gated off — plus `VIZOR_DEEPLINK_BASE_URL`. Set
`SIMULATOR_UDID` when more than one simulator is booted.

The onboarding runner uses the Ironwood regtest stack. It prepares three
independent faucet notes before activation, then funds fresh external Gift
addresses through the Rust wallet's transaction builder, driven by
`ironwood-regtest-driver.py`. Ironwood shares the Orchard receiver; the
ordinary `zcashd z_sendmany` faucet cannot fund these cards after NU6.3.
The runner supplies the same activation height to the node and app, defaults
to lightwalletd port 19067 and node RPC port 19232, and accepts
`IRONWOOD_LIGHTWALLETD_PORT`, `IRONWOOD_ZCASHD_RPC_PORT`,
`E2E_LIGHTWALLETD_URL`, and `E2E_ZCASHD_RPC_URL` overrides. Use
`IRONWOOD_COMPOSE_FILE` for an isolated Compose definition. `RESET_REGTEST=0`
reuses an already running, activated chain with its prepared Gift funder DB.

The onboarding test drives **Activate gift card → Paste card link** in a walletless
app. It verifies account/passcode persistence, real claim transactions and Home
Activity, six-confirmation bearer/temporary DB cleanup, manual setup carousel,
backup deferral/completion and birthday, education, first-wallet passphrase
import, and deletion of a waiting card with its removed recipient. The runner
passes the mobile tag/define and opts into skipped mobile tests. It does not
capture recovery words or bearer links, and skips native biometric enrollment.
Both Gift runners reset their disposable chains by default; run them
serially. `E2E_DRIVER_PORT` selects the onboarding driver's port.

The desktop and simulator round-trip runners also accept
`--dart-define=GIFT_CARD_E2E_AMOUNT_MODE=usd` or `usd-max` (the default is
`zec`). These modes fix only the USD price at $125.50 per ZEC, check both
currency switches, and use real regtest funding and claims. The `usd-max`
case checks that rounding the visible dollar amount preserves the exact
ZEC Max quote through the copied card link and recipient balance:

```bash
scripts/e2e/flutter-macos-regtest-payment-link-round-trip.sh \
  --dart-define=GIFT_CARD_E2E_AMOUNT_MODE=usd-max

SIMULATOR_UDID=<simulator-udid> \
  scripts/e2e/flutter-ios-regtest-mobile-payment-link-round-trip.sh \
  --dart-define=GIFT_CARD_E2E_AMOUNT_MODE=usd
```

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

## Proxy delegation

`scripts/e2e/flutter-macos-regtest-proxy-delegation.sh` runs proxy delegation through the real desktop app on a full local stack, built only from local checkouts:

- **Zcash:** the Ironwood regtest stack (`scripts/ironwood-regtest/`, in its own Compose project and state directory) and the deterministic wallet funded with 1.01 ZEC through the real Orchard-to-Ironwood migration, eight 0.125 ZEC ballots.
- **PIR:** `nf-server` and `pir-export` built offline from a local vote-nullifier-pir checkout, serving the regtest nullifiers at the round's snapshot.
- **Vote chain:** vote-sdk's isolated `PROXY=1` localnet (`svoted -tags proxyenabled`, proxy params, the development verifier key, two vote managers), started through the delegate verifier's `scripts/devstack/localnet.sh`.
- **Attester:** the dev stack (delegate-verifier `docs/devstack.md`) on fake or real X and GitHub ([Real or fake providers](#real-or-fake-providers)), with two delegates registered through its attester API on the fake X by `devstack delegate register`, and a proxy round created over the regtest snapshot with two vote-manager approvals (vote-sdk's `create_round_for_zashi` with `ZASHI_PROXY_DELEGATION=1`), whose ordinary entry is signed into the dynamic config once its ceremony publishes an `ea_pk`. The config's unsigned `extensions.proxy_delegation_v1` names the attester API and proof hosts (contracts-v1 section 12.1).
- **Wallet list:** a test Vizor list (`zcash-vote-wallet-list/v1`, contracts-v1 section 12.3) with a row for every live entry of the chain's registry, carrying the entry's key, provider and handle, with a small WebP picture. The harness signs it with `voting-config wallet-list sign` under a throwaway key made once per stack, checks it with `wallet-list verify --chain-check` as config CI does, and serves it from the dev stack's config mirror at `stage/wallets/vizor/list.json`. The app reads it from `VIZOR_PROXY_WALLET_LIST_URL` and pins the key in `VIZOR_PROXY_WALLET_LIST_KEY` (`<key_id>:<base64 public key>`), which only a regtest build honours.
- **Gateway:** `voting-regtest-gateway.py` for the logical vote and PIR hosts, the participation RPC, discovery, and a `/delegate-ballots` route that posts both delegates' ballots with `devstack delegate ballot`.
- **App:** a debug build with `VIZOR_PROXY_DELEGATION_ENABLED=true` and `VIZOR_UNSTABLE_PROXY_DELEGATION=1`, which turns on zcash_voting's dev-only `unstable-proxy-delegation` feature.

```bash
# Go and a warm cargo cache are needed. Nothing is cloned; the only network
# use is Docker's: the zcashd image and the lightwalletd build the Compose
# file pins.
E2E_PIR_SOURCE=~/Documents/vote-nullifier-pir \
  scripts/e2e/flutter-macos-regtest-proxy-delegation.sh          # up, test, down
scripts/e2e/flutter-macos-regtest-proxy-delegation.sh --keep     # up, test, leave it running
```

The full run and `test` run the dev stack on both fakes, and refuse `DEVSTACK_X` or `DEVSTACK_GITHUB` set to `real`.

`integration_test/regtest_proxy_delegation_test.dart` reuses the funded wallet (or imports it again when an earlier run's teardown removed it, so `test` can rerun on a live stack after `round`), opens the proxy round and delegates as one way of answering its ballot: from the round's "Let a delegate vote some or all" line it browses Vizor's list, which shows both delegates as reviewed, picks delegate A from it, pastes A's `zvdk1` key and checks it finds A, finds delegate B by exact handle search over the registry cache and picks it, gives them 25% and 50% with the rest kept, returns to the questions and answers them for the kept share, then on the one vote review passes the registry check over real proofs of both entries from the proof hosts, checks each delegate shows as `#N · fingerprint`, and submits once. The one progress screen sends the delegation first and the kept share's casts right after, and the test waits for the vote receipt, which comes only once the delegation is handed off. It then has the gateway post the delegates' ballots, reopens the round, whose status shows each question with the kept vote and both delegates' ballots, waits for the close and both delegations to read `Counted`, and checks the chain's `vote-summary` against a model of the kept vote and both pools. The window is 15 minutes (`E2E_PROXY_VOTE_WINDOW_SECS`), so the test waits out the rest of it; everything before the wait takes about three minutes on a warm build. Logs, the final tally and every service's state are in the state directory.

### By hand

```bash
scripts/e2e/flutter-macos-regtest-proxy-delegation.sh up       # the stack, the funded wallet and a round
scripts/e2e/flutter-macos-regtest-proxy-delegation.sh app      # Vizor in a window, against the stack
scripts/e2e/flutter-macos-regtest-proxy-delegation.sh ballots  # both delegates ballot in the round
scripts/e2e/flutter-macos-regtest-proxy-delegation.sh round    # another proxy round over the same snapshot, and re-sign the list
scripts/e2e/flutter-macos-regtest-proxy-delegation.sh list     # re-sign the wallet list from the chain's registry
scripts/e2e/flutter-macos-regtest-proxy-delegation.sh switch   # restart the dev stack in new provider modes
scripts/e2e/flutter-macos-regtest-proxy-delegation.sh test     # the integration test on the running stack
scripts/e2e/flutter-macos-regtest-proxy-delegation.sh status
scripts/e2e/flutter-macos-regtest-proxy-delegation.sh down     # stop and remove everything
```

`app` runs `integration_test/support/regtest_proxy_delegation_manual_main.dart` with the stack's defines; unlock the wallet with `Vizor123!`. After `test`, whose teardown removes the wallet, import it again from the mnemonic in `scripts/ironwood-regtest/run-flutter-test.sh`; its funds stay on the chain. Set `E2E_PROXY_VOTE_WINDOW_SECS` before `up` or `round` for a longer round. Set `E2E_PROXY_SCREENSHOT_DIR` to a folder name before `test` to save a PNG of each delegation screen under the app's sandboxed temp directory (`~/Library/Containers/<bundle id>/Data/tmp/<name>`); the test logs each path. `stack.env` in the state directory records the round, the gateway, the static config source, the chain anchor, the wallet list's URL and key, and the delegates; their keys are in `delegates/`, and the list's signing key in `wallet-list/`. `down` stops the gateway, the PIR server, the dev stack and the localnet through their own scripts, and removes the Compose project's containers and volumes.

### Real or fake providers

`up` and `switch` start the dev stack with real X and real GitHub unless `DEVSTACK_X` or `DEVSTACK_GITHUB` says `fake`; the harness passes both to delegate-verifier's `devstack-up`, which documents each mode (`docs/devstack.md`, "Real and fake providers"). The attester reads real X through the free oEmbed endpoint and real GitHub through the public gist API, under its daily attestation cap.

```bash
scripts/e2e/flutter-macos-regtest-proxy-delegation.sh up                    # both real
DEVSTACK_X=fake scripts/e2e/flutter-macos-regtest-proxy-delegation.sh switch   # fake X, real GitHub, on the running stack
```

`switch` restarts only the dev stack's services, keeping their state, the chain, PIR, the gateway, the round and a running app, and routes the rewritten config to the gateway again. Entries registered on a provider's fake stay in the chain's registry after a switch to real.

With real X, `up` registers no test delegates, so `ballots` and `test` have none, and the wallet list starts empty. Register real delegates in the app, then run `list`, which re-signs the wallet list from the chain's registry so they show in browse; the app takes it on its next list refresh, an hour later, or when restarted. An entry can take delegations in a round that was created before it registered.

### Trusting the dev stack's CA

The config, the wallet list, the attester API and the proof hosts are HTTPS under the dev stack's development CA, which is name-constrained to `127.0.0.1` and `localhost`. Vizor reads all of them through Dart's `HttpClient`, so the test and the manual entrypoint add that CA to Dart's own `SecurityContext` with `HttpOverrides` (`integration_test/support/proxy_delegation_regtest.dart`), beside the platform's roots: no keychain change, product code or build setting. Rust's transport, which posts to the vote servers and queries PIR, trusts only the platform's roots, so the harness rewrites the served config's unsigned `vote_servers` and `pir_endpoints` to the gateway's logical hosts and checks the result with `voting-config verify`.

### Ports

Every listener binds 127.0.0.1, off vote-sdk's, the dev stack's and the voting harness's defaults; the harness refuses to start while any is taken.

| Port | Service | Variable |
|---|---|---|
| 29232, 29067 | zcashd RPC, lightwalletd | `E2E_IRONWOOD_ZCASHD_RPC_PORT`, `E2E_IRONWOOD_LIGHTWALLETD_PORT` |
| 29078 | the Ironwood driver of the funding run | `E2E_DRIVER_PORT` |
| 23000 | PIR server | `E2E_PIR_PORT` |
| 23317, 38657 | vote chain REST and RPC | `E2E_VOTE_PORT`, `E2E_VOTE_RPC_PORT` |
| 38656, 38658, 38660, 29190, 29191, 26260 | vote chain P2P, ABCI, Prometheus, gRPC, gRPC-web, pprof | `E2E_VOTE_*_PORT` |
| 27201–27250 | the verifier dev stack | `E2E_DEVSTACK_PORT_BASE` (27200) |
| 28080 | gateway | `E2E_VOTING_GATEWAY_PORT` |

The other settings: `E2E_PROXY_STATE_DIR` (default `.regtest-proxy-delegation/`), `E2E_VOTE_SDK_DIR` and `E2E_DELEGATE_VERIFIER_DIR` (default the sibling checkouts), `E2E_PIR_DIR` (a ready checkout) or `E2E_PIR_SOURCE` (a local checkout to clone at `E2E_PIR_REV`), and `E2E_PROXY_DELEGATE_A_OPTIONS` and `E2E_PROXY_DELEGATE_B_OPTIONS` for the delegates' ballots.

### Prerequisites

- Docker able to run `linux/amd64` images (Rosetta or QEMU emulation on Apple Silicon): the zcashd image is amd64 only.
- A Debug macOS build that signs, as every macOS integration test needs. The harness passes the environment through to every Flutter run, so wrap the whole command with your own signing, for example a script that unlocks your keychain and exports `FLUTTER_XCODE_DEVELOPMENT_TEAM`, `FLUTTER_XCODE_CODE_SIGN_STYLE` and `FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER`. Nothing in the harness depends on the bundle ID.
- No unlocked screen. Vizor stores the macOS mnemonic in the data protection keychain as available only while unlocked, so writing it fails with `-25308` (`errSecInteractionNotAllowed`) whenever the screen is locked, including from an unattended or background shell. Both Flutter runs, the wallet funding and the test, pass `ZCASH_E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN=true` (honoured only in Debug), which stores it as available after first unlock instead. A new step that writes or reads the reused wallet's mnemonic needs it too.
- A warm cargo cache for vote-nullifier-pir (the build is `--offline`) and Go for the vote chain and `voting-config`.

The older voting harness, `flutter-macos-regtest-voting.sh`, takes `E2E_VOTE_SDK_DIR` and `E2E_PIR_DIR` the same way, to build local checkouts in place instead of fetching its pinned revisions.
