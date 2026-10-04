//! Upgrade probe, driven by `scripts/test-db-upgrade.sh`, which compiles this
//! file in both the base tree and the current tree:
//!
//! 1. `create` (base build) builds a wallet and records its schema, raw state,
//!    and what the base build's balance and history APIs report.
//! 2. `verify` (current build) upgrades it and checks that the schema is a
//!    superset of the base schema, the raw state is unchanged, and the current
//!    APIs report what the base APIs did.
//! Published-to-current upgrades are supported. Older writers after a private-ledger
//! upgrade are not qualified by this probe.
//!
//! API that differs between builds lives in `db_upgrade/compat.rs` (or a
//! base's `compat_<base>.rs`); current-build-only checks live in
//! `db_upgrade/current.rs`, which the base tree replaces with a stub.

use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::Path,
};

use rust_lib_zcash_wallet::api::{sync, wallet};
use serde::{Deserialize, Serialize};

#[path = "db_upgrade/compat.rs"]
mod compat;
#[path = "db_upgrade/current.rs"]
mod current;

const NETWORK: &str = "regtest";
const PRIMARY_MNEMONIC: &str = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art";
const SECONDARY_MNEMONIC: &str =
    "legal winner thank year wave sausage worth useful legal winner thank yellow";
/// Regtest UFVK of `SECONDARY_MNEMONIC` account 0, imported without its seed.
const HARDWARE_UFVK: &str = "uviewregtest1wc0v5cry88thqcarv52wll3a3kape7g3y4n3z938ul89jlnmclly56cttcg6cdat62m4nhcwn6vdsyf3g3ljkkd8fffk323l0qcy9ug8fsfxhexu737hckrvw6xgrz7dtepexaye25qdw02wys0l9h8kpes6wtge7ha6gu2c4jz75a4hrtzzt2ydympf2jjdg6hea687d2upfwf8ld6vdd46pxcylypkd8pdl3wt2jz4s0gjfu0swvzlzqm09nrjwj3uuf97yyvlrpx44stwlp6d9ak6sydqvyfp49a86khgzugrqkfm0l4qam995v56wt8c5k5pjlt947mazufsrkanv9y5atnh5tfh52nq30kjac97e6r2rcx25q8pl4p4uprqt60u3j2kedzev3acdr7ha5tg6gaejsjpmrtutyhstc7ssppwxga7cqd2r2fmlzp52ysaky97xznl23xtv36w2g3am9k42xy69qw3xz4pw6mussp6sg3l";

/// The chain tip the fixture records, so balances have a target height.
const TIP_HEIGHT: i64 = 20;
/// A transparent output discovered from the chain, later spent by `LOCAL_TXID`.
const REMOTE_TXID: [u8; 32] = [0x11; 32];
/// A locally created send: carries creation evidence and its own change output.
/// It is still unmined and unexpired at `TIP_HEIGHT`.
const LOCAL_TXID: [u8; 32] = [0x22; 32];
/// A mined transparent output nothing spends: spendable at `TIP_HEIGHT`.
const MINED_TXID: [u8; 32] = [0x33; 32];
const REMOTE_VALUE_ZAT: i64 = 50_000_000;
const LOCAL_CHANGE_ZAT: i64 = 49_990_000;
const MINED_VALUE_ZAT: i64 = 20_000_000;
const MINED_HEIGHT: i64 = 5;
/// The transaction the base build stores in `open-old`: it spends the mined
/// output and pays each account's first transparent address.
const OLD_BUILD_HEIGHT: u32 = 12;
const OLD_BUILD_PAYMENT_ZAT: u64 = 9_000_000;

/// The ledger schema, ledger policy generation, and ZIP 318 schema drop. The
/// pre-bump feature build applied them already; older bases did not.
const LEDGER_MIGRATIONS: [&str; 3] = [
    "772a06323d0e4dffb1f8c64863eefaaa",
    "8f290af0eb5a4f1e88d43550fc0ff911",
    "b7c4e2a19d3f4e8ba6c51f0e8d7c6b5a",
];
/// Transparent activity metadata and shared derivations, from the
/// wallet-libraries bump. No supported base has applied them.
const LIBRARY_BUMP_MIGRATIONS: [&str; 2] = [
    "935cd43609fd4f4fa808260ee399cb21",
    "a03b0d6a60854859ae77bce948345214",
];
const LEGACY_PUBLIC_ORIGIN: i64 = 0;
const LOCAL_ORIGIN: i64 = 1;

/// Schema objects the current build removes on purpose. Every entry must be
/// unused by the current build at runtime.
///
/// Matched as a prefix of `table:<name>`, `view:<name>`, `index:<name>`,
/// `column:<table or view>.<column>`, or `unique:<table>(<sorted columns>)`.
/// A removed table's indexes and unique keys go with it.
const REMOVED_FOR_ALL_BUILDS: [&str; 1] = [
    // The ZIP 318 pool-migration engine. Published builds reference these
    // tables only through `ON DELETE CASCADE` from `accounts`, which is inert
    // once the tables are gone.
    "table:orchard_ironwood_migration",
];
#[derive(Debug, Deserialize, Serialize)]
struct Manifest {
    state: LegacyState,
    schema: SchemaSnapshot,
    api: ApiSnapshot,
    /// What the base build wrote and read in `open-old`.
    after_old: Option<AfterOld>,
}

#[derive(Debug, Deserialize, Serialize)]
struct AfterOld {
    txid_hex: String,
    state: LegacyState,
    /// Recorded by `read-old`.
    api: Option<ApiSnapshot>,
}

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
    /// Every transparent output with its spent and lock state.
    transparent_outputs: Vec<TransparentOutputRow>,
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

#[derive(Debug, Deserialize, PartialEq, Serialize)]
struct TransparentOutputRow {
    txid_hex: String,
    output_index: i64,
    account_uuid_hex: String,
    address: String,
    value_zat: i64,
    spent: bool,
    /// `None` when the base schema has no transparent lock columns.
    locked: Option<bool>,
}

/// Tables and views with their columns, indexes with their table, and each
/// table's unique keys (the column sets an `ON CONFLICT` target can name).
#[derive(Debug, Default, Deserialize, PartialEq, Serialize)]
struct SchemaSnapshot {
    tables: BTreeMap<String, BTreeSet<String>>,
    views: BTreeMap<String, BTreeSet<String>>,
    indexes: BTreeMap<String, String>,
    unique_keys: BTreeMap<String, BTreeSet<Vec<String>>>,
}

/// What the balance and history APIs report, in the fields every supported
/// build shares.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
struct ApiSnapshot {
    accounts: Vec<AccountApi>,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
struct AccountApi {
    uuid: String,
    balance: BalanceSnapshot,
    history: Vec<HistoryRow>,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
struct BalanceSnapshot {
    availability: String,
    transparent: u64,
    sapling: u64,
    orchard: u64,
    ironwood: u64,
    transparent_locked: u64,
    sapling_locked: u64,
    orchard_locked: u64,
    ironwood_locked: u64,
    transparent_pending: u64,
    sapling_pending: u64,
    orchard_pending: u64,
    ironwood_pending: u64,
    change_pending_confirmation: u64,
    value_pending_spendability: u64,
    uneconomic_value: u64,
    spendable: u64,
    locked: u64,
    total: u64,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
struct HistoryRow {
    txid_hex: String,
    mined_height: u64,
    expired_unmined: bool,
    account_balance_delta: i64,
    fee: u64,
    block_time: u64,
    is_transparent: bool,
    tx_kind: String,
    display_amount: u64,
    display_pool: String,
    created_time: u64,
}

fn main() {
    let mut args = std::env::args().skip(1);
    let mode = args.next().expect(
        "usage: db_upgrade \
             <create|verify|open-old|read-old> <scenario> <db> <manifest>",
    );
    let scenario = args.next().expect("scenario");
    let db_path = args.next().expect("database path");
    let manifest_path = args.next().expect("manifest path");

    match mode.as_str() {
        "create" => create_fixture(&scenario, &db_path, &manifest_path),
        "verify" => verify_upgraded(&scenario, &db_path, &manifest_path),
        "open-old" => verify_old_reopen(&scenario, &db_path, &manifest_path),
        "read-old" => read_after_old(&scenario, &db_path, &manifest_path),
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
    let api = read_api(db_path);
    assert_fixture_balances(&api);
    let manifest = Manifest {
        state,
        schema: read_schema(db_path),
        api,
        after_old: None,
    };
    write_manifest(manifest_path, &manifest);
    println!(
        "created scenario={} accounts={} migrations={} tables={}",
        scenario,
        manifest.state.accounts.len(),
        manifest.state.migration_ids.len(),
        manifest.schema.tables.len(),
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

/// Inserts, as the base build would have stored them: a remote transparent
/// receive, a local send spending it whose change is locked when the base
/// schema supports transparent locks, and a mined receive nothing spends. Also
/// records a chain tip so balances have a target height. A base that already
/// keeps transparent provenance gets the provenance its writers record.
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
    let with_provenance = object_exists(&conn, "table", "tpir_output_origins");
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
    tx.execute(
        "INSERT INTO transactions (txid, mined_height, min_observed_height)
         VALUES (?1, ?2, ?2)",
        rusqlite::params![&MINED_TXID[..], MINED_HEIGHT],
    )
    .expect("insert mined receive");
    let mined_tx = tx.last_insert_rowid();
    let insert_output = |transaction_id: i64, output_index: i64, value: i64, observed: i64| {
        tx.execute(
            "INSERT INTO transparent_received_outputs (
                 transaction_id, output_index, account_id, address, script, value_zat,
                 max_observed_unspent_height, address_id
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            rusqlite::params![
                transaction_id,
                output_index,
                account_id,
                address,
                script,
                value,
                observed,
                address_id
            ],
        )
        .expect("insert transparent output");
        let id = tx.last_insert_rowid();
        if with_provenance {
            tx.execute(
                "INSERT INTO tpir_output_origins (output_id, origin) VALUES (?1, ?2)",
                [id, LEGACY_PUBLIC_ORIGIN],
            )
            .expect("record output provenance");
        }
        id
    };
    let remote_output = insert_output(remote_tx, 0, REMOTE_VALUE_ZAT, 10);
    let local_change = insert_output(local_tx, 1, LOCAL_CHANGE_ZAT, 10);
    insert_output(mined_tx, 0, MINED_VALUE_ZAT, TIP_HEIGHT);
    tx.execute(
        "INSERT INTO transparent_received_output_spends (
             transparent_received_output_id, transaction_id
         ) VALUES (?1, ?2)",
        [remote_output, local_tx],
    )
    .expect("insert local spend");
    if with_provenance {
        tx.execute(
            "INSERT INTO tpir_output_origins (output_id, origin) VALUES (?1, ?2)",
            [local_change, LOCAL_ORIGIN],
        )
        .expect("record local output provenance");
        for origin in [LEGACY_PUBLIC_ORIGIN, LOCAL_ORIGIN] {
            tx.execute(
                "INSERT INTO tpir_spend_origins (
                     spending_transaction_id, prevout_txid, prevout_output_index, origin
                 ) VALUES (?1, ?2, 0, ?3)",
                rusqlite::params![local_tx, &REMOTE_TXID[..], origin],
            )
            .expect("record spend provenance");
        }
    }
    if column_exists(&tx, "transparent_received_outputs", "lock_owner") {
        tx.execute(
            "UPDATE transparent_received_outputs
             SET lock_owner = X'01', lock_expiry_height = 52
             WHERE id = ?1",
            [local_change],
        )
        .expect("lock local change");
    }
    // A wallet born at height 1 and synced to the tip: everything above any
    // range account creation queued is scanned, and the tip block is stored.
    // History reads expiry against the highest stored block.
    let queued_end: Option<i64> = tx
        .query_row("SELECT MAX(block_range_end) FROM scan_queue", [], |row| {
            row.get(0)
        })
        .expect("read scan queue");
    let queued_end = queued_end.unwrap_or(1);
    assert!(
        queued_end <= TIP_HEIGHT,
        "fixture scan queue already passes the tip"
    );
    tx.execute(
        "INSERT INTO scan_queue (block_range_start, block_range_end, priority)
         VALUES (?1, ?2, 10)",
        [queued_end, TIP_HEIGHT + 1],
    )
    .expect("record the scanned chain");
    tx.execute(
        "INSERT INTO blocks (
             height, hash, time, sapling_tree, sapling_commitment_tree_size,
             orchard_commitment_tree_size, sapling_output_count, orchard_action_count
         ) VALUES (?1, ?2, 1700000000, X'000000', 0, 0, 0, 0)",
        rusqlite::params![TIP_HEIGHT, &[0x20u8; 32][..]],
    )
    .expect("store the tip block");
    if column_exists(&tx, "blocks", "ironwood_commitment_tree_size") {
        tx.execute(
            "UPDATE blocks SET ironwood_commitment_tree_size = 0, ironwood_action_count = 0
             WHERE height = ?1",
            [TIP_HEIGHT],
        )
        .expect("record empty Ironwood tree");
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

/// The fixture is only useful if the base build reports its transparent
/// funds: the mined receive is spendable and the local change is locked.
fn assert_fixture_balances(api: &ApiSnapshot) {
    let funded = api
        .accounts
        .iter()
        .find(|account| account.balance.transparent > 0)
        .unwrap_or_else(|| panic!("base build reports no transparent funds: {api:?}"));
    assert_eq!(funded.balance.availability, "available");
    assert_eq!(funded.balance.transparent, MINED_VALUE_ZAT as u64);
}

fn verify_upgraded(scenario: &str, db_path: &str, manifest_path: &str) {
    let manifest = read_manifest(manifest_path);
    assert_eq!(manifest.state.scenario, scenario);
    let (expected, expected_api) = match &manifest.after_old {
        Some(after) => (
            &after.state,
            after.api.as_ref().expect("read-old recorded the base APIs"),
        ),
        None => (&manifest.state, &manifest.api),
    };

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
    assert_eq!(
        strip_locks(&actual.transparent_outputs, expected),
        expected.transparent_outputs,
        "transparent outputs, spends, or locks changed during upgrade"
    );
    if let Some(locked) = expected.locked_transparent_outputs {
        assert_eq!(actual.locked_transparent_outputs, Some(locked));
    }
    assert_migrations(&manifest.state, &actual);

    assert_current_schema(db_path);
    assert_schema_superset(
        &manifest.schema,
        &read_schema(db_path),
        &REMOVED_FOR_ALL_BUILDS,
    );
    assert_transparent_ledger(db_path, manifest.after_old.as_ref());
    assert_sqlite_health(db_path);

    // The current APIs report what the base APIs did; only fields the base
    // build does not have may add information, and the documented history
    // rules may change a row only as `expected_current_api` states.
    let actual_api = read_api(db_path);
    current::assert_current_api(db_path, &actual_api);
    assert_eq!(
        actual_api,
        current::expected_current_api(db_path, expected_api),
        "current build reports different balances or history than the base build"
    );
    let spendable = spendable_outputs(db_path, &actual);
    let expected_spendable = expected_spendable(&manifest);
    assert_eq!(
        spendable, expected_spendable,
        "current build in Public mode selects different transparent inputs"
    );

    println!(
        "verified scenario={} accounts={} migrations={} returned={} integrity=ok",
        scenario,
        actual.accounts.len(),
        actual.migration_ids.len(),
        manifest.after_old.is_some(),
    );
}

/// The base schema may lack the lock columns; compare lock state only when it
/// has them.
fn strip_locks(
    outputs: &[TransparentOutputRow],
    expected: &LegacyState,
) -> Vec<TransparentOutputRow> {
    outputs
        .iter()
        .map(|output| TransparentOutputRow {
            txid_hex: output.txid_hex.clone(),
            output_index: output.output_index,
            account_uuid_hex: output.account_uuid_hex.clone(),
            address: output.address.clone(),
            value_zat: output.value_zat,
            spent: output.spent,
            locked: expected.locked_transparent_outputs.and(output.locked),
        })
        .collect()
}

/// Every migration the base applied survives, and the current build's own
/// migrations are applied: the library bump's always newly, the ledger's
/// newly unless the base already kept a transparent ledger.
fn assert_migrations(base: &LegacyState, actual: &LegacyState) {
    assert!(
        base.migration_ids.is_subset(&actual.migration_ids),
        "upgrade lost applied migrations"
    );
    let base_has_ledger = base.migration_ids.contains(LEDGER_MIGRATIONS[1]);
    for id in LEDGER_MIGRATIONS {
        assert!(actual.migration_ids.contains(id), "migration {id} missing");
        if !base_has_ledger {
            assert!(
                !base.migration_ids.contains(id),
                "migration {id} predates the ledger schema"
            );
        }
    }
    for id in LIBRARY_BUMP_MIGRATIONS {
        assert!(
            !base.migration_ids.contains(id) && actual.migration_ids.contains(id),
            "migration {id} was not newly applied"
        );
    }
}

/// Transparent outputs the current build would select as inputs, for every
/// account, as `(txid, index, value)`.
fn spendable_outputs(db_path: &str, state: &LegacyState) -> BTreeSet<(String, u32, u64)> {
    let addresses = state
        .addresses
        .iter()
        .filter_map(|row| row.cached_transparent_receiver_address.clone())
        .collect::<BTreeSet<_>>();
    current::spendable_outputs(db_path, &addresses, TIP_HEIGHT as u32)
}

/// The mined receive until the base build spends it; afterwards, the payments
/// that spend reached each account.
fn expected_spendable(manifest: &Manifest) -> BTreeSet<(String, u32, u64)> {
    match &manifest.after_old {
        None => BTreeSet::from([(hex::encode(MINED_TXID), 0, MINED_VALUE_ZAT as u64)]),
        Some(after) => (0..manifest.state.accounts.len() as u32)
            .map(|index| (after.txid_hex.clone(), index, OLD_BUILD_PAYMENT_ZAT))
            .collect(),
    }
}

/// The ledger starts public (generation 0, reader version 1), and every
/// transparent record carries legacy-public provenance, plus local provenance
/// where the wallet created the transaction. Neither is private coverage.
/// The upgrade runner uses only records stored before the upgrade.
fn assert_transparent_ledger(db_path: &str, after_old: Option<&AfterOld>) {
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
    // Queued follow-on work is bound to the initial policy generation.
    assert_eq!(
        scalar_i64(
            &conn,
            "SELECT COUNT(*) FROM pragma_table_info('tx_retrieval_queue')
             WHERE name = 'policy_generation'",
        ),
        1,
        "tx_retrieval_queue has no policy generation"
    );
    assert_eq!(
        scalar_i64(
            &conn,
            "SELECT COUNT(*) FROM tx_retrieval_queue WHERE policy_generation != 0",
        ),
        0,
        "queued work outside the initial policy generation"
    );
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
    let spend_origins = |txid: &[u8]| {
        origins(
            &conn,
            "SELECT r.origin FROM tpir_spend_origins r
             JOIN transactions t ON t.id_tx = r.spending_transaction_id
             WHERE t.txid = ?1",
            txid,
        )
    };
    assert_eq!(output_origins(&REMOTE_TXID), vec![LEGACY_PUBLIC_ORIGIN]);
    assert_eq!(
        output_origins(&LOCAL_TXID),
        vec![LEGACY_PUBLIC_ORIGIN, LOCAL_ORIGIN]
    );
    assert_eq!(output_origins(&MINED_TXID), vec![LEGACY_PUBLIC_ORIGIN]);
    assert_eq!(
        spend_origins(&LOCAL_TXID),
        vec![LEGACY_PUBLIC_ORIGIN, LOCAL_ORIGIN]
    );
    let mut spends = 2;
    if let Some(after) = after_old {
        // The base build's transaction is a public observation, not local intent.
        let txid = hex::decode(&after.txid_hex).expect("decode old-build txid");
        let outputs = output_origins(&txid);
        assert!(!outputs.is_empty(), "old-build outputs are missing");
        assert!(
            outputs.iter().all(|origin| *origin == LEGACY_PUBLIC_ORIGIN),
            "old-build outputs not reconciled as public: {outputs:?}"
        );
        assert_eq!(spend_origins(&txid), vec![LEGACY_PUBLIC_ORIGIN]);
        spends += 1;
    }
    assert_eq!(
        scalar_i64(&conn, "SELECT COUNT(*) FROM tpir_spend_origins"),
        spends,
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

/// Optional diagnostic command; the upgrade runner does not qualify older writers.
fn verify_old_reopen(scenario: &str, db_path: &str, manifest_path: &str) {
    let mut manifest = read_manifest(manifest_path);
    assert_eq!(manifest.state.scenario, scenario);
    assert!(manifest.after_old.is_none(), "open-old ran twice");
    let expected = &manifest.state;

    let accounts = wallet::list_accounts(db_path.to_string(), NETWORK.to_string())
        .expect("old build reopens upgraded pre-Ironwood wallet");
    assert_eq!(accounts.len(), expected.accounts.len());

    let actual = read_legacy_state(db_path, scenario);
    assert_eq!(actual.accounts, expected.accounts);
    assert_eq!(actual.addresses, expected.addresses);
    assert_eq!(actual.transaction_count, expected.transaction_count);
    assert_eq!(actual.sapling_note_count, expected.sapling_note_count);
    assert_eq!(actual.orchard_note_count, expected.orchard_note_count);
    assert_eq!(
        strip_locks(&actual.transparent_outputs, expected),
        expected.transparent_outputs
    );
    assert_sqlite_health(db_path);

    // The old build reads what it wrote before the upgrade.
    assert_eq!(
        read_api(db_path),
        manifest.api,
        "old build reads different balances or history after the upgrade"
    );

    // Its real ingestion path stores a transaction that spends a wallet
    // output and pays every account.
    let recipients = first_transparent_receivers(db_path);
    let raw = old_build_transaction(&recipients);
    let txid_hex = compat::store_transaction(db_path, &raw, OLD_BUILD_HEIGHT);
    let after = read_legacy_state(db_path, scenario);
    assert_eq!(after.transaction_count, expected.transaction_count + 1);
    assert_eq!(
        after.transparent_output_count,
        expected.transparent_output_count + recipients.len() as i64,
        "old build did not store its payments"
    );
    let mined_spent = after
        .transparent_outputs
        .iter()
        .any(|output| output.txid_hex == hex::encode(MINED_TXID) && output.spent);
    assert!(mined_spent, "old build did not record its spend");
    assert_sqlite_health(db_path);
    println!(
        "old-reopen scenario={} accounts={} migrations={} stored={} integrity=ok",
        scenario,
        actual.accounts.len(),
        actual.migration_ids.len(),
        txid_hex,
    );
    manifest.after_old = Some(AfterOld {
        txid_hex,
        state: after,
        api: None,
    });
    write_manifest(manifest_path, &manifest);
}

/// What the base APIs report after the base build's own write.
fn read_after_old(scenario: &str, db_path: &str, manifest_path: &str) {
    let mut manifest = read_manifest(manifest_path);
    assert_eq!(manifest.state.scenario, scenario);
    let after = manifest.after_old.as_mut().expect("open-old ran");
    assert!(after.api.is_none(), "read-old ran twice");
    let api = read_api(db_path);
    for account in &api.accounts {
        assert!(
            account
                .history
                .iter()
                .any(|row| row.txid_hex == after.txid_hex),
            "old build history lacks its transaction"
        );
    }
    assert_eq!(read_legacy_state(db_path, scenario), after.state);
    println!("old-read scenario={scenario} txid={}", after.txid_hex);
    after.api = Some(api);
    write_manifest(manifest_path, &manifest);
}

/// Each account's lowest external transparent receiver, in account order.
fn first_transparent_receivers(db_path: &str) -> Vec<String> {
    let conn = rusqlite::Connection::open(db_path).expect("open wallet DB");
    let receivers = conn
        .prepare(
            "SELECT (SELECT a.cached_transparent_receiver_address FROM addresses a
                     WHERE a.account_id = accounts.id AND a.key_scope = 0
                       AND a.cached_transparent_receiver_address IS NOT NULL
                     ORDER BY a.transparent_child_index LIMIT 1)
             FROM accounts ORDER BY accounts.id",
        )
        .expect("prepare receivers")
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query receivers")
        .collect::<Result<Vec<_>, _>>()
        .expect("every account has a transparent receiver");
    receivers
}

/// A version 1 transparent transaction spending the mined fixture output and
/// paying `OLD_BUILD_PAYMENT_ZAT` to each of `recipients`. Built as raw bytes so
/// every build parses the same transaction.
fn old_build_transaction(recipients: &[String]) -> Vec<u8> {
    let mut bytes = 1u32.to_le_bytes().to_vec();
    bytes.push(1);
    bytes.extend_from_slice(&MINED_TXID);
    bytes.extend_from_slice(&0u32.to_le_bytes());
    bytes.push(0);
    bytes.extend_from_slice(&u32::MAX.to_le_bytes());
    bytes.push(recipients.len() as u8);
    for recipient in recipients {
        bytes.extend_from_slice(&OLD_BUILD_PAYMENT_ZAT.to_le_bytes());
        bytes.push(25);
        bytes.extend_from_slice(&[0x76, 0xa9, 0x14]);
        bytes.extend_from_slice(&p2pkh_hash(recipient));
        bytes.extend_from_slice(&[0x88, 0xac]);
    }
    bytes.extend_from_slice(&0u32.to_le_bytes());
    bytes
}

/// The key hash of a base58check P2PKH address with a two-byte prefix.
fn p2pkh_hash(address: &str) -> [u8; 20] {
    const ALPHABET: &[u8] = b"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    let mut decoded: Vec<u8> = Vec::new();
    for c in address.bytes() {
        let mut carry = ALPHABET
            .iter()
            .position(|a| *a == c)
            .unwrap_or_else(|| panic!("not base58: {address}")) as u32;
        for byte in decoded.iter_mut().rev() {
            carry += u32::from(*byte) * 58;
            *byte = carry as u8;
            carry >>= 8;
        }
        while carry > 0 {
            decoded.insert(0, carry as u8);
            carry >>= 8;
        }
    }
    let leading = address.bytes().take_while(|c| *c == b'1').count();
    let decoded = [vec![0; leading], decoded].concat();
    assert_eq!(decoded.len(), 26, "not a two-byte-prefix P2PKH address");
    decoded[2..22].try_into().unwrap()
}

/// Balances and history of every account through the build's own APIs.
fn read_api(db_path: &str) -> ApiSnapshot {
    let conn = rusqlite::Connection::open(db_path).expect("open wallet DB");
    let uuids = conn
        .prepare("SELECT lower(hex(uuid)) FROM accounts ORDER BY id")
        .expect("prepare account uuids")
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query account uuids")
        .collect::<Result<Vec<_>, _>>()
        .expect("read account uuids");
    drop(conn);
    let accounts = uuids
        .into_iter()
        .map(|hex| {
            let uuid = format!(
                "{}-{}-{}-{}-{}",
                &hex[0..8],
                &hex[8..12],
                &hex[12..16],
                &hex[16..20],
                &hex[20..32]
            );
            let b = sync::get_balance(db_path.to_string(), NETWORK.to_string(), uuid.clone())
                .expect("read balance");
            let balance = BalanceSnapshot {
                availability: match b.availability {
                    sync::WalletBalanceAvailability::Available => "available",
                    sync::WalletBalanceAvailability::SummaryUnavailable => "summary-unavailable",
                    sync::WalletBalanceAvailability::AccountUnavailable => "account-unavailable",
                }
                .to_string(),
                transparent: b.transparent,
                sapling: b.sapling,
                orchard: b.orchard,
                ironwood: b.ironwood,
                transparent_locked: b.transparent_locked,
                sapling_locked: b.sapling_locked,
                orchard_locked: b.orchard_locked,
                ironwood_locked: b.ironwood_locked,
                transparent_pending: b.transparent_pending,
                sapling_pending: b.sapling_pending,
                orchard_pending: b.orchard_pending,
                ironwood_pending: b.ironwood_pending,
                change_pending_confirmation: b.change_pending_confirmation,
                value_pending_spendability: b.value_pending_spendability,
                uneconomic_value: b.uneconomic_value,
                spendable: b.spendable,
                locked: b.locked,
                total: b.total,
            };
            let history = sync::get_transaction_history(
                db_path.to_string(),
                NETWORK.to_string(),
                None,
                uuid.clone(),
            )
            .expect("read history")
            .into_iter()
            .map(|t| HistoryRow {
                txid_hex: t.txid_hex,
                mined_height: t.mined_height,
                expired_unmined: t.expired_unmined,
                account_balance_delta: t.account_balance_delta,
                fee: t.fee,
                block_time: t.block_time,
                is_transparent: t.is_transparent,
                tx_kind: t.tx_kind,
                display_amount: t.display_amount,
                display_pool: t.display_pool,
                created_time: t.created_time,
            })
            .collect();
            AccountApi {
                uuid,
                balance,
                history,
            }
        })
        .collect();
    ApiSnapshot { accounts }
}

fn read_manifest(path: &str) -> Manifest {
    serde_json::from_slice(&fs::read(path).expect("read manifest")).expect("decode manifest")
}

fn write_manifest(path: &str, manifest: &Manifest) {
    fs::write(
        path,
        serde_json::to_vec_pretty(manifest).expect("encode manifest"),
    )
    .expect("write manifest");
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

    let has_locks = column_exists(&conn, "transparent_received_outputs", "lock_owner");
    let transparent_outputs = conn
        .prepare(&format!(
            "SELECT lower(hex(t.txid)), o.output_index, hex(a.uuid), o.address, o.value_zat,
                    EXISTS(SELECT 1 FROM transparent_received_output_spends s
                           WHERE s.transparent_received_output_id = o.id),
                    {}
             FROM transparent_received_outputs o
             JOIN transactions t ON t.id_tx = o.transaction_id
             JOIN accounts a ON a.id = o.account_id
             ORDER BY t.txid, o.output_index",
            if has_locks {
                "o.lock_owner IS NOT NULL"
            } else {
                "NULL"
            }
        ))
        .expect("prepare transparent outputs")
        .query_map([], |row| {
            Ok(TransparentOutputRow {
                txid_hex: row.get(0)?,
                output_index: row.get(1)?,
                account_uuid_hex: row.get(2)?,
                address: row.get(3)?,
                value_zat: row.get(4)?,
                spent: row.get(5)?,
                locked: row.get(6)?,
            })
        })
        .expect("query transparent outputs")
        .collect::<Result<Vec<_>, _>>()
        .expect("read transparent outputs");

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
        transparent_outputs,
        locked_transparent_outputs: has_locks.then(|| {
            scalar_i64(
                &conn,
                "SELECT COUNT(*) FROM transparent_received_outputs WHERE lock_owner IS NOT NULL",
            )
        }),
    }
}

/// Every table, view, and index, with table and view columns.
fn read_schema(db_path: &str) -> SchemaSnapshot {
    let conn = rusqlite::Connection::open(db_path).expect("open wallet DB");
    let objects = conn
        .prepare(
            "SELECT type, name, tbl_name FROM sqlite_master
             WHERE type IN ('table', 'view', 'index') AND name NOT LIKE 'sqlite_%'",
        )
        .expect("prepare schema")
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
            ))
        })
        .expect("query schema")
        .collect::<Result<Vec<_>, _>>()
        .expect("read schema");
    let mut schema = SchemaSnapshot::default();
    for (kind, name, table) in objects {
        let columns = || {
            conn.prepare("SELECT name FROM pragma_table_info(?1)")
                .expect("prepare columns")
                .query_map([&name], |row| row.get::<_, String>(0))
                .expect("query columns")
                .collect::<Result<BTreeSet<_>, _>>()
                .expect("read columns")
        };
        match kind.as_str() {
            "table" => {
                schema.tables.insert(name.clone(), columns());
                schema
                    .unique_keys
                    .insert(name.clone(), unique_keys(&conn, &name));
            }
            "view" => {
                schema.views.insert(name.clone(), columns());
            }
            _ => {
                schema.indexes.insert(name, table);
            }
        }
    }
    schema
}

/// Column sets of `table`'s unique indexes, including inline UNIQUE and
/// PRIMARY KEY constraints, each sorted.
fn unique_keys(conn: &rusqlite::Connection, table: &str) -> BTreeSet<Vec<String>> {
    let indexes = conn
        .prepare("SELECT name FROM pragma_index_list(?1) WHERE \"unique\" = 1")
        .expect("prepare unique indexes")
        .query_map([table], |row| row.get::<_, String>(0))
        .expect("query unique indexes")
        .collect::<Result<Vec<_>, _>>()
        .expect("read unique indexes");
    indexes
        .into_iter()
        .map(|index| {
            let mut columns = conn
                .prepare("SELECT name FROM pragma_index_info(?1)")
                .expect("prepare index columns")
                .query_map([&index], |row| row.get::<_, Option<String>>(0))
                .expect("query index columns")
                .collect::<Result<Vec<_>, _>>()
                .expect("read index columns")
                .into_iter()
                .map(|column| column.unwrap_or_else(|| "<expression>".to_string()))
                .collect::<Vec<_>>();
            columns.sort();
            columns
        })
        .collect()
}

/// Older builds keep working only if nothing they use disappeared: every base
/// table, view, and index remains, with every base column and every base
/// unique key (older writers name them as `ON CONFLICT` targets), except
/// `removed`.
fn assert_schema_superset(base: &SchemaSnapshot, actual: &SchemaSnapshot, removed: &[&str]) {
    let allowed = |key: &str| removed.iter().any(|prefix| key.starts_with(prefix));
    let mut missing = Vec::new();
    for (kind, base_objects, actual_objects) in [
        ("table", &base.tables, &actual.tables),
        ("view", &base.views, &actual.views),
    ] {
        for (name, columns) in base_objects {
            let key = format!("{kind}:{name}");
            match actual_objects.get(name) {
                None if !allowed(&key) => missing.push(key),
                None => {}
                Some(actual_columns) => {
                    for column in columns.difference(actual_columns) {
                        let key = format!("column:{name}.{column}");
                        if !allowed(&key) {
                            missing.push(key);
                        }
                    }
                    if kind == "table" {
                        let actual_keys = actual.unique_keys.get(name);
                        for unique in base.unique_keys.get(name).into_iter().flatten() {
                            let key = format!("unique:{name}({})", unique.join(","));
                            if !actual_keys.is_some_and(|keys| keys.contains(unique))
                                && !allowed(&key)
                            {
                                missing.push(key);
                            }
                        }
                    }
                }
            }
        }
    }
    for (name, table) in &base.indexes {
        let key = format!("index:{name}");
        let removed_with_table = allowed(&format!("table:{table}"));
        if actual.indexes.get(name) != Some(table) && !allowed(&key) && !removed_with_table {
            missing.push(key);
        }
    }
    assert!(
        missing.is_empty(),
        "schema objects an older build may use were removed: {missing:?}"
    );
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
        "tpir_transaction_metadata",
        "tpir_shared_derivations",
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
    // The current library retains the published classification schema in place.
    assert!(column_exists(&conn, "transactions", "zip318_kind"));
    assert!(column_exists(&conn, "v_transactions", "zip318_kind"));
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
