# Ledger source ownership inventory

This inventory assigns the existing Ledger implementation to the planned core
review units and the UI collection. It is preparation evidence, not an extracted
implementation or a claim that the future PRs already compile.

## Immutable comparison

- Base: `7339fa94a62339d89bcbbb3f14916d7be931a26a`.
- Source: `fbe51859972213eb0c70dc80bda67c7ef7f249e8`.
- Fetch on 2026-09-16 confirmed `origin/main` and
  `origin/rowan/ledger-advanced` at those commits.
- Local main remains `80feec736470fd4a5f2cf82190369b4c3e0dd1b0`.
- The older `rowan/ledger-core` at
  `c2d71817b08025c62650367fa125ac676f32b109` is preserved.
- New collection heads are `rowan/ledger-core-collection` and
  `rowan/ledger-ui-collection`.

## Coverage

| Classification | File entries |
| --- | ---: |
| Core only; may span several core units | 149 |
| UI only | 41 |
| Mixed core/UI responsibilities | 90 |
| Explicitly excluded source churn | 1 |
| **Total** | **281** |

The inventory covers all **1,544 textual diff hunks** and the one binary asset.
Git reports 135 additions, 145 modifications and one rename. The rename from
`swap_keystone_broadcast_result.dart` to `swap_hardware_broadcast_result.dart`
retains both paths in the inventory; it is not silently treated as a new file.

Three sub-agents inspected native/Rust/build files (67), Dart files (122), and
tests/integration/scripts/assets/docs (92). The coordinating agent checked
coverage against Git, reviewed the shared boundaries and corrected the migration
and route ownership assumptions described below.

## How to use the inventory

[ledger-change-inventory.csv](ledger-change-inventory.csv) has one row per changed
file, sorted by source path:

- `path`, `base_path`, `status`: exact source/base paths and Git status.
- `owners`: `C01` through `C15`, `UI`, or `EXCLUDE`. Core IDs match
  [the execution plan](ledger-pr-plan.md).
- `split_rule`, `evidence`: the symbol/behavior groups and boundaries used to
  assign responsibility. Multiple owners mean the file must be split, not that
  every owner should copy the whole file.
- `hunk_count`, `base_to_source_hunks`: every zero-context Git diff coordinate,
  written as `-old_start,old_count +new_start,new_count`; omitted counts mean one
  line. A binary file is marked `BINARY` instead of receiving invented line ranges.

Hunk coordinates make omissions detectable. They do **not** assert that each
Git hunk is an independently cherry-pickable patch: new files often contain
several responsibilities in one hunk. Apply the symbol-level split rule, then
verify the actual feature diff and tests at extraction time. A consumer listed
on a mixed file does not move the producer's code into that consumer PR.

The CSV's SHA-256 at creation is
`33f192e4ef470f86dd5010cfd79afa53b7b3f105ff4ab13e1ce53a58854010e4`.
The baseline remains pinned while later review changes are documented separately.

## Shared boundaries confirmed during preparation

1. **C02/C03:** account import, duplicate checks and stored metadata precede
   transport selection/enrollment. Do not pull the BLE connector dependency into
   C02 just because it currently shares `ledger_account_service.dart`.
2. **C03/C08:** introduce the cancellation/operation-gate contract before actual
   signing. Signature validation and signing-status cooldown stay with C08.
3. **C06/C07:** Windows introduces the shared native BLE protocol headers; Linux
   consumes those headers. Linux does not depend on the Windows OS adapter.
4. **Routes and widgets:** screen registration and view composition are UI.
   Extract inline account/send/shield/deposit transactions into the respective
   core contract before wiring the UI. Lifecycle recovery invocation is core;
   toast/modal rendering is UI.
5. **Generated bridge:** `rust/src/api/ledger.rs`, account API and planner DTO
   changes are introduced per feature. Regenerate Dart/Rust bridge outputs with
   `scripts/generate-rust-bridge.sh`; never copy final generated hunks as a unit.
6. **Migration remains blocked:** both desktop and mobile migration entry points
   reject Ledger while `ledgerAutomaticOrchardMigrationCapability` is unsupported.
   Existing immediate-migration service/preview code is guarded residual code,
   assigned to C08 shared signing and C09 support policy/request lifecycle, with
   presentation in UI. This adds no C16 and does not enable migration.
   Its prepare/proof/complete/discard lifecycle is not C10's signed-operation DB.
7. **Tests and evidence:** split mixed widget behavior/rendering tests with their
   implementation. Speculos integration scenarios span several features and
   cannot all be introduced with C01. Synthetic BLE peers, static adapter tests,
   device canaries and historical device runs are distinct evidence categories.
8. **Documents and probes:** move only relevant sections/scenarios with each
   feature. `ledger-support-review.md` remains historical evidence rather than
   the current support contract. Whole-document import must not imply unmerged
   features have been delivered.

## Explicit exclusion

`ios/Podfile.lock` changes only existing Flutter plugin `SPEC CHECKSUMS`; Ledger's
Apple dependency is configured through SwiftPM. Do not transplant that unrelated
checksum churn. If the actual Apple feature branch changes the resolved Pod
inputs, regenerate and justify its own lockfile then. No source work is deleted
by recording this exclusion.

## Preparation checks and limits

- Exact equality between the CSV paths and `git diff --name-status --find-renames`
  for the pinned commits; no missing, duplicate or extra entries.
- Valid owner IDs, nonempty split/evidence fields, matching rename base path,
  every textual hunk coordinate and the binary marker accounted for.
- Document links and staged document-only collection diffs checked.
- No product code, dependencies, feature PRs, runtime tests or device interactions
  are part of this seed. The earlier source-branch test run is not reused as
  validation of future extracted PRs.

Feature reviews proceed **one at a time**: open, review, revise, merge into the
collection, then open the next. Parallel review requires a dependency/overlap
proposal and explicit user approval. The two collection drafts remain containers.
