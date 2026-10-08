# End-to-end tests

For the planned isolated execution framework and direct Zakura migration, see
the [E2E roadmap](ROADMAP.md). The roadmap tracks unmerged work. Catalog previews
are described first; the existing scenario runners below are unchanged.

The [native runtime contract](RUNTIME_CONTRACT.md) defines per-case launch
identity and storage isolation for the later worker/executor layers. It does
not add an execution backend or make pending catalog entries runnable.

## Catalog previews

`run-suite.py` provides a host-only inventory and selection preview. This first
slice does not include execution backends: all 64 catalog entries are pending,
and a plan reports `runnable: false` with its blockers. An exit code of 0 means
the preview succeeded, not that any E2E test ran or passed. Invocation without
`--list` or `--plan` fails before accessing a backend.

Previews require Python 3.9 or newer and use only the standard library. Git is
also required for `--changed-from`; Flutter, Docker, and a running regtest stack
are not needed for previews or the host-only checks below.

```bash
# List the inventory or preview a suite, exact scenario, or tag intersection.
python3 scripts/e2e/run-suite.py --list
python3 scripts/e2e/run-suite.py --suite flutter-native-all --tag ios --plan
python3 scripts/e2e/run-suite.py --scenario rust.send.basic --plan
python3 scripts/e2e/run-suite.py --suite all --tag ios --tag ironwood --list

# Preview affected scenarios or failed/timed-out cases from a schema-2 report.
python3 scripts/e2e/run-suite.py --changed-file integration_test/regtest_payment_link_round_trip_test.dart --plan
python3 scripts/e2e/run-suite.py --changed-from origin/main --plan
python3 scripts/e2e/run-suite.py --failed-from /path/to/prior/run.json --plan
```

Primary selectors are mutually exclusive. Repeat `--scenario` or `--changed-file`
to combine inputs, and repeat `--tag` to require every tag. Selection is deduplicated
in catalog order. Prior reports must contain known scenario IDs and matching
target/test identities; passed, cancelled, and unstarted cases are not failed-case
candidates, and the original report is never rewritten.

Changed-file selection uses conservative path rules, not a full dependency graph.
Known scripts, integration phases, and Rust targets select their mapped scenarios;
shared code and unknown files widen coverage. Pending cases remain in the preview
and its coverage gaps. Shared helpers under `test/support/` and `test/e2e/` select
the Flutter inventory; other `test/` paths are treated as unit-only.
Documentation/unit-only changes can select no E2Es.
`--changed-from` reads merge-base, committed, staged, unstaged, and nonignored
untracked paths, including deleted paths and both sides of renames. It rejects
HEAD or changed-path status drift during collection. Other previews need no
subprocess; no preview starts services, builds, simulators, or artifact directories.

Host-only checks for this slice:

```bash
python3 -B -m unittest scripts/e2e/test_e2e_catalog.py scripts/e2e/test_e2e_report.py scripts/e2e/test_e2e_changes.py scripts/e2e/test_e2e_impact.py scripts/e2e/test_run_suite.py
```

## Native port ownership primitive

`native_ports.py` is the first host-only worker-lifecycle component for macOS
and iOS Simulator runners. It reserves distinct loopback RPC, lightwalletd,
and proxy sockets and per-UID POSIX file locks. A service takes over a port
after `release_sockets()`; the cooperative lock remains until `close()`.
Uncooperative processes can still bind after socket handoff, so this is not a
claim of atomic listener transfer. Lock files remain in place to keep their
inodes stable. Acquisition failure rolls back this lease's existing handles;
cleanup errors stay failures rather than becoming a successful retry.

This library does not start a backend or wire an execution mode into
`run-suite.py`. All catalog entries remain pending. Process/workspace/simulator
ownership and actual app-storage cleanup are separate follow-up work. Tests
use private temporary directories, real ephemeral loopback sockets, and one
owned Python subprocess to verify cross-process lock exclusion:

```bash
python3 -B -m unittest scripts/e2e/test_native_ports.py
```

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

The onboarding runner funds fresh external Gift addresses through the existing
Python driver, then drives **Activate gift card → Paste card link** in a walletless
app. It verifies account/passcode persistence, real claim transactions and Home
Activity, six-confirmation bearer/temporary DB cleanup, manual setup carousel,
backup deferral/completion and birthday, education, first-wallet passphrase
import, and deletion of a waiting card with its removed recipient. The runner
passes the mobile tag/define and opts into skipped mobile tests. It does not
capture recovery words or bearer links, and skips native biometric enrollment.
Both Gift runners reset the disposable regtest chain by default; run them
serially. `E2E_DRIVER_PORT` selects the onboarding driver's port.

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
