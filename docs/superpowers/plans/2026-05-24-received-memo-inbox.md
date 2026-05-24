# Received Memo Inbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a read-only, searchable inbox of received Zcash text memos as a "Memos" tab on the Activity screen, with per-memo hide/restore for spam and abuse.

**Architecture:** A new Rust query (`get_received_memos`) decodes and returns all received text memos for the active account (optionally text-searched), reusing the existing received-output classification. Dart adds a `receivedMemosProvider`, a `hiddenMemosProvider` (local, per-account hide set persisted via `AppSecureStore`), and a `Memos` tab/Hidden view on the Activity screen. Hidden memos are also redacted in the existing transaction detail screen. No new crypto, no new sync path, no wallet-DB schema change.

**Tech Stack:** Rust (`zcash_client_sqlite`, `rusqlite`, `flutter_rust_bridge` v2), Flutter (Dart, Riverpod, go_router), `flutter_secure_storage`.

**Spec:** `docs/superpowers/specs/2026-05-24-received-memo-inbox-design.md`

---

## File Structure

**Rust (create/modify):**
- Modify `rust/src/wallet/sync/transactions.rs` — add `ReceivedMemo` struct, `get_received_memos()`, a shared `is_received_output()` predicate factored out of `detail_includes_output`, and a `memo_output_key` on the detail path. Add unit tests in the existing `#[cfg(test)] mod tests`.
- Modify `rust/src/wallet/sync/mod.rs` — re-export the new items. `transactions` is a private submodule; callers reach its items only through the explicit `use transactions::{...}` blocks (lines ~61-71). Add `get_received_memos` to the `pub use transactions::{...}` block and `ReceivedMemo` to the `pub(crate) use transactions::{...}` block. **Without this, Task 5 fails to compile** (`no function get_received_memos in module wallet::sync`).
- Modify `rust/src/api/sync.rs` — add FRB `ReceivedMemo` struct + `get_received_memos()` wrapper; add `memo_output_key` to the FRB `TransactionDetail` struct and its mapping.

**Dart (create/modify):**
- Create `lib/src/features/activity/models/memo_hide_key.dart` — pure helper to build/parse the stable hide key.
- Create `lib/src/providers/hidden_memos_provider.dart` — per-account hidden set, persisted via `AppSecureStore`.
- Modify `lib/src/core/storage/app_secure_store.dart` — add `kHiddenMemosKey` constant.
- Modify `lib/src/features/activity/screens/activity_screen.dart` — `All · Memos` segmented control, Memos list, search field, Hidden view, hide/restore actions.
- Modify `lib/src/features/activity/screens/activity_transaction_status_screen.dart` — redact memo text when its output is hidden; offer Restore.

**Codegen:** after Rust API changes, run `flutter_rust_bridge_codegen generate` (regenerates `rust/src/frb_generated.rs` and `lib/src/rust/api/sync.dart`).

**Build baseline:** before starting, run the cargo-check skill / `cd rust && cargo check` to confirm a clean baseline.

---

## Task 1: Rust — shared `is_received_output` predicate

Factor the "is this a received, user-visible output for this account" test out of `detail_includes_output` so the inbox and detail paths share one definition (spec: "cannot drift").

**Files:**
- Modify: `rust/src/wallet/sync/transactions.rs` (near `detail_includes_output`, ~line 782)
- Test: same file, `mod tests`

- [ ] **Step 1: Write the failing test**

Add to `mod tests`:

```rust
#[test]
fn is_received_output_matches_external_inbound_only() {
    let me = uuid::Uuid::new_v4();
    let me_bytes = me.as_bytes().to_vec();
    let other = uuid::Uuid::new_v4().as_bytes().to_vec();

    // External sender -> us, shielded: received.
    let inbound = TxOutput {
        txid: vec![1; 32], output_pool: 2, output_index: 0,
        from_account_uuid: Some(other.clone()),
        to_account_uuid: Some(me_bytes.clone()),
        to_address: Some("u1addr".into()), to_key_scope: None,
        value: 100, memo: None,
    };
    assert!(is_received_output(&inbound, &me_bytes));

    // We sent it (from us, to other): not received.
    let outbound = TxOutput {
        from_account_uuid: Some(me_bytes.clone()),
        to_account_uuid: Some(other.clone()),
        ..inbound.clone()
    };
    assert!(!is_received_output(&outbound, &me_bytes));

    // Internal change (from us, to us, no address, internal scope): not received.
    let change = TxOutput {
        from_account_uuid: Some(me_bytes.clone()),
        to_account_uuid: Some(me_bytes.clone()),
        to_address: None, to_key_scope: Some(1),
        ..inbound.clone()
    };
    assert!(!is_received_output(&change, &me_bytes));
}
```

(`TxOutput` must derive `Clone` for the `..` spread — it already does not; add `#[derive(Clone)]` to `struct TxOutput` if missing.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd rust && cargo test is_received_output_matches_external_inbound_only`
Expected: FAIL — `is_received_output` not found.

- [ ] **Step 3: Implement the predicate and refactor the caller**

Add:

```rust
/// One definition of "received, user-visible output for this account",
/// shared by the inbox query and the transaction-detail path.
fn is_received_output(output: &TxOutput, account_uuid: &[u8]) -> bool {
    let from_own = output.from_account_uuid.as_deref() == Some(account_uuid);
    let to_own = output.to_account_uuid.as_deref() == Some(account_uuid);
    to_own && (!from_own || is_user_visible_self_output(output))
}
```

Refactor the `"received" | "receiving"` arm of `detail_includes_output` to:

```rust
"received" | "receiving" => !base.is_shielding && is_received_output(output, account_uuid),
```

Ensure `struct TxOutput` has `#[derive(Clone)]`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd rust && cargo test transactions::`
Expected: PASS (new test + existing detail tests still green).

- [ ] **Step 5: Commit**

```bash
git add rust/src/wallet/sync/transactions.rs
git commit -m "refactor(rust): factor shared is_received_output predicate"
```

---

## Task 2: Rust — `get_received_memos` query (no search)

**Files:**
- Modify: `rust/src/wallet/sync/transactions.rs`
- Test: same file, `mod tests`

- [ ] **Step 1: Write the failing test**

Use the existing `insert_output_with_address_and_memo` fixture + `tempdir` (mirror `detail_*` tests). Insert: one external inbound output with text memo `b"incoming memo"`, one change output with memo `b"change memo"`, one sent output with memo `b"sent memo"`, and one inbound output with an empty memo (`Memo::Empty` encoding = `[0xF6, 0x00...]`). Assert `get_received_memos(db, network, me, None)` returns exactly one item whose `memo == "incoming memo"`, with `output_pool`/`output_index` populated.

(Model the DB/fixture setup on the existing `detail_*_row_*` tests in the same module so the schema matches.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd rust && cargo test get_received_memos`
Expected: FAIL — function not found.

- [ ] **Step 3: Implement the struct and query**

Add struct (near `TransactionDetail`):

```rust
pub(crate) struct ReceivedMemo {
    pub txid_hex: String,
    pub memo: String,
    pub amount_zatoshi: u64,
    pub block_time: u64,
    pub mined_height: u64,
    pub tx_kind: String,
    pub output_pool: i64,
    pub output_index: i64,
}
```

Add the function. Reuse `open_readonly_conn`, an `unchecked_transaction`, `read_history_bases`, and `read_history_outputs` (already keyed by txid for the account). For each base, for each output where `is_received_output(output, &uuid_bytes)` AND `decode_text_memo(output.memo.as_deref())` is `Some(text)`, push a `ReceivedMemo` with `tx_kind: "received".to_string()`, block_time/mined_height from the base. Sort newest-first using the **same comparator** as `get_transaction_history` (pending rank, then `block_time`/`created_time`, then `mined_height`, then `tx_index`, then `txid_hex` desc). Apply the `query` substring filter in Step (Task 3); for now ignore `query`.

```rust
pub fn get_received_memos(
    db_path: &str,
    _network: WalletNetwork,
    account_uuid: &str,
    query: Option<&str>,
) -> Result<Vec<ReceivedMemo>, String> {
    let uuid = uuid::Uuid::parse_str(account_uuid).map_err(|e| format!("Invalid UUID: {e}"))?;
    let uuid_bytes = uuid.as_bytes().to_vec();
    let conn = open_readonly_conn(db_path)?;
    let read_tx = conn.unchecked_transaction().map_err(|e| format!("SQL error: {e}"))?;
    let bases = read_history_bases(&read_tx, &uuid_bytes)?;
    if bases.is_empty() { return Ok(Vec::new()); }
    let outputs_by_txid = read_history_outputs(&read_tx, &uuid_bytes)?;

    let needle = query.map(|q| q.to_lowercase());
    let mut items: Vec<(ReceivedMemo, /* sort fields */ u64, u64, i64)> = Vec::new();
    for base in &bases {
        let Some(outputs) = outputs_by_txid.get(&base.txid) else { continue; };
        for output in outputs {
            if !is_received_output(output, &uuid_bytes) || base.is_shielding { continue; }
            let Some(text) = decode_text_memo(output.memo.as_deref()) else { continue; };
            if let Some(n) = &needle {
                if !text.to_lowercase().contains(n) { continue; }
            }
            items.push((
                ReceivedMemo {
                    txid_hex: hex::encode(&base.txid),
                    memo: text,
                    amount_zatoshi: output.value,
                    block_time: base.block_time,
                    mined_height: base.mined_height.map(u64::from).unwrap_or(0),
                    tx_kind: "received".to_string(),
                    output_pool: output.output_pool,
                    output_index: output.output_index,
                },
                base.block_time,
                base.created_time,
                base.tx_index,
            ));
        }
    }
    // newest-first; pending (mined_height 0) sorts first, matching history.
    items.sort_by(|a, b| {
        let a_pending = (a.0.mined_height == 0) as u8;
        let b_pending = (b.0.mined_height == 0) as u8;
        b_pending.cmp(&a_pending)
            .then_with(|| b.1.cmp(&a.1))
            .then_with(|| b.2.cmp(&a.2))
            .then_with(|| b.0.mined_height.cmp(&a.0.mined_height))
            .then_with(|| b.3.cmp(&a.3))
            .then_with(|| b.0.txid_hex.cmp(&a.0.txid_hex))
    });
    Ok(items.into_iter().map(|(m, ..)| m).collect())
}
```

Note: confirm `read_history_bases` exists and returns `TxBase` with `block_time`, `created_time`, `mined_height`, `tx_index`, `is_shielding`. If its name differs, use the actual loader used by `get_transaction_history`.

- [ ] **Step 4: Re-export from `sync/mod.rs`**

In `rust/src/wallet/sync/mod.rs`, add `get_received_memos` to the `pub use transactions::{...}` block and `ReceivedMemo` to the `pub(crate) use transactions::{...}` block (alongside `TransactionDetail`). The in-module test from Step 1 does not need this, but it must be present before Task 5; do it now so the function is reachable.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd rust && cargo test get_received_memos`
Expected: PASS. Also `cd rust && cargo check` clean (re-export resolves).

- [ ] **Step 6: Commit**

```bash
git add rust/src/wallet/sync/transactions.rs rust/src/wallet/sync/mod.rs
git commit -m "feat(rust): add get_received_memos query"
```

---

## Task 3: Rust — text search filter for `get_received_memos`

(The implementation in Task 2 already wired `query`; this task adds the test that locks the behavior.)

**Files:**
- Test: `rust/src/wallet/sync/transactions.rs` `mod tests`

- [ ] **Step 1: Write the failing test**

Insert two inbound text memos: `b"Invoice 1042 paid"` and `b"thanks for lunch"`. Assert:
- `get_received_memos(.., Some("invoice"))` returns 1 (case-insensitive match).
- `get_received_memos(.., Some("LUNCH"))` returns 1.
- `get_received_memos(.., Some("zzz"))` returns 0.
- `get_received_memos(.., None)` returns 2.

- [ ] **Step 2: Run test to verify it fails (or passes if Task 2 covered it)**

Run: `cd rust && cargo test get_received_memos_search`
Expected: PASS if Task 2 wired `query` correctly; otherwise fix `query` handling until green.

- [ ] **Step 3: (only if failing) fix `query` substring/lowercasing**

- [ ] **Step 4: Run test to verify it passes**

Run: `cd rust && cargo test get_received_memos`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add rust/src/wallet/sync/transactions.rs
git commit -m "test(rust): lock get_received_memos case-insensitive search"
```

---

## Task 4: Rust — `memo_output_key` on transaction detail

**Files:**
- Modify: `rust/src/wallet/sync/transactions.rs` (`TransactionDetail`, `get_transaction_detail` ~line 454-510)
- Test: same file, `mod tests`

- [ ] **Step 1: Write the failing test**

Extend an existing detail test (e.g. the incoming-memo detail test): assert the returned `TransactionDetail.memo_output_key == Some("<pool>:<index>")` matching the output the memo came from, and that a detail with no memo has `memo_output_key == None`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd rust && cargo test detail`
Expected: FAIL — no field `memo_output_key`.

- [ ] **Step 3: Implement**

Add `pub memo_output_key: Option<String>` to `pub(crate) struct TransactionDetail`. In `get_transaction_detail`, when computing `memo` via `find_map`, capture the originating output and set `memo_output_key = Some(format!("{}:{}", output.output_pool, output.output_index))`; `None` when no text memo found.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd rust && cargo test detail`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add rust/src/wallet/sync/transactions.rs
git commit -m "feat(rust): expose memo_output_key on transaction detail"
```

---

## Task 5: Rust — FRB API surface + codegen

**Files:**
- Modify: `rust/src/api/sync.rs`
- Generated: `rust/src/frb_generated.rs`, `lib/src/rust/api/sync.dart`

- [ ] **Step 1: Add FRB struct + wrapper**

In `rust/src/api/sync.rs` add:

```rust
pub struct ReceivedMemo {
    pub txid_hex: String,
    pub memo: String,
    pub amount_zatoshi: u64,
    pub block_time: u64,
    pub mined_height: u64,
    pub tx_kind: String,
    pub output_pool: i64,
    pub output_index: i64,
}

pub fn get_received_memos(
    db_path: String,
    network: String,
    account_uuid: String,
    query: Option<String>,
) -> Result<Vec<ReceivedMemo>, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let memos = wallet_sync::get_received_memos(
            &db_path, network, &account_uuid, query.as_deref(),
        )?;
        Ok(memos.into_iter().map(|m| ReceivedMemo {
            txid_hex: m.txid_hex, memo: m.memo, amount_zatoshi: m.amount_zatoshi,
            block_time: m.block_time, mined_height: m.mined_height, tx_kind: m.tx_kind,
            output_pool: m.output_pool, output_index: m.output_index,
        }).collect())
    })
}
```

Also add `pub memo_output_key: Option<String>` to the FRB `TransactionDetail` struct and set it in the `get_transaction_detail` mapping (`memo_output_key: detail.memo_output_key`).

- [ ] **Step 2: Run codegen**

Run (from project root, NOT `rust/`): `flutter_rust_bridge_codegen generate`
Expected: regenerates bindings; `lib/src/rust/api/sync.dart` now declares `getReceivedMemos`, `ReceivedMemo`, and `TransactionDetail.memoOutputKey`.

- [ ] **Step 3: Verify it compiles**

Run: `cd rust && cargo check` then `fvm flutter analyze`
Expected: both clean (analyze may still flag the not-yet-written Dart usages — that's fine, focus on no errors in generated files).

- [ ] **Step 4: Commit**

```bash
git add rust/src/api/sync.rs rust/src/frb_generated.rs lib/src/rust/api/sync.dart
git commit -m "feat(rust): FRB get_received_memos + memo_output_key, regen bindings"
```

---

## Task 6: Dart — hide-key helper

**Files:**
- Create: `lib/src/features/activity/models/memo_hide_key.dart`
- Test: `test/features/activity/memo_hide_key_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/activity/models/memo_hide_key.dart';
// (use the package name from pubspec.yaml; adjust import root if different)

void main() {
  test('builds key from memo fields', () {
    expect(memoHideKey(txidHex: 'ab12', outputPool: 2, outputIndex: 0), 'ab12:2:0');
  });
  test('builds key from detail output key', () {
    expect(memoHideKeyFromDetail(txidHex: 'ab12', memoOutputKey: '2:0'), 'ab12:2:0');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/activity/memo_hide_key_test.dart`
Expected: FAIL — file/functions missing.

- [ ] **Step 3: Implement**

```dart
String memoHideKey({
  required String txidHex,
  required int outputPool,
  required int outputIndex,
}) => '$txidHex:$outputPool:$outputIndex';

String memoHideKeyFromDetail({
  required String txidHex,
  required String memoOutputKey, // "pool:index"
}) => '$txidHex:$memoOutputKey';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/features/activity/memo_hide_key_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/activity/models/memo_hide_key.dart test/features/activity/memo_hide_key_test.dart
git commit -m "feat(dart): memo hide-key helper"
```

---

## Task 7: Dart — `hiddenMemosProvider` (local persistence)

**Files:**
- Modify: `lib/src/core/storage/app_secure_store.dart` (add `const kHiddenMemosKey = 'zcash_hidden_memos';`)
- Create: `lib/src/providers/hidden_memos_provider.dart`
- Test: `test/providers/hidden_memos_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Using `AppSecureStore.testing(storage: ...)` with an in-memory `FlutterSecureStorage` fake (mirror existing secure-store tests), assert:
- hide(account: 'A', key: 'tx:2:0') then read returns a set containing 'tx:2:0'.
- restore(account: 'A', key: 'tx:2:0') removes it.
- keys are per-account (hiding under 'A' does not appear under 'B').
- persisted JSON round-trips: a second provider instance over the same store sees the hidden key.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/providers/hidden_memos_provider_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Add `kHiddenMemosKey` to `app_secure_store.dart`. Create a Riverpod `Notifier`/`AsyncNotifier` `hiddenMemosProvider` exposing `Set<String> keysFor(String accountUuid)`, `Future<void> hide(accountUuid, key)`, `Future<void> restore(accountUuid, key)`. Persist as `{ "<accountUuid>": ["<key>", ...] }` JSON via `AppSecureStore.writePlain(kHiddenMemosKey, json)` and load via `readPlain`. Inject `AppSecureStore` so tests can pass `AppSecureStore.testing`.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/providers/hidden_memos_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/core/storage/app_secure_store.dart lib/src/providers/hidden_memos_provider.dart test/providers/hidden_memos_provider_test.dart
git commit -m "feat(dart): local per-account hidden-memos store"
```

---

## Task 8: Dart — Memos tab (list + search) on Activity screen

**Files:**
- Modify: `lib/src/features/activity/screens/activity_screen.dart`
- Test: `test/features/activity/memos_tab_test.dart`

- [ ] **Step 1: Write the failing widget test**

Pump `ActivityScreen` with overridden providers so `getReceivedMemos` is faked (inject a thin repository/provider seam if needed — prefer a `receivedMemosProvider` you can override rather than calling the FFI directly in the widget). Assert:
- An `All · Memos` segmented control is present; switching to Memos shows memo rows (date, amount, truncated text).
- Typing in the search field re-queries and narrows results.
- No-memos shows "No memos yet"; search-miss shows "No memos match".
- **Clears on lock** (spec requirement): when the wallet locks (drive via the same mechanism Activity history uses — `clearSensitiveStateForLock` / the security provider), the Memos list is cleared from memory. Assert the memo rows disappear on lock.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/activity/memos_tab_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Add a `receivedMemosProvider` (family on `(accountUuid, query)`, or a Notifier holding query state) that calls `rust_sync.getReceivedMemos(dbPath: await getWalletDbPath(), network: ref.read(rpcEndpointProvider).networkName, accountUuid: ..., query: ...)`. Add the segmented control + debounced search `TextField` + memo list to `ActivityScreen`, following the existing loading/error/empty patterns (`_isLoading`, `_error`, account-mismatch guards).

**Memo row navigation (do NOT reuse `_pushTransactionStatus` — it requires a `TransactionInfo`).** Construct the navigation directly from the memo item:

```dart
context.push(
  Uri(path: '/activity/tx/${memo.txidHex}',
      queryParameters: {'kind': memo.txKind}).toString(), // memo.txKind == "received"
  extra: ActivityTransactionStatusArgs(
    txidHex: memo.txidHex,
    txKind: memo.txKind,            // REQUIRED: detail self-loads via getTransactionHistory + _findTransaction, which falls back to args.txKind when initials are null
    initialTransaction: null,
    initialDetail: null,
  ),
);
```

The detail screen tolerates null `initialTransaction`/`initialDetail` (both optional) and self-loads via `_loadTransaction`; passing `txKind: "received"` is what makes its `_findTransaction` lookup match.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/features/activity/memos_tab_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/activity/screens/activity_screen.dart lib/src/providers/*.dart test/features/activity/memos_tab_test.dart
git commit -m "feat(dart): Memos tab with Rust-backed search on Activity screen"
```

---

## Task 9: Dart — hide / restore + Hidden view

**Files:**
- Modify: `lib/src/features/activity/screens/activity_screen.dart`
- Test: `test/features/activity/memos_hide_restore_test.dart`

- [ ] **Step 1: Write the failing widget test**

With faked `receivedMemosProvider` returning 2 memos and an overridden `hiddenMemosProvider`, assert:
- Each inbox memo row exposes a Hide action; invoking it removes the memo from the inbox.
- A Hidden toggle/link shows the hidden memo with a Restore action; Restore returns it to the inbox.
- When all memos are hidden, the inbox shows the "points to Hidden view" empty state (distinct from "No memos yet").

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/activity/memos_hide_restore_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Partition the Rust result: `inbox = memos where !hidden.contains(memoHideKey(...))`, `hidden = complement`. Add a Hide affordance per inbox row (calls `hiddenMemosProvider.hide`) and a Hidden view (toggle/segment state) listing hidden memos with Restore (`hiddenMemosProvider.restore`). Add the all-hidden empty state.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/features/activity/memos_hide_restore_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/activity/screens/activity_screen.dart test/features/activity/memos_hide_restore_test.dart
git commit -m "feat(dart): per-memo hide/restore and Hidden view"
```

---

## Task 10: Dart — redact hidden memo in transaction detail

**Files:**
- Modify: `lib/src/features/activity/screens/activity_transaction_status_screen.dart`
- Test: `test/features/activity/memo_detail_redaction_test.dart`

- [ ] **Step 1: Write the failing widget test**

Pump `ActivityTransactionStatusScreen` with a `TransactionDetail` whose `memoOutputKey` is set and an overridden `hiddenMemosProvider` containing `memoHideKeyFromDetail(txidHex, memoOutputKey)`. Assert the memo text is NOT shown; a "Memo hidden" placeholder and a Restore action are shown. Restoring reveals the text.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/activity/memo_detail_redaction_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

In the memo-rendering branch, compute `key = memoHideKeyFromDetail(txidHex: ..., memoOutputKey: detail.memoOutputKey!)` when `memoOutputKey != null`, and if `ref.watch(hiddenMemosProvider).keysFor(account).contains(key)`, render the placeholder + Restore instead of the memo text.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/features/activity/memo_detail_redaction_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/activity/screens/activity_transaction_status_screen.dart test/features/activity/memo_detail_redaction_test.dart
git commit -m "feat(dart): redact hidden memo in transaction detail"
```

---

## Task 11: Full verification

- [ ] **Step 1: Rust tests**

Run: `cd rust && cargo test`
Expected: all pass (existing 11 + new memo/predicate/detail tests).

- [ ] **Step 2: Dart analyze + tests**

Run: `fvm flutter analyze && fvm flutter test`
Expected: no analyzer errors; all tests pass.

- [ ] **Step 3: Manual smoke (simulator)**

Run the app, open Activity → Memos: confirm received memos list, search, hide (memo leaves inbox), Hidden view + restore, and that a hidden memo is redacted in tx detail. Confirm the underlying transaction still appears under Activity → All.

- [ ] **Step 4: Final commit (if any fixups)**

```bash
git add -A && git commit -m "chore: received memo inbox verification fixups"
```

---

## Notes for the implementer

- **Do NOT `LIKE` the raw memo BLOB.** Memos are decoded via `decode_text_memo` (returns only `Memo::Text`) and substring-matched in Rust. This is intentional — see the spec.
- **Hide is display-only.** Never delete or mutate wallet-DB rows. The hidden set lives only in `AppSecureStore` and is wiped on wallet reset.
- **Per-output identity.** A transaction can carry multiple received memo outputs; the hide key includes pool + index so each is addressed independently.
- **Lock model unchanged.** `receivedMemosProvider` holds results in memory and should clear on lock like other sensitive state; the hidden-key set is not sensitive and persists.
- Verify struct/loader names against the current `transactions.rs` (`read_history_bases`, `TxBase` fields) before coding — names in this plan reflect the file at planning time.
