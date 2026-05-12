use std::{
    collections::HashMap,
    sync::{Arc, Mutex, OnceLock},
};

use zcash_voting::{storage::VotingDb, tree_sync::VoteTreeSync};

use super::{endpoint_validation, state};

/// FRB-friendly representation of a Vote Authority Note Merkle witness.
///
/// `zcash_voting::tree_sync::VanWitness` stores the authentication path as
/// fixed-size arrays. This shape keeps the public Vizor wrapper on simple byte
/// vectors that are easy to pass through the API layer.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VanWitness {
    pub auth_path: Vec<Vec<u8>>,
    pub position: u32,
    pub anchor_height: u32,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct RegistryKey {
    db_path: String,
    wallet_id: String,
}

static TREE_SYNC_REGISTRY: OnceLock<Mutex<HashMap<RegistryKey, Arc<VoteTreeSync>>>> =
    OnceLock::new();
static RUSTLS_PROVIDER: OnceLock<()> = OnceLock::new();

/// Install the Rustls ring provider before constructing the tree HTTP transport.
///
/// Flutter calls `init_app()` during normal startup, but unit tests can touch the
/// vote-tree wrapper directly. Installing defensively here keeps the wrapper
/// usable in both paths.
fn ensure_rustls_provider() {
    RUSTLS_PROVIDER.get_or_init(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
    });
}

fn registry() -> &'static Mutex<HashMap<RegistryKey, Arc<VoteTreeSync>>> {
    TREE_SYNC_REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Build the stable identity for a process-local vote-tree sync session.
fn registry_key(db_path: &str, wallet_id: &str) -> RegistryKey {
    RegistryKey {
        db_path: db_path.to_string(),
        wallet_id: wallet_id.to_string(),
    }
}

/// Return the shared `VoteTreeSync` for a voting DB and wallet.
///
/// Vizor opens `VotingDb` per operation, but upstream `VoteTreeSync` keeps
/// in-memory `TreeClient` state that must be shared between sync and witness
/// generation calls. This registry bridges those two lifetime models.
fn tree_sync_for(db_path: &str, wallet_id: &str) -> Result<Arc<VoteTreeSync>, String> {
    ensure_rustls_provider();

    let key = registry_key(db_path, wallet_id);
    let mut guard = registry()
        .lock()
        .map_err(|e| format!("VoteTreeSync registry lock poisoned: {e}"))?;
    Ok(guard
        .entry(key)
        .or_insert_with(|| Arc::new(VoteTreeSync::new()))
        .clone())
}

/// Sync the vote commitment tree for `round_id` from a chain node URL.
pub fn sync_commitment_tree(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    node_url: &str,
) -> Result<u32, String> {
    let started = std::time::Instant::now();
    log::info!(
        "voting tree: sync start (round_id={}, wallet_id={})",
        round_id,
        wallet_id
    );
    let db = state::open_voting_db(db_path, wallet_id)?;
    let height = sync_commitment_tree_with_db(db_path, wallet_id, &db, round_id, node_url)?;
    log::info!(
        "voting tree: sync completed (round_id={}, wallet_id={}, height={}, elapsed={:.2}s)",
        round_id,
        wallet_id,
        height,
        started.elapsed().as_secs_f64()
    );
    Ok(height)
}

/// Sync the vote commitment tree using an already-open voting database.
///
/// This is kept separate from `sync_commitment_tree` so tests and future callers
/// that already hold a database handle can avoid reopening it, while still using
/// the same process-local `VoteTreeSync` registry.
pub fn sync_commitment_tree_with_db(
    db_path: &str,
    wallet_id: &str,
    voting_db: &VotingDb,
    round_id: &str,
    node_url: &str,
) -> Result<u32, String> {
    let node_url = endpoint_validation::validate_tree_base_endpoint(node_url, round_id)?;
    let tree_sync = tree_sync_for(db_path, wallet_id)?;
    tree_sync
        .sync(voting_db, round_id, &node_url)
        .map_err(|e| format!("sync_vote_tree failed: {e}"))
}

/// Generate a VAN Merkle witness for a bundle at `anchor_height`.
pub fn generate_van_witness(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    anchor_height: u32,
) -> Result<VanWitness, String> {
    let started = std::time::Instant::now();
    log::info!(
        "voting tree: VAN witness start \
         (round_id={}, wallet_id={}, bundle_index={}, anchor_height={})",
        round_id,
        wallet_id,
        bundle_index,
        anchor_height
    );
    let db = state::open_voting_db(db_path, wallet_id)?;
    let witness = generate_van_witness_with_db(
        db_path,
        wallet_id,
        &db,
        round_id,
        bundle_index,
        anchor_height,
    )?;
    log::info!(
        "voting tree: VAN witness completed \
         (round_id={}, wallet_id={}, bundle_index={}, position={}, elapsed={:.2}s)",
        round_id,
        wallet_id,
        bundle_index,
        witness.position,
        started.elapsed().as_secs_f64()
    );
    Ok(witness)
}

/// Generate a VAN Merkle witness using an already-open voting database.
///
/// The witness call intentionally reuses the same registry entry as sync; the
/// underlying `VoteTreeSync` requires its in-memory `TreeClient` to have synced
/// the round before witnesses can be produced.
pub fn generate_van_witness_with_db(
    db_path: &str,
    wallet_id: &str,
    voting_db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    anchor_height: u32,
) -> Result<VanWitness, String> {
    let tree_sync = tree_sync_for(db_path, wallet_id)?;
    tree_sync
        .generate_van_witness(voting_db, round_id, bundle_index, anchor_height)
        .map(|witness| VanWitness {
            auth_path: witness.auth_path.iter().map(|h| h.to_vec()).collect(),
            position: witness.position,
            anchor_height: witness.anchor_height,
        })
        .map_err(|e| format!("generate_van_witness failed: {e}"))
}

/// Reset cached vote-tree state for one round or all rounds in a session.
///
/// Passing `None` or an empty string clears all in-memory tree clients for the
/// `(db_path, wallet_id)` session. Passing a round ID clears only that round.
pub fn reset_tree_client(
    db_path: &str,
    wallet_id: &str,
    round_id: Option<&str>,
) -> Result<(), String> {
    let round_id = round_id.unwrap_or("");
    let tree_sync = tree_sync_for(db_path, wallet_id)?;
    tree_sync
        .reset(round_id)
        .map_err(|e| format!("reset_tree_client failed: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        io::{Read, Write},
        net::TcpListener,
        thread,
    };

    const ROUND_ID: &str = "0000000000000000000000000000000000000000000000000000000000000001";

    #[test]
    fn tree_sync_registry_reuses_session_clients() {
        let first = tree_sync_for("/tmp/voting-a.sqlite", "wallet-1").unwrap();
        let second = tree_sync_for("/tmp/voting-a.sqlite", "wallet-1").unwrap();
        let other_wallet = tree_sync_for("/tmp/voting-a.sqlite", "wallet-2").unwrap();
        let other_db = tree_sync_for("/tmp/voting-b.sqlite", "wallet-1").unwrap();

        assert!(Arc::ptr_eq(&first, &second));
        assert!(!Arc::ptr_eq(&first, &other_wallet));
        assert!(!Arc::ptr_eq(&first, &other_db));
    }

    #[test]
    fn reset_tree_client_accepts_round_and_all_rounds() {
        reset_tree_client("/tmp/voting-reset.sqlite", "wallet-1", Some("round-1")).unwrap();
        reset_tree_client("/tmp/voting-reset.sqlite", "wallet-1", None).unwrap();
        reset_tree_client("/tmp/voting-reset.sqlite", "wallet-1", Some("")).unwrap();
    }

    #[test]
    fn sync_commitment_tree_happy_path_accepts_empty_tree() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let server = start_tree_server(0, vec![], 1);

        let height = sync_commitment_tree(
            db_path.to_str().unwrap(),
            "wallet-empty-sync",
            ROUND_ID,
            &server,
        )
        .unwrap();

        assert_eq!(height, 0);
    }

    #[test]
    fn sync_then_generate_van_witness_happy_path() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = state::open_voting_db(db_path.to_str().unwrap(), "wallet-witness").unwrap();
        state::init_voting_round(&db, &test_round_params(), None).unwrap();
        db.setup_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        db.store_van_position(ROUND_ID, 0, 0).unwrap();
        let server = start_tree_server(1, vec![fp_one_base64()], 3);

        let height = sync_commitment_tree(
            db_path.to_str().unwrap(),
            "wallet-witness",
            ROUND_ID,
            &server,
        )
        .unwrap();
        let witness = generate_van_witness(
            db_path.to_str().unwrap(),
            "wallet-witness",
            ROUND_ID,
            0,
            height,
        )
        .unwrap();

        assert_eq!(height, 1);
        assert_eq!(witness.position, 0);
        assert_eq!(witness.anchor_height, 1);
        assert_eq!(witness.auth_path.len(), 24);
        assert!(witness.auth_path.iter().all(|hash| hash.len() == 32));
    }

    #[test]
    fn generate_van_witness_reports_missing_bundle_position_before_sync_requirement() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = generate_van_witness(db_path.to_str().unwrap(), "wallet-1", "round-1", 0, 100)
            .unwrap_err();

        assert!(!err.is_empty());
    }

    fn start_tree_server(height: u32, leaves: Vec<String>, expected_requests: usize) -> String {
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
                let body = tree_response_body(path, height, &leaves);
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

    fn tree_response_body(path: &str, height: u32, leaves: &[String]) -> String {
        if path.ends_with("/latest") {
            format!(
                r#"{{"tree":{{"next_index":{},"height":{}}}}}"#,
                leaves.len(),
                height
            )
        } else if path.contains("/leaves?") {
            if height == 0 {
                r#"{"blocks":[]}"#.to_string()
            } else {
                let leaves_json = leaves
                    .iter()
                    .map(|leaf| format!(r#""{leaf}""#))
                    .collect::<Vec<_>>()
                    .join(",");
                format!(
                    r#"{{"blocks":[{{"height":{height},"start_index":0,"leaves":[{leaves_json}]}}]}}"#
                )
            }
        } else {
            r#"{"tree":null}"#.to_string()
        }
    }

    fn fp_one_base64() -> String {
        // Little-endian canonical encoding of Pallas Fp::from(1).
        "AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=".to_string()
    }

    fn test_round_params() -> zcash_voting::VotingRoundParams {
        zcash_voting::VotingRoundParams {
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
