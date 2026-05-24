# Address Labeling — Design

Date: 2026-05-24
Status: Approved for planning

## Summary

Let users assign human-friendly names to their own receiving addresses. This is
**sub-project 1** of a two-part effort; **sub-project 2** (filter received memos
by receiving address) builds on it and is specced separately.

Vizor's Receive screen mints a new diversified unified address (UA) each time
the user "renews" the shielded address (`getNextAvailableAddress` →
`zcash_client_sqlite` advances the diversifier and inserts a row into the
`addresses` table). Over time an account accumulates multiple receiving
addresses. Today they are opaque UA strings with no names. This feature adds
local, per-account labels and two places to manage them.

## Context: why this is the prerequisite

The motivating goal is "filter received memos by which of my addresses got
paid." `get_received_memos`/`v_tx_outputs.to_address` already exposes the
receiving address (the `addresses.address` linked to a received note via
`address_id`). But raw UA strings are unusable as filter facets, so addresses
must be nameable first. Labeling is sub-project 1; the memo filter is
sub-project 2 and is out of scope here.

## Decisions

1. **Scope of "addresses":** only the user's own receiving (unified) addresses —
   the UAs they generate/hand out. NOT a general contacts/address-book of
   external addresses. (App-wide contacts was explicitly rejected.)
2. **Placement:** both — inline naming on the Receive screen AND a dedicated
   "My Addresses" manager screen. They share one label store.
3. **Storage:** local device only, via `AppSecureStore.writePlain`, same model
   as the hidden-memos store. Survives restart; wiped on wallet reset; NOT
   recoverable from seed and NOT synced across devices. (Wallet-DB storage was
   rejected: same seed-restore durability, but adds librustzcash migration risk.)
4. **Label key:** the **address string** (not diversifier index). This is what
   `v_tx_outputs.to_address` carries, so sub-project 2's filter joins with zero
   translation.
5. **Naming is optional** and never gates address generation/renewal.
6. **Labels** are free text, trimmed, max 50 characters, duplicates allowed.
7. **My Addresses scope:** unified receiving addresses only (external key
   scope) — not the transparent-only receiver, not internal/change addresses.
8. **My Addresses entry point:** a row in **Settings** (not a new sidebar item).

## Non-Goals (sub-project 1)

- The memo filter itself (sub-project 2).
- Labeling external/contact addresses (Send recipients, etc.).
- Labeling the transparent-only receiver.
- Syncing labels across devices or deriving them from seed.
- Editing/labeling internal (change) addresses.
- Listing the gap-limit lookahead pool (unexposed addresses the user has never
  been shown).
- Any change to address derivation or the Receive renewal behavior itself.

## Architecture

```
Receive screen (inline name field)        Settings → My Addresses screen
        │  setLabel/labelFor                       │  list + rename
        ▼                                          ▼
        addressLabelsProvider (Riverpod, local, per-account)
        │  persists via                            │  lists via
        ▼                                          ▼
AppSecureStore.writePlain(zcash_address_labels)   listAccountAddresses(account)  [FRB]
                                                          │
                                                          ▼
                                          rust: list_account_addresses
                                                          │ reads
                                                          ▼
                                          wallet DB `addresses` table
```

## Rust Layer

New function in `rust/src/wallet/keys.rs` (addresses live with key/address
logic), exposed via a thin FRB wrapper in `rust/src/api/wallet.rs`.

### API surface

```rust
// FRB-facing (rust/src/api/wallet.rs) — flat struct + primitives
pub struct AccountAddress {
    pub address: String,   // the unified address string (matches v_tx_outputs.to_address)
    pub is_default: bool,  // the account's default/first (lowest-diversifier) address
}

pub fn list_account_addresses(
    db_path: String,
    network: String,
    account_uuid: String,
) -> Result<Vec<AccountAddress>, String>;
```

The returned `Vec` is already sorted newest-first, so Dart relies on list order
and does not need the diversifier index. The address string is the stable
identity (and the label key).

### Implementation notes

- Query the `addresses` table joined to `accounts` by `account_uuid`, filtering
  to **external, exposed** receiving addresses:
  **`WHERE key_scope = 0 AND exposed_at_height IS NOT NULL`**.
  - `key_scope` values: `0` = External (the user-visible receiving UAs we want),
    `1` = Internal/change, `2` = Ephemeral (ZIP 320 interstitial), `-1` = Foreign
    (imported standalone transparent pubkeys). Only `0` is in scope. Do NOT use a
    negative filter like `key_scope != -1` — it would wrongly include internal
    (`1`) and ephemeral (`2`) rows.
  - **`exposed_at_height IS NOT NULL` is required.** `create_account`
    pre-populates a gap-limit *lookahead pool* of `key_scope = 0` addresses that
    the user has never been shown (`exposed_at_height = NULL`). Without this
    clause the list would be polluted with ~gap-limit unused addresses.
    librustzcash itself uses `exposed_at_height IS NOT NULL` to enumerate
    known/exposed addresses (`zcash_client_sqlite` `wallet.rs:978`, `1055`).
    The account's default address is inserted *exposed* (`exposed_at_height =
    birthday`), and `get_next_available_address` exposes each newly generated
    address, so this filter yields exactly the addresses the user has actually
    been handed — the correct set for both My Addresses and the future memo
    filter.
  - `is_default` = the exposed address with the smallest `diversifier_index_be`
    (the account default).
- **Ordering: `ORDER BY diversifier_index_be DESC` directly in SQL.**
  `diversifier_index_be` is an 11-byte big-endian BLOB, so SQLite's byte-wise
  BLOB comparison preserves numeric order — no decode to an integer is needed
  (and an 11-byte index cannot reliably fit a `u64`, so don't try). This gives
  newest-generated-first.
- `is_default`: the row with the lowest `diversifier_index_be` (the account's
  first/default address). Compute via a `MIN(diversifier_index_be)` comparison
  or by marking the last row after the DESC sort.
- The CHECK constraint `(diversifier_index_be IS NULL) == (key_scope = -1)`
  guarantees `diversifier_index_be` is non-NULL for `key_scope = 0`, so the
  ORDER BY is well-defined.
- Reuse `open_wallet_db_for_read` (the read helper in `keys.rs`) and the read
  patterns already there.
- `network` is parsed for consistency with sibling wrappers; the read-only
  query does not otherwise need it (carry as `_network` like the others).

## Dart Layer

- **`addressLabelsProvider`** (Riverpod `Notifier`): self-initializing
  (`Future.microtask(load)` in `build()`), with the same mutation-generation
  guard as `hiddenMemosProvider` so a deferred load cannot clobber a just-applied
  edit. Persists `{ "<accountUuid>": { "<address>": "<label>" } }` JSON via
  `AppSecureStore.writePlain(kAddressLabelsKey)`; loads via `readPlain`. Store
  injected via an overridable provider seam for tests.
  - `String? labelFor(String accountUuid, String address)`
  - `Future<void> setLabel({accountUuid, address, label})` — trims; empty/blank
    label removes the entry.
  - `Future<void> removeLabel({accountUuid, address})`
  - Not sensitive: persists across lock; wiped by `deleteAll` on reset.
- **`kAddressLabelsKey = 'zcash_address_labels'`** added to
  `app_secure_store.dart`.
- **Receive screen**: an optional "Name this address" field bound to the
  currently displayed shielded address. Pre-fills with the existing label.
  Saving calls `setLabel`. Does not block renew/generate.
- **My Addresses screen**: a new `ConsumerWidget`/screen listing
  `listAccountAddresses(activeAccount)` rows — each shows the label (or italic
  "Unnamed"), the truncated address, and a Rename action (inline edit or a small
  dialog). Reached from a new Settings row.
- **Label validation** reuses a small pure helper (trim, max 50). Keep it in a
  focused file so both Receive and My Addresses share it.

## States & Error Handling

- **Locked:** the Receive screen and My Addresses are behind unlock already;
  labels are non-sensitive and need no special lock handling.
- **`list_account_addresses` error:** My Addresses shows an error state (do not
  mask as empty).
- **Empty:** an account always has at least its default address, so the list is
  never truly empty; still handle gracefully.
- **Unknown/NULL receiving address (future, sub-project 2):** out of scope here
  but noted — some received notes may have a NULL `to_address`; the filter will
  bucket those separately.

## Security Notes

- Labels are user-chosen plaintext stored in the app-local plain KV. Not secret,
  no new sensitive data. Address strings are already user-visible.
- No new cryptography, no change to key/address derivation.
- At-rest exposure unchanged beyond storing user-entered names.

## Testing

### Rust (`keys.rs` test module, tempdir + addresses-table fixtures)
- `list_account_addresses` returns external receiving addresses for the account.
- Internal/change-scope addresses are excluded.
- Multiple generated addresses are returned newest-first; `is_default` marks the
  first/default one.
- Addresses for other accounts are excluded.

### Dart
- `addressLabelsProvider`: set/labelFor/remove; per-account isolation; empty
  label removes; round-trips through `AppSecureStore` (reuse
  `test/helpers/in_memory_secure_storage.dart`); self-initializes from storage
  without an explicit `load()`.
- Label helper: trims, enforces max length.
- Widget: Receive inline naming saves and pre-fills; My Addresses lists
  addresses, rename updates the row and persists, "Unnamed" shown for unlabeled.

## Build Step

Adding a Rust API function/struct requires, from the worktree root:

```
flutter_rust_bridge_codegen generate
```

## Follow-on

- **Sub-project 2 — filter received memos by receiving address:** the Memos tab
  gains a filter listing the account's labeled receiving addresses; selecting one
  narrows the inbox (composing with the existing search and hidden partition).
  Uses `to_address` (added to `ReceivedMemo`) joined against this label store.
  Specced separately once this lands.
