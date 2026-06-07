# Migration tab — Orchard → Ironwood (UI showcase)

**Date:** 2026-06-06
**Status:** Design approved (pending spec review)
**Type:** Feature (demo / UI showcase)

## 1. Summary

Add a new always-visible **Migration** tab to the desktop sidebar that *showcases*
what migrating shielded funds from the Orchard pool to a (fictional) "Ironwood"
next-generation pool would look like.

The migration is **theater**. Under the hood the feature builds **three small
self-sends** (to the user's own address) using the Keystone batch-signing
pipeline introduced in PR 72, has the Keystone sign all three in a single action,
and **broadcasts all three immediately**. The UI then claims the funds are
moving "in small batches over random intervals across the next 24 hours" and
asks the user to keep the app open, backed by a persistent simulated progress
state.

This is strictly a presentation/demo feature. There is no real pool migration —
Ironwood does not exist on-chain.

## 2. Goals / Non-goals

**Goals**
- A polished, always-visible "Migration" sidebar tab that looks native to Vizor.
- A believable end-to-end Keystone flow: explainer → sign (animated QR) → scan
  result → broadcast → completion popup → persistent "in progress" state.
- Reuse the existing/PR-72 batch machinery and the app's real Keystone signing
  widgets, not the throwaway debug screen.
- Re-runnable for repeated demos (a reset path).

**Non-goals**
- No real Orchard→Ironwood migration logic (Ironwood is fictional).
- No new Rust cryptography. We consume PR 72's batch APIs as-is.
- No background/iOS-specific work; this is a desktop showcase (works wherever
  the Keystone flow already works).
- No FRB regeneration on this machine (see Constraints).

## 3. Constraints (load-bearing)

1. **FRB bindings cannot be regenerated locally** (documented in AGENTS.md /
   CLAUDE.md — local codegen produces broken bindings). The batch APIs
   (`createReservedPcztBatch`, `encodeZcashSignBatchUrParts`,
   `decodeZcashSignResultCbor`, `pcztSpendNullifiers`) and their generated
   bindings **only exist on PR 72's commit** (`87b8f4e1`, branch
   `adam/keystone-batch-sim`). Therefore this feature **must build on top of that
   commit's already-generated bindings** rather than re-declaring the Rust APIs.
2. **Keystone-only.** The flow requires the batch-signing pipeline, which needs a
   Keystone hardware account. Software accounts get an informational state, not
   the flow.
3. **Orchard-only self-sends.** Self-sends to the user's own (Orchard-bearing)
   UA stay Orchard-only, so **no Sapling params** are passed (null), matching
   PR 72. If a Sapling bundle were ever required we surface a friendly error
   rather than silently downloading 50 MB.

### PR base strategy (decision to confirm at review)

Recommended: **bring PR 72's batch machinery into this PR and drop its debug-only
UI.** Concretely — base the branch on `adam/keystone-batch-sim`, then remove
`lib/src/features/debug/keystone_batch_debug_screen.dart` and revert the two
debug-only wiring additions (the `kDebugMode` sidebar entry and the
`/debug/keystone-batch` route). Keep all Rust changes and the generated bindings.

Result: a **self-contained, independently mergeable** PR — "Add Ironwood
migration showcase (incl. Keystone batch-signing support)" — whose diff is the
batch machinery this feature genuinely needs plus the migration tab, with no
throwaway debug screen.

Alternative (if preferred): stack this PR directly on top of PR 72's branch
(base = `adam/keystone-batch-sim`, debug screen left intact). Cleaner diff but
blocked on PR 72, which is marked "not intended for merge."

Branch name: `adam/migration-tab` (per the `adam/` prefix convention).

## 4. User-facing design

All copy is **sentence case** per project convention. Proper nouns: `ZEC`,
`Vizor`, `Keystone`, `Zcash`, `Orchard`, `Ironwood`. Approved mockups live in
`.superpowers/brainstorm/.../content/` (`migration-page.html`,
`signing-journey.html`).

### 4.1 Sidebar entry
- Label: **Migration**. Always visible. Placed after **Vote**, before
  **Address book** → order: Home, Swap (flagged), Vote, **Migration**, Address
  book, Activity.
- Route: `/migration`. Icon: `AppIcons.doubleArrowVertical` (transfer-between-
  pools feel; trivially swappable — `renew` / `shieldAsset` are alternatives).
- Key: `ValueKey('sidebar_migration_button')`.

### 4.2 Migration page — idle / landing (`/migration`, Keystone account, no active demo)
- Title: **Migration**
- Body: "Move your shielded ZEC to Ironwood, Zcash's next-generation shielded
  pool. Your Keystone approves the whole migration in one signature."
- Pool transition visual: **Orchard** (current pool, muted gold) → **Ironwood**
  (new pool, crimson accent).
- "Ready to migrate" card: shows the account's **Orchard pool balance**
  (`SyncState.orchardBalance`, formatted ZEC) with sub-label "Orchard pool →
  Ironwood pool". Display-only/cosmetic.
- Expectation bullets:
  - "Funds move in small batches over random intervals."
  - "Migration can take up to 24 hours to finish."
  - "Keep Vizor open until it completes."
- Primary CTA: **Start migration** (light primary button).

### 4.3 Migration page — software-account state
If the active account is **not** a Keystone hardware account, replace the card +
CTA with an informational block: "Migration is available for Keystone accounts.
Switch to or add a Keystone account to try it." (No flow is reachable.)

### 4.4 Keystone signing journey (after "Start migration")
1. **Preparing migration…** (transient) — build the 3-PCZT reserved batch and
   Orchard proofs; the signing modal opens in its "preparing" phase.
2. **Sign modal** (`KeystoneSigningModal`, overlay) — animated batch QR
   (`KeystonePcztQrStage`).
   - Title: "Approve your migration"
   - Subtitle: "Scan this code with your Keystone"
   - Instruction: "Your Keystone signs all 3 transfers in one step. Approve on
     the device, then scan the result."
   - Primary: "Scan signed result" → navigates to the scan screen.
   - Secondary: "Cancel" → aborts, returns to idle, discards in-memory batch.
3. **Scan result screen** (`/migration/scan`) — `KeystoneQrScannerCard` with
   `expectedUrType: 'zcash-sign-result'`.
   - Title: "Scan the signed migration"
   - Body: "Point your camera at the signed result QR on your Keystone."
   - Returns the result CBOR bytes to the controller.
4. **Broadcasting…** (transient) — decode + verify + broadcast all 3.
5. **Completion popup** (modal dialog):
   - Title: "Migration started"
   - Body: "Your funds are on their way to the Ironwood pool. Transfers go out in
     small batches over random intervals across the next 24 hours.\n\nKeep Vizor
     open so the migration can finish."
   - Button: "Got it" → dismisses; tab flips to in-progress state.

### 4.5 Migration page — in progress (active demo persisted)
- Title: **Migration in progress**
- Body: "Your funds are moving from Orchard to Ironwood. This finishes on its
  own — just keep Vizor open."
- Progress card: "Migrating {amount} ZEC" (amount captured at start), a progress
  bar driven by elapsed/24h, and a remaining-time line ("About 16 hours
  remaining · started 8h ago").
- Transfer schedule card: three rows "Transfer N of 3" with statuses — each flips
  to **Sent** as its (simulated) scheduled time passes:
  - Transfer 1: sent immediately (t0).
  - Transfers 2 & 3: each at a random offset within the 24h window.
- Warning callout (gold): "Keep Vizor open. Closing the app pauses the remaining
  transfers until you reopen it."
- A subtle **Reset demo** affordance (e.g., overflow/options action) clears the
  persisted state and returns to idle (for re-running the showcase).

### 4.6 Migration page — complete (elapsed ≥ 24h)
- Title: "Migration complete" with a success treatment; body: "Your funds have
  finished moving to the Ironwood pool." Primary "Done" clears the persisted
  state → returns to idle.

## 5. Architecture & components

### 5.1 New files (under `lib/src/features/migration/`)
- `screens/migration_screen.dart` — hosts the page; renders idle / software-only
  / in-progress / complete states; owns the flow controller; shows the signing
  modal overlay and routes to the scan screen.
- `screens/migration_scan_screen.dart` — mirrors `KeystoneSendScanScreen`; scans
  `zcash-sign-result`, returns CBOR bytes via `context.pop`.
- `controllers/migration_controller.dart` — Riverpod notifier orchestrating the
  flow with an explicit phase enum:
  `idle, preparing, awaitingSignature, scanning, broadcasting, complete(popup), failed`.
  Methods: `startMigration()`, `onSignedResultCbor(bytes)`, `cancel()`,
  `resetDemo()`. Holds in-memory batch artifacts (`requestId`,
  `batchMessages`, `pcztsWithProofsById`, `urParts`) and the broadcast txids.
- `models/migration_demo_state.dart` — persisted demo model:
  `{ accountUuid, startedAtEpochMs, displayAmountZatoshi, txids: [..],
  transferOffsetsMs: [0, r1, r2], totalDurationMs: 24h }` + JSON encode/decode +
  derived getters (progressFraction, remaining, perTransferStatus) computed from
  wall-clock at read time.
- `services/migration_demo_store.dart` — persistence via `AppSecureStore`
  `readPlain`/`writePlain`, key `vizor_migration_demo_state_{accountUuid}`.
  (Plain, non-sensitive storage; no `shared_preferences` dependency.)
- `migration_copy.dart` — centralized user-facing strings (keeps copy edits in
  one place; aids future copy review per AGENTS.md).
- `widgets/` (optional decomposition): `migration_pool_transition.dart`,
  `migration_progress_card.dart`, `migration_transfer_list.dart`,
  `migration_completion_dialog.dart`.

### 5.2 Changed files
- `lib/src/core/layout/app_main_sidebar.dart` — add the always-visible
  "Migration" item after Vote.
- `lib/app.dart` — add `/migration` and `/migration/scan` routes + imports.
- (Per PR base strategy) remove `lib/src/features/debug/keystone_batch_debug_screen.dart`
  and revert the two `kDebugMode` debug-only entries carried in from PR 72.

### 5.3 Reused (from PR 72 + existing app)
- Rust/FRB: `createReservedPcztBatch`, `extractAndBroadcastPczt`
  (`rust/api/sync.dart`); `encodeZcashSignBatchUrParts`,
  `decodeZcashSignResultCbor`, `decodeUrPart`, `resetUrSession`
  (`rust/api/keystone.dart`).
- Widgets: `KeystoneSigningModal`, `KeystonePcztQrStage`,
  `KeystoneQrScannerCard`, the pane modal overlay.
- Providers/helpers: `accountProvider` (active account, isHardware,
  activeAddress), `syncProvider` (`orchardBalance`, `refreshAfterSend`),
  `rpcEndpointProvider`, `getWalletDbPath()`.

## 6. Flow detail — the batch mechanism (mirrors PR 72)

1. **Build batch.** `createReservedPcztBatch(dbPath, network=endpoint.networkName,
   accountUuid, requests: 3 × ReservedPcztBatchRequest{ id: 'tx-{i}', sendFlowId:
   '{requestId}-{i}', toAddress: own UA (activeAddress), amountZatoshi: 10_000
   (0.0001 ZEC), memo: 'Ironwood migration {i}/3' }, spend/outputParams: null)`
   → `List<ReservedPcztBatchItem>`.
2. **Verify distinct notes.** Check no `spendNullifier` is shared across items
   (PR 72's collision guard). On collision/short batch → friendly error (see §7).
3. **Encode UR.** Build `ZcashBatchMessageInput{id, pcztBytes: redactedPczt}` per
   item, keep `pcztsWithProofsById[id] = pcztWithProofs`, then
   `encodeZcashSignBatchUrParts(requestId, messages, maxFragmentLen: 200)` →
   animated QR parts. Phase → `awaitingSignature`; show modal.
4. **Scan result.** Scan screen yields the `zcash-sign-result` CBOR.
   `decodeZcashSignResultCbor(cbor)` → `ZcashBatchSignResult`. Verify
   `requestId` matches and the result IDs match the batch IDs.
5. **Broadcast all three immediately.** For each signed message:
   `extractAndBroadcastPczt(dbPath, lightwalletdUrl, network, pcztWithProofs,
   signedPcztBytes)`; require `status == 'broadcasted'`; collect txids.
6. **Persist + finish.** Write `MigrationDemoState` (startedAt=now, display
   amount = current `orchardBalance`, random transfer offsets, txids),
   `syncProvider.refreshAfterSend()`, show completion popup, flip to in-progress.

`requestId` is a per-run identifier; since `Date.now()`/random are available in
normal Dart runtime (this is app code, not a workflow script), generate it from a
timestamp + counter as PR 72 does.

## 7. Edge cases & error handling

- **Not a Keystone account** → software-account state (§4.3); CTA unreachable.
- **Fewer than 3 distinct spendable Orchard notes** (collision / short batch) →
  friendly error returning to idle: "This demo needs at least 3 spendable notes.
  Receive a few payments, let Vizor sync, and try again."
- **User cancels at sign modal / leaves scan screen** → abort, discard in-memory
  batch, return to idle. (No proposal-store leak: the batch PCZTs are in-memory
  artifacts; nothing to discard server-side beyond letting them drop.)
- **Scan decodes wrong UR type** → reuse the existing "Open the … QR on Keystone,
  then scan again" guidance from `KeystoneQrScannerCard`.
- **Broadcast partial failure** (e.g., tx 2 of 3 rejected) → surface which
  transfers went out; show an error state with the succeeded txids; do **not**
  fabricate a "started" success. (Mirrors PR 72's per-message status check.)
- **Sapling unexpectedly required** → friendly error rather than silent 50 MB
  download (we pass null params by design for Orchard-only self-sends).
- **App restart mid-"migration"** → in-progress state rehydrates from persisted
  `MigrationDemoState`; the progress bar/time and per-transfer statuses recompute
  from wall-clock, so it keeps advancing.
- **Network** → not gated to mainnet; runs on the active network. Note: the 3
  self-sends are **real on-chain transactions** with real (tiny) fees on
  mainnet — prefer testnet/regtest for repeated demos.

## 8. Testing

- **Dart unit tests** (`fvm flutter test`):
  - `MigrationDemoState` JSON round-trip; derived progress/remaining and
    per-transfer status at representative elapsed times (t0, mid, ≥24h).
  - `MigrationController` phase transitions with the Rust batch calls faked
    (success path; collision error; broadcast-partial-failure; cancel).
  - `migration_demo_store` read/write/clear keyed per account (fake
    `AppSecureStore`).
- **Widget tests**: idle vs software-account vs in-progress vs complete render
  the expected copy/keys; "Start migration" gated on Keystone; "Reset demo"
  clears state. Update any `find.text(...)` if copy changes.
- **`fvm flutter analyze`** clean.
- **Manual** (macOS desktop, Keystone account, testnet/regtest): full
  explainer → sign → scan → broadcast → popup → in-progress → reset loop.
- Out of scope: regtest Rust integration suites (batch crypto is PR 72's; we
  don't re-test it here).

## 9. Risks

- **Depends on PR 72.** If PR 72's machinery changes, the consumed API surface
  may shift. Mitigation: pin to PR 72's commit; the consumed signatures are
  small and listed in §5.3/§6.
- **Demo wallet shape.** Needs ≥3 distinct spendable Orchard notes; handled with
  a clear error, but demo wallets should be pre-funded with several notes.
- **"Real txs" surprise.** The self-sends are real; the §7 mainnet note and a
  testnet/regtest recommendation mitigate accidental mainnet spend.

## 10. Open decision for review
- Confirm the **PR base strategy** in §3 (recommended: bring machinery in, drop
  debug UI, self-contained PR).
