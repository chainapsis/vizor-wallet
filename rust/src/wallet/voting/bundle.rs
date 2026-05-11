use std::borrow::Borrow;

use orchard::note::ExtractedNoteCommitment as OrchardExtractedNoteCommitment;
use zcash_client_backend::{
    data_api::{Account, WalletRead},
    proto::service::TreeState,
};
use zcash_client_sqlite::WalletDb;
use zcash_protocol::consensus::BlockHeight;
use zip32::Scope;

use crate::wallet::{
    keys::parse_account_uuid, network::WalletNetwork, sync::open_wallet_db_for_read, sync_engine,
};

const POOL_ORCHARD: &str = "orchard";

/// A snapshot-eligible shielded note selected for voting.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NoteRef {
    pub pool: String,
    pub txid_hex: String,
    pub output_index: u32,
    pub value_zatoshi: u64,
    pub voting_weight_zatoshi: u64,
    pub commitment: Vec<u8>,
    pub nullifier: Vec<u8>,
    pub diversifier: Vec<u8>,
    pub rho: Vec<u8>,
    pub rseed: Vec<u8>,
    pub scope: u32,
    pub ufvk_str: String,
    pub commitment_tree_position: u64,
    pub mined_height: u64,
    pub anchor_height: u64,
}

impl NoteRef {
    /// Converts this wallet-selected note into the core voting note payload.
    pub fn to_voting_note_info(&self) -> zcash_voting::NoteInfo {
        zcash_voting::NoteInfo {
            commitment: self.commitment.clone(),
            nullifier: self.nullifier.clone(),
            value: self.value_zatoshi,
            position: self.commitment_tree_position,
            diversifier: self.diversifier.clone(),
            rho: self.rho.clone(),
            rseed: self.rseed.clone(),
            scope: self.scope,
            ufvk_str: self.ufvk_str.clone(),
        }
    }
}

/// Spendable notes at a voting snapshot, plus the anchor tree state for proofs.
#[derive(Clone, Debug)]
pub struct SelectedNotes {
    pub notes: Vec<NoteRef>,
    pub snapshot_height: u64,
    pub anchor_tree_state: TreeState,
}

impl SelectedNotes {
    /// Returns notes in the shape expected by `zcash_voting` bundling APIs.
    pub fn voting_note_infos(&self) -> Vec<zcash_voting::NoteInfo> {
        self.notes
            .iter()
            .map(NoteRef::to_voting_note_info)
            .collect()
    }
}

pub fn build_bundle(_voting_db: &zcash_voting::storage::VotingDb) -> ! {
    unimplemented!()
}

/// Selects voting-eligible shielded notes using a placeholder anchor state.
///
/// The Linear prototype signature does not include a lightwalletd URL, so callers
/// that need a real anchor should use [`select_notes_with_lwd`] instead.
pub fn select_notes(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    snapshot_height: u64,
) -> Result<SelectedNotes, String> {
    let anchor_tree_state = placeholder_tree_state(network, snapshot_height);
    select_notes_with_anchor_tree_state(
        db_path,
        network,
        account_uuid,
        snapshot_height,
        anchor_tree_state,
    )
}

/// Selects voting-eligible shielded notes and fetches the real snapshot anchor.
pub async fn select_notes_with_lwd(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    snapshot_height: u64,
) -> Result<SelectedNotes, String> {
    let mut client = sync_engine::open_lwd_channel(lightwalletd_url)
        .await
        .map_err(|e| e.to_string())?;
    let anchor_tree_state = sync_engine::get_tree_state(&mut client, snapshot_height)
        .await
        .map_err(|e| e.to_string())?;
    select_notes_with_anchor_tree_state(
        db_path,
        network,
        account_uuid,
        snapshot_height,
        anchor_tree_state,
    )
}

/// Selects voting-eligible shielded notes with a caller-supplied anchor state.
pub fn select_notes_with_anchor_tree_state(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    snapshot_height: u64,
    anchor_tree_state: TreeState,
) -> Result<SelectedNotes, String> {
    let db = open_wallet_db_for_read(db_path, network)?;
    select_notes_from_db(
        &db,
        network,
        account_uuid,
        snapshot_height,
        anchor_tree_state,
    )
}

fn select_notes_from_db<C, CL, R>(
    db: &WalletDb<C, WalletNetwork, CL, R>,
    network: WalletNetwork,
    account_uuid: &str,
    snapshot_height: u64,
    anchor_tree_state: TreeState,
) -> Result<SelectedNotes, String>
where
    C: Borrow<rusqlite::Connection>,
{
    let account_id = parse_account_uuid(account_uuid)?;
    let snapshot_height_u32 = u32::try_from(snapshot_height)
        .map_err(|_| format!("Snapshot height out of range: {snapshot_height}"))?;

    let mut notes = Vec::new();
    let account = db
        .get_account(account_id)
        .map_err(|e| format!("Failed to load voting account: {e}"))?
        .ok_or_else(|| "Voting account not found".to_string())?;
    let ufvk = account
        .ufvk()
        .ok_or_else(|| "Voting account has no UFVK".to_string())?;
    let orchard_fvk = ufvk
        .orchard()
        .ok_or_else(|| "Voting account has no Orchard viewing key".to_string())?;
    let ufvk_str = ufvk.encode(&network);

    let height = BlockHeight::from_u32(snapshot_height_u32);
    let selected = db
        .get_unspent_orchard_notes_at_historical_height(account.id(), height)
        .map_err(|e| {
            format!("Failed to select unspent Orchard voting notes at snapshot height: {e}")
        })?;

    for note in selected {
        let value = note.note().value().inner();
        if let Some(weight) = note_voting_weight(value) {
            let commitment: OrchardExtractedNoteCommitment = note.note().commitment().into();
            let nullifier = note.note().nullifier(orchard_fvk);
            let scope = match note.spending_key_scope() {
                Scope::External => 0,
                Scope::Internal => 1,
            };
            notes.push(NoteRef {
                pool: POOL_ORCHARD.to_string(),
                txid_hex: note.txid().to_string(),
                output_index: note.output_index().into(),
                value_zatoshi: value,
                voting_weight_zatoshi: weight,
                commitment: commitment.to_bytes().to_vec(),
                nullifier: nullifier.to_bytes().to_vec(),
                diversifier: note.note().recipient().diversifier().as_array().to_vec(),
                rho: note.note().rho().to_bytes().to_vec(),
                rseed: note.note().rseed().as_bytes().to_vec(),
                scope,
                ufvk_str: ufvk_str.clone(),
                commitment_tree_position: u64::from(note.note_commitment_tree_position()),
                mined_height: note
                    .mined_height()
                    .map(u32::from)
                    .ok_or_else(|| format!("Selected voting note is unmined: {}", note.txid()))?
                    .into(),
                anchor_height: snapshot_height,
            });
        }
    }

    notes.sort_by(|a, b| {
        a.commitment_tree_position
            .cmp(&b.commitment_tree_position)
            .then_with(|| a.pool.cmp(&b.pool))
            .then_with(|| a.output_index.cmp(&b.output_index))
    });

    if notes.is_empty() {
        return Err(format!(
            "No spendable voting notes at snapshot height {snapshot_height}"
        ));
    }

    Ok(SelectedNotes {
        notes,
        snapshot_height,
        anchor_tree_state,
    })
}

/// Returns quantized zatoshi voting power for the selected note set.
pub fn voting_power(notes: &SelectedNotes) -> u64 {
    notes
        .notes
        .iter()
        .map(|note| note.voting_weight_zatoshi)
        .sum()
}

fn note_voting_weight(value_zatoshi: u64) -> Option<u64> {
    let ballots = value_zatoshi / zcash_voting::governance::BALLOT_DIVISOR;
    (ballots > 0).then_some(ballots * zcash_voting::governance::BALLOT_DIVISOR)
}

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

    #[test]
    fn note_voting_weight_filters_and_quantizes_by_ballot_divisor() {
        let divisor = zcash_voting::governance::BALLOT_DIVISOR;

        assert_eq!(note_voting_weight(divisor - 1), None);
        assert_eq!(note_voting_weight(divisor), Some(divisor));
        assert_eq!(
            note_voting_weight(divisor * 2 + divisor - 1),
            Some(divisor * 2)
        );
    }

    #[test]
    fn voting_power_sums_post_divisor_values() {
        let divisor = zcash_voting::governance::BALLOT_DIVISOR;
        let selected = SelectedNotes {
            notes: vec![
                test_note_ref("sapling", divisor, divisor),
                test_note_ref(POOL_ORCHARD, divisor * 2 + 1, divisor * 2),
            ],
            snapshot_height: 100,
            anchor_tree_state: placeholder_tree_state(WalletNetwork::Regtest, 100),
        };

        assert_eq!(voting_power(&selected), divisor * 3);
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
        let selected = select_notes_from_db(
            &db,
            network,
            &account_uuid.expose_uuid().to_string(),
            snapshot_height,
            placeholder_tree_state(network, snapshot_height),
        )
        .unwrap();

        assert_eq!(selected.snapshot_height, snapshot_height);
        assert_eq!(selected.anchor_tree_state.height, snapshot_height);
        assert_eq!(selected.notes.len(), 2);
        assert_eq!(selected.notes[0].commitment_tree_position, 3);
        assert_eq!(selected.notes[0].mined_height, 8);
        assert_eq!(selected.notes[0].voting_weight_zatoshi, divisor);
        assert_eq!(selected.notes[1].commitment_tree_position, 7);
        assert_eq!(selected.notes[1].mined_height, 10);
        assert_eq!(selected.notes[1].value_zatoshi, divisor * 2 + 1);
        assert_eq!(selected.notes[1].voting_weight_zatoshi, divisor * 2);
        assert_eq!(voting_power(&selected), divisor * 3);
        assert!(selected.notes.iter().all(|note| note.pool == POOL_ORCHARD));
        assert!(selected.notes.iter().all(|note| note.scope == 0));
        assert!(selected.notes.iter().all(|note| !note.ufvk_str.is_empty()));
    }

    #[test]
    fn selected_notes_convert_to_voting_note_info() {
        let selected = SelectedNotes {
            notes: vec![NoteRef {
                pool: POOL_ORCHARD.to_string(),
                txid_hex: hex::encode([9u8; 32]),
                output_index: 2,
                value_zatoshi: 13_000_000,
                voting_weight_zatoshi: zcash_voting::governance::BALLOT_DIVISOR,
                commitment: vec![1; 32],
                nullifier: vec![2; 32],
                diversifier: vec![3; 11],
                rho: vec![4; 32],
                rseed: vec![5; 32],
                scope: 1,
                ufvk_str: "uviewtest".to_string(),
                commitment_tree_position: 42,
                mined_height: 100,
                anchor_height: 123,
            }],
            snapshot_height: 123,
            anchor_tree_state: placeholder_tree_state(WalletNetwork::Regtest, 123),
        };

        let infos = selected.voting_note_infos();

        assert_eq!(infos.len(), 1);
        assert_eq!(infos[0].value, 13_000_000);
        assert_eq!(infos[0].position, 42);
        assert_eq!(infos[0].commitment, vec![1; 32]);
        assert_eq!(infos[0].nullifier, vec![2; 32]);
        assert_eq!(infos[0].diversifier, vec![3; 11]);
        assert_eq!(infos[0].rho, vec![4; 32]);
        assert_eq!(infos[0].rseed, vec![5; 32]);
        assert_eq!(infos[0].scope, 1);
        assert_eq!(infos[0].ufvk_str, "uviewtest");
    }

    #[test]
    fn select_notes_rejects_snapshot_heights_that_do_not_fit_librustzcash() {
        let result = select_notes_with_anchor_tree_state(
            "/tmp/not-opened.sqlite",
            WalletNetwork::Regtest,
            "550e8400-e29b-41d4-a716-446655440000",
            u64::from(u32::MAX) + 1,
            placeholder_tree_state(WalletNetwork::Regtest, u64::from(u32::MAX) + 1),
        );

        assert!(result.unwrap_err().contains("Snapshot height out of range"));
    }

    #[test]
    #[should_panic(expected = "not implemented")]
    fn build_bundle_is_explicit_placeholder() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let db = zcash_voting::storage::VotingDb::open(db_path.to_str().unwrap()).unwrap();

        build_bundle(&db);
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
            commitment: vec![],
            nullifier: vec![],
            diversifier: vec![],
            rho: vec![],
            rseed: vec![],
            scope: 0,
            ufvk_str: String::new(),
            commitment_tree_position: 0,
            mined_height: 1,
            anchor_height: 1,
        }
    }
}
