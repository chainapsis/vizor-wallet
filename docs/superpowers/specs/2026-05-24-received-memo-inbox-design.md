# Received Memo Inbox — Design

Date: 2026-05-24
Status: Approved for planning

## Summary

Add a read-only inbox for received Zcash text memos. Memos are already
decrypted at sync time and persisted per-output in the wallet DB; today they
are only surfaced one transaction at a time via `get_transaction_detail`. This
feature exposes them as a browsable, searchable list scoped to the active
account.

The inbox is delivered as a **Memos** tab inside the existing Activity screen
(segmented `All · Memos`), not as a new top-level navigation destination.

## Decisions

These were settled during brainstorming and are fixed for v1:

1. **Placement:** a segmented control on the Activity screen (`All · Memos`).
   Not a new sidebar/bottom-nav item. The Memos tab therefore inherits
   Activity's existing active-account scoping (one account at a time).
2. **Contents:** received text memos only. Memos on outputs the user *sent*,
   on change outputs, and on self-sends are excluded. Sent memos remain
   visible via Activity → All → transaction detail.
3. **Search:** Rust-backed, covering all received memos for the account
   regardless of any UI load window. Matches memo text via case-insensitive
   substring. No date/amount filtering in v1.
4. **Sender:** none. Zcash shielded memos carry no authenticated sender, so no
   "from" is shown. Reply-to detection is explicitly out of scope for v1.
5. **Codegen:** adding a Rust API function/struct requires
   `flutter_rust_bridge_codegen generate`; this is an accepted build step.

## Non-Goals (v1)

- No compose / reply / send-from-inbox.
- No sender identity, no reply-to-UA parsing or display.
- No threading or conversation grouping.
- No date/amount/range filters.
- No new transaction-detail screen (reuse the existing one on row tap).
- No change to the at-rest storage of memo plaintext or to the lock model.

## Architecture

```
Activity screen (Memos tab + search field)
        │  watches
        ▼
receivedMemosProvider (Riverpod)      ── active account uuid + wallet DB path
        │  calls
        ▼
getReceivedMemos(db_path, network, account_uuid, query?)   [FRB]
        │
        ▼
rust/src/wallet/sync/transactions.rs::get_received_memos
        │  reads
        ▼
wallet DB v_tx_outputs (memo BLOB)  → decode_text_memo → filter
```

Row tap → existing `activity_transaction_status_screen` using the
`txid_hex` + `tx_kind` carried on each memo item.

## Rust Layer

New function in `rust/src/wallet/sync/transactions.rs`, exposed via a thin FRB
wrapper in `rust/src/api/sync.rs`.

### API surface

```rust
// rust/src/api/sync.rs (FRB-facing, flat struct + primitives only)
pub struct ReceivedMemo {
    pub txid_hex: String,
    pub memo: String,          // decoded Memo::Text, never empty
    pub amount_zatoshi: u64,   // value received to this account on the memo output
    pub block_time: u64,       // 0 if not yet mined
    pub mined_height: u64,     // 0 if unmined
    pub tx_kind: String,       // carried so row tap opens the correct detail view
}
// One item == one received output, NOT one transaction. A single tx may carry
// multiple received outputs with distinct memos; each becomes its own row so
// `memo` and `amount_zatoshi` stay aligned. Row tap navigates by `txid_hex` +
// `tx_kind`, so multiple rows can point at the same detail screen.

pub fn get_received_memos(
    db_path: String,
    network: String,
    account_uuid: String,
    query: Option<String>,
) -> Result<Vec<ReceivedMemo>, String>;
```

### Implementation notes

- **Do not `LIKE` the raw `memo` BLOB.** The stored value is the 512-byte memo
  encoding (marker byte + UTF-8 + zero padding). A SQL `LIKE` would mis-match
  binary memos and break on UTF-8 boundaries. Instead:
  1. Select received outputs with a non-empty memo for the account.
  2. Decode each with the existing `decode_text_memo` (already returns only
     `Memo::Text`, dropping `Empty`/`Future`/`Arbitrary`).
  3. If `query` is `Some`, keep items whose decoded text contains the query as
     a case-insensitive substring.
  4. Sort newest-first. Match the exact ordering `get_transaction_history`
     already produces (look it up during planning and mirror it, including how
     it places unmined entries) so the Memos tab and the All tab agree.
- **"Received" classification** must reuse the existing logic that
  `get_transaction_detail` relies on (`to_account_uuid == account`, not change,
  external sender) rather than re-deriving it. The current code path uses
  `read_outputs_for_tx` + `detail_includes_output` + `to_key_scope`; factor the
  received-output predicate so both the detail path and the inbox path share
  one definition and cannot drift.
- Reuse `open_readonly_conn` and the read-transaction pattern already in the
  file.
- `network` is included to match the existing function signatures in the file.
  If the read-only `v_tx_outputs` path does not actually require it, drop the
  parameter rather than carry an unused one.

## Dart Layer

- **`receivedMemosProvider`** (Riverpod): keyed off the active account UUID and
  the resolved wallet DB path. Calls `getReceivedMemos`. Holds results in
  memory only and is cleared on lock, mirroring how Activity history is treated
  by `clearSensitiveStateForLock`. It does **not** change at-rest exposure —
  the plaintext already lives in the wallet DB.
- **Activity screen**: add the `All · Memos` segmented control and, in the
  Memos tab, a debounced search `TextField` that re-queries Rust (passing the
  `query` argument; empty/blank query = full list).
- **Row tap**: reuse existing navigation into
  `activity_transaction_status_screen`, passing `txid_hex` and `tx_kind` from
  the memo item.

## States & Error Handling

- **Locked:** provider yields empty and the list clears, consistent with the
  existing sensitive-state lifecycle.
- **Query error:** surface an error state in the Memos tab. Do not mask errors
  as an empty inbox (matches the WalletProvider "do not mask errors as empty
  state" convention).
- **Empty (no memos):** "No memos yet" empty state.
- **Empty (search miss):** "No memos match" state, distinct from no-memos.

## Security Notes

- No new cryptography and no new sync path: this reads already-decrypted data.
- At-rest exposure is unchanged — memo plaintext is already stored in the
  wallet DB; search does not copy it anywhere new.
- In-memory results follow the lock/clear lifecycle of other sensitive state.
- No sender is displayed, so the feature introduces no spoofing/phishing
  surface in v1.

## Testing

### Rust (`transactions.rs` test module, `tempdir` + existing helpers)

- Received text memo appears in `get_received_memos`.
- Sent, self-send, and change-output memos are excluded.
- Empty, `Future`, and `Arbitrary` memos are excluded.
- `query = Some(...)` filters by case-insensitive substring; non-matching
  memos are excluded; blank/`None` query returns the full list.
- Ordering is newest-first and stable.
- Reuse `insert_output_with_address_and_memo` for fixtures.

### Dart

- `receivedMemosProvider` returns items and clears on lock.
- Widget test: tab switch shows the Memos list; typing in search filters;
  empty-search-result vs no-memos states render distinctly; row tap routes to
  the transaction detail screen.

## Build Step

After adding the Rust API function/struct, run from the project root:

```
flutter_rust_bridge_codegen generate
```

## Open Questions / Future Work (not v1)

- Reply-to-UA detection with an explicit "unverified" treatment.
- Unread/seen tracking and a badge.
- Cross-account unified inbox.
- Date/amount filters.
