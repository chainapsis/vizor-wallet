//! Reusable local Activity snapshots. Connections stay open, read transactions do
//! not. data_version on the same connection detects outside commits. A page
//! may continue across unrelated writes after comparing account summaries and
//! re-reading its details; the next explicit index refresh advances its token.
use std::{
    collections::{BTreeSet, VecDeque},
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, Mutex, MutexGuard, OnceLock, TryLockError,
    },
};

use super::*;

const DETAIL_BATCH: usize = 20;
const MAX_ACCOUNTS: usize = 4;

pub(crate) struct HistoryIndex {
    pub snapshot_id: String,
    pub summaries: Vec<HistorySummary>,
}

pub(crate) struct HistorySummary {
    pub txid_hex: String,
    pub mined_height: u64,
    pub expired_unmined: bool,
    pub block_time: u64,
    pub created_time: u64,
    pub source_order: u32,
}

pub(crate) struct HistoryRows {
    pub stale: bool,
    pub transactions: Vec<TransactionInfo>,
}

#[derive(Clone, PartialEq, Eq)]
struct Key {
    path: String,
    network: WalletNetwork,
    account: AccountUuid,
}

struct Entry {
    conn: rusqlite::Connection,
    file: same_file::Handle,
    snapshot: Option<Snapshot>,
}

struct Snapshot {
    id: String,
    version: i64,
    refresh_on_next_index: bool,
    bases: Vec<TxBase>,
    order: Vec<usize>,
    by_txid: HashMap<Vec<u8>, usize>,
    peers: HashMap<(String, i64), Vec<usize>>,
    details: HashMap<Vec<u8>, HistoryCompleteness>,
    outputs: HashMap<Vec<u8>, Vec<TxOutput>>,
}

struct HistorySlot {
    retired: AtomicBool,
    entry: Mutex<Option<Entry>>,
}
type Slot = Arc<HistorySlot>;

fn next_snapshot_id() -> String {
    static NEXT_ID: AtomicU64 = AtomicU64::new(1);
    NEXT_ID.fetch_add(1, Ordering::Relaxed).to_string()
}

#[derive(Default)]
struct Registry {
    active: VecDeque<(Key, Slot)>,
    // Unlike the LRU, this owns every retired connection until it is closed.
    retired: Vec<(Key, Slot)>,
    draining: HashMap<String, usize>,
}

impl Registry {
    fn retire(&mut self, entry: (Key, Slot)) {
        entry.1.retired.store(true, Ordering::Release);
        self.retired.push(entry);
    }
}

#[derive(Default)]
struct HistoryCache {
    registry: Mutex<Registry>,
}

struct ReadLease<'a> {
    cache: &'a HistoryCache,
    slot: Slot,
}

impl Drop for ReadLease<'_> {
    fn drop(&mut self) {
        // with_snapshot releases its entry guard before this lease. Retired
        // reads close on their native worker, including error/unwind paths.
        if self.slot.retired.load(Ordering::Acquire) {
            drop(self.cache.close_retired(&self.slot, true));
        }
    }
}

struct DbDrain<'a> {
    cache: &'a HistoryCache,
    path: &'a str,
}

impl Drop for DbDrain<'_> {
    fn drop(&mut self) {
        let mut registry = self.cache.lock();
        let count = registry.draining.get_mut(self.path).unwrap();
        *count -= 1;
        if *count == 0 {
            registry.draining.remove(self.path);
        }
    }
}

impl HistoryCache {
    fn lock(&self) -> MutexGuard<'_, Registry> {
        self.registry.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn slot(&self, key: Key) -> Result<ReadLease<'_>, String> {
        let (lease, evicted) = {
            let mut registry = self.lock();
            if registry.draining.contains_key(&key.path) {
                return Err("Activity database is being closed".into());
            }
            let entry = registry
                .active
                .iter()
                .position(|(k, _)| k == &key)
                .and_then(|i| registry.active.remove(i))
                .unwrap_or_else(|| {
                    (
                        key,
                        Arc::new(HistorySlot {
                            retired: AtomicBool::new(false),
                            entry: Mutex::new(None),
                        }),
                    )
                });
            let slot = entry.1.clone();
            registry.active.push_back(entry);
            let evicted = if registry.active.len() > MAX_ACCOUNTS {
                let entry = registry.active.pop_front().unwrap();
                let slot = entry.1.clone();
                registry.retire(entry);
                Some(slot)
            } else {
                None
            };
            (ReadLease { cache: self, slot }, evicted)
        };
        if let Some(slot) = evicted {
            // LRU eviction must not wait for a different account's read.
            drop(self.close_retired(&slot, false));
        }
        Ok(lease)
    }

    fn close_retired(&self, slot: &Slot, blocking: bool) -> Option<Snapshot> {
        let mut entry = if blocking {
            slot.entry.lock().unwrap_or_else(|e| e.into_inner())
        } else {
            match slot.entry.try_lock() {
                Ok(entry) => entry,
                Err(TryLockError::Poisoned(error)) => error.into_inner(),
                Err(TryLockError::WouldBlock) => return None,
            }
        };
        let snapshot = entry.take().and_then(
            |Entry {
                 conn,
                 file,
                 snapshot,
             }| {
                // Keep the entry lock until both file handles are closed. Another
                // drain must never observe None while a taken connection is open.
                drop(conn);
                drop(file);
                snapshot
            },
        );
        drop(entry);
        self.lock()
            .retired
            .retain(|(_, candidate)| !Arc::ptr_eq(candidate, slot));
        snapshot
    }

    fn clear(&self) {
        let retired = {
            let mut registry = self.lock();
            while let Some(entry) = registry.active.pop_front() {
                registry.retire(entry);
            }
            registry
                .retired
                .iter()
                .map(|(_, slot)| slot.clone())
                .collect::<Vec<_>>()
        };
        // Synchronous FFI closes idle handles now but never waits for a read.
        // Busy slots remain registered and their ReadLease closes them later.
        let snapshots: Vec<_> = retired
            .iter()
            .filter_map(|slot| self.close_retired(slot, false))
            .collect();
        if !snapshots.is_empty() {
            let _ = std::thread::Builder::new()
                .name("activity-cache-release".into())
                .spawn(move || drop(snapshots));
        }
    }

    fn evict_db(&self, path: &str) {
        let (_drain, retired) = {
            let mut registry = self.lock();
            *registry.draining.entry(path.into()).or_default() += 1;
            let mut kept = VecDeque::new();
            while let Some(entry) = registry.active.pop_front() {
                if entry.0.path == path {
                    registry.retire(entry);
                } else {
                    kept.push_back(entry);
                }
            }
            registry.active = kept;
            let retired = registry
                .retired
                .iter()
                .filter(|(key, _)| key.path == path)
                .map(|(_, slot)| slot.clone())
                .collect::<Vec<_>>();
            (DbDrain { cache: self, path }, retired)
        };
        // No registry lock while waiting. Concurrent drains can still find
        // each slot until its handles close; new reads of this DB are refused.
        for slot in retired {
            drop(self.close_retired(&slot, true));
        }
    }
}

fn cache() -> &'static HistoryCache {
    static CACHE: OnceLock<HistoryCache> = OnceLock::new();
    CACHE.get_or_init(HistoryCache::default)
}

pub(crate) fn clear() {
    cache().clear();
}

pub(crate) fn evict_db(path: &str) {
    cache().evict_db(path);
}

#[cfg(test)]
#[path = "history_pages/tests.rs"]
mod tests;

fn with_snapshot<T>(
    path: &str,
    network: WalletNetwork,
    account: AccountUuid,
    expected: Option<&str>,
    rebase_unchanged_summary: bool,
    read: impl FnOnce(&rusqlite::Connection, &mut Snapshot) -> Result<T, String>,
) -> Result<Option<T>, String> {
    let lease = cache().slot(Key {
        path: path.into(),
        network,
        account,
    })?;
    let mut entry = lease.slot.entry.lock().unwrap_or_else(|e| e.into_inner());
    if lease.slot.retired.load(Ordering::Acquire) {
        return Err("Activity snapshot is no longer available".into());
    }
    let file = same_file::Handle::from_path(path).map_err(|e| e.to_string())?;
    if entry.as_ref().is_none_or(|e| e.file != file) {
        *entry = Some(Entry {
            conn: open_readonly_conn(path)?,
            file,
            snapshot: None,
        });
    }
    let Entry { conn, snapshot, .. } = entry.as_mut().unwrap();
    let tx = conn.unchecked_transaction().map_err(|e| e.to_string())?;
    // Establish the SQLite snapshot before observing its connection-local
    // data_version. A concurrent writer cannot change either within this read.
    let present: bool = tx
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM accounts WHERE uuid = ?1)",
            [account.expose_uuid().as_bytes().as_slice()],
            |r| r.get(0),
        )
        .map_err(|e| e.to_string())?;
    if !present {
        return Err("Activity account no longer exists".into());
    }
    let version: i64 = tx
        .pragma_query_value(None, "data_version", |r| r.get(0))
        .map_err(|e| e.to_string())?;
    if let Some(expected) = expected {
        let Some(saved) = snapshot.as_mut().filter(|s| s.id == expected) else {
            return Ok(None);
        };
        if !rebase_unchanged_summary && saved.refresh_on_next_index {
            return Ok(None);
        }
        if saved.version != version {
            if !rebase_unchanged_summary {
                return Ok(None);
            }
            let bases = read_history_bases_with_claim_state(&tx, path, network, account)?;
            if bases != saved.bases {
                return Ok(None);
            }
            // Scanning often commits blocks unrelated to this account between
            // the index and row calls. The same ordering remains valid, but
            // detail facts must come from this transaction, never the old cache.
            saved.bases = bases;
            saved.version = version;
            saved.details.clear();
            saved.outputs.clear();
            // A screen refresh must still replace its older displayed facts,
            // even when a page continued under unchanged ordering metadata.
            saved.refresh_on_next_index = true;
        }
    } else if let Some(saved) = snapshot
        .as_mut()
        .filter(|s| s.version == version && s.refresh_on_next_index)
    {
        // The page already revalidated this version. Advance the UI identity
        // without repeating its summary/detail SQL on an unchanged database.
        saved.id = next_snapshot_id();
        saved.refresh_on_next_index = false;
    } else if snapshot.as_ref().is_none_or(|s| s.version != version) {
        let bases = read_history_bases_with_claim_state(&tx, path, network, account)?;
        let mut order: Vec<_> = (0..bases.len()).collect();
        order.sort_by_cached_key(|&i| std::cmp::Reverse(bases[i].history_sort_key()));
        let by_txid = bases
            .iter()
            .enumerate()
            .map(|(i, b)| (b.txid.clone(), i))
            .collect();
        let mut peers: HashMap<(String, i64), Vec<usize>> = HashMap::new();
        for (i, base) in bases.iter().enumerate() {
            if let Some(created) = &base.created {
                peers
                    .entry((created.clone(), base.expiry_key()))
                    .or_default()
                    .push(i);
            }
        }
        *snapshot = Some(Snapshot {
            id: next_snapshot_id(),
            version,
            refresh_on_next_index: false,
            bases,
            order,
            by_txid,
            peers,
            details: HashMap::new(),
            outputs: HashMap::new(),
        });
    }
    read(&tx, snapshot.as_mut().unwrap()).map(Some)
}

fn load_details(
    conn: &rusqlite::Connection,
    snapshot: &mut Snapshot,
    path: &str,
    network: WalletNetwork,
    account: AccountUuid,
    bases: &mut [TxBase],
) -> Result<(), String> {
    let mut missing: Vec<_> = bases
        .iter()
        .filter(|b| !snapshot.details.contains_key(&b.txid))
        .cloned()
        .collect();
    for batch in missing.chunks_mut(DETAIL_BATCH) {
        attach_history_details(conn, path, network, account, batch)?;
        let outputs = read_history_outputs(
            conn,
            account.expose_uuid().as_bytes(),
            batch.iter().map(|b| b.txid.as_slice()),
        )?;
        snapshot.outputs.extend(outputs);
        for base in batch.iter() {
            snapshot
                .details
                .insert(base.txid.clone(), base.history.clone());
        }
    }
    for base in bases {
        base.attach_history(snapshot.details[&base.txid].clone());
    }
    Ok(())
}

pub(crate) fn index(
    path: &str,
    network: WalletNetwork,
    account: AccountUuid,
) -> Result<HistoryIndex, String> {
    Ok(
        with_snapshot(path, network, account, None, false, |_, snapshot| {
            Ok(HistoryIndex {
                snapshot_id: snapshot.id.clone(),
                summaries: snapshot
                    .order
                    .iter()
                    .enumerate()
                    .map(|(source_order, &i)| {
                        let base = &snapshot.bases[i];
                        HistorySummary {
                            txid_hex: hex::encode(&base.txid),
                            mined_height: base.mined_height.unwrap_or(0).into(),
                            expired_unmined: base.expired_unmined,
                            block_time: base.block_time,
                            created_time: base.created_time,
                            source_order: source_order as u32,
                        }
                    })
                    .collect(),
            })
        })?
        .unwrap(),
    )
}

pub(crate) fn rows(
    path: &str,
    network: WalletNetwork,
    account: AccountUuid,
    snapshot_id: &str,
    txids: &[String],
) -> Result<HistoryRows, String> {
    if txids.len() > DETAIL_BATCH {
        return Err("Activity batch exceeds 20 transactions".into());
    }
    let requested = txids
        .iter()
        .map(|s| {
            let bytes = hex::decode(s).map_err(|e| e.to_string())?;
            if bytes.len() != 32 {
                return Err("Invalid Activity txid".to_owned());
            }
            Ok(bytes)
        })
        .collect::<Result<HashSet<_>, String>>()?;
    let transactions = with_snapshot(
        path,
        network,
        account,
        Some(snapshot_id),
        !requested.is_empty(),
        |conn, snapshot| requested_rows(conn, snapshot, path, network, account, &requested),
    )?;
    Ok(HistoryRows {
        stale: transactions.is_none(),
        transactions: transactions.unwrap_or_default(),
    })
}

/// Targeted lookups share the account cache without an Activity page token.
/// Each call observes the current DB version, and unchanged batches reuse both
/// summaries and details. A proposal stays within its caller's single read.
pub(crate) fn targeted(
    path: &str,
    network: WalletNetwork,
    account: AccountUuid,
    requested: &HashSet<Vec<u8>>,
) -> Result<Vec<TransactionInfo>, String> {
    if requested.is_empty() {
        return Ok(Vec::new());
    }
    Ok(
        with_snapshot(path, network, account, None, false, |conn, snapshot| {
            requested_rows(conn, snapshot, path, network, account, requested)
        })?
        .unwrap(),
    )
}

fn requested_rows(
    conn: &rusqlite::Connection,
    snapshot: &mut Snapshot,
    path: &str,
    network: WalletNetwork,
    account: AccountUuid,
    requested: &HashSet<Vec<u8>>,
) -> Result<Vec<TransactionInfo>, String> {
    let mut selected = BTreeSet::new();
    for txid in requested {
        if let Some(&i) = snapshot.by_txid.get(txid) {
            // A previous requested peer already included this entire group.
            if !selected.insert(i) {
                continue;
            }
            let base = &snapshot.bases[i];
            if let Some(created) = &base.created {
                if let Some(peers) = snapshot.peers.get(&(created.clone(), base.expiry_key())) {
                    selected.extend(peers);
                }
            }
        }
    }
    let mut bases: Vec<_> = selected
        .into_iter()
        .map(|i| snapshot.bases[i].clone())
        .collect();
    load_details(conn, snapshot, path, network, account, &mut bases)?;
    let mut rows = assemble_history(
        &bases,
        &snapshot.outputs,
        account.expose_uuid().as_bytes(),
        None,
    );
    let hexes: HashSet<_> = requested.iter().map(hex::encode).collect();
    rows.retain(|row| hexes.contains(&row.txid_hex));
    Ok(rows)
}

pub(crate) fn recent(
    path: &str,
    network: WalletNetwork,
    account: AccountUuid,
    limit: u32,
) -> Result<Vec<TransactionInfo>, String> {
    if limit == 0 {
        return Ok(Vec::new());
    }
    Ok(
        with_snapshot(path, network, account, None, false, |conn, snapshot| {
            recent_history::assemble_recent_history(
                snapshot.bases.clone(),
                account.expose_uuid().as_bytes(),
                limit,
                |batch| {
                    load_details(conn, snapshot, path, network, account, batch)?;
                    Ok(batch
                        .iter()
                        .filter_map(|b| {
                            snapshot
                                .outputs
                                .get(&b.txid)
                                .map(|outputs| (b.txid.clone(), outputs.clone()))
                        })
                        .collect())
                },
            )
        })?
        .unwrap(),
    )
}
