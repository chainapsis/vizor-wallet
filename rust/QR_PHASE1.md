# ZIP-2005 QR Orchard Phase 1

This branch enables ZIP-2005 Phase 1 QR Orchard internal outputs for Vizor
software wallets on testnet and regtest only.

## Dependency refs

- `zcash_client_backend`, `zcash_client_sqlite`, `zcash_primitives`,
  `zcash_keys`, `zcash_protocol`, `zcash_proofs`, `zcash_transparent`, and
  `pczt` are pinned to `valargroup/librustzcash` at:
  `d39cbbea0323bbba6ad477e36b604025c4dbbf6f`
- That ref is based on the librustzcash QR branch whose reviewed head was:
  `ccdb50eeb0271483659fe580110af30906a66dda`
- `orchard` is pinned to `valargroup/qr_orchard` at:
  `9f046f22a46dd644aeed070968e51add57478973`
- The reviewed Orchard QR branch head was:
  `52da377f23e63407f7ca9c1c623aadd8429dc221`

The librustzcash dependency ref is a Vizor Stage 1 validation branch. No
upstream PR, issue, review, or discussion comment has been opened for that
branch.

## Persistence checkpoint

The initial QR dependency branch could parse QR Orchard notes, but
`zcash_client_sqlite` still reconstructed persisted Orchard notes with
`Note::from_parts`, which defaults to ordinary V2 notes. That would make a QR
note parse during scan but be reconstructed incorrectly after restart.

The pinned `valargroup/librustzcash` ref fixes this in
`zcash_client_sqlite`:

- `zcash_client_sqlite/src/wallet/db.rs` adds
  `orchard_received_notes.note_version INTEGER NOT NULL DEFAULT 2`.
- `zcash_client_sqlite/src/wallet/init/migrations/orchard_note_versions.rs`
  adds the same column for existing wallet databases.
- `zcash_client_sqlite/src/wallet/orchard.rs` stores
  `output.note().version()` when inserting or updating received Orchard notes.
- Orchard note queries now select `note_version` in reconstruction paths.
- Orchard note reconstruction uses `Note::from_parts_with_version`.

This satisfies the Phase 1 persistence checkpoint for the selected dependency
set. The selected ref also fixes a SQL alias issue found by the Vizor live test
while selecting spendable Orchard notes after the persistence patch.

## Vizor policy

- Software sends on `WalletNetwork::Test` and `WalletNetwork::Regtest` pass
  `Some(TxVersion::V5_Qr)` into librustzcash proposal and transaction
  construction.
- Software sends on `WalletNetwork::Main` pass `Some(TxVersion::V5)`.
- Software transparent shielding follows the same software policy. On testnet
  and regtest, its internal Orchard output is QR.
- Keystone send PCZT construction remains ordinary V5/default.
- Hardware transparent shielding PCZT construction remains ordinary V5/default.
- External Orchard recipient outputs remain ordinary V2. The QR selector is
  only used for internal wallet outputs handled by librustzcash.
- No Flutter Rust Bridge API files changed, so bindings were not regenerated.
- No UI, setting, banner, or opt-in flow was added.

## Tests

Focused local checks:

```bash
cd rust
cargo test software_
cargo test funded_testnet_seed_can_create_reopen_and_spend_qr_change --no-run
```

The `software_shielding_internal_output_is_qr_on_regtest` unit test builds a
regtest software shielding transaction with the QR policy and asserts the
stored internal Orchard note has `note_version = 3`.

The ignored live test imports the provided funded testnet seed into a temporary
wallet DB, creates a temporary receiver wallet, sends a small amount to force
QR change, waits for the first transaction to mine, reopens through normal API
calls, spends the QR change in a second transaction, and verifies external
recipient notes stayed V2. It accepts both transaction display byte order and
wallet DB byte order when matching mined history rows.

The companion ignored test `existing_testnet_db_can_spend_qr_change` can finish
validation from an existing temporary sender DB that already contains unspent QR
change:

```bash
cd rust
VIZOR_QR_TESTNET_LIVE=1 \
VIZOR_QR_TESTNET_EXISTING_SENDER_DB=/path/to/zcash_wallet.db \
VIZOR_QR_TESTNET_CONFIRM_TIMEOUT_SECS=3600 \
VIZOR_QR_TESTNET_CONFIRM_POLL_SECS=75 \
cargo test --test testnet_qr_phase1 existing_testnet_db_can_spend_qr_change -- --ignored --nocapture
```

Live testnet validation completed against `https://testnet.zec.rocks:443`:

- Existing DB QR spend:
  `e016f41a1b1a2b534c5c103ca83d75e12a798967a747cd8728ad7b82f8429895`
  mined at height `4028555`.
- Full funded-seed run first send:
  `3d66e4f88acb5aaef4f520c23a2ab9554e460c7b42ec526d2a9bc55dfdb65bbf`
  mined at height `4028558`.
- Full funded-seed run second QR-change spend:
  `b23db05262a14d5b8524e18e65861ca7d178682a8e122c390ba5ed4730783564`
  mined at height `4028561`.

Run the live test explicitly:

```bash
cd rust
VIZOR_QR_TESTNET_LIVE=1 \
VIZOR_QR_TESTNET_ARTIFACT_DIR=target/qr-phase1-live/known-accounts-latest \
VIZOR_QR_TESTNET_CONFIRM_TIMEOUT_SECS=3600 \
VIZOR_QR_TESTNET_CONFIRM_POLL_SECS=75 \
cargo test --test testnet_qr_phase1 -- --ignored --nocapture
```

Optional endpoint override:

```bash
VIZOR_QR_TESTNET_LIGHTWALLETD_URL=https://testnet.zec.rocks:443
```

Testnet validation seed:

```text
powder bronze skirt because truly bonus link gloom cluster quantum birth mutual limit veteran garden almost trophy potato twelve win crush surface decline uphold
```

Birthday height: `4000000`.

Known Account A/B live validation completed against
`https://testnet.zec.rocks:443`:

- Account A -> Account B send, creating Account A QR change and funding the
  Account B spend:
  `f0250cb22adc07fc56c9c273654bb2978c41780abfe400b4871221f8cc5accb8`
  mined at height `4028955`.
- Follow-up Account A -> Account B send during the artifact run, also creating
  Account A QR change:
  `4210b0f959b7e519eaabec412bac8838fb5a119bdf1b397d1f0cb17c8e9bfffd`
  mined at height `4028964`.
- Account B -> Account A send, creating Account B QR change:
  `373f2e36c83178ad70c8d9bf67a7de333fc42f6dd5f4583249bcc5b3ce0e6446`
  mined at height `4028969`.
- The saved artifact DBs from this run are written under
  `rust/target/qr-phase1-live/known-accounts-latest/`.

Inspect note versions in the saved DBs:

```bash
sqlite3 -header -column target/qr-phase1-live/known-accounts-latest/account-a.db \
  "SELECT rn.id, lower(hex(t.txid)) AS txid_db_order, rn.action_index,
          rn.value, rn.note_version, rn.is_change,
          CASE WHEN s.transaction_id IS NULL THEN 0 ELSE 1 END AS spent,
          IFNULL(t.mined_height, 0) AS mined_height
   FROM orchard_received_notes rn
   JOIN transactions t ON t.id_tx = rn.transaction_id
   LEFT JOIN orchard_received_note_spends s ON s.orchard_received_note_id = rn.id
   ORDER BY rn.id;"

sqlite3 -header -column target/qr-phase1-live/known-accounts-latest/account-b.db \
  "SELECT rn.id, lower(hex(t.txid)) AS txid_db_order, rn.action_index,
          rn.value, rn.note_version, rn.is_change,
          CASE WHEN s.transaction_id IS NULL THEN 0 ELSE 1 END AS spent,
          IFNULL(t.mined_height, 0) AS mined_height
   FROM orchard_received_notes rn
   JOIN transactions t ON t.id_tx = rn.transaction_id
   LEFT JOIN orchard_received_note_spends s ON s.orchard_received_note_id = rn.id
   ORDER BY rn.id;"
```

## Validation checklist

Run from the repo root unless noted:

```bash
cd rust && cargo check
cd rust && cargo test
cd rust && cargo tree -d
cd rust && cargo tree -i orchard
cd rust && cargo tree -i zcash_client_backend
cd rust && cargo tree -i zcash_client_sqlite
cd rust && cargo tree -i zcash_primitives
fvm flutter analyze
fvm flutter test
fvm flutter build macos --release --dart-define=ZCASH_DEFAULT_NETWORK=test
```

The macOS release build command is locally blocked by Xcode signing
configuration:

```text
"Runner" requires a provisioning profile.
```
