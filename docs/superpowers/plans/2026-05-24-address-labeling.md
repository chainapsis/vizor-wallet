# Address Labeling Implementation Plan (sub-project 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users assign local, human-friendly names to their own receiving (unified) addresses, manageable both inline on the Receive screen and in a dedicated "My Addresses" screen reached from Settings.

**Architecture:** A new Rust `list_account_addresses` query reads external receiving addresses from the librustzcash `addresses` table; Dart stores labels locally per-account (keyed by address string) via `AppSecureStore`, mirroring the existing `hiddenMemosProvider`. The Receive screen gains an inline name field; a new My Addresses screen lists addresses with rename. No change to address derivation.

**Tech Stack:** Rust (`zcash_client_sqlite`, `rusqlite`, `flutter_rust_bridge` v2), Flutter (Dart, Riverpod, go_router), `flutter_secure_storage`.

**Spec:** `docs/superpowers/specs/2026-05-24-address-labeling-design.md`

**Branch:** continue on `feature/received-memo-inbox` (stacked on the memo-inbox work). Run from `/Users/zakimanian/code/vizor-wallet/.worktrees/received-memo-inbox`. Use `cargo` from `rust/`; `fvm flutter ...` and `flutter_rust_bridge_codegen generate` from the worktree root.

---

## File Structure

**Rust (create/modify):**
- Modify `rust/src/wallet/keys.rs` — add `AccountAddress` struct + `list_account_addresses()` query + unit tests.
- Modify `rust/src/api/wallet.rs` — FRB `AccountAddress` struct + `list_account_addresses()` wrapper.
- Generated: `rust/src/frb_generated.rs`, `lib/src/rust/api/wallet.dart` (+ frb_generated.* variants).

**Dart (create/modify):**
- Modify `lib/src/core/storage/app_secure_store.dart` — add `kAddressLabelsKey`.
- Create `lib/src/features/receive/address_label_policy.dart` — pure label normalize/validate helper.
- Create `lib/src/providers/address_labels_provider.dart` — local per-account label store (mirrors `hidden_memos_provider.dart`).
- Modify `lib/src/features/receive/screens/receive_screen.dart` — inline "Name this address" field.
- Create `lib/src/features/settings/screens/my_addresses_screen.dart` — the manager screen.
- Modify `lib/src/features/settings/screens/settings_screen.dart` — a "My addresses" row.
- Modify `lib/app.dart` — register `/settings/my-addresses` route.

**Reuse:** `test/helpers/in_memory_secure_storage.dart` (from the memo-inbox work) for storage-backed tests.

**Baseline:** before starting, `cd rust && cargo check` and `fvm flutter analyze` to confirm a clean start (note: the pre-existing `app_secure_store_test` "password rotation" test flakes under full-suite load — run target tests in isolation).

---

## Task 1: Rust — `list_account_addresses` query

**Files:**
- Modify: `rust/src/wallet/keys.rs`
- Test: same file, `#[cfg(test)] mod tests`

- [ ] **Step 1: Write the failing test**

In the `keys.rs` test module (mirror the existing account tests that build a wallet with `tempdir`), create a wallet/account, generate one extra external address via the same path the app uses (`db.get_next_available_address(account_id, UnifiedAddressRequest...)` — match how `transactions::get_next_available_address` calls it), then assert:
- `list_account_addresses(db_path, network, account_uuid)` returns >= 2 addresses (default + generated), all with `key_scope = 0` semantics (i.e. they are external receiving UAs).
- Exactly one has `is_default == true`.
- Newest-generated address sorts first (its `address` string differs from the default).
- An address from a *different* account is not present.

(If generating a second address in-test is awkward, at minimum assert the default address is returned with `is_default == true` and that the list contains only that account's address. Prefer the 2-address version — model it on `transactions.rs`'s address handling.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd rust && cargo test list_account_addresses`
Expected: FAIL — function not found.

- [ ] **Step 3: Implement**

Add struct (near other `pub(crate)` result structs in `keys.rs`):

```rust
pub(crate) struct AccountAddress {
    pub address: String,
    pub is_default: bool,
}
```

Add the function. Get a read-only `rusqlite::Connection` via **`crate::wallet::sync::open_readonly_conn(db_path)`** (it is `pub(crate)`, defined in `rust/src/wallet/sync/mod.rs`, and returns a `rusqlite::Connection` — exactly what `transactions.rs` uses). Query the `addresses` table joined to `accounts` by uuid, **`WHERE key_scope = 0`**, ordered by `diversifier_index_be DESC` (big-endian BLOB byte order == numeric order; do NOT decode to an integer). Mark `is_default` for the row with the smallest `diversifier_index_be`.

```rust
pub fn list_account_addresses(
    db_path: &str,
    _network: WalletNetwork,
    account_uuid: &str,
) -> Result<Vec<AccountAddress>, String> {
    let uuid = uuid::Uuid::parse_str(account_uuid).map_err(|e| format!("Invalid UUID: {e}"))?;
    let conn = crate::wallet::sync::open_readonly_conn(db_path)?;
    let mut stmt = conn
        .prepare(
            r#"
            SELECT a.address, a.diversifier_index_be
            FROM addresses a
            JOIN accounts acc ON acc.id = a.account_id
            WHERE acc.uuid = ?1 AND a.key_scope = 0
            ORDER BY a.diversifier_index_be DESC
            "#,
        )
        .map_err(|e| format!("SQL error: {e}"))?;
    let rows = stmt
        .query_map(rusqlite::params![uuid.as_bytes().as_slice()], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, Vec<u8>>(1)?))
        })
        .map_err(|e| format!("Query error: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Row error: {e}"))?;

    // Default = smallest diversifier_index_be (last in DESC order).
    let min_div = rows.iter().map(|(_, d)| d).min().cloned();
    Ok(rows
        .into_iter()
        .map(|(address, div)| AccountAddress {
            address,
            is_default: Some(&div) == min_div.as_ref(),
        })
        .collect())
}
```

`accounts.uuid` is stored as bytes — the delete path in `keys.rs` already binds `account_uuid.as_bytes().as_slice()` against `accounts`/`ta.uuid`; do the same here (`uuid.as_bytes().as_slice()`).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd rust && cargo test list_account_addresses`
Expected: PASS.

- [ ] **Step 5: Re-export + commit**

If `keys.rs` items are re-exported through a `mod.rs` for the API layer, ensure `list_account_addresses` and `AccountAddress` are reachable from `rust/src/api/wallet.rs` (check how `get_address_from_db` / existing `keys::` functions are referenced there — they're called as `keys::...`, so a `pub fn` in `keys.rs` is reachable as `keys::list_account_addresses`; `pub(crate) struct AccountAddress` is reachable as `keys::AccountAddress`). No extra re-export needed if the api layer uses `keys::`.

```bash
git add rust/src/wallet/keys.rs
git commit -m "feat(rust): add list_account_addresses query"
```
End commit body with: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`

---

## Task 2: Rust — FRB wrapper + codegen

**Files:**
- Modify: `rust/src/api/wallet.rs`
- Generated: `rust/src/frb_generated.rs`, `lib/src/rust/api/wallet.dart`, `lib/src/rust/frb_generated*.dart`

- [ ] **Step 1: Add FRB struct + wrapper**

In `rust/src/api/wallet.rs`, mirror the existing `get_unified_address` wrapper style:

```rust
pub struct AccountAddress {
    pub address: String,
    pub is_default: bool,
}

pub fn list_account_addresses(
    db_path: String,
    network: String,
    account_uuid: String,
) -> Result<Vec<AccountAddress>, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let addrs = keys::list_account_addresses(&db_path, network, &account_uuid)?;
        Ok(addrs
            .into_iter()
            .map(|a| AccountAddress { address: a.address, is_default: a.is_default })
            .collect())
    })
}
```

(Confirm `catch` is in scope in `wallet.rs` as it is in `sync.rs`; if `wallet.rs` uses a different error-wrapping idiom, follow that file's existing pattern.)

- [ ] **Step 2: Run codegen**

Run (worktree root): `flutter_rust_bridge_codegen generate`
Expected: `lib/src/rust/api/wallet.dart` declares `listAccountAddresses` and class `AccountAddress` with `address` + `isDefault`.

- [ ] **Step 3: Verify compile**

Run: `cd rust && cargo check` (clean) then `fvm flutter analyze lib/src/rust/` (no errors).

- [ ] **Step 4: Commit**

```bash
git add rust/src/api/wallet.rs rust/src/frb_generated.rs lib/src/rust/
git commit -m "feat(rust): FRB list_account_addresses, regen bindings"
```
End commit body with the Co-Authored-By line.

---

## Task 3: Dart — label policy helper

**Files:**
- Create: `lib/src/features/receive/address_label_policy.dart`
- Test: `test/features/receive/address_label_policy_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/receive/address_label_policy.dart';

void main() {
  test('trims and preserves a normal label', () {
    expect(normalizeAddressLabel('  Donations  '), 'Donations');
  });
  test('blank becomes null (clears the label)', () {
    expect(normalizeAddressLabel('   '), isNull);
    expect(normalizeAddressLabel(''), isNull);
  });
  test('truncates to max length', () {
    final long = 'x' * 100;
    expect(normalizeAddressLabel(long)!.length, kAddressLabelMaxLength);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/features/receive/address_label_policy_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
const int kAddressLabelMaxLength = 50;

/// Normalizes a user-entered address label: trims whitespace, enforces the
/// max length, and returns null for blank input (which clears the label).
String? normalizeAddressLabel(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.length > kAddressLabelMaxLength
      ? trimmed.substring(0, kAddressLabelMaxLength)
      : trimmed;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `fvm flutter test test/features/receive/address_label_policy_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/receive/address_label_policy.dart test/features/receive/address_label_policy_test.dart
git commit -m "feat(dart): address label normalize/validate helper"
```
End commit body with the Co-Authored-By line.

---

## Task 4: Dart — `addressLabelsProvider` (local persistence)

**Files:**
- Modify: `lib/src/core/storage/app_secure_store.dart` (add `const kAddressLabelsKey = 'zcash_address_labels';` in the plain-key const block)
- Create: `lib/src/providers/address_labels_provider.dart`
- Test: `test/providers/address_labels_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Mirror `test/providers/hidden_memos_provider_test.dart` exactly (it already uses `AppSecureStore.testing(storage: InMemorySecureStorage())` from `test/helpers/in_memory_secure_storage.dart` + `appSecureStoreProvider` override). Assert:
- `setLabel(account:'A', address:'u1aaa', label:'Donations')` then `labelFor('A','u1aaa') == 'Donations'`.
- setting a blank label removes it (`labelFor` → null).
- `removeLabel` removes it.
- per-account isolation ('A' vs 'B').
- JSON round-trips: a second container over the same store sees the label.
- self-initializes from pre-seeded storage WITHOUT an explicit `load()` (pump microtasks, then assert).

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/providers/address_labels_provider_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Add `kAddressLabelsKey` to `app_secure_store.dart`. Create `address_labels_provider.dart` by closely following `lib/src/providers/hidden_memos_provider.dart`:
- `appSecureStoreProvider` already exists (reuse the one from `hidden_memos_provider.dart` — import it; do NOT declare a second). If it is private to that file, promote it to a shared location (e.g. its own `lib/src/providers/app_secure_store_provider.dart`) and have both providers import it — note this refactor in your report.
- `AddressLabelsState` wrapping `Map<String, Map<String, String>>` (accountUuid → {address → label}); `labelFor(account, address)` returns `String?`; `toSerializable()` for persistence.
- `AddressLabelsNotifier extends Notifier<AddressLabelsState>`: `build()` does `Future.microtask(load)`; `load()` public + idempotent; `_mutationGen` guard identical to `HiddenMemosNotifier`; `setLabel({accountUuid, address, label})` (apply `normalizeAddressLabel`; null/blank removes), `removeLabel({accountUuid, address})`; persist whole JSON via `writePlain(kAddressLabelsKey, ...)`, load via `readPlain`.

- [ ] **Step 4: Run to verify it passes**

Run: `fvm flutter test test/providers/address_labels_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/core/storage/app_secure_store.dart lib/src/providers/address_labels_provider.dart test/providers/address_labels_provider_test.dart lib/src/providers/app_secure_store_provider.dart
git commit -m "feat(dart): local per-account address-labels store"
```
(Include the shared `appSecureStoreProvider` file only if you extracted it.) End commit body with the Co-Authored-By line.

---

## Task 5: Dart — inline naming on the Receive screen

**Files:**
- Modify: `lib/src/features/receive/screens/receive_screen.dart`
- Test: `test/features/receive/receive_address_naming_test.dart`

- [ ] **Step 1: Write the failing widget test**

This screen has real dependencies (loads addresses via `receiveAddressServiceProvider`, reads `walletProvider`/`accountProvider`). Prefer extracting a small `AddressNameField` `ConsumerWidget` that takes `(accountUuid, address)` and renders a label `TextField` bound to `addressLabelsProvider`, and test THAT widget directly (override `appSecureStoreProvider` with an in-memory store). Assert:
- pre-fills with the existing label when one is set (pre-seed the store).
- editing + submitting calls `setLabel` and persists (read back via the provider).
- clearing the field removes the label.

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/features/receive/receive_address_naming_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Create `AddressNameField` (in `receive_screen.dart` or a sibling widget file). It watches `addressLabelsProvider` for the current `(activeAccountUuid, _shieldedAddress)` and writes via `ref.read(addressLabelsProvider.notifier).setLabel(...)` on submit/blur, using `normalizeAddressLabel`. Place it on the Receive screen below the shielded address (only when a shielded address is shown; not for the transparent type). Naming is optional and must NOT block renew/generate.

- [ ] **Step 4: Run to verify it passes**

Run: `fvm flutter test test/features/receive/receive_address_naming_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/receive/ test/features/receive/receive_address_naming_test.dart
git commit -m "feat(dart): inline address naming on Receive screen"
```
End commit body with the Co-Authored-By line.

---

## Task 6: Dart — My Addresses screen + Settings entry + route

**Files:**
- Create: `lib/src/features/settings/screens/my_addresses_screen.dart`
- Modify: `lib/src/features/settings/screens/settings_screen.dart` (add a row)
- Modify: `lib/app.dart` (register route `/settings/my-addresses`)
- Test: `test/features/settings/my_addresses_screen_test.dart`

- [ ] **Step 1: Write the failing widget test**

Introduce a repository seam so the address list is fakeable (mirror the memo-inbox `memoRepositoryProvider` pattern): `addressListProvider = FutureProvider.family<List<rust_wallet.AccountAddress>, String>` (accountUuid) that calls `rust_wallet.listAccountAddresses(...)`, behind an overridable `addressRepositoryProvider`. Pump `MyAddressesScreen` with the repo overridden to return 2 fake `AccountAddress`es and `appSecureStoreProvider` → in-memory store. Assert:
- both addresses render; unlabeled shows italic "Unnamed".
- a Rename action edits a label; after saving, the row shows the new label and it persists via `addressLabelsProvider`.

- [ ] **Step 2: Run to verify it fails**

Run: `fvm flutter test test/features/settings/my_addresses_screen_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

- `addressRepositoryProvider` + `addressListProvider` (resolve `getWalletDbPath()` + `rpcEndpointProvider.networkName` + active account internally, like `memo_repository.dart`).
- `MyAddressesScreen`: lists `addressListProvider` rows; each row shows label-or-"Unnamed", truncated address, Rename (inline edit or small dialog) writing via `addressLabelsProvider.notifier.setLabel`. Loading/error/empty states like the Activity screen conventions (don't mask error as empty).
- `settings_screen.dart`: add a `_SettingsRow` (e.g. under the "Account" or "System" section) with `onTap: () => context.push('/settings/my-addresses')`, wired through the same callback pattern the screen already uses (see `onEndpoint`/`onSeedPhrase`).
- `lib/app.dart`: add `GoRoute(path: '/settings/my-addresses', builder: (_, _) => const MyAddressesScreen())` next to the other `/settings/*` routes.

- [ ] **Step 4: Run to verify it passes**

Run: `fvm flutter test test/features/settings/my_addresses_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/settings/ lib/src/providers/ lib/app.dart test/features/settings/my_addresses_screen_test.dart
git commit -m "feat(dart): My Addresses screen with rename, Settings entry + route"
```
End commit body with the Co-Authored-By line.

---

## Task 7: Full verification

- [ ] **Step 1: Rust** — `cd rust && cargo test --lib` → all pass (existing + new `list_account_addresses` tests).
- [ ] **Step 2: Dart analyze** — `fvm flutter analyze` → no NEW issues in changed files (pre-existing cargokit `rust_builder` errors are unrelated; ignore).
- [ ] **Step 3: Dart targeted tests** — run the new test files plus the existing memo tests to confirm no regression:
  `fvm flutter test test/features/receive/ test/features/settings/my_addresses_screen_test.dart test/providers/address_labels_provider_test.dart test/features/activity/ test/providers/hidden_memos_provider_test.dart`
  → all pass. (Avoid the full `fvm flutter test` for pass/fail judgement due to the known `app_secure_store_test` rotation flake under load; if you run it, verify that test passes in isolation.)
- [ ] **Step 4: Manual smoke (simulator)** — Receive screen: name the current address; renew → name the new one. Settings → My Addresses: both appear with names; rename one; relaunch app and confirm names persist.
- [ ] **Step 5: Final commit** (if fixups): `git add -A && git commit -m "chore: address labeling verification fixups"`

---

## Notes for the implementer

- **`key_scope = 0` only.** Never a negative filter — `1` (internal/change), `2` (ephemeral), `-1` (foreign) must all be excluded. Only `0` is a user-facing receiving UA.
- **Order by the raw `diversifier_index_be` BLOB**, DESC, in SQL. It's big-endian so byte order == numeric order; do not decode to an integer (it's 11 bytes, won't fit u64).
- **Labels keyed by address string** — this is intentional so sub-project 2's memo filter (`v_tx_outputs.to_address`) joins with no translation.
- **Mirror the existing patterns**: `hiddenMemosProvider` (self-init + mutation-gen guard), `memoRepositoryProvider` (FFI seam), `InMemorySecureStorage` test helper. Don't reinvent them.
- **Don't duplicate `appSecureStoreProvider`** — share one definition between the hidden-memos and address-labels providers.
- Naming is optional everywhere; never gate address generation/renewal.
- This is sub-project 1. Do NOT build the memo filter (sub-project 2) — only labeling + the address list it needs.
