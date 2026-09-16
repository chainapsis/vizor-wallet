# Ledger account import core

C02 adds account import and persistence on top of the C01 USB protocol. The
source implementation is `fbe51859972213eb0c70dc80bda67c7ef7f249e8`.

## Account contract

`ledger_export_account` requests the selected mainnet account from the connected
USB Ledger, validates its UFVK, and returns the account index, synthetic
derivation fingerprint and optional USB product name. The selected Zcash app
must already be open. Connection readiness and transport selection are C03.

`AccountNotifier.importLedgerAccount` imports that material into the wallet DB
and saves account display/connection metadata locally. The first account may be
Ledger-backed; additional imports may use another index or another seed. No
seed or spending key is exported, and no mnemonic is written for the account.
A UFVK reveals wallet activity and must still be treated as sensitive.

`ledgerAccountSetupProvider` owns the first-account password transaction:
prepare the password, import the account, then commit it. An import failure
rolls back the prepared password; additional accounts skip password setup.
UI callers later own router-refresh suspension and navigation around this action.

- Account indexes are `0..2147483647`, selecting shielded
  `m/32'/133'/account'` and transparent `m/44'/133'/account'` paths.
- A duplicate UFVK is rejected. Equal indexes on different seeds are allowed.
  The service's duplicate check is a convenience; DB import is authoritative.
- The signer kind, birthday and derivation index are restored from Rust. Local
  metadata retains the profile picture and device/connection display hints.
- Rename preserves the account's signer and derivation metadata.
- Device model/name/ID and transport hints are neither seed identity nor proof
  that a connected Ledger can sign for the account.

## Signer identity and operation support

Hardware custody and signing protocol are separate contracts. `isHardware`
means the wallet does not hold the account's software spending key. It remains
appropriate for seed access, UFVK receive-address derivation and hardware
transaction bookkeeping; it must not select a Keystone QR flow.

`AccountInfo.signerKind` identifies software, Keystone or Ledger independently
of which operations this build supports. The common account-signing policy
selects a supported backend for a specific operation. In C02, software and
Keystone signing remain available; Ledger signing produces an explicit
unsupported-operation error. Adding a later Ledger signer must enable only the
operations implemented by that slice, rather than enable all hardware actions.

Send, shielding, gift-card funding, outbound ZEC swaps, voting and Ironwood
migration use this policy at signing dispatch. Resumed operations use the
operation's account identity. Keystone-specific preparation boundaries also
validate their account before creating a device request, including callers
that bypass the usual screen entry point. Missing accounts cannot fall through
to software signing.

Ledger account listing, balances, receive addresses and inbound swaps remain
available. Existing Keystone metadata without an explicit signer kind retains
its deployed interpretation. No stored account schema or Ledger migration is
introduced by the dispatch refactor.

## Synthetic derivation fingerprint

The Ledger app does not return a ZIP-32 seed fingerprint. The existing source
implementation fills the 32-byte DB derivation slot with SHA-256 of
`vizor-ledger-account-fingerprint-v1\0`, the big-endian account index and the
approved UFVK. Here `\0` denotes one NUL byte.

This is account-scoped metadata, not a standard seed fingerprint, wallet
identity, authentication factor or account-grouping key. It changes across
account indexes even when their seed is the same. Duplicate detection uses the
UFVK. No wallet grouping or separate wallet fingerprint is introduced.

## Scope and limits

The existing Keystone account metadata is preserved when restoring older
wallets. Ledger is unreleased; no Ledger legacy migration is added.
Hardware-first imports can leave an Imported-only database. Current supported
migrations work with that shape, but a future migration requiring a seed may
need a recovery/re-import product flow. C02 does not solve that limitation.

This slice has no Ledger onboarding routes, BLE implementation, connection
fallback, signing, transaction planning, Wallet Link integration or broadcast.
The account service accepts exported material; C03 supplies the coordinated
connector, and the UI collection supplies the user flow. Physical device and
platform validation must be recorded separately from hardware-free tests.
