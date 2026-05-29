/// Returns the sidecar path used for `zcash_voting` state for a wallet DB path.
///
/// The voting database is intentionally separate from the wallet SQLite file so
/// upstream voting migrations cannot affect the wallet DB `user_version`.
fn voting_db_path_for_wallet_db(db_path: &str) -> String {
    format!("{db_path}.voting")
}

/// Opens the voting sidecar database for a wallet and binds it to `wallet_id`.
///
/// `db_path` is the main wallet database path; the voting DB is opened at the
/// deterministic sidecar path returned by `voting_db_path_for_wallet_db`.
///
/// # Errors
///
/// Returns an error if the upstream voting database cannot be opened or
/// initialized.
pub fn open_voting_db(
    db_path: &str,
    wallet_id: &str,
) -> Result<zcash_voting::storage::VotingDb, String> {
    let voting_db_path = voting_db_path_for_wallet_db(db_path);
    let db = zcash_voting::storage::VotingDb::open(&voting_db_path)
        .map_err(|e| format!("Error opening voting database: {e}"))?;
    db.set_wallet_id(wallet_id);
    Ok(db)
}

/// Validates and persists initial state for a voting round.
///
/// `session_json`, when present, is stored with the round as opaque upstream
/// session metadata.
///
/// # Errors
///
/// Returns an error if the round parameters fail `zcash_voting` validation or
/// the voting database rejects the round initialization.
pub fn init_voting_round(
    db: &zcash_voting::storage::VotingDb,
    params: &zcash_voting::VotingRoundParams,
    session_json: Option<&str>,
) -> Result<(), String> {
    zcash_voting::validate_round_params(params)
        .map_err(|e| format!("Invalid voting round params: {e}"))?;
    db.init_round(params, session_json)
        .map_err(|e| format!("init_round failed: {e}"))
}

/// Loads a round state, initializing it first when the round is absent.
///
/// Existing round state is returned unchanged; missing state is created from
/// `params` and `session_json` before being reloaded from storage.
///
/// # Errors
///
/// Returns an error if round initialization fails or if the round state cannot
/// be read after initialization.
pub fn ensure_voting_round(
    db: &zcash_voting::storage::VotingDb,
    params: &zcash_voting::VotingRoundParams,
    session_json: Option<&str>,
) -> Result<zcash_voting::storage::RoundState, String> {
    match db.get_round_state(&params.vote_round_id) {
        Ok(state) => Ok(state),
        Err(_) => {
            init_voting_round(db, params, session_json)?;
            db.get_round_state(&params.vote_round_id)
                .map_err(|e| format!("get_round_state failed after init_round: {e}"))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn open_voting_db_initializes_upstream_schema() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let db = open_voting_db(db_path.to_str().unwrap(), "wallet-1").unwrap();

        assert!(db.list_rounds().unwrap().is_empty());
        assert!(
            std::path::Path::new(&voting_db_path_for_wallet_db(db_path.to_str().unwrap())).exists()
        );
    }

    #[test]
    fn open_voting_db_uses_sidecar_path_not_wallet_user_version() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let wallet_conn = rusqlite::Connection::open(&db_path).unwrap();
        wallet_conn.pragma_update(None, "user_version", 8).unwrap();

        let db = open_voting_db(db_path.to_str().unwrap(), "wallet-1").unwrap();

        assert!(db.list_rounds().unwrap().is_empty());
        let wallet_version: u32 = wallet_conn
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .unwrap();
        assert_eq!(wallet_version, 8);
    }

    #[test]
    fn ensure_voting_round_initializes_and_loads_round_state() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let db = open_voting_db(db_path.to_str().unwrap(), "wallet-1").unwrap();
        let params = test_round_params();

        let state = ensure_voting_round(&db, &params, Some(r#"{"round_name":"Demo"}"#)).unwrap();

        assert_eq!(state.round_id, params.vote_round_id);
        assert_eq!(state.snapshot_height, params.snapshot_height);
        assert_eq!(db.list_rounds().unwrap().len(), 1);
    }

    #[test]
    fn init_voting_round_rejects_invalid_round_params() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let db = open_voting_db(db_path.to_str().unwrap(), "wallet-1").unwrap();
        let mut params = test_round_params();
        params.nc_root = vec![2; 31];

        let err = init_voting_round(&db, &params, None).unwrap_err();

        assert!(err.contains("Invalid voting round params"));
        assert!(db.list_rounds().unwrap().is_empty());
    }

    #[test]
    fn voting_db_clear_round_removes_round_state() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let db = open_voting_db(db_path.to_str().unwrap(), "wallet-1").unwrap();
        let params = test_round_params();
        ensure_voting_round(&db, &params, None).unwrap();

        db.clear_round(&params.vote_round_id).unwrap();

        assert!(db.list_rounds().unwrap().is_empty());
    }

    #[test]
    fn delegation_tx_hash_roundtrips_through_voting_db() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let db = open_voting_db(db_path.to_str().unwrap(), "wallet-1").unwrap();
        let params = test_round_params();
        ensure_voting_round(&db, &params, None).unwrap();
        db.ensure_bundles(&params.vote_round_id, &[test_note_info(42)])
            .unwrap();

        db.store_delegation_tx_hash(&params.vote_round_id, 0, "abc123")
            .unwrap();

        assert_eq!(
            db.get_delegation_tx_hash(&params.vote_round_id, 0)
                .unwrap()
                .as_deref(),
            Some("abc123")
        );
    }

    #[test]
    fn delegation_tx_hashes_are_keyed_by_bundle_index() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let db = open_voting_db(db_path.to_str().unwrap(), "wallet-1").unwrap();
        let params = test_round_params();
        ensure_voting_round(&db, &params, None).unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();
        db.ensure_bundles(&params.vote_round_id, &notes).unwrap();

        db.store_delegation_tx_hash(&params.vote_round_id, 0, "tx0")
            .unwrap();
        db.store_delegation_tx_hash(&params.vote_round_id, 1, "tx1")
            .unwrap();

        assert_eq!(
            db.get_delegation_tx_hash(&params.vote_round_id, 0)
                .unwrap()
                .as_deref(),
            Some("tx0")
        );
        assert_eq!(
            db.get_delegation_tx_hash(&params.vote_round_id, 1)
                .unwrap()
                .as_deref(),
            Some("tx1")
        );
        assert!(db.get_delegation_tx_hash(&params.vote_round_id, 2).is_err());
    }

    #[test]
    fn delete_skipped_bundles_removes_indices_at_or_above_keep_count() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let db = open_voting_db(db_path.to_str().unwrap(), "wallet-1").unwrap();
        let params = test_round_params();
        ensure_voting_round(&db, &params, None).unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();
        db.ensure_bundles(&params.vote_round_id, &notes).unwrap();

        let deleted = db.delete_skipped_bundles(&params.vote_round_id, 1).unwrap();

        assert_eq!(deleted, 1);
        assert_eq!(db.get_bundle_count(&params.vote_round_id).unwrap(), 1);
        assert!(db
            .store_delegation_tx_hash(&params.vote_round_id, 1, "skipped")
            .is_err());
    }

    fn test_round_params() -> zcash_voting::VotingRoundParams {
        zcash_voting::VotingRoundParams {
            vote_round_id: "0000000000000000000000000000000000000000000000000000000000000001"
                .to_string(),
            snapshot_height: 100,
            ea_pk: vec![1; 32],
            nc_root: vec![2; 32],
            nullifier_imt_root: vec![3; 32],
        }
    }

    fn test_note_info(position: u64) -> zcash_voting::NoteInfo {
        zcash_voting::NoteInfo {
            commitment: vec![1; 32],
            nullifier: vec![2; 32],
            value: zcash_voting::governance::BALLOT_DIVISOR,
            position,
            diversifier: vec![3; 11],
            rho: vec![4; 32],
            rseed: vec![5; 32],
            scope: 0,
            ufvk_str: "uviewtest".to_string(),
        }
    }
}
