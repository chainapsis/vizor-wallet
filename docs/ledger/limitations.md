# Ledger Zcash app limits

Start here when changing a Ledger send, Gift Card, shielding, swap, or voting
flow. Limits belong to the **Zcash app running on the device**, not the Ledger
Wallet desktop application or the host signing crate.

## Two different budgets

**32 actions does not mean 32 recipients.** The supported device apps can
review only **4 external shielded outputs in one transaction**, even when
their per-pool action counts remain below 32. Internal change is excluded from
those 4 outputs. A payment to the account's own external address still counts.

| Constraint | Scope | Current enforcement |
| --- | --- | --- |
| 32 transparent inputs | Per transaction | `ledger/limits.rs`, serializer |
| 10 transparent outputs | Per transaction | `ledger/limits.rs`, serializer |
| 32 Orchard actions | Orchard bundle | `ledger/limits.rs`, serializer and Gift Card planner |
| 32 Ironwood actions | Ironwood bundle | `ledger/limits.rs`, serializer and Gift Card planner |
| 4 external shielded outputs | Orchard + Ironwood combined; exclude internal change | Gift Card planner and UI; firmware checks every transaction |
| 1 shielded change output | Per transaction | Ledger input selection uses `SplitPolicy::single_output`; firmware verifies change belongs to the signing account |
| 1,024 bytes of retained memo text | Both shielded pools combined | Firmware switches subsequent memo display to hashes when the review budget is exhausted |
| No Sapling spends or outputs | Per transaction | PCZT parser and proposal preparation |
| No automatic Orchard-to-Ironwood recovery | Product flows | Explicit release/capability gate; only the developer canary bypasses it |
| Mainnet only | Production account APIs | Network gate; testnet/regtest firmware is a separate test build |

The memo preflight handles the single memo-bearing output built by current
product proposals. A future multi-memo flow must model the device's cumulative
text-retention budget; the per-output printable-ASCII check alone is insufficient.
Likewise, the Gift Card review-count check is proposal-level, not a general
classification of arbitrary PCZT outputs.

## Supported app versions

| Device app | Existing-account signing | New account import | Memo shown as a hash |
| --- | --- | --- | --- |
| Below 3.9.3 | Refused | Refused | Not applicable |
| 3.9.3 | Allowed within these limits | Refused | Refused; the app has a memo-hasher defect |
| 3.9.4 | Allowed within these limits | Allowed | Allowed |

Both supported versions have the same record and review limits. There is no
3.9.2 compatibility branch. Higher versions pass the existing minimum-version
policy; that does **not** remove these bounds or prove that recovery works.

The firmware reference is
[`LedgerHQ/app-zcash` 3.9.4, `1a0f649`](https://github.com/LedgerHQ/app-zcash/tree/1a0f6495458ecb77abf97c8cff25b0a1a344daaa):
`src/consts.rs`, `src/parser/pczt.rs`, and its Orchard/Ironwood parsers.
Host constants live in [`limits.rs`](../../rust/src/wallet/ledger/limits.rs).
The Flutter review-count policy lives alongside app-version capabilities in
[`ledger_capability.dart`](../../lib/src/features/ledger/ledger_capability.dart).
Gift Card limits and UI use that constant directly. Rust and Flutter boundary
tests check enforcement and the selectable card count respectively.

## Privacy before signing

Product USB and Bluetooth signing check the device's public key at
`m/44'/133'/account'/0/0` against the key derived from the stored UFVK **before
streaming PCZT bytes**. Checking signatures afterwards protects correctness but
cannot undo disclosure to the wrong seed's device. The probe is silent and
adds one APDU exchange; it is an account-key check, not hardware attestation.
It needs no new secure-storage field or account migration.

The local account fingerprint remains part of PCZT/account validation. Only the
fingerprint field in outgoing device packets is zeroed: the firmware derives
keys from the path and does not use the fingerprint to authenticate the account.
Returned signatures are still cryptographically verified.

## Changing a limit or capability

1. Verify the actual firmware implementation and its release status. An open
   firmware PR or a host-crate version is not a deployed device capability.
2. Update the relevant Rust enforcement, Flutter policy, and this table together.
   Test the boundary and an adjacent software/Keystone path.
3. Run the affected [Speculos scenario](speculos.md). For recovery, run the
   Orchard-to-Ironwood canary before removing the release gate. Speculos proves
   firmware/APDU behavior, not physical USB/Bluetooth or production broadcast.

`pczt-ledger` is a comparison/reference implementation; Vizor does not add it as
a dependency. Its open PR #4 concerns emulator tests, not larger device limits.
