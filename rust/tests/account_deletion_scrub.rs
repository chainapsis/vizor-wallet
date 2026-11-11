//! Deleting an account must not leave its keys or addresses readable in the wallet files.
use rusqlite::Connection;
use rust_lib_zcash_wallet::wallet::keys::{
    add_account, delete_account, generate_mnemonic, init_db_and_create_account, mnemonic_to_seed,
};
use rust_lib_zcash_wallet::wallet::network::WalletNetwork;

const NETWORK: WalletNetwork = WalletNetwork::Main;

struct Wallet {
    _dir: tempfile::TempDir,
    path: String,
    kept_uuid: String,
    deleted_uuid: String,
    /// The deleted account's viewing key and every address stored for it.
    secrets: Vec<String>,
    kept_ufvk: String,
}

fn uuid_bytes(uuid: &str) -> Vec<u8> {
    uuid::Uuid::parse_str(uuid).unwrap().as_bytes().to_vec()
}

fn ufvk(conn: &Connection, uuid: &str) -> String {
    conn.query_row(
        "SELECT ufvk FROM accounts WHERE uuid = ?1",
        [uuid_bytes(uuid)],
        |row| row.get(0),
    )
    .unwrap()
}

fn wallet_with_two_accounts() -> Wallet {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    let seed = |_| mnemonic_to_seed(&generate_mnemonic()).unwrap();
    let (kept_uuid, _) =
        init_db_and_create_account(&path, NETWORK, &seed(0), None, "kept").unwrap();
    let (deleted_uuid, _) = add_account(&path, NETWORK, "deleted", &seed(1), None).unwrap();

    let conn = Connection::open(&path).unwrap();
    let mut secrets = vec![ufvk(&conn, &deleted_uuid)];
    secrets.extend(
        conn.prepare(
            "SELECT COALESCE(a.cached_transparent_receiver_address, a.address)
             FROM addresses a JOIN accounts acc ON acc.id = a.account_id
             WHERE acc.uuid = ?1",
        )
        .unwrap()
        .query_map([uuid_bytes(&deleted_uuid)], |row| {
            row.get::<_, Option<String>>(0)
        })
        .unwrap()
        .filter_map(|address| address.unwrap()),
    );
    let kept_ufvk = ufvk(&conn, &kept_uuid);
    Wallet {
        _dir: dir,
        path,
        kept_uuid,
        deleted_uuid,
        secrets,
        kept_ufvk,
    }
}

/// How many of `needles` appear anywhere in the database file or its WAL.
fn found_on_disk(path: &str, needles: &[String]) -> usize {
    let mut bytes = std::fs::read(path).unwrap();
    bytes.extend(std::fs::read(format!("{path}-wal")).unwrap_or_default());
    needles
        .iter()
        .filter(|needle| bytes.windows(needle.len()).any(|w| w == needle.as_bytes()))
        .count()
}

#[test]
fn deleted_account_is_scrubbed_while_another_connection_stays_open() {
    let wallet = wallet_with_two_accounts();
    assert!(wallet.secrets.len() > 1, "expected stored addresses");
    assert_eq!(
        found_on_disk(&wallet.path, &wallet.secrets),
        wallet.secrets.len()
    );
    // Closing the last connection checkpoints on its own; an open one shows
    // the deletion did it.
    let other = Connection::open(&wallet.path).unwrap();

    delete_account(&wallet.path, NETWORK, &wallet.deleted_uuid).unwrap();

    assert_eq!(found_on_disk(&wallet.path, &wallet.secrets), 0);
    assert_eq!(ufvk(&other, &wallet.kept_uuid), wallet.kept_ufvk);
    assert_eq!(found_on_disk(&wallet.path, &[wallet.kept_ufvk.clone()]), 1);
}

#[test]
fn deletion_succeeds_when_a_reader_blocks_the_checkpoint() {
    let wallet = wallet_with_two_accounts();
    let reader = Connection::open(&wallet.path).unwrap();
    reader
        .execute_batch("BEGIN; SELECT count(*) FROM accounts;")
        .unwrap();

    delete_account(&wallet.path, NETWORK, &wallet.deleted_uuid).unwrap();

    let remaining: i64 = Connection::open(&wallet.path)
        .unwrap()
        .query_row("SELECT count(*) FROM accounts", [], |row| row.get(0))
        .unwrap();
    assert_eq!(remaining, 1);
    // Once the reader is gone, the next checkpoint finishes the scrub.
    reader.execute_batch("COMMIT").unwrap();
    drop(reader);
    assert_eq!(found_on_disk(&wallet.path, &wallet.secrets), 0);
}
