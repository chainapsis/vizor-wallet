# Ledger core review tracks

This classifies merge dependencies, not the order in which users can access
Ledger features. A native adapter can compile and be reviewed before the Dart
coordinator or onboarding UI calls its method channel.

The collection is #693 (`rowan/ledger-core-collection`). Keep it as a draft.
Every code slice still needs review before merging into the collection; this
classification does not authorize merging the collection into main.

## Direct collection targets

| Slice | Status | Why it can target the collection |
| --- | --- | --- |
| C01 USB/protocol | Merged, #695 | Foundation already present |
| C02 account import and signer dispatch | In review, #696 | Depends on merged C01; signer refactor is in progress |
| C04 Apple BLE | Draft, #700 | Swift adapter, registrations and native dependencies are self-contained |
| C05 Android BLE | Draft, #698 | Kotlin adapter, permissions and native dependencies are self-contained |
| C06a shared native BLE protocol | Preparing | Platform-neutral framing, response assembly and operation gate, with host tests |

C04 and C05 were originally stacked on C03. Their own native patches apply
unchanged to the collection and have been rebased to target it directly.
Neither needs to wait for C02's signer-dispatch refactor or for the other
platform adapter. C04 raises the app-wide minimum to macOS 12; C05 raises the
app-wide minimum to Android 11 (API 30). Those remain release constraints.

## One shared prerequisite, independent adapters

| Slice | Initial base | Merge condition |
| --- | --- | --- |
| C06b Windows BLE | C06a | After C06a merges, rebase its Windows-only commit onto the collection |
| C07 Linux BLE | C06a | After C06a merges, rebase its Linux-only commit onto the collection |

C06a owns `native/ledger/ble_protocol.h`, `ble_operation_gate.h` and their
transport-neutral tests. Windows and Linux reuse these headers, but do not
depend on one another. The source inventory's C06 ownership covers C06a and
C06b together; this split does not duplicate ownership or leave common files
unassigned.

Native channel implementations expose discovery, connection, readiness, UFVK
exchange and cancellation. Transaction-signing-only channel methods belong
with C08. C03 integration and physical device tests are separate from the
native compilation and fake-transport evidence recorded in each PR.

## Slices that still need feature prerequisites

| Slice | Required predecessor code |
| --- | --- |
| C03 connection coordination, #697 | C02 account/import APIs |
| C08 PCZT signing | C02 and C03, plus C01 protocol |
| C09 planning/device limits | C02 and C08 |
| C10 signed-operation recovery | C02 and C08 |
| C11 send, C12 shield, C13 swap/pay | C08, C09 and C10 |
| C14 voting | C02, C03 and C08 |
| C15 Wallet Link | C02 and C03; C08 and a mobile adapter for first-sign integration |

C09 and C10 are candidates for parallel review after C08. Later execution
slices may also be prepared in parallel once their shared contracts settle;
shared generated bridge files must have one owner during regeneration.

## Rebase and validation

- Fetch and record the collection and old head before moving a PR. Retain a
  rollback ref and use an explicit force-with-lease for rewritten branches.
- Move only the slice's own commits; changing the PR base alone can accidentally
  include unmerged parent features.
- Compare the resulting diff against the former slice diff. When only ancestry
  changes, report that fact and identify which base the earlier build exercised.
- Native protocol tests do not prove host OS integration, permission prompts,
  physical pairing or radio behavior. State unavailable platform builds and
  device tests explicitly instead of substituting earlier source-branch results.
