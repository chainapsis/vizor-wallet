use std::{fs, path::Path};

use rust_lib_zcash_wallet::api::wallet;
use serde::{Deserialize, Serialize};

const NETWORK: &str = "regtest";
const PRIMARY_MNEMONIC: &str = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art";
const SECONDARY_MNEMONIC: &str =
    "legal winner thank year wave sausage worth useful legal winner thank yellow";

#[derive(Debug, Deserialize, PartialEq, Serialize)]
struct LegacyState {
    scenario: String,
    migration_count: i64,
    accounts: Vec<AccountRow>,
    addresses: Vec<AddressRow>,
    scan_queue: Vec<ScanRangeRow>,
    transaction_count: i64,
    sapling_note_count: i64,
    orchard_note_count: i64,
    transparent_output_count: i64,
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
        "usage: db_upgrade_mobile_v0_0_18 \
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

    let primary = wallet::import_wallet(
        PRIMARY_MNEMONIC.to_string(),
        Some(1),
        NETWORK.to_string(),
        db_path.to_string(),
        Some("Primary".to_string()),
    )
    .expect("create primary account");

    match scenario {
        "single-derived" => {}
        "multi-seed" | "imported-only" => {
            wallet::add_account(
                db_path.to_string(),
                NETWORK.to_string(),
                "Secondary".to_string(),
                SECONDARY_MNEMONIC.to_string(),
                Some(1),
            )
            .expect("add secondary imported account");
            if scenario == "imported-only" {
                wallet::delete_account(
                    db_path.to_string(),
                    NETWORK.to_string(),
                    primary.account_uuid,
                )
                .expect("delete primary derived account");
            }
        }
        other => panic!("unknown fixture scenario {other}"),
    }

    let state = read_legacy_state(db_path, scenario);
    assert_scenario_shape(&state);
    let conn = rusqlite::Connection::open(db_path).expect("open mobile/v0.0.18 DB");
    assert!(
        object_exists(&conn, "table", "orchard_ironwood_migrations"),
        "mobile/v0.0.18 Ironwood migration table is missing"
    );
    assert!(
        !column_exists(
            &conn,
            "orchard_ironwood_migrations",
            "anchor_bucket_interval"
        ),
        "mobile/v0.0.18 fixture unexpectedly has anchor_bucket_interval"
    );
    let error = conn
        .query_row(
            "SELECT anchor_bucket_interval FROM orchard_ironwood_migrations LIMIT 1",
            [],
            |_| Ok(()),
        )
        .expect_err("current backend query must fail against the mobile/v0.0.18 schema");
    assert!(
        error.to_string().contains("no such column"),
        "unexpected mobile/v0.0.18 schema failure: {error}"
    );
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
    .expect("insert representative mobile/v0.0.18 in-flight migration");
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
        state.migration_count
    );
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
        actual.migration_count, expected.migration_count,
        "unexpected upstream migration count"
    );

    assert_current_schema(db_path);
    let conn = rusqlite::Connection::open(db_path).expect("open upgraded DB");
    let migrated: (i64, String, u32) = conn
        .query_row(
            "SELECT COUNT(*), MIN(status), MIN(anchor_bucket_interval)
             FROM orchard_ironwood_migrations",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("read upgraded in-flight migration");
    assert_eq!(
        migrated,
        (1, "committed".to_string(), 144),
        "mobile/v0.0.18 in-flight migration was not preserved with the ZIP 318 grid"
    );
    assert_sqlite_health(db_path);
    println!(
        "verified scenario={} accounts={} migrations={} integrity=ok",
        scenario,
        actual.accounts.len(),
        actual.migration_count
    );
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
        actual.migration_count
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

    LegacyState {
        scenario: scenario.to_string(),
        migration_count: scalar_i64(&conn, "SELECT COUNT(*) FROM schemer_migrations"),
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
        "imported-only" => {
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
        "orchard_ironwood_migrations",
        "orchard_ironwood_migration_transactions",
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
        ("orchard_ironwood_migrations", "anchor_bucket_interval"),
    ] {
        assert!(
            column_exists(&conn, table, column),
            "missing upgraded column {table}.{column}"
        );
    }
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
