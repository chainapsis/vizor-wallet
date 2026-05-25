# Filter Memos by Receiving Address — Implementation Plan (sub-project 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a receiving-address dropdown filter to the Memos tab that narrows the inbox to memos received at a chosen one of the user's own addresses (shown by label when named), composing with the existing search and Inbox/Hidden views.

**Architecture:** Surface `to_address` on `ReceivedMemo` (Rust → FRB → Dart). The Memos tab derives dropdown options from the distinct non-null receiving addresses in the loaded per-query memo set, and applies the selected address as a client-side narrow on top of the existing search (Rust) + hidden partition. No new Rust query.

**Tech Stack:** Rust (`flutter_rust_bridge` v2), Flutter (Dart, Riverpod, go_router).

**Spec:** `docs/superpowers/specs/2026-05-24-memo-address-filter-design.md`

**Branch:** continue on `feature/received-memo-inbox`. Run from `/Users/zakimanian/code/vizor-wallet/.worktrees/received-memo-inbox`. `cargo` from `rust/`; `fvm flutter ...` and `flutter_rust_bridge_codegen generate` from the worktree root.

**Baseline:** the pre-existing `app_secure_store_test` rotation test flakes under full-suite load — run target tests in isolation for pass/fail.

---

## File Structure

- Modify `rust/src/wallet/sync/transactions.rs` — add `to_address: Option<String>` to `ReceivedMemo`, populate in `get_received_memos`, extend a test.
- Modify `rust/src/api/sync.rs` — add `to_address` to FRB `ReceivedMemo` + mapping; codegen regenerates `lib/src/rust/api/sync.dart` (+ frb_generated.*).
- Create `lib/src/features/activity/address_display.dart` — a shared `truncateAddress(String)` helper (extracted from the private one in `my_addresses_screen.dart`), so the filter and My Addresses share one truncation.
- Modify `lib/src/features/settings/screens/my_addresses_screen.dart` — use the shared `truncateAddress`.
- Modify `lib/src/features/activity/widgets/memos_tab.dart` — `_selectedAddress` state, options derivation, an `_AddressFilter` dropdown, compose the address narrow into both partitions, reset logic, "No memos for this address" empty state.
- Tests: extend `rust` tests; extend `test/features/activity/memos_tab_test.dart` (or a new `memos_address_filter_test.dart`).

---

## Task 1: Rust — surface `to_address` on the wallet-layer `ReceivedMemo`

**Files:**
- Modify: `rust/src/wallet/sync/transactions.rs`
- Test: same file, `mod tests`

- [ ] **Step 1: Extend the failing test**

In the existing `get_received_memos_returns_only_inbound_text_memos` test (the one that inserts an external inbound output with a known `to_address`), add an assertion that the returned `ReceivedMemo.to_address == Some(<the inbound output's address string>)`. Use the address the fixture inserted for the inbound output (the test already calls `insert_output_with_address_and_memo` with a `to_address` — assert the memo carries that same string). Also assert a memo whose output had no address (if such a fixture case exists, or add one) yields `to_address == None`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd rust && cargo test get_received_memos`
Expected: FAIL — no field `to_address` on `ReceivedMemo`.

- [ ] **Step 3: Implement**

Add `pub to_address: Option<String>,` to `pub(crate) struct ReceivedMemo` (after `output_index`). In `get_received_memos`, in the `ReceivedMemo { ... }` constructor inside the output loop, add `to_address: output.to_address.clone(),` (`output` is the `&TxOutput` in scope; `TxOutput.to_address: Option<String>` already exists, sourced from `v_tx_outputs.to_address`).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd rust && cargo test get_received_memos`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add rust/src/wallet/sync/transactions.rs
git commit -m "feat(rust): surface to_address on received memos"
```
End commit body with: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`

---

## Task 2: Rust — FRB `to_address` + codegen

**Files:**
- Modify: `rust/src/api/sync.rs`
- Generated: `rust/src/frb_generated.rs`, `lib/src/rust/api/sync.dart`, `lib/src/rust/frb_generated*.dart`

- [ ] **Step 1: Add the field + mapping**

In `rust/src/api/sync.rs`, add `pub to_address: Option<String>,` to the FRB `pub struct ReceivedMemo` (after `output_index`), and in the `get_received_memos` wrapper's `.map(|m| ReceivedMemo { ... })`, add `to_address: m.to_address,`.

- [ ] **Step 2: Run codegen**

Run (worktree root): `flutter_rust_bridge_codegen generate`
Expected: `lib/src/rust/api/sync.dart` `ReceivedMemo` class gains `final String? toAddress;`.

- [ ] **Step 3: Verify compile**

Run: `cd rust && cargo check` (clean) then `fvm flutter analyze lib/src/rust/` (no errors).

- [ ] **Step 4: Commit (ALL generated files — verify git status clean after)**

```bash
git add rust/src/api/sync.rs rust/src/frb_generated.rs lib/src/rust/
git commit -m "feat(rust): FRB to_address on ReceivedMemo, regen bindings"
```
End commit body with the Co-Authored-By line.

---

## Task 3: Dart — receiving-address filter on the Memos tab

**Files:**
- Create: `lib/src/features/activity/address_display.dart`
- Modify: `lib/src/features/settings/screens/my_addresses_screen.dart`
- Modify: `lib/src/features/activity/widgets/memos_tab.dart`
- Test: `test/features/activity/memos_address_filter_test.dart`

### 3a — shared truncation helper (small, do first)

- [ ] **Step 1: Write the failing test**

`test/features/activity/address_display_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/activity/address_display.dart';

void main() {
  test('truncates long address head…tail', () {
    final a = 'u1${'x' * 60}';
    final t = truncateAddress(a);
    expect(t.contains('...'), isTrue);
    expect(t.length, lessThan(a.length));
  });
  test('short address returned as-is', () {
    expect(truncateAddress('u1abc'), 'u1abc');
  });
}
```

- [ ] **Step 2: Run** `fvm flutter test test/features/activity/address_display_test.dart` → FAIL.

- [ ] **Step 3: Implement** `lib/src/features/activity/address_display.dart` by lifting the existing private `_truncateAddress` from `my_addresses_screen.dart` (head 10 + '...' + tail 10, guarded for short strings):
```dart
/// Shortens a (long) address for display: first 10 + '...' + last 10 chars.
/// Returns the address unchanged when it is already short.
String truncateAddress(String address) {
  if (address.length <= 22) return address;
  return '${address.substring(0, 10)}...${address.substring(address.length - 10)}';
}
```
Then change `my_addresses_screen.dart` to import and use `truncateAddress`, deleting its private `_truncateAddress`.

- [ ] **Step 4: Run** the new test + `fvm flutter test test/features/settings/my_addresses_screen_test.dart` → both PASS (My Addresses still renders truncated addresses).

- [ ] **Step 5: Commit**
```bash
git add lib/src/features/activity/address_display.dart lib/src/features/settings/screens/my_addresses_screen.dart test/features/activity/address_display_test.dart
git commit -m "refactor(dart): extract shared truncateAddress helper"
```
End commit body with the Co-Authored-By line.

### 3b — the address filter

- [ ] **Step 1: Write the failing widget test**

`test/features/activity/memos_address_filter_test.dart`. Mirror `memos_tab_test.dart`'s harness (override `memoRepositoryProvider` with a fake returning canned `ReceivedMemo`s — now WITH `toAddress` set — and `appSecureStoreProvider` → in-memory store so `addressLabelsProvider` works). Provide 3 memos: two with `toAddress: 'u1aaa...'`, one with `toAddress: 'u1bbb...'`. Assert:
- The address dropdown is present (≥2 distinct addresses) with an "All addresses" default plus the two addresses.
- A labeled address (pre-seed `addressLabelsProvider` with a label for `u1aaa...`) shows its label in the dropdown; the unlabeled one shows a truncated address.
- Selecting `u1aaa...` narrows the list to the 2 memos with that address; selecting `u1bbb...` shows the 1.
- Composition: with a search query active (set `_committedQuery` via the search field or by constructing the fake to return a filtered set) AND an address selected, both narrow.
- In the Hidden view, the address filter still applies (hide a `u1aaa` memo, switch to Hidden, select `u1aaa`, see it).
- When only one distinct address is present, the dropdown is hidden.
- Selecting an address then switching to data where it's absent resets to "All addresses".
- A specific address with no matches in the active view shows "No memos for this address".

(You may split these into several `testWidgets` — keep each focused. Use the existing `_settle`/pump helpers and `InMemorySecureStorage` from the memo tests.)

- [ ] **Step 2: Run** `fvm flutter test test/features/activity/memos_address_filter_test.dart` → FAIL.

- [ ] **Step 3: Implement**

In `memos_tab.dart`:
1. Add state: `String? _selectedAddress;` to `_MemosTabState`.
2. Inside the `memosAsync.when(data: (memos) { ... })` branch (where `memos` is available):
   - Compute `final addresses = <String>{ for (final m in memos) if (m.toAddress != null) m.toAddress! }.toList();` (distinct, preserve first-seen order or sort by label-then-address).
   - **Reset guard:** if `_selectedAddress != null && !addresses.contains(_selectedAddress)`, schedule a reset and treat as null for this build:
     ```dart
     if (_selectedAddress != null && !addresses.contains(_selectedAddress)) {
       WidgetsBinding.instance.addPostFrameCallback((_) {
         if (mounted) setState(() => _selectedAddress = null);
       });
     }
     final effectiveAddress = addresses.contains(_selectedAddress) ? _selectedAddress : null;
     ```
   - Build the partition list as today (inbox/hidden by `hiddenKeys`), THEN apply the address narrow: `.where((m) => effectiveAddress == null || m.toAddress == effectiveAddress)`.
   - Return a `Column` with: the `_AddressFilter` dropdown (only `if (addresses.length >= 2)`) above the `Expanded(child: list-or-empty-state)`.
   - Empty states: if the post-filter list is empty AND `effectiveAddress != null`, show `_MemosMessage(text: 'No memos for this address')`. Otherwise keep the existing no-memos / all-hidden / "No memos match" messages.
3. Add `_AddressFilter` widget (a `ConsumerWidget`): a `DropdownButton<String?>` (value `effectiveAddress`, items = `null` → "All addresses" plus each address) where each item's label = `ref.watch(addressLabelsProvider).labelFor(accountUuid, addr) ?? truncateAddress(addr)`; `onChanged` → `onSelected(value)` calling `setState(() => _selectedAddress = value)` in the parent. Style to match the tab (the toggle/search use simple Flutter widgets; a `DropdownButton` with the app's text styles is fine — no design-system dropdown exists).

Note: the address filter predicate must be applied to BOTH the inbox and hidden branches (factor a local `applyAddress(list)` closure to avoid duplicating the `.where`).

- [ ] **Step 4: Run** `fvm flutter test test/features/activity/memos_address_filter_test.dart test/features/activity/memos_tab_test.dart test/features/activity/memos_hide_restore_test.dart` → all PASS (filter works + no regression to existing memo tests).

- [ ] **Step 5: Run** `fvm flutter analyze lib/src/features/activity/widgets/memos_tab.dart lib/src/features/activity/address_display.dart` → no issues.

- [ ] **Step 6: Commit**
```bash
git add lib/src/features/activity/widgets/memos_tab.dart test/features/activity/memos_address_filter_test.dart
git commit -m "feat(dart): filter memos by receiving address on Memos tab"
```
End commit body with the Co-Authored-By line.

---

## Task 4: Full verification

- [ ] **Step 1: Rust** — `cd rust && cargo test --lib` → all pass (incl. the `to_address` assertion).
- [ ] **Step 2: Dart analyze** — `fvm flutter analyze` → no NEW issues in changed files (vendored `rust_builder/cargokit` errors are pre-existing/unrelated).
- [ ] **Step 3: Dart targeted tests (incl. regression)** —
  `fvm flutter test test/features/activity/ test/features/receive/ test/features/settings/my_addresses_screen_test.dart test/providers/hidden_memos_provider_test.dart test/providers/address_labels_provider_test.dart`
  → all pass. (Avoid full `fvm flutter test` for verdicts due to the known `app_secure_store_test` flake under load.)
- [ ] **Step 4: Manual smoke (simulator)** — Memos tab with memos received at ≥2 addresses: dropdown appears; "All" shows everything; selecting an address narrows; labeled addresses show names; filter + search compose; filter applies in Hidden view; dropdown hidden with one address.
- [ ] **Step 5: Final commit** (if fixups): `git add -A && git commit -m "chore: memo address filter verification fixups"`

---

## Notes for the implementer

- `to_address` is the ONLY Rust change — a single field threaded through; no new query, no filter in Rust.
- The filter is **client-side**, composing with the Rust-backed search and the existing hidden partition. Apply the address predicate to BOTH inbox and hidden branches.
- **Options derive from the loaded (search-filtered) memo set — this is intentional** (see spec). Do NOT add a separate unfiltered provider to keep options stable across searches. The dropdown hides at <2 options.
- The reset-when-absent must use a post-frame `setState` (never `setState` during build) and use an `effectiveAddress` fallback for the current build.
- NULL `toAddress` memos are never a dropdown option and show only under "All addresses" — no "Unknown" bucket.
- Reuse the existing memo-test harness (`memoRepositoryProvider` override + `InMemorySecureStorage` + `addressLabelsProvider`). Construct fake `ReceivedMemo`s with the new `toAddress` field set.
- This is the final sub-project; do not expand scope.
