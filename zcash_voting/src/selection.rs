//! Wallet note selection helpers for voting snapshots.

use std::borrow::Borrow;

use crate::storage::VotingDb;
use crate::{
    delegate::{load_account_keys, DelegationKeys},
    types::{Network, NoteInfo, NoteRef, SelectedNotes, VotingError, VotingHotkey},
};

use zcash_client_backend::{
    data_api::{wallet::ConfirmationsPolicy, Account, WalletRead},
    proto::service::TreeState,
};
use zcash_client_sqlite::util::SystemClock;
use zcash_client_sqlite::{AccountUuid, WalletDb};
use zcash_protocol::consensus::{BlockHeight, Parameters};

const POOL_ORCHARD: &str = "orchard";

/// Wallet-derived notes, anchor, and keys needed for delegation precompute.
#[derive(Clone, Debug)]
pub struct DelegationWalletInputs {
    pub anchor_tree_state_bytes: Vec<u8>,
    pub round_note_infos: Vec<NoteInfo>,
    pub delegation_keys: DelegationKeys,
}

/// Parameters for gathering delegation inputs from a caller-opened wallet DB.
pub struct GatherDelegationWalletParams<'a, C, P, CL, R> {
    pub wallet_db: &'a WalletDb<C, P, CL, R>,
    pub account_uuid: &'a str,
    pub voting_hotkey: &'a VotingHotkey,
    pub snapshot_height: u64,
    pub scanned_height: u64,
    pub anchor_tree_state_bytes: Vec<u8>,
    pub resolved_round_name: String,
}

/// Selects voting-eligible Orchard notes using a caller-opened wallet DB and anchor.
///
/// Fetch the anchor tree state first, then open the wallet once and pass it
/// here. The handle must not be held across an `.await` in async callers because
/// it is not [`Send`].
///
/// # Errors
///
/// Returns an error if the wallet DB network does not match `network`, the
/// wallet is not scanned through `snapshot_height`, or note selection fails.
pub fn select_notes_with_wallet_db<C, P, CL, R>(
    wallet_db: &WalletDb<C, P, CL, R>,
    network: Network,
    account_uuid: &str,
    snapshot_height: u64,
    anchor_tree_state: TreeState,
) -> Result<SelectedNotes, VotingError>
where
    C: Borrow<rusqlite::Connection>,
    P: Parameters,
{
    ensure_wallet_network(wallet_db.params(), network)?;
    ensure_wallet_scanned_to_snapshot(wallet_db, snapshot_height)?;
    select_snapshot_notes(wallet_db, account_uuid, snapshot_height, anchor_tree_state)
}

/// Selects voting-eligible Orchard notes and fetches the real snapshot anchor.
///
/// Fetches the anchor before opening the wallet database so async API futures
/// do not hold a non-`Send` database handle across an `.await`.
///
/// # Errors
///
/// Returns an error if lightwalletd cannot provide the snapshot anchor, the
/// wallet DB cannot be opened, or [`select_notes_with_wallet_db`] fails.
pub async fn select_notes_with_lwd(
    voting_db: &VotingDb,
    db_path: &str,
    lightwalletd_url: &str,
    network: Network,
    snapshot_height: u64,
) -> Result<SelectedNotes, VotingError> {
    let wallet_id = voting_db.wallet_id();
    let anchor_tree_state =
        crate::lwd::anchor_tree_state_with_retry(lightwalletd_url, snapshot_height).await?;
    // Open after the await so async callers do not capture rusqlite state in
    // generated Send futures.
    let conn = rusqlite::Connection::open(db_path).map_err(|e| VotingError::Internal {
        message: format!("failed to open wallet database: {e}"),
    })?;
    let wallet_db = WalletDb::from_connection(conn, network, SystemClock, rand::rngs::OsRng);
    select_notes_with_wallet_db(
        &wallet_db,
        network,
        &wallet_id,
        snapshot_height,
        anchor_tree_state,
    )
}

struct SnapshotNote {
    position: u64,
    output_index: u32,
    note_info: NoteInfo,
    note_ref: NoteRef,
}

/// Selects snapshot-eligible Orchard notes and returns wallet/display metadata
/// plus the caller-supplied anchor tree state.
pub fn select_snapshot_notes<C, P, CL, R>(
    db: &WalletDb<C, P, CL, R>,
    account_uuid: &str,
    snapshot_height: u64,
    anchor_tree_state: TreeState,
) -> Result<SelectedNotes, VotingError>
where
    C: Borrow<rusqlite::Connection>,
    P: Parameters,
{
    let entries = select_snapshot_note_entries(db, account_uuid, snapshot_height)?;
    Ok(SelectedNotes {
        notes: entries.into_iter().map(|entry| entry.note_ref).collect(),
        snapshot_height,
        anchor_tree_state,
    })
}

/// Selects snapshot-eligible Orchard notes in the proof-input shape.
pub fn select_snapshot_note_infos<C, P, CL, R>(
    db: &WalletDb<C, P, CL, R>,
    account_uuid: &str,
    snapshot_height: u64,
) -> Result<Vec<NoteInfo>, VotingError>
where
    C: Borrow<rusqlite::Connection>,
    P: Parameters,
{
    Ok(
        select_snapshot_note_entries(db, account_uuid, snapshot_height)?
            .into_iter()
            .map(|entry| entry.note_info)
            .collect(),
    )
}

/// Reads snapshot-eligible Orchard notes and delegation keys from a wallet DB.
///
/// # Errors
///
/// Returns [`VotingError::InvalidInput`] for malformed account IDs, missing
/// account/key material, a hotkey for the wrong network, empty note selections,
/// unsynced wallets, or snapshot heights outside the librustzcash height range.
/// Wallet DB read failures are returned as [`VotingError::Internal`].
pub fn gather_delegation_wallet_inputs<C, P, CL, R>(
    params: GatherDelegationWalletParams<'_, C, P, CL, R>,
) -> Result<DelegationWalletInputs, VotingError>
where
    C: Borrow<rusqlite::Connection>,
    P: Parameters,
{
    if params.scanned_height < params.snapshot_height {
        return Err(VotingError::InvalidInput {
            message: format!(
                "wallet is not synced to voting snapshot height {}. Fully scanned height is {}.",
                params.snapshot_height, params.scanned_height
            ),
        });
    }
    if params.wallet_db.params().network_type() != params.voting_hotkey.network().network_type() {
        return Err(VotingError::InvalidInput {
            message: "voting hotkey network does not match wallet DB network".to_string(),
        });
    }

    let round_note_infos = select_snapshot_note_infos(
        params.wallet_db,
        params.account_uuid,
        params.snapshot_height,
    )?;
    let account = load_account_keys(params.wallet_db, params.account_uuid)?;
    let delegation_keys = DelegationKeys::with_voting_hotkey(
        account.orchard_fvk_bytes.to_vec(),
        params.voting_hotkey,
        account.seed_fingerprint,
        account.account_index,
        params.resolved_round_name,
    )?;

    Ok(DelegationWalletInputs {
        anchor_tree_state_bytes: params.anchor_tree_state_bytes,
        round_note_infos,
        delegation_keys,
    })
}

fn select_snapshot_note_entries<C, P, CL, R>(
    db: &WalletDb<C, P, CL, R>,
    account_uuid: &str,
    snapshot_height: u64,
) -> Result<Vec<SnapshotNote>, VotingError>
where
    C: Borrow<rusqlite::Connection>,
    P: Parameters,
{
    let account_id = parse_account_uuid(account_uuid)?;
    let snapshot_block_height = u32::try_from(snapshot_height)
        .map(BlockHeight::from_u32)
        .map_err(|_| VotingError::InvalidInput {
            message: format!("snapshot height {snapshot_height} does not fit in u32"),
        })?;

    let account = db
        .get_account(account_id)
        .map_err(|e| VotingError::Internal {
            message: format!("failed to load voting account: {e}"),
        })?
        .ok_or_else(|| VotingError::InvalidInput {
            message: "voting account not found".to_string(),
        })?;
    let ufvk = account.ufvk().ok_or_else(|| VotingError::InvalidInput {
        message: "voting account has no UFVK".to_string(),
    })?;
    if ufvk.orchard().is_none() {
        return Err(VotingError::InvalidInput {
            message: "voting account has no Orchard viewing key".to_string(),
        });
    }

    let selected = db
        .get_unspent_orchard_notes_at_historical_height(account.id(), snapshot_block_height)
        .map_err(|e| VotingError::Internal {
            message: format!(
                "failed to select unspent Orchard voting notes at snapshot height: {e}"
            ),
        })?;
    let mut notes = Vec::new();
    for note in selected {
        let value = note.note().value().inner();
        let position = u64::from(note.note_commitment_tree_position());
        let output_index: u32 = note.output_index().into();
        let note_info = NoteInfo::from_orchard_note(
            note.note(),
            position,
            note.spending_key_scope(),
            ufvk,
            db.params(),
        )?;
        let note_ref = NoteRef {
            pool: POOL_ORCHARD.to_string(),
            txid_hex: note.txid().to_string(),
            output_index,
            value_zatoshi: value,
            voting_weight_zatoshi: value,
            commitment: note_info.commitment.clone(),
            nullifier: note_info.nullifier.clone(),
            diversifier: note_info.diversifier.clone(),
            rho: note_info.rho.clone(),
            rseed: note_info.rseed.clone(),
            scope: note_info.scope,
            ufvk_str: note_info.ufvk_str.clone(),
            commitment_tree_position: position,
            mined_height: note
                .mined_height()
                .map(u32::from)
                .ok_or_else(|| VotingError::Internal {
                    message: format!("selected voting note is unmined: {}", note.txid()),
                })?
                .into(),
            anchor_height: snapshot_height,
        };
        notes.push(SnapshotNote {
            position,
            output_index,
            note_info,
            note_ref,
        });
    }

    notes.sort_by(|a, b| {
        a.position
            .cmp(&b.position)
            .then_with(|| a.output_index.cmp(&b.output_index))
    });
    if notes.is_empty() {
        return Err(VotingError::InvalidInput {
            message: format!("no spendable voting notes at snapshot height {snapshot_height}"),
        });
    }

    Ok(notes)
}

fn ensure_wallet_network<P>(wallet_network: &P, network: Network) -> Result<(), VotingError>
where
    P: Parameters,
{
    if wallet_network.network_type() == network.network_type() {
        Ok(())
    } else {
        Err(VotingError::InvalidInput {
            message: format!(
                "wallet network {:?} does not match voting network {:?}",
                wallet_network.network_type(),
                network.network_type()
            ),
        })
    }
}

fn ensure_wallet_scanned_to_snapshot<C, P, CL, R>(
    wallet_db: &WalletDb<C, P, CL, R>,
    snapshot_height: u64,
) -> Result<(), VotingError>
where
    C: Borrow<rusqlite::Connection>,
    P: Parameters,
{
    let scanned_height = match wallet_db
        .get_wallet_summary(ConfirmationsPolicy::default())
        .map_err(|e| VotingError::Internal {
            message: format!("failed to load wallet summary: {e}"),
        })? {
        Some(summary) => u32::from(summary.fully_scanned_height()) as u64,
        None => 0,
    };
    if scanned_height >= snapshot_height {
        Ok(())
    } else {
        Err(VotingError::InvalidInput {
            message: format!(
                "wallet is not synced to voting snapshot height {snapshot_height}. Fully scanned height is {scanned_height}."
            ),
        })
    }
}

fn parse_account_uuid(account_uuid: &str) -> Result<AccountUuid, VotingError> {
    let uuid = uuid::Uuid::parse_str(account_uuid).map_err(|e| VotingError::InvalidInput {
        message: format!("invalid account UUID: {e}"),
    })?;
    Ok(AccountUuid::from_uuid(uuid))
}

#[cfg(test)]
mod tests {
    use super::*;

    use orchard::{
        note::{RandomSeed, Rho},
        value::NoteValue,
    };
    use rusqlite::{params, Connection};
    use secrecy::{ExposeSecret, SecretVec};
    use zcash_client_backend::data_api::{chain::ChainState, AccountBirthday, WalletWrite};
    use zcash_client_sqlite::{util::SystemClock, wallet::init::init_wallet_db};
    use zcash_primitives::block::BlockHash;
    use zcash_protocol::consensus::{NetworkUpgrade, Parameters};
    use zip32::Scope;

    #[test]
    fn select_snapshot_notes_returns_snapshot_eligible_orchard_notes() {
        let network = crate::Network::Regtest;
        let snapshot_height = 12;
        let divisor = crate::governance::BALLOT_DIVISOR;
        let mut conn = Connection::open_in_memory().unwrap();
        let (account_uuid, orchard_fvk) = setup_test_account(&mut conn, network);
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

        mark_scanned_through(&conn, 0, snapshot_height);
        let db = WalletDb::from_connection(&conn, network, SystemClock, rand::rngs::OsRng);
        let selected = select_notes_with_wallet_db(
            &db,
            network,
            &account_uuid.expose_uuid().to_string(),
            snapshot_height,
            placeholder_tree_state(snapshot_height),
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
        assert_eq!(selected.notes[2].commitment_tree_position, 8);
        assert_eq!(selected.notes[2].value_zatoshi, divisor - 1);
        assert_eq!(crate::voting_power(&selected), divisor * 4);
        assert!(selected.notes.iter().all(|note| note.pool == POOL_ORCHARD));
        assert!(selected.notes.iter().all(|note| note.scope == 0));
        assert!(selected.notes.iter().all(|note| !note.ufvk_str.is_empty()));
    }

    #[test]
    fn select_notes_with_wallet_db_keeps_sub_divisor_notes_for_smart_bundles() {
        let network = crate::Network::Regtest;
        let snapshot_height = 12;
        let divisor = crate::governance::BALLOT_DIVISOR;
        let mut conn = Connection::open_in_memory().unwrap();
        let (account_uuid, orchard_fvk) = setup_test_account(&mut conn, network);
        let account_ref = account_internal_id(&conn, &account_uuid);
        let note_value = (divisor / crate::governance::BUNDLE_NOTE_SLOTS as u64) + 1;

        for note_tag in 1..=crate::governance::BUNDLE_NOTE_SLOTS {
            insert_orchard_note(
                &conn,
                account_ref,
                &orchard_fvk,
                note_tag as u8,
                10,
                note_value,
                note_tag as u64,
            );
        }

        mark_scanned_through(&conn, 0, snapshot_height);
        let db = WalletDb::from_connection(&conn, network, SystemClock, rand::rngs::OsRng);
        let selected = select_notes_with_wallet_db(
            &db,
            network,
            &account_uuid.expose_uuid().to_string(),
            snapshot_height,
            placeholder_tree_state(snapshot_height),
        )
        .unwrap();

        assert_eq!(selected.notes.len(), crate::governance::BUNDLE_NOTE_SLOTS);
        assert!(selected
            .notes
            .iter()
            .all(|note| note.value_zatoshi < divisor));
        assert_eq!(crate::voting_power(&selected), divisor);
    }

    #[test]
    fn select_notes_with_wallet_db_rejects_unsynced_wallet() {
        let network = crate::Network::Regtest;
        let snapshot_height = 12;
        let mut conn = Connection::open_in_memory().unwrap();
        let (account_uuid, orchard_fvk) = setup_test_account(&mut conn, network);
        let account_ref = account_internal_id(&conn, &account_uuid);
        insert_orchard_note(&conn, account_ref, &orchard_fvk, 1, 10, 1, 3);

        mark_scanned_through(&conn, 0, snapshot_height - 1);
        let db = WalletDb::from_connection(&conn, network, SystemClock, rand::rngs::OsRng);
        let err = select_notes_with_wallet_db(
            &db,
            network,
            &account_uuid.expose_uuid().to_string(),
            snapshot_height,
            placeholder_tree_state(snapshot_height),
        )
        .unwrap_err()
        .to_string();

        assert!(err.contains("wallet is not synced to voting snapshot height 12"));
    }

    #[test]
    fn select_notes_with_wallet_db_rejects_network_mismatch() {
        let wallet_network = crate::Network::Regtest;
        let snapshot_height = 12;
        let mut conn = Connection::open_in_memory().unwrap();
        let (account_uuid, orchard_fvk) = setup_test_account(&mut conn, wallet_network);
        let account_ref = account_internal_id(&conn, &account_uuid);
        insert_orchard_note(&conn, account_ref, &orchard_fvk, 1, 10, 1, 3);

        mark_scanned_through(&conn, 0, snapshot_height);
        let db = WalletDb::from_connection(&conn, wallet_network, SystemClock, rand::rngs::OsRng);
        let err = select_notes_with_wallet_db(
            &db,
            crate::Network::Mainnet,
            &account_uuid.expose_uuid().to_string(),
            snapshot_height,
            placeholder_tree_state(snapshot_height),
        )
        .unwrap_err()
        .to_string();

        assert!(err.contains("does not match voting network"));
    }

    #[test]
    fn select_snapshot_note_infos_returns_sorted_snapshot_note_inputs() {
        let network = crate::Network::Regtest;
        let snapshot_height = 12;
        let divisor = crate::governance::BALLOT_DIVISOR;
        let mut conn = Connection::open_in_memory().unwrap();
        let (account_uuid, orchard_fvk) = setup_test_account(&mut conn, network);
        let account_ref = account_internal_id(&conn, &account_uuid);

        insert_orchard_note(&conn, account_ref, &orchard_fvk, 1, 10, divisor, 9);
        insert_orchard_note(&conn, account_ref, &orchard_fvk, 2, 10, divisor * 2, 4);
        insert_orchard_note(&conn, account_ref, &orchard_fvk, 3, 16, divisor * 3, 1);

        let db = WalletDb::from_connection(&conn, network, SystemClock, rand::rngs::OsRng);
        let notes = select_snapshot_note_infos(
            &db,
            &account_uuid.expose_uuid().to_string(),
            snapshot_height,
        )
        .unwrap();

        assert_eq!(notes.len(), 2);
        assert_eq!(notes[0].position, 4);
        assert_eq!(notes[0].value, divisor * 2);
        assert_eq!(notes[1].position, 9);
        assert_eq!(notes[1].value, divisor);
        assert!(notes.iter().all(|note| note.commitment.len() == 32));
        assert!(notes.iter().all(|note| note.nullifier.len() == 32));
        assert!(notes.iter().all(|note| note.scope == 0));
        assert!(notes.iter().all(|note| !note.ufvk_str.is_empty()));
    }

    #[test]
    fn select_snapshot_notes_rejects_empty_snapshot() {
        let network = crate::Network::Regtest;
        let snapshot_height = 12;
        let mut conn = Connection::open_in_memory().unwrap();
        let (account_uuid, _) = setup_test_account(&mut conn, network);
        mark_scanned_through(&conn, 0, snapshot_height);
        let db = WalletDb::from_connection(&conn, network, SystemClock, rand::rngs::OsRng);

        let err = select_notes_with_wallet_db(
            &db,
            network,
            &account_uuid.expose_uuid().to_string(),
            snapshot_height,
            placeholder_tree_state(snapshot_height),
        )
        .unwrap_err()
        .to_string();

        assert!(err.contains("no spendable voting notes at snapshot height 12"));
    }

    #[test]
    fn select_snapshot_note_infos_rejects_snapshot_heights_that_do_not_fit() {
        let db = WalletDb::from_connection(
            rusqlite::Connection::open_in_memory().unwrap(),
            crate::Network::Regtest,
            SystemClock,
            rand::rngs::OsRng,
        );

        let err = select_snapshot_note_infos(
            &db,
            "550e8400-e29b-41d4-a716-446655440000",
            u64::from(u32::MAX) + 1,
        )
        .unwrap_err()
        .to_string();

        assert!(err.contains("does not fit in u32"));
    }

    fn placeholder_tree_state(snapshot_height: u64) -> TreeState {
        TreeState {
            network: "test".to_string(),
            height: snapshot_height,
            hash: String::new(),
            time: 0,
            sapling_tree: String::new(),
            orchard_tree: String::new(),
        }
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

    fn mark_scanned_through(conn: &Connection, start_height: u32, scanned_height: u64) {
        let scanned_height = u32::try_from(scanned_height).unwrap();
        conn.execute("DELETE FROM scan_queue", []).unwrap();
        conn.execute("DELETE FROM blocks", []).unwrap();
        conn.execute(
            "INSERT INTO scan_queue (block_range_start, block_range_end, priority)
             VALUES (?1, ?2, 10)",
            params![start_height, scanned_height + 1],
        )
        .unwrap();
        for height in start_height..=scanned_height {
            conn.execute(
                "INSERT INTO blocks (
                    height, hash, time, sapling_tree, sapling_commitment_tree_size,
                    orchard_commitment_tree_size, sapling_output_count, orchard_action_count
                 )
                 VALUES (?1, ?2, ?3, ?4, 0, 0, 0, 0)",
                params![height, [height as u8; 32], height, Vec::<u8>::new()],
            )
            .unwrap();
        }
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
        network: crate::Network,
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
}
