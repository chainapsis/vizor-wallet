//! The DAG-sync pass: private spend checks, change discovery, and external
//! witnesses for Ironwood notes, all keyed by commitment-tree position.
//!
//! Compact scanning discovers payments from third parties; this pass makes a
//! restoring wallet correct before that scan reaches the tip. For every known
//! note it asks the nullifier tables whether the note is spent, reads the
//! spending transaction's action records to find change, and fetches a Merkle
//! path so unspent notes are spendable without a complete local shard.
//!
//! Every pass issues exactly the generation's query envelope; what the wallet
//! has pending changes only which rows the (indistinguishable) queries target.
//! A pass runs only while some scan range below the anchor is still pending
//! or a note lacks a witness, so a synced wallet sends nothing.

use std::collections::{HashMap, HashSet};

use http::Method;
use incrementalmerkletree::Position;
use zakura_pir_memo::{
    dag::{DagSyncPlanner, PlannedQuery, TableSessions, Target},
    spend::scan_bucket,
    witness::reconstruct,
    DatabaseId, PirRow, WitnessCap, RECORDS_PER_ROW,
};
use zcash_client_backend::data_api::{
    memo_pir::{MemoPirRead, MemoPirSnapshotAnchor, MemoPirSnapshotStatus},
    pir_dag::{
        discover_change, ActionRecordView, DagNote, PirDagRead, PirDagWrite, PirWitnessRecord,
        SpendMeta,
    },
    scanning::ScanPriority,
    WalletCommitmentTrees, WalletRead,
};
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::BlockHeight;

use crate::wallet::{db::with_wallet_db_write_lock, network::WalletNetwork};

use super::memo_pir::{
    client_protocol_error, connect_table, endpoint_for, endpoint_path, fetch_manifest,
    routed_request, MAX_MANIFEST_BYTES, MAX_PIR_BODY_BYTES,
};
use super::{SyncError, WalletDatabase};

/// Passes per run while nothing else is pending. A spend found in one pass
/// needs the next pass to read its transaction, and change found there needs
/// another for its own checks, so a chain of self-spends resolves one link
/// per pass; the rest waits for the next run.
const MAX_PASSES_AT_TIP: usize = 8;

/// Passes per run while compact scanning still has work: the pass runs after
/// every batch anyway, and one envelope per batch keeps the scan moving.
const MAX_PASSES_WHILE_SCANNING: usize = 1;

/// Blocks compact scanning covers between two passes while it has work. A
/// pass costs one envelope; spending it after every small batch would hold
/// the scan far more than it helps.
const BLOCKS_BETWEEN_PASSES: u64 = 2_000;

/// Queries of one envelope in flight at once. The envelope is fixed either
/// way; concurrency changes only how long a pass takes. Matches the
/// coordinator's per-table query slots so a burst is queued, not refused.
const QUERY_CONCURRENCY: usize = 2;

#[derive(Default)]
struct PassStats {
    passes: usize,
    spends: usize,
    change: usize,
    witnesses: usize,
}

/// Per-sync cached state: five table sessions pinned to one generation, the
/// public witness cap, and the spends awaiting attribution to a transaction.
pub(super) struct DagSync {
    endpoint: Option<String>,
    /// The generation anchor advertised at sync start, fetched once.
    anchor_hint: Option<BlockHeight>,
    sessions: Option<(TableSessions, WitnessCap)>,
    root_verified: bool,
    /// Blocks scanned since the last pass ran after a batch.
    blocks_since_pass: u64,
    /// Nullifiers already checked against the connected generation.
    checked: HashSet<[u8; 32]>,
    /// Spent notes whose spending transaction's records are still to be read.
    pending_spends: Vec<(Position, SpendMeta)>,
}

impl DagSync {
    pub(super) fn new(network: WalletNetwork) -> Self {
        Self {
            endpoint: endpoint_for(network),
            anchor_hint: None,
            blocks_since_pass: 0,
            sessions: None,
            root_verified: false,
            checked: HashSet::new(),
            pending_spends: Vec::new(),
        }
    }

    /// The height compact scanning should visit before the pending history,
    /// if the pass can be of use: the generation's anchor block, while it is
    /// not yet scanned. Authenticating the generation needs that block; in
    /// ascending order it would be scanned last, after every block the pass
    /// could have covered privately. Reads only public manifest data and the
    /// wallet's own scan state; a fetch failure just keeps the normal order.
    pub(super) async fn anchor_first_height(
        &mut self,
        db: &WalletDatabase,
    ) -> Result<Option<BlockHeight>, SyncError> {
        let Some(endpoint) = self.endpoint.as_deref() else {
            return Ok(None);
        };
        if self.anchor_hint.is_none() {
            match fetch_manifest(endpoint).await {
                Ok(manifest) => {
                    self.anchor_hint = Some(BlockHeight::from(manifest.anchor_height as u32));
                }
                Err(error) => {
                    log::warn!("sync: DAG pass could not read the generation anchor: {error}");
                    return Ok(None);
                }
            }
        }
        let anchor = self.anchor_hint.expect("set above");
        let scanned = db
            .block_metadata(anchor)
            .map_err(|error| SyncError::db(format!("block_metadata: {error}")))?
            .is_some();
        Ok((!scanned).then_some(anchor))
    }

    /// Runs after a compact batch of `batch_blocks` blocks: a pass every
    /// [`BLOCKS_BETWEEN_PASSES`] scanned blocks while the scan has work, and
    /// unconditionally once it has none.
    pub(super) async fn run_after_batch(
        &mut self,
        db: &mut WalletDatabase,
        batch_blocks: u64,
    ) -> Result<(), SyncError> {
        self.blocks_since_pass += batch_blocks;
        let scan_pending = db
            .suggest_scan_ranges()
            .map_err(|error| SyncError::db(format!("suggest_scan_ranges: {error}")))?
            .iter()
            .any(|range| range.priority() > ScanPriority::Scanned);
        if scan_pending && self.blocks_since_pass < BLOCKS_BETWEEN_PASSES {
            return Ok(());
        }
        self.blocks_since_pass = 0;
        self.run(db).await
    }

    pub(super) async fn run(&mut self, db: &mut WalletDatabase) -> Result<(), SyncError> {
        let Some(endpoint) = self.endpoint.clone() else {
            return Ok(());
        };
        let notes = db
            .dag_notes()
            .map_err(|error| SyncError::db(format!("dag_notes: {error}")))?;
        if notes.is_empty() && self.pending_spends.is_empty() {
            return Ok(());
        }

        if self.sessions.is_none() {
            // A service that does not (yet) serve all five tables is not an
            // error for the wallet: compact scanning remains correct, only
            // slower. Memo completion keeps its own, stricter, session.
            match connect_all(&endpoint).await {
                Ok(connected) => {
                    self.sessions = Some(connected);
                    self.root_verified = false;
                    self.checked.clear();
                }
                Err(error) => {
                    // Deferred, not disabled: a redeploy or a publish race
                    // clears within a batch or two, and the block-count gate
                    // already spaces out reconnect attempts.
                    log::warn!("sync: DAG pass deferred to a later pass: {error}");
                    return Ok(());
                }
            }
        }
        // Taken out of `self` for the pass so the pass can update the
        // spend and check state; put back only if every query succeeded.
        let (sessions, cap) = self.sessions.take().expect("connected above");
        let manifest = sessions.action.manifest();
        let anchor = sessions.action.snapshot_anchor();
        let anchor_height = BlockHeight::from(anchor.height);
        match db
            .memo_pir_snapshot_status(MemoPirSnapshotAnchor {
                height: anchor_height,
                block_hash: BlockHash::from_slice(&anchor.block_hash),
                ironwood_tree_size: anchor.ironwood_tree_size,
            })
            .map_err(|error| SyncError::db(format!("memo_pir_snapshot_status: {error}")))?
        {
            MemoPirSnapshotStatus::NotYetScanned => {
                self.sessions = Some((sessions, cap));
                return Ok(());
            }
            MemoPirSnapshotStatus::Mismatch => {
                return Err(SyncError::parse(
                    "PIR generation anchor disagrees with the locally scanned chain",
                ));
            }
            MemoPirSnapshotStatus::Accepted => {}
        }
        if !self.root_verified {
            verify_cap_root(db, &cap, anchor_height)?;
            self.root_verified = true;
        }

        // Compact scanning marks spends inside every range it scans, so a
        // spend check is only informative while a range below the anchor is
        // still pending (a restore in progress).
        let scan_ranges = db
            .suggest_scan_ranges()
            .map_err(|error| SyncError::db(format!("suggest_scan_ranges: {error}")))?;
        let scan_pending = scan_ranges
            .iter()
            .any(|range| range.priority() > ScanPriority::Scanned);
        let scan_pending_below_anchor = scan_ranges.iter().any(|range| {
            range.priority() > ScanPriority::Scanned && range.block_range().start < anchor_height
        });
        let max_passes = if scan_pending {
            MAX_PASSES_WHILE_SCANNING
        } else {
            MAX_PASSES_AT_TIP
        };
        let tree_size = manifest.ironwood_tree_size;

        let mut planner = DagSyncPlanner::new();
        let mut by_nullifier = HashMap::new();
        enqueue_notes(
            &notes,
            tree_size,
            scan_pending_below_anchor,
            &self.checked,
            &mut planner,
            &mut by_nullifier,
        );
        for (_, meta) in &self.pending_spends {
            planner.enqueue_actions(
                u64::from(meta.first_output_position),
                u64::from(meta.action_count),
                RECORDS_PER_ROW as u64,
            );
        }

        if planner.pending() == (0, 0, 0) {
            log::info!(
                "sync: DAG pass idle: {} note(s) known, nothing to check, witness, or discover",
                notes.len()
            );
        }
        let mut stats = PassStats::default();
        let result = self
            .drain(
                db,
                &sessions,
                &cap,
                &endpoint,
                &mut planner,
                &mut by_nullifier,
                &mut stats,
                tree_size,
                scan_pending_below_anchor,
                max_passes,
            )
            .await;
        // On failure the generation most likely aged out of retention
        // mid-pass; leaving the session dropped makes the sync's retry
        // reconnect to the current one instead of reusing this session.
        result?;
        self.sessions = Some((sessions, cap));

        if stats.passes > 0 {
            // Aggregate counts only: no positions, nullifiers, or txids.
            log::info!(
                "sync: DAG pass ran {} envelope(s): {} spend(s) recorded, {} change note(s) discovered, {} witness(es) stored privately",
                stats.passes,
                stats.spends,
                stats.change,
                stats.witnesses
            );
        }
        Ok(())
    }

    /// Runs passes until nothing is queued or the per-run cap is reached.
    #[allow(clippy::too_many_arguments)]
    async fn drain(
        &mut self,
        db: &mut WalletDatabase,
        sessions: &TableSessions,
        cap: &WitnessCap,
        endpoint: &str,
        planner: &mut DagSyncPlanner,
        by_nullifier: &mut HashMap<[u8; 32], Position>,
        stats: &mut PassStats,
        tree_size: u64,
        scan_pending_below_anchor: bool,
        max_passes: usize,
    ) -> Result<(), SyncError> {
        while planner.pending() != (0, 0, 0) && stats.passes < max_passes {
            stats.passes += 1;
            let queries = planner.plan(sessions).map_err(client_protocol_error)?;
            let mut found_spends = HashMap::new();
            let mut witness_parts: HashMap<u64, (Option<Vec<u8>>, Option<Vec<u8>>)> =
                HashMap::new();

            for (table, target, row) in issue_envelope(endpoint, sessions, queries).await? {
                match target {
                    Target::Dummy => {}
                    Target::Nullifier(nullifier) => {
                        self.checked.insert(nullifier);
                        if let Some(meta) = scan_bucket(row.bytes(), &nullifier) {
                            found_spends.entry(nullifier).or_insert(meta);
                        }
                    }
                    Target::ActionRow(row_index) => {
                        let first_position = row_index * RECORDS_PER_ROW as u64;
                        let records = action_records(&row, first_position);
                        stats.spends += attribute_spends(
                            db,
                            &mut self.pending_spends,
                            first_position,
                            &records,
                        )?;
                        let stored = with_wallet_db_write_lock(
                            "sync_engine.dag_sync.discover_change",
                            || discover_change(db, Position::from(first_position), &records),
                        )
                        .map_err(|error| SyncError::db(format!("discover_change: {error}")))?;
                        stats.change += stored;
                    }
                    Target::WitnessRoots(position) | Target::WitnessLeaves(position) => {
                        let parts = witness_parts.entry(position).or_default();
                        if table == DatabaseId::WitnessRoots {
                            parts.0 = Some(row.bytes().to_vec());
                        } else {
                            parts.1 = Some(row.bytes().to_vec());
                        }
                        if let (Some(roots), Some(leaves)) = (&parts.0, &parts.1) {
                            let witness =
                                reconstruct(position, leaves, roots, cap).map_err(|error| {
                                    SyncError::parse(format!("PIR witness rejected: {error}"))
                                })?;
                            let record = PirWitnessRecord {
                                position: Position::from(witness.position),
                                leaf: witness.leaf,
                                siblings: witness.siblings,
                                anchor_height: BlockHeight::from(witness.anchor_height as u32),
                                anchor_root: witness.root,
                            };
                            let stored = with_wallet_db_write_lock(
                                "sync_engine.dag_sync.put_pir_witness",
                                || db.put_pir_witness(&record),
                            )
                            .map_err(|error| SyncError::db(format!("put_pir_witness: {error}")))?;
                            if stored {
                                stats.witnesses += 1;
                            }
                        }
                    }
                }
            }

            // A spend is attributed once its transaction's records are read,
            // which is the next pass at the earliest.
            for (nullifier, meta) in found_spends {
                let Some(position) = by_nullifier.get(&nullifier).copied() else {
                    continue;
                };
                let meta = SpendMeta {
                    spend_height: BlockHeight::from(meta.spend_height),
                    first_output_position: Position::from(u64::from(meta.first_output_position)),
                    action_count: meta.action_count,
                };
                planner.enqueue_actions(
                    u64::from(meta.first_output_position),
                    u64::from(meta.action_count),
                    RECORDS_PER_ROW as u64,
                );
                self.pending_spends.push((position, meta));
            }

            // Change discovered this pass needs its own spend check and witness.
            let notes = db
                .dag_notes()
                .map_err(|error| SyncError::db(format!("dag_notes: {error}")))?;
            enqueue_notes(
                &notes,
                tree_size,
                scan_pending_below_anchor,
                &self.checked,
                planner,
                by_nullifier,
            );
        }
        Ok(())
    }
}

/// Queues the checks each known note still needs: a spend check while a
/// restore is in progress and the note is old enough to be in the tables, and
/// a witness fetch while neither the local shard tree nor a stored PIR path
/// can witness it.
fn enqueue_notes<A>(
    notes: &[DagNote<A>],
    tree_size: u64,
    scan_pending_below_anchor: bool,
    checked: &HashSet<[u8; 32]>,
    planner: &mut DagSyncPlanner,
    by_nullifier: &mut HashMap<[u8; 32], Position>,
) {
    for note in notes {
        if u64::from(note.position) >= tree_size {
            continue;
        }
        by_nullifier.insert(note.nullifier, note.position);
        if scan_pending_below_anchor && !checked.contains(&note.nullifier) {
            planner.enqueue_nullifier(note.nullifier);
        }
        if !note.has_witness && !note.witness_stabilized {
            planner.enqueue_witness(u64::from(note.position));
        }
    }
}

/// Sends every query of one envelope, at most `QUERY_CONCURRENCY` in flight,
/// and returns the decoded rows in issue order. The request set is fixed by
/// the planner before anything is sent, so concurrency does not change what
/// the server observes beyond timing.
async fn issue_envelope(
    endpoint: &str,
    sessions: &TableSessions,
    queries: Vec<PlannedQuery>,
) -> Result<Vec<(DatabaseId, Target, PirRow)>, SyncError> {
    use futures::stream::{StreamExt, TryStreamExt};

    let responses: Vec<Vec<u8>> = futures::stream::iter(queries.iter().map(|planned| {
        let url = endpoint_path(endpoint, &format!("/v1/{}/query", planned.table.as_str()));
        let body = planned.query.request_body().to_vec();
        async move { routed_request(Method::POST, &url?, body, MAX_PIR_BODY_BYTES).await }
    }))
    .buffered(QUERY_CONCURRENCY)
    .try_collect()
    .await?;

    queries
        .into_iter()
        .zip(responses)
        .map(|(planned, response)| {
            let row = table_session(sessions, planned.table)
                .decode(planned.query, &response)
                .map_err(client_protocol_error)?;
            Ok((planned.table, planned.target, row))
        })
        .collect()
}

fn table_session(sessions: &TableSessions, table: DatabaseId) -> &zakura_pir_memo::PirSession {
    match table {
        DatabaseId::Action => &sessions.action,
        DatabaseId::Witness => &sessions.witness,
        DatabaseId::WitnessRoots => &sessions.witness_roots,
        DatabaseId::NfCold => &sessions.nf_cold,
        DatabaseId::NfWarm => &sessions.nf_warm,
    }
}

/// Every record of an ACTION row, in position order. Padding records beyond
/// the populated tail decrypt under no key and are harmless.
fn action_records(row: &PirRow, first_position: u64) -> Vec<ActionRecordView> {
    (0..RECORDS_PER_ROW as u64)
        .filter_map(|offset| row.record(first_position + offset))
        .map(|record| ActionRecordView {
            nullifier: *record.nullifier(),
            ephemeral_key: *record.ephemeral_key(),
            ciphertext: *record.ciphertext(),
            cmx: *record.cmx(),
            txid: *record.txid(),
            height: BlockHeight::from(record.height()),
        })
        .collect()
}

/// Records every pending spend whose transaction starts in this row, taking
/// the txid from the record at the transaction's first output position.
fn attribute_spends(
    db: &mut WalletDatabase,
    pending: &mut Vec<(Position, SpendMeta)>,
    first_position: u64,
    records: &[ActionRecordView],
) -> Result<usize, SyncError> {
    let mut recorded = 0;
    let mut index = 0;
    while index < pending.len() {
        let (_, meta) = pending[index];
        let start = u64::from(meta.first_output_position);
        let offset = start.wrapping_sub(first_position);
        let Some(record) = (offset < RECORDS_PER_ROW as u64)
            .then(|| records.get(offset as usize))
            .flatten()
        else {
            index += 1;
            continue;
        };
        if record.height != meta.spend_height {
            return Err(SyncError::parse(
                "PIR action record height disagrees with the nullifier table",
            ));
        }
        let (position, _) = pending.swap_remove(index);
        let stored = with_wallet_db_write_lock("sync_engine.dag_sync.record_pir_spend", || {
            db.record_pir_spend(position, meta, record.txid)
        })
        .map_err(|error| SyncError::db(format!("record_pir_spend: {error}")))?;
        if stored {
            recorded += 1;
        }
    }
    Ok(recorded)
}

/// The cap's tree root must equal the local tree's root at the anchor when
/// the wallet retains that checkpoint. When it does not, the manifest's
/// block-hash and tree-size gate is all the wallet can check.
fn verify_cap_root(
    db: &mut WalletDatabase,
    cap: &WitnessCap,
    anchor_height: BlockHeight,
) -> Result<(), SyncError> {
    let expected = hex::decode(&cap.tree_root)
        .ok()
        .and_then(|bytes| <[u8; 32]>::try_from(bytes).ok())
        .ok_or_else(|| SyncError::parse("witness cap tree root is not a 32-byte hex string"))?;
    let local = db
        .with_ironwood_tree_mut::<_, _, shardtree::error::ShardTreeError<
            zcash_client_sqlite::wallet::commitment_tree::Error,
        >>(|tree| tree.root_at_checkpoint_id(&anchor_height))
        .map_err(|error| SyncError::db(format!("local Ironwood root: {error:?}")))?
        .flatten();
    match local {
        Some(root) if root.to_bytes() != expected => Err(SyncError::parse(
            "witness cap tree root disagrees with the local Ironwood tree",
        )),
        Some(_) => Ok(()),
        None => {
            log::info!("sync: DAG pass accepted the witness cap under the anchor gate (no local checkpoint at the anchor)");
            Ok(())
        }
    }
}

/// Builds the five table sessions from one manifest and fetches the cap it
/// describes.
async fn connect_all(endpoint: &str) -> Result<(TableSessions, WitnessCap), SyncError> {
    let manifest = fetch_manifest(endpoint).await?;
    let sessions = TableSessions {
        action: connect_table(endpoint, &manifest, DatabaseId::Action).await?,
        witness: connect_table(endpoint, &manifest, DatabaseId::Witness).await?,
        witness_roots: connect_table(endpoint, &manifest, DatabaseId::WitnessRoots).await?,
        nf_cold: connect_table(endpoint, &manifest, DatabaseId::NfCold).await?,
        nf_warm: connect_table(endpoint, &manifest, DatabaseId::NfWarm).await?,
    };
    let cap = routed_request(
        Method::GET,
        &endpoint_path(
            endpoint,
            &format!("/v1/witness/cap?generation={}", manifest.generation),
        )?,
        Vec::new(),
        MAX_MANIFEST_BYTES,
    )
    .await?;
    let cap: WitnessCap = serde_json::from_slice(&cap)
        .map_err(|error| SyncError::parse(format!("witness cap JSON: {error}")))?;
    if cap.anchor_height != manifest.anchor_height
        || cap.tree_size != manifest.ironwood_tree_size
        || cap.tree_root != manifest.anchor_tree_root
    {
        return Err(SyncError::parse(
            "witness cap does not describe the generation manifest's anchor",
        ));
    }
    Ok((sessions, cap))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_mainnet_runs_the_dag_pass() {
        assert!(DagSync::new(WalletNetwork::Main).endpoint.is_some());
        assert!(DagSync::new(WalletNetwork::Test).endpoint.is_none());
    }

    #[test]
    fn spends_are_attributed_only_from_the_row_holding_the_first_output() {
        let meta = SpendMeta {
            spend_height: BlockHeight::from(10),
            first_output_position: Position::from(13u64),
            action_count: 2,
        };
        // Row 0 holds positions 0..8: position 13 is not in it.
        let mut pending = vec![(Position::from(1u64), meta)];
        let records: Vec<ActionRecordView> = Vec::new();
        assert_eq!(
            pending_in_row(&mut pending, 0, &records),
            None,
            "row 0 cannot attribute a spend starting at 13"
        );
        assert_eq!(pending_in_row(&mut pending, 8, &records), Some(5));
    }

    /// Manual smoke test against the deployed service: builds all five table
    /// sessions from one manifest, fetches the cap, and issues one full pass
    /// of cover queries. It carries no wallet state, so it discloses nothing.
    #[tokio::test]
    #[ignore = "requires the deployed PIR service"]
    async fn deployed_endpoint_serves_five_tables_and_answers_a_cover_pass() {
        let _ = rustls::crypto::ring::default_provider().install_default();
        let endpoint = endpoint_for(WalletNetwork::Main).unwrap();
        let (sessions, cap) = connect_all(&endpoint).await.unwrap();
        assert_eq!(cap.tree_size, sessions.action.manifest().ironwood_tree_size);
        let envelope = sessions.action.manifest().envelope;
        let mut planner = DagSyncPlanner::new();
        let queries = planner.plan(&sessions).unwrap();
        assert_eq!(
            queries.len(),
            (envelope.k_nf * 2 + envelope.k_act + envelope.k_wit * 2) as usize
        );
        for PlannedQuery {
            table,
            target,
            query,
        } in queries
        {
            assert_eq!(target, Target::Dummy);
            let response = routed_request(
                Method::POST,
                &endpoint_path(&endpoint, &format!("/v1/{}/query", table.as_str())).unwrap(),
                query.request_body().to_vec(),
                MAX_PIR_BODY_BYTES,
            )
            .await
            .unwrap();
            let row = table_session(&sessions, table)
                .decode(query, &response)
                .unwrap();
            assert_eq!(row.table(), table);
        }
    }

    /// The row-offset arithmetic `attribute_spends` relies on, isolated from the DB.
    fn pending_in_row(
        pending: &mut [(Position, SpendMeta)],
        first_position: u64,
        _records: &[ActionRecordView],
    ) -> Option<u64> {
        let start = u64::from(pending[0].1.first_output_position);
        let offset = start.wrapping_sub(first_position);
        (offset < RECORDS_PER_ROW as u64).then_some(offset)
    }
}
