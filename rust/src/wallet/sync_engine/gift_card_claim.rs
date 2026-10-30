//! A single-funding Ironwood card: decrypt only through funding, retain that
//! witness, and observe later blocks without wallet scanning or enhancement.
use super::*;
use futures::{stream, stream::FuturesOrdered, StreamExt};
use prost::Message;
use rusqlite::{Connection, OptionalExtension};
use std::num::NonZeroU32;
use zcash_client_backend::{
    data_api::anchor_retention::AnchorRetentionInterval, proto::compact_formats::CompactBlock,
};

mod recovery;

const TAIL: u32 = 12;
const DISCOVERY_BATCH: u32 = 100;
const OBSERVATION_BATCH: u32 = 500;
const DOWNLOADS: usize = 4;
static DOWNLOAD_BUDGET: std::sync::LazyLock<Arc<tokio::sync::Semaphore>> =
    std::sync::LazyLock::new(|| Arc::new(tokio::sync::Semaphore::new(8)));

async fn download_observation(
    client: CompactTxStreamerClient<Channel>,
    start: u32,
    end: u32,
    nullifier_only: bool,
    cancel: Arc<AtomicBool>,
) -> Result<(u32, u32, Vec<CompactBlock>), String> {
    let _permit = cancellable(&cancel, async {
        DOWNLOAD_BUDGET
            .clone()
            .acquire_owned()
            .await
            .map_err(|e| e.to_string())
    })
    .await?;
    retry(&cancel, || {
        let mut client = client.clone();
        async move {
            let blocks = if nullifier_only {
                lwd::download_nullifiers(&mut client, start, end).await
            } else {
                lwd::download_card_blocks(&mut client, start, end).await
            }
            .map_err(|e| e.to_string())?;
            Ok((start, end, blocks))
        }
    })
    .await
}

#[derive(Clone, Default)]
pub(crate) struct Snapshot {
    pub funding_height: u32,
    pub anchor_height: u32,
    pub checked_height: u32,
    pub total: u64,
    pub unspent: u64,
    pub complete: bool,
}

/// Use the same anchor depth as the claim selector, including for a frozen
/// funding prefix whose later blocks are observed without wallet scanning.
pub(crate) fn max_claim_anchor_height(checked_height: u32) -> Option<u32> {
    checked_height.checked_add(1)?.checked_sub(u32::from(
        crate::wallet::payment_link_claim_confirmations_policy().trusted(),
    ))
}

impl Snapshot {
    pub(crate) fn has_confirmed_anchor(&self) -> bool {
        self.funding_height > 0
            && self.funding_height <= self.anchor_height
            && max_claim_anchor_height(self.checked_height)
                .is_some_and(|maximum| self.anchor_height <= maximum)
    }
}

enum CheckResult {
    Complete(Snapshot),
    RebuildWitnesses,
}

fn has_unexpired_claim(c: &Connection, tip: u32) -> Result<bool, String> {
    c.query_row(
        "SELECT EXISTS(
           SELECT 1 FROM v_received_output_spends spent
           JOIN ironwood_received_notes n ON spent.pool=4 AND spent.received_output_id=n.id
           JOIN transactions funding ON funding.id_tx=n.transaction_id
           JOIN vizor_giftcard_check g ON funding.txid=g.funding_txid
           JOIN transactions t ON t.id_tx=spent.transaction_id
           WHERE t.created IS NOT NULL AND t.raw IS NOT NULL
             AND (t.expiry_height IS NULL OR t.expiry_height=0 OR t.expiry_height>?1))",
        [tip],
        |r| r.get(0),
    )
    .map_err(|e| e.to_string())
}

/// Only choose from the scanned prefix whose chain identity was just checked.
/// A checkpoint row alone does not establish that its funding witnesses exist.
fn stable_anchor(
    db: &mut WalletDatabase,
    c: &Connection,
    state: &Snapshot,
    maximum: u32,
) -> Result<Option<u32>, String> {
    let anchor: Option<u32> = c
        .query_row(
            "SELECT MAX(checkpoint_id) FROM ironwood_tree_checkpoints
             WHERE checkpoint_id BETWEEN ?1 AND ?2",
            rusqlite::params![state.funding_height, maximum.min(state.anchor_height)],
            |r| r.get(0),
        )
        .map_err(|e| e.to_string())?;
    let Some(anchor) = anchor else {
        return Ok(None);
    };
    let mut query = c
        .prepare(
            "SELECT n.commitment_tree_position FROM ironwood_received_notes n
             JOIN transactions t ON t.id_tx=n.transaction_id
             JOIN vizor_giftcard_check g ON t.txid=g.funding_txid WHERE n.value>0",
        )
        .map_err(|e| e.to_string())?;
    let positions = query
        .query_map([], |r| r.get::<_, Option<u64>>(0))
        .map_err(|e| e.to_string())?
        .collect::<rusqlite::Result<Option<Vec<_>>>>()
        .map_err(|e| e.to_string())?;
    let Some(positions) = positions.filter(|p| !p.is_empty()) else {
        return Ok(None);
    };
    let height = BlockHeight::from_u32(anchor);
    let usable: Result<_, ShardTreeError<zcash_client_sqlite::wallet::commitment_tree::Error>> = db
        .with_ironwood_tree_mut(|tree| {
            if tree.root_at_checkpoint_id(&height)?.is_none() {
                return Ok(false);
            }
            for position in &positions {
                if tree
                    .witness_at_checkpoint_id((*position).into(), &height)?
                    .is_none()
                {
                    return Ok(false);
                }
            }
            Ok(true)
        });
    match usable {
        Ok(Some(true)) => Ok(Some(anchor)),
        Ok(_) | Err(ShardTreeError::Query(_)) => Ok(None),
        Err(e) => Err(format!("Read Gift Card witnesses: {e}")),
    }
}

async fn rebuild_discovery(
    db: &mut WalletDatabase,
    c: &Connection,
    client: &mut CompactTxStreamerClient<Channel>,
    birthday: BlockHeight,
) -> Result<(), String> {
    let from = get_tree_state(client, u32::from(birthday - 1) as u64)
        .await
        .map_err(|e| e.to_string())?
        .to_chain_state()
        .map_err(|e| e.to_string())?;
    // A witness rebuild does not revoke signed transactions or their input
    // reservations. Those attempts retain their original anchor and expiry.
    db.truncate_to_chain_state(from)
        .map_err(|e| e.to_string())?;
    c.execute_batch("DELETE FROM vizor_giftcard_check; DELETE FROM vizor_giftcard_blocks; DELETE FROM vizor_giftcard_spends; DELETE FROM vizor_giftcard_mined; DELETE FROM vizor_giftcard_canary;").map_err(|e|e.to_string())?;
    Ok(())
}

fn schema(c: &Connection) -> Result<(), String> {
    c.execute_batch("CREATE TABLE IF NOT EXISTS vizor_giftcard_check(
      id INTEGER PRIMARY KEY CHECK(id=1), funding_height INTEGER NOT NULL,
      funding_txid BLOB NOT NULL, anchor_height INTEGER NOT NULL,
      checked_height INTEGER NOT NULL DEFAULT 0, complete INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE IF NOT EXISTS vizor_giftcard_blocks(height INTEGER PRIMARY KEY, hash BLOB NOT NULL);
      CREATE TABLE IF NOT EXISTS vizor_giftcard_spends(nf BLOB PRIMARY KEY, txid BLOB NOT NULL, height INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS vizor_giftcard_mined(txid BLOB PRIMARY KEY, height INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS vizor_giftcard_canary(id INTEGER PRIMARY KEY CHECK(id=1), block BLOB NOT NULL);")
      .map_err(|e| e.to_string())
}

pub(crate) fn snapshot(path: &str) -> Result<Option<Snapshot>, String> {
    let c = crate::wallet::sync::open_readonly_conn(path)?;
    snapshot_from_conn(&c)
}

/// Read all observer state on the caller's existing SQLite snapshot.
pub(crate) fn snapshot_from_conn(c: &Connection) -> Result<Option<Snapshot>, String> {
    if !c
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name='vizor_giftcard_check')",
            [],
            |r| r.get::<_, bool>(0),
        )
        .map_err(|e| e.to_string())?
    {
        return Ok(None);
    }
    read_snapshot(c).map_err(|e| e.to_string())
}

fn read_snapshot(c: &Connection) -> rusqlite::Result<Option<Snapshot>> {
    c.query_row("SELECT funding_height,anchor_height,checked_height,complete,
      (SELECT COALESCE(SUM(n.value),0) FROM ironwood_received_notes n JOIN transactions t ON t.id_tx=n.transaction_id WHERE t.txid=g.funding_txid),
      (SELECT COALESCE(SUM(n.value),0) FROM ironwood_received_notes n JOIN transactions t ON t.id_tx=n.transaction_id WHERE t.txid=g.funding_txid AND NOT EXISTS(SELECT 1 FROM vizor_giftcard_spends s WHERE s.nf=n.nf))
      FROM vizor_giftcard_check g WHERE id=1", [], |r| Ok(Snapshot {
        funding_height:r.get(0)?,anchor_height:r.get(1)?,checked_height:r.get(2)?,
        complete:r.get(3)?,total:r.get(4)?,unspent:r.get(5)?,
    })).optional()
}

/// All positive outputs of the first funding transaction must have six observed
/// confirmations on their spends. An empty/damaged cache is never settlement.
fn funding_spends_settled(c: &Connection, state: &Snapshot) -> Result<bool, String> {
    if state.total == 0 || state.unspent != 0 {
        return Ok(false);
    }
    let Some(settled_height) = state.checked_height.checked_sub(5) else {
        return Ok(false);
    };
    c.query_row(
        "SELECT EXISTS(
           SELECT 1 FROM ironwood_received_notes n
           JOIN transactions t ON t.id_tx=n.transaction_id
           JOIN vizor_giftcard_check g ON t.txid=g.funding_txid WHERE n.value>0)
         AND NOT EXISTS(
           SELECT 1 FROM ironwood_received_notes n
           JOIN transactions t ON t.id_tx=n.transaction_id
           JOIN vizor_giftcard_check g ON t.txid=g.funding_txid
           LEFT JOIN vizor_giftcard_spends s ON s.nf=n.nf
           WHERE n.value>0 AND (s.height IS NULL OR s.height>?1))",
        [settled_height],
        |r| r.get(0),
    )
    .map_err(|e| e.to_string())
}

fn check_cancel(cancel: &AtomicBool) -> Result<(), String> {
    if cancel.load(Ordering::Relaxed) {
        Err("Gift Card check cancelled".into())
    } else {
        Ok(())
    }
}

/// Legacy sync may have scanned recent blocks before older history. Resume
/// from the contiguous prefix, including any earlier verification work, never
/// from the highest stored block. Discovery itself commits in height order.
fn discovery_start(db: &WalletDatabase, birthday: BlockHeight, tip: u32) -> Result<u32, String> {
    let contiguous_end = db
        .block_fully_scanned()
        .map_err(|e| e.to_string())?
        .map(|block| u32::from(block.block_height()));
    let mut start = contiguous_end.map_or(u32::from(birthday), |h| h.saturating_add(1));
    if let Some(pending_start) = db
        .suggest_scan_ranges()
        .map_err(|e| e.to_string())?
        .iter()
        .filter(|range| is_pending_scan_range(range) && range.block_range().start <= tip.into())
        .map(|range| u32::from(range.block_range().start))
        .min()
    {
        start = start.min(pending_start);
    }
    Ok(start.max(u32::from(birthday)))
}

async fn cancellable<T>(
    cancel: &AtomicBool,
    work: impl Future<Output = Result<T, String>>,
) -> Result<T, String> {
    tokio::select! {
        result = work => result,
        _ = async { while !cancel.load(Ordering::Relaxed) { tokio::time::sleep(std::time::Duration::from_millis(100)).await; } } => Err("Gift Card check cancelled".into()),
    }
}

async fn retry<T, F, Fut>(cancel: &AtomicBool, mut work: F) -> Result<T, String>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<T, String>>,
{
    let mut error = String::new();
    for attempt in 0..4 {
        check_cancel(cancel)?;
        if attempt > 0 {
            cancellable(cancel, async {
                tokio::time::sleep(std::time::Duration::from_secs(1 << attempt)).await;
                Ok(())
            })
            .await?;
        }
        match cancellable(cancel, work()).await {
            Ok(v) => return Ok(v),
            Err(e) if e.contains("range exceeds memory limit") => return Err(e),
            Err(e) => error = e,
        }
    }
    Err(error)
}

/// No main-wallet sync guard: callers serialize by retained claim DB identity.
pub(crate) async fn run(
    path: &str,
    url: &str,
    fallbacks: &[String],
    network: WalletNetwork,
    cancel: Arc<AtomicBool>,
    allow_resubmit: bool,
    progress: impl Fn(&str, u64, u64, &Snapshot),
) -> Result<Snapshot, String> {
    check_cancel(&cancel)?;
    // Covers connection/Tor startup and every RPC wait, including boundary
    // checks. Dropping the future also drops downloads and SQLite connections.
    cancellable(&cancel, async {
        // Repair a legacy/missing witness cache once within the same check.
        // A broken endpoint must not create an unbounded rediscovery loop.
        for _ in 0..2 {
            match run_inner(
                path,
                url,
                fallbacks,
                network,
                cancel.clone(),
                allow_resubmit,
                &progress,
            )
            .await?
            {
                CheckResult::Complete(state) => return Ok(state),
                CheckResult::RebuildWitnesses => {}
            }
        }
        Err("Gift Card funding witnesses could not be rebuilt".into())
    })
    .await
}

/// No main-wallet sync guard: callers serialize by retained claim DB identity.
async fn run_inner(
    path: &str,
    url: &str,
    fallbacks: &[String],
    network: WalletNetwork,
    cancel: Arc<AtomicBool>,
    allow_resubmit: bool,
    progress: impl Fn(&str, u64, u64, &Snapshot),
) -> Result<CheckResult, String> {
    let mut client = open_lwd_channel_with_cancel(url, || cancel.load(Ordering::Relaxed))
        .await
        .map_err(|e| e.to_string())?;
    let tip = get_latest_block(&mut client)
        .await
        .map_err(|e| e.to_string())?;
    let tip = u32::try_from(tip.height).map_err(|_| "Invalid Gift Card tip")?;
    let mut db = open_db(path, network).map_err(|e| e.to_string())?;
    let birthday = db
        .get_wallet_birthday()
        .map_err(|e| e.to_string())?
        .ok_or("Gift Card account missing")?;
    if !network.is_nu_active(zcash_protocol::consensus::NetworkUpgrade::Nu6_3, birthday) {
        return Err("Gift Cards require an Ironwood birthday".into());
    }
    if db.get_account_ids().map_err(|e| e.to_string())?.len() != 1 {
        return Err("Gift Card requires one account".into());
    }
    db.set_anchor_retention_interval(AnchorRetentionInterval::custom(NonZeroU32::new(1).unwrap()));
    let c = crate::wallet::db::open_wallet_raw_conn_with_timeout(
        path,
        crate::wallet::db::WALLET_DB_BUSY_TIMEOUT,
    )?;
    schema(&c)?;
    let mut state = read_snapshot(&c)
        .map_err(|e| e.to_string())?
        .unwrap_or_default();
    // Legacy wallets may have no observer row. Do not overwrite their known
    // tip or unmine a receipt merely because the selected endpoint is behind.
    let known_mined: Option<u32> = c
        .query_row("SELECT MAX(mined_height) FROM transactions", [], |r| {
            r.get(0)
        })
        .map_err(|e| e.to_string())?;
    let known_scanned = db
        .block_max_scanned()
        .map_err(|e| e.to_string())?
        .map(|b| u32::from(b.block_height()));
    let known_tip = db.chain_height().map_err(|e| e.to_string())?.map(u32::from);
    if [
        Some(state.checked_height),
        known_tip,
        known_scanned,
        known_mined,
    ]
    .into_iter()
    .flatten()
    .any(|h| h > tip)
    {
        return Err("Gift Card endpoint is behind the last known block".into());
    }
    db.update_chain_tip(BlockHeight::from_u32(tip))
        .map_err(|e| e.to_string())?;
    crate::wallet::sync::recover_orphaned_send_locks(path, network)?;

    c.execute("UPDATE vizor_giftcard_check SET complete=0", [])
        .map_err(|e| e.to_string())?;
    let mut start = u32::from(birthday);
    if state.funding_height == 0 {
        start = discovery_start(&db, birthday, tip)?;
        let anchor: Option<u32> = c
            .query_row(
                "SELECT MAX(checkpoint_id) FROM ironwood_tree_checkpoints",
                [],
                |r| r.get(0),
            )
            .map_err(|e| e.to_string())?;
        if let Some(anchor) = anchor {
            if let Some((height, txid)) = first_funding(&c)? {
                if height < start && height <= anchor {
                    c.execute("INSERT INTO vizor_giftcard_check(id,funding_height,funding_txid,anchor_height) VALUES(1,?1,?2,?3)",rusqlite::params![height,txid,anchor]).map_err(|e|e.to_string())?;
                    state = read_snapshot(&c).map_err(|e| e.to_string())?.unwrap();
                }
            }
        }
    }
    // Prefetch two ranges, but scan and commit strictly in height order. Once
    // funding is found, dropping this stream cancels outstanding prefetched work.
    if state.funding_height == 0 {
        let ranges: Vec<_> = (start..=tip)
            .step_by(DISCOVERY_BATCH as usize)
            .map(|s| (s, s.saturating_add(DISCOVERY_BATCH - 1).min(tip)))
            .collect();
        let mut batches = stream::iter(ranges)
            .map(|(start, end)| {
                let client = client.clone();
                let cancel = cancel.clone();
                async move {
                    let _permit = cancellable(&cancel, async {
                        DOWNLOAD_BUDGET
                            .clone()
                            .acquire_owned()
                            .await
                            .map_err(|e| e.to_string())
                    })
                    .await?;
                    retry(&cancel, || {
                        let mut client = client.clone();
                        async move {
                            download_scan_batch(
                                &mut client,
                                BlockHeight::from_u32(start),
                                BlockHeight::from_u32(end),
                                network,
                            )
                            .await
                            .map(|v| (start, end, v))
                            .map_err(|e| e.to_string())
                        }
                    })
                    .await
                }
            })
            .buffered(2);
        while let Some(batch) = batches.next().await {
            let (start, end, (source, from)) = batch?;
            check_cancel(&cancel)?;
            validate_scan_batch(
                &source,
                &from,
                BlockHeight::from_u32(start),
                BlockHeight::from_u32(end + 1),
            )
            .map_err(|e| e.to_string())?;
            scan_cached_blocks(
                &network,
                &source,
                &mut db,
                BlockHeight::from_u32(start),
                &from,
                (end - start + 1) as usize,
            )
            .map_err(|e| format!("Gift Card discovery: {e}"))?;
            let funding:Option<(u32,Vec<u8>)>=c.query_row("SELECT t.mined_height,t.txid FROM ironwood_received_notes n JOIN transactions t ON t.id_tx=n.transaction_id WHERE n.value>0 AND t.mined_height IS NOT NULL ORDER BY t.mined_height,t.tx_index LIMIT 1",[],|r|Ok((r.get(0)?,r.get(1)?))).optional().map_err(|e|e.to_string())?;
            progress(
                "finding",
                (end - u32::from(birthday) + 1) as u64,
                (tip - u32::from(birthday) + 1) as u64,
                &state,
            );
            // A legacy cache can already contain a later note. Do not stop
            // until discovery has covered its preceding history and funding.
            if let Some((height, txid)) = funding.filter(|(height, _)| *height <= end) {
                c.execute("INSERT OR REPLACE INTO vizor_giftcard_check(id,funding_height,funding_txid,anchor_height) VALUES(1,?1,?2,?3)",rusqlite::params![height,txid,end]).map_err(|e|e.to_string())?;
                state = read_snapshot(&c).map_err(|e| e.to_string())?.unwrap();
                progress("checking", 0, (tip - height + 1) as u64, &state);
                if let Some(block) = source.block_at(BlockHeight::from_u32(height)) {
                    save_canary(&c, block)?;
                }
                break;
            }
        }
        if state.funding_height == 0 {
            progress("complete", 1, 1, &state);
            return Ok(CheckResult::Complete(state));
        }
    }
    drop(db);

    // A nonempty canary from the actual funding block detects servers which
    // implement the RPC but silently omit Ironwood actions.
    let cached: Option<Vec<u8>> = c
        .query_row(
            "SELECT block FROM vizor_giftcard_canary WHERE id=1",
            [],
            |r| r.get(0),
        )
        .optional()
        .map_err(|e| e.to_string())?;
    let canary = if let Some(bytes) = cached {
        CompactBlock::decode(bytes.as_slice()).map_err(|e| e.to_string())?
    } else {
        let full = download_blocks(
            &mut client,
            BlockHeight::from_u32(state.funding_height),
            BlockHeight::from_u32(state.funding_height),
            network,
        )
        .await
        .map_err(|e| e.to_string())?;
        let block = full
            .block_at(BlockHeight::from_u32(state.funding_height))
            .ok_or("Gift Card canary missing")?
            .clone();
        save_canary(&c, &block)?;
        block
    };
    let mut observer = None;
    for candidate in std::iter::once(url).chain(fallbacks.iter().map(String::as_str)) {
        check_cancel(&cancel)?;
        let probe = async {
            let mut probe =
                open_lwd_channel_with_cancel(candidate, || cancel.load(Ordering::Relaxed))
                    .await
                    .map_err(|e| e.to_string())?;
            let blocks =
                lwd::download_nullifiers(&mut probe, state.funding_height, state.funding_height)
                    .await
                    .map_err(|e| e.to_string())?;
            if blocks.len() != 1 || !canary_matches(&canary, &blocks[0]) {
                return Err("Gift Card endpoint omits Ironwood nullifiers".to_string());
            }
            Ok(probe)
        };
        if let Ok(probe) = cancellable(&cancel, probe).await {
            observer = Some(probe);
            break;
        }
    }
    let nullifier_only = observer.is_some();
    let observer = observer.unwrap_or(client.clone());
    let mut anchor_client = observer.clone();
    let actual_hash = if nullifier_only {
        lwd::download_nullifiers(&mut anchor_client, state.anchor_height, state.anchor_height)
            .await
            .map_err(|e| e.to_string())?
            .first()
            .ok_or("Gift Card anchor missing")?
            .hash
            .clone()
    } else {
        get_compact_block_hash(&mut anchor_client, state.anchor_height as u64)
            .await
            .map_err(|e| e.to_string())?
            .0
            .to_vec()
    };
    let stored: Option<Vec<u8>> = c
        .query_row(
            "SELECT hash FROM blocks WHERE height=?1",
            [state.anchor_height],
            |r| r.get(0),
        )
        .optional()
        .map_err(|e| e.to_string())?;
    if stored.as_ref() != Some(&actual_hash) {
        let mut db = open_db(path, network).map_err(|e| e.to_string())?;
        rebuild_discovery(&mut db, &c, &mut client, birthday).await?;
        if stored.is_none() {
            return Ok(CheckResult::RebuildWitnesses);
        }
        return Err("Gift Card anchor changed; observation restart required".into());
    }

    // Validate the previous frozen boundary before changing it. In particular,
    // moving a legacy tip anchor must never hide a reorg of a signed attempt.
    // Keep that boundary for the lifetime of an existing signed claim; changing
    // the observer row cannot change the anchor inside its immutable raw bytes.
    // A legacy SDK mined_height may be stale after a reorg; mined evidence now
    // belongs to the observer. Retain every unexpired signed attempt's boundary.
    let unexpired_claim = has_unexpired_claim(&c, tip)?;
    if let Some(maximum) = max_claim_anchor_height(tip)
        .filter(|h| state.funding_height <= *h)
        .filter(|_| !unexpired_claim)
    {
        let mut db = open_db(path, network).map_err(|e| e.to_string())?;
        let Some(anchor) = stable_anchor(&mut db, &c, &state, maximum)? else {
            rebuild_discovery(&mut db, &c, &mut client, birthday).await?;
            return Ok(CheckResult::RebuildWitnesses);
        };
        if anchor != state.anchor_height {
            c.execute("UPDATE vizor_giftcard_check SET anchor_height=?1", [anchor])
                .map_err(|e| e.to_string())?;
            state.anchor_height = anchor;
        }
    }

    let start = state
        .funding_height
        .max(state.checked_height.saturating_sub(TAIL - 1));
    let transaction = c.unchecked_transaction().map_err(|e| e.to_string())?;
    transaction
        .execute(
            "DELETE FROM vizor_giftcard_spends WHERE height>=?1",
            [start],
        )
        .map_err(|e| e.to_string())?;
    transaction
        .execute("DELETE FROM vizor_giftcard_mined WHERE height>=?1", [start])
        .map_err(|e| e.to_string())?;
    transaction
        .execute(
            "DELETE FROM vizor_giftcard_blocks WHERE height>=?1",
            [start],
        )
        .map_err(|e| e.to_string())?;
    transaction
        .execute(
            "UPDATE vizor_giftcard_check SET checked_height=?1,complete=0",
            [start - 1],
        )
        .map_err(|e| e.to_string())?;
    transaction.commit().map_err(|e| e.to_string())?;
    let nfs = tracked_nullifiers(&c)?;
    let own = local_txids(&c)?;
    let mut batches = FuturesOrdered::new();
    let mut next = start;
    let mut width = OBSERVATION_BATCH;
    state.checked_height = start - 1;
    let mut predecessor: Option<Vec<u8>> = if start > state.funding_height {
        c.query_row(
            "SELECT hash FROM vizor_giftcard_blocks WHERE height=?1",
            [start - 1],
            |r| r.get(0),
        )
        .optional()
        .map_err(|e| e.to_string())?
    } else {
        None
    };
    loop {
        while batches.len() < DOWNLOADS && next <= tip {
            let end = next.saturating_add(width - 1).min(tip);
            batches.push_back(download_observation(
                observer.clone(),
                next,
                end,
                nullifier_only,
                cancel.clone(),
            ));
            next = end.saturating_add(1);
        }
        let Some(batch) = batches.next().await else {
            break;
        };
        let (s, e, blocks) = match batch {
            Ok(v) => v,
            Err(error) if error.contains("range exceeds memory limit") && width > 1 => {
                // Cancel prefetch, then resume from the last committed height.
                // Large valid blocks shrink ranges without gaps or false readiness.
                width = (width / 2).max(1);
                batches.clear();
                next = state.checked_height + 1;
                continue;
            }
            Err(error) => return Err(error),
        };
        check_cancel(&cancel)?;
        if let Err(error) = validate_observation(&blocks, s, e, predecessor.as_deref()) {
            c.execute(
                "UPDATE vizor_giftcard_check SET checked_height=0,complete=0",
                [],
            )
            .map_err(|e| e.to_string())?;
            c.execute_batch("DELETE FROM vizor_giftcard_spends; DELETE FROM vizor_giftcard_mined; DELETE FROM vizor_giftcard_blocks;").map_err(|e|e.to_string())?;
            return Err(error);
        }
        let tx = c.unchecked_transaction().map_err(|e| e.to_string())?;
        for block in &blocks {
            for compact_tx in &block.vtx {
                if own.contains(&compact_tx.txid) {
                    tx.execute(
                        "INSERT OR REPLACE INTO vizor_giftcard_mined VALUES(?1,?2)",
                        rusqlite::params![compact_tx.txid, block.height],
                    )
                    .map_err(|e| e.to_string())?;
                }
                for action in &compact_tx.ironwood_actions {
                    if nfs.contains(&action.nullifier) {
                        tx.execute(
                            "INSERT OR REPLACE INTO vizor_giftcard_spends VALUES(?1,?2,?3)",
                            rusqlite::params![action.nullifier, compact_tx.txid, block.height],
                        )
                        .map_err(|e| e.to_string())?;
                    }
                }
            }
            if block.height >= tip.saturating_sub(TAIL) as u64 || block.height == e as u64 {
                tx.execute(
                    "INSERT OR REPLACE INTO vizor_giftcard_blocks VALUES(?1,?2)",
                    rusqlite::params![block.height, block.hash],
                )
                .map_err(|e| e.to_string())?;
            }
        }
        tx.execute("UPDATE vizor_giftcard_check SET checked_height=?1", [e])
            .map_err(|e| e.to_string())?;
        tx.commit().map_err(|e| e.to_string())?;
        predecessor = blocks.last().map(|b| b.hash.clone());
        state = read_snapshot(&c).map_err(|e| e.to_string())?.unwrap();
        progress(
            "checking",
            (e - start + 1) as u64,
            (tip - start + 1) as u64,
            &state,
        );
        if funding_spends_settled(&c, &state)? {
            break;
        }
    }
    drop(batches);
    // Cheap endpoint/tip continuity check before readiness or destructive cleanup.
    let observed_height = state.checked_height;
    let observed: Vec<u8> = c
        .query_row(
            "SELECT hash FROM vizor_giftcard_blocks WHERE height=?1",
            [observed_height],
            |r| r.get(0),
        )
        .map_err(|e| e.to_string())?;
    let mut tip_client = observer.clone();
    let hash = if nullifier_only {
        lwd::download_nullifiers(&mut tip_client, observed_height, observed_height)
            .await
            .map_err(|e| e.to_string())?
            .first()
            .ok_or("Gift Card observed block missing")?
            .hash
            .clone()
    } else {
        get_compact_block_hash(&mut tip_client, observed_height as u64)
            .await
            .map_err(|e| e.to_string())?
            .0
            .to_vec()
    };
    // Fallback servers must agree with the configured server at the observed
    // boundary before enabling a claim or deleting recovery data.
    let configured_hash = get_compact_block_hash(&mut client, observed_height as u64)
        .await
        .map_err(|e| e.to_string())?
        .0
        .to_vec();
    if hash != observed || configured_hash != observed {
        return Err("Gift Card tip changed during inspection; retrying is required".into());
    }
    check_cancel(&cancel)?;
    // Before settlement, repair stale SDK receipts for a possible new claim.
    // Once all funding spends settle, only reflect observed mined claims;
    // this disposable cache no longer needs a wallet-wide recovery rewind.
    let Some(anchor) = recovery::reconcile_mined_claims(path, network, &c, &state)? else {
        let mut db = open_db(path, network).map_err(|e| e.to_string())?;
        rebuild_discovery(&mut db, &c, &mut client, birthday).await?;
        return Ok(CheckResult::RebuildWitnesses);
    };
    if anchor != state.anchor_height {
        // The previous boundary and the entire observed chain were validated
        // before this recovery rewind. Keep readiness false until it is saved;
        // a crash between SDK commit and this write triggers cache rediscovery.
        c.execute("UPDATE vizor_giftcard_check SET anchor_height=?1", [anchor])
            .map_err(|e| e.to_string())?;
    }
    c.execute("UPDATE vizor_giftcard_check SET complete=1", [])
        .map_err(|e| e.to_string())?;
    c.execute(
        "DELETE FROM vizor_giftcard_blocks WHERE height<?1",
        [observed_height.saturating_sub(TAIL)],
    )
    .map_err(|e| e.to_string())?;
    state = read_snapshot(&c).map_err(|e| e.to_string())?.unwrap();
    if allow_resubmit && !funding_spends_settled(&c, &state)? {
        check_cancel(&cancel)?;
        let candidates = recovery::resubmittable_claims(path, network, &c, &state)?;
        crate::wallet::sync::resubmit_transactions(url, &mut client, tip, candidates, || {
            cancel.load(Ordering::Relaxed)
        })
        .await;
    }
    check_cancel(&cancel)?;
    progress("complete", 1, 1, &state);
    Ok(CheckResult::Complete(state))
}

fn canary_matches(full: &CompactBlock, probe: &CompactBlock) -> bool {
    let values = |b: &CompactBlock| {
        b.vtx
            .iter()
            .flat_map(|t| {
                t.ironwood_actions
                    .iter()
                    .map(|a| (t.txid.clone(), a.nullifier.clone()))
            })
            .collect::<Vec<_>>()
    };
    let expected = values(full);
    !expected.is_empty()
        && full.height == probe.height
        && full.hash.len() == 32
        && full.hash == probe.hash
        && expected == values(probe)
}

fn validate_observation(
    blocks: &[CompactBlock],
    start: u32,
    end: u32,
    prior: Option<&[u8]>,
) -> Result<(), String> {
    if blocks.len() != (end - start + 1) as usize {
        return Err("Gift Card nullifier range incomplete".into());
    }
    let mut previous = prior;
    for (offset, b) in blocks.iter().enumerate() {
        if b.height != start as u64 + offset as u64
            || b.hash.len() != 32
            || b.prev_hash.len() != 32
            || previous.is_some_and(|p| p != b.prev_hash)
        {
            return Err("Gift Card nullifier range is not contiguous".into());
        }
        if b.vtx.iter().any(|t| {
            t.txid.len() != 32 || t.ironwood_actions.iter().any(|a| a.nullifier.len() != 32)
        }) {
            return Err("Gift Card nullifier data malformed".into());
        }
        previous = Some(&b.hash);
    }
    Ok(())
}

fn tracked_nullifiers(c: &Connection) -> Result<HashSet<Vec<u8>>, String> {
    let mut q=c.prepare("SELECT n.nf FROM ironwood_received_notes n JOIN transactions t ON t.id_tx=n.transaction_id JOIN vizor_giftcard_check g ON t.txid=g.funding_txid WHERE n.value>0").map_err(|e|e.to_string())?;
    let rows = q.query_map([], |r| r.get(0)).map_err(|e| e.to_string())?;
    rows.collect::<rusqlite::Result<_>>()
        .map_err(|e| e.to_string())
}
fn local_txids(c: &Connection) -> Result<HashSet<Vec<u8>>, String> {
    let mut q = c
        .prepare("SELECT txid FROM transactions WHERE created IS NOT NULL AND raw IS NOT NULL")
        .map_err(|e| e.to_string())?;
    let rows = q.query_map([], |r| r.get(0)).map_err(|e| e.to_string())?;
    rows.collect::<rusqlite::Result<_>>()
        .map_err(|e| e.to_string())
}
pub(crate) fn confirmations(path: &str, txids: &str) -> Result<Option<i32>, String> {
    let c = crate::wallet::sync::open_readonly_conn(path)?;
    let c = c.unchecked_transaction().map_err(|e| e.to_string())?;
    let Some(state) = snapshot_from_conn(&c)? else {
        return Ok(None);
    };
    if !state.complete {
        return Ok(Some(-1));
    }
    let mut count = u32::MAX;
    for id in txids.split(',').filter(|id| !id.is_empty()) {
        let bytes = hex::decode(id.trim()).map_err(|e| e.to_string())?;
        if bytes.len() != 32 {
            return Err("Invalid Gift Card claim txid".into());
        }
        let reversed: Vec<u8> = bytes.iter().rev().copied().collect();
        let height: Option<u32> = c
            .query_row(
                "SELECT height FROM vizor_giftcard_mined WHERE txid=?1 OR txid=?2 ORDER BY height LIMIT 1",
                rusqlite::params![bytes,reversed],
                |r| r.get(0),
            )
            .optional()
            .map_err(|e| e.to_string())?;
        count = count.min(height.map_or(0, |h| {
            if h <= state.checked_height {
                state.checked_height - h + 1
            } else {
                0
            }
        }));
    }
    Ok(Some(if count == u32::MAX {
        0
    } else {
        count.min(6) as i32
    }))
}

/// Positive spend evidence remains available without a wallet-wide scan queue.
pub(crate) fn spend_evidence(
    path: &str,
    claim_txids: &str,
) -> Result<Option<crate::wallet::sync::payment_link::SpendEvidence>, String> {
    let c = crate::wallet::sync::open_readonly_conn(path)?;
    let c = c.unchecked_transaction().map_err(|e| e.to_string())?;
    let Some(state) = snapshot_from_conn(&c)? else {
        return Ok(None);
    };
    let own = local_txids(&c)?;
    let mut requested = own.clone();
    for id in claim_txids.split(',').filter(|id| !id.is_empty()) {
        let bytes = hex::decode(id.trim()).map_err(|e| e.to_string())?;
        requested.insert(bytes.iter().rev().copied().collect());
        requested.insert(bytes);
    }
    let mut q=c.prepare("SELECT s.txid,s.height FROM ironwood_received_notes n JOIN transactions t ON t.id_tx=n.transaction_id JOIN vizor_giftcard_check g ON t.txid=g.funding_txid LEFT JOIN vizor_giftcard_spends s ON s.nf=n.nf WHERE n.value>0").map_err(|e|e.to_string())?;
    let rows = q
        .query_map([], |r| {
            Ok((r.get::<_, Option<Vec<u8>>>(0)?, r.get::<_, Option<u32>>(1)?))
        })
        .map_err(|e| e.to_string())?;
    let mut has_notes = false;
    let mut all_spent = state.complete;

    for row in rows {
        has_notes = true;
        let (id, h) = row.map_err(|e| e.to_string())?;
        let settled = h.is_some_and(|h| state.checked_height.saturating_sub(h) >= 5);
        let external = id.is_some_and(|id| !requested.contains(&id));
        all_spent &= settled && external;
    }
    let mut local_claim_txids: Vec<_> = own.into_iter().map(hex::encode).collect();
    local_claim_txids.sort();
    let mut conflicted_txids = vec![];
    if state.complete {
        let mut query=c.prepare("SELECT DISTINCT t.txid FROM vizor_giftcard_spends s JOIN ironwood_received_notes n ON n.nf=s.nf JOIN v_received_output_spends spent ON spent.pool=4 AND spent.received_output_id=n.id JOIN transactions t ON t.id_tx=spent.transaction_id WHERE t.created IS NOT NULL AND t.txid!=s.txid AND s.height<=?1").map_err(|e|e.to_string())?;
        for id in query
            .query_map([state.checked_height.saturating_sub(5)], |r| {
                r.get::<_, Vec<u8>>(0)
            })
            .map_err(|e| e.to_string())?
        {
            conflicted_txids.push(hex::encode(id.map_err(|e| e.to_string())?));
        }
        conflicted_txids.sort();
    }
    Ok(Some(crate::wallet::sync::payment_link::SpendEvidence {
        all_funds_spent_elsewhere: has_notes && all_spent,
        conflicted_txids,
        local_claim_txids,
        verified_height: state.checked_height as u64,
    }))
}

fn first_funding(c: &Connection) -> Result<Option<(u32, Vec<u8>)>, String> {
    c.query_row("SELECT t.mined_height,t.txid FROM ironwood_received_notes n JOIN transactions t ON t.id_tx=n.transaction_id WHERE n.value>0 AND t.mined_height IS NOT NULL ORDER BY t.mined_height,t.tx_index LIMIT 1",[],|r|Ok((r.get(0)?,r.get(1)?))).optional().map_err(|e|e.to_string())
}
fn save_canary(c: &Connection, block: &CompactBlock) -> Result<(), String> {
    let mut block = block.clone();
    for tx in &mut block.vtx {
        tx.outputs.clear();
        tx.spends.clear();
        tx.actions.clear();
        for a in &mut tx.ironwood_actions {
            a.cmx.clear();
            a.ephemeral_key.clear();
            a.ciphertext.clear();
        }
    }
    c.execute(
        "INSERT OR REPLACE INTO vizor_giftcard_canary VALUES(1,?1)",
        [block.encode_to_vec()],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use zcash_client_backend::proto::compact_formats::{CompactOrchardAction, CompactTx};

    #[test]
    fn claim_anchor_depth_matches_the_confirmation_policy() {
        assert_eq!(max_claim_anchor_height(0), None);
        assert_eq!(max_claim_anchor_height(101), Some(100));
        assert_eq!(max_claim_anchor_height(u32::MAX), None);
        let mut state = Snapshot {
            funding_height: 100,
            anchor_height: 100,
            checked_height: 100,
            ..Default::default()
        };
        assert!(!state.has_confirmed_anchor());
        state.checked_height = 101;
        assert!(state.has_confirmed_anchor());
        state.anchor_height = 101;
        assert!(!state.has_confirmed_anchor());
        state.anchor_height = 99;
        assert!(!state.has_confirmed_anchor());
        state.funding_height = 0;
        assert!(!state.has_confirmed_anchor());
    }

    fn block(height: u64, hash: u8, previous: u8) -> CompactBlock {
        CompactBlock {
            height,
            hash: vec![hash; 32],
            prev_hash: vec![previous; 32],
            ..Default::default()
        }
    }
    #[test]
    fn rejects_missing_reordered_malformed_and_disconnected_observations() {
        let blocks = vec![block(10, 2, 1), block(11, 3, 2)];
        assert!(validate_observation(&blocks, 10, 11, Some(&[1; 32])).is_ok());
        assert!(validate_observation(&blocks[..1], 10, 11, None).is_err());
        let mut wrong = blocks.clone();
        wrong.reverse();
        assert!(validate_observation(&wrong, 10, 11, None).is_err());
        assert!(validate_observation(&blocks, 10, 11, Some(&[9; 32])).is_err());
        let mut wrong = blocks;
        wrong[1].vtx.push(CompactTx {
            txid: vec![4u8; 32],
            ironwood_actions: vec![CompactOrchardAction {
                nullifier: vec![0; 31],
                ..Default::default()
            }],
            ..Default::default()
        });
        assert!(validate_observation(&wrong, 10, 11, None).is_err());
    }
    #[test]
    fn capability_canary_requires_actual_ironwood_actions_and_chain_identity() {
        let mut full = block(10, 2, 1);
        full.vtx = vec![CompactTx {
            txid: vec![7u8; 32],
            ironwood_actions: vec![CompactOrchardAction {
                nullifier: vec![8u8; 32],
                ..Default::default()
            }],
            ..Default::default()
        }];
        assert!(canary_matches(&full, &full));
        let mut incomplete = full.clone();
        incomplete.vtx[0].ironwood_actions.clear();
        assert!(!canary_matches(&full, &incomplete));
        incomplete = full.clone();
        incomplete.hash = vec![9u8; 32];
        assert!(!canary_matches(&full, &incomplete));
        assert!(!canary_matches(&block(10, 2, 1), &block(10, 2, 1)));
    }
    fn fixture() -> (tempfile::TempDir, String, Connection) {
        let directory = tempfile::tempdir().unwrap();
        let path = directory
            .path()
            .join("card.db")
            .to_str()
            .unwrap()
            .to_string();
        let c = Connection::open(&path).unwrap();
        schema(&c).unwrap();
        c.execute_batch("CREATE TABLE transactions(id_tx INTEGER PRIMARY KEY,txid BLOB,created TEXT,raw BLOB);
          CREATE TABLE ironwood_received_notes(id INTEGER PRIMARY KEY,transaction_id INTEGER,value INTEGER,nf BLOB);
          CREATE TABLE v_received_output_spends(pool INTEGER,received_output_id INTEGER,transaction_id INTEGER);").unwrap();
        c.execute(
            "INSERT INTO transactions VALUES(1,?1,NULL,NULL)",
            [vec![1u8; 32]],
        )
        .unwrap();
        c.execute(
            "INSERT INTO ironwood_received_notes VALUES(1,1,10,?1)",
            [vec![2u8; 32]],
        )
        .unwrap();
        c.execute(
            "INSERT INTO ironwood_received_notes VALUES(2,1,20,?1)",
            [vec![3u8; 32]],
        )
        .unwrap();
        c.execute(
            "INSERT INTO vizor_giftcard_check VALUES(1,100,?1,101,110,1)",
            [vec![1u8; 32]],
        )
        .unwrap();
        (directory, path, c)
    }

    #[test]
    fn signed_claim_boundary_does_not_trust_cached_mined_status_before_expiry() {
        let (_dir, _path, c) = fixture();
        c.execute_batch(
            "ALTER TABLE transactions ADD COLUMN mined_height INTEGER;
             ALTER TABLE transactions ADD COLUMN expiry_height INTEGER;
             INSERT INTO transactions VALUES(2,X'04','created',X'01',105,120);
             INSERT INTO v_received_output_spends VALUES(4,1,2);",
        )
        .unwrap();
        // Legacy wallet sync may have cached a receipt later removed by a
        // reorg. Only the observer can establish its current mined status.
        assert!(has_unexpired_claim(&c, 110).unwrap());
        c.execute(
            "UPDATE transactions SET mined_height=NULL WHERE id_tx=2",
            [],
        )
        .unwrap();
        assert!(has_unexpired_claim(&c, 119).unwrap());
        assert!(!has_unexpired_claim(&c, 120).unwrap());
    }
    #[test]
    fn includes_all_funding_notes_and_requires_positive_six_block_spend_evidence() {
        let (_dir, path, c) = fixture();
        assert_eq!(snapshot(&path).unwrap().unwrap().unspent, 30);
        assert!(
            !spend_evidence(&path, "")
                .unwrap()
                .unwrap()
                .all_funds_spent_elsewhere
        );
        c.execute(
            "INSERT INTO vizor_giftcard_spends VALUES(?1,?2,105)",
            rusqlite::params![vec![2u8; 32], vec![4u8; 32]],
        )
        .unwrap();
        assert_eq!(snapshot(&path).unwrap().unwrap().unspent, 20);
        assert!(
            !spend_evidence(&path, "")
                .unwrap()
                .unwrap()
                .all_funds_spent_elsewhere
        );
        c.execute(
            "INSERT INTO vizor_giftcard_spends VALUES(?1,?2,106)",
            rusqlite::params![vec![3u8; 32], vec![4u8; 32]],
        )
        .unwrap();
        assert!(
            !spend_evidence(&path, "")
                .unwrap()
                .unwrap()
                .all_funds_spent_elsewhere
        );
        c.execute("UPDATE vizor_giftcard_check SET checked_height=111", [])
            .unwrap();
        assert!(
            spend_evidence(&path, "")
                .unwrap()
                .unwrap()
                .all_funds_spent_elsewhere
        );
        // An interrupted check cannot classify the card as consumed.
        c.execute("UPDATE vizor_giftcard_check SET complete=0", [])
            .unwrap();
        assert!(
            !spend_evidence(&path, "")
                .unwrap()
                .unwrap()
                .all_funds_spent_elsewhere
        );
    }
    #[test]
    fn conflicts_settle_only_local_transactions_using_the_competing_input() {
        let (_dir, path, c) = fixture();
        c.execute(
            "INSERT INTO transactions VALUES(2,?1,'created',X'01')",
            [vec![5u8; 32]],
        )
        .unwrap();
        c.execute(
            "INSERT INTO transactions VALUES(3,?1,'created',X'02')",
            [vec![6u8; 32]],
        )
        .unwrap();
        c.execute_batch("INSERT INTO v_received_output_spends VALUES(4,1,2),(4,2,3)")
            .unwrap();
        c.execute(
            "INSERT INTO vizor_giftcard_spends VALUES(?1,?2,105)",
            rusqlite::params![vec![2u8; 32], vec![4u8; 32]],
        )
        .unwrap();
        assert_eq!(
            spend_evidence(&path, "").unwrap().unwrap().conflicted_txids,
            vec![hex::encode([5u8; 32])]
        );
        c.execute("UPDATE vizor_giftcard_check SET complete=0", [])
            .unwrap();
        assert!(spend_evidence(&path, "")
            .unwrap()
            .unwrap()
            .conflicted_txids
            .is_empty());
    }

    #[test]
    fn settlement_requires_every_positive_funding_note_and_six_confirmations() {
        let (_dir, _path, c) = fixture();
        let settled = || funding_spends_settled(&c, &read_snapshot(&c).unwrap().unwrap()).unwrap();
        assert!(!settled());
        c.execute(
            "INSERT INTO vizor_giftcard_spends VALUES(?1,?2,105)",
            rusqlite::params![vec![2u8; 32], vec![5u8; 32]],
        )
        .unwrap();
        assert!(!settled(), "One remaining funding note prevents settlement");
        c.execute(
            "INSERT INTO vizor_giftcard_spends VALUES(?1,?2,106)",
            rusqlite::params![vec![3u8; 32], vec![6u8; 32]],
        )
        .unwrap();
        assert!(!settled(), "The second spend has only five confirmations");
        c.execute("UPDATE vizor_giftcard_check SET checked_height=111", [])
            .unwrap();
        assert!(settled());
        c.execute(
            "INSERT INTO vizor_giftcard_spends VALUES(?1,?2,999)",
            rusqlite::params![vec![8u8; 32], vec![9u8; 32]],
        )
        .unwrap();
        assert!(
            settled(),
            "Unrelated observer rows cannot change funding settlement"
        );
        c.execute(
            "UPDATE vizor_giftcard_spends SET height=112 WHERE nf=?1",
            [vec![3u8; 32]],
        )
        .unwrap();
        assert!(
            !settled(),
            "A spend beyond the observed height is not confirmed"
        );
        c.execute("DELETE FROM ironwood_received_notes", [])
            .unwrap();
        assert!(!settled(), "Missing funding notes are not settlement");
    }

    #[test]
    fn cleanup_requires_every_claim_leg_and_preserves_incomplete_observations() {
        let (_dir, path, c) = fixture();
        let a = hex::encode([5; 32]);
        let b = hex::encode([6; 32]);
        c.execute(
            "INSERT INTO vizor_giftcard_mined VALUES(?1,105)",
            [vec![5u8; 32]],
        )
        .unwrap();
        assert_eq!(confirmations(&path, &a).unwrap(), Some(6));
        assert_eq!(confirmations(&path, &format!("{a},{b}")).unwrap(), Some(0));
        c.execute(
            "INSERT INTO vizor_giftcard_mined VALUES(?1,108)",
            [vec![6u8; 32]],
        )
        .unwrap();
        assert_eq!(confirmations(&path, &format!("{a},{b}")).unwrap(), Some(3));
        c.execute("UPDATE vizor_giftcard_check SET complete=0", [])
            .unwrap();
        assert_eq!(confirmations(&path, &a).unwrap(), Some(-1));
    }
    #[tokio::test]
    async fn cancellation_interrupts_a_stalled_native_connection() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("never-opened.db");
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let server = tokio::spawn(async move {
            let (_socket, _) = listener.accept().await.unwrap();
            futures::future::pending::<()>().await;
        });
        let cancel = Arc::new(AtomicBool::new(false));
        let flag = cancel.clone();
        let signal = tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
            flag.store(true, Ordering::Relaxed);
        });
        let result = tokio::time::timeout(
            std::time::Duration::from_secs(1),
            run(
                path.to_str().unwrap(),
                &url,
                &[],
                WalletNetwork::Main,
                cancel,
                false,
                |_, _, _, _| {},
            ),
        )
        .await
        .unwrap();
        server.abort();
        signal.await.unwrap();
        assert!(result.err().unwrap().contains("cancelled"));
        assert!(!path.exists());
    }

    #[tokio::test]
    async fn cancelled_card_never_opens_a_connection_or_database() {
        let error = run(
            "missing.db",
            "invalid-url",
            &[],
            WalletNetwork::Main,
            Arc::new(AtomicBool::new(true)),
            false,
            |_, _, _, _| panic!("Cancelled progress"),
        )
        .await
        .err()
        .unwrap();
        assert!(error.contains("cancelled"));
    }

    #[tokio::test]
    async fn cancellation_interrupts_retry_backoff() {
        let cancel = Arc::new(AtomicBool::new(false));
        let flag = cancel.clone();
        let result = retry(&cancel, || {
            flag.store(true, Ordering::Relaxed);
            async { Err::<(), String>("transient failure".into()) }
        })
        .await;
        assert!(result.unwrap_err().contains("cancelled"));
    }
}
