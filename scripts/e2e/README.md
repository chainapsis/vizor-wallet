# End-to-end tests

## Zakura regtest

`scripts/e2e/zakura-run.py` runs regtest scenarios one at a time, each on its
own fresh Zakura regtest chain. The Rust regtest suite
(`./run-regtest-rust-tests.sh`) and the Flutter regtest runners
(`scripts/e2e/flutter-*.sh`) run on it.

For every scenario, the runner:

1. starts a Zakura node and lightwalletd (`zakura_regtest.py`) on a private
   Docker network with leased host ports;
2. mines 100 blocks, or more for a few Flutter scenarios, so the chain's
   coinbase can fund wallets;
3. funds a Flutter scenario's wallets;
4. starts the Dart lightwalletd shim (`zakura_lwd_shim.dart`), which serves the
   node-verified genesis tree state and reports the chain as `regtest`;
5. serves an HTTP control for funding, mining, activation, reorgs and
   lightwalletd outages;
6. runs the test, then removes the containers, network, volume and wallet files.

The node runs the official `zakuracore/zakura` image (1.6.0), and lightwalletd
the build Zcash Labs makes for Zakura
(`ghcr.io/zcashlabs/thus-spoke-zakura-lightwalletd` 0.3.0). `zakura_regtest.py`
pins both by digest. Tests steer the chain only with RPCs Zakura ships for
Regtest: `generate`, `submitblock` and `invalidateblock`. Zakura cannot keep a
mempool transaction out of the blocks it mines, so to hold transactions pending
or to build a reorg branch, a second node without peers mines the blocks and
the main node accepts them through `submitblock`.

Ironwood (NU6.3) is active from height 1. Scenarios that fund Orchard before a
controlled activation (`rust.ironwood.*`, `flutter.*.ironwood-*` and the voting
scenarios) use a chain that activates it at height 500.

Funding transactions are signed offline by
`rust/examples/regtest_direct_funder.rs` from the chain's coinbase, which pays
a public test-only key, and are broadcast with the node's `sendrawtransaction`.
Nothing uses a node wallet. The signer and the Rust test executables are built
from `git archive HEAD rust`, so the runner refuses to start while `rust/` has
uncommitted changes.

Every run asks for the same build, the signer with every catalog Rust target
and the address tool, and keeps it in `.regtest-logs/build-cache/funder-v1`,
keyed by the committed `rust/` tree, the Rust toolchain, the Apple linker and
the Cargo dependencies. A later run with the same inputs, whatever scenarios it
selects, skips the 8 to 16 minute build; `report.json` says whether it hit.
Each entry is about 500 MB. `prune-build-cache.py` lists the cache, and with
`--apply` removes all but each kind's two newest entries, skipping any that a
running run holds:

```bash
python3 scripts/e2e/prune-build-cache.py
python3 scripts/e2e/prune-build-cache.py --apply
```

Prerequisites: Python 3.11+, Docker, `grpcurl`, the fvm-pinned Flutter SDK after
`fvm flutter pub get`, and fetched Cargo dependencies (`cargo fetch --locked` in
`rust/`). Pinned images that Docker lacks are pulled by digest before the first
scenario.

```bash
python3 scripts/e2e/zakura-run.py --list
python3 scripts/e2e/zakura-run.py rust.import rust.send.basic
python3 scripts/e2e/zakura-run.py flutter.ios
```

Each run writes `.regtest-logs/zakura-<run id>/report.json` with every
scenario's status, phase durations and evidence directory, which holds its
process logs and the chain's records. The run's build output (several GB) is
removed when the run ends. `--keep-failed` keeps the stopped containers and
wallet files of failed scenarios; the report lists their Docker IDs. Remove them
with `docker rm`, `docker network rm` and `docker volume rm`, and the run
directory, when done.

The harness unit tests run offline with Docker mocked. Some replace modules,
so run each file in its own interpreter, from `scripts/e2e`:

```bash
cd scripts/e2e && for test in test_*.py; do python3 -B -m unittest "${test%.py}" || break; done
```

### Flutter scenarios

Each Flutter regtest runner, such as
`scripts/e2e/flutter-macos-regtest-import-sync.sh`, runs `zakura-run.py` with
its scenario IDs and passes its arguments on. `flutter-macos-regtest-full.sh`
and `flutter-ios-regtest-mobile-full.sh` run the platform suites. The catalog,
`zakura_flutter.py`, gives each scenario its test files, process phases,
funding and defines. The tests fund, mine, reorg and stop lightwalletd through
the control (`integration_test/support/regtest_control.dart`).

The app's endpoints are compile-time defines, so Flutter scenarios use fixed
loopback ports: the control on 18232 (`ZCASH_E2E_DRIVER_URL`), the shim on 9067
and the in-test fault proxy on 19068. Port 19067 must stay unbound because the
endpoint tests use it as an unavailable server. The screenshot scenarios also
take 39070, and the voting scenarios take 1317, 13000, 18080 and 26657. Run one
Flutter runner at a time on a host.

macOS windows stay hidden unless `VIZOR_E2E_HIDDEN_WINDOW=false` is set. iOS
scenarios run on a simulator that the run creates and deletes at the end:
`Vizor Zakura E2E <run id>`, an iPhone 16 on the newest installed iOS runtime
unless `--ios-runtime` names another one. `--keep-failed` keeps it along with
the failed scenarios' chains. The run never uses other simulators. `--dart-define=NAME=VALUE`
adds a define to every Flutter phase, but it cannot repeat a define the
scenario already sets.

Keep the Mac unlocked while Flutter scenarios run. A locked session makes the
app's keychain writes fail and can leave platform calls unanswered, so a run
with Flutter scenarios does not start, and stops before its next case, while
the session is locked; a case that fails while it is locked says so in its
error. When a phase prints nothing for four minutes or misses its deadline, the
run saves the app's thread stacks (`sample`) in the case's `stacks/`.

Before the first case, a run with voting scenarios fetches the pinned
`valargroup/vote-sdk` and `valargroup/vote-nullifier-pir` revisions into
`.regtest-voting/deps` and builds them (`voting-services.sh build`, logged to
`voting-build.log`). This needs network access, Go, Cargo and `make`. Once the
desktop setup phase has migrated the voting power, `voting-services.sh` starts
the vote chain, the nullifier PIR server and the voting gateway against the
case's chain. Their logs and the gateway's screenshots are written to the case's
`voting/logs/`. The PIR data and the vote chain home, several GB that each case
regenerates, are removed once the case stops. The final-tally scenarios,
`flutter.macos.voting-final-tally` and
`flutter.macos.voting-ledger-final-tally`, also wait for the round to finalize
and check its tally. Their vote window is 300 seconds unless
`E2E_VOTE_WINDOW_SECS` sets another. `scripts/e2e/ledger-speculos-docker.sh
voting-tally` runs them, with the Ledger one signing on its Speculos device.

The other Ledger Speculos lanes, the mainnet keychain runner and the payment-URI
prefill runner need no regtest chain and run as before.

## Gift Cards

Sender usage tracking and empty observer DB reuse:

```bash
scripts/e2e/flutter-macos-regtest-gift-card-tracking.sh
```

This runner imports the funded sender, drives creation and receipt in the UI,
and checks `Unused`, `Use detected` at one confirmation, and `Used` plus
automatic observer deletion at six. It then restarts the process after 200 mined
blocks, checks persisted usage and the same empty DB path, and repeats the
lifecycle for a new card. It uses the production tracking timer rather than
forcing refreshes. The prepare and resume tests run as two processes of one
scenario, because resume needs prepare's wallet and manifest. The runner copies
the app-content PNG captures into the case's `captures/` directory.

The companion Rust scenario verifies the skipped block interval directly with
real shielded notes and a changed tree frontier, then imports an older card:

```bash
./run-regtest-rust-tests.sh rust.gift-card.tracking-multiple rust.gift-card.empty-db-reuse
```

Each test starts its own Zakura regtest chain, so it does not share a chain
with app E2Es. It uses temporary wallet DBs and does not inject scan queue rows.
The test is excluded from ordinary Rust test runs.


The macOS regtest runners cover the Gift Card (payment-link) flows. Their
scenarios fund the sender account and pass the payment-link defines every phase
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

The outcomes runner runs two scenarios of two processes each. In
`flutter.macos.gift-card-competition`, the competition leaves a real losing card
and the next process removes it. In `flutter.macos.gift-card-response`, a
prepare/resume pair recovers a transaction whose accepted response was dropped.
It checks five versus six confirmations, winner/loser balances, a fresh
observer's spend evidence, retained secrets and claim databases, and zero
transmissions during a manual status check. A fully spent competing card resolves
to `Claimed elsewhere` and can be removed; `Claim failed` is reserved for other
settled failures.
Automatic claim recovery is gated only during the manual-check measurement,
then released to execute the production recovery path.

Each scenario gets its own chain, and the fault proxy listens on 19068.
`--keep-failed` keeps a failed scenario's chain for inspection. As with the
other runners, run it only when regtest execution is intended.

The Gift Card scenarios set `VIZOR_DEEPLINK_BASE_URL` to
`https://link-dev.vizor.cash`.

The iOS simulator runs the round trip too, against the mobile Settings ›
My Gift Cards surface:

```bash
# Create, open, and claim a card between two accounts, on the simulator.
scripts/e2e/flutter-ios-regtest-mobile-payment-link-round-trip.sh

# First-wallet Gift creation/import, receipt, Home setup, and recipient removal.
scripts/e2e/flutter-ios-regtest-mobile-gift-onboarding.sh
```

It is part of `scripts/e2e/flutter-ios-regtest-mobile-full.sh`. Besides
`VIZOR_FORM_FACTOR=mobile` and the regtest defines, the scenario passes
`VIZOR_PAYMENT_LINK_REGTEST_ENABLED=true`, without which payment links stay
gated off, and `VIZOR_DEEPLINK_BASE_URL`.

The onboarding test funds fresh external Gift addresses with Ironwood notes
through the control. Each card takes one of three coinbases that the
scenario reserves.

The onboarding test drives **Activate gift card → Paste card link** in a walletless
app. It verifies account/passcode persistence, real claim transactions and Home
Activity, six-confirmation bearer/temporary DB cleanup, manual setup carousel,
backup deferral/completion and birthday, education, first-wallet passphrase
import, and deletion of a waiting card with its removed recipient. The runner
passes the mobile tag/define and opts into skipped mobile tests. It does not
capture recovery words or bearer links, and skips native biometric enrollment.

The desktop and simulator round-trip runners also accept
`--dart-define=GIFT_CARD_E2E_AMOUNT_MODE=usd` or `usd-max` (the default is
`zec`). These modes fix only the USD price at $125.50 per ZEC, check both
currency switches, and use real regtest funding and claims. The `usd-max`
case checks that rounding the visible dollar amount preserves the exact
ZEC Max quote through the copied card link and recipient balance:

```bash
scripts/e2e/flutter-macos-regtest-payment-link-round-trip.sh \
  --dart-define=GIFT_CARD_E2E_AMOUNT_MODE=usd-max

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
runner's mobile and regtest defines; no payment-link or deeplink define applies.
