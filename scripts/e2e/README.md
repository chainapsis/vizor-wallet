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

## Owned process lifecycle primitive

`e2e_runtime.py` starts each command in a new POSIX session/process group and
returns an owned `ManagedProcess` handle. `wait_managed_process()` accepts
that handle, not an arbitrary PID or existing subprocess. A command completes
only after its direct child is reaped, no group member or thread remains active,
and its output pump has finished. A parent exit or output EOF alone is not
completion.
Cancellation, timeout, and interruption stop the group; termination escalates
from TERM to KILL within one bounded cleanup budget. Verified completion is
latched so repeated cleanup cannot signal a subsequently reused group ID.

On Linux, adopted children owned by the runner are reaped only within this
command's group, after its direct child is reaped. A group containing only
externally parented zombies can also finish: two matching `/proc` snapshots
must verify every member and thread is a zombie. Those remaining kernel records
are exposed as `unreaped_zombie_pids`, an observation at cleanup, not future
signal targets or a claim that all PIDs were reaped. Live or stopped threads,
unreadable state, and incomplete inventories cannot prove completion. The
runner does not change process-wide subreaper or `SIGCHLD` policy.

Logging and cleanup failures remain failures, even if a later cleanup attempt
physically releases the resources. Cancellation/interrupt type and timeout
exit code are retained when cleanup also fails. Callers must not release
dependent case state unless `cleanup_completed` is true. Handles have one
lifecycle owner; concurrent waits/cleanup are unsupported. Descendants must
remain in the launched group: this is not containment of daemonizing code.

The persisted log redacts the prototype's known credential markers, not all
possible secrets. Raw output in `CommandResult.lines` or `raw_lines` is for
in-memory protocol consumers and must not be published as sanitized evidence.
No backend, app, simulator, execution mode, or catalog support flag is wired
by this library. The host-only tests launch disposable Python children, with
Linux-specific adoption and thread checks skipped on other hosts. Linux host
primitive checks do not enable Linux wallet E2E execution:

```bash
python3 -B -m unittest scripts/e2e/test_e2e_runtime.py
```

The Linux checks also run descendant cancellation, interruption, EOF, and
SIGKILL cases under a private fixture parent that delays zombie reaping. This
covers an ordinary runner beneath a non-reaping PID 1, not just a runner that
owns adopted children itself. Release assertions recheck that any remaining
members are recorded zombies, including their threads; missing proof or live
members still fail. Subreaper policy remains confined to the disposable fixture
process.

## Owned native case workspace primitive

`native_workspace.py` allocates one private directory per case under an existing,
private canonical run root: `e2e/vizor_<run_id>_w<worker_id>_<case_index>`.
`prepare_native_case_workspace()` returns an owned handle only after its marker
and schema-1 manifest are written and verified. Allocation is exclusive within
that run root: existing directories and partial allocations are never adopted,
overwritten, or reset. Failed allocations retain their on-disk evidence.

`launch_environment()` emits the two environment values in the
[native runtime contract](RUNTIME_CONTRACT.md). `VIZOR_E2E_CASE_MANIFEST` is the
ASCII JSON value, not a filename. macOS uses the owned case's `native-context.json`
path; iOS uses `app-support`. Run/worker/case identity, scenario/platform syntax,
distinct port values, explicit activation height, and the 2048-byte bound match
that contract. Restarts reuse the same handle and retain mutable state; reruns
require fresh run identity. Changing the caller's port map cannot rebind a case.

Before each launch phase, the handle rechecks original directory/file identities,
ownership, permissions, link safety, and exact metadata. Verification failures
are sticky. This is a cooperative filesystem boundary, not containment of
untrusted code. Callers must allocate fresh run IDs and hold actual port leases;
the manifest's port numbers do not prove reservation or service readiness.

There is no deletion or native-cleanup operation in this slice. Workspaces and
evidence remain on disk; no marker or context declaration authorizes cleanup of
wallets, Keychain, preferences, or simulators. This library copies no source or
build cache and wires no executor or catalog support flag. Host-only checks use
private temporary directories and owned Python children:

```bash
python3 -B -m unittest scripts/e2e/test_native_workspace.py
```

## Case-bound process lifecycle primitive

`native_case_lifecycle.py` composes the owned workspace and process primitives.
Create one `NativeCaseLifecycle` per workspace. Claiming is cooperative and
single-owner: a second owner, including a copied workspace handle, cannot adopt
the case. Do not call its methods concurrently or launch untracked processes
with the workspace's environment.

`start_process()` binds the case's immutable namespace/manifest, uses its owned
directory as cwd, and reserves a fresh private log without overwriting a file
or symlink. Conflicting caller identity fails before spawn. `wait_process()`
preserves exit codes and timeout/cancellation classification; `stop_process()`
stops only a handle launched by this case. Restarts keep the same identity and
state. Failed launch/registration without a returned handle conservatively
seals the case and prevents a successful cleanup record.

Final `close()` seals future launches and attempts every tracked group, with a
timeout budget per group. It does not skip remaining groups when one cleanup
fails or when workspace verification fails. Success requires the shared
primitive's positive child/group/output cleanup and intact workspace ownership.
Cleanup failures remain sticky. Repeated successful close does not signal a
retired numeric group again.

`CaseProcessCleanup` records namespace, workspace, exit codes, and any observed
external Linux zombies. It is a historical process/output observation, not a
test PASS, permission to delete files, or proof of native storage/simulator
cleanup. Nonzero exit codes remain nonzero; zombie PIDs are not future kill
targets. Files, logs, native context declarations, and failure evidence remain
on disk. This slice wires no executor, port leases, simulator, backend, or
catalog support flag and changes no app code.

```bash
python3 -B -m unittest scripts/e2e/test_native_case_lifecycle.py
```

## Fresh case-owned iOS simulator primitive

`native_ios_simulator.py` allocates a new simulator for an open iOS
`NativeCaseLifecycle`. `acquire_ios_simulator()` requires explicit installed
runtime and device-type identifiers and checks runtime support before creation.
It never adopts an existing UUID or case name and does not choose the newest
runtime automatically. Allocation requires macOS and Xcode's `simctl`.

The allocation intent is published exclusively before `create`; the successful
result's new UUID is then bound to private owner metadata. Every operation
rechecks the original workspace/metadata identities and the exact UUID's
runtime, type, availability, and name in the current inventory. `boot()` waits
for `bootstatus` and a positive `Booted` observation. All device mutations use
that captured UUID, never `booted`, `all`, `unavailable`, or a device name.
`SIMCTL_CHILD_*` host values are excluded from SDK commands so boot does not
inherit unrelated child-environment overrides.

`close()` seals and closes case process groups first, then uses a separate
bounded simulator-command budget to shut down the owned device. Only a fresh
**pre-app** case with no phase launches and proven teardown can be deleted;
success also requires positive absence in the device inventory. Any case launch
(even a backend or Python phase) conservatively requires native cleanup that is
not implemented here, so it retains the shut-down device and returns an error.
Process, ownership, or cleanup uncertainty also prevents deletion and remains
a failure after a later retry. A helper command exception supplies no process
handle/proof and conservatively blocks deletion; an ordinary nonzero command
result retains its execution error but can still permit verified pre-app teardown.

The `SimulatorCleanup` record observes deletion of this fresh pre-app device,
not Keychain, preferences, wallet-storage cleanup, or an E2E PASS. Case files,
allocation markers, and command logs remain on disk, including failed/partial
allocations. Unknown creation outcomes are not recovered by searching names or
deleting broad sets of devices. Report-scoped recovery is separate work.

Use one cooperative lifecycle owner and do not call these methods concurrently.
Do not install/launch apps or mutate device state outside the case owner; this
primitive does not discover untracked activity or contain untrusted code. It
does not build/install an app, implement native storage cleanup, start a backend,
wire `run-suite.py`, or make pending catalog entries runnable.

Portable tests use a modelled `simctl` transport and an owned Python phase, not
real iOS execution. Real-device validation requires a separately allocated
fresh simulator on macOS; Linux test success is not an iOS support claim.

```bash
python3 -B -m unittest scripts/e2e/test_native_ios_simulator.py
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
