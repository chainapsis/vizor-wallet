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
retains files and does not rewrite the app context or failed results. Trusted
helper provisioning/build publication, directory removal,
iOS recovery/auxiliary-secret cleanup, post-app simulator teardown,
backend/executor integration, and scenario migrations remain pending. A native
observation or process receipt alone never authorizes deleting a run.

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
