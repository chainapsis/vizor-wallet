use std::panic;

use crate::wallet::{
    keys,
    voting::{
        delegation::{self, BundleSetupResult, SignedDelegation},
        state,
    },
};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiVotingRoundParams {
    pub vote_round_id: String,
    pub snapshot_height: u64,
    pub ea_pk: Vec<u8>,
    pub nc_root: Vec<u8>,
    pub nullifier_imt_root: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiVotingBundleSetupResult {
    pub bundle_count: u32,
    pub eligible_weight_zatoshi: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiSignedDelegation {
    pub pczt_bytes: Vec<u8>,
    pub txid_hex: String,
    pub status: String,
    pub message: Option<String>,
    pub eligible_weight_zatoshi: u64,
    pub delegated_weight_zatoshi: u64,
    pub bundle_count: u32,
    pub bundle_index: u32,
}

impl From<ApiVotingRoundParams> for zcash_voting::VotingRoundParams {
    fn from(params: ApiVotingRoundParams) -> Self {
        Self {
            vote_round_id: params.vote_round_id,
            snapshot_height: params.snapshot_height,
            ea_pk: params.ea_pk,
            nc_root: params.nc_root,
            nullifier_imt_root: params.nullifier_imt_root,
        }
    }
}

impl From<BundleSetupResult> for ApiVotingBundleSetupResult {
    fn from(result: BundleSetupResult) -> Self {
        Self {
            bundle_count: result.bundle_count,
            eligible_weight_zatoshi: result.eligible_weight_zatoshi,
        }
    }
}

impl From<SignedDelegation> for ApiSignedDelegation {
    fn from(result: SignedDelegation) -> Self {
        Self {
            pczt_bytes: result.pczt_bytes,
            txid_hex: result.txid_hex,
            status: result.status,
            message: result.message,
            eligible_weight_zatoshi: result.eligible_weight_zatoshi,
            delegated_weight_zatoshi: result.delegated_weight_zatoshi,
            bundle_count: result.bundle_count,
            bundle_index: result.bundle_index,
        }
    }
}

fn catch<T>(f: impl FnOnce() -> Result<T, String> + panic::UnwindSafe) -> Result<T, String> {
    match panic::catch_unwind(f) {
        Ok(result) => result,
        Err(e) => {
            let msg = if let Some(s) = e.downcast_ref::<&str>() {
                s.to_string()
            } else if let Some(s) = e.downcast_ref::<String>() {
                s.clone()
            } else {
                "Unknown panic".to_string()
            };
            Err(format!("Rust panic: {msg}"))
        }
    }
}

pub fn prepare_voting_round(
    db_path: String,
    wallet_id: String,
    round_params: ApiVotingRoundParams,
    session_json: Option<String>,
) -> Result<(), String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        state::init_voting_round(&db, &round_params.into(), session_json.as_deref())
    })
}

pub fn get_bundle_count(
    db_path: String,
    wallet_id: String,
    round_id: String,
) -> Result<u32, String> {
    catch(|| delegation::get_bundle_count(&db_path, &wallet_id, &round_id))
}

pub async fn setup_delegation_bundles(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    round_params: ApiVotingRoundParams,
    round_name: String,
    session_json: Option<String>,
    account_uuid: String,
) -> Result<ApiVotingBundleSetupResult, String> {
    let network = keys::parse_network(&network)?;
    delegation::setup_delegation_bundles(
        &db_path,
        &lightwalletd_url,
        network,
        round_params.into(),
        &round_name,
        session_json.as_deref(),
        &account_uuid,
    )
    .await
    .map(Into::into)
}

#[allow(clippy::too_many_arguments)]
pub async fn build_and_prove_delegation_bundle(
    db_path: String,
    lightwalletd_url: String,
    pir_server_url: String,
    network: String,
    round_params: ApiVotingRoundParams,
    round_name: String,
    session_json: Option<String>,
    account_uuid: String,
    seed_bytes: Vec<u8>,
    bundle_index: u32,
) -> Result<ApiSignedDelegation, String> {
    let network = keys::parse_network(&network)?;
    delegation::build_and_prove_delegation_bundle(
        &db_path,
        &lightwalletd_url,
        &pir_server_url,
        network,
        round_params.into(),
        &round_name,
        session_json.as_deref(),
        &account_uuid,
        &seed_bytes,
        bundle_index,
        |_| {},
    )
    .await
    .map(Into::into)
}

pub fn store_delegation_tx_hash(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    tx_hash: String,
) -> Result<(), String> {
    catch(|| {
        delegation::store_delegation_tx_hash(
            &db_path,
            &wallet_id,
            &round_id,
            bundle_index,
            &tx_hash,
        )
    })
}

pub fn get_delegation_tx_hash(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
) -> Result<Option<String>, String> {
    catch(|| delegation::get_delegation_tx_hash(&db_path, &wallet_id, &round_id, bundle_index))
}

pub fn delete_skipped_bundles(
    db_path: String,
    wallet_id: String,
    round_id: String,
    keep_count: u32,
) -> Result<u32, String> {
    catch(|| delegation::delete_skipped_bundles(&db_path, &wallet_id, &round_id, keep_count))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wallet::voting::state::open_voting_db;

    const WALLET_ID: &str = "wallet-1";
    const ROUND_ID: &str = "0000000000000000000000000000000000000000000000000000000000000001";

    #[test]
    fn api_round_params_convert_to_core_round_params() {
        let api = test_api_round_params();

        let core: zcash_voting::VotingRoundParams = api.clone().into();

        assert_eq!(core.vote_round_id, api.vote_round_id);
        assert_eq!(core.snapshot_height, api.snapshot_height);
        assert_eq!(core.ea_pk, api.ea_pk);
        assert_eq!(core.nc_root, api.nc_root);
        assert_eq!(core.nullifier_imt_root, api.nullifier_imt_root);
    }

    #[test]
    fn api_bundle_setup_result_preserves_core_fields() {
        let api = ApiVotingBundleSetupResult::from(BundleSetupResult {
            bundle_count: 2,
            eligible_weight_zatoshi: 50,
        });

        assert_eq!(api.bundle_count, 2);
        assert_eq!(api.eligible_weight_zatoshi, 50);
    }

    #[test]
    fn api_signed_delegation_preserves_core_fields() {
        let api = ApiSignedDelegation::from(SignedDelegation {
            pczt_bytes: vec![1, 2, 3],
            txid_hex: "abc".to_string(),
            status: "broadcasted".to_string(),
            message: Some("ok".to_string()),
            eligible_weight_zatoshi: 20,
            delegated_weight_zatoshi: 10,
            bundle_count: 2,
            bundle_index: 1,
        });

        assert_eq!(api.pczt_bytes, vec![1, 2, 3]);
        assert_eq!(api.txid_hex, "abc");
        assert_eq!(api.status, "broadcasted");
        assert_eq!(api.message.as_deref(), Some("ok"));
        assert_eq!(api.eligible_weight_zatoshi, 20);
        assert_eq!(api.delegated_weight_zatoshi, 10);
        assert_eq!(api.bundle_count, 2);
        assert_eq!(api.bundle_index, 1);
    }

    #[test]
    fn prepare_voting_round_initializes_round_happy_path() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");

        prepare_voting_round(
            db_path.to_str().unwrap().to_string(),
            WALLET_ID.to_string(),
            test_api_round_params(),
            Some(r#"{"round_name":"Demo"}"#.to_string()),
        )
        .unwrap();

        let db = open_voting_db(db_path.to_str().unwrap(), WALLET_ID).unwrap();
        let state = db.get_round_state(ROUND_ID).unwrap();
        assert_eq!(state.round_id, ROUND_ID);
        assert_eq!(state.snapshot_height, 100);
    }

    #[test]
    fn prepare_voting_round_rejects_invalid_round_params() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let mut params = test_api_round_params();
        params.nc_root.pop();

        let err = prepare_voting_round(
            db_path.to_str().unwrap().to_string(),
            WALLET_ID.to_string(),
            params,
            None,
        )
        .unwrap_err();

        assert!(err.contains("Invalid voting round params"));
    }

    #[test]
    fn bundle_count_and_hash_api_roundtrip_happy_path() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        prepare_voting_round(
            db_path.to_str().unwrap().to_string(),
            WALLET_ID.to_string(),
            test_api_round_params(),
            None,
        )
        .unwrap();
        insert_bundles(db_path.to_str().unwrap(), 6);

        assert_eq!(
            get_bundle_count(
                db_path.to_str().unwrap().to_string(),
                WALLET_ID.to_string(),
                ROUND_ID.to_string(),
            )
            .unwrap(),
            2
        );

        store_delegation_tx_hash(
            db_path.to_str().unwrap().to_string(),
            WALLET_ID.to_string(),
            ROUND_ID.to_string(),
            1,
            "txid-1".to_string(),
        )
        .unwrap();

        assert_eq!(
            get_delegation_tx_hash(
                db_path.to_str().unwrap().to_string(),
                WALLET_ID.to_string(),
                ROUND_ID.to_string(),
                1,
            )
            .unwrap()
            .as_deref(),
            Some("txid-1")
        );
    }

    #[test]
    fn store_delegation_tx_hash_rejects_missing_bundle() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        prepare_voting_round(
            db_path.to_str().unwrap().to_string(),
            WALLET_ID.to_string(),
            test_api_round_params(),
            None,
        )
        .unwrap();

        let err = store_delegation_tx_hash(
            db_path.to_str().unwrap().to_string(),
            WALLET_ID.to_string(),
            ROUND_ID.to_string(),
            0,
            "txid-0".to_string(),
        )
        .unwrap_err();

        assert!(err.contains("get_delegation_tx_hash failed after store"));
    }

    #[test]
    fn delete_skipped_bundles_api_happy_path() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        prepare_voting_round(
            db_path.to_str().unwrap().to_string(),
            WALLET_ID.to_string(),
            test_api_round_params(),
            None,
        )
        .unwrap();
        insert_bundles(db_path.to_str().unwrap(), 6);

        let deleted = delete_skipped_bundles(
            db_path.to_str().unwrap().to_string(),
            WALLET_ID.to_string(),
            ROUND_ID.to_string(),
            1,
        )
        .unwrap();

        assert_eq!(deleted, 1);
        assert_eq!(
            get_bundle_count(
                db_path.to_str().unwrap().to_string(),
                WALLET_ID.to_string(),
                ROUND_ID.to_string(),
            )
            .unwrap(),
            1
        );
    }

    #[test]
    fn setup_delegation_bundles_rejects_invalid_network_before_network_io() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(setup_delegation_bundles(
                db_path.to_str().unwrap().to_string(),
                "http://127.0.0.1:1".to_string(),
                "bogus".to_string(),
                test_api_round_params(),
                "Demo".to_string(),
                None,
                WALLET_ID.to_string(),
            ))
            .unwrap_err();

        assert!(err.contains("Unknown network"));
    }

    #[test]
    fn build_and_prove_delegation_bundle_rejects_invalid_network_before_network_io() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(build_and_prove_delegation_bundle(
                db_path.to_str().unwrap().to_string(),
                "http://127.0.0.1:1".to_string(),
                "http://127.0.0.1:2".to_string(),
                "bogus".to_string(),
                test_api_round_params(),
                "Demo".to_string(),
                None,
                WALLET_ID.to_string(),
                vec![7; 32],
                0,
            ))
            .unwrap_err();

        assert!(err.contains("Unknown network"));
    }

    fn insert_bundles(db_path: &str, note_count: u64) {
        let db = open_voting_db(db_path, WALLET_ID).unwrap();
        let notes: Vec<_> = (0..note_count).map(test_note_info).collect();
        db.setup_bundles(ROUND_ID, &notes).unwrap();
    }

    fn test_api_round_params() -> ApiVotingRoundParams {
        ApiVotingRoundParams {
            vote_round_id: ROUND_ID.to_string(),
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
