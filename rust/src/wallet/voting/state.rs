pub fn open_voting_db(
    db_path: &str,
    wallet_id: &str,
) -> Result<zcash_voting::storage::VotingDb, String> {
    let db = zcash_voting::storage::VotingDb::open(db_path)
        .map_err(|e| format!("Error opening voting database: {e}"))?;
    db.set_wallet_id(wallet_id);
    Ok(db)
}

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
        db.setup_bundles(&params.vote_round_id, &[test_note_info(42)])
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
        db.setup_bundles(&params.vote_round_id, &notes).unwrap();

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
        db.setup_bundles(&params.vote_round_id, &notes).unwrap();

        let deleted = db.delete_skipped_bundles(&params.vote_round_id, 1).unwrap();

        assert_eq!(deleted, 1);
        assert_eq!(db.get_bundle_count(&params.vote_round_id).unwrap(), 1);
        assert!(crate::wallet::voting::delegation::store_delegation_tx_hash(
            db_path.to_str().unwrap(),
            "wallet-1",
            &params.vote_round_id,
            1,
            "skipped",
        )
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
