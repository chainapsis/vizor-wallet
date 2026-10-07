//! Reader incompatibility and damaged ledger metadata must refuse before account mutation.
use rusqlite::{types::Value, Connection};
use rust_lib_zcash_wallet::api::wallet;

fn dump(conn: &Connection) -> Vec<(String, Vec<String>)> {
    let mut names = conn.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name").unwrap();
    names
        .query_map([], |r| r.get::<_, String>(0))
        .unwrap()
        .map(|name| {
            let name = name.unwrap();
            let mut stmt = conn
                .prepare(&format!("SELECT * FROM \"{}\"", name.replace('"', "\"\"")))
                .unwrap();
            let count = stmt.column_count();
            let mut rows = stmt
                .query_map([], |row| {
                    Ok(format!(
                        "{:?}",
                        (0..count)
                            .map(|i| row.get::<_, Value>(i))
                            .collect::<Result<Vec<_>, _>>()?
                    ))
                })
                .unwrap()
                .collect::<Result<Vec<_>, _>>()
                .unwrap();
            rows.sort();
            (name, rows)
        })
        .collect()
}

#[test]
fn deletion_child() {
    let Ok(path) = std::env::var("VIZOR_TEST_DELETE_DB") else {
        return;
    };
    let account = std::env::var("VIZOR_TEST_DELETE_ACCOUNT").unwrap();
    let conn = Connection::open(&path).unwrap();
    let before = dump(&conn);
    assert!(wallet::delete_account(path, "regtest".into(), account).is_err());
    assert!(
        dump(&conn) == before,
        "refused deletion mutated wallet tables"
    );
}

#[test]
fn fresh_process_refuses_incompatible_and_damaged_policy() {
    for damage in [
        "UPDATE tpir_meta SET min_reader_version = 999",
        "DELETE FROM tpir_meta WHERE id = 0",
        "DROP TABLE tpir_meta",
    ] {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
        let first = wallet::import_wallet(
            rust_lib_zcash_wallet::wallet::keys::mnemonic_from_entropy(vec![0; 32]).unwrap(),
            "".into(),
            Some(1),
            "regtest".into(),
            path.clone(),
            Some("First".into()),
        )
        .unwrap()
        .account_uuid;
        wallet::add_account(
            path.clone(),
            "regtest".into(),
            "Second".into(),
            rust_lib_zcash_wallet::wallet::keys::mnemonic_from_entropy(vec![1; 32]).unwrap(),
            "".into(),
            Some(1),
        )
        .unwrap();
        Connection::open(&path)
            .unwrap()
            .execute_batch(damage)
            .unwrap();
        let status = std::process::Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "deletion_child", "--nocapture"])
            .env("VIZOR_TEST_DELETE_DB", &path)
            .env("VIZOR_TEST_DELETE_ACCOUNT", first)
            .status()
            .unwrap();
        assert!(status.success(), "fresh-process refusal failed: {damage}");
    }
}

#[test]
fn cleanup_failure_rolls_back_library_account_deletion() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    let first = wallet::import_wallet(
        rust_lib_zcash_wallet::wallet::keys::mnemonic_from_entropy(vec![0; 32]).unwrap(),
        "".into(),
        Some(1),
        "regtest".into(),
        path.clone(),
        Some("First".into()),
    )
    .unwrap()
    .account_uuid;
    wallet::add_account(
        path.clone(),
        "regtest".into(),
        "Second".into(),
        rust_lib_zcash_wallet::wallet::keys::mnemonic_from_entropy(vec![1; 32]).unwrap(),
        "".into(),
        Some(1),
    )
    .unwrap();
    let conn = Connection::open(&path).unwrap();
    conn.execute(
        "INSERT OR REPLACE INTO ext_vizor_receive_addresses(account_uuid, address) VALUES (?1, 'test')",
        [uuid::Uuid::parse_str(&first).unwrap().as_bytes().as_slice()],
    )
    .unwrap();
    conn.execute_batch("CREATE TRIGGER refuse_receive_cleanup BEFORE DELETE ON ext_vizor_receive_addresses BEGIN SELECT RAISE(ABORT, 'injected cleanup failure'); END").unwrap();
    let before = dump(&conn);
    assert!(wallet::delete_account(path.clone(), "regtest".into(), first).is_err());
    assert!(
        dump(&conn) == before,
        "refused deletion mutated wallet tables"
    );
}

#[test]
fn missing_account_refuses_without_mutation() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    wallet::import_wallet(
        rust_lib_zcash_wallet::wallet::keys::mnemonic_from_entropy(vec![1; 32]).unwrap(),
        "".into(),
        Some(1),
        "regtest".into(),
        path.clone(),
        Some("First".into()),
    )
    .unwrap();
    wallet::add_account(
        path.clone(),
        "regtest".into(),
        "Second".into(),
        rust_lib_zcash_wallet::wallet::keys::mnemonic_from_entropy(vec![0; 32]).unwrap(),
        "".into(),
        Some(1),
    )
    .unwrap();
    let conn = Connection::open(&path).unwrap();
    let before = dump(&conn);
    assert!(wallet::delete_account(
        path.clone(),
        "regtest".into(),
        uuid::Uuid::new_v4().to_string()
    )
    .is_err());
    assert!(
        dump(&conn) == before,
        "refused deletion mutated wallet tables"
    );
}
