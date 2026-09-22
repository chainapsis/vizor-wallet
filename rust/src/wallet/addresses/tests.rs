use secrecy::{ExposeSecret, SecretVec};
use voting_crypto_deps::rand::rngs::OsRng;
use zcash_client_backend::data_api::{
    chain::ChainState, Account as _, AccountBirthday, AccountPurpose, WalletRead, WalletWrite,
};
use zcash_client_sqlite::{util::SystemClock, wallet::init::init_wallet_db, AccountUuid, WalletDb};
use zcash_keys::{
    address::Address,
    keys::{ReceiverRequirement, UnifiedAddressRequest, UnifiedFullViewingKey, UnifiedSpendingKey},
};
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::{BlockHeight, NetworkUpgrade, Parameters};
use zip32::DiversifierIndex;

use crate::wallet::{db::WalletDatabase, keys, network::WalletNetwork};

fn legacy_software_request() -> UnifiedAddressRequest {
    UnifiedAddressRequest::custom(
        ReceiverRequirement::Require,
        ReceiverRequirement::Require,
        ReceiverRequirement::Omit,
    )
    .unwrap()
}

fn orchard_only_request() -> UnifiedAddressRequest {
    UnifiedAddressRequest::custom(
        ReceiverRequirement::Require,
        ReceiverRequirement::Omit,
        ReceiverRequirement::Omit,
    )
    .unwrap()
}

fn orchard_transparent_request() -> UnifiedAddressRequest {
    UnifiedAddressRequest::custom(
        ReceiverRequirement::Require,
        ReceiverRequirement::Omit,
        ReceiverRequirement::Require,
    )
    .unwrap()
}

fn account_ufvk(seed: &SecretVec<u8>) -> UnifiedFullViewingKey {
    UnifiedSpendingKey::from_seed(
        &WalletNetwork::Main,
        seed.expose_secret(),
        zip32::AccountId::ZERO,
    )
    .unwrap()
    .to_unified_full_viewing_key()
}

fn hardware_ufvk(seed: &SecretVec<u8>) -> UnifiedFullViewingKey {
    use zcash_address::unified::{Encoding, Fvk, Ufvk};
    use zcash_protocol::consensus::NetworkType;

    let full = account_ufvk(seed);
    let encoded = Ufvk::try_from_items(vec![
        Fvk::Orchard(full.orchard().unwrap().to_bytes()),
        Fvk::P2pkh(full.transparent().unwrap().serialize().try_into().unwrap()),
    ])
    .unwrap()
    .encode(&NetworkType::Main);
    UnifiedFullViewingKey::decode(&WalletNetwork::Main, &encoded).unwrap()
}

fn old_wallet(db_path: &str) -> WalletDatabase {
    let conn = rusqlite::Connection::open(db_path).unwrap();
    rusqlite::vtab::array::load_module(&conn).unwrap();
    // A plain handle deliberately retains the upstream AllAvailableKeys default.
    WalletDb::from_connection(conn, WalletNetwork::Main, SystemClock, OsRng)
}

fn old_birthday() -> AccountBirthday {
    let height = WalletNetwork::Main
        .activation_height(NetworkUpgrade::Sapling)
        .unwrap();
    AccountBirthday::from_parts(ChainState::empty(height - 1, BlockHash([0; 32])), None)
}

fn create_old_software_account(
    db: &mut WalletDatabase,
    seed: &SecretVec<u8>,
    name: &str,
) -> AccountUuid {
    init_wallet_db(db, Some(SecretVec::new(seed.expose_secret().to_vec()))).unwrap();
    db.create_account(name, seed, &old_birthday(), None)
        .unwrap()
        .0
}

fn old_current_address(
    db: &WalletDatabase,
    account_id: AccountUuid,
    ufvk: &UnifiedFullViewingKey,
    request: UnifiedAddressRequest,
) -> String {
    db.get_last_generated_address_matching(account_id, request)
        .unwrap()
        .unwrap_or_else(|| ufvk.default_address(request).unwrap().0)
        .encode(&WalletNetwork::Main)
}

fn orchard_projection(ufvk: &UnifiedFullViewingKey, index: DiversifierIndex) -> String {
    ufvk.address(index, orchard_only_request())
        .unwrap()
        .encode(&WalletNetwork::Main)
}

fn assert_same_orchard_receiver(old: &str, new: &str) {
    let Address::Unified(old) = Address::decode(&WalletNetwork::Main, old).unwrap() else {
        panic!("old address is not unified");
    };
    let Address::Unified(new) = Address::decode(&WalletNetwork::Main, new).unwrap() else {
        panic!("new address is not unified");
    };
    assert_eq!(old.orchard(), new.orchard());
    assert!(new.sapling().is_none());
    assert!(new.transparent().is_none());
}

type AddressRow = (
    i64,
    i64,
    i64,
    Option<Vec<u8>>,
    String,
    Option<i64>,
    Option<String>,
    Option<i64>,
    i64,
);

fn address_rows(conn: &rusqlite::Connection) -> Vec<AddressRow> {
    let mut stmt = conn
        .prepare(
            "SELECT id, account_id, key_scope, diversifier_index_be, address, \
                    transparent_child_index, cached_transparent_receiver_address, \
                    exposed_at_height, receiver_flags \
             FROM addresses ORDER BY account_id, key_scope, diversifier_index_be, id",
        )
        .unwrap();
    stmt.query_map([], |row| {
        Ok((
            row.get(0)?,
            row.get(1)?,
            row.get(2)?,
            row.get(3)?,
            row.get(4)?,
            row.get(5)?,
            row.get(6)?,
            row.get(7)?,
            row.get(8)?,
        ))
    })
    .unwrap()
    .collect::<Result<Vec<_>, _>>()
    .unwrap()
}

fn extension_schema(conn: &rusqlite::Connection) -> Vec<(String, String)> {
    let mut stmt = conn
        .prepare(
            "SELECT type, name FROM sqlite_schema \
             WHERE name LIKE 'ext\\_%' ESCAPE '\\' ORDER BY type, name",
        )
        .unwrap();
    stmt.query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap()
}

fn snapshot(db_path: &str) -> (Vec<AddressRow>, Vec<(String, String)>) {
    let conn = rusqlite::Connection::open(db_path).unwrap();
    (address_rows(&conn), extension_schema(&conn))
}

fn address_row_id(conn: &rusqlite::Connection, encoded: &str) -> i64 {
    conn.query_row(
        "SELECT id FROM addresses WHERE address = ?1",
        [encoded],
        |row| row.get(0),
    )
    .unwrap()
}

#[test]
fn old_default_nonzero_index_keeps_its_orchard_receiver_without_writes() {
    let (seed, ufvk, legacy_index) = (1u8..=u8::MAX)
        .find_map(|marker| {
            let seed = SecretVec::new(vec![marker; 32]);
            let ufvk = account_ufvk(&seed);
            let (_, index) = ufvk.default_address(legacy_software_request()).ok()?;
            (index != DiversifierIndex::new()).then_some((seed, ufvk, index))
        })
        .expect("test vectors include a nonzero Sapling-compatible diversifier");

    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path_str = db_path.to_str().unwrap();
    let mut old_db = old_wallet(db_path_str);
    let account_id = create_old_software_account(&mut old_db, &seed, "old default");
    let old_displayed = old_current_address(&old_db, account_id, &ufvk, legacy_software_request());
    drop(old_db);
    let before = snapshot(db_path_str);
    assert!(before.1.is_empty());

    let uuid = account_id.expose_uuid().to_string();
    let projected =
        keys::get_address_from_db(db_path_str, WalletNetwork::Main, Some(&uuid)).unwrap();

    assert_eq!(projected, orchard_projection(&ufvk, legacy_index));
    assert_same_orchard_receiver(&old_displayed, &projected);
    assert_eq!(snapshot(db_path_str), before);
    assert_eq!(
        keys::get_address_from_db(db_path_str, WalletNetwork::Main, Some(&uuid)).unwrap(),
        projected
    );
    assert_eq!(snapshot(db_path_str), before);
}

#[test]
fn old_renewed_sapling_address_is_projected_from_its_stored_index() {
    let seed = SecretVec::new(vec![42; 32]);
    let ufvk = account_ufvk(&seed);
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path_str = db_path.to_str().unwrap();
    let mut old_db = old_wallet(db_path_str);
    let account_id = create_old_software_account(&mut old_db, &seed, "old renewed");
    old_db
        .update_chain_tip(BlockHeight::from_u32(2_500_000))
        .unwrap();
    let (renewed, renewed_index) = old_db
        .get_next_available_address(account_id, legacy_software_request())
        .unwrap()
        .unwrap();
    let old_displayed = old_current_address(&old_db, account_id, &ufvk, legacy_software_request());
    assert_eq!(old_displayed, renewed.encode(&WalletNetwork::Main));
    drop(old_db);
    let before = snapshot(db_path_str);

    let uuid = account_id.expose_uuid().to_string();
    let projected =
        keys::get_address_from_db(db_path_str, WalletNetwork::Main, Some(&uuid)).unwrap();
    assert_eq!(projected, orchard_projection(&ufvk, renewed_index));
    assert_same_orchard_receiver(&old_displayed, &projected);
    assert_eq!(snapshot(db_path_str), before);
}

#[test]
fn legacy_receive_address_ignores_later_swap_reservations() {
    let seed = SecretVec::new(vec![73; 32]);
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path_str = db_path.to_str().unwrap();
    let mut old_db = old_wallet(db_path_str);
    let account_id = create_old_software_account(&mut old_db, &seed, "old mixed requests");
    old_db
        .update_chain_tip(BlockHeight::from_u32(2_500_000))
        .unwrap();
    let (receive, _) = old_db
        .get_next_available_address(account_id, legacy_software_request())
        .unwrap()
        .unwrap();
    old_db
        .update_chain_tip(BlockHeight::from_u32(2_500_001))
        .unwrap();
    let (latest_orchard, _) = old_db
        .get_next_available_address(account_id, orchard_only_request())
        .unwrap()
        .unwrap();
    drop(old_db);
    let before = snapshot(db_path_str);

    let uuid = account_id.expose_uuid().to_string();
    assert_eq!(
        keys::get_address_from_db(db_path_str, WalletNetwork::Main, Some(&uuid)).unwrap(),
        crate::wallet::addresses::orchard_projection(&receive, WalletNetwork::Main).unwrap()
    );
    assert_ne!(
        keys::get_address_from_db(db_path_str, WalletNetwork::Main, Some(&uuid)).unwrap(),
        latest_orchard.encode(&WalletNetwork::Main)
    );
    assert_eq!(snapshot(db_path_str), before);
}

#[test]
fn old_software_and_hardware_accounts_are_projected_independently() {
    let software_seed = SecretVec::new(vec![19; 32]);
    let hardware_seed = SecretVec::new(vec![91; 32]);
    let software_ufvk = account_ufvk(&software_seed);
    let hardware_ufvk = hardware_ufvk(&hardware_seed);
    let software_index = software_ufvk
        .default_address(legacy_software_request())
        .unwrap()
        .1;
    let hardware_index = hardware_ufvk
        .default_address(orchard_only_request())
        .unwrap()
        .1;

    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path_str = db_path.to_str().unwrap();
    let mut old_db = old_wallet(db_path_str);
    let software_id = create_old_software_account(&mut old_db, &software_seed, "old software");
    let hardware_id = old_db
        .import_account_ufvk(
            "old hardware",
            &hardware_ufvk,
            &old_birthday(),
            AccountPurpose::Spending { derivation: None },
            Some("vizor.hardware.keystone.v1"),
        )
        .unwrap()
        .id();
    let old_software = old_current_address(
        &old_db,
        software_id,
        &software_ufvk,
        legacy_software_request(),
    );
    let old_hardware =
        old_current_address(&old_db, hardware_id, &hardware_ufvk, orchard_only_request());
    drop(old_db);
    let before = snapshot(db_path_str);

    let software_uuid = software_id.expose_uuid().to_string();
    let hardware_uuid = hardware_id.expose_uuid().to_string();
    let new_software =
        keys::get_address_from_db(db_path_str, WalletNetwork::Main, Some(&software_uuid)).unwrap();
    let new_hardware =
        keys::get_address_from_db(db_path_str, WalletNetwork::Main, Some(&hardware_uuid)).unwrap();

    assert_eq!(
        new_software,
        orchard_projection(&software_ufvk, software_index)
    );
    assert_eq!(
        new_hardware,
        orchard_projection(&hardware_ufvk, hardware_index)
    );
    assert_same_orchard_receiver(&old_software, &new_software);
    assert_eq!(old_hardware, new_hardware);
    assert_ne!(new_software, new_hardware);
    assert_eq!(snapshot(db_path_str), before);

    assert_eq!(
        keys::get_address_from_db(db_path_str, WalletNetwork::Main, Some(&software_uuid),).unwrap(),
        new_software
    );
    assert_eq!(
        keys::get_address_from_db(db_path_str, WalletNetwork::Main, Some(&hardware_uuid),).unwrap(),
        new_hardware
    );
    assert_eq!(snapshot(db_path_str), before);
}

#[test]
fn old_default_survives_transparent_alias_exposed_at_birthday_without_writes() {
    let (seed, ufvk, legacy_index) = (1u8..=u8::MAX)
        .find_map(|marker| {
            let seed = SecretVec::new(vec![marker; 32]);
            let ufvk = account_ufvk(&seed);
            let (_, index) = ufvk.default_address(legacy_software_request()).ok()?;
            (index != DiversifierIndex::new()).then_some((seed, ufvk, index))
        })
        .unwrap();
    let stored_default = ufvk
        .default_address(UnifiedAddressRequest::AllAvailableKeys)
        .unwrap()
        .0
        .encode(&WalletNetwork::Main);

    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path_str = db_path.to_str().unwrap();
    let mut old_db = old_wallet(db_path_str);
    let account_id = create_old_software_account(&mut old_db, &seed, "old exposed alias");
    let alias = old_db
        .get_address_for_index(
            account_id,
            DiversifierIndex::new(),
            orchard_transparent_request(),
        )
        .unwrap()
        .unwrap();
    let alias = alias.encode(&WalletNetwork::Main);
    let old_displayed = old_current_address(&old_db, account_id, &ufvk, legacy_software_request());
    drop(old_db);

    let conn = rusqlite::Connection::open(db_path_str).unwrap();
    assert!(address_row_id(&conn, &stored_default) < address_row_id(&conn, &alias));
    drop(conn);
    let before = snapshot(db_path_str);
    let uuid = account_id.expose_uuid().to_string();

    let projected =
        keys::get_address_from_db(db_path_str, WalletNetwork::Main, Some(&uuid)).unwrap();
    assert_eq!(projected, orchard_projection(&ufvk, legacy_index));
    assert_same_orchard_receiver(&old_displayed, &projected);
    assert_eq!(snapshot(db_path_str), before);
}

#[test]
fn old_default_survives_received_transparent_alias_without_writes() {
    let (seed, ufvk, legacy_index) = (1u8..=u8::MAX)
        .find_map(|marker| {
            let seed = SecretVec::new(vec![marker; 32]);
            let ufvk = account_ufvk(&seed);
            let (_, index) = ufvk.default_address(legacy_software_request()).ok()?;
            (index != DiversifierIndex::new()).then_some((seed, ufvk, index))
        })
        .unwrap();

    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path_str = db_path.to_str().unwrap();
    let mut old_db = old_wallet(db_path_str);
    let account_id = create_old_software_account(&mut old_db, &seed, "old funded alias");
    let birthday = old_birthday().height();
    old_db.update_chain_tip(birthday + 100).unwrap();
    let alias = ufvk
        .address(DiversifierIndex::new(), orchard_transparent_request())
        .unwrap();
    let utxo = zcash_client_backend::wallet::WalletTransparentOutput::from_parts(
        transparent::bundle::OutPoint::new([42; 32], 0),
        transparent::bundle::TxOut::new(
            zcash_protocol::value::Zatoshis::const_from_u64(100_000),
            alias.transparent().unwrap().script().into(),
        ),
        Some(birthday - 1),
        Some(account_id),
        Some(transparent::keys::TransparentKeyScope::EXTERNAL),
        None,
    )
    .unwrap();
    old_db.put_received_transparent_utxo(&utxo).unwrap();
    let old_displayed = old_current_address(&old_db, account_id, &ufvk, legacy_software_request());
    drop(old_db);
    let before = snapshot(db_path_str);
    let uuid = account_id.expose_uuid().to_string();

    let projected =
        keys::get_address_from_db(db_path_str, WalletNetwork::Main, Some(&uuid)).unwrap();
    assert_eq!(projected, orchard_projection(&ufvk, legacy_index));
    assert_same_orchard_receiver(&old_displayed, &projected);
    assert_eq!(snapshot(db_path_str), before);
}

#[test]
fn new_orchard_default_survives_later_transparent_alias_exposure() {
    // The library's stored default can have a different index from a freshly
    // derived Orchard-only default. Creation and subsequent reads must agree.
    let seed = (1u8..=u8::MAX)
        .map(|marker| SecretVec::new(vec![marker; 32]))
        .find(|seed| {
            account_ufvk(seed)
                .default_address(UnifiedAddressRequest::AllAvailableKeys)
                .unwrap()
                .1
                != DiversifierIndex::new()
        })
        .unwrap();
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path_str = db_path.to_str().unwrap();
    let (uuid, issued) = keys::init_db_and_create_account(
        db_path_str,
        WalletNetwork::Main,
        &seed,
        None,
        "new Orchard default",
    )
    .unwrap();
    assert_eq!(
        issued,
        orchard_projection(&account_ufvk(&seed), DiversifierIndex::new())
    );
    let account_id = keys::parse_account_uuid(&uuid).unwrap();

    let mut alias_index = account_ufvk(&seed)
        .default_address(UnifiedAddressRequest::AllAvailableKeys)
        .unwrap()
        .1;
    alias_index.increment().unwrap();
    let mut db = old_wallet(db_path_str);
    let alias = db
        .get_address_for_index(account_id, alias_index, orchard_transparent_request())
        .unwrap()
        .unwrap();
    let alias = alias.encode(&WalletNetwork::Main);
    drop(db);

    let conn = rusqlite::Connection::open(db_path_str).unwrap();
    let issued_row: i64 = conn
        .query_row(
            "SELECT MIN(id) FROM addresses WHERE account_id = \
             (SELECT id FROM accounts WHERE uuid = ?1) AND key_scope = 0",
            [account_id.expose_uuid().as_bytes().as_slice()],
            |row| row.get(0),
        )
        .unwrap();
    assert!(issued_row < address_row_id(&conn, &alias));
    drop(conn);
    let before = snapshot(db_path_str);

    let displayed =
        keys::get_address_from_db(db_path_str, WalletNetwork::Main, Some(&uuid)).unwrap();
    assert_eq!(displayed, issued);
    let Address::Unified(displayed) = Address::decode(&WalletNetwork::Main, &displayed).unwrap()
    else {
        panic!("new address is not unified");
    };
    assert!(displayed.has_orchard());
    assert!(!displayed.has_sapling());
    assert!(!displayed.has_transparent());
    assert_eq!(snapshot(db_path_str), before);
    assert_eq!(
        keys::get_address_from_db(db_path_str, WalletNetwork::Main, Some(&uuid)).unwrap(),
        issued
    );
    assert_eq!(snapshot(db_path_str), before);
}

#[test]
fn software_renewal_remains_current_after_reservation_and_reopen() {
    use crate::wallet::addresses::{get_next_available_address, AddressRequestKind};
    let seed = SecretVec::new(vec![73; 32]);
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db");
    let path = path.to_str().unwrap();
    let (uuid, initial) =
        keys::init_db_and_create_account(path, WalletNetwork::Main, &seed, None, "software")
            .unwrap();
    crate::wallet::sync::update_chain_tip(path, WalletNetwork::Main, 2_500_000).unwrap();
    let renewed = get_next_available_address(
        path,
        WalletNetwork::Main,
        &uuid,
        AddressRequestKind::Shielded,
    )
    .unwrap();
    assert_ne!(initial, renewed);
    let reservation = get_next_available_address(
        path,
        WalletNetwork::Main,
        &uuid,
        AddressRequestKind::Orchard,
    )
    .unwrap();
    assert_ne!(renewed, reservation);
    assert_eq!(
        keys::get_address_from_db(path, WalletNetwork::Main, Some(&uuid)).unwrap(),
        renewed
    );
    assert_eq!(
        keys::list_accounts(path, WalletNetwork::Main).unwrap()[0].unified_address,
        renewed
    );
    let conn = rusqlite::Connection::open(path).unwrap();
    for address in [&renewed, &reservation] {
        let stored: String = conn
            .query_row(
                "SELECT address FROM addresses WHERE address = ?1",
                [address],
                |row| row.get(0),
            )
            .unwrap();
        let Address::Unified(ua) = Address::decode(&WalletNetwork::Main, &stored).unwrap() else {
            panic!("not unified")
        };
        assert!(ua.has_orchard());
        assert!(!ua.has_sapling());
        assert!(ua.transparent().is_none());
    }
    let again = get_next_available_address(
        path,
        WalletNetwork::Main,
        &uuid,
        AddressRequestKind::Shielded,
    )
    .unwrap();
    assert_ne!(again, renewed);
    assert_ne!(again, reservation);
    assert_eq!(
        keys::get_address_from_db(path, WalletNetwork::Main, Some(&uuid)).unwrap(),
        again
    );
}

#[test]
fn failed_receive_record_rolls_back_address_issuance() {
    use crate::wallet::addresses::{get_next_available_address, AddressRequestKind};
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db");
    let path = path.to_str().unwrap();
    let seed = SecretVec::new(vec![73; 32]);
    let (uuid, initial) =
        keys::init_db_and_create_account(path, WalletNetwork::Main, &seed, None, "software")
            .unwrap();
    crate::wallet::sync::update_chain_tip(path, WalletNetwork::Main, 2_500_000).unwrap();
    let before = snapshot(path);
    let conn = rusqlite::Connection::open(path).unwrap();
    conn.execute_batch("CREATE TRIGGER reject_receive_update BEFORE UPDATE ON ext_vizor_receive_addresses BEGIN SELECT RAISE(ABORT, 'test write failure'); END").unwrap();
    assert!(get_next_available_address(
        path,
        WalletNetwork::Main,
        &uuid,
        AddressRequestKind::Shielded
    )
    .is_err());
    assert_eq!(snapshot(path), before);
    assert_eq!(
        keys::get_address_from_db(path, WalletNetwork::Main, Some(&uuid)).unwrap(),
        initial
    );
}

#[test]
fn legacy_hardware_receive_survives_new_reservations_and_renewal() {
    use crate::wallet::addresses::{get_next_available_address, AddressRequestKind};
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db");
    let path = path.to_str().unwrap();
    let mut db = old_wallet(path);
    init_wallet_db(&mut db, None).unwrap();
    let ufvk = hardware_ufvk(&SecretVec::new(vec![91; 32]));
    let id = db
        .import_account_ufvk(
            "hardware",
            &ufvk,
            &old_birthday(),
            AccountPurpose::Spending { derivation: None },
            Some("vizor.hardware.keystone.v1"),
        )
        .unwrap()
        .id();
    db.update_chain_tip(BlockHeight::from_u32(2_500_000))
        .unwrap();
    let initial = old_current_address(&db, id, &ufvk, orchard_only_request());
    drop(db);
    let uuid = id.expose_uuid().to_string();
    get_next_available_address(
        path,
        WalletNetwork::Main,
        &uuid,
        AddressRequestKind::Orchard,
    )
    .unwrap();
    assert_eq!(
        keys::get_address_from_db(path, WalletNetwork::Main, Some(&uuid)).unwrap(),
        initial
    );
    let renewed = get_next_available_address(
        path,
        WalletNetwork::Main,
        &uuid,
        AddressRequestKind::Shielded,
    )
    .unwrap();
    get_next_available_address(
        path,
        WalletNetwork::Main,
        &uuid,
        AddressRequestKind::Orchard,
    )
    .unwrap();
    assert_eq!(
        keys::get_address_from_db(path, WalletNetwork::Main, Some(&uuid)).unwrap(),
        renewed
    );
}

#[test]
fn imported_account_tracks_its_receive_address_and_cleans_up_on_deletion() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db");
    let path = path.to_str().unwrap();
    let first_seed = SecretVec::new(vec![73; 32]);
    let second_seed = SecretVec::new(vec![91; 32]);
    let (first, initial) =
        keys::init_db_and_create_account(path, WalletNetwork::Main, &first_seed, None, "first")
            .unwrap();
    let (second, imported) =
        keys::add_account(path, WalletNetwork::Main, "second", &second_seed, None).unwrap();
    assert_eq!(
        imported,
        orchard_projection(&account_ufvk(&second_seed), DiversifierIndex::new())
    );
    assert_eq!(
        keys::get_address_from_db(path, WalletNetwork::Main, Some(&second)).unwrap(),
        imported
    );
    let db = old_wallet(path);
    let account = db
        .get_account(keys::parse_account_uuid(&second).unwrap())
        .unwrap()
        .unwrap();
    assert!(account.ufvk().unwrap().sapling().is_some());
    drop(db);
    keys::delete_account(path, WalletNetwork::Main, &second).unwrap();
    let conn = rusqlite::Connection::open(path).unwrap();
    let remaining: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ext_vizor_receive_addresses",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(remaining, 1);
    assert_eq!(
        keys::get_address_from_db(path, WalletNetwork::Main, Some(&first)).unwrap(),
        initial
    );
}
