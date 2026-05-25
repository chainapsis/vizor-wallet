# Filter Memos by Receiving Address — Design (sub-project 2)

Date: 2026-05-24
Status: Approved for planning

## Summary

Add a receiving-address filter to the Memos tab: narrow the received-memo inbox
to memos that arrived at a specific one of the user's own receiving addresses.
This is **sub-project 2**, building on sub-project 1 (address labeling) and the
memo inbox. The filter options are the user's addresses (shown by label when
named), so this completes the original goal: "filter memos by which of my
addresses got paid."

## Context

- The memo inbox (`MemosTab`) already composes a Rust-backed search field and an
  Inbox/Hidden toggle, partitioning a per-query received-memo list.
- `get_received_memos` already iterates outputs that carry `to_address`
  (`v_tx_outputs.to_address` = `addresses.address` via `address_id`), but
  `ReceivedMemo` does not yet expose it.
- Sub-project 1 added `addressLabelsProvider` (address → label) and
  `list_account_addresses`. Labels are keyed by the address string — the same
  string `to_address` carries — so a memo's receiving address joins to its label
  with zero translation.

## Decisions

1. **Filter options = distinct non-null `to_address` values present in the
   loaded received-memo set** (not all of the account's addresses). A filter
   only offers values that yield results. Each option displays its label
   (`addressLabelsProvider.labelFor`) if set, else a truncated address. Plus a
   default **"All addresses"**.
2. **NULL receiving address:** memos with a NULL `to_address` are NOT a filter
   option. They appear only under "All addresses." No "Unknown address" bucket
   (the NULL case is an edge — unrecorded diversifier / import-rescan paths —
   not the norm; building a facet for it is YAGNI).
3. **Control = a dropdown** (not a chip row) above the list, scaling better than
   chips when there are many addresses.
4. **Client-side filtering**, consistent with the existing Hidden partition. The
   full per-query list is already in memory; the address filter is a
   set-membership narrow applied after the Rust query.
5. **Composition:** the selected address ANDs with the search query (Rust) and
   the active Inbox/Hidden view. All three narrow together.
6. **Dropdown shown only when ≥2 distinct addresses** are present in the loaded
   set; with one (or zero) it is pointless and hidden.
   - **Intentional:** options are derived from the current (search-filtered)
     `receivedMemosProvider` result, so the option set reflects what the search
     returns. If a search narrows results down to a single address, the dropdown
     disappears (<2 options) — that is correct, not a bug. Do NOT add a separate
     unfiltered provider just to keep the option set stable across searches.
     "All addresses" always sits at the top and shows the full current result,
     so the user is never stranded.
7. **Reset to "All addresses"** if the selected address leaves the option set
   (account switch, or it no longer has memos after a refresh).

## Non-Goals

- Filtering by sender (no authenticated sender exists in Zcash memos).
- An "Unknown address" bucket for NULL `to_address`.
- Server/Rust-side address filtering (client-side only).
- Address filtering anywhere other than the Memos tab (e.g. the All activity
  list is unchanged).
- Any change to address derivation, labeling, or the memo hide/restore behavior.

## Architecture

```
MemosTab (search [Rust] + Inbox/Hidden toggle [client] + Address dropdown [client])
        │  watches receivedMemosProvider(query) → List<ReceivedMemo> (each w/ toAddress)
        │  watches addressLabelsProvider (for option labels)
        ▼
  client-side narrowing:
    visible = memos
      .where(hidden-partition for active view)
      .where(selectedAddress == null || m.toAddress == selectedAddress)
        │
        ▼
  dropdown options = distinct non-null toAddress in `memos`, labeled
```

## Rust Layer

- Add `pub to_address: Option<String>` to `pub(crate) struct ReceivedMemo`
  (`transactions.rs`) and to the FRB `ReceivedMemo` (`api/sync.rs`); set it from
  the `output.to_address.clone()` already available in the `get_received_memos`
  loop. Codegen regenerates `lib/src/rust/api/sync.dart` (+ frb_generated).
- No new query, no filter logic in Rust. `to_address` is the only addition.

## Dart Layer

- `MemosTab` gains `String? _selectedAddress` state (null = All).
- **Options derivation:** from the current `receivedMemosProvider` result, the
  distinct non-null `toAddress` values (stable order — e.g. by first appearance
  or by label then address). Build `[All] + options`. Hide the dropdown when
  `< 2` distinct addresses.
- **Display label:** `ref.watch(addressLabelsProvider).labelFor(account, addr)`
  ?? truncated `addr`. Reuse the existing truncation/label conventions from the
  My Addresses screen where reasonable.
- **Filtering:** extend the existing inbox/hidden partition with the address
  predicate. `_selectedAddress == null` → no address narrowing.
- **Reset:** when the derived option set changes and no longer contains
  `_selectedAddress`, set it back to null.
- Keep the dropdown a focused widget (e.g. `_AddressFilter`) so `memos_tab.dart`
  stays readable.

## States & Error Handling

- **Specific address, no results in the active view:** "No memos for this
  address" empty state, distinct from the existing "No memos yet" /
  "No memos match" / all-hidden states.
- **Locked:** unchanged — `receivedMemosProvider` already returns empty when
  locked, so the dropdown disappears (<2 addresses) and the list is empty.
- **Account switch:** options recompute from the new account's memos; selection
  resets if absent.

## Testing

### Rust
- `get_received_memos` populates `to_address` for received outputs (extend
  existing tests; assert it equals the inbound output's address; NULL when the
  output had no linked address).

### Dart
- Filter options are the distinct non-null receiving addresses of the loaded
  memos; labeled addresses show their label, unlabeled show a truncated address.
- Selecting an address narrows the list to memos with that `toAddress`.
- Composition: address filter + search both applied; address filter applies
  within the Hidden view too.
- Dropdown hidden when < 2 distinct addresses.
- Reset to All when the selected address is no longer in the option set.
- "No memos for this address" empty state renders for an address+view with no
  matches.

## Build Step

After the Rust `ReceivedMemo` field addition, from the worktree root:

```
flutter_rust_bridge_codegen generate
```

## Notes

- Because filtering is client-side over the already-loaded per-query list, it
  composes with the Rust-backed search without extra round-trips, and reuses the
  same in-memory list the Hidden partition already operates on.
- This is the terminal sub-project of the receiving-address-filter effort; with
  it, the memo inbox supports search, hide/restore, and address filtering, and
  addresses are nameable (sub-project 1).
