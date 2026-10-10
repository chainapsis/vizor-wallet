# Isolated Zakura E2E execution

This roadmap tracks a local E2E execution improvement and the migration to
direct Zakura fixtures. Reviewed functional groups merge into the draft umbrella,
not `main`. The composed executor now wires all twenty-three Rust, twenty
macOS and twenty-one iOS Simulator cases. Wiring is not a passing final-source
catalog. Keep the umbrella draft through implementation, cache/performance and
final-source validation, and obtain explicit user confirmation before starting
its final review. Earlier prototype evidence is separate from this executor.

The iOS functional group [#937](https://github.com/chainapsis/vizor-wallet/pull/937)
preserves original wallet assertions and independently owned Simulator state.
Official SDK prerequisite [#945](https://github.com/chainapsis/vizor-wallet/pull/945)
pins Flutter/core Riverpod3.4.2 and Dart3.12, without a Riverpod vendor; it affects
production dependency builds. Actual full21 run34c9e26ffa on clean6b083b58e
finished19 PASS/2 FAIL. Backend catch-up and wallet-snapshot synchronization
repairs then passed both failures in run989c2e115c on clean e7aa6909f,
485.319s including one shared app/helper build, with original native/backend
cleanup. Earlier failures remain retained. Do not combine these revisions into
an all-green final-source catalog; that gate and separate cache/resource
evidence remain outstanding.

## Local cache and dispatch checkpoint

The cache/dispatch functional group remains separate from the integrated
umbrella. Its review can proceed against the iOS prerequisite branch; integration
into the umbrella follows that prerequisite, never into `main` directly.
Original signed native-cache probes on `5553030ee` verified iOS220.269-to-4.984s
and macOS235.689-to-5.196s separate-invocation reuse, with zero app/helper builds
on hits. Real signature/access-right capture passed on new private copies.
These are build boundaries, not iOS wallet or full-catalog PASS evidence.

Timing-informed dispatch on `763c910e1` passed63 focused schedule/CLI/coordinator
checks. The ordinary selected-case CLI then ran Rust receive plus macOS import
on that clean source in `native-suite-467f251344`, two PASS/zero FAIL. A fresh
signer/Rust build took4m17s; the app/helper came from the verified cache. Warm
serial `native-suite-5e5396546d` took23.824s and warm two-worker
`native-suite-dc43a90cda` took19.520s, both two PASS/zero FAIL with all four build
counts zero. Every case completed native/backend cleanup with no cleanup errors;
the original financial assertions remain unchanged. Both warm runs used the
same measured short-first dispatch history and isolated fresh case namespaces.

That single two-case comparison is not final-source64-case coverage, a guarantee
of18-percent general speedup, Docker VM CPU accounting, concurrent aggregate
peak-memory measurement or evidence that the remaining iOS failures are fixed.
Original pinned voting producers on clean `cf256da33` additionally verified a
138.338s executable-cache miss and a1.390s hit, with build counts1/0 and all
22/19 original command groups joined successfully. All five binary hashes
matched, while SDK scripts and writable runtime copies had fresh private roots
and independent inodes. Rust/Go dependency caches were already populated; this
is not an empty-machine baseline or a voting-wallet/catalog PASS.

On clean `4429038fc`, the latest single iOS migration and same-case restart
receipt call sites passed actual two-worker validation (`7b9a8d7577`), both
original assertions and native/backend cleanup proved. Its402.209s included
one shared app/helper build each and a signer/address-tool cache hit. Matched
warm invocations on that exact source/workload passed2/2 with all build counts
zero: one worker227.533s (`a127c6e326`), two workers157.747s (`8009b90765`).
All15 native producer groups joined successfully in each warm invocation.
The measured30.7-percent wall-time reduction is one two-case observation, not
general resource efficiency. Host parent/child CPU80.55to89.00s and maximum
RSS436,125,696to451,477,504bytes do not include complete Simulator/Docker VM
costs or a concurrent aggregate memory peak. The native cache-miss run was not
fully cold; Gift SDK repair and same-final-source21/64 coverage remain unproved.

Broader resource/performance evidence, iOS completion and final-source validation
remain open. Once those gates are satisfied, ask the user before starting the
umbrella's final review. Keep it draft and do not merge it to `main` without
explicit confirmation. No CI or SDK-floor change.

## Problem and intended workflow

The [existing runners](README.md) include suites that reset a shared regtest
chain and must run serially. Simply launching more copies risks collisions in
chain state, ports, app storage, Keychain, simulator selection, and cleanup.
Repeated native builds can also dominate execution time.

The intended workflow is to select relevant scenarios, preview the execution
plan without side effects, build compatible native artifacts once, and execute
cases against independently owned fixtures. Failed-case reruns should preserve
the original report and create a new execution with its own resources.

The initial target is Rust regtests, macOS native E2E, and iOS Simulator E2E.
macOS and iOS work can share a host resource budget, but Rust and native execution
remain separate engines. Worker counts are resource limits, not a guarantee of
linear speedup.

## Safety and coverage contracts

- Each case owns its chain, wallet databases, listeners, app-storage namespace,
  and native resources. An iOS case owns a fresh disposable simulator.
- Share immutable app (and macOS helper) build artifacts, never mutable wallet
  or chain state. Restart phases retain the same case's state and prove a real
  process restart; they are not independent jobs.
- Bind manifests and cleanup to exact resource ownership. Stop new assignments
  when cleanup or process termination is unproven, and retain failure evidence.
  Never reset a user's wallet, app, or simulator to make a run pass.
- Preserve financial, receipt, transaction-inclusion, confirmation, reorg, and
  timeout assertions. Test-oracle corrections and coverage changes need explicit
  review rather than weaker expectations.
- Keep height-1 and activation-at-height-500 fixtures distinct so migration
  coverage still exercises pre-activation Orchard funding.
- Use integer zatoshis and independently signed funding transactions. The direct
  path must not rely on a node wallet RPC, THS server, or faucet.
- Report cleanup at its actual boundary. Declaring owned Keychain services and
  preferences does not prove their deletion. A successful iOS case proves
  cleanup by deleting its fresh case-owned Simulator and observing inventory and
  device-directory absence; macOS keeps its native helper observations.
- Changed-file selection is conservative path-based selection, not a complete
  dependency graph. Unknown changes must widen coverage rather than skip it.

## Reviewable implementation slices

Follow-up wallet PRs target the umbrella branch, or a prerequisite branch while
it is under review. Integrate them bottom-up. Keep each intermediate branch
runnable and update this checklist with its PR link and validation before
marking it complete. The umbrella targets `main` and merges last.

Catalog and report planning ([PR #890](https://github.com/chainapsis/vizor-wallet/pull/890))
and the [app runtime contract](RUNTIME_CONTRACT.md)
([PR #892](https://github.com/chainapsis/vizor-wallet/pull/892)) are merged into
the umbrella, not `main`. Worker lifecycle now includes the independently
testable port-reservation primitive
([PR #893](https://github.com/chainapsis/vizor-wallet/pull/893)) and owned POSIX
process-group/output-pump lifecycle
([PR #894](https://github.com/chainapsis/vizor-wallet/pull/894)). Both are merged
into the umbrella, not `main`. The process slice's macOS host regression had
124 passes and 4 Linux-only skips; its 44 lifecycle tests passed three times
each with the Linux runner as PID 1 and beneath a non-reaping PID 1.

Owned case workspaces and the schema-1 launch manifest
([PR #896](https://github.com/chainapsis/vizor-wallet/pull/896)) are also merged
into the umbrella, not `main`. Their macOS host regression had 155 passes and
4 Linux-only skips; the Linux workspace/process/port suite had 90 passes. The
31 workspace tests passed five repetitions on each OS, and six local
Python-to-Dart native-environment probes matched the app contract.

Case-bound process start, same-case restart, and final process/output teardown
([PR #897](https://github.com/chainapsis/vizor-wallet/pull/897)) are merged into
the umbrella, not `main`. Their macOS host regression had 185 passes and
4 Linux-only skips; the Linux case/workspace/process/port suite had 120 passes
both as PID 1 and beneath a non-reaping PID 1. A process cleanup record does not
prove native storage cleanup or authorize deletion. Directories and evidence
are retained.

Fresh, explicitly selected case-owned iOS simulators
([PR #898](https://github.com/chainapsis/vizor-wallet/pull/898)) are merged into
the umbrella, not `main`. They provide
exact-UUID boot/readiness, and verified pre-app shutdown/deletion. Existing
devices are never adopted. Any case launch or unproven process/native teardown
retains the device; this is not native storage cleanup. On 2026-10-09, its
macOS host regression had 219 passes and 4 Linux-only skips, and its Linux
host-primitive suite had 154 passes. The 34 modelled simulator checks passed
three repetitions per host. A real fresh iOS 26.3 simulator passed create,
boot/readiness, shutdown, and positive deletion checks on the initial slice head;
all 31 pre-existing devices retained their identities and states. No app was
installed or launched in that smoke check.
Four review findings were fixed before merging: shutdown while still booting,
shutdown after failed readiness inventory, reserving SDK process-cleanup time,
and accepting installed encoded iPad type IDs. Latest focused simulator/case
validation had 73 passes. Broad suites and the actual simulator smoke were not
rerun on those localized review corrections.

One broader macOS repetition failed the unchanged descendant-process teardown
test with `EPERM` during process-group verification. The final full suite then
passed three consecutive repetitions; the individual test passed 30 repetitions
each on the umbrella baseline and this branch. The cause was not reproduced or
established; retain this observation rather than treating reruns as a fix.

The current slice adds a standalone [macOS native storage helper](native-cleanup/README.md)
with signing checks, exact case Keychain/preference cleanup, positive native
observations and failed partial receipts. It does not add production app startup
wiring or enable execution. The host binding now captures actual helper/cohort
signing and unchanged artifact identities, seals/stops the owned case, runs one
terminal cleanup command and validates its complete scope-bound receipt. It
does not rewrite the app context or failed results. The macOS support owner now
exclusively allocates the SDK-declared sandbox case directory before app launches,
proves native absence read-only, binds direct app/context identities, and composes
verified terminal native cleanup with anchored support removal. Failed scenarios
retain state; cleanup uncertainty stays failed with remaining state/evidence.
Case workspaces/logs/markers/manifests are never removed by this owner.
The separate iOS Simulator helper now observes or deletes all five exact
case services (including recovery staging and auxiliary migration secrets),
prefixed preferences, the dedicated suite and prefixed notifications. It checks
the actual UUID/helper marker and bounded embedded Simulator access rights,
preflights all resources before mutation, and requires positive native absence.
Swift models cover sibling preservation/errors; a manual owned-device SDK smoke
proved selective synthetic Keychain/preference cleanup, not real wallet or
populated notification behavior. No ordinary wallet target links the helper.
Read-only host artifact capture now checks actual ad-hoc signatures, role
markers, bounded Simulator Mach-O rights, matching default application identity/
architecture and original files. Its strict receipt parser rejects wrong scopes
and incomplete absence; neither capture nor parsing runs an app or grants
deletion authority.
The Simulator case owner now binds fresh SDK install/launch/stop/restart and
the app's actual PID/context independently of console process completion. It
exclusively allocates canonical private support, claims native ownership before
installation, composes terminal helper output internally, and permits exact-UUID
deletion only after verified native absence and original support ownership.
Failure retains device/state/evidence; an external JSON/PID/cleanup flag never
authorizes deletion. A separate manual metadata-only lifecycle fixture uses the
actual native profile without changing ordinary wallet targets. Models exercise
separate native/console writers and sibling preservation, not wallet scenarios.
The worker lifecycle now allocates a private mutable workspace separately from
retained case evidence, owns per-case port/native/process handles from allocation,
and executes their teardown internally. Only completed original sessions permit
anchored workspace removal; incomplete/failed cases stop assignment and retain
state. Native support rejects links; mutable workspace links are only unlinked,
never followed. Shared build artifacts must remain outside the removable tree.
The composed executor wires twenty macOS import/endpoint/send/payment/mempool/Gift/voting cases and all twenty-three
catalog Rust cases to original per-case Zakura/native owners, including controlled
activation-500 Orchard migration and Gift claim/reorg/OVK coverage.
Compatible macOS app/helper artifacts are built once when selected; selected Rust
targets and the signer share one offline Cargo producer. Rust-only selections
build no app/helper. Fresh repetitions have independent schema-2 reports and
may overlap under one bounded worker count, including mixed Rust/macOS selections.
The twenty-one iOS catalog scenarios, persistent build-cache publication/invalidation,
resource scheduling and final-source catalog/performance validation remain
pending. A native observation or process receipt alone never authorizes deletion.

D3-2 (2026-10-10) removed the iOS helper chain described above. Every iOS case
already owns a fresh Simulator, so the app now keeps its production identifiers
inside that device, and a successful case proves cleanup by deleting the device
and observing inventory and device-directory absence. The helper app and its
receipts, the in-container support marker, the app's runtime context file and
the `Info.plist` build stamp are gone. Capture runs one signature verification;
later continuity checks compare file identities only. Failed cases still retain
their shut-down device. The first app launch now takes one of the two
preparation slots until its VM URL appears, and every launch must publish that
URL within a 120-second launch deadline. The iOS catalog has not yet been rerun
on this change.

The [multi-account group (#926)](https://github.com/chainapsis/vizor-wallet/pull/926)
originally carried a minimum rc7 SQLite backport of upstream
[wallet-libraries #87](https://github.com/zakura-core/wallet-libraries/pull/87).
The backport was removed so the umbrella no longer overrides the production
SDK. On stock rc7, actual two-worker batch `native-suite-3e7c729afd` recorded
seven PASS / one FAIL: `rust.multi-account.preserve-history` failed in
`add_account` with `CorruptedData`. That failure is expected until an SDK
release contains the fix; the case stays runnable so it keeps reporting the
shipped bug. With the backport, actual two-worker batch
`native-suite-6e3a47e71c` on committed source
`a947b43ac940a6a791ded75bd0be48d33a05b26b` recorded eight PASS / zero FAIL in
145.437 seconds, including one 1m53s Cargo build of the signer and one test
target. Original owners proved wallet/backend/port cleanup for all eight cases.
The private pending-case entrypoint used the normal CLI selector and shared
executor before enabling the catalog entries. Old terminal-run compiler-cache
bytes were input to a new original producer, not published-artifact adoption
or a verified persistent cache. Existing financial assertions were unchanged.
The orphaned/deleted range cases inject historical scan-queue state explicitly.
This is one domain's behavior evidence, not a full-catalog, local upstream SDK
unit-test, mixed-engine, comparative speedup or CPU/RAM result.

The Gift/direct-receive/import group recorded five PASS / zero FAIL in actual
two-worker batch `native-suite-604f4815c6`, on committed source
`d6da2e51b773315f5eeab290f80bc86cb2a2f9a0`. Total147.656s includes one2m01s
Cargo build of signer/four targets. Every original owner proved wallet/backend/
port cleanup, with empty cleanup errors. It used the same normal-selector/shared
core pending-case entrypoint and ordinary compiler-cache input before activating
the five catalog flags. Exact1ZEC/six-confirmation, history/txid, wrong-passphrase,
observer and competing-claim assertions remain. Observer DBs now use owned
storage; funding/losing-txid evidence assertions are strengthened. No production
source or dependency changes. This is separate incremental domain evidence,
not a combined final-source catalog or performance result.

The Rust activation-500 group recorded two PASS / zero FAIL in actual two-worker
batch `native-suite-e1ee84dba2` on committed source
`9814055de5e89e763983f4f163bf60efe4559863`, with a clean worktree. Total136.143s
includes one1m57s signer/two-target Cargo build; cases took15.177/15.308s.
Original owners proved wallet/backend/port cleanup, with empty cleanup errors.
Preactivation Orchard funding, height500 transition, scheduled denominations,
planned change/fees and Gift two-confirmation/one-block-reorg/OVK assertions
remain. The original pinned fixture replaced height508 from parent507 with two
donor blocks, proved parity at509, preserved the captured claim and released
the exact held raw transaction set before mining it. The normal selector/shared
core private entrypoint ran before catalog activation, with old terminal-run
compiler-cache bytes as input to a new original frozen-source producer. No
old artifact adoption, persistent-cache attestation, production source/dependency
changes, mixed-engine or comparative performance claim. Earlier domain results
do not form a same-final-source all-green Rust catalog.

The macOS send/shield/TEX/payment-request group was executed with two workers.
Batch `native-suite-03873ec8d9` on clean committed source
`077fd54774c38a22c4c2ad4a66d9f30f0d3e45ab` recorded five PASS / two FAIL in
527.265 seconds, including one 2m00s signer/address-tool Cargo build and one
macOS cohort/helper build. Shielding, shielding retry, multi-account send, TEX
send and payment-request round trip passed. Both URI cases reached the review
route but still expected the obsolete `Review payment request` title; the
production screen already uses `Review Payment`. Financial assertions were not
weakened and the production UI was not changed.
The normal `--failed-from` selector chose exactly those two cases for batch
`native-suite-d201b4e90f` on clean committed source
`6aeff60a1e02ee9b22625f31ca1b9ae9743e039f`: two PASS / zero FAIL in
188.393 seconds, including one 1m59s signer build and one cohort/helper build.
Both runs used a private pending-case entrypoint through the normal selector
and shared executor before catalog activation. Ordinary compiler-cache bytes
seeded a new original frozen-source producer; this is not artifact adoption or
a verified persistent cache. Every successful case proved original native and
backend cleanup with empty cleanup errors. Initial failed state/logs remain.
The corrected source also retains failed clipboard sections until the original
writers join, with six focused Dart unit tests. This is incremental five-plus-
two evidence across two commits, not one final-source seven-case pass, a full
catalog run, CPU/RAM measurement or comparative speedup claim.

The macOS mempool/Gift group was also executed with two workers. Batch
`native-suite-d33ca1ca57` on clean source
`c95d7a22850571667c31ed13d3ad9c6fe06aa41a` recorded three PASS / three FAIL in
663.202 seconds, with one signer/cohort/helper build. All three mempool cases
passed; Gift round trip/restart/recovery failed waiting for the copy action.
The cohort builder had omitted the existing manual Gift regtest compile flag,
so the payment-link model rejected regtest before funding. The E2E-only builder
now passes that flag and the cohort fails fast if it is absent; production
defaults and financial assertions were not changed.
The normal failed-only selector reran exactly those three Gift cases in
`native-suite-9f3ba4477f` on clean source
`ed5c3ea6bbc616005565918b4588f19ac9531b34`: three PASS / zero FAIL in
252.669 seconds, with one signer/cohort/helper build. Original wallet/backend
state survived the two-phase restart; recovery replaced the five-block branch
and preserved/released both captured claim transactions through the pinned
fixture. Every successful case proved native/backend cleanup with empty cleanup
errors. Earlier failures and retained state remain failed evidence.
Both preactivation invocations used the normal selector/executor through a
private pending-case entrypoint and ordinary compiler-cache inputs to a fresh
original producer, not prior artifact adoption or verified persistent caching.
Ninety-six focused host lifecycle/control/executor checks and thirteen Dart
driver-result unit tests passed; the E2E builder-flag correction added four
focused build checks. After activation, seventy-three catalog/CLI/impact/suite
checks passed and the public six-case preview reported ready with no blockers.
These are incremental checks, not financial E2E results.
The actual three-plus-three passes belong to two commits, not one final-source
six-case/full-catalog pass, CPU/RAM measurement or comparative speedup result.
Review follow-up corrects the two-phase overall app budgets to 30 minutes for
restart and 32 for recovery: existing 15+10 and 15+12-minute test limits plus
five minutes for launch/stop/join/mining. A regression reads both actual Dart
phase declarations; forty-one focused catalog/CLI checks passed. No phase
limit or assertion changed, and financial E2Es were not repeated for this
catalog-only deadline correction.
This functional group changes test/harness files only, not production source,
dependencies or CI. Voting and iOS were pending at that checkpoint.

The following macOS voting group completed both cases on clean implementation
`c39bd8b8e224da416189c18ebaa94acae92f62a9` in actual two-worker batch
`native-suite-a557db86cc`: two PASS / zero FAIL, 1103.291 seconds including
one signer/cohort/helper/voting-dependency build each. Case durations were
65.619/67.664 seconds. The original 0.13 ZEC Orchard funding, activation500,
immediate Ironwood migration and ten confirmations precede a real same-wallet
app restart. Per-case PIR snapshots and vote services execute real signed
discovery, eligibility and UI proofs; both commitment trees had `next_index=5`.
The slow helper observed32 delayed requests with maximum32 in flight. Both
cases proved native/backend cleanup with no cleanup errors. Exact SDK/PIR Git
source pins and publication records remain in that run's evidence.

The private preactivation entry point used the normal selector and suite core,
not prototype binaries/receipts. The subsequent catalog/docs/check activation
has78 passing focused checks and a ready public two-case preview; no financial
rerun solely for support flags. This is not a final-source full-catalog pass,
persistent artifact-cache attestation or measured serial speedup/CPU/RAM result.
No production source/dependency or CI changes in this voting group. Twenty-one
iOS cases and the cache/resource/final-source gates remain pending.

| Slice | Scope | Prerequisites |
| --- | --- | --- |
| Catalog and reports | Stable scenario IDs, suite/exact-ID/tag selection, conservative changed-file selection, failed-case reruns, side-effect-free plans, report schema | None for schema/planning; execution requires an implemented engine |
| App runtime contract | Regtest-only namespace, endpoints, case manifest, and owned-storage context across Dart/Rust (macOS); iOS isolation by a fresh case-owned device | Review independently from orchestration |
| Worker lifecycle | Owned workspaces, ports, simulators, processes, and fail-closed cleanup | App runtime contract for native execution |
| Direct Zakura backend | Offline funding, readiness and inclusion proofs, Rust test support, native adapter | Vendored Zakura fixture; native adapter also needs runtime and lifecycle |
| Native build-once executor | One compatible app build per OS and a shared macOS helper build, with isolated case execution | Runtime contract, worker lifecycle, and native backend |
| Basic scenario migrations | Import/sync and endpoint behavior | Catalog, backend, executor; SDK fix for affected account-history cases |
| Payment scenario migrations | Send, payment links, Gift flows, and mempool behavior | Basic execution; case-specific app repair only for an observed regression |
| Ironwood scenario migrations | Activation, account recovery, restart, and native outbox transport | Activation fixture, executor, separately reviewed case-specific app changes |
| Voting scenario migrations | Owned voting/PIR services, configuration, and UI flow | Executor and voting-specific service lifecycle |
| Immutable caches | Verified publication, identity, reuse, and invalidation for build artifacts | Correct build-once execution |
| Resource scheduling | Separate build/run budgets and timing-informed assignment | Stable reports and measured workload; validate cold and warm cache behavior |

The prototype mixes these concerns in shared runner and app files. Reconstruct
changes by contract and hunk; copying entire dirty files into the first PR would
pull later dependencies into earlier layers. A catalog entry must not advertise
execution support before its backend and lifecycle are available.

Separate dependencies and optional work:

- The Zakura regtest-fixture helper is vendored byte-for-byte from its
  contributor-fork commit under `scripts/e2e/zakura_fixture/`, with a size and
  SHA-256 pin. It targets Zakura 1.6.0 and is not a released CLI fixture API.
  Its pinned lightwalletd image is still packaged by THS.
- The SQLite sparse-checkpoint fix (wallet-libraries #87) is not released. The
  umbrella uses stock rc7 instead of overriding the production SDK, so the one
  affected account-history case is an expected failure until a release with the
  fix is adopted.
- The Riverpod Gift activity fix is a separately reviewable dependency update
  with a regression test. It gates the affected Gift test, not unrelated cases.
- Report-scoped recovery is a separate safety-sensitive PR after ownership and
  report contracts. Recovery receipts must not rewrite failed run results.
- Preparation, handoff, and replay experiments are optional diagnostics, not
  dependencies of the basic migration.

## Local prototype evidence

As of 2026-10-08, the unmerged prototype catalog connects 64 scenarios: 23 Rust,
20 macOS, and 21 iOS. Connected does not mean passing on one final source.

The historical ledger records 60 PASS and 4 FAIL, with no unobserved catalog
entries, across multiple runs and source revisions. Later focused fixes do not
rewrite that ledger or establish an all-green 64-scenario run.

Focused iOS run `494ad4e6be` completed 3 PASS / 0 FAIL, exit 0, in 864.788 seconds
with two workers and one build slot. It built one shared app and one helper and
reported no cleanup errors or retained native state. The selected cases were
native outbox migration, outbox restart, and the Gift payment-link round trip.
The run used base commit `f8751b2f499d48ea29ee00b0863f3dd0dcc5a59a` plus the
uncommitted prototype snapshot, not just that Git commit:

- Source fingerprint: `911898e3a5e42db837f43e20895285022f8491727bf932ca85fb1474faeb346c`
- Retained local report SHA-256: `6aa79817e7f144fd0622bcc513407b26daec4b1bd8ca937b9de2988ed3d5ef59`

These are local prototype observations; sanitized reproducible evidence for
each implementation slice still belongs in its follow-up PR. No native tests
were rerun for the initial documentation-only umbrella.

The background-named cases now separate transport from manager policy:
foreground approval produces signed bytes, the production native outbox entry
point sends them while Flutter is paused, and a separate negative policy check
verifies rejection without notification authorization. This does **not** prove
successful authorized OS background scheduling, manager cancellation
propagation, expiration handling, or continued-task tracking. That coverage
change must remain explicit in the scenario PR.

CPU-seconds, peak RAM, and energy have not been measured. Historical worker-count
and build-sharing experiments are not a current Direct Zakura efficiency or
speedup guarantee. Establish a frozen-source baseline before making that claim.

## Completion gates

- [ ] Split and review the required implementation slices above, with working
  intermediate branches and no unrelated product changes.
- [x] Vendor the Zakura fixture helper with a byte pin. The umbrella carries no
  third-party source patch; the SQLite backport was removed.
- [ ] Run the complete Rust and native catalogs on the same final source;
  record failures, skips, unobserved cases, and cleanup outcomes without
  combining revisions into a passing result.
- [ ] Verify selection and failed-case reruns, isolated concurrent cases,
  same-case restart, cancellation, cleanup failure, and sibling survival.
- [ ] Verify immutable build reuse and invalidation without sharing mutable
  fixture or wallet state.
- [ ] Compare serial and parallel execution on identical source/workloads with
  cold and warm caches; record wall time, build counts, CPU and memory costs.
- [ ] Refresh the operational README and attach sanitized reproduction commands
  and validation evidence to the implementation PRs.

CI changes, Android/Windows/Linux execution, physical iOS devices, and positive
OS-background integration are outside the initial delivery scope. Do not credit
them as validated by the macOS/iOS Simulator results.
