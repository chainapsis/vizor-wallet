# Migration tab: two-step redesign

Date: 2026-06-09
Branch: `adam/migration-tab`
Status: approved (design discussion in session; this document is the written spec)

## Problem

The migration tab drives a two-stage backend flow through a UI that hides the
two-stage shape:

1. The Rust entry point `migrate_orchard_to_ironwood` already advances one
   stage per call. With no active run it builds and broadcasts the Orchard
   denomination split transaction, then stops (`waiting_denom_confirmations`).
   Called again once the split notes are spendable, it signs one
   Orchard→Ironwood transaction per prepared note and submits them across the
   broadcast window (`MIGRATION_BROADCAST_WINDOW_SECS = 60`).
2. The UI presents this as seven sequential full-screen status pages. The
   second stage's call to action is labeled "Resume migration", which reads as
   error recovery rather than a deliberate step 2. The modal
   `MigrationSigningOverlay` shows identical "Starting migration … sent over
   about one minute" copy for both stages, which is wrong for the split step.

Separately, the tab flashes "Waiting for Orchard funds" every 5–10 seconds
while a sync is running:

- `activeOrchardMigrationStatusProvider` watches `syncProvider` wholesale, so
  it re-queries Rust on every sync event (scan-batch progress, 10 s
  block-height poll, balance refreshes, the screen's own 5 s timer).
- Mid-scan, librustzcash reclassifies Orchard funds from `spendable_value`
  into `value_pending_spendability`, so the no-run phase selector in
  `rust/src/wallet/sync/migration.rs` transiently answers
  `waiting_for_spendable_orchard` (or `no_orchard_funds` when the summary is
  empty), then flips back after the batch completes.

A persistent two-step layout makes this flapping *more* visible, so the fix is
part of this work.

## Decisions (made with Adam, 2026-06-09)

1. **Persistent two-step cards**: both steps always visible, each owning its
   status, progress, and button. No wizard, no per-phase page swapping.
2. **Inline run progress**: no modal overlay. The active card renders its own
   spinner/progress; runs continue in Rust if the user navigates away.
3. **Labels**: step 1 button "Prepare denominations", step 2 button
   "Start migration" (closest to existing copy; sentence case per AGENTS.md).

## Scope

Dart-only. No Rust, FFI, or FRB changes. No new backend phases.

## Design

### Layout

One stable screen:

- Header: "Migration" title, existing one-line description, existing
  Orchard → Ironwood pool-transition row.
- Step 1 card and step 2 card, stacked, always visible.
- Hardware accounts keep the existing standalone software-required view in
  place of the cards (unchanged behavior).

### Step 1 card — "Prepare denominations"

| State | Trigger | Content |
|---|---|---|
| blocked | `noOrchardFunds`, `waitingForSpendableOrchard` | Disabled button; reason as status line ("No Orchard funds to prepare." / "Waiting for Orchard funds to become spendable. Keep Vizor syncing.") |
| active | `planningDenominations` | "Ready to prepare" amount (spendable Orchard balance), body copy, enabled **Prepare denominations** button |
| running | local in-flight intent = preparing (also `preparingDenominations`) | Spinner + "Creating and submitting the denomination transaction..." |
| waiting | `waitingDenomConfirmations` | "Denomination transaction submitted. The prepared notes need to confirm before migration can start." + "Prepared notes: `preparedNoteCount` of `totalCount`" |
| done | `readyToMigrate` and every later phase | Collapsed check row: "`totalCount` prepared notes ready." |
| error | `failedRecoverable` routed to step 1 (see routing rule) | Error banner with `status.message`; **Retry migration** button |

### Step 2 card — "Migrate to Ironwood"

| State | Trigger | Content |
|---|---|---|
| locked | step 1 not done | Dimmed. "Available once the prepared notes confirm." Disabled **Start migration** button |
| ready | `readyToMigrate` | "Vizor signs `totalCount` migration transactions and submits them over `windowText`." Enabled **Start migration** button |
| ready (paused) | `paused` | Same as ready plus "Migration paused. Start migration to resume this run." |
| running | local in-flight intent = migrating (also `buildingSigningBatch`, `signingBatch`, `broadcastScheduled`, `broadcasting`) | Spinner; "Signing migration transactions..." then "Submitting migration transaction `broadcastedTxCount + 1` of `totalCount`..."; progress bar valued `broadcastedTxCount / totalCount` (count-based, no time animation); step2KeepOpen line |
| confirming | `waitingMigrationConfirmations` | Existing transfer list ("Transfer i of N", Completed / In progress / Failed rows) + completed/total progress bar, inside the card |
| done | `complete` | Existing done copy ("Migration complete" / "Your migration transactions have finished.") |
| error | `failedRecoverable` (routed here, see below), `failedTerminal`, `abandoned` | Error banner with `status.message` detail; **Retry migration** button for the recoverable case only |

`windowText` derives from `status.broadcastWindowSeconds`: exactly 60 →
"about one minute"; < 90 → "about N seconds"; otherwise "about M minutes"
(M = seconds/60 rounded).

### State mapping

A pure mapper in `models/migration_step_state.dart`, same style and
testability as the existing `migrationViewState` selector:

```dart
enum MigrationStepOneState { blocked, active, running, waiting, done, error }
enum MigrationStepTwoState { locked, ready, running, confirming, done, error }

MigrationStepsModel migrationStepsModel({
  required MigrationViewState viewState,
  required MigrationStatus? status,
  required bool runInFlight,
  required MigrationRunIntent intent,
});
```

Rules:

- Local in-flight intent takes precedence over provider-derived state: while
  the controller's Rust call is awaiting with intent `preparing`, step 1 is
  `running` (and step 2 `locked`) regardless of the last provider answer;
  intent `migrating` forces step 2 `running`. The status provider lags the
  run row by design, especially with the settled-sync gate.
- `failedRecoverable` routes to step 2's error state when
  `status.pendingTxCount > 0 || status.broadcastedTxCount > 0`, otherwise to
  step 1 (error banner on step 1, button becomes **Retry**). Both retries call
  the same controller method; Rust resumes from the stored run phase.
- `failedTerminal` and `abandoned`: step 1 done, step 2 error with the
  existing terminal/abandoned copy, no retry button.
- `complete` with newly received Orchard funds later: backend reports
  `ready_to_prepare` again, cards reset to active/locked automatically.

### Run controller

`providers/migration_run_controller.dart`, an `AsyncNotifier` that owns the
in-flight Rust call. Logic transplanted from the deleted overlay:

- `Future<void> advance(MigrationRunIntent intent)` — guards (active software
  account, testnet endpoint), macOS native-mnemonic path with Dart secure
  storage fallback, mnemonic zeroization, `_friendlyError` mapping,
  "already running" detection, expected-transfer-count bookkeeping
  (`migrationExpectedTransferCountProvider`), `refreshAfterSend`, and
  `ref.invalidate(activeOrchardMigrationStatusProvider)` on completion.
- Exposes `intent` + in-flight state for the mapper; errors land in
  `AsyncError` and render in the card the intent points at.
- While a call is in flight, a 2 s periodic
  `ref.invalidate(activeOrchardMigrationStatusProvider)` drives inline
  progress (the status query reads the run DB directly and is safe during
  broadcast; reads use `READ_DB_BUSY_TIMEOUT`). Timer stops on completion.
- The screen's existing 5 s `refreshAfterSend` polling for
  `hasPendingMigration || shouldPollProgress` is retained unchanged (it feeds
  the confirmations list).

### Anti-flash groundwork (first implementation task)

In `providers/orchard_migration_status_provider.dart`:

1. Add a settled-sync gate: a small `Notifier<int>` that listens to
   `syncProvider` and updates its state only when `!isSyncing`, exposing
   `Object.hash(accountUuid, scannedHeight, orchardBalance,
   orchardPendingBalance, ironwoodBalance, ironwoodPendingBalance)`.
   `activeOrchardMigrationStatusProvider` watches the gate instead of
   `syncProvider`. Result: zero re-queries while a scan runs (including at
   scan start), exactly one re-query when a sync cycle settles or balances
   change while idle. Explicit `ref.invalidate` calls keep working.
2. Harden `migrationBlocksSendProvider`: keep blocking on `hasError` and on
   first load (`value == null && isLoading`), but use the preserved previous
   value during reloads instead of blocking on every `isLoading`.

Known accepted edge: opening the tab mid-catch-up answers the first query from
a mid-scan reading and holds it (stable, possibly conservative) until the sync
settles, then corrects. Stable-but-briefly-stale beats flashing.

### Copy

New/changed `MigrationCopy` strings (sentence case; check
`qa-copy-review.csv` conventions before finalizing wording):

| Key | Text |
|---|---|
| step1Title | `Prepare denominations` |
| step1Body | `Split your Orchard funds into standard note amounts in a single transaction.` |
| step1Cta | `Prepare denominations` |
| step1Running | `Creating and submitting the denomination transaction...` |
| step1Waiting | `Denomination transaction submitted. The prepared notes need to confirm before migration can start.` |
| step1Done(n) | `$n prepared notes ready.` |
| step1NoFunds | `No Orchard funds to prepare.` |
| step1Unspendable | `Waiting for Orchard funds to become spendable. Keep Vizor syncing.` |
| step2Title | `Migrate to Ironwood` |
| step2Locked | `Available once the prepared notes confirm.` |
| step2Ready(n, window) | `Vizor signs $n migration transactions and submits them over $window.` |
| step2Cta | `Start migration` |
| step2Signing | `Signing migration transactions...` |
| step2Submitting(i, n) | `Submitting migration transaction $i of $n...` |
| step2PausedNote | `Migration paused. Start migration to resume this run.` |
| step2KeepOpen | `Keep Vizor open while the migration transactions are created and broadcast.` (text of today's `signInstruction`, shown in step 2 running state) |
| retryCta | `Retry migration` (existing) |

Retained: header copy, pool-transition labels, transfer-row strings,
`keepOpenWarning` (confirming state), done/terminal/abandoned copy,
scan-screen strings.
Removed with the overlay and dead dialog: `signTitle`, `signSubtitle`,
`signInstruction` (text lives on as `step2KeepOpen`), `signCancel`,
`signBack`, `broadcastingTitle`, `broadcastingSubtitle`,
`broadcastingInstruction`, `completeTitle`, `completeBody`,
`completeButton`.

### Files

- New: `lib/src/features/migration/models/migration_step_state.dart`
- New: `lib/src/features/migration/widgets/migration_step_card.dart` (shared
  shell: step badge, title, status chip, body, button; per-step content may
  live in the screen file or sibling widgets — implementer's choice)
- New: `lib/src/features/migration/providers/migration_run_controller.dart`
- Modified: `screens/migration_screen.dart` (composition only),
  `migration_copy.dart`, `providers/orchard_migration_status_provider.dart`
- Deleted: `widgets/migration_signing_overlay.dart`,
  `widgets/migration_completion_dialog.dart` (verified unreferenced)
- Untouched: `screens/migration_scan_screen.dart` (Keystone), all of `rust/`

### Testing

- Unit: `migration_step_state_test.dart` — every mapping-table row, intent
  precedence, failedRecoverable routing both ways, windowText formatting.
- Provider: settled-sync gate — no re-query mid-scan (flapping balances), one
  re-query on settle, invalidate still re-queries;
  `migrationBlocksSendProvider` uses preserved value during reload.
- Widget: step cards render the right state/button enablement for
  representative view states; new `find.text` matchers against the new copy.
- Existing `migration_view_state_test.dart` unchanged (Rust-phase selector is
  untouched).
- Manual: macOS desktop build (local bundle id recipe) against testnet —
  prepare, wait for confirmations, migrate, watch the ~60 s window, confirm
  no flashing during sync.

## Out of scope

- Rust/FRB changes of any kind.
- Pre-existing backend edge: if the denomination broadcast fails,
  `failed_recoverable` resume reports "not spendable yet" because the split tx
  never reached the network. Surfaced via the step 1 error banner + retry;
  fixing the backend recovery path is separate work.
- Keystone migration flow (gated off in this build).
