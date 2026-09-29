//! Upgrade probe: `create` builds a wallet with a base build, `verify` upgrades
//! it with the current build, and `open-old` reopens the upgraded wallet with
//! the base build. Driven by `scripts/test-db-upgrade.sh`, which compiles this
//! file in both trees; checks after `create` use raw SQL only.

use std::{collections::BTreeSet, fs, path::Path};

use rust_lib_zcash_wallet::api::wallet;
use serde::{Deserialize, Serialize};

#[path = "db_upgrade/compat.rs"]
mod compat;

const NETWORK: &str = "regtest";
const PRIMARY_MNEMONIC: &str = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art";
const SECONDARY_MNEMONIC: &str =
    "legal winner thank year wave sausage worth useful legal winner thank yellow";
/// Regtest UFVK of `SECONDARY_MNEMONIC` account 0, imported without its seed.
const HARDWARE_UFVK: &str = "uviewregtest1wc0v5cry88thqcarv52wll3a3kape7g3y4n3z938ul89jlnmclly56cttcg6cdat62m4nhcwn6vdsyf3g3ljkkd8fffk323l0qcy9ug8fsfxhexu737hckrvw6xgrz7dtepexaye25qdw02wys0l9h8kpes6wtge7ha6gu2c4jz75a4hrtzzt2ydympf2jjdg6hea687d2upfwf8ld6vdd46pxcylypkd8pdl3wt2jz4s0gjfu0swvzlzqm09nrjwj3uuf97yyvlrpx44stwlp6d9ak6sydqvyfp49a86khgzugrqkfm0l4qam995v56wt8c5k5pjlt947mazufsrkanv9y5atnh5tfh52nq30kjac97e6r2rcx25q8pl4p4uprqt60u3j2kedzev3acdr7ha5tg6gaejsjpmrtutyhstc7ssppwxga7cqd2r2fmlzp52ysaky97xznl23xtv36w2g3am9k42xy69qw3xz4pw6mussp6sg3l";

/// A transparent output discovered from the chain, later spent by `LOCAL_TXID`.
const REMOTE_TXID: [u8; 32] = [0x11; 32];
/// A locally created send: carries creation evidence and its own change output.
const LOCAL_TXID: [u8; 32] = [0x22; 32];
const REMOTE_VALUE_ZAT: i64 = 50_000_000;
const LOCAL_CHANGE_ZAT: i64 = 49_990_000;

/// Migrations the current build adds that no supported base has applied: the
/// ZIP 318 schema drop and the transparent ledger schema. Older bases also
/// pick up earlier upstream migrations.
const NEW_MIGRATIONS: [&str; 2] = [
    "772a06323d0e4dffb1f8c64863eefaaa",
    "8f290af0eb5a4f1e88d43550fc0ff911",
];
const LEGACY_PUBLIC_ORIGIN: i64 = 0;
const LOCAL_ORIGIN: i64 = 1;

#[derive(Debug, Deserialize, PartialEq, Serialize)]
struct LegacyState {
    scenario: String,
    migration_ids: BTreeSet<String>,
    accounts: Vec<AccountRow>,
    addresses: Vec<AddressRow>,
    scan_queue: Vec<ScanRangeRow>,
    transaction_count: i64,
    sapling_note_count: i64,
    orchard_note_count: i64,
    transparent_output_count: i64,
    transparent_unspent_zat: i64,
    /// `None` when the base schema has no transparent lock columns.
    locked_transparent_outputs: Option<i64>,
}

#[derive(Debug, Deserialize, PartialEq, Serialize)]
struct AccountRow {
    uuid_hex: String,
    account_kind: i64,
    name: Option<String>,
    birthday_height: i64,
    has_ufvk: bool,
}

#[derive(Debug, Deserialize, PartialEq, Serialize)]
struct AddressRow {
    account_uuid_hex: String,
    diversifier_index_be_hex: String,
    address: Option<String>,
    cached_transparent_receiver_address: Option<String>,
    key_scope: i64,
    transparent_child_index: Option<i64>,
}

#[derive(Debug, Deserialize, PartialEq, Serialize)]
struct ScanRangeRow {
    start: i64,
    end: i64,
    priority: i64,
}

fn main() {
    let mut args = std::env::args().skip(1);
    let mode = args.next().expect(
        "usage: db_upgrade \
             <create|verify|open-old> <scenario> <db> <manifest>",
    );
    let scenario = args.next().expect("scenario");
    let db_path = args.next().expect("database path");
    let manifest_path = args.next().expect("manifest path");

    match mode.as_str() {
        "create" => create_fixture(&scenario, &db_path, &manifest_path),
        "verify" => verify_upgraded(&scenario, &db_path, &manifest_path),
        "open-old" => verify_old_reopen(&scenario, &db_path, &manifest_path),
        other => panic!("unknown mode {other}"),
    }
}

fn create_fixture(scenario: &str, db_path: &str, manifest_path: &str) {
    assert!(
        !Path::new(db_path).exists(),
        "fixture DB already exists: {db_path}"
    );

    if scenario == "hardware-first" {
        // No seed ever reaches this wallet: account creation and migration are seedless.
        compat::import_hardware_account(
            db_path,
            NETWORK,
            "Hardware",
            HARDWARE_UFVK,
            vec![0x5a; 32],
        );
    } else {
        create_software_accounts(scenario, db_path);
    }

    insert_transparent_fixture(db_path);
    let state = read_legacy_state(db_path, scenario);
    assert_scenario_shape(&state);
    insert_pool_migration_row(db_path);
    assert_sqlite_health(db_path);
    fs::write(
        manifest_path,
        serde_json::to_vec_pretty(&state).expect("encode manifest"),
    )
    .expect("write manifest");
    println!(
        "created scenario={} accounts={} migrations={}",
        state.scenario,
        state.accounts.len(),
        state.migration_ids.len()
    );
}

fn create_software_accounts(scenario: &str, db_path: &str) {
    let primary = compat::import_wallet(PRIMARY_MNEMONIC, NETWORK, db_path, "Primary");

    match scenario {
        "single-derived" => {}
        "multi-seed" | "imported-only" => {
            compat::add_account(db_path, NETWORK, "Secondary", SECONDARY_MNEMONIC);
            if scenario == "imported-only" {
                wallet::delete_account(db_path.to_string(), NETWORK.to_string(), primary)
                    .expect("delete primary derived account");
            }
        }
        other => panic!("unknown fixture scenario {other}"),
    }
}

/// Inserts a remote transparent receive and a local send spending it, as the
/// base build would have stored them. The local send keeps a change output,
/// locked when the base schema supports transparent locks.
fn insert_transparent_fixture(db_path: &str) {
    let conn = rusqlite::Connection::open(db_path).expect("open base DB");
    let (address_id, account_id, address): (i64, i64, String) = conn
        .query_row(
            "SELECT id, account_id, cached_transparent_receiver_address
             FROM addresses
             WHERE cached_transparent_receiver_address IS NOT NULL
             ORDER BY id LIMIT 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("fixture account has a transparent receiver");
    let script: Vec<u8> = [&[0x76, 0xa9, 0x14][..], &[0; 20], &[0x88, 0xac]].concat();
    let tx = conn.unchecked_transaction().expect("begin fixture");
    tx.execute(
        "INSERT INTO transactions (txid, mined_height, min_observed_height)
         VALUES (?1, 10, 10)",
        [&REMOTE_TXID[..]],
    )
    .expect("insert remote transaction");
    let remote_tx = tx.last_insert_rowid();
    tx.execute(
        "INSERT INTO transactions (txid, created, target_height, expiry_height, min_observed_height)
         VALUES (?1, '2026-01-01 00:00:00', 12, 52, 11)",
        [&LOCAL_TXID[..]],
    )
    .expect("insert local send");
    let local_tx = tx.last_insert_rowid();
    let insert_output = |transaction_id: i64, output_index: i64, value: i64| {
        tx.execute(
            "INSERT INTO transparent_received_outputs (
                 transaction_id, output_index, account_id, address, script, value_zat,
                 max_observed_unspent_height, address_id
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, 10, ?7)",
            rusqlite::params![
                transaction_id,
                output_index,
                account_id,
                address,
                script,
                value,
                address_id
            ],
        )
        .expect("insert transparent output");
        tx.last_insert_rowid()
    };
    let remote_output = insert_output(remote_tx, 0, REMOTE_VALUE_ZAT);
    let local_change = insert_output(local_tx, 1, LOCAL_CHANGE_ZAT);
    tx.execute(
        "INSERT INTO transparent_received_output_spends (
             transparent_received_output_id, transaction_id
         ) VALUES (?1, ?2)",
        [remote_output, local_tx],
    )
    .expect("insert local spend");
    if column_exists(&tx, "transparent_received_outputs", "lock_owner") {
        tx.execute(
            "UPDATE transparent_received_outputs
             SET lock_owner = X'01', lock_expiry_height = 52
             WHERE id = ?1",
            [local_change],
        )
        .expect("lock local change");
    }
    tx.commit().expect("commit fixture");
}

/// Leaves a row in the ZIP 318 pool-migration table the current build drops,
/// so the drop is exercised on a non-empty table.
fn insert_pool_migration_row(db_path: &str) {
    let conn = rusqlite::Connection::open(db_path).expect("open base DB");
    if !object_exists(&conn, "table", "orchard_ironwood_migrations") {
        return;
    }
    conn.execute(
        "INSERT INTO orchard_ironwood_migrations (
             account_id, status, note_split_fee_buffer, note_split_change,
             note_split_prep_fees, note_split_total_input,
             note_split_total_migratable
         ) VALUES (
             (SELECT id FROM accounts ORDER BY id LIMIT 1),
             'committed', 0, NULL, 0, 0, 0
         )",
        [],
    )
    .expect("insert representative in-flight pool migration");
}

fn verify_upgraded(scenario: &str, db_path: &str, manifest_path: &str) {
    let expected = read_manifest(manifest_path);
    assert_eq!(expected.scenario, scenario);

    let accounts = wallet::list_accounts(db_path.to_string(), NETWORK.to_string())
        .expect("open and migrate wallet");
    assert_eq!(accounts.len(), expected.accounts.len());

    let actual = read_legacy_state(db_path, scenario);
    assert_eq!(
        actual.accounts, expected.accounts,
        "account rows changed during upgrade"
    );
    assert_eq!(
        actual.addresses, expected.addresses,
        "address rows changed during upgrade"
    );
    assert_eq!(
        actual.scan_queue, expected.scan_queue,
        "scan queue changed below the disabled regtest Ironwood activation"
    );
    assert_eq!(actual.transaction_count, expected.transaction_count);
    assert_eq!(actual.sapling_note_count, expected.sapling_note_count);
    assert_eq!(actual.orchard_note_count, expected.orchard_note_count);
    assert_eq!(
        actual.transparent_output_count,
        expected.transparent_output_count
    );
    assert_eq!(
        actual.transparent_unspent_zat, expected.transparent_unspent_zat,
        "transparent balance changed during upgrade"
    );
    if let Some(locked) = expected.locked_transparent_outputs {
        assert_eq!(actual.locked_transparent_outputs, Some(locked));
    }
    assert!(
        expected.migration_ids.is_subset(&actual.migration_ids),
        "upgrade lost applied migrations"
    );
    for id in NEW_MIGRATIONS {
        assert!(
            !expected.migration_ids.contains(id) && actual.migration_ids.contains(id),
            "migration {id} was not newly applied"
        );
    }

    assert_current_schema(db_path);
    assert_transparent_ledger(db_path);
    assert_sqlite_health(db_path);
    println!(
        "verified scenario={} accounts={} migrations={} integrity=ok",
        scenario,
        actual.accounts.len(),
        actual.migration_ids.len()
    );
}

/// The ledger starts public (generation 0, reader version 1), and every
/// transparent record carries legacy-public provenance, plus local provenance
/// where the wallet created the transaction. Neither is private coverage.
fn assert_transparent_ledger(db_path: &str) {
    let conn = rusqlite::Connection::open(db_path).expect("open upgraded DB");
    for table in ["tpir_meta", "tpir_output_origins", "tpir_spend_origins"] {
        assert!(object_exists(&conn, "table", table), "missing {table}");
    }
    let meta: (i64, i64, i64) = conn
        .query_row(
            "SELECT applied_mode, policy_generation, min_reader_version FROM tpir_meta",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("read tpir_meta");
    assert_eq!(meta, (0, 0, 1), "transparent ledger policy is not public");
    assert_eq!(
        scalar_i64(
            &conn,
            "SELECT COUNT(*) FROM transparent_received_outputs o
             WHERE NOT EXISTS (
                 SELECT 1 FROM tpir_output_origins r
                 WHERE r.output_id = o.id AND r.origin = 0
             )",
        ),
        0,
        "transparent output without legacy provenance"
    );
    let output_origins = |txid: &[u8]| {
        origins(
            &conn,
            "SELECT r.origin FROM tpir_output_origins r
             JOIN transparent_received_outputs o ON o.id = r.output_id
             JOIN transactions t ON t.id_tx = o.transaction_id
             WHERE t.txid = ?1",
            txid,
        )
    };
    assert_eq!(output_origins(&REMOTE_TXID), vec![LEGACY_PUBLIC_ORIGIN]);
    assert_eq!(
        output_origins(&LOCAL_TXID),
        vec![LEGACY_PUBLIC_ORIGIN, LOCAL_ORIGIN]
    );
    let spend_origins = origins(
        &conn,
        "SELECT r.origin FROM tpir_spend_origins r
         JOIN transactions t ON t.id_tx = r.spending_transaction_id
         WHERE t.txid = ?1",
        &LOCAL_TXID,
    );
    assert_eq!(spend_origins, vec![LEGACY_PUBLIC_ORIGIN, LOCAL_ORIGIN]);
    assert_eq!(
        scalar_i64(&conn, "SELECT COUNT(*) FROM tpir_spend_origins"),
        2,
        "unexpected transparent spend provenance"
    );
}

fn origins(conn: &rusqlite::Connection, sql: &str, txid: &[u8]) -> Vec<i64> {
    let mut origins = conn
        .prepare(sql)
        .expect("prepare origins")
        .query_map([txid], |row| row.get(0))
        .expect("query origins")
        .collect::<Result<Vec<i64>, _>>()
        .expect("read origins");
    origins.sort();
    origins
}

fn verify_old_reopen(scenario: &str, db_path: &str, manifest_path: &str) {
    let expected = read_manifest(manifest_path);
    assert_eq!(expected.scenario, scenario);

    let accounts = wallet::list_accounts(db_path.to_string(), NETWORK.to_string())
        .expect("old build reopens upgraded pre-Ironwood wallet");
    assert_eq!(accounts.len(), expected.accounts.len());

    let actual = read_legacy_state(db_path, scenario);
    assert_eq!(actual.accounts, expected.accounts);
    assert_eq!(actual.addresses, expected.addresses);
    assert_eq!(actual.transaction_count, expected.transaction_count);
    assert_eq!(actual.sapling_note_count, expected.sapling_note_count);
    assert_eq!(actual.orchard_note_count, expected.orchard_note_count);
    assert_sqlite_health(db_path);
    println!(
        "old-reopen scenario={} accounts={} migrations={} integrity=ok",
        scenario,
        actual.accounts.len(),
        actual.migration_ids.len()
    );
}

fn read_manifest(path: &str) -> LegacyState {
    serde_json::from_slice(&fs::read(path).expect("read manifest")).expect("decode manifest")
}

fn read_legacy_state(db_path: &str, scenario: &str) -> LegacyState {
    let conn = rusqlite::Connection::open(db_path).expect("open wallet DB");

    let accounts = conn
        .prepare(
            "SELECT hex(uuid), account_kind, name, birthday_height, ufvk IS NOT NULL
             FROM accounts ORDER BY id",
        )
        .expect("prepare accounts")
        .query_map([], |row| {
            Ok(AccountRow {
                uuid_hex: row.get(0)?,
                account_kind: row.get(1)?,
                name: row.get(2)?,
                birthday_height: row.get(3)?,
                has_ufvk: row.get(4)?,
            })
        })
        .expect("query accounts")
        .collect::<Result<Vec<_>, _>>()
        .expect("read accounts");

    let addresses = conn
        .prepare(
            "SELECT hex(accounts.uuid), hex(addresses.diversifier_index_be),
                    addresses.address, addresses.cached_transparent_receiver_address,
                    addresses.key_scope, addresses.transparent_child_index
             FROM addresses
             JOIN accounts ON accounts.id = addresses.account_id
             ORDER BY accounts.id, addresses.id",
        )
        .expect("prepare addresses")
        .query_map([], |row| {
            Ok(AddressRow {
                account_uuid_hex: row.get(0)?,
                diversifier_index_be_hex: row.get(1)?,
                address: row.get(2)?,
                cached_transparent_receiver_address: row.get(3)?,
                key_scope: row.get(4)?,
                transparent_child_index: row.get(5)?,
            })
        })
        .expect("query addresses")
        .collect::<Result<Vec<_>, _>>()
        .expect("read addresses");

    let scan_queue = conn
        .prepare(
            "SELECT block_range_start, block_range_end, priority
             FROM scan_queue ORDER BY block_range_start",
        )
        .expect("prepare scan queue")
        .query_map([], |row| {
            Ok(ScanRangeRow {
                start: row.get(0)?,
                end: row.get(1)?,
                priority: row.get(2)?,
            })
        })
        .expect("query scan queue")
        .collect::<Result<Vec<_>, _>>()
        .expect("read scan queue");

    let migration_ids = conn
        .prepare(
            "SELECT CASE typeof(id) WHEN 'blob' THEN lower(hex(id))
                    ELSE lower(replace(id, '-', '')) END
             FROM schemer_migrations",
        )
        .expect("prepare migrations")
        .query_map([], |row| row.get(0))
        .expect("query migrations")
        .collect::<Result<BTreeSet<String>, _>>()
        .expect("read migrations");

    LegacyState {
        scenario: scenario.to_string(),
        migration_ids,
        accounts,
        addresses,
        scan_queue,
        transaction_count: scalar_i64(&conn, "SELECT COUNT(*) FROM transactions"),
        sapling_note_count: scalar_i64(&conn, "SELECT COUNT(*) FROM sapling_received_notes"),
        orchard_note_count: scalar_i64(&conn, "SELECT COUNT(*) FROM orchard_received_notes"),
        transparent_output_count: scalar_i64(
            &conn,
            "SELECT COUNT(*) FROM transparent_received_outputs",
        ),
        transparent_unspent_zat: scalar_i64(
            &conn,
            "SELECT COALESCE(SUM(value_zat), 0) FROM transparent_received_outputs o
             WHERE NOT EXISTS (
                 SELECT 1 FROM transparent_received_output_spends s
                 WHERE s.transparent_received_output_id = o.id
             )",
        ),
        locked_transparent_outputs: column_exists(
            &conn,
            "transparent_received_outputs",
            "lock_owner",
        )
        .then(|| {
            scalar_i64(
                &conn,
                "SELECT COUNT(*) FROM transparent_received_outputs WHERE lock_owner IS NOT NULL",
            )
        }),
    }
}

fn assert_scenario_shape(state: &LegacyState) {
    match state.scenario.as_str() {
        "single-derived" => {
            assert_eq!(state.accounts.len(), 1);
            assert_eq!(state.accounts[0].account_kind, 0);
        }
        "multi-seed" => {
            assert_eq!(state.accounts.len(), 2);
            assert_eq!(state.accounts[0].account_kind, 0);
            assert_eq!(state.accounts[1].account_kind, 1);
        }
        "imported-only" | "hardware-first" => {
            assert_eq!(state.accounts.len(), 1);
            assert_eq!(state.accounts[0].account_kind, 1);
        }
        other => panic!("unknown scenario {other}"),
    }
}

fn assert_current_schema(db_path: &str) {
    let conn = rusqlite::Connection::open(db_path).expect("open upgraded DB");
    for table in [
        "ironwood_received_notes",
        "ironwood_received_note_spends",
        "ironwood_tree_shards",
        "ironwood_tree_cap",
        "ironwood_tree_checkpoints",
        "ironwood_tree_checkpoint_marks_removed",
        "ironwood_tree_retained_checkpoints",
        "orchard_tree_retained_checkpoints",
        "sapling_tree_retained_checkpoints",
    ] {
        assert!(
            object_exists(&conn, "table", table),
            "missing upgraded table {table}"
        );
    }
    for view in [
        "v_ironwood_shard_scan_ranges",
        "v_ironwood_shard_unscanned_ranges",
        "v_ironwood_shards_scan_state",
    ] {
        assert!(
            object_exists(&conn, "view", view),
            "missing upgraded view {view}"
        );
    }
    for (table, column) in [
        ("orchard_received_notes", "note_version"),
        ("sapling_received_notes", "lock_expiry_height"),
        ("sapling_received_notes", "lock_owner"),
        ("orchard_received_notes", "lock_expiry_height"),
        ("orchard_received_notes", "lock_owner"),
        ("ironwood_received_notes", "lock_expiry_height"),
        ("ironwood_received_notes", "lock_owner"),
        ("transparent_received_outputs", "lock_expiry_height"),
        ("transparent_received_outputs", "lock_owner"),
        ("blocks", "ironwood_commitment_tree_size"),
        ("blocks", "ironwood_action_count"),
    ] {
        assert!(
            column_exists(&conn, table, column),
            "missing upgraded column {table}.{column}"
        );
    }
    // The ZIP 318 pool-migration engine's schema is dropped.
    assert_eq!(
        scalar_i64(
            &conn,
            "SELECT COUNT(*) FROM sqlite_master WHERE name LIKE 'orchard_ironwood_migration%'",
        ),
        0,
        "ZIP 318 pool-migration schema survived the upgrade"
    );
    assert!(!column_exists(&conn, "transactions", "zip318_kind"));
    assert!(
        object_exists(
            &conn,
            "index",
            "idx_addresses_cached_transparent_receiver_address"
        ),
        "missing transparent receiver unique index"
    );
}

fn assert_sqlite_health(db_path: &str) {
    let conn = rusqlite::Connection::open(db_path).expect("open DB for health check");
    let integrity: String = conn
        .query_row("PRAGMA integrity_check", [], |row| row.get(0))
        .expect("integrity_check");
    assert_eq!(integrity, "ok");
    assert_eq!(
        scalar_i64(&conn, "SELECT COUNT(*) FROM pragma_foreign_key_check"),
        0,
        "foreign key violations"
    );
}

fn scalar_i64(conn: &rusqlite::Connection, sql: &str) -> i64 {
    conn.query_row(sql, [], |row| row.get(0))
        .unwrap_or_else(|error| panic!("query failed ({sql}): {error}"))
}

fn object_exists(conn: &rusqlite::Connection, kind: &str, name: &str) -> bool {
    conn.query_row(
        "SELECT EXISTS(
             SELECT 1 FROM sqlite_master WHERE type = ?1 AND name = ?2
         )",
        [kind, name],
        |row| row.get(0),
    )
    .expect("check sqlite object")
}

fn column_exists(conn: &rusqlite::Connection, table: &str, column: &str) -> bool {
    conn.query_row(
        "SELECT EXISTS(
             SELECT 1 FROM pragma_table_info(?1) WHERE name = ?2
         )",
        [table, column],
        |row| row.get(0),
    )
    .expect("check table column")
}
