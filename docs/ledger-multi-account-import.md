# Ledger multi-account import

Status: implemented on desktop and mobile, including account-family
presentation and editable Ledger wallet names.

## Decision

Vizor will treat every Ledger ZIP-32 account index as a separate Vizor
account. Adding another account always requires the user to approve that
index's UFVK on the Ledger.

The desktop entry points are:

- a Ledger account's context menu: **Add Ledger account**;
- the Ledger account details page: **Add another Ledger account**;
- the existing **Add account > Ledger** route for a Ledger that is not yet
  represented in Vizor.

The source-account entry points open a Ledger-specific import view. It shows
the known Vizor accounts from the same Ledger wallet, suggests the lowest
unused ZIP-32 account index, and keeps manual index selection behind a
**Choose a different index** disclosure.

## Wallet identity contract

Physical device identifiers are not wallet identifiers. A Ledger reset to a
different seed must not be grouped with its previous accounts, while the same
seed restored to another Ledger should be grouped with the original accounts.

Vizor therefore derives a local-only wallet fingerprint from public BIP-44
material:

1. Ask the Zcash Ledger app for the public key and chain code at
   `m/44'/133'/0'` with `GET_PUBLIC_KEY` (`INS 0x40`, `P1 0x00`). This request
   does not display an address or require user approval.
2. Parse and validate the returned secp256k1 public key.
3. Compress the public key to its canonical 33-byte encoding.
4. Compute SHA-256 over
   `vizor-ledger-wallet-fingerprint-v1\0 || compressed_pubkey || chain_code`.
5. Persist the lowercase hex digest on each imported Ledger account.

The fingerprint never leaves the local wallet metadata and does not grant
viewing or spending authority.

There is no legacy enrollment or fingerprint backfill. A Ledger account must
be imported through this contract from the start. An older local Ledger
account without a fingerprint must be removed and imported again before it can
join a Ledger wallet group or serve as the source for adding another index.

Protocol references:

- [Zcash app APDU: get wallet public key](https://github.com/LedgerHQ/app-zcash/blob/0e048bbf1731fac2b9fcd7c5541df6222fd1cb62/docs/APDU.md#L64-L83)
- [Zcash app handler: no-display request](https://github.com/LedgerHQ/app-zcash/blob/0e048bbf1731fac2b9fcd7c5541df6222fd1cb62/src/handlers/get_public_key.rs#L49-L94)

## Data and validation rules

Each Ledger `AccountInfo` stores `ledgerWalletFingerprint` in addition to its
existing ZIP-32 account index and connection metadata. It also stores the
optional `ledgerWalletName`; renaming a group writes the same name to every
local account with that fingerprint.

- Accounts are grouped only when their non-null wallet fingerprints match.
- An account without a fingerprint is shown by itself and is never enrolled by
  a recovery path.
- The selected index must be in `0..2147483647`.
- An index already used by the same wallet fingerprint is blocked inline.
- The same index is valid for a different Ledger wallet.
- The suggested index is the lowest non-negative integer not used by the
  selected Ledger wallet.
- Vizor re-checks the source wallet identity after connecting and before the
  UFVK approval request.
- Rust's existing UFVK import remains the final duplicate-account guard.

## Desktop flow

1. The user enters from an existing Ledger account or the general add-account
   route.
2. Vizor shows the known same-wallet accounts when a source account exists.
3. Vizor preselects the lowest unused index. A different index can be entered
   after expanding the disclosure.
4. Vizor checks that the Zcash app is open, reads the no-display wallet
   identity, and requires an exact fingerprint match when a source account is
   present.
5. Vizor requests the target index's UFVK. The Ledger approval screen remains
   the source of truth for what is shared.
6. The existing birthday-height and account-name steps continue unchanged.
7. Import persists the wallet fingerprint on the new account.

USB and macOS Bluetooth use the same Rust APDU plan and parser. Native BLE code
continues to own only discovery, connection, and byte exchange.

## Mobile flow

Mobile reuses the same wallet identity, source fingerprint check, index
suggestion, and duplicate rules over the selected BLE session. The Account details action
opens the source-account flow; the general Ledger import remains index 0 with
manual selection behind **Advanced options**. The source account context is
preserved through birthday height, passcode setup when required, and account
customisation.

## UI states and copy

- Empty/general state: the current Connect Ledger screen and advanced index
  option remain available.
- Known accounts: show account name and `Index N`; long names truncate.
- Invalid range: `Account index must be between 0 and 2147483647.`
- Same-wallet duplicate: `Index N is already used by this Ledger wallet.`
- Wrong wallet: `This Ledger does not match the account you started from.`
- Busy state: inputs and disclosures are disabled, the button retains the
  current readiness label, and the spinner stays on the right.
- Rejection or disconnect preserves the chosen index for retry.

## Scope

Included in the current implementation:

- wallet identity APDU and strict response parsing;
- USB and macOS BLE identity exchange;
- required fingerprint persistence on every new Ledger import;
- same-wallet account list, index suggestion, and duplicate validation;
- same-wallet account grouping and editable group names on desktop and mobile;
- Accounts context-menu and Account details entry points;
- mobile Account details entry point and single-column account-index flow;
- focused Rust, provider, model, and widget tests.

Follow-up:

- run the final BLE identity and UFVK sequence on physical iOS and Android
  devices.

Out of scope:

- scanning arbitrary account indexes for balances or transaction history;
- deriving or importing a UFVK without an explicit Ledger approval;
- receive-address verification on the device;
- private migration support for Ledger;
- using BLE device IDs as wallet identity.

## Acceptance criteria

- Starting from Ledger index 0 suggests index 1 when no other same-wallet
  account is known.
- Known indexes 0, 1, and 3 suggest index 2.
- A known same-wallet duplicate is rejected before device interaction.
- The same index on a different wallet fingerprint is allowed.
- A wrong Ledger connected from a source-account flow is rejected before the
  target UFVK approval.
- A source account without a fingerprint cannot pass the same-wallet identity
  gate; its add-account entry points are hidden until it is removed and
  imported again.
- A successful import always stores the connected wallet fingerprint on the
  new account.
- Accounts with the same fingerprint render as one group, and a renamed group
  name persists across every member account.
- General Ledger import still defaults to index 0 and keeps index selection
  under Advanced options.
- USB and macOS BLE produce the same fingerprint for the same seed.
- Mobile source-account import follows the same identity and duplicate gates.

## Estimate

Engineering estimates include implementation, focused automated tests, and
one device/simulator QA pass. They do not include Ledger app firmware changes.

| Work | Estimate |
| --- | ---: |
| Rust identity APDU, parser, fingerprint, USB/BLE bridge | 0.5-0.75 day |
| Account metadata persistence and strict identity contract | 0.5 day |
| Desktop import UI, routing, and duplicate handling | 0.75-1.25 days |
| Context menu and Account details entry points | 0.25 day |
| Focused tests and Ledger/Speculos desktop QA | 0.5-0.75 day |
| **Desktop total** | **2.5-3.5 engineer-days** |
| Mobile follow-up and mobile QA | 1.0-1.5 days |
| **Desktop + mobile total** | **3.5-5.0 engineer-days** |

The main schedule risk is wallet-identity stability across Zcash app versions
and real Ledger models. Canonical public-key compression keeps equivalent key
encodings stable, but each app version still needs protocol regression
coverage.

## Validation plan

- Rust unit tests for APDU bytes, strict response lengths/status, public-key
  validation, and canonical fingerprint stability.
- Dart unit tests for grouping, lowest-unused suggestion, and JSON persistence.
- Widget tests for the source-account list, disclosure, duplicate error,
  wrong-device stop, USB continuation, and Bluetooth continuation.
- Focused desktop and mobile build/analyze for changed files.
- Visible mobile simulator review with deterministic same-wallet accounts.
- Visible desktop smoke test with a real Ledger before declaring the UI flow
  complete.
