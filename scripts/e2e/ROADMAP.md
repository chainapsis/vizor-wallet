# Isolated Zakura E2E execution

This roadmap tracks a local E2E execution improvement and the migration to
direct Zakura fixtures. The initial umbrella PR contains documentation only;
the implementation is an unmerged local prototype, not functionality available
on `main`. Keep the umbrella draft until its required implementation and
validation gates are complete.

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
- Share immutable app/helper build artifacts, never mutable wallet or chain
  state. Restart phases retain the same case's state and prove a real process
  restart; they are not independent jobs.
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
  preferences does not prove their deletion; include recovery staging secrets
  and retain fresh-simulator ownership for simulator-global resources.
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
The composed executor wires twelve macOS import/endpoint/send/payment cases and all twenty-three
catalog Rust cases to original per-case Zakura/native owners, including controlled
activation-500 Orchard migration and Gift claim/reorg/OVK coverage.
Compatible app/helper artifacts are built once when selected; selected Rust
targets and the signer share one offline Cargo producer. Rust-only selections
build no app/helper. Fresh repetitions have independent schema-2 reports and
may overlap under one bounded worker count, including mixed Rust/macOS selections.
The other 29 catalog scenarios, iOS execution, persistent build-cache publication/invalidation,
resource scheduling and final-source catalog/performance validation remain
pending. A native observation or process receipt alone never authorizes deletion.

The [multi-account group (#926)](https://github.com/chainapsis/vizor-wallet/pull/926)
includes the minimum rc7 SQLite backport from upstream
[wallet-libraries #87](https://github.com/zakura-core/wallet-libraries/pull/87).
This changes the production SDK's sparse-checkpoint rewind fallback without
upgrading SDK versions or changing schemas. Provenance and removal conditions
are in [rust/vendor/README.md](../../rust/vendor/README.md).
Actual two-worker batch `native-suite-6e3a47e71c` on committed source
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

| Slice | Scope | Prerequisites |
| --- | --- | --- |
| Catalog and reports | Stable scenario IDs, suite/exact-ID/tag selection, conservative changed-file selection, failed-case reruns, side-effect-free plans, report schema | None for schema/planning; execution requires an implemented engine |
| App runtime contract | Regtest-only namespace, endpoints, case manifest, and owned-storage context across Dart/Rust/iOS | Review independently from orchestration |
| Worker lifecycle | Owned workspaces, ports, simulators, processes, and fail-closed cleanup | App runtime contract for native execution |
| Direct Zakura backend | Offline funding, readiness and inclusion proofs, Rust test support, native adapter | Zakura fixture contribution; native adapter also needs runtime and lifecycle |
| Native build-once executor | One compatible app build per OS and shared helper build, with isolated case execution | Runtime contract, worker lifecycle, and native backend |
| Basic scenario migrations | Import/sync and endpoint behavior | Catalog, backend, executor; SDK fix for affected account-history cases |
| Payment scenario migrations | Send, payment links, Gift flows, and mempool behavior | Basic execution; Riverpod fix for the affected Gift scenario |
| Ironwood scenario migrations | Activation, account recovery, restart, and native outbox transport | Activation fixture, executor, separately reviewed case-specific app changes |
| Voting scenario migrations | Owned voting/PIR services, configuration, and UI flow | Executor and voting-specific service lifecycle |
| Immutable caches | Verified publication, identity, reuse, and invalidation for build artifacts | Correct build-once execution |
| Resource scheduling | Separate build/run budgets and timing-informed assignment | Stable reports and measured workload; validate cold and warm cache behavior |

The prototype mixes these concerns in shared runner and app files. Reconstruct
changes by contract and hunk; copying entire dirty files into the first PR would
pull later dependencies into earlier layers. A catalog entry must not advertise
execution support before its backend and lifecycle are available.

Separate dependencies and optional work:

- The Zakura regtest-fixture helper is a separate repository contribution and
  must have a reproducible pin before wallet execution depends on it. The local
  prototype uses Zakura 1.6.0 and an unreleased fixture helper, not a released CLI
  fixture API. Its pinned lightwalletd image is still packaged by THS.
- The SQLite sparse-checkpoint fix is a narrowly scoped rc7 vendor backport,
  with provenance and a removal condition. It gates affected account-history
  tests, not the entire execution framework.
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
- [ ] Pin the separate Zakura fixture dependency and record third-party patch
  provenance and removal conditions.
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
