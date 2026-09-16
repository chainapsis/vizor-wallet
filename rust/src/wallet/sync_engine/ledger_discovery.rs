//! One-time, resumable transparent history recovery for imported Ledger accounts.
//! Subsequent address growth belongs to the ordinary UTXO sync, not this pass.
use futures::Stream;
use futures::{stream, StreamExt, TryStreamExt};
use rusqlite::{params, OptionalExtension};
use std::pin::Pin;
use tonic::transport::Channel;
use transparent::keys::TransparentKeyScope;
use zcash_client_backend::{
    data_api::{
        ll::LowLevelWalletWrite, wallet::decrypt_and_store_transaction, Account as _, WalletRead,
    },
    proto::service::{compact_tx_streamer_client::CompactTxStreamerClient, RawTransaction},
};
use zcash_client_sqlite::AccountUuid;
use zcash_keys::keys::{
    transparent::gap_limits::GapLimits, ReceiverRequirement::*, UnifiedAddressRequest,
};
use zcash_primitives::block::BlockHash;
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::{BlockHeight, BranchId};

use super::{get_taddress_txids, next_stream_message, watch_for_exit, SyncError};
use crate::wallet::{
    db::{
        open_readonly_conn_with_timeout, open_wallet_raw_conn_with_timeout,
        with_wallet_db_write_lock, WalletDatabase, SYNC_DB_BUSY_TIMEOUT,
    },
    keys::{self, HardwareSignerKind},
    network::WalletNetwork,
};

const TABLE: &str = "ext_vizor_ledger_initial_discovery";
const CONCURRENCY: usize = 4;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct Progress {
    next_index: u32,
    unused: u32,
}
impl Progress {
    fn advance(&mut self, used: bool) -> Result<(), SyncError> {
        self.next_index = self
            .next_index
            .checked_add(1)
            .filter(|i| *i <= 0x8000_0000)
            .ok_or_else(|| SyncError::other("Ledger discovery exhausted transparent indices"))?;
        self.unused = if used { 0 } else { self.unused + 1 };
        Ok(())
    }
    fn batch_size(self, gap: u32) -> usize {
        (gap.saturating_sub(self.unused) as usize).min(CONCURRENCY)
    }
}

fn table_exists(conn: &rusqlite::Connection) -> Result<bool, String> {
    conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name=?1)",
        [TABLE],
        |r| r.get(0),
    )
    .map_err(|e| e.to_string())
}

/// Read-only gate: a missing checkpoint means a Ledger import still needs recovery.
pub(crate) fn is_ready(db_path: &str, account_id: AccountUuid) -> Result<bool, String> {
    let conn = open_readonly_conn_with_timeout(db_path, Some(SYNC_DB_BUSY_TIMEOUT))?;
    let source: Option<String> = conn
        .query_row(
            "SELECT key_source FROM accounts WHERE uuid=?1",
            [account_id.expose_uuid().as_bytes().as_slice()],
            |r| r.get(0),
        )
        .map_err(|e| e.to_string())?;
    if source.as_deref() != Some(keys::KEY_SOURCE_LEDGER) {
        return Ok(true);
    }
    if !table_exists(&conn)? {
        return Ok(false);
    }
    conn.query_row(&format!("SELECT COUNT(*)=2 FROM {TABLE} WHERE account_uuid=?1 AND complete=2 AND key_scope IN (0,1)"), [account_id.expose_uuid().as_bytes().as_slice()], |r| r.get(0)).map_err(|e| e.to_string())
}

pub(crate) fn delete_account(conn: &rusqlite::Connection, uuid: &[u8]) -> Result<(), String> {
    if table_exists(conn)? {
        conn.execute(
            &format!("DELETE FROM {TABLE} WHERE account_uuid=?1"),
            [uuid],
        )
        .map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Invalidate Ledger discovery before truncating. The caller first invalidates
/// the shared UTXO cache and owns the wallet write lock.
pub(crate) fn truncate(
    db_path: &str,
    db: &mut WalletDatabase,
    height: BlockHeight,
) -> Result<BlockHeight, zcash_client_sqlite::error::SqliteClientError> {
    use zcash_client_backend::data_api::WalletWrite;
    invalidate_for_rewind(db_path, db, height)?;
    db.truncate_to_height(height)
}

pub(super) fn invalidate_for_rewind(
    _db_path: &str,
    db: &mut WalletDatabase,
    height: BlockHeight,
) -> Result<(), zcash_client_sqlite::error::SqliteClientError> {
    db.transactionally_with_extension(|_, ext| {
        let exists: bool = ext.query_row(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name=?1)",
            [TABLE],
            |r| r.get(0),
        )?;
        if exists {
            ext.execute(
                &format!("DELETE FROM {TABLE} WHERE tip_height > ?1"),
                [u32::from(height)],
            )?;
        }
        Ok::<_, zcash_client_sqlite::error::SqliteClientError>(())
    })
}

fn ensure_table(db_path: &str) -> Result<(), SyncError> {
    with_wallet_db_write_lock("ledger_discovery.schema", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT)
            .map_err(SyncError::db)?;
        conn.execute_batch(&format!("CREATE TABLE IF NOT EXISTS {TABLE} (
            account_uuid BLOB NOT NULL, key_scope INTEGER NOT NULL CHECK(key_scope IN (0,1)),
            tip_height INTEGER NOT NULL, tip_hash BLOB NOT NULL,
            next_index INTEGER NOT NULL, unused INTEGER NOT NULL, complete INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY(account_uuid,key_scope))")).map_err(|e| SyncError::db(e.to_string()))
    })
}

fn load(
    db_path: &str,
    id: AccountUuid,
    scope: u32,
) -> Result<Option<(Progress, u32, Vec<u8>, bool)>, SyncError> {
    let conn = open_readonly_conn_with_timeout(db_path, Some(SYNC_DB_BUSY_TIMEOUT))
        .map_err(SyncError::db)?;
    conn.query_row(&format!("SELECT next_index,unused,tip_height,tip_hash,complete FROM {TABLE} WHERE account_uuid=?1 AND key_scope=?2"), params![id.expose_uuid().as_bytes().as_slice(),scope], |r| Ok((Progress { next_index:r.get(0)?, unused:r.get(1)? },r.get(2)?,r.get(3)?,r.get(4)?))).optional().map_err(|e| SyncError::db(e.to_string()))
}

fn save(
    db_path: &str,
    id: AccountUuid,
    scope: u32,
    progress: Progress,
    tip: u32,
    hash: &[u8],
    complete: bool,
) -> Result<(), SyncError> {
    with_wallet_db_write_lock("ledger_discovery.checkpoint", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT)
            .map_err(SyncError::db)?;
        conn.execute(&format!("INSERT INTO {TABLE} (account_uuid,key_scope,next_index,unused,tip_height,tip_hash,complete)
            SELECT ?1,?2,?3,?4,?5,?6,?7 WHERE EXISTS(SELECT 1 FROM accounts WHERE uuid=?1)
            ON CONFLICT(account_uuid,key_scope) DO UPDATE SET next_index=excluded.next_index,unused=excluded.unused,tip_height=excluded.tip_height,tip_hash=excluded.tip_hash,complete=excluded.complete"), params![id.expose_uuid().as_bytes().as_slice(),scope,progress.next_index,progress.unused,tip,hash,complete]).map_err(|e| SyncError::db(e.to_string()))?;
        Ok(())
    })
}

type History = Pin<Box<dyn Stream<Item = Result<RawTransaction, SyncError>> + Send>>;

trait DiscoveryRpc: Clone {
    async fn block_hash(&mut self, height: u64) -> Result<BlockHash, SyncError>;
    async fn history(&mut self, address: String, tip: u64) -> Result<History, SyncError>;
}

impl DiscoveryRpc for CompactTxStreamerClient<Channel> {
    async fn block_hash(&mut self, height: u64) -> Result<BlockHash, SyncError> {
        super::get_compact_block_hash(self, height).await
    }
    async fn history(&mut self, address: String, tip: u64) -> Result<History, SyncError> {
        let history = get_taddress_txids(self, address, 0, tip).await?;
        Ok(Box::pin(stream::try_unfold(
            history,
            |mut history| async move {
                next_stream_message(&mut history, "ledger discovery history")
                    .await
                    .map(|raw| raw.map(|raw| (raw, history)))
            },
        )))
    }
}

/// Called by sync before its normal UTXO refresh; shares sync's cancellation lifetime.
pub(super) async fn run(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
    tip: BlockHeight,
    should_exit: &impl Fn() -> bool,
) -> Result<(), SyncError> {
    run_with(client, db, db_path, network, tip, should_exit).await
}

async fn run_with<R: DiscoveryRpc>(
    client: &mut R,
    db: &mut WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
    tip: BlockHeight,
    should_exit: &impl Fn() -> bool,
) -> Result<(), SyncError> {
    let mut accounts = Vec::new();
    for id in db
        .get_account_ids()
        .map_err(|e| SyncError::db(e.to_string()))?
    {
        let account = db
            .get_account(id)
            .map_err(|e| SyncError::db(e.to_string()))?
            .ok_or_else(|| SyncError::db("Ledger account disappeared"))?;
        if keys::hardware_signer_kind(account.source()) == Some(HardwareSignerKind::Ledger) {
            if account.ufvk().and_then(|k| k.transparent()).is_none() {
                return Err(SyncError::other(
                    "Ledger account has no transparent viewing key",
                ));
            }
            accounts.push(id);
        }
    }
    if accounts.is_empty() || should_exit() {
        return Ok(());
    }
    ensure_table(db_path)?;
    for id in accounts {
        if is_ready(db_path, id).map_err(SyncError::db)? {
            continue;
        }
        for (scope_code, scope, gap) in [
            (
                0,
                TransparentKeyScope::EXTERNAL,
                GapLimits::default().external(),
            ),
            (
                1,
                TransparentKeyScope::INTERNAL,
                GapLimits::default().internal(),
            ),
        ] {
            if should_exit() {
                return Ok(());
            }
            let state = load(db_path, id, scope_code)?;
            let mut scan_tip = u32::from(tip);
            let mut progress = Progress::default();
            if let Some((saved, height, hash, complete)) = state {
                if height <= scan_tip {
                    let actual = tokio::select! { biased; _ = watch_for_exit(should_exit) => return Ok(()), r = client.block_hash(u64::from(height)) => r? };
                    if actual.0.as_slice() == hash {
                        if complete {
                            continue;
                        }
                        progress = saved;
                        scan_tip = height;
                    }
                }
            }
            let hash = tokio::select! { biased; _ = watch_for_exit(should_exit) => return Ok(()), r = client.block_hash(u64::from(scan_tip)) => r? };
            if should_exit() {
                return Ok(());
            }
            save(db_path, id, scope_code, progress, scan_tip, &hash.0, false)?;
            let started = std::time::Instant::now();
            log::info!(
                "ledger discovery: account={} scope={} resume_index={} tip={}",
                id.expose_uuid(),
                scope_code,
                progress.next_index,
                scan_tip
            );
            while progress.unused < gap {
                if should_exit() {
                    return Ok(());
                }
                with_wallet_db_write_lock("ledger_discovery.addresses", || {
                    db.transactionally(|tx| {
                        tx.generate_transparent_gap_addresses(
                            id,
                            scope,
                            UnifiedAddressRequest::unsafe_custom(Allow, Allow, Require),
                        )
                    })
                })
                .map_err(|e| SyncError::db(e.to_string()))?;
                let candidates = next_candidates(
                    db_path,
                    network,
                    id,
                    scope_code,
                    progress.next_index,
                    progress.batch_size(gap),
                )?;
                if candidates.first().map(|c| c.0) != Some(progress.next_index) {
                    return Err(SyncError::db(
                        "Ledger discovery candidate range is incomplete",
                    ));
                }
                // Only stream headers are acquired concurrently. Bodies are drained and stored
                // incrementally, so heavily reused addresses cannot accumulate unbounded history.
                let opening = stream::iter(candidates)
                    .map(|(index, address)| {
                        let mut client = client.clone();
                        async move {
                            let stream = client.history(address, u64::from(scan_tip)).await?;
                            Ok::<_, SyncError>((index, stream))
                        }
                    })
                    .buffered(CONCURRENCY)
                    .try_collect::<Vec<_>>();
                let streams = tokio::select! { biased; _ = watch_for_exit(should_exit) => return Ok(()), result = opening => result? };
                for (index, mut history) in streams {
                    if index != progress.next_index {
                        return Err(SyncError::db("Ledger discovery candidate index skipped"));
                    }
                    let Some(used) = store_history(
                        &mut history,
                        db,
                        network,
                        scan_tip,
                        (id, scope_code, index),
                        should_exit,
                    )
                    .await?
                    else {
                        return Ok(());
                    };
                    if should_exit() {
                        return Ok(());
                    }
                    progress.advance(used)?;
                    save(db_path, id, scope_code, progress, scan_tip, &hash.0, false)?;
                    log::info!(
                        "ledger discovery: account={} scope={} index={} used={} gap={}/{} elapsed_ms={}",
                        id.expose_uuid(),
                        scope_code,
                        index,
                        used,
                        progress.unused,
                        gap,
                        started.elapsed().as_millis()
                    );
                }
            }
            // A reorg during the pass must not turn stale empty responses into completion.
            let final_hash = tokio::select! { biased; _ = watch_for_exit(should_exit) => return Ok(()), r = client.block_hash(u64::from(scan_tip)) => r? };
            if final_hash != hash {
                save(
                    db_path,
                    id,
                    scope_code,
                    Progress::default(),
                    scan_tip,
                    &final_hash.0,
                    false,
                )?;
                return Err(SyncError::other("Ledger discovery chain changed; retrying"));
            }
            if should_exit() {
                return Ok(());
            }
            save(db_path, id, scope_code, progress, scan_tip, &hash.0, true)?;
            log::info!(
                "ledger discovery: account={} scope={} complete addresses={} elapsed_ms={}",
                id.expose_uuid(),
                scope_code,
                progress.next_index,
                started.elapsed().as_millis()
            );
        }
        // Publish account readiness only after both scopes agree with the chain.
        // Scope-complete (1) is resumable; account-complete (2) opens shielding.
        for scope in 0..2 {
            let (_, height, hash, complete) = load(db_path, id, scope)?
                .ok_or_else(|| SyncError::db("Ledger recovery checkpoint missing"))?;
            if !complete {
                return Err(SyncError::db("Ledger recovery scope incomplete"));
            }
            let actual = tokio::select! { biased; _ = watch_for_exit(should_exit) => return Ok(()), r = client.block_hash(u64::from(height)) => r? };
            if actual.0.as_slice() != hash {
                if should_exit() {
                    return Ok(());
                }
                save(
                    db_path,
                    id,
                    scope,
                    Progress::default(),
                    height,
                    &actual.0,
                    false,
                )?;
                return Err(SyncError::other(
                    "Ledger recovery scope chain changed; retrying",
                ));
            }
        }
        if should_exit() {
            return Ok(());
        }
        with_wallet_db_write_lock("ledger_discovery.complete", || {
            let conn = open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT)
                .map_err(SyncError::db)?;
            conn.execute(
                &format!("UPDATE {TABLE} SET complete=2 WHERE account_uuid=?1 AND complete=1"),
                [id.expose_uuid().as_bytes().as_slice()],
            )
            .map_err(|e| SyncError::db(e.to_string()))?;
            Ok::<_, SyncError>(())
        })?;
    }
    Ok(())
}

// Read only the next bounded child-index range, rather than decoding every
// registered receiver again for each four-address batch.
fn next_candidates(
    db_path: &str,
    network: WalletNetwork,
    id: AccountUuid,
    scope: u32,
    next_index: u32,
    limit: usize,
) -> Result<Vec<(u32, String)>, SyncError> {
    let conn = open_readonly_conn_with_timeout(db_path, Some(SYNC_DB_BUSY_TIMEOUT))
        .map_err(SyncError::db)?;
    let mut stmt = conn
        .prepare(
            "SELECT a.transparent_child_index, a.cached_transparent_receiver_address
         FROM addresses a JOIN accounts acct ON acct.id=a.account_id
         WHERE acct.uuid=?1 AND a.key_scope=?2 AND a.transparent_child_index>=?3
           AND a.cached_transparent_receiver_address IS NOT NULL
         ORDER BY a.transparent_child_index LIMIT ?4",
        )
        .map_err(|e| SyncError::db(e.to_string()))?;
    let rows = stmt
        .query_map(
            params![
                id.expose_uuid().as_bytes().as_slice(),
                scope,
                next_index,
                limit
            ],
            |r| Ok((r.get::<_, u32>(0)?, r.get::<_, String>(1)?)),
        )
        .map_err(|e| SyncError::db(e.to_string()))?;
    rows.map(|r| {
        let (index, address) = r.map_err(|e| SyncError::db(e.to_string()))?;
        super::transparent_address_for_query(
            &address,
            network,
            super::transparent_utxo_query_network(network),
        )
        .map(|a| (index, a))
        .map_err(SyncError::parse)
    })
    .collect()
}

async fn store_history(
    history: &mut History,
    db: &mut WalletDatabase,
    network: WalletNetwork,
    tip: u32,
    context: (AccountUuid, u32, u32),
    should_exit: &impl Fn() -> bool,
) -> Result<Option<bool>, SyncError> {
    let started = std::time::Instant::now();
    let mut transactions = 0usize;
    let mut response_bytes = 0usize;
    loop {
        let raw = tokio::select! { biased; _ = watch_for_exit(should_exit) => return Ok(None), r = history.next() => r.transpose()? };
        let Some(raw) = raw else {
            log::info!(
                "ledger discovery history: account={} scope={} index={} rpc_count=1 transactions={} response_bytes={} elapsed_ms={}",
                context.0.expose_uuid(), context.1, context.2, transactions,
                response_bytes,
                started.elapsed().as_millis()
            );
            return Ok(Some(transactions > 0));
        };
        response_bytes += prost::Message::encoded_len(&raw);
        let height = u32::try_from(raw.height)
            .ok()
            .filter(|h| *h > 0 && *h <= tip)
            .ok_or_else(|| SyncError::parse("Ledger history returned an invalid mined height"))?;
        let tx = Transaction::read(
            &raw.data[..],
            BranchId::for_height(&network, BlockHeight::from_u32(height)),
        )
        .map_err(|e| SyncError::parse(format!("Ledger history transaction: {e}")))?;
        if should_exit() {
            return Ok(None);
        }
        with_wallet_db_write_lock("ledger_discovery.transaction", || {
            decrypt_and_store_transaction(&network, db, &tx, Some(BlockHeight::from_u32(height)))
        })
        .map_err(|e| SyncError::db(format!("Ledger history store: {e}")))?;
        transactions += 1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use zcash_keys::encoding::AddressCodec;
    #[test]
    fn spent_addresses_extend_the_same_gap_as_funded_addresses() {
        let mut p = Progress::default();
        for _ in 0..9 {
            p.advance(false).unwrap();
        }
        assert_eq!(p.batch_size(10), 1);
        p.advance(true).unwrap(); // History exists; current UTXO balance is irrelevant.
        assert_eq!(
            p,
            Progress {
                next_index: 10,
                unused: 0
            }
        );
        for _ in 0..10 {
            p.advance(false).unwrap();
        }
        assert_eq!(p.next_index, 20);
        assert_eq!(p.batch_size(10), 0);
    }
    #[test]
    fn scopes_follow_library_defaults_without_overquerying_tail() {
        let gaps = GapLimits::default();
        assert_eq!((gaps.external(), gaps.internal()), (10, 5));
        let p = Progress {
            next_index: 4,
            unused: 4,
        };
        assert_eq!(p.batch_size(gaps.internal()), 1);
        assert_eq!(p.batch_size(gaps.external()), 4);
    }

    #[derive(Clone)]
    struct FakeRpc {
        histories: std::sync::Arc<std::collections::HashMap<String, Vec<RawTransaction>>>,
        queries: std::sync::Arc<std::sync::Mutex<Vec<String>>>,
        fail_address: Option<String>,
        hash: u8,
    }
    impl DiscoveryRpc for FakeRpc {
        async fn block_hash(&mut self, _: u64) -> Result<BlockHash, SyncError> {
            Ok(BlockHash([self.hash; 32]))
        }
        async fn history(&mut self, address: String, _: u64) -> Result<History, SyncError> {
            self.queries.lock().unwrap().push(address.clone());
            let mut items = self
                .histories
                .get(&address)
                .cloned()
                .unwrap_or_default()
                .into_iter()
                .map(Ok)
                .collect::<Vec<_>>();
            if self.fail_address.as_ref() == Some(&address) {
                items.push(Err(SyncError::other("injected stream failure")));
            }
            Ok(Box::pin(stream::iter(items)))
        }
    }
    fn ledger_fixture() -> (
        tempfile::TempDir,
        String,
        AccountUuid,
        WalletDatabase,
        zcash_keys::keys::UnifiedFullViewingKey,
    ) {
        use secrecy::ExposeSecret;
        use zcash_client_backend::data_api::WalletWrite;
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
        let seed=keys::mnemonic_to_seed("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about").unwrap();
        let ufvk = zcash_keys::keys::UnifiedSpendingKey::from_seed(
            &WalletNetwork::Main,
            seed.expose_secret(),
            zip32::AccountId::try_from(7).unwrap(),
        )
        .unwrap()
        .to_unified_full_viewing_key();
        let fp = zip32::fingerprint::SeedFingerprint::from_seed(seed.expose_secret())
            .unwrap()
            .to_bytes();
        let (uuid, _) = keys::import_hardware_account(
            &path,
            WalletNetwork::Main,
            "Ledger",
            &ufvk.encode(&WalletNetwork::Main),
            &fp,
            7,
            Some(2_500_000),
            HardwareSignerKind::Ledger,
        )
        .unwrap();
        let mut db = crate::wallet::db::open_wallet_db_with_timeout(
            &path,
            WalletNetwork::Main,
            SYNC_DB_BUSY_TIMEOUT,
        )
        .unwrap();
        db.update_chain_tip(BlockHeight::from_u32(2_600_000))
            .unwrap();
        (
            dir,
            path,
            keys::parse_account_uuid(&uuid).unwrap(),
            db,
            ufvk,
        )
    }
    fn payment(
        outpoint: transparent::bundle::OutPoint,
        address: transparent::address::TransparentAddress,
        height: u32,
    ) -> (RawTransaction, zcash_primitives::transaction::TxId) {
        use transparent::{
            address::Script,
            bundle::{Authorized, Bundle, TxIn, TxOut},
        };
        use zcash_primitives::transaction::{TransactionData, TxVersion};
        let tx = TransactionData::<zcash_primitives::transaction::Authorized>::from_parts(
            TxVersion::V5,
            BranchId::Nu5,
            0,
            BlockHeight::from_u32(0),
            Some(Bundle {
                vin: vec![TxIn::from_parts(outpoint, Script::default(), u32::MAX)],
                vout: vec![TxOut::new(
                    zcash_protocol::value::Zatoshis::const_from_u64(100_000),
                    address.script().into(),
                )],
                authorization: Authorized,
            }),
            None,
            None,
            None,
        )
        .freeze()
        .unwrap();
        let mut data = Vec::new();
        tx.write(&mut data).unwrap();
        (
            RawTransaction {
                data,
                height: u64::from(height),
            },
            tx.txid(),
        )
    }
    #[test]
    fn rewind_invalidates_both_query_caches_even_after_discovery_anchor() {
        use crate::wallet::transparent_receive_cache::{self as cache};
        let (_dir, path, id, mut db, _) = ledger_fixture();
        let uuid = id.expose_uuid().to_string();
        let external = vec![keys::ExternalTransparentAddress {
            child_index: 0,
            address: "external".into(),
            has_received: false,
        }];
        let internal = vec![(0, "internal".into())];
        let plan_external = || {
            cache::plan_external_utxo_refresh(
                &path,
                WalletNetwork::Main,
                &uuid,
                &external,
                0,
                0,
                20,
                20,
            )
            .unwrap()
        };
        let plan_internal = || {
            cache::plan_internal_utxo_refresh(&path, WalletNetwork::Main, &uuid, &internal, 20, 20)
                .unwrap()
        };
        plan_external();
        plan_internal();
        cache::mark_utxo_refresh_batch_complete(
            &path,
            WalletNetwork::Main,
            &uuid,
            &[0],
            2_600_001,
            None,
        )
        .unwrap();
        cache::mark_non_external_utxo_refresh_complete(
            &path,
            WalletNetwork::Main,
            &uuid,
            &["internal".into()],
            2_600_001,
        )
        .unwrap();
        assert_eq!(plan_external()[0].start_height, 2_599_901);
        assert_eq!(plan_internal()[0].start_height, 2_599_901);
        // An early recovery anchor remains valid across this later rewind.
        ensure_table(&path).unwrap();
        for scope in [0, 1] {
            save(
                &path,
                id,
                scope,
                Progress::default(),
                2_500_000,
                &[1; 32],
                true,
            )
            .unwrap();
        }
        cache::invalidate_utxo_checks(&path).unwrap();
        invalidate_for_rewind(&path, &mut db, BlockHeight::from_u32(2_550_000)).unwrap();
        assert!(load(&path, id, 0).unwrap().is_some());
        assert_eq!(plan_external()[0].start_height, 0);
        assert_eq!(plan_internal()[0].start_height, 0);
        // A subsequent successful batch can advance normally after invalidation.
        cache::mark_non_external_utxo_refresh_complete(
            &path,
            WalletNetwork::Main,
            &uuid,
            &["internal".into()],
            2_550_001,
        )
        .unwrap();
        assert_eq!(plan_internal()[0].start_height, 2_549_901);
    }

    #[test]
    fn candidate_query_matches_library_receivers_and_limits_each_scope() {
        let (_dir, path, id, db, _) = ledger_fixture();
        let receivers = db.get_transparent_receivers(id, true, false).unwrap();
        for (code, scope) in [
            (0, TransparentKeyScope::EXTERNAL),
            (1, TransparentKeyScope::INTERNAL),
        ] {
            let mut expected = receivers
                .iter()
                .filter(|(_, m)| m.scope() == Some(scope))
                .map(|(a, m)| {
                    (
                        m.address_index().unwrap().index(),
                        a.encode(&WalletNetwork::Main),
                    )
                })
                .filter(|(i, _)| *i >= 1)
                .collect::<Vec<_>>();
            expected.sort_by_key(|c| c.0);
            expected.truncate(4);
            assert_eq!(
                next_candidates(&path, WalletNetwork::Main, id, code, 1, 4).unwrap(),
                expected
            );
        }
    }

    #[tokio::test]
    async fn discovers_spent_history_beyond_initial_gaps_and_runs_only_once() {
        use transparent::keys::{IncomingViewingKey, NonHardenedChildIndex};
        let (_dir, path, id, mut db, ufvk) = ledger_fixture();
        let external = ufvk.transparent().unwrap().derive_external_ivk().unwrap();
        let internal = ufvk.transparent().unwrap().derive_internal_ivk().unwrap();
        let mut histories = std::collections::HashMap::new();
        for scope in 0..2 {
            let count = if scope == 0 { 13 } else { 6 };
            for i in 0..count {
                let index = NonHardenedChildIndex::from_index(i).unwrap();
                let addr = if scope == 0 {
                    external.derive_address(index).unwrap()
                } else {
                    internal.derive_address(index).unwrap()
                };
                let (received, txid) = payment(
                    transparent::bundle::OutPoint::new([i as u8 + scope * 30; 32], 0),
                    addr,
                    2_000_000,
                );
                let (spent, _) = payment(
                    transparent::bundle::OutPoint::new(*txid.as_ref(), 0),
                    transparent::address::TransparentAddress::PublicKeyHash([99; 20]),
                    2_000_001,
                );
                histories.insert(addr.encode(&WalletNetwork::Main), vec![received, spent]);
            }
        }
        let mut rpc = FakeRpc {
            histories: std::sync::Arc::new(histories),
            queries: Default::default(),
            fail_address: None,
            hash: 1,
        };
        assert!(!is_ready(&path, id).unwrap());
        run_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            BlockHeight::from_u32(2_600_000),
            &|| false,
        )
        .await
        .unwrap();
        assert!(is_ready(&path, id).unwrap());
        assert_eq!(
            load(&path, id, 0).unwrap().unwrap().0,
            Progress {
                next_index: 23,
                unused: 10
            }
        );
        assert_eq!(
            load(&path, id, 1).unwrap().unwrap().0,
            Progress {
                next_index: 11,
                unused: 5
            }
        );
        assert_eq!(rpc.queries.lock().unwrap().len(), 34);
        run_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            BlockHeight::from_u32(2_600_001),
            &|| false,
        )
        .await
        .unwrap();
        assert_eq!(rpc.queries.lock().unwrap().len(), 34);
        let conn = rusqlite::Connection::open(&path).unwrap();
        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM transparent_received_output_spends",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(count, 19);
    }
    #[tokio::test]
    async fn failed_stream_is_not_unused_and_resume_keeps_completed_indices() {
        use transparent::keys::{IncomingViewingKey, NonHardenedChildIndex};
        let (_dir, path, id, mut db, ufvk) = ledger_fixture();
        let addr = ufvk
            .transparent()
            .unwrap()
            .derive_external_ivk()
            .unwrap()
            .derive_address(NonHardenedChildIndex::from_index(3).unwrap())
            .unwrap()
            .encode(&WalletNetwork::Main);
        let mut rpc = FakeRpc {
            histories: Default::default(),
            queries: Default::default(),
            fail_address: Some(addr),
            hash: 1,
        };
        assert!(run_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            BlockHeight::from_u32(2_600_000),
            &|| false
        )
        .await
        .is_err());
        assert_eq!(
            load(&path, id, 0).unwrap().unwrap().0,
            Progress {
                next_index: 3,
                unused: 3
            }
        );
        assert!(!is_ready(&path, id).unwrap());
        drop(db);
        let mut db = crate::wallet::db::open_wallet_db_with_timeout(
            &path,
            WalletNetwork::Main,
            SYNC_DB_BUSY_TIMEOUT,
        )
        .unwrap();
        rpc.fail_address = None;
        rpc.queries.lock().unwrap().clear();
        run_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            BlockHeight::from_u32(2_600_010),
            &|| false,
        )
        .await
        .unwrap();
        assert_eq!(rpc.queries.lock().unwrap().len(), 12);
        assert!(is_ready(&path, id).unwrap());
    }
    #[tokio::test]
    async fn cancelled_discovery_does_not_create_checkpoints() {
        let (_dir, path, id, mut db, _) = ledger_fixture();
        let mut rpc = FakeRpc {
            histories: Default::default(),
            queries: Default::default(),
            fail_address: None,
            hash: 1,
        };
        run_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            BlockHeight::from_u32(2_600_000),
            &|| true,
        )
        .await
        .unwrap();
        assert!(!is_ready(&path, id).unwrap());
        assert!(rpc.queries.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn changed_chain_restarts_partial_history_and_rewind_invalidates_completion() {
        use transparent::keys::{IncomingViewingKey, NonHardenedChildIndex};
        let (_dir, path, id, mut db, ufvk) = ledger_fixture();
        let addr = ufvk
            .transparent()
            .unwrap()
            .derive_external_ivk()
            .unwrap()
            .derive_address(NonHardenedChildIndex::from_index(3).unwrap())
            .unwrap()
            .encode(&WalletNetwork::Main);
        let mut rpc = FakeRpc {
            histories: Default::default(),
            queries: Default::default(),
            fail_address: Some(addr),
            hash: 1,
        };
        assert!(run_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            BlockHeight::from_u32(2_600_000),
            &|| false
        )
        .await
        .is_err());
        rpc.hash = 2;
        rpc.fail_address = None;
        rpc.queries.lock().unwrap().clear();
        run_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            BlockHeight::from_u32(2_600_001),
            &|| false,
        )
        .await
        .unwrap();
        assert_eq!(rpc.queries.lock().unwrap().len(), 15);
        assert!(is_ready(&path, id).unwrap());
        // Invalidation precedes the truncate, including when the wallet cannot rewind.
        let _ = truncate(&path, &mut db, BlockHeight::from_u32(2_599_999));
        assert!(!is_ready(&path, id).unwrap());
        let conn = rusqlite::Connection::open(&path).unwrap();
        delete_account(&conn, id.expose_uuid().as_bytes()).unwrap();
        assert!(load(&path, id, 0).unwrap().is_none());
    }

    #[tokio::test]
    async fn resume_revalidates_finished_scope_before_publishing_account_ready() {
        use transparent::keys::{IncomingViewingKey, NonHardenedChildIndex};
        let (_dir, path, id, mut db, ufvk) = ledger_fixture();
        let addr = ufvk
            .transparent()
            .unwrap()
            .derive_internal_ivk()
            .unwrap()
            .derive_address(NonHardenedChildIndex::ZERO)
            .unwrap()
            .encode(&WalletNetwork::Main);
        let mut rpc = FakeRpc {
            histories: Default::default(),
            queries: Default::default(),
            fail_address: Some(addr),
            hash: 1,
        };
        assert!(run_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            BlockHeight::from_u32(2_600_000),
            &|| false
        )
        .await
        .is_err());
        assert!(load(&path, id, 0).unwrap().unwrap().3);
        assert!(!is_ready(&path, id).unwrap());
        rpc.hash = 2;
        rpc.fail_address = None;
        rpc.queries.lock().unwrap().clear();
        run_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            BlockHeight::from_u32(2_600_001),
            &|| false,
        )
        .await
        .unwrap();
        assert_eq!(rpc.queries.lock().unwrap().len(), 15);
        assert!(is_ready(&path, id).unwrap());
    }
}
