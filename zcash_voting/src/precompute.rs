//! Precomputation APIs for delegation inputs.
//!
//! Prepared delegation bundles warm witnesses, padded-note secret initialization,
//! and PIR-backed nullifier proofs through `PreparedDelegationBundle::precompute`.
//! Lower-level helpers remain available for callers that already persisted
//! intermediate state.
//!
//! See the `zcash-voting-wallet-example` workspace crate for caller-oriented
//! precompute orchestration that can evolve independently from the library API.

use std::borrow::Borrow;

use std::{
    collections::HashMap,
    sync::{Arc, Mutex, OnceLock},
};

use zcash_client_sqlite::WalletDb;

use crate::{
    round::VotingDb,
    types::{NoteInfo, VotingError, WitnessData},
};

use crate::{delegate::PreparedDelegationReport, round::BundleLayout, types::Network};

pub use crate::vote::VanWitness;

static VOTE_TREE_SYNCS: OnceLock<Mutex<HashMap<String, Arc<crate::tree_sync::VoteTreeSync>>>> =
    OnceLock::new();

/// Result of PIR precomputation for one delegation bundle.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PirPrecomputeReport {
    pub cached: u32,
    pub fetched: u32,
}

/// Persists a snapshot tree state, generates shielded note witnesses, and caches them.
///
/// This is the FFI-friendly variant for callers that pass the round tree state
/// with the note-witness request.
pub fn note_witnesses<C, P, CL, R>(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    tree_state_bytes: &[u8],
    notes: &[NoteInfo],
    wallet_db: &WalletDb<C, P, CL, R>,
) -> Result<Vec<WitnessData>, VotingError>
where
    C: Borrow<rusqlite::Connection>,
    P: zcash_protocol::consensus::Parameters,
{
    crate::witness::store_tree_state_and_generate_note_witnesses(
        db,
        round_id,
        bundle_index,
        tree_state_bytes,
        notes,
        wallet_db,
    )
}

/// Loads a round's cached tree state, generates shielded note witnesses, and caches them.
///
/// This is the FFI-friendly variant for callers that already persisted the
/// round tree state through [`VotingDb`] and should not reach into storage
/// query helpers.
pub fn stored_note_witnesses<C, P, CL, R>(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    notes: &[NoteInfo],
    wallet_db: &WalletDb<C, P, CL, R>,
) -> Result<Vec<WitnessData>, VotingError>
where
    C: Borrow<rusqlite::Connection>,
    P: zcash_protocol::consensus::Parameters,
{
    let witnesses = crate::witness::generate_note_witnesses(db, round_id, notes, wallet_db)?;
    db.replace_bundle_witnesses(round_id, bundle_index, &witnesses)?;
    Ok(witnesses)
}

/// Verifies a shielded note witness against its stored root.
///
/// Returns `Ok(())` when the witness recomputes to the expected root and
/// [`VotingError::InvalidInput`] when the bytes are malformed or mismatched.
pub fn verify_witness(witness: &WitnessData) -> Result<(), VotingError> {
    if crate::witness::verify_witness(witness)? {
        Ok(())
    } else {
        Err(VotingError::InvalidInput {
            message: format!(
                "witness root mismatch at note position {}",
                witness.position
            ),
        })
    }
}

/// Syncs the vote commitment tree for one round and returns the latest height.
pub fn sync_vote_tree(db: &VotingDb, round_id: &str, node_url: &str) -> Result<u32, VotingError> {
    vote_tree_sync_for(db)?.sync(db, round_id, node_url)
}

/// Generates the VAN witness needed by `vote::commit`.
pub fn van_witness(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    anchor_height: u32,
) -> Result<VanWitness, VotingError> {
    vote_tree_sync_for(db)?.generate_van_witness(db, round_id, bundle_index, anchor_height)
}

/// Drops cached vote tree state for one round, or all rounds when `round_id` is empty.
pub fn reset_vote_tree(db: &VotingDb, round_id: &str) -> Result<(), VotingError> {
    vote_tree_sync_for(db)?.reset(round_id)
}

/// Drops cached vote tree state and, for round-scoped resets, clears unsigned
/// delegation setup fields so interrupted Keystone requests can be rebuilt safely.
///
/// Round-scoped cleanup is mainly for the restart mid-signing case: if the app
/// dies after `build_governance_pczt` persisted `pczt_sighash` (and related
/// setup columns) but before the user finishes signing, the next startup tries
/// to rebuild the Keystone request and `store_delegation_data` refuses to
/// overwrite those fields. Clearing unsigned setup for that round lets setup
/// run again without touching bundles that already have Keystone signatures or
/// a stored `delegation_tx_hash`.
///
/// When `round_id` is empty, only the process-local vote tree cache is reset
/// account-wide; no persisted delegation setup columns are cleared.
pub fn reset_voting_session_state(db: &VotingDb, round_id: &str) -> Result<(), VotingError> {
    reset_vote_tree(db, round_id)?;
    if !round_id.is_empty() {
        db.clear_unsigned_delegation_setup_fields(round_id)?;
    }
    Ok(())
}

fn vote_tree_sync_for(db: &VotingDb) -> Result<Arc<crate::tree_sync::VoteTreeSync>, VotingError> {
    let wallet_id = db.wallet_id();
    let mut guard = VOTE_TREE_SYNCS
        .get_or_init(|| Mutex::new(HashMap::new()))
        .lock()
        .map_err(|e| VotingError::Internal {
            message: format!("vote tree sync registry lock poisoned: {e}"),
        })?;
    Ok(guard
        .entry(wallet_id)
        .or_insert_with(|| Arc::new(crate::tree_sync::VoteTreeSync::new()))
        .clone())
}

/// Fetches and persists PIR-backed IMT non-membership proofs for one bundle.
///
/// This must run after padded-note secrets have been initialized for the bundle.
pub fn delegation_pir(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    notes: &[NoteInfo],
    pir_client: &pir_client::PirClientBlocking,
    network: Network,
) -> Result<PirPrecomputeReport, VotingError> {
    let result =
        db.precompute_delegation_pir(round_id, bundle_index, notes, pir_client, network)?;
    Ok(PirPrecomputeReport {
        cached: result.cached_count,
        fetched: result.fetched_count,
    })
}

/// Initializes padded-note secrets and runs PIR precompute.
///
/// Witnesses must already be cached for `notes`. Prefer
/// `PreparedDelegationBundle::precompute` for the full warm-up path from
/// prepared bundle state.
///
/// # Errors
///
/// Failures come from padded-secret initialization or PIR precompute.
pub(crate) fn warm_delegation_pir(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    notes: &[NoteInfo],
    layout: BundleLayout,
    pir_client: &pir_client::PirClientBlocking,
    network: Network,
) -> Result<PreparedDelegationReport, VotingError> {
    db.ensure_padded_secrets(round_id, bundle_index, notes)?;
    let report = delegation_pir(db, round_id, bundle_index, notes, pir_client, network)?;

    Ok(PreparedDelegationReport {
        report,
        layout,
        bundle_index,
    })
}

#[cfg(test)]
mod pir_tests {
    use super::*;
    use crate::round::BundleLayout;
    use crate::types::{Network, NoteInfo};

    const ROUND_ID: &str = "0101010101010101010101010101010101010101010101010101010101010101";

    #[test]
    fn warm_delegation_pir_runs_precompute_transport_path() {
        struct StaticPirTransport;

        impl pir_client::Transport for StaticPirTransport {
            fn get<'a>(&'a self, url: &'a str) -> pir_client::TransportFuture<'a> {
                Box::pin(async move {
                    let path = request_path(url);
                    match path {
                        "/tier0" => Ok(transport_response(vec![
                            0;
                            ((1usize
                                << pir_types::TIER0_LAYERS)
                                - 1)
                                * 32
                                + pir_types::TIER1_ROWS * 64
                        ])),
                        "/params/tier1" => Ok(transport_response(
                            serde_json::to_vec(&pir_types::YpirScenario {
                                num_items: pir_types::TIER1_YPIR_ROWS,
                                item_size_bits: pir_types::TIER1_ITEM_BITS,
                            })
                            .unwrap(),
                        )),
                        "/params/tier2" => Ok(transport_response(
                            serde_json::to_vec(&pir_types::YpirScenario {
                                num_items: pir_types::TIER1_YPIR_ROWS,
                                item_size_bits: pir_types::TIER2_ITEM_BITS,
                            })
                            .unwrap(),
                        )),
                        "/root" => Ok(transport_response(
                            serde_json::to_vec(&pir_types::RootInfo {
                                root29: hex::encode([0u8; 32]),
                                root25: hex::encode([0u8; 32]),
                                num_ranges: 1,
                                pir_depth: pir_types::PIR_DEPTH,
                                height: None,
                            })
                            .unwrap(),
                        )),
                        _ => Err(anyhow::anyhow!("unexpected GET {path}")),
                    }
                })
            }

            fn post<'a>(&'a self, url: &'a str, _body: Vec<u8>) -> pir_client::TransportFuture<'a> {
                Box::pin(async move {
                    Err(anyhow::anyhow!(
                        "unexpected POST {}; warm path reached transport",
                        request_path(url)
                    ))
                })
            }
        }

        fn request_path(url: &str) -> &str {
            let without_scheme = url.split_once("://").map(|(_, rest)| rest).unwrap_or(url);
            without_scheme
                .find('/')
                .map(|idx| &without_scheme[idx..])
                .unwrap_or("/")
        }

        fn transport_response(body: Vec<u8>) -> pir_client::TransportResponse {
            pir_client::TransportResponse {
                status: 200,
                headers: Vec::new(),
                body,
            }
        }

        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id("warm-delegation-cancel");
        let notes = vec![NoteInfo {
            commitment: vec![1; 32],
            nullifier: vec![2; 32],
            value: crate::governance::BALLOT_DIVISOR,
            position: 42,
            diversifier: vec![3; 11],
            rho: vec![4; 32],
            rseed: vec![5; 32],
            scope: 0,
            ufvk_str: "uviewtest".to_string(),
        }];
        db.create_round(
            crate::Network::Testnet,
            &crate::round::RoundParams {
                vote_round_id: ROUND_ID.to_string(),
                snapshot_height: 100,
                ea_pk: vec![1; 32],
                nc_root: vec![2; 32],
                nullifier_imt_root: vec![3; 32],
            },
            None,
        )
        .unwrap();
        db.ensure_bundles(ROUND_ID, &notes).unwrap();
        let layout = BundleLayout {
            bundle_count: 1,
            eligible_weight: 42,
            dropped_count: 0,
        };
        let pir_client = pir_client::PirClientBlocking::with_transport(
            "https://pir.test",
            std::sync::Arc::new(StaticPirTransport),
        )
        .unwrap();

        let err = warm_delegation_pir(
            &db,
            ROUND_ID,
            0,
            &notes,
            layout,
            &pir_client,
            Network::Testnet,
        )
        .unwrap_err();

        let message = err.to_string();
        assert!(
            message.contains("failed to decode UFVK while deriving padded nullifiers")
                || message.contains("unexpected POST"),
            "unexpected warm_delegation_pir error: {message}",
        );
    }
}

#[cfg(test)]
mod tree_sync_tests {
    use super::*;
    use pasta_curves::Fp;
    use std::{
        io::{Read, Write},
        net::TcpListener,
        thread,
    };
    use vote_commitment_tree::{MemoryTreeServer, MerkleHashVote};

    const ROUND_ID: &str = "0101010101010101010101010101010101010101010101010101010101010101";
    const WALLET_ID: &str = "wallet-tree-sync";

    #[test]
    fn vote_tree_sync_witness_and_reset_happy_path() {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id(WALLET_ID);
        db.create_round(crate::Network::Testnet, &round_params(), None)
            .unwrap();
        db.ensure_bundles(ROUND_ID, &[note(0)]).unwrap();
        db.store_van_position(ROUND_ID, 0, 0).unwrap();
        let server = start_tree_server(1, vec![1], 2);

        let height = sync_vote_tree(&db, ROUND_ID, &server).unwrap();
        let witness = van_witness(&db, ROUND_ID, 0, height).unwrap();
        reset_vote_tree(&db, ROUND_ID).unwrap();

        assert_eq!(height, 1);
        assert_eq!(witness.position, 0);
        assert_eq!(witness.anchor_height, 1);
        assert_eq!(witness.auth_path.len(), crate::vote::VAN_AUTH_PATH_LEN);
        assert!(witness.auth_path.iter().all(|hash| hash.len() == 32));
    }

    #[derive(Clone)]
    struct MockTreeBlock {
        height: u32,
        start_index: u64,
        leaf: String,
        root: String,
    }

    fn start_tree_server(height: u32, leaf_values: Vec<u64>, expected_requests: usize) -> String {
        let (latest_root, blocks) = mock_tree_blocks(&leaf_values);
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        thread::spawn(move || {
            for _ in 0..expected_requests {
                let (mut stream, _) = listener.accept().unwrap();
                let mut request = [0u8; 2048];
                let len = stream.read(&mut request).unwrap();
                let request = String::from_utf8_lossy(&request[..len]);
                let path = request
                    .lines()
                    .next()
                    .and_then(|line| line.split_whitespace().nth(1))
                    .unwrap_or("/");
                let body = tree_response_body(path, height, &latest_root, &blocks);
                let response = format!(
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    body.len(),
                    body
                );
                stream.write_all(response.as_bytes()).unwrap();
            }
        });
        url
    }

    fn tree_response_body(
        path: &str,
        height: u32,
        latest_root: &Option<String>,
        blocks: &[MockTreeBlock],
    ) -> String {
        if path.ends_with("/latest") {
            match latest_root {
                Some(root) => format!(
                    r#"{{"tree":{{"next_index":{},"root":"{}","height":{}}}}}"#,
                    blocks.len(),
                    root,
                    height
                ),
                None => format!(
                    r#"{{"tree":{{"next_index":{},"height":{}}}}}"#,
                    blocks.len(),
                    height
                ),
            }
        } else if path.contains("/leaves?") {
            if height == 0 || blocks.is_empty() {
                r#"{"blocks":[]}"#.to_string()
            } else {
                let Some(block) = blocks.first() else {
                    return r#"{"blocks":[]}"#.to_string();
                };
                format!(
                    r#"{{"blocks":[{{"height":{},"start_index":{},"leaves":["{}"],"root":"{}"}}]}}"#,
                    block.height, block.start_index, block.leaf, block.root
                )
            }
        } else {
            r#"{"tree":null}"#.to_string()
        }
    }

    fn mock_tree_blocks(leaf_values: &[u64]) -> (Option<String>, Vec<MockTreeBlock>) {
        if leaf_values.is_empty() {
            return (None, vec![]);
        }

        let mut server = MemoryTreeServer::empty();
        let mut blocks = Vec::with_capacity(leaf_values.len());
        for (index, value) in leaf_values.iter().copied().enumerate() {
            let height = u32::try_from(index + 1).unwrap();
            server.append(Fp::from(value)).unwrap();
            server.checkpoint(height).unwrap();
            let root = server.root_at_height(height).unwrap();
            blocks.push(MockTreeBlock {
                height,
                start_index: u64::try_from(index).unwrap(),
                leaf: base64_encode(&MerkleHashVote::from_fp(Fp::from(value)).to_bytes()),
                root: base64_encode(&MerkleHashVote::from_fp(root).to_bytes()),
            });
        }

        let latest_root = blocks.last().map(|block| block.root.clone());
        (latest_root, blocks)
    }

    fn base64_encode(bytes: &[u8]) -> String {
        const TABLE: &[u8; 64] =
            b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
        for chunk in bytes.chunks(3) {
            let b0 = chunk[0];
            let b1 = *chunk.get(1).unwrap_or(&0);
            let b2 = *chunk.get(2).unwrap_or(&0);
            out.push(TABLE[(b0 >> 2) as usize] as char);
            out.push(TABLE[(((b0 & 0x03) << 4) | (b1 >> 4)) as usize] as char);
            if chunk.len() > 1 {
                out.push(TABLE[(((b1 & 0x0F) << 2) | (b2 >> 6)) as usize] as char);
            } else {
                out.push('=');
            }
            if chunk.len() > 2 {
                out.push(TABLE[(b2 & 0x3F) as usize] as char);
            } else {
                out.push('=');
            }
        }
        out
    }

    fn round_params() -> crate::round::RoundParams {
        crate::round::RoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 100,
            ea_pk: vec![1; 32],
            nc_root: vec![2; 32],
            nullifier_imt_root: vec![3; 32],
        }
    }

    fn note(position: u64) -> NoteInfo {
        NoteInfo {
            commitment: vec![1; 32],
            nullifier: vec![2; 32],
            value: crate::governance::BALLOT_DIVISOR,
            position,
            diversifier: vec![3; 11],
            rho: vec![4; 32],
            rseed: vec![5; 32],
            scope: 0,
            ufvk_str: "uviewtest".to_string(),
        }
    }
}

#[cfg(test)]
mod session_reset_tests {
    use super::*;
    use crate::storage::queries;

    const ROUND_ID: &str = "0101010101010101010101010101010101010101010101010101010101010101";
    const OTHER_ROUND_ID: &str = "0000000000000000000000000000000000000000000000000000000000000002";
    const WALLET_ID: &str = "wallet-session-reset";

    fn round_params(round_id: &str) -> crate::round::RoundParams {
        crate::round::RoundParams {
            vote_round_id: round_id.to_string(),
            snapshot_height: 100,
            ea_pk: vec![1; 32],
            nc_root: vec![2; 32],
            nullifier_imt_root: vec![3; 32],
        }
    }

    fn seed_unsigned_setup_fields(db: &VotingDb, round_id: &str, bundle_index: u32) {
        let conn = db.conn();
        conn.execute(
            "UPDATE bundles
             SET pczt_sighash = :sighash,
                 padded_note_secrets = :secrets,
                 padded_note_data = :padded
             WHERE round_id = :round_id
               AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index",
            rusqlite::named_params! {
                ":round_id": round_id,
                ":wallet_id": WALLET_ID,
                ":bundle_index": bundle_index,
                ":sighash": vec![0xAAu8; 32],
                ":secrets": vec![0xBBu8; 64],
                ":padded": vec![0xCCu8; 32],
            },
        )
        .unwrap();
    }

    fn has_unsigned_setup_fields(db: &VotingDb, round_id: &str, bundle_index: u32) -> bool {
        let conn = db.conn();
        queries::load_pczt_sighash(&conn, round_id, WALLET_ID, bundle_index).is_ok()
    }

    #[test]
    fn reset_voting_session_state_clears_unsigned_setup_fields() {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id(WALLET_ID);
        db.create_round(crate::Network::Testnet, &round_params(ROUND_ID), None)
            .unwrap();
        db.ensure_bundles(ROUND_ID, &[note(0), note(1)]).unwrap();
        seed_unsigned_setup_fields(&db, ROUND_ID, 0);
        seed_unsigned_setup_fields(&db, ROUND_ID, 1);

        reset_voting_session_state(&db, ROUND_ID).unwrap();

        assert!(!has_unsigned_setup_fields(&db, ROUND_ID, 0));
        assert!(!has_unsigned_setup_fields(&db, ROUND_ID, 1));
    }

    #[test]
    fn reset_voting_session_state_preserves_keystone_signed_bundles() {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id(WALLET_ID);
        db.create_round(crate::Network::Testnet, &round_params(ROUND_ID), None)
            .unwrap();
        db.ensure_bundles(ROUND_ID, &[note(0), note(1)]).unwrap();
        seed_unsigned_setup_fields(&db, ROUND_ID, 0);
        seed_unsigned_setup_fields(&db, ROUND_ID, 1);
        db.store_keystone_signature(ROUND_ID, 0, &[0x11; 64], &[0xAA; 32], &[0x22; 32])
            .unwrap();

        reset_voting_session_state(&db, ROUND_ID).unwrap();

        assert!(has_unsigned_setup_fields(&db, ROUND_ID, 0));
        assert!(!has_unsigned_setup_fields(&db, ROUND_ID, 1));
    }

    #[test]
    fn reset_voting_session_state_preserves_submitted_bundles() {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id(WALLET_ID);
        db.create_round(crate::Network::Testnet, &round_params(ROUND_ID), None)
            .unwrap();
        db.ensure_bundles(ROUND_ID, &[note(0), note(1)]).unwrap();
        seed_unsigned_setup_fields(&db, ROUND_ID, 0);
        seed_unsigned_setup_fields(&db, ROUND_ID, 1);
        db.store_delegation_tx_hash(ROUND_ID, 0, "submitted-tx")
            .unwrap();

        reset_voting_session_state(&db, ROUND_ID).unwrap();

        assert!(has_unsigned_setup_fields(&db, ROUND_ID, 0));
        assert!(!has_unsigned_setup_fields(&db, ROUND_ID, 1));
    }

    #[test]
    fn reset_voting_session_state_is_round_scoped() {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id(WALLET_ID);
        db.create_round(crate::Network::Testnet, &round_params(ROUND_ID), None)
            .unwrap();
        db.create_round(crate::Network::Testnet, &round_params(OTHER_ROUND_ID), None)
            .unwrap();
        db.ensure_bundles(ROUND_ID, &[note(0)]).unwrap();
        db.ensure_bundles(OTHER_ROUND_ID, &[note(0)]).unwrap();
        seed_unsigned_setup_fields(&db, ROUND_ID, 0);
        seed_unsigned_setup_fields(&db, OTHER_ROUND_ID, 0);

        reset_voting_session_state(&db, ROUND_ID).unwrap();

        assert!(!has_unsigned_setup_fields(&db, ROUND_ID, 0));
        assert!(has_unsigned_setup_fields(&db, OTHER_ROUND_ID, 0));
    }

    fn note(position: u64) -> NoteInfo {
        NoteInfo {
            commitment: vec![1; 32],
            nullifier: vec![2; 32],
            value: crate::governance::BALLOT_DIVISOR,
            position,
            diversifier: vec![3; 11],
            rho: vec![4; 32],
            rseed: vec![5; 32],
            scope: 0,
            ufvk_str: "uviewtest".to_string(),
        }
    }
}
