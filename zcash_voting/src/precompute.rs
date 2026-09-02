//! Precomputation APIs for delegation inputs.
//!
//! [`precompute_snapshot_bundles`] persists the canonical bundle plan for a
//! snapshot-stable note set, samples padded-note secrets, and warms PIR for
//! real notes plus padded-slot nullifiers. That path does not need a hotkey or
//! wallet DB; witnesses still come from `PreparedDelegationBundle::precompute`
//! or [`prepare_delegation_bundle`](crate::delegate::prepare_delegation_bundle).
//!
//! Lower-level helpers remain available for callers that already persisted
//! intermediate state. See the `zcash-voting-wallet-example` workspace crate
//! for caller-oriented precompute orchestration.

#[allow(unused_imports)]
pub(crate) use crate::backend::{pasta_curves, zcash_client_sqlite};
use std::borrow::Borrow;

use std::{
    collections::HashMap,
    sync::{Arc, Mutex, OnceLock},
};

use zcash_client_sqlite::WalletDb;

use crate::{
    note_bundling::BundlePolicy,
    round::VotingDb,
    types::{
        NoteInfo, PirCachePrecomputeResult, PirCacheValidationReport, VotingError, WitnessData,
    },
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

/// Result of [`precompute_snapshot_bundles`].
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SnapshotBundlePrecomputeReport {
    /// Canonical layout persisted (or validated) from the snapshot note set.
    pub layout: BundleLayout,
    /// PIR warmup for each persisted bundle, in bundle-index order.
    pub bundles: Vec<PirPrecomputeReport>,
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
///
/// For each confirmed bundle that has not yet submitted a vote, this also
/// verifies that the confirmed event position contains its delegation VAN.
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

/// Drops cached vote tree state and, for round-scoped resets, clears locally
/// prepared unsigned delegation setup fields so interrupted Keystone requests
/// can be rebuilt safely. Imported delegation capabilities and bundles with a
/// successful persisted proof are preserved.
///
/// Round-scoped cleanup is mainly for the restart mid-signing case: if the app
/// dies after `build_governance_pczt` persisted `pczt_sighash` (and related
/// setup columns) but before the user finishes signing, the next startup tries
/// to rebuild the Keystone request and `store_delegation_data` refuses to
/// overwrite those fields. Clearing unsigned setup for that round lets setup
/// run again without touching bundles that already have a successful proof,
/// Keystone signatures, or a stored `delegation_tx_hash`. Proved bundles retain
/// the setup fields that later signing must reproduce.
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

/// Fetches and persists PIR proofs for notes that survive `bundle_policy`.
///
/// Callers pass the selected snapshot set against the IMT root the connected
/// PIR server currently serves, keyed by `network`. This plans first with the
/// same path round setup uses, so sub-ballot bundles and the privacy-trim tail
/// are not PIR-queried. Pass the same [`crate::note_bundling::BundlePolicy`]
/// the wallet will later persist at round setup.
///
/// Padded-slot nullifiers are not an input here: they only exist after bundle
/// rows and padded-note secrets are initialized. Use
/// [`precompute_snapshot_bundles`] once the round exists and the snapshot note
/// set is frozen.
///
/// Proofs can be warmed before any round or bundle exists, and later checked
/// against a round's expected root with [`validate_cached_pir_proofs`]. The
/// delegation prove path reads the same cache, so real-note proofs warmed here
/// are never refetched at proving time. A cached row that fails to decode or
/// verify is treated as a miss and overwritten. Each call prunes cache rows
/// created more than four weeks ago before checking or fetching proofs.
pub fn precompute_pir_proofs(
    db: &VotingDb,
    notes: &[NoteInfo],
    bundle_policy: crate::note_bundling::BundlePolicy,
    network: Network,
    pir_client: &pir_client::PirClientBlocking,
) -> Result<PirCachePrecomputeResult, VotingError> {
    db.precompute_pir_proof_cache(notes, bundle_policy, network, pir_client)
}

/// Classifies the cached PIR proofs for the given nullifiers against an
/// expected IMT root (e.g. a round's `nullifier_imt_root`). Offline — the PIR
/// server is never contacted; mismatches are reported, not raised.
pub fn validate_cached_pir_proofs(
    db: &VotingDb,
    notes: &[NoteInfo],
    extra_nullifiers: &[Vec<u8>],
    network: Network,
    expected_root: &[u8],
) -> Result<PirCacheValidationReport, VotingError> {
    db.validate_pir_proof_cache(notes, extra_nullifiers, network, expected_root)
}

/// Persists the canonical bundle plan for a snapshot-stable note set, samples
/// padded-note secrets, and warms PIR for every real note plus each bundle's
/// padded-slot nullifiers.
///
/// Call this after the wallet is scanned through the round snapshot height, so
/// [`crate::selection::select_snapshot_note_infos`] is historically frozen.
/// The round must already exist: PIR targets the stored `nullifier_imt_root`.
/// No hotkey, spending seed, or wallet DB is required.
///
/// Bundle rows are first-write-wins. That is the intended lock-in once the
/// snapshot set is known. Later
/// [`crate::delegate::prepare_delegation_bundle`] re-selects the same
/// historical notes and must reproduce this plan. `reset_voting_session_state`
/// does not clear bundle rows.
///
/// Witnesses are not generated here;
/// [`crate::delegate::prepare_delegation_bundle`] still warms them from the
/// snapshot tree state.
///
/// The connected PIR client must serve the round's `nullifier_imt_root` for
/// any proof that is not already cached. Retries are idempotent: secrets are
/// sampled for every bundle before any PIR fetch, so a later retry still has
/// authoritative padding for every index.
///
/// # Errors
///
/// Returns [`VotingError::InvalidInput`] when the round is missing, the
/// caller network does not match the stored round, the notes cannot be
/// planned, or they do not reproduce already-persisted bundle rows.
pub fn precompute_snapshot_bundles(
    db: &VotingDb,
    round_id: &str,
    notes: &[NoteInfo],
    bundle_policy: BundlePolicy,
    pir_client: &pir_client::PirClientBlocking,
    network: Network,
) -> Result<SnapshotBundlePrecomputeReport, VotingError> {
    db.require_round_network(round_id, network, "snapshot bundle precompute")?;
    let layout = db.ensure_bundles_with_policy(round_id, notes, bundle_policy)?;
    if layout.bundle_count == 0 {
        return Ok(SnapshotBundlePrecomputeReport {
            layout,
            bundles: Vec::new(),
        });
    }

    let policy = db.effective_bundle_policy(round_id, bundle_policy)?;
    let planned = crate::round::note_bundles_with_policy(notes, policy)?;
    if planned.len() as u32 != layout.bundle_count {
        return Err(VotingError::Internal {
            message: format!(
                "planned bundle count {} does not match persisted layout {}",
                planned.len(),
                layout.bundle_count
            ),
        });
    }

    for (bundle_index, bundle_notes) in planned.iter().enumerate() {
        db.ensure_padded_secrets(round_id, bundle_index as u32, bundle_notes)?;
    }

    let mut bundles = Vec::with_capacity(planned.len());
    for (bundle_index, bundle_notes) in planned.iter().enumerate() {
        bundles.push(delegation_pir(
            db,
            round_id,
            bundle_index as u32,
            bundle_notes,
            pir_client,
            network,
        )?);
    }

    Ok(SnapshotBundlePrecomputeReport { layout, bundles })
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
                                num_items: pir_types::TIER1_ROWS,
                                item_size_bits: pir_types::TIER1_ITEM_BITS,
                                poly_len: pir_types::DEFAULT_YPIR_POLY_LEN,
                            })
                            .unwrap(),
                        )),
                        "/root" => Ok(transport_response(
                            serde_json::to_vec(&pir_types::RootInfo {
                                zcash_network: pir_types::ZcashNetwork::Test,
                                nullifier_pool: pir_types::NULLIFIER_POOL.to_owned(),
                                dataset_version: pir_types::DATASET_VERSION,
                                circuit_root: hex::encode([0u8; 32]),
                                pir_root: hex::encode([0u8; 32]),
                                num_ranges: 1,
                                pir_layout: pir_types::COMPILED_PIR_LAYOUT,
                                pir_depth: pir_types::PIR_DEPTH,
                                tier1_rows: pir_types::TIER1_ROWS,
                                tier1_row_bytes: pir_types::TIER1_ROW_BYTES,
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
            privacy_trim_dropped_bundles: 0,
            privacy_trim_dropped_notes: 0,
            privacy_trim_dropped_value_zatoshi: 0,
        };
        let pir_client = pir_client::PirClientBlocking::with_transport(
            "https://pir.test",
            pir_types::COMPILED_PIR_LAYOUT,
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

    #[test]
    fn precompute_pir_proofs_wrapper_delegates_and_surfaces_input_errors() {
        struct StaticPirTransport;

        impl pir_client::Transport for StaticPirTransport {
            fn get<'a>(&'a self, url: &'a str) -> pir_client::TransportFuture<'a> {
                Box::pin(async move {
                    let path = {
                        let without_scheme =
                            url.split_once("://").map(|(_, rest)| rest).unwrap_or(url);
                        without_scheme
                            .find('/')
                            .map(|idx| without_scheme[idx..].to_owned())
                            .unwrap_or_else(|| "/".to_owned())
                    };
                    let respond = |body: Vec<u8>| pir_client::TransportResponse {
                        status: 200,
                        headers: Vec::new(),
                        body,
                    };
                    match path.as_str() {
                        "/tier0" => Ok(respond(vec![
                            0;
                            ((1usize << pir_types::TIER0_LAYERS) - 1) * 32
                                + pir_types::TIER1_ROWS * 64
                        ])),
                        "/params/tier1" => Ok(respond(
                            serde_json::to_vec(&pir_types::YpirScenario {
                                num_items: pir_types::TIER1_ROWS,
                                item_size_bits: pir_types::TIER1_ITEM_BITS,
                                poly_len: pir_types::DEFAULT_YPIR_POLY_LEN,
                            })
                            .unwrap(),
                        )),
                        "/root" => Ok(respond(
                            serde_json::to_vec(&pir_types::RootInfo {
                                zcash_network: pir_types::ZcashNetwork::Test,
                                nullifier_pool: pir_types::NULLIFIER_POOL.to_owned(),
                                dataset_version: pir_types::DATASET_VERSION,
                                circuit_root: hex::encode([0u8; 32]),
                                pir_root: hex::encode([0u8; 32]),
                                num_ranges: 1,
                                pir_layout: pir_types::COMPILED_PIR_LAYOUT,
                                pir_depth: pir_types::PIR_DEPTH,
                                tier1_rows: pir_types::TIER1_ROWS,
                                tier1_row_bytes: pir_types::TIER1_ROW_BYTES,
                                height: None,
                            })
                            .unwrap(),
                        )),
                        _ => Err(anyhow::anyhow!("unexpected GET {path}")),
                    }
                })
            }

            fn post<'a>(&'a self, url: &'a str, _body: Vec<u8>) -> pir_client::TransportFuture<'a> {
                let _ = url;
                Box::pin(async move { Err(anyhow::anyhow!("unexpected POST")) })
            }
        }

        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id("test-wallet");
        let pir_client = pir_client::PirClientBlocking::with_transport(
            "https://pir.test",
            pir_types::COMPILED_PIR_LAYOUT,
            std::sync::Arc::new(StaticPirTransport),
        )
        .unwrap();

        // Empty inputs run the whole wrapper path without any PIR query and
        // report the served (all-zero) root.
        let result = precompute_pir_proofs(
            &db,
            &[],
            crate::note_bundling::BundlePolicy::default(),
            Network::Testnet,
            &pir_client,
        )
        .unwrap();
        assert_eq!(result.cached_count, 0);
        assert_eq!(result.fetched_count, 0);
        assert_eq!(result.served_root, vec![0u8; 32]);

        // Malformed caller input surfaces through the wrapper as InvalidInput
        // at planning time, before any PIR query.
        let short = NoteInfo {
            commitment: vec![1; 32],
            nullifier: vec![0x07; 31],
            value: crate::governance::BALLOT_DIVISOR,
            position: 0,
            diversifier: vec![3; 11],
            rho: vec![4; 32],
            rseed: vec![5; 32],
            scope: 0,
            ufvk_str: "uviewtest".to_string(),
        };
        let err = precompute_pir_proofs(
            &db,
            &[short],
            crate::note_bundling::BundlePolicy::default(),
            Network::Testnet,
            &pir_client,
        )
        .unwrap_err();
        assert!(
            err.to_string()
                .contains("notes[0].nullifier must be 32 bytes, got 31"),
            "{err}"
        );

        // Sub-ballot selected notes are planned away before any PIR query.
        let dust = vec![NoteInfo {
            commitment: vec![1; 32],
            nullifier: vec![2; 32],
            value: 100,
            position: 0,
            diversifier: vec![3; 11],
            rho: vec![4; 32],
            rseed: vec![5; 32],
            scope: 0,
            ufvk_str: "uviewtest".to_string(),
        }];
        let result = precompute_pir_proofs(
            &db,
            &dust,
            crate::note_bundling::BundlePolicy::default(),
            Network::Testnet,
            &pir_client,
        )
        .unwrap();
        assert_eq!(result.cached_count, 0);
        assert_eq!(result.fetched_count, 0);
    }

    fn dummy_note(position: u64, value: u64) -> NoteInfo {
        NoteInfo {
            commitment: vec![position as u8; 32],
            nullifier: vec![(position as u8).wrapping_add(10); 32],
            value,
            position,
            diversifier: vec![3; 11],
            rho: vec![4; 32],
            rseed: vec![5; 32],
            scope: 0,
            ufvk_str: "uviewtest".to_string(),
        }
    }

    fn testnet_pir_client() -> pir_client::PirClientBlocking {
        struct StaticPirTransport;

        impl pir_client::Transport for StaticPirTransport {
            fn get<'a>(&'a self, url: &'a str) -> pir_client::TransportFuture<'a> {
                Box::pin(async move {
                    let path = {
                        let without_scheme =
                            url.split_once("://").map(|(_, rest)| rest).unwrap_or(url);
                        without_scheme
                            .find('/')
                            .map(|idx| without_scheme[idx..].to_owned())
                            .unwrap_or_else(|| "/".to_owned())
                    };
                    let respond = |body: Vec<u8>| pir_client::TransportResponse {
                        status: 200,
                        headers: Vec::new(),
                        body,
                    };
                    match path.as_str() {
                        "/tier0" => Ok(respond(vec![
                            0;
                            ((1usize << pir_types::TIER0_LAYERS) - 1) * 32
                                + pir_types::TIER1_ROWS * 64
                        ])),
                        "/params/tier1" => Ok(respond(
                            serde_json::to_vec(&pir_types::YpirScenario {
                                num_items: pir_types::TIER1_ROWS,
                                item_size_bits: pir_types::TIER1_ITEM_BITS,
                                poly_len: pir_types::DEFAULT_YPIR_POLY_LEN,
                            })
                            .unwrap(),
                        )),
                        "/root" => Ok(respond(
                            serde_json::to_vec(&pir_types::RootInfo {
                                zcash_network: pir_types::ZcashNetwork::Test,
                                nullifier_pool: pir_types::NULLIFIER_POOL.to_owned(),
                                dataset_version: pir_types::DATASET_VERSION,
                                circuit_root: hex::encode([0u8; 32]),
                                pir_root: hex::encode([0u8; 32]),
                                num_ranges: 1,
                                pir_layout: pir_types::COMPILED_PIR_LAYOUT,
                                pir_depth: pir_types::PIR_DEPTH,
                                tier1_rows: pir_types::TIER1_ROWS,
                                tier1_row_bytes: pir_types::TIER1_ROW_BYTES,
                                height: None,
                            })
                            .unwrap(),
                        )),
                        _ => Err(anyhow::anyhow!("unexpected GET {path}")),
                    }
                })
            }

            fn post<'a>(&'a self, url: &'a str, _body: Vec<u8>) -> pir_client::TransportFuture<'a> {
                let _ = url;
                Box::pin(async move { Err(anyhow::anyhow!("unexpected POST")) })
            }
        }

        pir_client::PirClientBlocking::with_transport(
            "https://pir.test",
            pir_types::COMPILED_PIR_LAYOUT,
            std::sync::Arc::new(StaticPirTransport),
        )
        .unwrap()
    }

    fn snapshot_round_params(nullifier_imt_root: Vec<u8>) -> crate::round::RoundParams {
        crate::round::RoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 100,
            ea_pk: vec![1; 32],
            nc_root: vec![2; 32],
            nullifier_imt_root,
        }
    }

    #[test]
    fn precompute_snapshot_bundles_requires_an_existing_round() {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id("test-wallet");
        let err = precompute_snapshot_bundles(
            &db,
            ROUND_ID,
            &[dummy_note(0, crate::governance::BALLOT_DIVISOR)],
            BundlePolicy::default(),
            &testnet_pir_client(),
            Network::Testnet,
        )
        .unwrap_err();
        assert!(err.to_string().contains("round not found"), "{err}");
        assert_eq!(db.get_bundle_count(ROUND_ID).unwrap(), 0);
    }

    #[test]
    fn precompute_snapshot_bundles_is_a_noop_for_sub_ballot_notes() {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id("test-wallet");
        db.create_round(Network::Testnet, &snapshot_round_params(vec![3; 32]), None)
            .unwrap();

        let result = precompute_snapshot_bundles(
            &db,
            ROUND_ID,
            &[dummy_note(0, 100)],
            BundlePolicy::default(),
            &testnet_pir_client(),
            Network::Testnet,
        )
        .unwrap();
        assert_eq!(result.layout.bundle_count, 0);
        assert!(result.bundles.is_empty());
        assert_eq!(db.get_bundle_count(ROUND_ID).unwrap(), 0);
    }

    #[test]
    fn precompute_snapshot_bundles_persists_bundles_and_padded_secrets_before_pir() {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id("test-wallet");
        db.create_round(Network::Testnet, &snapshot_round_params(vec![3; 32]), None)
            .unwrap();
        let notes = vec![dummy_note(0, crate::governance::BALLOT_DIVISOR)];

        let err = precompute_snapshot_bundles(
            &db,
            ROUND_ID,
            &notes,
            BundlePolicy::default(),
            &testnet_pir_client(),
            Network::Testnet,
        )
        .unwrap_err();
        let message = err.to_string();
        assert!(
            message.contains("failed to decode UFVK while deriving padded nullifiers")
                || message.contains("unexpected POST"),
            "unexpected error: {message}",
        );
        assert_eq!(db.get_bundle_count(ROUND_ID).unwrap(), 1);
        let secrets = crate::storage::queries::load_padded_note_secrets_optional(
            &db.conn(),
            ROUND_ID,
            "test-wallet",
            0,
        )
        .unwrap()
        .expect("padded secrets must be sampled before PIR");
        assert_eq!(secrets.len(), crate::governance::BUNDLE_NOTE_SLOTS - 1);

        db.ensure_bundles_with_policy(ROUND_ID, &notes, BundlePolicy::default())
            .unwrap();
    }

    #[test]
    fn precompute_snapshot_bundles_reuses_cached_real_note_proofs_for_a_full_bundle() {
        use crate::backend::{orchard, pasta_curves, zcash_keys};
        use orchard::{
            note::{NoteVersion, Rho},
            value::NoteValue,
        };
        use pasta_curves::group::ff::PrimeField;
        use pasta_curves::pallas;
        use voting_circuits::delegation::ImtProvider;
        use voting_crypto_deps::rand::rngs::OsRng;
        use zcash_keys::keys::UnifiedSpendingKey;
        use zip32::{AccountId, Scope};

        let seed = [0x42u8; 32];
        let account = AccountId::try_from(0u32).unwrap();
        let usk = UnifiedSpendingKey::from_seed(&Network::Testnet, &seed, account).unwrap();
        let ufvk = usk.to_unified_full_viewing_key();
        let fvk = ufvk.orchard().unwrap().clone();
        let address = fvk.address_at(0u32, Scope::External);

        let mut rng = OsRng;
        let mut notes = Vec::new();
        for position in 0..crate::governance::BUNDLE_NOTE_SLOTS {
            let (_, _, parent_note) = orchard::Note::dummy(&mut rng, None, NoteVersion::V2);
            let note = orchard::Note::new(
                address,
                NoteValue::from_raw(13_000_000),
                Rho::from_nf_old(parent_note.nullifier(&fvk)),
                NoteVersion::V3,
                &mut rng,
            );
            notes.push(
                NoteInfo::from_orchard_note(
                    &note,
                    position as u64,
                    Scope::External,
                    &ufvk,
                    &Network::Testnet,
                )
                .unwrap(),
            );
        }

        let imt = voting_circuits::delegation::SpacedLeafImtProvider::new();
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id("test-wallet");
        db.create_round(
            Network::Testnet,
            &snapshot_round_params(imt.root().to_repr().to_vec()),
            None,
        )
        .unwrap();
        {
            let conn = db.conn();
            for note in &notes {
                let nf_bytes: [u8; 32] = note.nullifier.as_slice().try_into().unwrap();
                let nf = Option::from(pallas::Base::from_repr(nf_bytes)).unwrap();
                let circuit_proof = imt.non_membership_proof(nf).unwrap();
                let proof = pir_client::ImtProofData {
                    root: circuit_proof.root,
                    nf_bounds: circuit_proof.nf_bounds,
                    leaf_pos: circuit_proof.leaf_pos,
                    path: circuit_proof.path,
                };
                crate::storage::queries::store_pir_cache_proof(
                    &conn,
                    "test-wallet",
                    Network::Testnet,
                    &nf_bytes,
                    &proof,
                )
                .unwrap();
            }
        }

        let result = precompute_snapshot_bundles(
            &db,
            ROUND_ID,
            &notes,
            BundlePolicy::default(),
            &testnet_pir_client(),
            Network::Testnet,
        )
        .unwrap();
        assert_eq!(result.layout.bundle_count, 1);
        assert_eq!(result.bundles.len(), 1);
        assert_eq!(
            result.bundles[0].cached,
            crate::governance::BUNDLE_NOTE_SLOTS as u32
        );
        assert_eq!(result.bundles[0].fetched, 0);

        let again = precompute_snapshot_bundles(
            &db,
            ROUND_ID,
            &notes,
            BundlePolicy::default(),
            &testnet_pir_client(),
            Network::Testnet,
        )
        .unwrap();
        assert_eq!(again, result);
        let secrets = crate::storage::queries::load_padded_note_secrets_optional(
            &db.conn(),
            ROUND_ID,
            "test-wallet",
            0,
        )
        .unwrap()
        .expect("full bundles still store an empty padded-secret list");
        assert!(secrets.is_empty());
    }

    #[test]
    fn validate_cached_pir_proofs_wrapper_reports_offline() {
        use crate::types::PirProofCacheStatus;

        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id("test-wallet");
        let notes = vec![NoteInfo {
            commitment: vec![1; 32],
            nullifier: vec![2; 32],
            value: 10,
            position: 0,
            diversifier: vec![3; 11],
            rho: vec![4; 32],
            rseed: vec![5; 32],
            scope: 0,
            ufvk_str: "uviewtest".to_string(),
        }];

        // No PIR client anywhere in sight: the wrapper works fully offline.
        let report =
            validate_cached_pir_proofs(&db, &notes, &[], Network::Testnet, &[0u8; 32]).unwrap();
        assert_eq!(report.entries.len(), 1);
        assert_eq!(report.entries[0].status, PirProofCacheStatus::Missing);
        assert_eq!(report.missing_count, 1);

        let err = validate_cached_pir_proofs(&db, &notes, &[], Network::Testnet, &[0xBB; 31])
            .unwrap_err();
        assert!(
            err.to_string()
                .contains("expected IMT root must be 32 bytes, got 31"),
            "{err}"
        );
    }
}

#[cfg(test)]
mod tree_sync_tests {
    use super::*;
    pub(crate) use crate::backend::pasta_curves;
    use pasta_curves::group::ff::PrimeField;
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
        db.conn()
            .execute(
                "UPDATE bundles SET gov_comm = ?1
                 WHERE round_id = ?2 AND wallet_id = ?3 AND bundle_index = 0",
                rusqlite::params![Fp::from(1).to_repr().as_slice(), ROUND_ID, WALLET_ID],
            )
            .unwrap();
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
    pub(crate) use crate::backend::pasta_curves;
    use crate::storage::queries;
    use pasta_curves::group::ff::PrimeField;
    use pasta_curves::Fp;

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
                 tx1_effects = :tx1_effects,
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
                ":tx1_effects": crate::tx1::placeholder_tx1_effects(),
                ":secrets": vec![0xBBu8; 64],
                ":padded": vec![0xCCu8; 32],
            },
        )
        .unwrap();
    }

    fn has_unsigned_setup_fields(db: &VotingDb, round_id: &str, bundle_index: u32) -> bool {
        let conn = db.conn();
        let has_sighash =
            queries::load_pczt_sighash(&conn, round_id, WALLET_ID, bundle_index).is_ok();
        let has_tx1_effects =
            queries::load_tx1_effects(&conn, round_id, WALLET_ID, bundle_index).is_ok();
        assert_eq!(has_sighash, has_tx1_effects);
        has_sighash
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
    fn reset_voting_session_state_preserves_proved_bundle_setup_fields() {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id(WALLET_ID);
        db.create_round(crate::Network::Testnet, &round_params(ROUND_ID), None)
            .unwrap();
        db.ensure_bundles(ROUND_ID, &[note(0), note(1)]).unwrap();
        seed_unsigned_setup_fields(&db, ROUND_ID, 0);
        seed_unsigned_setup_fields(&db, ROUND_ID, 1);
        queries::store_proof(&db.conn(), ROUND_ID, WALLET_ID, 0, &[0xAB; 96]).unwrap();

        reset_voting_session_state(&db, ROUND_ID).unwrap();

        assert!(has_unsigned_setup_fields(&db, ROUND_ID, 0));
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
    fn confirmed_local_delegation_survives_recovery_and_session_cleanup() {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id(WALLET_ID);
        db.create_round(crate::Network::Testnet, &round_params(ROUND_ID), None)
            .unwrap();
        let conn = db.conn();
        queries::insert_bundle(&conn, ROUND_ID, WALLET_ID, 0, &[0]).unwrap();
        queries::insert_bundle(&conn, ROUND_ID, WALLET_ID, 1, &[1]).unwrap();
        drop(conn);

        for bundle_index in 0..=1 {
            seed_unsigned_setup_fields(&db, ROUND_ID, bundle_index);
            let rand = Fp::from(0x10 + u64::from(bundle_index)).to_repr();
            let commitment = Fp::from(0x20 + u64::from(bundle_index)).to_repr();
            db.conn()
                .execute(
                    "UPDATE bundles
                     SET van_comm_rand = :rand,
                         gov_comm = :commitment,
                         total_note_value = :value,
                         address_index = 0
                     WHERE round_id = :round_id
                       AND wallet_id = :wallet_id
                       AND bundle_index = :bundle_index",
                    rusqlite::named_params! {
                        ":round_id": ROUND_ID,
                        ":wallet_id": WALLET_ID,
                        ":bundle_index": bundle_index,
                        ":rand": &rand[..],
                        ":commitment": &commitment[..],
                        ":value": crate::governance::BALLOT_DIVISOR as i64,
                    },
                )
                .unwrap();
            db.store_van_position(ROUND_ID, bundle_index, 40 + bundle_index)
                .unwrap();
        }

        // Bundle 0 is the canonical confirmed state. Bundle 1 exercises the
        // position guard when a standalone confirmation write preceded its hash.
        db.store_delegation_tx_hash(ROUND_ID, 0, "confirmed-delegation")
            .unwrap();
        assert_eq!(
            db.get_delegation_tx_hash(ROUND_ID, 0).unwrap().as_deref(),
            Some("confirmed-delegation")
        );

        reset_voting_session_state(&db, ROUND_ID).unwrap();

        for bundle_index in 0..=1 {
            assert!(has_unsigned_setup_fields(&db, ROUND_ID, bundle_index));
            let conn = db.conn();
            let zkp2 = queries::load_zkp2_inputs(&conn, ROUND_ID, WALLET_ID, bundle_index).unwrap();
            assert_eq!(
                zkp2.gov_comm_rand,
                Fp::from(0x10 + u64::from(bundle_index)).to_repr().to_vec()
            );
            assert_eq!(zkp2.total_note_value, crate::governance::BALLOT_DIVISOR);
            assert_eq!(zkp2.address_index, 0);
            let gov_comm: Vec<u8> = conn
                .query_row(
                    "SELECT gov_comm FROM bundles
                     WHERE round_id = ?1 AND wallet_id = ?2 AND bundle_index = ?3",
                    rusqlite::params![ROUND_ID, WALLET_ID, bundle_index],
                    |row| row.get(0),
                )
                .unwrap();
            assert_eq!(
                gov_comm,
                Fp::from(0x20 + u64::from(bundle_index)).to_repr().to_vec()
            );
        }
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
