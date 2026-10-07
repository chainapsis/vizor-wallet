//! Public-mode transparent history discovery, shared by every account kind.
//!
//! Compact blocks carry no transparent data, so in public mode an account's
//! transparent history comes from lightwalletd address queries. UTXO streams
//! return only unspent outputs, and the library's spend searches cover only
//! outputs it already knows, so neither finds an output that was received and
//! spent before the wallet first looked, and what they find depends on the
//! order in which transactions arrive. This component establishes an account's
//! transparent history once, whatever its kind (software, Ledger, Keystone):
//!
//! 1. **Initial discovery** ([`run`], before the chain scan): every derived
//!    external and internal address, by child index, over its whole mined
//!    history, until the library's gap limit of unused addresses. An address
//!    with any history, spent or not, is used. Progress is checkpointed per
//!    scope against a block hash, so a pass resumes where it stopped and a
//!    reorg restarts it.
//! 2. **Restored TEX operations** ([`run_restored_ephemeral`], after the chain
//!    scan): an ephemeral-address output the wallet learned from the chain
//!    rather than built itself, such as a ZIP 320 first leg found by a restore,
//!    is checked once, immediately, so its second leg and any returned funds
//!    are found now rather than on the randomized ZIP 320 schedule, which
//!    still applies afterwards ([`super::ephemeral_checks`]). Each such query
//!    uses its own channel, like the scheduled checks.
//!
//! Afterwards the ordinary UTXO refresh and the library's spend searches keep
//! the history current. [`Coverage`] reports whether an account's public
//! history is complete: initial discovery done, no restored ephemeral output
//! unchecked, and no spend search due at or below the tip. Balances report
//! transparent funds as current, shielding spends them, and sync reports
//! completion only when it is complete.
//!
//! Every request sends a wallet address to public lightwalletd, so it goes
//! through [`TransparentLookupGate`]; every write that marks work done reads
//! the durable policy in its own SQLite transaction. Under a private
//! transparent policy nothing is queried, and the private ledger owns
//! completeness instead.
use futures::Stream;
use futures::{stream, StreamExt, TryStreamExt};
use rusqlite::{params, params_from_iter, OptionalExtension};
use std::pin::Pin;
use tonic::transport::Channel;
use transparent::address::TransparentAddress;
use transparent::keys::TransparentKeyScope;
use zcash_client_backend::{
    data_api::{
        ll::LowLevelWalletWrite,
        transparent_ledger::{TransparentAuthority, TransparentLedgerRead},
        wallet::decrypt_and_store_transaction,
        Account as _, OutputStatusFilter, TransactionDataRequest, TransactionStatusFilter,
        WalletRead, WalletWrite,
    },
    proto::service::{compact_tx_streamer_client::CompactTxStreamerClient, RawTransaction},
};
use zcash_client_sqlite::{error::SqliteClientError, AccountUuid, ExtensionTransaction};
use zcash_keys::encoding::{encode_transparent_address_p, AddressCodec as _};
use zcash_keys::keys::{
    transparent::gap_limits::GapLimits, ReceiverRequirement::*, UnifiedAddressRequest,
};
use zcash_primitives::block::BlockHash;
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::{BlockHeight, BranchId};

use super::enhancement::EnhancementPolicy;
use super::{next_stream_message, watch_for_exit, SyncError, TransparentLookupGate};
use crate::wallet::{
    db::{
        open_readonly_conn_with_timeout, open_wallet_raw_conn_with_timeout,
        with_wallet_db_write_lock, WalletDatabase, SYNC_DB_BUSY_TIMEOUT,
    },
    keys::{self, HardwareSignerKind},
    network::WalletNetwork,
};

/// Per-scope checkpoints. The name predates other account kinds: released
/// builds created it for Ledger imports, and keep reading it for them.
const TABLE: &str = "ext_vizor_ledger_initial_discovery";
const CONCURRENCY: usize = 4;

/// An unspent ephemeral-address output that the wallet learned from the chain
/// (its transaction was not built locally) and whose address has never been
/// checked: no observation of it as unspent is recorded. Key scope 2 is
/// `KeyScope::Ephemeral` as encoded in `addresses.key_scope`.
const RESTORED_EPHEMERAL_OUTPUTS: &str = "
    FROM transparent_received_outputs tro
    JOIN addresses a ON a.id = tro.address_id
    JOIN accounts acct ON acct.id = a.account_id
    JOIN transactions t ON t.id_tx = tro.transaction_id
    WHERE a.key_scope = 2
      AND t.mined_height IS NOT NULL
      AND t.created IS NULL
      AND tro.max_observed_unspent_height IS NULL
      AND NOT EXISTS (
          SELECT 1 FROM transparent_received_output_spends s
          WHERE s.transparent_received_output_id = tro.id
      )";

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
            .ok_or_else(|| SyncError::other("Address discovery exhausted transparent indices"))?;
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

fn initial_discovery_complete_sql() -> String {
    format!(
        "SELECT COUNT(*)=2 FROM {TABLE} WHERE account_uuid=?1 AND complete=2 AND key_scope IN (0,1)"
    )
}

/// Whether both derived scopes of `account_id` finished initial discovery and
/// were published as one account. Says nothing about whether the account
/// needs discovery at all; see [`Coverage`].
pub(crate) fn initial_discovery_complete(
    db_path: &str,
    account_id: AccountUuid,
) -> Result<bool, String> {
    let conn = open_readonly_conn_with_timeout(db_path, Some(SYNC_DB_BUSY_TIMEOUT))?;
    if !table_exists(&conn)? {
        return Ok(false);
    }
    conn.query_row(
        &initial_discovery_complete_sql(),
        [account_id.expose_uuid().as_bytes().as_slice()],
        |r| r.get(0),
    )
    .map_err(|e| e.to_string())
}

/// Records `account_id`'s initial discovery as complete at `tip`, as a sync
/// that discovered both scopes would. For fixtures that build wallet state
/// directly instead of syncing.
#[cfg(test)]
pub(crate) fn record_initial_discovery_for_test(db_path: &str, account_id: AccountUuid, tip: u32) {
    ensure_table(db_path).unwrap();
    let conn = open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT).unwrap();
    for scope in 0..2u32 {
        conn.execute(
            &upsert_checkpoint_sql(),
            params![
                account_id.expose_uuid().as_bytes().as_slice(),
                scope,
                0u32,
                0u32,
                tip,
                [0u8; 32].as_slice(),
                2
            ],
        )
        .unwrap();
    }
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

/// Invalidate address discovery before truncating. The caller first
/// invalidates the shared UTXO cache and owns the wallet write lock.
pub(crate) fn truncate(
    db_path: &str,
    db: &mut WalletDatabase,
    height: BlockHeight,
) -> Result<BlockHeight, zcash_client_sqlite::error::SqliteClientError> {
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
    with_wallet_db_write_lock("address_discovery.schema", || {
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

fn upsert_checkpoint_sql() -> String {
    format!("INSERT INTO {TABLE} (account_uuid,key_scope,next_index,unused,tip_height,tip_hash,complete)
            SELECT ?1,?2,?3,?4,?5,?6,?7 WHERE EXISTS(SELECT 1 FROM accounts WHERE uuid=?1)
            ON CONFLICT(account_uuid,key_scope) DO UPDATE SET next_index=excluded.next_index,unused=excluded.unused,tip_height=excluded.tip_height,tip_hash=excluded.tip_hash,complete=excluded.complete")
}

/// Writes a checkpoint that marks no candidate checked: a pass's starting
/// tip, or a reset after a reorg.
fn save(
    db_path: &str,
    id: AccountUuid,
    scope: u32,
    progress: Progress,
    tip: u32,
    hash: &[u8],
    complete: bool,
) -> Result<(), SyncError> {
    with_wallet_db_write_lock("address_discovery.checkpoint", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT)
            .map_err(SyncError::db)?;
        conn.execute(
            &upsert_checkpoint_sql(),
            params![
                id.expose_uuid().as_bytes().as_slice(),
                scope,
                progress.next_index,
                progress.unused,
                tip,
                hash,
                complete
            ],
        )
        .map_err(|e| SyncError::db(e.to_string()))?;
        Ok(())
    })
}

/// Writes a checkpoint that marks candidates checked, or a scope complete, in
/// the SQLite transaction that reads the durable policy, so a transition by
/// another connection fails the write instead of slipping past the check.
/// Returns `false`, writing nothing, when `gate` no longer authorizes it.
#[allow(clippy::too_many_arguments)]
fn commit(
    db: &mut WalletDatabase,
    gate: &TransparentLookupGate,
    id: AccountUuid,
    scope: u32,
    progress: Progress,
    tip: u32,
    hash: &[u8],
    complete: bool,
) -> Result<bool, SyncError> {
    commit_extension(db, gate, "address_discovery.checkpoint", |ext| {
        ext.execute(
            &upsert_checkpoint_sql(),
            params![
                id.expose_uuid().as_bytes().as_slice(),
                scope,
                progress.next_index,
                progress.unused,
                tip,
                hash,
                complete
            ],
        )
    })
}

/// Runs `write` against Vizor's extension tables only while `gate` still
/// authorizes it, reading the policy in the same transaction.
fn commit_extension(
    db: &mut WalletDatabase,
    gate: &TransparentLookupGate,
    label: &'static str,
    write: impl FnOnce(&zcash_client_sqlite::ExtensionTransaction<'_>) -> rusqlite::Result<usize>,
) -> Result<bool, SyncError> {
    with_wallet_db_write_lock(label, || {
        db.transactionally_with_extension(|wdb, ext| {
            if !gate.permits_applied(wdb.applied_transparent_policy()?) {
                return Ok(false);
            }
            write(ext)?;
            Ok::<_, SqliteClientError>(true)
        })
    })
    .map_err(|e| SyncError::db(e.to_string()))
}

type History = Pin<Box<dyn Stream<Item = Result<RawTransaction, SyncError>> + Send>>;

trait DiscoveryRpc: Clone {
    async fn block_hash(&mut self, height: u64) -> Result<BlockHash, SyncError>;
    /// Opens `address`'s mined history through `gate` over the sync's channel;
    /// `None` means withheld, and then nothing was sent.
    async fn history(
        &mut self,
        gate: &TransparentLookupGate,
        address: String,
        tip: u64,
    ) -> Result<Option<History>, SyncError>;
    /// Like [`Self::history`], over a channel of its own (an isolated circuit
    /// when Tor is enabled), for an address that must not be linked to the
    /// others by connection.
    async fn isolated_history(
        &mut self,
        gate: &TransparentLookupGate,
        address: String,
        tip: u64,
    ) -> Result<Option<History>, SyncError>;
}

/// Production discovery transport: the sync's lightwalletd client, plus its
/// endpoint for isolated channels.
#[derive(Clone)]
struct Lightwalletd {
    client: CompactTxStreamerClient<Channel>,
    url: String,
}

fn stream_history(
    history: tonic::Streaming<RawTransaction>,
    label: &'static str,
    keep_alive: Option<CompactTxStreamerClient<Channel>>,
) -> History {
    Box::pin(stream::try_unfold(
        (history, keep_alive),
        move |(mut history, keep_alive)| async move {
            next_stream_message(&mut history, label)
                .await
                .map(|raw| raw.map(|raw| (raw, (history, keep_alive))))
        },
    ))
}

impl DiscoveryRpc for Lightwalletd {
    async fn block_hash(&mut self, height: u64) -> Result<BlockHash, SyncError> {
        super::get_compact_block_hash(&mut self.client, height).await
    }
    async fn history(
        &mut self,
        gate: &TransparentLookupGate,
        address: String,
        tip: u64,
    ) -> Result<Option<History>, SyncError> {
        let Some(history) = gate
            .taddress_txids(&mut self.client, address, 0, tip)
            .await?
        else {
            return Ok(None);
        };
        Ok(Some(stream_history(
            history,
            "address discovery history",
            None,
        )))
    }
    async fn isolated_history(
        &mut self,
        gate: &TransparentLookupGate,
        address: String,
        tip: u64,
    ) -> Result<Option<History>, SyncError> {
        let mut client = super::lwd::open_isolated_lwd_channel(&self.url).await?;
        let Some(history) = gate.taddress_txids(&mut client, address, 0, tip).await? else {
            return Ok(None);
        };
        // The client lives as long as its stream is read.
        Ok(Some(stream_history(
            history,
            "restored ephemeral address history",
            Some(client),
        )))
    }
}

/// The accounts whose derived addresses initial discovery covers: every
/// account with a transparent viewing key, whatever its kind.
fn discovery_accounts(db: &WalletDatabase) -> Result<Vec<AccountUuid>, SyncError> {
    let mut accounts = Vec::new();
    for id in db
        .get_account_ids()
        .map_err(|e| SyncError::db(e.to_string()))?
    {
        let account = db
            .get_account(id)
            .map_err(|e| SyncError::db(e.to_string()))?
            .ok_or_else(|| SyncError::db("account disappeared during address discovery"))?;
        if account.ufvk().and_then(|k| k.transparent()).is_some() {
            accounts.push(id);
        } else if keys::hardware_signer_kind(account.source()) == Some(HardwareSignerKind::Ledger) {
            // A Ledger account is imported with its transparent key; one
            // without it cannot be recovered or shielded.
            return Err(SyncError::other(
                "Ledger account has no transparent viewing key",
            ));
        }
    }
    Ok(accounts)
}

/// Called by sync before its normal UTXO refresh; shares sync's cancellation
/// lifetime and the transparent policy it captured.
pub(super) async fn run(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    policy: EnhancementPolicy,
    tip: BlockHeight,
    should_exit: &impl Fn() -> bool,
) -> Result<(), SyncError> {
    let mut rpc = Lightwalletd {
        client: client.clone(),
        url: lightwalletd_url.to_owned(),
    };
    run_with(&mut rpc, db, db_path, network, policy, tip, should_exit).await
}

async fn run_with<R: DiscoveryRpc>(
    client: &mut R,
    db: &mut WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
    policy: EnhancementPolicy,
    tip: BlockHeight,
    should_exit: &impl Fn() -> bool,
) -> Result<(), SyncError> {
    // Candidate addresses are sent to public lightwalletd; the gate authorizes
    // each history request, and every checkpoint that marks candidates checked
    // re-checks it, so nothing is queried or completed without authority.
    let gate = TransparentLookupGate::for_wallet(
        policy.public_transparent_lookups(db)?,
        db_path,
        network,
    )?;
    if !gate.is_allowed() {
        log::info!("sync: transparent policy withholds address-history discovery");
        return Ok(());
    }
    let accounts = discovery_accounts(db)?;
    if accounts.is_empty() || should_exit() {
        return Ok(());
    }
    ensure_table(db_path)?;
    for id in accounts {
        if initial_discovery_complete(db_path, id).map_err(SyncError::db)? {
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
                "address discovery: account={} scope={} resume_index={} tip={}",
                id.expose_uuid(),
                scope_code,
                progress.next_index,
                scan_tip
            );
            while progress.unused < gap {
                if should_exit() {
                    return Ok(());
                }
                with_wallet_db_write_lock("address_discovery.addresses", || {
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
                        "Address discovery candidate range is incomplete",
                    ));
                }
                // Only stream headers are acquired concurrently. Bodies are drained and stored
                // incrementally, so heavily reused addresses cannot accumulate unbounded history.
                let opening = stream::iter(candidates)
                    .map(|(index, address)| {
                        let mut client = client.clone();
                        let gate = gate.clone();
                        async move {
                            let stream =
                                client.history(&gate, address, u64::from(scan_tip)).await?;
                            Ok::<_, SyncError>((index, stream))
                        }
                    })
                    .buffered(CONCURRENCY)
                    .try_collect::<Vec<_>>();
                let streams = tokio::select! { biased; _ = watch_for_exit(should_exit) => return Ok(()), result = opening => result? };
                for (index, history) in streams {
                    if index != progress.next_index {
                        return Err(SyncError::db("Address discovery candidate index skipped"));
                    }
                    let Some(mut history) = history else {
                        log::info!(
                            "sync: transparent policy withholds remaining address discovery"
                        );
                        return Ok(());
                    };
                    let Some(used) = store_history(
                        &mut history,
                        db,
                        network,
                        scan_tip,
                        &format!(
                            "account={} scope={scope_code} index={index}",
                            id.expose_uuid()
                        ),
                        should_exit,
                    )
                    .await?
                    else {
                        return Ok(());
                    };
                    if should_exit() {
                        return Ok(());
                    }
                    // Answers already received are stored, but progress is not
                    // checkpointed after a transition, so a later pass under the
                    // new policy re-covers these indices.
                    progress.advance(used)?;
                    if !commit(
                        db, &gate, id, scope_code, progress, scan_tip, &hash.0, false,
                    )? {
                        return Ok(());
                    }
                    log::info!(
                        "address discovery: account={} scope={} index={} used={} gap={}/{} elapsed_ms={}",
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
                return Err(SyncError::other(
                    "Address discovery chain changed; retrying",
                ));
            }
            if should_exit() {
                return Ok(());
            }
            // The last batch may have been answered after a transition; a
            // scope completed under stale authority would never be retried.
            if !commit(db, &gate, id, scope_code, progress, scan_tip, &hash.0, true)? {
                return Ok(());
            }
            log::info!(
                "address discovery: account={} scope={} complete addresses={} elapsed_ms={}",
                id.expose_uuid(),
                scope_code,
                progress.next_index,
                started.elapsed().as_millis()
            );
        }
        // Publish account completion only after both scopes agree with the
        // chain. Scope-complete (1) is resumable; account-complete (2) is what
        // coverage reads.
        for scope in 0..2 {
            let (_, height, hash, complete) = load(db_path, id, scope)?
                .ok_or_else(|| SyncError::db("Address discovery checkpoint missing"))?;
            if !complete {
                return Err(SyncError::db("Address discovery scope incomplete"));
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
                    "Address discovery scope chain changed; retrying",
                ));
            }
        }
        if should_exit() {
            return Ok(());
        }
        let ready = commit_extension(db, &gate, "address_discovery.complete", |ext| {
            ext.execute(
                &format!("UPDATE {TABLE} SET complete=2 WHERE account_uuid=?1 AND complete=1"),
                [id.expose_uuid().as_bytes().as_slice()],
            )
        })?;
        if !ready {
            return Ok(());
        }
    }
    Ok(())
}

/// Called by sync once the chain scan and its enhancement have stored what
/// they found, under the transparent policy the sync captured. Checks every
/// restored ephemeral output's address once, and returns whether any
/// transaction was stored.
pub(super) async fn run_restored_ephemeral(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    policy: EnhancementPolicy,
    tip: BlockHeight,
    should_exit: &impl Fn() -> bool,
) -> Result<bool, SyncError> {
    let mut rpc = Lightwalletd {
        client: client.clone(),
        url: lightwalletd_url.to_owned(),
    };
    restored_ephemeral_with(&mut rpc, db, db_path, network, policy, tip, should_exit).await
}

async fn restored_ephemeral_with<R: DiscoveryRpc>(
    client: &mut R,
    db: &mut WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
    policy: EnhancementPolicy,
    tip: BlockHeight,
    should_exit: &impl Fn() -> bool,
) -> Result<bool, SyncError> {
    // Each address is sent to public lightwalletd, so the gate authorizes
    // every query and the write that records it checked.
    let gate = TransparentLookupGate::for_wallet(
        policy.public_transparent_lookups(db)?,
        db_path,
        network,
    )?;
    if !gate.is_allowed() {
        return Ok(false);
    }
    let mut stored = false;
    for address in restored_ephemeral_addresses(db_path)? {
        if should_exit() {
            return Ok(stored);
        }
        let checked = TransparentAddress::decode(&network, &address)
            .map_err(|e| SyncError::parse(format!("restored ephemeral address: {e}")))?;
        let query = super::transparent_address_for_query(
            &address,
            network,
            super::transparent_utxo_query_network(network),
        )
        .map_err(SyncError::parse)?;
        let opening = client.isolated_history(&gate, query, u64::from(u32::from(tip)));
        let history = tokio::select! { biased; _ = watch_for_exit(should_exit) => return Ok(stored), r = opening => r? };
        let Some(mut history) = history else {
            log::info!("sync: transparent policy withholds restored ephemeral discovery");
            return Ok(stored);
        };
        let Some(used) = store_history(
            &mut history,
            db,
            network,
            u32::from(tip),
            "restored ephemeral address",
            should_exit,
        )
        .await?
        else {
            return Ok(stored);
        };
        stored |= used;
        if should_exit() {
            return Ok(stored);
        }
        // Record the address as checked through `tip`, under the policy that
        // authorized the query. A transition withholds the record, so the
        // address is checked again under the new policy.
        let TransactionDataRequest::TransactionsInvolvingAddress(request) =
            TransactionDataRequest::transactions_involving_address(
                checked,
                BlockHeight::from_u32(0),
                Some(tip + 1),
                None,
                TransactionStatusFilter::Mined,
                OutputStatusFilter::All,
            );
        let recorded = with_wallet_db_write_lock("address_discovery.ephemeral_checked", || {
            db.transactionally(|tx| {
                if !gate.permits_applied(tx.applied_transparent_policy()?) {
                    return Ok(false);
                }
                tx.notify_address_checked(request, tip)?;
                Ok::<_, SqliteClientError>(true)
            })
        })
        .map_err(|e| SyncError::db(format!("restored ephemeral address checked: {e}")))?;
        if !recorded {
            return Ok(stored);
        }
    }
    Ok(stored)
}

/// Addresses of every restored ephemeral output (see
/// [`RESTORED_EPHEMERAL_OUTPUTS`]), each once.
fn restored_ephemeral_addresses(db_path: &str) -> Result<Vec<String>, SyncError> {
    let conn = open_readonly_conn_with_timeout(db_path, Some(SYNC_DB_BUSY_TIMEOUT))
        .map_err(SyncError::db)?;
    let mut stmt = conn
        .prepare(&format!(
            "SELECT DISTINCT a.cached_transparent_receiver_address {RESTORED_EPHEMERAL_OUTPUTS}
               AND a.cached_transparent_receiver_address IS NOT NULL
             ORDER BY a.cached_transparent_receiver_address"
        ))
        .map_err(|e| SyncError::db(e.to_string()))?;
    let rows = stmt
        .query_map([], |r| r.get::<_, String>(0))
        .map_err(|e| SyncError::db(e.to_string()))?;
    rows.collect::<Result<_, _>>()
        .map_err(|e| SyncError::db(e.to_string()))
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

/// Stores each mined transaction of `history` as it arrives. Returns whether
/// the address has any history, or `None` on exit.
async fn store_history(
    history: &mut History,
    db: &mut WalletDatabase,
    network: WalletNetwork,
    tip: u32,
    context: &str,
    should_exit: &impl Fn() -> bool,
) -> Result<Option<bool>, SyncError> {
    let started = std::time::Instant::now();
    let mut transactions = 0usize;
    let mut response_bytes = 0usize;
    loop {
        let raw = tokio::select! { biased; _ = watch_for_exit(should_exit) => return Ok(None), r = history.next() => r.transpose()? };
        let Some(raw) = raw else {
            log::info!(
                "address discovery history: {context} rpc_count=1 transactions={} response_bytes={} elapsed_ms={}",
                transactions,
                response_bytes,
                started.elapsed().as_millis()
            );
            return Ok(Some(transactions > 0));
        };
        response_bytes += prost::Message::encoded_len(&raw);
        let height = u32::try_from(raw.height)
            .ok()
            .filter(|h| *h > 0 && *h <= tip)
            .ok_or_else(|| SyncError::parse("Address history returned an invalid mined height"))?;
        let tx = Transaction::read(
            &raw.data[..],
            BranchId::for_height(&network, BlockHeight::from_u32(height)),
        )
        .map_err(|e| SyncError::parse(format!("Address history transaction: {e}")))?;
        if should_exit() {
            return Ok(None);
        }
        with_wallet_db_write_lock("address_discovery.transaction", || {
            decrypt_and_store_transaction(&network, db, &tx, Some(BlockHeight::from_u32(height)))
        })
        .map_err(|e| SyncError::db(format!("Address history store: {e}")))?;
        transactions += 1;
    }
}

/// Whether an account's public transparent history is complete, and if not,
/// what is still missing. Read only where the account's transparent authority
/// is public; a private ledger reports its own completeness.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Coverage {
    Complete,
    /// Initial discovery of the account's derived addresses has not finished.
    InitialDiscovery,
    /// A restored ephemeral output's address has not been checked yet.
    RestoredEphemeral,
    /// A spend search for one of the account's outputs is due at or below
    /// the tip.
    SpendSearch,
}

/// Reads [`Coverage`] from one database snapshot. The library's due spend
/// searches are read once, for every account.
pub(crate) struct CoverageRead {
    /// Addresses with a spend search due at or below the tip.
    due_spend_searches: Vec<String>,
}

impl CoverageRead {
    pub(crate) fn new<W>(wdb: &W, network: WalletNetwork) -> Result<Self, SqliteClientError>
    where
        W: WalletRead<Error = SqliteClientError>,
    {
        let requests = wdb.transaction_data_requests()?;
        let due_spend_searches = super::address_history::plan(&requests)
            .iter()
            .filter_map(|group| group.front())
            .map(|request| encode_transparent_address_p(&network, &request.address()))
            .collect();
        Ok(Self { due_spend_searches })
    }

    pub(crate) fn account<W>(
        &self,
        wdb: &W,
        ext: &ExtensionTransaction<'_>,
        account: AccountUuid,
    ) -> Result<Coverage, SqliteClientError>
    where
        W: WalletRead<AccountId = AccountUuid, Error = SqliteClientError>,
    {
        let uuid = account.expose_uuid().as_bytes().to_vec();
        let has_transparent = wdb
            .get_account(account)?
            .is_some_and(|a| a.ufvk().and_then(|k| k.transparent()).is_some());
        if has_transparent {
            let table: bool = ext.query_row(
                "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name=?1)",
                [TABLE],
                |r| r.get(0),
            )?;
            let complete =
                table && ext.query_row(&initial_discovery_complete_sql(), [&uuid], |r| r.get(0))?;
            if !complete {
                return Ok(Coverage::InitialDiscovery);
            }
        }
        let restored: bool = ext.query_row(
            &format!("SELECT EXISTS(SELECT 1 {RESTORED_EPHEMERAL_OUTPUTS} AND acct.uuid = ?1)"),
            [&uuid],
            |r| r.get(0),
        )?;
        if restored {
            return Ok(Coverage::RestoredEphemeral);
        }
        if !self.due_spend_searches.is_empty() {
            let placeholders = vec!["?"; self.due_spend_searches.len()].join(",");
            let due: bool = ext.query_row(
                &format!(
                    "SELECT EXISTS(SELECT 1 FROM addresses a
                     JOIN accounts acct ON acct.id = a.account_id
                     WHERE acct.uuid = ?1
                       AND a.cached_transparent_receiver_address IN ({placeholders}))"
                ),
                params_from_iter(
                    std::iter::once(rusqlite::types::Value::Blob(uuid.clone())).chain(
                        self.due_spend_searches
                            .iter()
                            .cloned()
                            .map(rusqlite::types::Value::Text),
                    ),
                ),
                |r| r.get(0),
            )?;
            if due {
                return Ok(Coverage::SpendSearch);
            }
        }
        Ok(Coverage::Complete)
    }
}

/// Whether public discovery can govern any account of `wdb`'s wallet: the
/// handle retains public transparent authority. A handle adopts a durable
/// `PrivateRequired`, and one opened before that transition can no longer
/// read the wallet; either way the lookup gate withholds public discovery,
/// private recovery owns completeness, and waiting for discovery would block
/// every sync.
fn retains_public_authority<W>(wdb: &W) -> Result<bool, SqliteClientError>
where
    W: TransparentLedgerRead<Error = SqliteClientError>,
{
    match wdb.transparent_ledger_mode() {
        Ok(mode) => Ok(mode.retains_public_authority()),
        Err(SqliteClientError::TransparentLedgerPolicyConflict { .. }) => Ok(false),
        Err(e) => Err(e),
    }
}

/// `account`'s coverage, or `None` when its transparent authority is not
/// public, so that public discovery does not govern it.
pub(crate) fn account_coverage(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    account: AccountUuid,
) -> Result<Option<Coverage>, String> {
    db.transactionally_with_extension(|wdb, ext| {
        if !retains_public_authority(&*wdb)? {
            return Ok(None);
        }
        let snapshot =
            wdb.transparent_ledger_snapshot(account, crate::wallet::confirmations_policy())?;
        if snapshot.authority != TransparentAuthority::Public {
            return Ok(None);
        }
        CoverageRead::new(wdb, network)?
            .account(wdb, ext, account)
            .map(Some)
    })
    .map_err(|e: SqliteClientError| format!("Failed to read transparent history coverage: {e}"))
}

/// The first account whose public transparent history is incomplete, if any.
pub(crate) fn first_incomplete(
    db: &mut WalletDatabase,
    network: WalletNetwork,
) -> Result<Option<(AccountUuid, Coverage)>, String> {
    db.transactionally_with_extension(|wdb, ext| {
        if !retains_public_authority(&*wdb)? {
            return Ok(None);
        }
        let read = CoverageRead::new(wdb, network)?;
        for account in wdb.get_account_ids()? {
            let snapshot =
                wdb.transparent_ledger_snapshot(account, crate::wallet::confirmations_policy())?;
            if snapshot.authority != TransparentAuthority::Public {
                continue;
            }
            let coverage = read.account(wdb, ext, account)?;
            if coverage != Coverage::Complete {
                return Ok(Some((account, coverage)));
            }
        }
        Ok(None)
    })
    .map_err(|e: SqliteClientError| format!("Failed to read transparent history coverage: {e}"))
}

/// Whether public discovery permits spending `account`'s transparent funds:
/// its history is complete, or its authority is not public.
pub(crate) fn permits_transparent_spend(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    account: AccountUuid,
) -> Result<bool, String> {
    Ok(account_coverage(db, network, account)?.is_none_or(|c| c == Coverage::Complete))
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
        /// Goes through the real gate, so a query is recorded only when sent.
        async fn history(
            &mut self,
            gate: &TransparentLookupGate,
            address: String,
            tip: u64,
        ) -> Result<Option<History>, SyncError> {
            self.answer(gate, address, false, tip).await
        }
        /// Recorded with an `isolated:` prefix, so tests see which channel
        /// each address used.
        async fn isolated_history(
            &mut self,
            gate: &TransparentLookupGate,
            address: String,
            tip: u64,
        ) -> Result<Option<History>, SyncError> {
            self.answer(gate, address, true, tip).await
        }
    }
    impl FakeRpc {
        async fn answer(
            &self,
            gate: &TransparentLookupGate,
            address: String,
            isolated: bool,
            _: u64,
        ) -> Result<Option<History>, SyncError> {
            gate.dispatch(async {
                self.queries.lock().unwrap().push(if isolated {
                    format!("isolated:{address}")
                } else {
                    address.clone()
                });
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
                Box::pin(stream::iter(items)) as History
            })
            .await
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
        assert!(!initial_discovery_complete(&path, id).unwrap());
        run_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            EnhancementPolicy::current(WalletNetwork::Main),
            BlockHeight::from_u32(2_600_000),
            &|| false,
        )
        .await
        .unwrap();
        assert!(initial_discovery_complete(&path, id).unwrap());
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
            EnhancementPolicy::current(WalletNetwork::Main),
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
            EnhancementPolicy::current(WalletNetwork::Main),
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
        assert!(!initial_discovery_complete(&path, id).unwrap());
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
            EnhancementPolicy::current(WalletNetwork::Main),
            BlockHeight::from_u32(2_600_010),
            &|| false,
        )
        .await
        .unwrap();
        assert_eq!(rpc.queries.lock().unwrap().len(), 12);
        assert!(initial_discovery_complete(&path, id).unwrap());
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
            EnhancementPolicy::current(WalletNetwork::Main),
            BlockHeight::from_u32(2_600_000),
            &|| true,
        )
        .await
        .unwrap();
        assert!(!initial_discovery_complete(&path, id).unwrap());
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
            EnhancementPolicy::current(WalletNetwork::Main),
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
            EnhancementPolicy::current(WalletNetwork::Main),
            BlockHeight::from_u32(2_600_001),
            &|| false,
        )
        .await
        .unwrap();
        assert_eq!(rpc.queries.lock().unwrap().len(), 15);
        assert!(initial_discovery_complete(&path, id).unwrap());
        // Invalidation precedes the truncate, including when the wallet cannot rewind.
        let _ = truncate(&path, &mut db, BlockHeight::from_u32(2_599_999));
        assert!(!initial_discovery_complete(&path, id).unwrap());
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
            EnhancementPolicy::current(WalletNetwork::Main),
            BlockHeight::from_u32(2_600_000),
            &|| false
        )
        .await
        .is_err());
        assert!(load(&path, id, 0).unwrap().unwrap().3);
        assert!(!initial_discovery_complete(&path, id).unwrap());
        rpc.hash = 2;
        rpc.fail_address = None;
        rpc.queries.lock().unwrap().clear();
        run_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            EnhancementPolicy::current(WalletNetwork::Main),
            BlockHeight::from_u32(2_600_001),
            &|| false,
        )
        .await
        .unwrap();
        assert_eq!(rpc.queries.lock().unwrap().len(), 15);
        assert!(initial_discovery_complete(&path, id).unwrap());
    }

    #[tokio::test]
    async fn private_transparent_policy_withholds_discovery_without_completing_it() {
        use zcash_client_backend::data_api::transparent_ledger::{
            TransparentLedgerMode, TransparentLedgerWrite,
        };
        let (_dir, path, id, mut db, _) = ledger_fixture();
        crate::wallet::db::open_wallet_db_with_timeout(
            &path,
            WalletNetwork::Main,
            SYNC_DB_BUSY_TIMEOUT,
        )
        .unwrap()
        .apply_transparent_policy(TransparentLedgerMode::PrivateRequired)
        .unwrap();
        let mut rpc = FakeRpc {
            histories: Default::default(),
            queries: Default::default(),
            fail_address: None,
            hash: 1,
        };
        let tip = BlockHeight::from_u32(2_600_000);
        // A Public handle opened before the transition cannot read the
        // stricter wallet, so discovery fails closed on it.
        assert!(run_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            EnhancementPolicy::current(WalletNetwork::Main),
            tip,
            &|| { false }
        )
        .await
        .is_err());
        // A handle opened after it adopts the durable policy, so discovery is
        // withheld: it succeeds without a query.
        let mut db = crate::wallet::db::open_wallet_db_with_timeout(
            &path,
            WalletNetwork::Main,
            SYNC_DB_BUSY_TIMEOUT,
        )
        .unwrap();
        run_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            EnhancementPolicy::current(WalletNetwork::Main),
            tip,
            &|| false,
        )
        .await
        .unwrap();

        assert!(rpc.queries.lock().unwrap().is_empty());
        // Withheld discovery records no checkpoint, so it stays owed.
        let conn = open_readonly_conn_with_timeout(&path, Some(SYNC_DB_BUSY_TIMEOUT)).unwrap();
        assert!(
            !table_exists(&conn).unwrap(),
            "withheld scopes stay incomplete"
        );
        // While lookups are withheld, public coverage does not govern the
        // account, so it does not hold back a sync; private recovery owns its
        // authority.
        assert_eq!(coverage_of(&mut db, id), None);
        assert_eq!(
            first_incomplete(&mut db, WalletNetwork::Main).unwrap(),
            None
        );
        // Nor does a handle opened before the transition, which can no longer
        // read the wallet.
        let mut stale = crate::wallet::db::open_wallet_db_with_timeout(
            &path,
            WalletNetwork::Main,
            SYNC_DB_BUSY_TIMEOUT,
        )
        .unwrap();
        stale.set_transparent_ledger_mode(TransparentLedgerMode::Public);
        assert_eq!(
            first_incomplete(&mut stale, WalletNetwork::Main).unwrap(),
            None
        );
        // Once they are public again, its discovery is owed.
        crate::wallet::db::open_wallet_db_with_timeout(
            &path,
            WalletNetwork::Main,
            SYNC_DB_BUSY_TIMEOUT,
        )
        .unwrap()
        .apply_transparent_policy(TransparentLedgerMode::Public)
        .unwrap();
        let mut db = crate::wallet::db::open_wallet_db_with_timeout(
            &path,
            WalletNetwork::Main,
            SYNC_DB_BUSY_TIMEOUT,
        )
        .unwrap();
        assert_eq!(
            first_incomplete(&mut db, WalletNetwork::Main).unwrap(),
            Some((id, Coverage::InitialDiscovery))
        );
    }

    #[tokio::test]
    async fn transition_during_discovery_withholds_every_later_request() {
        use zcash_client_backend::data_api::transparent_ledger::TransparentLedgerMode;
        let (_dir, path, id, mut db, _) = ledger_fixture();
        let mut rpc = FakeRpc {
            histories: Default::default(),
            queries: Default::default(),
            fail_address: None,
            hash: 1,
        };
        // The first request's dispatch lands a transition before the rest of
        // its concurrent batch is polled.
        let _transition = crate::wallet::sync_engine::test_lwd::transition_on_first_dispatch(
            &path,
            WalletNetwork::Main,
            TransparentLedgerMode::PrivateShadow,
        );
        run_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            EnhancementPolicy::current(WalletNetwork::Main),
            BlockHeight::from_u32(2_600_000),
            &|| false,
        )
        .await
        .unwrap();

        assert_eq!(
            rpc.queries.lock().unwrap().len(),
            1,
            "no request is sent after the transition, even within its batch"
        );
        assert_eq!(
            load(&path, id, 0).unwrap().unwrap().0,
            Progress::default(),
            "answers after the transition are not checkpointed"
        );
        assert!(!initial_discovery_complete(&path, id).unwrap());
    }

    // ---- Every account kind, coverage, and restored TEX operations ----

    const TIP: u32 = 2_600_000;
    const BIRTHDAY: u32 = TIP - 10;

    /// Marks the blocks from the birthday through the tip scanned, so the
    /// library authorizes the account's transparent amounts.
    fn mark_scanned(path: &str) {
        let conn = rusqlite::Connection::open(path).unwrap();
        for height in BIRTHDAY..=TIP {
            conn.execute(
                "INSERT OR REPLACE INTO blocks (height, hash, time, sapling_tree,
                     sapling_commitment_tree_size, orchard_commitment_tree_size,
                     ironwood_commitment_tree_size)
                 VALUES (?1, ?2, 0, x'00', 0, 0, 0)",
                rusqlite::params![height, height.to_le_bytes().repeat(8)],
            )
            .unwrap();
        }
        conn.execute_batch(&format!(
            "DELETE FROM scan_queue;
             INSERT INTO scan_queue (block_range_start, block_range_end, priority)
             VALUES ({BIRTHDAY}, {}, 10);",
            TIP + 1
        ))
        .unwrap();
    }

    /// A restored software (mnemonic) account, with nothing discovered yet.
    fn software_fixture() -> (
        tempfile::TempDir,
        String,
        AccountUuid,
        WalletDatabase,
        zcash_keys::keys::UnifiedFullViewingKey,
    ) {
        use secrecy::ExposeSecret;
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
        let seed=keys::mnemonic_to_seed("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about").unwrap();
        let (uuid, _) = keys::init_db_and_create_account(
            &path,
            WalletNetwork::Main,
            &seed,
            Some(u64::from(BIRTHDAY)),
            "restored",
        )
        .unwrap();
        let ufvk = zcash_keys::keys::UnifiedSpendingKey::from_seed(
            &WalletNetwork::Main,
            seed.expose_secret(),
            zip32::AccountId::ZERO,
        )
        .unwrap()
        .to_unified_full_viewing_key();
        let mut db = crate::wallet::db::open_wallet_db_with_timeout(
            &path,
            WalletNetwork::Main,
            SYNC_DB_BUSY_TIMEOUT,
        )
        .unwrap();
        {
            use zcash_client_backend::data_api::WalletWrite;
            db.update_chain_tip(BlockHeight::from_u32(TIP)).unwrap();
        }
        (
            dir,
            path,
            keys::parse_account_uuid(&uuid).unwrap(),
            db,
            ufvk,
        )
    }

    fn external_address(
        ufvk: &zcash_keys::keys::UnifiedFullViewingKey,
        index: u32,
    ) -> transparent::address::TransparentAddress {
        use transparent::keys::{IncomingViewingKey, NonHardenedChildIndex};
        ufvk.transparent()
            .unwrap()
            .derive_external_ivk()
            .unwrap()
            .derive_address(NonHardenedChildIndex::from_index(index).unwrap())
            .unwrap()
    }

    fn rpc(histories: std::collections::HashMap<String, Vec<RawTransaction>>) -> FakeRpc {
        FakeRpc {
            histories: std::sync::Arc::new(histories),
            queries: Default::default(),
            fail_address: None,
            hash: 1,
        }
    }

    fn spends(db: &str) -> i64 {
        rusqlite::Connection::open(db)
            .unwrap()
            .query_row(
                "SELECT COUNT(*) FROM transparent_received_output_spends",
                [],
                |r| r.get(0),
            )
            .unwrap()
    }

    fn coverage_of(db: &mut WalletDatabase, id: AccountUuid) -> Option<Coverage> {
        account_coverage(db, WalletNetwork::Main, id).unwrap()
    }

    fn authority(path: &str, id: AccountUuid) -> crate::wallet::sync::TransparentBalanceAuthority {
        crate::wallet::sync::get_wallet_balance(
            path,
            WalletNetwork::Main,
            &id.expose_uuid().to_string(),
        )
        .unwrap()
        .transparent_authority
    }

    /// V4, gap 6: a restored software account gets the same gap-limit
    /// history scan as a Ledger import. Outputs received and spent before the
    /// restore, which no UTXO stream returns, are found, and a used address
    /// beyond the initial gap extends it.
    #[tokio::test]
    async fn a_restored_software_account_discovers_received_then_spent_history() {
        let (_dir, path, id, mut db, ufvk) = software_fixture();
        let mut histories = std::collections::HashMap::new();
        for (index, seed) in [(0u32, 1u8), (9, 2), (15, 3)] {
            let address = external_address(&ufvk, index);
            let (received, txid) = payment(
                transparent::bundle::OutPoint::new([seed; 32], 0),
                address,
                TIP - 5,
            );
            let (spent, _) = payment(
                transparent::bundle::OutPoint::new(*txid.as_ref(), 0),
                transparent::address::TransparentAddress::PublicKeyHash([99; 20]),
                TIP - 4,
            );
            histories.insert(address.encode(&WalletNetwork::Main), vec![received, spent]);
        }
        let mut rpc = rpc(histories);
        assert!(!initial_discovery_complete(&path, id).unwrap());

        run_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            EnhancementPolicy::current(WalletNetwork::Main),
            BlockHeight::from_u32(TIP),
            &|| false,
        )
        .await
        .unwrap();

        assert!(initial_discovery_complete(&path, id).unwrap());
        assert_eq!(spends(&path), 3, "each received-then-spent output is found");
        let queried = rpc.queries.lock().unwrap().clone();
        assert!(queried.contains(&external_address(&ufvk, 15).encode(&WalletNetwork::Main)));
        assert_eq!(
            load(&path, id, 0).unwrap().unwrap().0,
            Progress {
                next_index: 26,
                unused: 10
            },
            "index 15 is reached through 9, and the gap follows it"
        );
        assert_eq!(coverage_of(&mut db, id), Some(Coverage::Complete));
    }

    /// V5: until discovery and every due spend search are done, a public
    /// account's transparent funds are only last known, shielding waits, and
    /// the wallet does not read as synchronized.
    #[tokio::test]
    async fn coverage_waits_for_discovery_and_due_spend_searches() {
        use crate::wallet::sync::TransparentBalanceAuthority;
        use zcash_client_backend::data_api::WalletWrite;
        let (_dir, path, id, mut db, ufvk) = software_fixture();
        mark_scanned(&path);
        assert_eq!(coverage_of(&mut db, id), Some(Coverage::InitialDiscovery));
        assert_eq!(authority(&path, id), TransparentBalanceAuthority::LastKnown);
        assert_eq!(
            first_incomplete(&mut db, WalletNetwork::Main).unwrap(),
            Some((id, Coverage::InitialDiscovery))
        );
        assert!(!permits_transparent_spend(&mut db, WalletNetwork::Main, id).unwrap());

        // Discovery finds an unspent receive. Its spend search is due until
        // the address is checked through the tip.
        let address = external_address(&ufvk, 0);
        let (received, _) = payment(
            transparent::bundle::OutPoint::new([7; 32], 0),
            address,
            TIP - 5,
        );
        let mut rpc = rpc(std::collections::HashMap::from([(
            address.encode(&WalletNetwork::Main),
            vec![received],
        )]));
        run_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            EnhancementPolicy::current(WalletNetwork::Main),
            BlockHeight::from_u32(TIP),
            &|| false,
        )
        .await
        .unwrap();
        assert_eq!(coverage_of(&mut db, id), Some(Coverage::SpendSearch));
        assert_eq!(authority(&path, id), TransparentBalanceAuthority::LastKnown);
        let balance = crate::wallet::sync::get_wallet_balance(
            &path,
            WalletNetwork::Main,
            &id.expose_uuid().to_string(),
        )
        .unwrap();
        assert_eq!(balance.transparent, 0, "nothing is spendable");
        assert_eq!(balance.transparent_last_known, Some(100_000));

        let TransactionDataRequest::TransactionsInvolvingAddress(request) = db
            .transaction_data_requests()
            .unwrap()
            .into_iter()
            .find(|r| {
                let TransactionDataRequest::TransactionsInvolvingAddress(r) = r;
                r.address() == address && r.block_range_end().is_some()
            })
            .expect("a spend search for the receive");
        let end = request.block_range_end().unwrap();
        db.transactionally(|tx| tx.notify_address_checked(request, end - 1))
            .unwrap();
        assert_eq!(coverage_of(&mut db, id), Some(Coverage::Complete));
        assert_eq!(authority(&path, id), TransparentBalanceAuthority::Current);
        assert_eq!(
            first_incomplete(&mut db, WalletNetwork::Main).unwrap(),
            None
        );
        assert!(permits_transparent_spend(&mut db, WalletNetwork::Main, id).unwrap());
    }

    /// Gap 7 (H13 N_cut): a cut address-history stream fails discovery, and
    /// the account's history stays incomplete rather than reading as current.
    #[tokio::test]
    async fn a_cut_history_stream_fails_discovery_and_leaves_history_incomplete() {
        use crate::wallet::sync::TransparentBalanceAuthority;
        let (_dir, path, id, mut db, ufvk) = software_fixture();
        mark_scanned(&path);
        let mut rpc = rpc(Default::default());
        rpc.fail_address = Some(external_address(&ufvk, 2).encode(&WalletNetwork::Main));

        let result = run_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            EnhancementPolicy::current(WalletNetwork::Main),
            BlockHeight::from_u32(TIP),
            &|| false,
        )
        .await;

        assert!(result.is_err(), "the failure surfaces to sync");
        assert!(!initial_discovery_complete(&path, id).unwrap());
        assert_eq!(
            first_incomplete(&mut db, WalletNetwork::Main).unwrap(),
            Some((id, Coverage::InitialDiscovery))
        );
        assert_eq!(authority(&path, id), TransparentBalanceAuthority::LastKnown);
    }

    /// Stores a ZIP 320 first leg the wallet did not build, as a restore's
    /// scan finds it, paying the account's next ephemeral address.
    fn restored_first_leg(
        db: &mut WalletDatabase,
        id: AccountUuid,
    ) -> (
        transparent::address::TransparentAddress,
        RawTransaction,
        zcash_primitives::transaction::TxId,
    ) {
        use zcash_client_backend::data_api::WalletWrite;
        let (ephemeral, _) = db
            .reserve_next_n_ephemeral_addresses(id, 1)
            .unwrap()
            .remove(0);
        let (leg1, txid) = payment(
            transparent::bundle::OutPoint::new([5; 32], 0),
            ephemeral,
            TIP - 5,
        );
        let tx = Transaction::read(&leg1.data[..], BranchId::Nu5).unwrap();
        decrypt_and_store_transaction(
            &WalletNetwork::Main,
            db,
            &tx,
            Some(BlockHeight::from_u32(TIP - 5)),
        )
        .unwrap();
        (ephemeral, leg1, txid)
    }

    /// TEX leg 2 after a restore: the restored first leg's ephemeral address
    /// is checked once, immediately and over its own channel, so the second
    /// leg is found without waiting for the daily ZIP 320 schedule.
    #[tokio::test]
    async fn a_restored_tex_first_leg_finds_its_second_leg_at_once() {
        let (_dir, path, id, mut db, _) = software_fixture();
        record_initial_discovery_for_test(&path, id, TIP);
        let (ephemeral, leg1, txid) = restored_first_leg(&mut db, id);
        assert_eq!(coverage_of(&mut db, id), Some(Coverage::RestoredEphemeral));

        let (leg2, _) = payment(
            transparent::bundle::OutPoint::new(*txid.as_ref(), 0),
            transparent::address::TransparentAddress::PublicKeyHash([42; 20]),
            TIP - 4,
        );
        let encoded = ephemeral.encode(&WalletNetwork::Main);
        let mut rpc = rpc(std::collections::HashMap::from([(
            encoded.clone(),
            vec![leg1, leg2],
        )]));
        let stored = restored_ephemeral_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            EnhancementPolicy::current(WalletNetwork::Main),
            BlockHeight::from_u32(TIP),
            &|| false,
        )
        .await
        .unwrap();

        assert!(stored);
        assert_eq!(
            *rpc.queries.lock().unwrap(),
            vec![format!("isolated:{encoded}")]
        );
        assert_eq!(
            spends(&path),
            1,
            "the second leg spends the first leg's output"
        );
        assert_eq!(coverage_of(&mut db, id), Some(Coverage::Complete));

        // Once checked, the address is left to the ZIP 320 schedule.
        restored_ephemeral_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            EnhancementPolicy::current(WalletNetwork::Main),
            BlockHeight::from_u32(TIP),
            &|| false,
        )
        .await
        .unwrap();
        assert_eq!(rpc.queries.lock().unwrap().len(), 1);
    }

    /// A restored first leg whose second leg never reached the chain is
    /// checked once too; the unspent output is then recorded as observed
    /// through the tip.
    #[tokio::test]
    async fn a_restored_first_leg_without_a_second_leg_is_checked_once() {
        let (_dir, path, id, mut db, _) = software_fixture();
        record_initial_discovery_for_test(&path, id, TIP);
        let (ephemeral, leg1, _) = restored_first_leg(&mut db, id);
        let mut rpc = rpc(std::collections::HashMap::from([(
            ephemeral.encode(&WalletNetwork::Main),
            vec![leg1],
        )]));
        for _ in 0..2 {
            restored_ephemeral_with(
                &mut rpc,
                &mut db,
                &path,
                WalletNetwork::Main,
                EnhancementPolicy::current(WalletNetwork::Main),
                BlockHeight::from_u32(TIP),
                &|| false,
            )
            .await
            .unwrap();
        }
        assert_eq!(rpc.queries.lock().unwrap().len(), 1);
        assert_eq!(spends(&path), 0);
        assert_eq!(coverage_of(&mut db, id), Some(Coverage::Complete));
    }

    /// A failed restored-ephemeral check fails the pass and leaves the
    /// account incomplete, to be checked again.
    #[tokio::test]
    async fn a_failed_restored_ephemeral_check_is_retried() {
        let (_dir, path, id, mut db, _) = software_fixture();
        record_initial_discovery_for_test(&path, id, TIP);
        let (ephemeral, _, _) = restored_first_leg(&mut db, id);
        let mut rpc = rpc(Default::default());
        rpc.fail_address = Some(ephemeral.encode(&WalletNetwork::Main));
        assert!(restored_ephemeral_with(
            &mut rpc,
            &mut db,
            &path,
            WalletNetwork::Main,
            EnhancementPolicy::current(WalletNetwork::Main),
            BlockHeight::from_u32(TIP),
            &|| false,
        )
        .await
        .is_err());
        assert_eq!(coverage_of(&mut db, id), Some(Coverage::RestoredEphemeral));
    }
}
