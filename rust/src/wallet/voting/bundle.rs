use std::borrow::Borrow;

use crate::wallet::{
    db::WalletDatabase,
    network::WalletNetwork,
    sync::{get_sync_progress_from_db, open_wallet_db_for_read},
};
use zcash_client_backend::proto::service::TreeState;
use zcash_client_sqlite::WalletDb;

pub use zcash_voting::{voting_power, NoteRef, SelectedNotes};

#[cfg(test)]
const POOL_ORCHARD: &str = "orchard";

/// Selects voting-eligible Orchard notes using a caller-opened wallet DB and anchor.
///
/// Fetch the anchor tree state first, then open the wallet once and pass it
/// here. The handle must not be held across an `.await` in async callers because
/// it is not [`Send`].
pub fn select_notes_with_wallet_db(
    wallet_db: &WalletDatabase,
    network: WalletNetwork,
    account_uuid: &str,
    snapshot_height: u64,
    anchor_tree_state: TreeState,
) -> Result<SelectedNotes, String> {
    ensure_wallet_scanned_to_snapshot(wallet_db, snapshot_height)?;
    select_notes_with_anchor_tree_state(
        wallet_db,
        network,
        account_uuid,
        snapshot_height,
        anchor_tree_state,
    )
}

/// Selects voting-eligible Orchard notes and fetches the real snapshot anchor.
///
/// Opens the wallet database twice internally. Callers that already have a wallet
/// handle should fetch the anchor state through `zcash_voting::lwd` plus
/// [`select_notes_with_wallet_db`] for a single open.
pub async fn select_notes_with_lwd(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    snapshot_height: u64,
) -> Result<SelectedNotes, String> {
    let anchor_tree_state =
        zcash_voting::lwd::anchor_tree_state_with_retry(lightwalletd_url, snapshot_height)
            .await
            .map_err(|e| e.to_string())?;
    let wallet_db = open_wallet_db_for_read(db_path, network)?;
    select_notes_with_wallet_db(
        &wallet_db,
        network,
        account_uuid,
        snapshot_height,
        anchor_tree_state,
    )
}

fn ensure_wallet_scanned_to_snapshot(
    wallet_db: &WalletDatabase,
    snapshot_height: u64,
) -> Result<(), String> {
    let progress = get_sync_progress_from_db(wallet_db)?;
    if progress.scanned_height >= snapshot_height {
        return Ok(());
    }
    Err(format!(
        "Wallet is not synced to voting snapshot height {snapshot_height}. Fully scanned height is {}.",
        progress.scanned_height
    ))
}

/// Selects voting-eligible Orchard notes with a caller-supplied anchor state.
pub fn select_notes_with_anchor_tree_state<C, CL, R>(
    wallet_db: &WalletDb<C, WalletNetwork, CL, R>,
    _network: WalletNetwork,
    account_uuid: &str,
    snapshot_height: u64,
    anchor_tree_state: TreeState,
) -> Result<SelectedNotes, String>
where
    C: Borrow<rusqlite::Connection>,
{
    zcash_voting::select_snapshot_notes(wallet_db, account_uuid, snapshot_height, anchor_tree_state)
        .map_err(|e| e.to_string())
}

/// Validates that `bundle_index` is in `[0, bundle_count)`.
pub(super) fn validate_bundle_index(
    bundle_count: u32,
    bundle_index: u32,
    bundle_kind: &str,
) -> Result<(), String> {
    if bundle_index < bundle_count {
        Ok(())
    } else {
        Err(format!(
            "bundle_index {bundle_index} is out of range for {bundle_count} {bundle_kind} bundles"
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn placeholder_tree_state(network: WalletNetwork, snapshot_height: u64) -> TreeState {
        TreeState {
            network: match network {
                WalletNetwork::Main => "main".to_string(),
                WalletNetwork::Test | WalletNetwork::Regtest => "test".to_string(),
            },
            height: snapshot_height,
            hash: String::new(),
            time: 0,
            sapling_tree: String::new(),
            orchard_tree: String::new(),
        }
    }
    use orchard::{
        note::{RandomSeed, Rho},
        value::NoteValue,
    };
    use rusqlite::{params, Connection};
    use secrecy::{ExposeSecret, SecretVec};
    use zcash_client_backend::data_api::{chain::ChainState, AccountBirthday, WalletWrite};
    use zcash_client_sqlite::{util::SystemClock, wallet::init::init_wallet_db, WalletDb};
    use zcash_primitives::block::BlockHash;
    use zcash_protocol::consensus::{NetworkUpgrade, Parameters};
    use zip32::Scope;

    #[test]
    fn validate_bundle_index_rejects_out_of_range_before_work() {
        assert!(validate_bundle_index(2, 0, "voting").is_ok());
        assert!(validate_bundle_index(2, 1, "voting").is_ok());
        assert!(validate_bundle_index(2, 2, "voting")
            .unwrap_err()
            .contains("out of range"));
        assert!(validate_bundle_index(0, 0, "delegation")
            .unwrap_err()
            .contains("0 delegation bundles"));
    }

    #[test]
    fn select_notes_from_in_memory_db_returns_snapshot_eligible_orchard_notes() {
        let network = WalletNetwork::Regtest;
        let snapshot_height = 12;
        let divisor = zcash_voting::governance::BALLOT_DIVISOR;
        let mut conn = Connection::open_in_memory().unwrap();
        let seed = SecretVec::new(vec![7u8; 32]);
        let (account_uuid, orchard_fvk) = {
            let mut db =
                WalletDb::from_connection(&mut conn, network, SystemClock, rand::rngs::OsRng);
            init_wallet_db(&mut db, Some(SecretVec::new(seed.expose_secret().to_vec()))).unwrap();

            let sapling_height = network
                .activation_height(NetworkUpgrade::Sapling)
                .expect("regtest has Sapling activation");
            let birthday = AccountBirthday::from_parts(
                ChainState::empty(sapling_height - 1, BlockHash([0; 32])),
                None,
            );
            let (account_uuid, usk) = db.create_account("voter", &seed, &birthday, None).unwrap();
            let orchard_fvk = usk
                .to_unified_full_viewing_key()
                .orchard()
                .expect("test account has Orchard viewing key")
                .clone();

            (account_uuid, orchard_fvk)
        };

        let account_ref = account_internal_id(&conn, &account_uuid);
        let selected_before_snapshot =
            insert_orchard_note(&conn, account_ref, &orchard_fvk, 1, 8, divisor, 3);
        let spent_after_snapshot_tx = insert_transaction(&conn, 11, 15);
        conn.execute(
            "INSERT INTO orchard_received_note_spends (orchard_received_note_id, transaction_id)
             VALUES (?1, ?2)",
            params![selected_before_snapshot, spent_after_snapshot_tx],
        )
        .unwrap();

        insert_orchard_note(&conn, account_ref, &orchard_fvk, 2, 10, divisor * 2 + 1, 7);
        insert_orchard_note(&conn, account_ref, &orchard_fvk, 3, 10, divisor - 1, 8);
        insert_orchard_note(&conn, account_ref, &orchard_fvk, 4, 16, divisor, 9);

        let spent_before_snapshot =
            insert_orchard_note(&conn, account_ref, &orchard_fvk, 5, 9, divisor * 3, 10);
        let spent_before_snapshot_tx = insert_transaction(&conn, 12, 11);
        conn.execute(
            "INSERT INTO orchard_received_note_spends (orchard_received_note_id, transaction_id)
             VALUES (?1, ?2)",
            params![spent_before_snapshot, spent_before_snapshot_tx],
        )
        .unwrap();

        let db = WalletDb::from_connection(&conn, network, SystemClock, rand::rngs::OsRng);
        let selected = select_notes_with_anchor_tree_state(
            &db,
            network,
            &account_uuid.expose_uuid().to_string(),
            snapshot_height,
            placeholder_tree_state(network, snapshot_height),
        )
        .unwrap();

        assert_eq!(selected.snapshot_height, snapshot_height);
        assert_eq!(selected.anchor_tree_state.height, snapshot_height);
        assert_eq!(selected.notes.len(), 3);
        assert_eq!(selected.notes[0].commitment_tree_position, 3);
        assert_eq!(selected.notes[0].mined_height, 8);
        assert_eq!(selected.notes[0].voting_weight_zatoshi, divisor);
        assert_eq!(selected.notes[1].commitment_tree_position, 7);
        assert_eq!(selected.notes[1].mined_height, 10);
        assert_eq!(selected.notes[1].value_zatoshi, divisor * 2 + 1);
        assert_eq!(selected.notes[1].voting_weight_zatoshi, divisor * 2 + 1);
        assert_eq!(selected.notes[2].commitment_tree_position, 8);
        assert_eq!(selected.notes[2].value_zatoshi, divisor - 1);
        assert_eq!(selected.notes[2].voting_weight_zatoshi, divisor - 1);
        assert_eq!(voting_power(&selected), divisor * 4);
        assert!(selected.notes.iter().all(|note| note.pool == POOL_ORCHARD));
        assert!(selected.notes.iter().all(|note| note.scope == 0));
        assert!(selected.notes.iter().all(|note| !note.ufvk_str.is_empty()));
    }

    #[test]
    fn select_notes_keeps_sub_divisor_notes_for_smart_bundles() {
        let network = WalletNetwork::Regtest;
        let snapshot_height = 12;
        let divisor = zcash_voting::governance::BALLOT_DIVISOR;
        let mut conn = Connection::open_in_memory().unwrap();
        let (account_uuid, orchard_fvk) = setup_test_account(&mut conn, network);
        let account_ref = account_internal_id(&conn, &account_uuid);

        for note_tag in 1..=5 {
            insert_orchard_note(
                &conn,
                account_ref,
                &orchard_fvk,
                note_tag,
                10,
                divisor / 5,
                u64::from(note_tag),
            );
        }

        let db = WalletDb::from_connection(&conn, network, SystemClock, rand::rngs::OsRng);
        let selected = select_notes_with_anchor_tree_state(
            &db,
            network,
            &account_uuid.expose_uuid().to_string(),
            snapshot_height,
            placeholder_tree_state(network, snapshot_height),
        )
        .unwrap();

        assert_eq!(selected.notes.len(), 5);
        assert!(selected
            .notes
            .iter()
            .all(|note| note.value_zatoshi < divisor));
        assert_eq!(voting_power(&selected), divisor);
    }

    #[test]
    fn select_notes_returns_structured_error_when_no_snapshot_notes() {
        let network = WalletNetwork::Regtest;
        let snapshot_height = 12;
        let mut conn = Connection::open_in_memory().unwrap();
        let (account_uuid, _) = setup_test_account(&mut conn, network);

        let db = WalletDb::from_connection(&conn, network, SystemClock, rand::rngs::OsRng);
        let err = select_notes_with_anchor_tree_state(
            &db,
            network,
            &account_uuid.expose_uuid().to_string(),
            snapshot_height,
            placeholder_tree_state(network, snapshot_height),
        )
        .unwrap_err();

        assert!(err.contains(&format!(
            "no spendable voting notes at snapshot height {snapshot_height}"
        )));
    }

    #[test]
    fn select_notes_sorts_deterministically_by_position_pool_and_output() {
        let selected = SelectedNotes {
            notes: vec![
                test_note_ref(POOL_ORCHARD, 10, 10)
                    .with_position(10)
                    .with_output_index(2),
                test_note_ref("sapling", 10, 10)
                    .with_position(10)
                    .with_output_index(9),
                test_note_ref(POOL_ORCHARD, 10, 10)
                    .with_position(10)
                    .with_output_index(1),
                test_note_ref(POOL_ORCHARD, 10, 10)
                    .with_position(11)
                    .with_output_index(0),
            ],
            snapshot_height: 100,
            anchor_tree_state: placeholder_tree_state(WalletNetwork::Regtest, 100),
        };

        let mut notes = selected.notes;
        notes.sort_by(|a, b| {
            a.commitment_tree_position
                .cmp(&b.commitment_tree_position)
                .then_with(|| a.pool.cmp(&b.pool))
                .then_with(|| a.output_index.cmp(&b.output_index))
        });

        assert_eq!(notes[0].pool, POOL_ORCHARD);
        assert_eq!(notes[0].output_index, 1);
        assert_eq!(notes[1].pool, POOL_ORCHARD);
        assert_eq!(notes[1].output_index, 2);
        assert_eq!(notes[2].pool, "sapling");
        assert_eq!(notes[3].commitment_tree_position, 11);
    }

    #[test]
    fn select_notes_rejects_snapshot_heights_that_do_not_fit_librustzcash() {
        let conn = Connection::open_in_memory().unwrap();
        let network = WalletNetwork::Regtest;
        let wallet_db = WalletDb::from_connection(&conn, network, SystemClock, rand::rngs::OsRng);
        let result = select_notes_with_anchor_tree_state(
            &wallet_db,
            network,
            "550e8400-e29b-41d4-a716-446655440000",
            u64::from(u32::MAX) + 1,
            placeholder_tree_state(network, u64::from(u32::MAX) + 1),
        );

        assert!(result.unwrap_err().contains("does not fit in u32"));
    }

    fn account_internal_id(
        conn: &Connection,
        account_uuid: &zcash_client_sqlite::AccountUuid,
    ) -> i64 {
        conn.query_row(
            "SELECT id FROM accounts WHERE uuid = ?1",
            params![account_uuid.expose_uuid().as_bytes()],
            |row| row.get(0),
        )
        .unwrap()
    }

    fn insert_transaction(conn: &Connection, txid_tag: u8, mined_height: u32) -> i64 {
        let txid = [txid_tag; 32];
        conn.execute(
            "INSERT INTO transactions (txid, mined_height, min_observed_height)
             VALUES (?1, ?2, ?3)",
            params![txid, mined_height, mined_height],
        )
        .unwrap();
        conn.last_insert_rowid()
    }

    fn insert_orchard_note(
        conn: &Connection,
        account_ref: i64,
        orchard_fvk: &orchard::keys::FullViewingKey,
        note_tag: u8,
        mined_height: u32,
        value_zatoshi: u64,
        commitment_tree_position: u64,
    ) -> i64 {
        let transaction_id = insert_transaction(conn, note_tag, mined_height);
        let note = test_orchard_note(orchard_fvk, note_tag, value_zatoshi);
        let nullifier = note.nullifier(orchard_fvk);

        conn.execute(
            "INSERT INTO orchard_received_notes (
                transaction_id, action_index, account_id, diversifier, value, rho, rseed,
                nf, is_change, commitment_tree_position, recipient_key_scope
             )
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 0, ?9, 0)",
            params![
                transaction_id,
                i64::from(note_tag),
                account_ref,
                note.recipient().diversifier().as_array(),
                value_zatoshi,
                note.rho().to_bytes(),
                note.rseed().as_bytes(),
                nullifier.to_bytes(),
                commitment_tree_position,
            ],
        )
        .unwrap();
        conn.last_insert_rowid()
    }

    fn setup_test_account(
        conn: &mut Connection,
        network: WalletNetwork,
    ) -> (
        zcash_client_sqlite::AccountUuid,
        orchard::keys::FullViewingKey,
    ) {
        let seed = SecretVec::new(vec![7u8; 32]);
        let mut db = WalletDb::from_connection(conn, network, SystemClock, rand::rngs::OsRng);
        init_wallet_db(&mut db, Some(SecretVec::new(seed.expose_secret().to_vec()))).unwrap();

        let sapling_height = network
            .activation_height(NetworkUpgrade::Sapling)
            .expect("regtest has Sapling activation");
        let birthday = AccountBirthday::from_parts(
            ChainState::empty(sapling_height - 1, BlockHash([0; 32])),
            None,
        );
        let (account_uuid, usk) = db.create_account("voter", &seed, &birthday, None).unwrap();
        let orchard_fvk = usk
            .to_unified_full_viewing_key()
            .orchard()
            .expect("test account has Orchard viewing key")
            .clone();

        (account_uuid, orchard_fvk)
    }

    fn test_orchard_note(
        orchard_fvk: &orchard::keys::FullViewingKey,
        note_tag: u8,
        value_zatoshi: u64,
    ) -> orchard::Note {
        let recipient = orchard_fvk.address_at(u64::from(note_tag), Scope::External);
        let rho = rho_from_nonce(u64::from(note_tag) + 1);

        for seed_nonce in 1..10_000 {
            let mut seed = [0u8; 32];
            seed[..8].copy_from_slice(&(seed_nonce + u64::from(note_tag) * 10_000).to_le_bytes());
            if let Some(rseed) = Option::<RandomSeed>::from(RandomSeed::from_bytes(seed, &rho)) {
                if let Some(note) = Option::<orchard::Note>::from(orchard::Note::from_parts(
                    recipient,
                    NoteValue::from_raw(value_zatoshi),
                    rho,
                    rseed,
                )) {
                    return note;
                }
            }
        }

        panic!("failed to generate valid Orchard note fixture");
    }

    fn rho_from_nonce(nonce: u64) -> Rho {
        let mut bytes = [0u8; 32];
        bytes[..8].copy_from_slice(&nonce.to_le_bytes());
        Option::<Rho>::from(Rho::from_bytes(&bytes))
            .expect("small integers are valid pallas base field elements")
    }

    fn test_note_ref(pool: &str, value_zatoshi: u64, voting_weight_zatoshi: u64) -> NoteRef {
        NoteRef {
            pool: pool.to_string(),
            txid_hex: hex::encode([0u8; 32]),
            output_index: 0,
            value_zatoshi,
            voting_weight_zatoshi,
            commitment: vec![0x01; 32],
            nullifier: vec![0x02; 32],
            diversifier: vec![0x03; 11],
            rho: vec![0x04; 32],
            rseed: vec![0x05; 32],
            scope: 0,
            ufvk_str: String::new(),
            commitment_tree_position: 0,
            mined_height: 1,
            anchor_height: 1,
        }
    }

    trait TestNoteRefExt {
        fn with_output_index(self, output_index: u32) -> Self;
        fn with_position(self, commitment_tree_position: u64) -> Self;
    }

    impl TestNoteRefExt for NoteRef {
        fn with_output_index(mut self, output_index: u32) -> Self {
            self.output_index = output_index;
            self
        }

        fn with_position(mut self, commitment_tree_position: u64) -> Self {
            self.commitment_tree_position = commitment_tree_position;
            self
        }
    }
}
