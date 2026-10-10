# End-to-end tests

For the planned isolated execution framework and direct Zakura migration, see
the [E2E roadmap](ROADMAP.md). The roadmap tracks unmerged work. The isolated
executor implements all twenty-three Rust and twenty macOS cases, including
voting, import/endpoint, send, shielding, payment-request, mempool and Gift;
existing shell runners remain.

The [native runtime contract](RUNTIME_CONTRACT.md) defines per-case launch
identity and storage isolation for the later worker/executor layers. It does
not add an execution backend or make pending catalog entries runnable.

## Pinned Zakura fixture source

`zakura_fixture_source.py` reads the fixture's Git blob from one published,
immutable [contributor-fork commit](https://github.com/piatoss3612/zakura/commit/5ecafcfdb43cf42f34c8046f09c6d874b567daa4).
This is proposed tooling, not an official Zakura release. The helper's exact
commit, path, byte count, SHA-256 and node/lightwalletd image digests are pinned
in the module. Updates require a reviewed pin change; there is no latest-tag
fallback or implicit download.

Provide a local Zakura Git object cache containing that exact commit and blob. The
loader does not execute the checkout's script, require a clean checkout, change
HEAD or fetch anything. It disables Git replacement objects and executes the
same captured bytes that passed SHA-256 verification, avoiding a second file
read between verification and import. Each load has its own module identity.
The returned code identity is not resource ownership, readiness or scenario PASS.
Each read sets `GIT_ALLOW_PROTOCOL` to an empty allow-list, denying every Git
transport even if the cache has a promisor remote or permissive protocol config.
There is no dependency on the newer `--no-lazy-fetch` option. A partial cache
missing tree/blob objects is rejected without downloading them. To populate
a complete local cache explicitly:

```bash
git -C /path/to/zakura fetch https://github.com/piatoss3612/zakura.git 5ecafcfdb43cf42f34c8046f09c6d874b567daa4:refs/vizor-e2e/zakura-fixture/5ecafcfdb43cf42f34c8046f09c6d874b567daa4
```

The commit-specific destination ref keeps the cached commit reachable during
Git garbage collection, without changing HEAD or an existing branch/tag. The
loader still uses the fixed commit ID, never the mutable ref as source authority.

Each backend requests an explicit RFC1918 `/28` subnet derived from its fresh
fixture UUID. This avoids exhausting Docker's larger default address pools when
failed fixtures are retained. Only immutable builds are shared, never networks.
Docker rejects overlapping subnets; a collision stays a startup failure, without
pruning, adopting, or retrying another fixture's resources. The start proof records
the requested subnet. Existing retained networks, containers, and volumes remain.

This source-loading boundary starts no Docker resource, wallet or test, and
does not enable catalog execution. Offline checks use disposable Git commits:

```bash
python3 -B -m unittest scripts/e2e/test_zakura_fixture_source.py
```

## Catalog previews

`run-suite.py` provides a host-only inventory and selection preview. Of 64
entries, all twenty-three Rust, twenty macOS and twenty-one iOS Simulator
cases are wired to the isolated executor. Runnable is an execution capability,
not a claim that every case passed together on the final implementation source.
A preview exit code of 0 means the preview succeeded,
not that any test ran or passed. Execution requires explicit `--run`.

Previews require Python 3.9 or newer and use only the standard library. Actual
isolated execution requires Python 3.11 or newer for the standard TOML parser
that binds Cargo-selected build tools to cache identity. Git is
also required for `--changed-from`; Flutter, Docker, and a running regtest stack
are not needed for previews or the host-only checks below.
Use `python3.11` (or a newer interpreter) for execution and builder/cache
host checks, including CLI tests that mock supported execution. Pure
catalog/selector checks and public previews still run on Python 3.9.

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
python3.11 -B -m unittest scripts/e2e/test_e2e_catalog.py scripts/e2e/test_e2e_report.py scripts/e2e/test_e2e_changes.py scripts/e2e/test_e2e_impact.py scripts/e2e/test_run_suite.py
```

## Isolated iOS Simulator execution

The iOS executor builds one signed Simulator cohort and cleanup helper before
dispatch. Each case owns a fresh device, wallet/native storage, ports and pinned
Zakura/lightwalletd backend; restarts retain only their original case's state.
The original UIKit PID's VM event binds Driver discovery. Financial, receipt,
inclusion, fee, reorg, restart, account recovery and outbox assertions remain.
Outbox transport is not positive authorized OS-background scheduling coverage.

Use the common macOS tooling requirements below plus an installed, available
iOS Simulator runtime and a device type that it supports. Flutter dependencies
must already be resolved with Dart3.12 or newer; the official Riverpod3.4.2
prerequisite is separate from this executor. The runner installs nothing and
never adopts an existing developer device. Preview the21-case suite first:

```bash
python3 -B scripts/e2e/run-suite.py --suite flutter-ios-full --plan
python3.11 -B scripts/e2e/run-suite.py --suite flutter-ios-full --run \
  --flutter /absolute/flutter-sdk/bin/flutter \
  --zakura-cache /absolute/zakura-git-cache \
  --grpcurl /absolute/bin/grpcurl \
  --proto-dir /absolute/lightwalletd-protos \
  --ios-runtime com.apple.CoreSimulator.SimRuntime.iOS-26-3 \
  --ios-device-type com.apple.CoreSimulator.SimDeviceType.iPhone-16 \
  --build-jobs 4 --workers 2
```

Replace the runtime/device examples with identifiers available on your host.
Select a single case with `--scenario`, or rerun only failures using
`--failed-from /absolute/prior/repetition-0/run.json` and the same tool arguments.
The original failed report is not rewritten. iOS and macOS selections can share
one invocation's worker budget; runtime/device arguments are required whenever
iOS is selected. Evidence stays in `.regtest-logs/native-suite-<id>/`.

Actual full21 run34c9e26ffa on clean6b083b58e finished19 PASS/2 FAIL.
After synchronizing backend parity and pre-removal wallet scanning, failed-only
run989c2e115c on clean e7aa6909f passed both original cases in485.319s including
one app/helper build. Both passed native/backend cleanup; older failed evidence
and devices remain retained. These revision-specific runs do not establish a
same-final-source all-green21/64-case result or current-policy cache coverage.

### Timing-informed dispatch and resource budgets

`--timing-report /path/to/run.json` reads an existing schema-2 case report with
the current catalog fingerprint and matching profile/target/test identities.
Repeat it for median successful case durations. Failures, timeouts, cancellations
and unstarted cases do not supply completed-case estimates. Timings include
case preparation and cleanup, not the shared build. Older source commits remain
recorded provenance, never evidence that the current wallet passed.

The default `--order short-first` dispatches measured short cases first for early
feedback. `--order long-first` starts measured long cases first to reduce a late
tail; neither guarantees a shorter whole run under contention. `--order catalog`
uses inventory order. Cases without successful timings follow measured cases in
catalog order; without timings, all modes use catalog order. `--plan` shows the
dispatch order and report hashes without launching or writing anything.

```bash
python3 scripts/e2e/run-suite.py --suite rust-direct --plan \
  --order long-first --timing-report /path/to/prior/repetition-0/run.json
```

Shared artifact producers run one at a time before the case queue. `--build-jobs`
controls the Cargo job budget; it is not a global Flutter/Xcode CPU limit.
`--workers` bounds concurrent case owners across engines and fresh repetitions.
Fresh iOS device preparation (boot, helper install and native absence checks)
has a separate maximum of two simultaneous operations within that worker
budget. Waiting happens before device allocation and does not consume the
unchanged120-second preparation timeout. The slot is released before backend
and wallet execution, so already prepared cases still use the global worker
limit. Failed preparation retains/joins its original owner before releasing
the slot; unproven retention cancels queued admissions. Reports include
`ios_preparation_slots` (zero when no iOS scenarios are selected).
The runner records these separate budgets and reports each completed case
immediately, retaining selected catalog order in the final results. Independent
wallet/backend/native state and existing assertions remain unchanged. Unproven
worker retention cancels subsequent case allocation. No CPU/RAM-based automatic
worker limit or measured general speedup is claimed by this dispatch policy.

```bash
python3.11 -B -m unittest scripts/e2e/test_e2e_schedule.py scripts/e2e/test_run_suite.py scripts/e2e/test_native_macos_suite.py
```

## Isolated macOS import and endpoint execution

The selected native cohort/helper pair, offline signer and Rust test executables
use immutable caches by default. A miss builds each selected artifact once;
a hit records zero corresponding builds and creates fresh publication copies.
Each case has fresh wallet/Keychain/preferences storage,
ports and its own pinned Zakura/lightwalletd containers. The existing import
test still requires shielded **1.25** and transparent **0.75**; a completed
Driver connection or empty successful test response is not assertion completion.
The sandbox app returns its storage observation through its original Driver,
which writes the host evidence file. Neither that observation nor a JSON receipt
authorizes cleanup; the original worker must prove terminal cleanup itself.

Requirements: macOS, Python 3.11 or newer, Flutter dependencies already resolved,
Xcode/Swift and an
available development identity/profile that signs the native app, Docker,
grpcurl/protos, the pinned Zakura Git object cache above, and Cargo dependencies
already available for the offline signer build. Commit Rust changes first: the
signer uses the exact committed Rust subtree rather than mixing source versions.
Use explicit absolute tooling paths; no automatic installation or download.

```bash
python3.11 -B scripts/e2e/run-suite.py \
  --scenario flutter.macos.import-sync --run \
  --flutter /absolute/flutter-sdk/bin/flutter \
  --zakura-cache /absolute/zakura-git-cache \
  --grpcurl /absolute/bin/grpcurl \
  --proto-dir /absolute/lightwalletd-protos \
  --build-jobs 4 --workers 2 --repeat 2
```

`--repeat 2` creates two independent executions, not a retry that erases the
first result. `--workers 2` permits both to overlap after one shared build;
selecting one scenario without repetitions only uses one worker.

The same cohort also runs `flutter.macos.fallback-endpoint`,
`flutter.macos.custom-endpoint-no-fallback`, `flutter.macos.slow-height-fallback`
and `flutter.macos.sync-startup-stall-recovery`. Repeat `--scenario` to combine
only the cases needed, using the same explicit tooling arguments above:

```bash
python3.11 -B scripts/e2e/run-suite.py \
  --scenario flutter.macos.fallback-endpoint \
  --scenario flutter.macos.custom-endpoint-no-fallback \
  --scenario flutter.macos.slow-height-fallback \
  --scenario flutter.macos.sync-startup-stall-recovery --plan
```

Replace `--plan` with `--run` and add the tooling paths and `--workers 2` to
execute that selection. Each proxy uses its case's leased ports, not shared
19068/9067. The custom-endpoint case uses its own unserved port and keeps the
no-fallback privacy assertions. Fallback still requires the original 1.25
balance; slow-height recovery still checks 1.25, 1.75, 2.00 and 2.25 through
fallback, recovered primary and primary-down transitions. Its later payments
use integer zatoshis, independently signed transactions, the direct inclusion
oracle and the original three confirmation blocks. Startup recovery retains
the actual first-stream stall, healthy retry and persisted completed status.
Evidence stays in `.regtest-logs/native-suite-<id>/`. Each repetition's
`run.json` is a schema-2 report accepted by the existing `--failed-from` selector;
`summary.json` records the batch/build counts. Failed cases keep state/logs,
and uncertain cleanup remains failure. Cancellation stops owned children and
new assignment without terminating ordinary wallet processes.

Build artifact reuse does not establish a wallet PASS or a general measured
speedup. Resource/performance comparison
and final-source all-green catalog are still pending. No CI behavior changes.

## Isolated macOS send, shielding and payment requests

These seven cases share one macOS cohort/helper build and one offline signer
build while retaining separate wallet storage, chain state and ports. Use the
same requirements and absolute tooling paths as the import example above:

```bash
python3.11 -B scripts/e2e/run-suite.py \
  --scenario flutter.macos.shield-transparent \
  --scenario flutter.macos.shield-transparent-retry \
  --scenario flutter.macos.multi-account-send \
  --scenario flutter.macos.tex-send \
  --scenario flutter.macos.payment-uri-send \
  --scenario flutter.macos.payment-uri-locked-send \
  --scenario flutter.macos.payment-request-round-trip --plan
```

Replace `--plan` with `--run`, add the tooling paths and `--workers 2`.
The original balance, fee, history, retry, locked-URI and ZIP320 return/shielding
assertions remain. Funding uses exact integer zatoshis and independent inclusion
checks. The existing public SDK address example derives the second wallet's TEX
address in the same Cargo build; the TEX app alone receives its existing debug
ephemeral-check flag. No production app or dependency code changes here.

Copy/paste still uses the real OS clipboard. Only the copy/read section acquires
a cooperative per-UID lock, shared across runner processes. A failed section
retains that lease until the original app/driver writers have stopped; closing
an HTTP listener alone cannot release it. Other cases can continue concurrently.
Mining, funding and bounded raw-transaction reads use the original case's
controller, not shared node-wallet RPC. Existing manual shell runs outside the
isolated cohort retain their deployed path. Failed cases retain state/logs;
cleanup does not delete a DB while Rust work is still active.

Rerun only failures from the original schema-2 report with
`--failed-from .regtest-logs/native-suite-<id>/repetition-0/run.json --run`, plus
the same tooling arguments. The [roadmap](ROADMAP.md) records the separate
five-pass/two-failure batch and corrected two-case rerun; they are not one
final-source seven-case pass or a measured performance improvement.

## Isolated Rust execution

The same coordinator runs `rust.receive.sync`, `rust.send.basic`,
`rust.send.second-account` and the five `rust.import.*` cases for
`bip39-passphrase`, `historical-birthday`, `future-birthday`, `receive-after-sync`
and `deterministic-reimport`. Use the same absolute tooling paths shown above:

```bash
python3.11 -B scripts/e2e/run-suite.py \
  --scenario rust.receive.sync --scenario rust.send.basic \
  --scenario rust.import.bip39-passphrase --plan
```

Replace `--plan` with `--run`, add the tooling paths and `--workers 2`.
Commit Rust inputs first. One offline Cargo invocation builds the selected test
targets and signer from that committed subtree. Rust-only selections build no
native app/helper; mixed Rust/macOS selections use the same signer and bounded
worker queue. Only read-only executables are shared, never wallet DBs or chains.
Rust execution currently targets the host macOS platform; it is not Linux coverage.

The test-only common adapter validates its original manifest, configures the
scenario-bound height-one or activation-500 profile, uses its case's LWD/control ports and creates DBs under its
own wallet root. It rejects shared regtest shell scripts in isolated mode.
Funding uses exact integer zatoshis, independent coinbase sources, the existing
signer/inclusion oracles and ten confirmations. The original financial checks
remain. The BIP39 import expects the current Orchard-only receive address,
independently derives both current and legacy public-vector goldens, and still
recovers the funds sent to the legacy address and checks the BIP44 address.

The executor requires exactly the selected test's successful libtest result;
exit zero with no tests or an ignored/different test is not PASS. TempDir drop
does not erase isolated DBs: the original host stops/joins writers before
anchored wallet/backend/port removal, or retains failed DBs and logs. The same
schema-2 per-repetition reports support `--failed-from` without rewriting an
earlier failure. Ordinary shared shell runs keep their existing behavior.

All eight `rust.multi-account.*` cases use the same original owner and one
`regtest_multi_account` binary. They preserve historical/future recovery,
account balance separation, existing history and idempotent-sync assertions.
Select just this domain without building the native app/helper:

```bash
python3.11 -B scripts/e2e/run-suite.py \
  --changed-file rust/tests/regtest_multi_account.rs --plan
```

Replace `--plan` with `--run` and provide the tooling paths above. The two
orphaned/deleted scan-range regressions intentionally inject historical
scan-queue state because regtest cannot naturally reproduce a mainnet partial
scan. These scenarios use the narrowly scoped rc7 SQLite
[backport](../../rust/vendor/README.md), which also affects production builds.
No SDK package versions or database schemas change.

The same executor also runs `rust.receive.direct-zakura`,
`rust.import.direct-zakura` and `rust.gift-card.tracking-multiple`,
`rust.gift-card.empty-db-reuse`, `rust.gift-card.competition`. Direct receive/import
require exactly 100,000,000 Ironwood zatoshis, six confirmations, complete sync,
matching history/txid and no other balances. The BIP39 import independently
derives the public vector and verifies a wrong-passphrase wallet stays empty.
Direct cases require the original isolated manifest/controller; there is no
shared-service fallback or filesystem funding handoff.

Gift observer databases use the owned wallet root as well. Existing observer
retirement, empty-gap recovery and competing-claim financial assertions remain;
the rejected claimant must retain complete transaction IDs, and independent
funding transactions must differ. Example side-effect-free selection:

```bash
python3.11 -B scripts/e2e/run-suite.py \
  --scenario rust.receive.direct-zakura --scenario rust.import.direct-zakura \
  --scenario rust.gift-card.tracking-multiple \
  --scenario rust.gift-card.empty-db-reuse --scenario rust.gift-card.competition --plan
```

Add the documented tooling paths and change to `--run` for execution.

The two `rust.ironwood.*` cases start before NU6.3 with activation fixed at
height 500, not height one. Their independently signed Orchard funding is
confirmed before activation. Migration retains denomination scheduling,
planned change and fee checks. Gift retains the one-versus-two/six-confirmation
policy, exact claim value, one-block reorg and discarded-versus-sender OVK checks.
The original pinned fixture owns the donor node, replacement block/raw-transaction
verification, captured held set, explicit release gate and all backend cleanup.
The original control owner forwards those operations; it does not reconstruct
ownership from JSON or implement a second reorg algorithm. Example preview:

```bash
python3.11 -B scripts/e2e/run-suite.py \
  --scenario rust.ironwood.migration --scenario rust.ironwood.gift-card-claim --plan
```

Use `--run`, the tooling paths above and `--workers 2` to execute both with one
Cargo signer/two-target build and independent chains/DBs. All iOS execution
and persistent cache/resource/performance gates remain pending.

## macOS mempool and Gift execution

The three mempool cases cover pending receive/history, discovery during an
active scan, and expiry after controlled mining excludes the held transaction.
Gift round trip, restart and recovery use the same isolated executor. Restart
stops and joins the original app/driver, retains the case's wallet and backend,
mines six blocks (five for recovery), then launches a distinct app/driver on the
same case. Recovery delegates the original multi-block fork replacement and
held-transaction release to the pinned fixture; it is not a one-tip substitute.
Amounts, confirmation/finality, history and claim assertions remain in the tests.
Clipboard sections serialize briefly; independent chain and wallet state do not.
Restart and recovery have overall 30- and 32-minute app-execution budgets:
their existing 15+10 and 15+12-minute test limits plus five minutes for the two
launches, original stop/join and confirmation mining. Phase limits are unchanged.

```bash
python3.11 -B scripts/e2e/run-suite.py \
  --scenario flutter.macos.mempool-receive-history \
  --scenario flutter.macos.mempool-during-sync \
  --scenario flutter.macos.mempool-expiry \
  --scenario flutter.macos.payment-link-round-trip \
  --scenario flutter.macos.payment-link-restart \
  --scenario flutter.macos.payment-link-recovery --plan
```

Use `--run`, the tooling paths above and `--workers 2` to execute with one
cohort/helper/signer build per invocation. The dedicated E2E app enables the
existing `VIZOR_PAYMENT_LINK_REGTEST_ENABLED` compile flag; ordinary wallet
builds and its default are unchanged. `--failed-from /path/to/run.json` selects
only failed/timed-out cases without rewriting the earlier report.
The roadmap records incremental three-plus-three actual passes on two source
commits, not a final-source six-case pass or measured resource/speedup result.

## Isolated macOS voting

Both voting scenarios now use the same selected-case executor. Each first
receives exactly 0.13 ZEC Orchard before activation at height 500, imports the
real wallet and performs the existing immediate Orchard-to-Ironwood migration.
After ten confirmations, the host joins the setup app/driver without deleting
its wallet or backend. It exports that chain's real Ironwood nullifiers, starts
case-owned PIR/vote/helper/gateway services, creates a real round and signs its
configuration. A distinct app process opens the preserved wallet and completes
the original discovery, eligibility, delegation, commitment and share proofs.
The slow-helper variant also requires overlapping delayed share requests;
both require a nonempty real commitment tree. No assertion result is mocked.

Each invocation builds the SDK services, PIR tools and round-creation test once
from these exact source commits, sharing only the joined executable publication
and immutable SDK scripts. Every case retains separate vote home, keys, PIR
dataset, chain, wallet and service-port locks. Locks remain through listener
handoff and release only after original service groups/output capture join.
Clients use loopback URLs; the pinned upstream `nf-server` itself listens on
all interfaces because that revision exposes no bind-address option. This is
mutable-state isolation, not a network sandbox. Cleanup uncertainty fails and
retains original state/evidence. The 75-minute app-execution budget preserves
the existing 15-minute migration and 45-minute voting limits, plus service setup
and restart allowance. Build budgets are separate.

Voting selections additionally require Git source caches for
`vote-sdk` commit `36f5d828fc5be42d9a80baa38d1145c5541b229e` and
`vote-nullifier-pir` commit `20356d14f61a825ef28726f38270c37d604cc268`,
plus Go, Make and the pinned Cargo/Go dependencies. The runner reads exact Git
archives offline; it does not fetch or execute the cache's checkout. To prepare
fresh source-only caches explicitly:

```bash
git init --bare /path/to/vote-sdk-cache.git
git -C /path/to/vote-sdk-cache.git fetch https://github.com/valargroup/vote-sdk.git 36f5d828fc5be42d9a80baa38d1145c5541b229e:refs/vizor-e2e/source/36f5d828fc5be42d9a80baa38d1145c5541b229e
git init --bare /path/to/voting-pir-cache.git
git -C /path/to/voting-pir-cache.git fetch https://github.com/valargroup/vote-nullifier-pir.git 20356d14f61a825ef28726f38270c37d604cc268:refs/vizor-e2e/source/20356d14f61a825ef28726f38270c37d604cc268

python3.11 -B scripts/e2e/run-suite.py \
  --scenario flutter.macos.voting --scenario flutter.macos.voting-slow-helper \
  --run --workers 2 \
  --flutter /path/to/flutter/bin/flutter --zakura-cache /path/to/zakura \
  --grpcurl /path/to/grpcurl --proto-dir /path/to/protos \
  --voting-sdk-cache /path/to/vote-sdk-cache.git \
  --voting-pir-cache /path/to/voting-pir-cache.git
```

Use `--plan` without tool/cache paths for a side-effect-free preview. Ordinary
manual shell runners retain their compile-time settings; owned voting supplies
its per-case URLs and trust anchor through test-only runtime/provider seams.
Production source, defaults and financial/proof assertions are unchanged.
The actual two-worker run on clean `c39bd8b8e` passed both cases in
65.619/67.664 seconds, with a build-inclusive 1103.291-second invocation and
proved native/backend cleanup. It is not a serial speedup comparison, persistent
artifact-cache attestation or final-source full-catalog result.

## Native port ownership primitive

`native_ports.py` is the first host-only worker-lifecycle component for macOS
and iOS Simulator runners. It reserves distinct loopback RPC, lightwalletd,
and proxy sockets and per-UID POSIX file locks. A service takes over a port
after `release_sockets()`; the cooperative lock remains until `close()`.
Uncooperative processes can still bind after socket handoff, so this is not a
claim of atomic listener transfer. Lock files remain in place to keep their
inodes stable. Acquisition failure rolls back this lease's existing handles;
cleanup errors stay failures rather than becoming a successful retry.

The per-UID shared parent may be readable/searchable, as in the pinned standalone
fixture, but must be canonical, owned and not writable by other users. The actual
`ports` directory and lock files remain private. Existing directory permissions
are checked, never changed to make acquisition succeed.

This library does not start a backend or wire an execution mode into
`run-suite.py` by itself. Only the forty-three composed Rust/macOS cases above are
runnable; other catalog cases remain pending. Process/workspace/simulator
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
bounded simulator-command budget to shut down the owned device.
SDK command waits reserve the shared runner's five-second process-cleanup
allowance inside that budget; a new command cannot start when the remaining
budget is five seconds or less. This bounds waits/cleanup, not OS spawn or
system-call latency. Case process groups have their separate per-group budget.
Only a fresh **pre-app** case with no phase launches and proven teardown can be deleted;
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

### macOS native storage cleanup helper

The standalone [native cleanup helper](native-cleanup/README.md) observes or
deletes one canonical case's exact macOS regtest Keychain services and preference
prefix. It requires a sandboxed helper signed with the stopped cohort's actual
identity, explicit team matching, noninteractive queries and positive native
absence. Partial/uncertain results remain failures; no values are emitted.

This is not wired to app startup or an executor, does not grant ownership from a
namespace/receipt, and does not remove support/workspace files or simulators.
iOS host composition and full worker cleanup remain pending. Catalog
execution flags are unchanged.

```bash
swift test --package-path scripts/e2e/native-cleanup
```

### Bind macOS cleanup to an owned case

`native_mac_cleanup.py` captures the actual signed helper and cohort artifacts:
valid signatures, sandbox/application/Keychain identity, the same leaf certificate
and public provisioning profile, original directory/file identities and content
digests. It does not derive a team from Xcode defaults. The distinct helper must
be background-only, named `vizor-native-cleanup`, and have only the minimal
cleanup entitlements. The future artifact builder must compile the trusted
helper sources and correct cohort profile; signature capture alone is not source
provenance, nor does this module publish a build/cache.

`clean_mac_case()` verifies artifacts, then uses the case owner's single terminal
command. `run_final_command()` seals normal launches, stops every tracked writer,
and refuses a terminal launch after any unproven process cleanup. It never
reopens the lifecycle, even for a successful close; only one terminal attempt is
allowed. Do not run case methods concurrently or launch untracked native writers.
The helper receives a minimal environment, not caller loader/user-domain overrides.

Only a successful owned process with completed output, unchanged artifacts and
an exact schema-1 deletion receipt can yield `CaseMacCleanupObservation`. Reject
duplicate/extra fields, another namespace/team, partial status, retained items,
unproven preference synchronization, or nonzero exit. No context PID, external
JSON/log, or caller cleanup boolean substitutes for that launch. A failure keeps
logs/state and cannot be retried on the same case. The observation is historical,
not a test PASS or deletion permission; `native-context.json` remains unchanged.

```python
helper = capture_mac_cleanup_helper(helper_app, cohort_app=cohort_app)
observed = clean_mac_case(case, helper, timeout=30, cancel_event=cancel_event)
```

Artifact probes have a 15-second per-command allowance; the terminal command's
`timeout` is its execution wait, with the shared five-second error-cleanup
allowance. Writer close has a separate per-group budget. These are not one hard
wall-time bound (filesystem/system calls can add latency).

```bash
python3 -B -m unittest scripts/e2e/test_native_mac_cleanup.py scripts/e2e/test_native_case_lifecycle.py
```

The host tests model codesign/native receipts but use real private artifacts and
owned children. They do not establish actual Keychain deletion. Workspace
removal, iOS/post-app simulator cleanup, signed helper provisioning/build-once
execution and failed-report recovery remain separate implementation boundaries.

### Own macOS case support storage

`prepare_mac_case_storage()` composes an owned unlaunched macOS case and captured
signed helper. First a read-only `--support-location` SDK query declares the
current sandbox/user-domain support path, using the pinned
[path_provider_foundation 2.6.0 calculation](https://pub.dev/api/archives/path_provider_foundation-2.6.0.tar.gz).
The host checks the exact actual-user sandbox path, creates the case directory
exclusively, and captures original no-follow directory/file identities and a
private marker. Existing case directories are never adopted. A subsequent
read-only native `--verify` must prove both services and prefixed preferences
absent before any wallet launch: a new folder is not proof of fresh secrets.
Failure retains the partial allocation and evidence, without erasing old state.

Use `owner.start_app()` for each direct cohort app launch/restart; ordinary
backend/control phases may use the same case owner, but must not write untracked
native state. The builder still must supply the trusted isolated cohort profile.
After tracked writers stop, context is checked against the exact original case,
latest owned app PID, allocated support path and declared services/preferences.
Context/JSON/PIDs are declarations, not cleanup or signalling permissions.

```python
owner = prepare_mac_case_storage(case, helper, timeout=30, cancel_event=cancel_event)
app = owner.start_app(env=app_environment)
# Execute/observe the scenario and preserve its independent result.
# For a failed scenario: owner.retain() stops writers without deleting state.
cleanup = owner.close(timeout=30, cancel_event=cancel_event)  # successful scenario
```

`close()` seals/stops tracked writers, verifies original identities and a safe
tree, composes the signed terminal native cleanup internally, then rechecks and
removes only that owned support tree through anchored descriptors. Reject
symlinks, hardlinks, nonregular/unowned/writable entries and moved/replaced
parents/children. Require positive final absence. It never accepts an external
cleanup boolean/receipt as deletion authority, removes the case workspace,
rewrites context, or converts an execution failure into PASS.

Use `retain()` for failed scenarios. Unproven cleanup is sticky: do not retry or
adopt partial state. A native or filesystem failure can occur after some owned
state has been removed; remaining state and case logs/markers/manifests stay for
diagnosis. This is not rollback or failed-report recovery. Calls are cooperative
and single-owner; all native writers must remain tracked in owned groups.
Each SDK phase has its own wait/error-cleanup allowance, not a total wall-time SLA.

```bash
python3 -B -m unittest scripts/e2e/test_native_mac_case_storage.py scripts/e2e/test_native_mac_cleanup.py scripts/e2e/test_native_case_lifecycle.py
swift test --package-path scripts/e2e/native-cleanup
```

The host models use real private fake-home files and owned children, not real
wallets or Keychain secrets. Catalog execution, trusted build publication, iOS
host composition and whole-worker teardown remain pending; `runnable` flags stay false.

### iOS Simulator native storage observations

The separate [Simulator helper](native-cleanup/README.md#ios-simulator-contract)
verifies or deletes one canonical case's five exact Keychain services, prefixed
application preferences, dedicated defaults suite and prefixed notifications.
Before native I/O it requires the exact simulator UUID, strict helper marker,
expected application identifier and bounded embedded Simulator access rights.
It preflights all resources before deletion and proves absence afterward;
native errors and partial observations remain failures. No secret values are
returned, no authentication prompt or broad domain reset is requested.

Use Xcode's Simulator entitlement processing with the actual cohort's team.
Bare `swiftc` plus ad-hoc signing does not establish the required embedded
rights. The helper is neither a wallet target nor an app-startup hook, and its
receipt/owner nonce does not grant process, simulator or filesystem ownership.
Installing it over the shared bundle ID is permitted only on a newly owned
case device after wallet writers stop, never on an existing/user simulator.
Host-owned post-app launch/receipt binding, simulator/workspace teardown,
trusted build publication and executor integration remain pending. Catalog
`runnable` flags stay false.

```bash
swift test --package-path scripts/e2e/native-cleanup
```

Model tests cover scope/access-right refusals, exact cleanup, sibling survival,
positive absence and failed partial receipts. The optional SDK smoke seeds only
synthetic generic Keychain items and preferences on an owned fresh simulator;
it is not wallet execution, protected biometric validation, populated OS
notification validation or a financial scenario result.

### Capture Simulator cleanup artifacts

`native_ios_cleanup.py` captures the actual separate helper and cohort bundles
read-only. It requires canonical owned files/directories, strict helper/cohort
boolean markers, thin 64-bit Simulator executables, valid ad-hoc signatures,
matching embedded application identifiers/default Keychain rights and architecture.
The helper must be `vizor-ios-cleanup`, not the synthetic smoke or wallet role,
and cannot inherit widget/app/shared groups. Ordinary cohort widget groups are
not confused with extra Keychain groups. Both absent signature entitlement data
and an empty signature dictionary are valid only with required embedded rights;
nonempty signed/embedded rights must agree. No Xcode default supplies the team.

```python
helper = capture_ios_cleanup_helper(helper_app, cohort_app=cohort_app)
helper.verify_unchanged()
```

Original file identities/digests and directory identities are rechecked, with
OS signature verification, before reuse. This is not trusted-source publication:
the builder still must compile the correct isolated helper/cohort sources.
Artifact probes have a 15-second per-command allowance, not one aggregate SLA.

The internal schema-1 receipt parser rejects duplicate/extra fields, wrong
namespace/UUID/nonce/team/mode, missing services, retained native state,
unsynchronized preferences and incomplete notification absence. It exposes no
successful-cleanup capability: callers cannot use external JSON/logs/PIDs as
ownership. Host-owned app launch/stop, output provenance and post-app simulator
teardown are not implemented in this module. Catalog flags remain false.

```bash
python3 -B -m unittest scripts/e2e/test_native_ios_cleanup.py
```

These models use real private fake bundles but model signatures and output;
they do not run an app or delete native state/devices. A captured file or valid
historical receipt alone is not proof of a completed owned SDK launch.

### Own the Simulator app and case support lifecycle

`native_ios_case_storage.py` composes a newly acquired, unlaunched Simulator
with captured helper/cohort artifacts. It claims native ownership before helper
installation, closing the earlier pre-app deletion route. Preparation boots
only the owned UUID, installs the helper, requires a completed read-only native
absence observation, and exclusively allocates the namespace below the SDK's
canonical app data container. Existing cases/devices are never adopted.

Directory descriptors, original inode identities and a private owner marker
anchor support ownership. CoreSimulator's group-writable `data` component is
accepted only behind an already opened owned ancestor that denies group/other
traversal; arbitrary writable parents and symlinks remain rejected. SDK directory
permissions are not changed. Case support and its marker remain private.
SDK app updates may rename the data container. Only immediately after our owned
install, all original directory identities and marker inode/bytes must match
under the new canonical SDK path and the old container must be absent. The move
is recorded separately; original markers/context are not rewritten. Copies or
path changes during ordinary observations never qualify for adoption.

```python
simulator = acquire_ios_simulator(case, runtime_identifier=runtime_id,
                                 device_type_identifier=device_type_id)
owner = prepare_ios_case_storage(simulator, helper, cancel_event=cancel_event)
try:
    launch = owner.start_app(cancel_event=cancel_event)
    # Execute the selected scenario; restart phases use the same owned support.
    owner.stop_app(launch)
    restarted = owner.start_app(cancel_event=cancel_event)
except BaseException:
    owner.retain()  # Stop case writers and shut down its UUID; delete nothing.
    raise
else:
    cleanup = owner.close(cancel_event=cancel_event)
```

The owned `simctl --console` process is not the native app. Startup binds the
SDK job's actual app PID to the exact namespace, support directory, service names
and disabled-background context. Caller environment overrides are not inherited;
only the case identity is forwarded using `SIMCTL_CHILD_`. Restart installs the
cohort once, preserves support, and tolerates only the previous fully matching
owned context while the next generation publishes atomically. Context PIDs are
never global signalling targets. Stop uses the exact owned UUID and bundle ID,
then proves native job absence independently of console group completion.

Successful close seals/stops case groups, verifies original support/context,
runs the captured terminal helper internally, and validates its complete
scope-bound receipt plus native app absence. The SDK console's exact
`com.keplr.vizor: <positive-PID>` line is separated from the helper's single JSON
line; extra diagnostics/receipts or missing launch framing fail closed. Cleanup
never accepts caller-provided JSON, PIDs, context flags or success booleans as
authority. Only then does it shut down/delete its UUID and positively observe
both SDK inventory absence and filesystem data/device-directory absence.

Preparation, launch or cleanup failures remain failed, stop/shut down only owned
writers/device, and retain state/evidence. Cleanup can fail after partial native
mutation; there is no same-owner retry or adoption. Case manifests/logs/markers
are never removed, and app context cleanup flags are not rewritten. Operations
are cooperative/single-owner, with separate process-group and SDK phase budgets,
not one wall-clock SLA. The cleanup record is not a scenario PASS.

```bash
python3 -B -m unittest scripts/e2e/test_native_ios_case_storage.py scripts/e2e/test_native_ios_simulator.py scripts/e2e/test_native_ios_cleanup.py
```

Models use real private trees and separate app/console child groups, but model
SDK transport, signatures and native observations. The optional
`VizorIosLifecycleFixture` SDK app exercises the actual native profile and
publishes synthetic metadata only; it is not a wallet or a financial scenario.
Trusted build publication, real wallet/backend execution, full worker workspace
removal and broader catalog execution remain pending. This primitive alone does
not enable catalog cases; see the composed macOS executor above.

### Own worker mutable storage and retain case evidence

`native_worker_lifecycle.py` composes the existing port, case and native storage
owners. `prepare_native_worker_lifecycle()` exclusively creates
`native-workers/<run>-w<worker>/workspace` and a separate `evidence` directory
under an existing private artifact root. The worker marker, manifests, process
logs and app context remain outside the removable mutable workspace.
Existing or partially allocated workers/cases are never adopted.

```python
worker = prepare_native_worker_lifecycle(artifacts_root, run_id=run_id, worker_id=0)
try:
    session = worker.prepare_case(platform="macos", scenario_id=scenario_id,
        case_index=0, activation_height=500, helper=captured_helper)
    # Owned control/backend phases use session.case; place mutable fixture data
    # under session.mutable_directory. Native writers use session.storage.
    app = session.storage.start_app(env=app_environment)
    # Run the selected scenario and any same-case restart phases.
    session.close(cancel_event=cancel_event)
    cleanup = worker.close()
except BaseException:
    worker.retain()  # Stop owned writers; preserve workspace/native/evidence.
    raise
```

iOS cases require explicit installed runtime/device-type identifiers and an
actual captured Simulator helper/cohort. Native preparation claims/boots a new
exact-UUID simulator before returning the usable session. Session close runs
the original native owner internally, verifies process completion and releases
the original port handles. Neither close API accepts caller-provided cleanup
booleans, JSON, report receipts or PIDs. The result is cleanup, not scenario PASS.
Port locks remain held when any owned writer/device stop is unproven.

Worker close requires all originally allocated cases to have completed through
their sessions, rechecks original worker/case directory and marker identities,
then removes only the anchored mutable workspace and observes its absence.
The [shared owned-tree primitive](native_owned_tree.py) retains the macOS
support owner's strict link rejection. Mutable build workspaces may contain
owned symlinks; they are unlinked as entries, never traversed. Hardlinks, unsafe
entries, replaced parents or uncertain cleanup retain remaining state and seal
new assignment. Closing an unfinished worker stops its case writers and retains
workspace/state instead of deleting it. Evidence is never removed, including
after successful cleanup, and partial failures never become successful reruns.

Operations are cooperative/single-owner; all writers must use the owned case
groups/native app APIs. Phase SDK/native allowances and per-group termination
budgets are separate, not one aggregate wall-clock SLA. Shared immutable artifacts
must live outside the removable workspace; source cloning, trusted build
publication, worker scheduling, backend execution and scenario assertions are
not implemented by this primitive. It does not itself enable catalog cases;
see the composed macOS executor above.

```bash
python3 -B -m unittest scripts/e2e/test_native_worker_lifecycle.py scripts/e2e/test_native_mac_case_storage.py scripts/e2e/test_native_ios_case_storage.py
```

These host models compose private signed-artifact/native-output fixtures,
separate app/console children and real port reservations. They do not execute
real wallets, chains, protected biometric state or financial scenarios.

### Compose an owned raw Zakura backend

`session.prepare_zakura_backend(tooling_root=..., grpcurl=..., proto_dir=...,
miner_address=..., timeout=60)` constructs and registers an original backend
handle before starting Docker. It loads only the pinned source above, maps the
sealed manifest's activation height to `zakura-direct-height1` or
`zakura-direct-activation500`, and requires an explicit miner address. Constructor
or startup failure retains the failed worker and preserves the original error.
The returned value proves raw fixture readiness, not wallet readiness or PASS.

`native_zakura_backend.py` keeps source identity and raw fixture evidence in a
new private `zakura-backend` directory under the original case evidence root.
Every helper artifact write uses its originally opened directory descriptor and
rechecks attachment; replacement directories are not adopted. The adapter
overrides artifact writes only, not the pinned helper's Docker ownership checks.
Existing fixture data, external backend handles and cleanup JSON are not accepted.

On successful session close, the original native app and case/control groups
stop first. iOS independently proves its SDK app job absent before joining its
console; the console PID is not app-stop proof. Only then does the raw fixture
prove removal of its exact Docker IDs and release its own port locks, followed
by native support/device cleanup and coordinator port release. Unproven backend
cleanup never grants native state deletion or case completion. Failure retention
stops only original owned resources, preserves state/evidence, and cannot become
a successful retry. Unproven writer/backend stops keep coordinator reservations.

This is cooperative, synchronous lifecycle composition, not an executor. The
raw fixture owns **internal** RPC/lightwalletd ports, separate from the immutable
manifest's front ports. No front/control server, genesis shim, funder, build
publication, mid-call cancellation or financial scenario execution is provided
here; catalog flags remain pending. Helper commands have bounded phase timeouts,
not a single aggregate run SLA. Stopped retained node state is not a proven
restart snapshot: non-finalized backups may lag and the mempool is volatile.

```bash
python3 -B -m unittest scripts/e2e/test_native_zakura_backend.py scripts/e2e/test_native_worker_lifecycle.py scripts/e2e/test_zakura_fixture_source.py
```

These host models cover original-handle registration, app/backend/native cleanup
ordering, startup rollback, sticky retention failures and artifact replacement.
Docker transport is modeled; an owned raw-chain smoke is separate from wallet,
funding, reorg or full-catalog validation.

### Offline direct-fixture signing tool

`rust/examples/regtest_direct_funder.rs` is a standalone development example,
not a wallet API or a network client. It has no RPC, faucet or THS dependency.
It signs spends from coinbase outputs to the fixed **public test-only** key
`[1; 32]`; never send real funds to that key. The owning host fixture must obtain
and prove the actual source transactions/heights, broadcast, and independently
check exact raw and compact-chain inclusion. Offline JSON is not inclusion/PASS.

```bash
cargo test --locked --manifest-path rust/Cargo.toml --example regtest_direct_funder
cargo run --locked --manifest-path rust/Cargo.toml --example regtest_direct_funder -- identity
```

`identity` emits the miner address. Other commands read one strict schema-1 JSON
request from stdin (at most 2 MiB), emit one JSON result on stdout, and use stderr
plus a nonzero exit for errors. Unknown fields, non-integer amounts/heights,
out-of-range values, malformed/trailing transaction bytes, non-coinbase sources,
wrong miner outputs and immature declared input heights are rejected. Amounts,
fees and change are integer zatoshis; the SDK's ZIP-317 fee is recalculated after
sizing, with positive change and exact value conservation.

- `build`: one transparent coinbase input to an Ironwood regtest UA, with the
  fixed height-1 activation profile.
- `build-orchard`: the same input/payment fields plus
  `nu6_3_activation_height: 500`, with the target strictly before activation.
- `build-transparent`: one transparent payment with no shielded bundle.
- `build-batch`: up to 64 distinct coinbase inputs and 500 payments, explicit
  pool and activation height (1 or 500), and optional bounded expiry. Repeated
  payments remain distinct outputs. The selected shielded pool must be active.

Single-payment fields are `schema_version`, `coinbase_hex`, `coinbase_height`,
`coinbase_vout`, `target_height`, `recipient_address` and `amount_zatoshi`.
Batch fields are `schema_version`, `coinbase_inputs`, `target_height`,
`recipient_pool`, `nu6_3_activation_height`, `payments`, and optional
`expiry_height`. Inputs carry coinbase hex/height/vout; payments carry recipient
address and integer amount. Neither path spends a wallet-under-test key or skips
coinbase maturity. No production Rust API, dependency update, vendored SQLite
fix, host funding adapter or catalog execution is added by this tool.

### Original offline signer build producer

`funder_build.py` publishes the signer once for later case reuse. Pass a fresh,
dedicated `NativeCaseLifecycle`, a local Vizor Git object cache and one full
commit SHA to `build_regtest_funder`. It never builds the dirty checkout or
downloads missing Git/dependency objects. Git replacement objects are disabled.
The complete Rust subtree is inventoried from that commit; only exact regular
Git blobs are copied into new private directories, with read-only source files.
Archive links, omitted/export-transformed blobs and unexpected files fail.

The original case owns all Git/toolchain/Cargo processes and output capture.
On a cache miss, Cargo uses a fresh target directory, `--offline --locked`, an
explicit rustc host target and 1–8 jobs (default four). Cold publication requires successful Cargo
JSON for this exact example/source, not a test harness, and positive completion
of every original process group/output writer. Cargo's output may be hard-linked;
only after joining writers is it copied into a new private single-link read-only
publication. Shared file ownership invariants are not relaxed for Cargo aliases.
An explicit `RUSTC` or the PATH compiler is resolved to the executable actually
probed (including rustup proxy resolution), then passed as Cargo's `RUSTC`.
Compiler wrappers are disabled so Cargo cannot silently substitute a compiler.

The returned `ProducedRegtestFunder` is an in-memory original-publication handle,
not a path/JSON receipt that can be adopted. Call `verify_unchanged()` before
and after an owning case runs it. `identity()` records the exact commit, Rust
Git/blob hashes, toolchain, host target and executable SHA-256. Changed source,
executable or original parent attachments invalidate that handle permanently;
all failure evidence is retained. Two cases can consume the same publication
without starting another Cargo build, but each owns its own process/output.

The suite enables `.regtest-logs/build-cache/funder-v1` by default. Keys bind the
complete Rust Git/blob inventory, compiler/Cargo identity and executable bytes,
host target, exact selected tests/address tool, producer implementation, Cargo
configuration contents and hashed build environment. The invocation ID, Git
commit outside the Rust subtree, target directory and build job count are not
compilation inputs in this key. No environment values or configuration contents
are written to the manifest. A hit still inventories the exact current source,
joins its original owner and copies binaries into a fresh private publication;
it never accepts a loose old executable or adopts an old case. Reports record
`signer_cache_hit`, `signer_cache_key` and actual signer/Rust build counts.

Locked Cargo metadata binds the actual external registry, Git and vendored
dependency source trees, not only their versions or replacement directory paths.
Git dependencies include their complete checkout so workspace sibling inputs
are covered. The offline signer and native cache collectors do not download
missing Cargo inputs; the original offline signer build remains offline.

Only an original successfully joined producer may create an entry. A bounded,
cancel-aware per-key lock serializes publication; staging is sealed and renamed
without replacing an existing entry. Every hit verifies exact inventory and
read-only single-link executable hashes. Corrupt or writable entries fail rather
than being silently rebuilt or overwritten. Partial staging and failed cases
remain evidence; this runner does not prune caches or developer resources.
Wallet storage, chain state, devices and process owners are never cached.

This is not a portable hermetic/environment attestation, native app build
publication, funding/inclusion validation or catalog execution.
The source cache and compiler remain trusted cooperative inputs, not a sandbox.
Missing offline dependencies remain errors rather than triggering downloads.
Host checks use real Git/files/processes with only the compiler modeled:

```bash
python3.11 -B -m unittest scripts/e2e/test_funder_build.py scripts/e2e/test_funder_cache.py scripts/e2e/test_funder_execution.py scripts/e2e/test_native_macos_suite.py
```

### Immutable native cohort/helper cache

The suite enables `.regtest-logs/build-cache/macos-cohort-v1` and
`ios-cohort-v1` by default. It preserves the existing cohort build flags and
signing/capture checks, and caches both the app and its matching cleanup helper.
The inputs bind checked wallet/test/native/Rust sources, helper and builder
implementation, actual Dart package contents, semantic package configuration,
locked Pod versions, Flutter/engine/Dart identity, Xcode/SDK, Cargokit compiler
identity, Cargo configuration, environment and platform/architecture/TEX fixture.
The wallet's package-config generation timestamp and workspace-local Podspec
checksums are not keys; the local package sources are checked instead. External
package inventories exclude generated directories only at their roots; a
configured packageUri source subtree is always included, even under a
generated-looking name. A root packageUri includes the complete package tree.
Same-named directories beneath source trees remain inputs. Remote Podspec checksums and all
locked versions remain inputs. Compiler environment values are hashed.
Executables selected by Rust wrappers, target linkers, CC/CXX/AR and Rust
linker flags are also hashed, including forwarded `-fuse-ld`, `-B` and
`--ld-path` selectors, Cargo configuration, included files, relative paths,
driver siblings and configured PATH lookups. Collection never executes those
configured tools. The signer and voting builders use the same collector and
recheck its inputs before publication, including after the original owner seals.

macOS and iOS producers share one checkout-wide lock under
`.regtest-logs/native-build-locks` from configuration through publication, even
with different artifact keys/cache roots or with caching disabled. Different
checkouts remain independent; case-worker parallelism is unchanged. The shared
lock also protects common Flutter-generated files. Waiting uses the original
deadline/cancellation;
unproved writer shutdown leaves a retained denial marker and blocks later builds
without deleting evidence or adopting a receipt. This coordinates these E2E
producers, not unrelated developer builds.

Only the original source-checking native builder with positively joined
successful command groups can publish.
Before lookup, `flutter build --config-only --no-pub` prepares the selected
platform's configuration/Pod sandbox without app compilation. Missing Rust
toolchains/targets in the captured Cargokit inventory are prepared before
sysroot identity is collected; installed targets are not reinstalled or updated.
Installed Pod
contents bind the key alongside normalized lock metadata and package sources;
preparation and build still reject changed project/wallet/tool inputs.
The Flutter SDK inventory includes material-font artifact bytes copied into
these Material-enabled debug apps, not just compiler and engine artifacts.
The same bounded per-key lock and
exclusive rename protect a sealed, complete app/helper pair. All bundle files
are hashed, including resources and Frameworks; relative internal Framework
aliases are preserved, while absolute/escaping links are rejected. Joined SDK
resources can have group-writable modes, such as Flutter's stock font. They are
copied without modifying the originals, then the cache directories/files are
sealed as private read-only independent inodes. Published cache files must be
single-link; a mutable or corrupt entry fails without replacement or pruning.

On every hit, copies go into the new producer case's `native-publication/`.
Those independent SDK staging copies use owner-writable private directories
and files (0700/0600), preserving executable bits and signed bytes. Simulator
installation cannot populate a staged read-only app directory. Cache entries
remain sealed; neither the originals nor sibling publications are unsealed.
The normal actual signature, role, entitlement, team and architecture capture
runs on those copies; inputs are checked again before joining the new owner.
Reports retain real app/helper build counts, cache hit/key and joined process
outcomes. `persistent_cache_attestation` describes this cooperative local
publication, not portable hermetic provenance or a wallet/catalog PASS.
Wallets, storage, devices, Keychain and chain state remain case-local.

Actual preactivation validation on clean `4429038fc` selected single iOS
migration plus same-case app restart through the normal selectors and original
owned executor on arm64, Flutter3.47.2 and iOS26.3. Each invocation used fresh
case devices, wallets and backends, with unchanged assertions, `--build-jobs 8`
and short-first without timing history:

| Native cache / case workers | Total seconds | Signer / app / helper builds | Result |
| --- | ---: | --- | --- |
| App/helper miss, 2 workers (`7b9a8d7577`) | 402.209 | 0 / 1 / 1 | 2 PASS |
| Warm, 1 worker (`a127c6e326`) | 227.533 | 0 / 0 / 0 | 2 PASS |
| Warm, 2 workers (`8009b90765`) | 157.747 | 0 / 0 / 0 | 2 PASS |

Both warm invocations reused the same captured signer/native keys, joined all
15 native producer groups successfully, and proved original Driver assertions
and native/backend cleanup with no cleanup errors. The real restart changed
the app PID while retaining its case Simulator and wallet, not a restored state.
The miss shared one app/helper build between the cases; the signer and existing
dependency caches were already warm. It is not an empty-machine cold baseline.

This single matched warm comparison reduced wall time by30.7 percent, not total
system resource use. One trial per worker count ran serial-first, not randomized;
host load and OS caches were not controlled. `/usr/bin/time -l` observed host
parent/child CPU80.55 to89.00 seconds and maximum RSS436,125,696 to451,477,504 bytes. Daemon-parented
Simulator apps and Docker VM CPU/memory are outside that accounting; maximum
RSS is not a concurrent aggregate peak. This does not prove a general speedup,
Gift SDK repair or same-final-source21/64-case coverage. The public iOS catalog
remains pending until its functional integration gate is satisfied.

```bash
python3.11 -B -m unittest scripts/e2e/test_native_build_cache.py scripts/e2e/test_native_ios_build.py scripts/e2e/test_native_macos_build.py scripts/e2e/test_native_macos_suite.py
```

### Immutable voting executable cache

Voting selections use `.regtest-logs/build-cache/voting-v1` for the five pinned
SDK/PIR/round executables. Inputs bind both exact Git archives, selected Rust,
Go and Make tool paths/bytes/versions, Cargo/Go configuration content hashes,
hashed build environment, platform and producer implementation. Build job count
and case-private output paths are not compilation identities. The cache reuses
the bounded per-key lock and exclusive, sealed executable publication; changed
or writable cached bytes fail without rebuild or overwrite.

Both Go contexts query effective CC/CXX/FC/PKG_CONFIG/GOCACHEPROG settings and
bind the referenced executable bytes, including programs selected through
GOENV rather than inherited environment variables. Setting values are hashed,
not recorded. External Cargo dependency source trees also bind voting keys.
The SDK Go producer queries the effective module-cache location and the source
trees selected by `go list -deps` for svoted's Halo2/RedPallas tags and
voting-config. Actual replacement source directories are included; unrelated
module-cache entries are not. Sources are rechecked before reuse/publication,
including byte-only validation after the original owner has joined. The same
readonly module mode as the producer prevents module-file edits.
Voting Cargo producers already permit dependency downloads; their locked
metadata preparation may also fetch unbuilt workspace/dev dependencies before
lookup. This does not compile them or change either pinned revision.

A hit still reads and extracts the original pinned sources, prepares fresh SDK
runtime scripts and joins its new producer owner. It copies verified binaries
into that owner's independent publication; vote-chain homes, keys, PIR data,
wallets and process owners remain case-local. Reports use the actual
`voting_build_count` (zero on a hit) and `voting_proof.cache_hit/cache_key`.
This is cooperative local build reuse, not hermetic provenance, voting success
or final-source full-catalog coverage.

Actual original producers on clean `cf256da33` verified an artifact-cache miss
in138.338s and a hit in1.390s. Build counts were1/0; all22/19 original command
groups joined exit0, all five binary hashes matched and private runtime inodes
were independent. The warm owner re-extracted its original pinned SDK scripts.
Rust/Go dependency caches were already populated: this is not an empty-machine
baseline, complete voting E2E, aggregate CPU/RAM saving or whole-suite speedup.

```bash
python3.11 -B -m unittest scripts/e2e/test_native_voting.py scripts/e2e/test_native_macos_suite.py scripts/e2e/test_funder_cache.py
```

### Owned offline signer execution

`funder_execution.py` runs an original `ProducedRegtestFunder` handle through
one accepting `NativeCaseLifecycle`; it never accepts an external binary path
or build receipt. `run_offline_funder` accepts the five documented commands,
with no request for `identity` and one finite JSON object for a build command.
Input serialization stops at 2 MiB, with oversized atoms rejected before
encoding. Input is exclusively created in the original consumer case,
made read-only and supplied through an open descriptor until process/output
completion. No temporary shared path, stdin pipe or wallet-under-test key is used.

Every consumer has its own launch identity and private process log. Input,
workspace and producer attachments are all checked after both successful and
exceptional execution exits. Attachment failures accompany the original error
without replacing its timeout/cancellation/interrupt classification. Nonzero exit,
timeout/cancellation, changed artifacts, duplicate/nonfinite/malformed JSON or
the wrong identity remain failures; request/log evidence is preserved. The
caller owns final case/backend/native shutdown, including after a failed call.
The parsed schema-1 object is only tool output: host funding must still verify
actual input heights, integer conservation, transaction IDs and exact raw/
compact-chain inclusion. This module does not broadcast, mine, decrypt notes,
make catalog entries runnable or establish a wallet/scenario PASS.

```bash
python3 -B -m unittest scripts/e2e/test_funder_execution.py
```

### Owned direct-fixture funding

`zakura_funding.py` combines one accepting original case/backend with an original
published offline signer. `fund_zakura` takes an explicit coinbase source height,
integer zatoshi amount, recipient pool/address and confirmation count. It does
not guess a source, mine its maturity automatically or use faucet/node-wallet
RPCs. The caller first mines until the source will be mature in the next block:
the target inclusion height must be at least the source height plus 100.

Before broadcasting, the adapter checks the fixed miner, actual coinbase block
and unspent outpoint, unchanged tip, activation profile and exact integer
input/amount/fee/change conservation. It then checks the submitted transaction
ID, exact signed bytes in the expected raw block and the corresponding compact
block identity. Transparent funding additionally requires the exact raw output,
lightwalletd raw transaction stream and UTXO; shielded funding requires the
correct compact pool/action presence. Successful evidence is written under the
original backend directory, not accepted from an external receipt.

These oracles prove a fixture payment, not recipient note decryption, wallet
balance, recovery or catalog PASS. Cancellation is checked between synchronous
backend calls, not inside Docker/RPC transport. The caller still owns process
shutdown, failed-state retention and final original backend/native cleanup.

```bash
python3 -B -m unittest scripts/e2e/test_zakura_funding.py
```

### Owned direct-fixture genesis evidence

`zakura_genesis.py` observes height zero through one accepting original
case/backend pair. It requires matching raw block/tree hash, height and time,
one version-one transparent coinbase, no shielded actions, empty trees and zero
integer shielded-pool values. It never borrows a height-one frontier or treats a
raw lightwalletd error as proof of an empty tree.

The SDK legacy empty commitment-tree encoding is `000000` (two absent nodes
and an empty parents vector). The module publishes the independently verified
TreeState with the captured source/backend identity to an exclusive, bounded
64-KiB file, mode `0400`, inside the original backend directory. Its original
handle rechecks inode, permissions, bytes and backend attachment before yielding
the path/SHA-256/run-ID/raw-port handoff. An existing or replaced file is never
adopted or overwritten. Deadline/cancellation checks are between synchronous
RPC calls, not an in-progress-call interruption guarantee.

```sh
python3 -B -m unittest scripts/e2e/test_zakura_genesis.py
```

This is only genesis evidence for the next native LWD shim slice. It does not
start a shim/control server, decrypt wallet notes, enable a catalog executor or
provide native app teardown authority. Callers still own original case joins,
raw backend cleanup and evidence retention.

### Verified direct Zakura LWD shim

`zakura_lwd_shim.dart` consumes the original host's genesis proof with explicit
path/SHA-256/fixture-run-ID/raw-port arguments. Its Dart reader checks the bounded
canonical read-only file, digest and independently verified empty-genesis schema;
raw RPC error diagnostics are not evidence of emptiness. The host must obtain
these arguments from the original proof handle, not an adopted external receipt.

The adapter serves only the verified height-zero, empty-hash `GetTreeState`
request locally. Nonzero/hash requests and other RPCs are forwarded upstream;
`GetLightdInfo` changes only a known `test`/`regtest` chainName to `regtest`, never
an unexpected network. Existing proxy fault-mode availability checks still
apply to the local genesis response. SIGINT/SIGTERM close the server/channel
before normal process exit; the host remains responsible for original group
and output joins before raw backend/port cleanup.

```sh
fvm dart run scripts/e2e/zakura_lwd_shim.dart \
  --listen-port "$FRONT_PORT" --upstream-port "$RAW_PORT" \
  --genesis-proof "$PROOF_PATH" --genesis-proof-sha256 "$PROOF_SHA256" \
  --fixture-run-id "$FIXTURE_RUN_ID"
```

This test-only server does not adopt a fixture, enable a catalog executor or
prove wallet synchronization/decryption. No production app or dependency edits
are required. Native front/control orchestration remains a separate boundary.

### Original-case-owned native Zakura front

`native_zakura_front.py` registers exactly one original case/backend/genesis
front before launching the standalone Dart shim. It uses the immutable native
manifest's LWD port, never rewrites it to the internal raw port, and requires
the package binding to point at the explicit source root. Script/generated
protocol/package/tool identities and hashes are checked across launch. This is
source continuity, not hermetic build or reusable-cache attestation.

Readiness proves exact verified genesis, known chainName-only LightdInfo
adaptation, and unchanged nonzero TreeState/LatestBlock against the original raw
backend's synchronized tip. Only pre-listen connection refusal is retryable.
Daemon/probe output is bounded; deadline/cancellation checks are between the
helper's synchronous calls. The executor must keep monitoring `assert_running()`;
startup observations are not ongoing backend health or wallet/catalog PASS.

`NativeWorkerCase.prepare_zakura_front(dart=..., source_root=...)` creates the
original genesis proof, registers the front, and releases reserved sockets while
keeping its cooperative port locks. Failed preparation stops only new original
children, then the worker retains native/backend/evidence state. Successful final
case teardown joins the original daemon/output before raw backend deletion and
lease release. No external JSON receipt/PID grants these actions.

```sh
python3 -B -m unittest scripts/e2e/test_native_zakura_front.py
```

No native app build/launch, control server, funding change or catalog execution
is enabled by this boundary. Front readiness composes the existing real shim;
native control-handler ownership and execution engines remain separate work.

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
