use std::sync::OnceLock;

use zcash_voting::{storage::VotingDb, validate_bundle_index};

use super::state;

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
    _db_path: &str,
    _wallet_id: &str,
    voting_db: &VotingDb,
    round_id: &str,
    node_url: &str,
) -> Result<u32, String> {
    ensure_rustls_provider();
    zcash_voting::precompute::sync_vote_tree(voting_db, round_id, node_url)
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
    let witness = generate_van_witness_with_db(&db, round_id, bundle_index, anchor_height)?;
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
    voting_db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    anchor_height: u32,
) -> Result<VanWitness, String> {
    ensure_rustls_provider();
    let bundle_count = voting_db
        .get_bundle_count(round_id)
        .map_err(|e| format!("get_bundle_count failed: {e}"))?;
    validate_bundle_index(bundle_count, bundle_index, "voting").map_err(|e| e.to_string())?;
    zcash_voting::precompute::van_witness(voting_db, round_id, bundle_index, anchor_height)
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
    ensure_rustls_provider();
    let round_id = round_id.unwrap_or("");
    let db = state::open_voting_db(db_path, wallet_id)?;
    zcash_voting::precompute::reset_vote_tree(&db, round_id)
        .map_err(|e| format!("reset_tree_client failed: {e}"))
}

/// Drop the process-local vote-tree sync client for a voting session.
///
/// Use this for account-wide lifecycle boundaries such as lock, account switch,
/// account removal, or wallet reset. Round-scoped cleanup should keep this
/// client because `VoteTreeSync` can serve multiple rounds for the same wallet.
pub fn clear_tree_sync_session(db_path: &str, wallet_id: &str) -> Result<usize, String> {
    ensure_rustls_provider();
    let db = state::open_voting_db(db_path, wallet_id)?;
    zcash_voting::precompute::reset_vote_tree(&db, "")
        .map_err(|e| format!("clear_tree_sync_session failed: {e}"))?;
    Ok(1)
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::prelude::*;
    use pasta_curves::Fp;
    use std::{
        io::{Read, Write},
        net::TcpListener,
        thread,
    };
    use vote_commitment_tree::{MemoryTreeServer, MerkleHashVote};

    const ROUND_ID: &str = "0000000000000000000000000000000000000000000000000000000000000001";

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
        let server = start_tree_server(1, vec![1], 2);

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
        assert_eq!(
            witness
                .auth_path
                .iter()
                .map(hex::encode)
                .collect::<Vec<_>>(),
            vec![
                "7a515983cec6c21e27c2f24fbc31c54d698400d33300ebc7f4677cb71b529403",
                "82a64809dbe974e7d141cebe86442be2fb7f9b9a9eeb1f75f462d6e7e8202336",
                "14815bae396c839e1210560d74ef1cdb97851d89f999b6e8e4128a08fdb4a912",
                "8c3074d3f71c5c6316c5d2a536dd5a79b694d562436eac88eccc51b551f4af2e",
                "878d8066cbd4d0073520041c2fe41c3b8b1933041d8b862337378474a6405d14",
                "306c6fa59275c245f89ccb1a857624f8d78ae999035d33aa66d0a65b27314f38",
                "953990ee917dce3d11f332fa6539f0e932fa11973828163943501d67b3373d15",
                "74cb897bc0643f418ac9a2eaaafaeb83179d6d6fa54ef6d559b32998b747020f",
                "a0b190e21a231d274275f20e4c40af39e5387d66339e1f436e23a5e70618431f",
                "e01482b9f9d66be7feb94d3ba771dec9dc299ecaf91edd612e15cb718c558e01",
                "30d9c5b9372fbad01fef2baa713cfaba14d0eb7d2d5ffd29381be274468eb800",
                "07023d01f99b5c7a2495449156fdfea3d47476ff9a5cd7a65f1aec743a1e9e31",
                "f86737aa6004422175918549ffecb01dd7b7893dd4659e8de9c529810639761e",
                "7fd484623a74052f1eeb4326c7ed34a2708d0343ebe717aa3ab2140a2ab42c30",
                "09385fd5ab538ac5f24451b30fc597a2b3f1a6022d92e50c6cf81a5e87a97715",
                "053114f4ba1aa6a2ce1a7c7eb1816f3d4906941eb3f86d7acb0a69b2efc35435",
                "02bcecd24479b7017f0d1ef5b404fcda609126d79c4d3b32e0d3639918d0c333",
                "bb61ef6c5b7013f54215cf9e52cec51739bb6c783c154666e9ccb63baaf4791c",
                "892d340244e211747dacdaf755c7423a5514f4c17d1bbe5f9b6afc86cb7e6c35",
                "2f405cdca85c479d2207e41deef7589e63d7d55e8dd7c26ecc6fce748e12372d",
                "617ef09aa96820c33e241c6f483faca32fb407775eedce8f7bd6e8ae48ea8d25",
                "b25282f8717a7d0de5b799ea8e6d13c298cb0058388af568818b53bbe1ba5824",
                "0d6709c82b101cfed97d7923df40fe28c90a6b982a9239b16496df6f6efbe530",
                "1a872423eac38fa63d3e848cbe8d857f2e6da3c3f4d4b8cdc9962dda06def715",
            ]
        );
    }

    #[test]
    fn sync_commitment_tree_happy_path_accepts_paginated_leaves() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let server = start_tree_server(2, vec![1, 2], 3);

        let height = sync_commitment_tree(
            db_path.to_str().unwrap(),
            "wallet-paginated-sync",
            ROUND_ID,
            &server,
        )
        .unwrap();

        assert_eq!(height, 2);
    }

    #[test]
    fn generate_van_witness_reports_missing_bundle_before_sync_requirement() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = generate_van_witness(db_path.to_str().unwrap(), "wallet-1", "round-1", 0, 100)
            .unwrap_err();

        assert!(err.contains("bundle_index 0 is out of range for 0 voting bundles"));
    }

    #[test]
    fn generate_van_witness_rejects_out_of_range_bundle_before_tree_work() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = state::open_voting_db(db_path.to_str().unwrap(), "wallet-out-of-range").unwrap();
        state::init_voting_round(&db, &test_round_params(), None).unwrap();
        db.setup_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();

        let err = generate_van_witness(
            db_path.to_str().unwrap(),
            "wallet-out-of-range",
            ROUND_ID,
            1,
            100,
        )
        .unwrap_err();

        assert!(err.contains("bundle_index 1 is out of range for 1 voting bundles"));
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
                let from_height = query_u32(path, "from_height").unwrap_or(0);
                let to_height = query_u32(path, "to_height").unwrap_or(height);
                // Return one block per response when more data remains, matching
                // the paginated tree API exposed by zcash_voting tree sync.
                let Some(block) = blocks
                    .iter()
                    .find(|block| block.height >= from_height && block.height <= to_height)
                else {
                    return r#"{"blocks":[]}"#.to_string();
                };
                let next_from_height = blocks
                    .iter()
                    .find(|next| next.height > block.height && next.height <= to_height)
                    .map(|next| format!(r#","next_from_height":{}"#, next.height))
                    .unwrap_or_default();
                format!(
                    r#"{{"blocks":[{{"height":{},"start_index":{},"leaves":["{}"],"root":"{}"}}]{}}}"#,
                    block.height, block.start_index, block.leaf, block.root, next_from_height
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
                leaf: fp_base64(value),
                root: fp_base64_from_fp(root),
            });
        }

        let latest_root = blocks.last().map(|block| block.root.clone());
        (latest_root, blocks)
    }

    fn query_u32(path: &str, key: &str) -> Option<u32> {
        path.split('?').nth(1)?.split('&').find_map(|pair| {
            let (name, value) = pair.split_once('=')?;
            (name == key).then(|| value.parse().ok()).flatten()
        })
    }

    fn fp_base64(value: u64) -> String {
        fp_base64_from_fp(Fp::from(value))
    }

    fn fp_base64_from_fp(value: Fp) -> String {
        BASE64_STANDARD.encode(MerkleHashVote::from_fp(value).to_bytes())
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
