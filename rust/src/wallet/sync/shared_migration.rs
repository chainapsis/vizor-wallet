//! Vizor integration for the upstream Orchard-to-Ironwood migration engine.

mod adapter;
mod cache;
mod finalize;

use std::{
    collections::{BTreeSet, HashMap},
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        Mutex, OnceLock,
    },
};

use rand::{rngs::OsRng, seq::SliceRandom, RngCore};
use secrecy::{ExposeSecret, SecretVec};
use zcash_client_backend::data_api::{Account, WalletRead};
use zcash_client_sqlite::AccountUuid;
use zcash_keys::keys::UnifiedSpendingKey;
use zcash_pool_migration_backend::{
    engine::{
        self, MigrationPlan, MigrationState, MigrationStatus as EngineStatus, MigrationTransaction,
        MigrationTxId, MigrationTxKind, MigrationTxState, PoolMigrationRead, PoolMigrationWrite,
    },
    note_splitting::MIGRATION_MAX_PREPARED_NOTES_PER_RUN,
    scheduling,
    wallet::WalletMigrationProver,
};
use zcash_protocol::{consensus::BlockHeight, TxId};

use crate::wallet::{keys::parse_account_uuid, network::WalletNetwork};

use super::{
    migration::{
        MigrationOutboxBatch, MigrationOutboxItem, MigrationPartState, MigrationPartStatus,
        MigrationStatus, ScheduledMigrationBroadcast,
    },
    open_wallet_db, open_wallet_db_for_read,
    send::{
        ActiveIronwoodMigration, IronwoodMigrationResult, KeystoneMigrationMessage,
        KeystoneMigrationProofStatus, KeystoneMigrationSigningRequest,
        KeystoneSignedMigrationMessage, OrchardMigrationPrivatePlan,
    },
    MigrationScheduleEntry, WalletDatabase,
};
use adapter::Backend;

struct CallContext {
    network: WalletNetwork,
    wallet: WalletDatabase,
    store_conn: rusqlite::Connection,
    db_path: PathBuf,
    account: AccountUuid,
}

#[derive(Clone, Copy)]
enum SigningSubset {
    Preparations,
    Transfers,
    All,
}

enum DrivePurpose<'a> {
    Broadcast { max_broadcasts: Option<usize> },
    Preparation { cancel: &'a AtomicBool },
    Outbox,
}

impl DrivePurpose<'_> {
    fn is_cancelled(&self) -> bool {
        matches!(self, Self::Preparation { cancel } if cancel.load(Ordering::Relaxed))
    }

    fn may_prove(&self, kind: MigrationTxKind) -> bool {
        match self {
            Self::Preparation { .. } => matches!(kind, MigrationTxKind::Preparation { .. }),
            Self::Broadcast { .. } | Self::Outbox => true,
        }
    }

    fn may_broadcast(&self, kind: MigrationTxKind) -> bool {
        match self {
            Self::Broadcast { .. } => true,
            Self::Preparation { .. } | Self::Outbox => {
                matches!(kind, MigrationTxKind::Preparation { .. })
            }
        }
    }

    fn broadcast_limit_reached(&self, count: usize) -> bool {
        matches!(
            self,
            Self::Broadcast {
                max_broadcasts: Some(limit)
            } if count >= *limit
        )
    }
}

#[derive(Clone)]
struct SigningRequest {
    db_path: String,
    network: WalletNetwork,
    account_uuid: String,
    ids: Vec<MigrationTxId>,
    expected_schedule: Option<Vec<MigrationScheduleEntry>>,
}

fn signing_requests() -> &'static Mutex<HashMap<String, SigningRequest>> {
    static REQUESTS: OnceLock<Mutex<HashMap<String, SigningRequest>>> = OnceLock::new();
    REQUESTS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn new_request_id(label: &str) -> String {
    format!("shared-{label}-{:016x}", OsRng.next_u64())
}

fn open_context(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<CallContext, String> {
    Ok(CallContext {
        network,
        wallet: open_wallet_db(db_path, network)?,
        store_conn: rusqlite::Connection::open(db_path)
            .map_err(|e| format!("Open migration store: {e}"))?,
        db_path: PathBuf::from(db_path),
        account: parse_account_uuid(account_uuid)?,
    })
}

impl CallContext {
    fn tip(&self) -> Result<BlockHeight, String> {
        self.wallet
            .chain_height()
            .map_err(|e| format!("Read migration chain tip: {e}"))?
            .ok_or_else(|| "The wallet has no chain tip yet. Sync first.".to_string())
    }
}

fn account_bytes(account: AccountUuid) -> [u8; 16] {
    *account.expose_uuid().as_bytes()
}

const RUN_IDS_TABLE: &str = "vizor_shared_migration_run_ids";

fn ensure_run_ids_schema(conn: &rusqlite::Connection) -> Result<(), String> {
    conn.execute_batch(&format!(
        "CREATE TABLE IF NOT EXISTS {RUN_IDS_TABLE} (
            account_uuid BLOB PRIMARY KEY NOT NULL,
            run_id TEXT NOT NULL,
            approved_schedule_json TEXT
        );"
    ))
    .map_err(|e| format!("Create shared migration run identity store: {e}"))
}

fn new_shared_run_id() -> String {
    let mut bytes = [0u8; 16];
    OsRng.fill_bytes(&mut bytes);
    format!("shared-{}", hex::encode(bytes))
}

fn shared_run_id(conn: &rusqlite::Connection, account: AccountUuid) -> Result<String, String> {
    use rusqlite::OptionalExtension;

    ensure_run_ids_schema(conn)?;
    let account = account_bytes(account);
    if let Some(run_id) = conn
        .query_row(
            &format!("SELECT run_id FROM {RUN_IDS_TABLE} WHERE account_uuid = ?1"),
            rusqlite::params![account.as_slice()],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| format!("Read shared migration run identity: {e}"))?
    {
        return Ok(run_id);
    }
    let run_id = new_shared_run_id();
    conn.execute(
        &format!("INSERT INTO {RUN_IDS_TABLE} (account_uuid, run_id) VALUES (?1, ?2)"),
        rusqlite::params![account.as_slice(), &run_id],
    )
    .map_err(|e| format!("Store shared migration run identity: {e}"))?;
    Ok(run_id)
}

fn replace_shared_run_id(
    conn: &rusqlite::Connection,
    account: AccountUuid,
    approved_schedule: &[MigrationScheduleEntry],
) -> Result<String, String> {
    ensure_run_ids_schema(conn)?;
    let run_id = new_shared_run_id();
    let account = account_bytes(account);
    let approved_schedule_json = serde_json::to_string(approved_schedule)
        .map_err(|e| format!("Encode shared migration consent schedule: {e}"))?;
    conn.execute(
        &format!(
            "INSERT INTO {RUN_IDS_TABLE} (account_uuid, run_id, approved_schedule_json)
             VALUES (?1, ?2, ?3)
             ON CONFLICT(account_uuid) DO UPDATE SET
                run_id = excluded.run_id,
                approved_schedule_json = excluded.approved_schedule_json"
        ),
        rusqlite::params![account.as_slice(), &run_id, approved_schedule_json],
    )
    .map_err(|e| format!("Replace shared migration run identity: {e}"))?;
    Ok(run_id)
}

fn shared_approved_schedule(
    conn: &rusqlite::Connection,
    account: AccountUuid,
) -> Result<Option<Vec<MigrationScheduleEntry>>, String> {
    use rusqlite::OptionalExtension;

    ensure_run_ids_schema(conn)?;
    let account = account_bytes(account);
    conn.query_row(
        &format!("SELECT approved_schedule_json FROM {RUN_IDS_TABLE} WHERE account_uuid = ?1"),
        rusqlite::params![account.as_slice()],
        |row| row.get::<_, Option<String>>(0),
    )
    .optional()
    .map_err(|e| format!("Read shared migration consent schedule: {e}"))?
    .flatten()
    .map(|json| {
        serde_json::from_str(&json)
            .map_err(|e| format!("Decode shared migration consent schedule: {e}"))
    })
    .transpose()
}

fn map_plan(plan: &MigrationPlan, tip: BlockHeight) -> Result<OrchardMigrationPrivatePlan, String> {
    let split = plan.note_split();
    let funding_notes = plan.funding_notes();
    if funding_notes.len() != plan.schedule().len() {
        return Err(format!(
            "Migration plan has {} funding notes but {} schedule entries",
            funding_notes.len(),
            plan.schedule().len()
        ));
    }
    let target_values_zatoshi = funding_notes
        .iter()
        .copied()
        .enumerate()
        .map(|(index, funding_note)| {
            (funding_note - split.note_fee_buffer())
                .map(u64::from)
                .ok_or_else(|| {
                    format!(
                        "Migration funding note {index} is smaller than its transfer fee buffer"
                    )
                })
        })
        .collect::<Result<Vec<_>, String>>()?;
    let planned_batch_count = u32::try_from(target_values_zatoshi.len())
        .map_err(|_| "Migration batch count exceeds u32".to_string())?;
    let denomination_split_stage_count = u32::try_from(plan.preparation().transaction_count())
        .map_err(|_| "Migration preparation count exceeds u32".to_string())?;
    let migration_fee_zatoshi = u64::from(split.note_fee_buffer())
        .checked_mul(u64::from(planned_batch_count))
        .ok_or("Migration fee estimate overflow")?;
    let estimated_total_fee_zatoshi = u64::from(split.prep_fees())
        .checked_add(migration_fee_zatoshi)
        .ok_or("Migration total fee estimate overflow")?;

    let scheduled_transfers = plan
        .schedule()
        .iter()
        .enumerate()
        .map(|(index, schedule)| {
            Ok(MigrationScheduleEntry {
                part_index: Some(
                    u32::try_from(index)
                        .map_err(|_| "Migration part index exceeds u32".to_string())?,
                ),
                value_zatoshi: *target_values_zatoshi
                    .get(index)
                    .ok_or("Migration schedule has no matching funding note")?,
                block_offset: u32::from(schedule.broadcast_height()).saturating_sub(u32::from(tip)),
            })
        })
        .collect::<Result<Vec<_>, String>>()?;

    let last_preparation_height = plan.prep_schedule().iter().flatten().copied().max();
    let first_transfer_height = plan
        .schedule()
        .iter()
        .map(|schedule| schedule.broadcast_height())
        .min();
    let proof_readiness_delay_blocks = match (last_preparation_height, first_transfer_height) {
        (Some(preparation), Some(transfer)) => {
            u32::from(transfer).saturating_sub(u32::from(preparation))
        }
        _ => 0,
    };

    Ok(OrchardMigrationPrivatePlan {
        target_values_zatoshi,
        total_input_zatoshi: u64::from(split.total_input()),
        total_migratable_zatoshi: u64::from(split.total_migratable()),
        orchard_change_zatoshi: split.change().map(u64::from),
        denomination_split_fee_zatoshi: u64::from(split.prep_fees()),
        migration_fee_zatoshi,
        estimated_total_fee_zatoshi,
        planned_batch_count,
        denomination_split_stage_count,
        signing_batch_limit: crate::wallet::keystone::ZCASH_SIGN_BATCH_MAX_MESSAGES as u32,
        schedule_mean_delay_blocks: scheduling::MEAN_DELAY,
        schedule_max_delay_blocks: scheduling::MAX_DELAY,
        proof_readiness_delay_blocks,
        max_prepared_notes_per_run: MIGRATION_MAX_PREPARED_NOTES_PER_RUN as u32,
        scheduled_transfers,
    })
}

pub(crate) fn get_private_plan(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<Option<OrchardMigrationPrivatePlan>, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let wallet = open_wallet_db_for_read(db_path, network)?;
    let account = parse_account_uuid(account_uuid)?;
    let mut store_conn =
        rusqlite::Connection::open(db_path).map_err(|e| format!("Open migration store: {e}"))?;
    let backend = Backend::new(&wallet, account, None, &mut store_conn)
        .map_err(|e| format!("Open shared migration backend: {e}"))?;
    if backend
        .get_migration()
        .map_err(|e| format!("Read shared migration: {e}"))?
        .is_some_and(|state| !state.is_terminal())
    {
        return Err("An Orchard migration is already in progress".to_string());
    }
    let tip = engine::MigrationBackend::chain_tip_height(&backend)
        .map_err(|e| format!("Read migration chain tip: {e}"))?;
    let mut rng = OsRng;
    match engine::plan_migration(&network, &backend, &mut rng) {
        Ok(plan) => {
            let mapped = map_plan(&plan, tip)?;
            cache::set(PathBuf::from(db_path), account_bytes(account), plan, tip);
            Ok(Some(mapped))
        }
        Err(engine::MigrationError::NothingToMigrate) => Ok(None),
        Err(error) => Err(format!("Plan Orchard migration: {error}")),
    }
}

fn validate_approved_schedule(
    cached: &cache::CachedPlan,
    approved_schedule: &[MigrationScheduleEntry],
) -> Result<(), String> {
    let mut expected = map_plan(&cached.plan, cached.tip)?.scheduled_transfers;
    let mut approved = approved_schedule.to_vec();
    expected.sort_by_key(|entry| entry.part_index);
    approved.sort_by_key(|entry| entry.part_index);
    if expected != approved {
        return Err(
            "Migration plan changed. Review the refreshed amounts and schedule.".to_string(),
        );
    }
    Ok(())
}

fn derive_usk(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    seed: SecretVec<u8>,
) -> Result<UnifiedSpendingKey, String> {
    let wallet = open_wallet_db_for_read(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    let account = wallet
        .get_account(account_id)
        .map_err(|e| format!("Read migration account: {e}"))?
        .ok_or("Account not found")?;
    let account_index = account
        .source()
        .key_derivation()
        .ok_or("Migration account has no key derivation")?
        .account_index();
    let usk = UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), account_index)
        .map_err(|e| format!("Derive migration spending key: {e:?}"))?;
    let derived_account = wallet
        .get_account_for_ufvk(&usk.to_unified_full_viewing_key())
        .map_err(|e| format!("Match migration spending key: {e}"))?
        .ok_or("Spending key not recognized")?;
    if derived_account.id() != account_id {
        return Err("Spending key does not match migration account".to_string());
    }
    Ok(usk)
}

fn commit_or_resume(
    context: &mut CallContext,
    usk: Option<UnifiedSpendingKey>,
    external_signer: bool,
    approved_schedule: Option<&[MigrationScheduleEntry]>,
) -> Result<(MigrationState, Vec<(MigrationTxId, Vec<u8>)>), String> {
    {
        let backend = Backend::new(
            &context.wallet,
            context.account,
            None,
            &mut context.store_conn,
        )
        .map_err(|e| format!("Open shared migration backend: {e}"))?;
        if let Some(state) = backend
            .get_migration()
            .map_err(|e| format!("Read shared migration: {e}"))?
        {
            if !state.is_terminal() {
                let unsigned = state
                    .transactions()
                    .iter()
                    .filter(|transaction| {
                        matches!(transaction.state(), MigrationTxState::AwaitingSignature)
                    })
                    .map(|transaction| (transaction.id(), transaction.pczt().clone()))
                    .collect();
                return Ok((state, unsigned));
            }
        }
    }

    let cached = cache::get(&context.db_path, account_bytes(context.account))
        .ok_or("Migration plan is stale. Review a new migration plan.")?;
    if let Some(approved_schedule) = approved_schedule {
        validate_approved_schedule(&cached, approved_schedule)?;
    }
    let stored_approved_schedule = map_plan(&cached.plan, cached.tip)?.scheduled_transfers;
    let target_height = context.tip()? + 1;
    replace_shared_run_id(
        &context.store_conn,
        context.account,
        &stored_approved_schedule,
    )?;
    let mut backend = Backend::new(
        &context.wallet,
        context.account,
        usk,
        &mut context.store_conn,
    )
    .map_err(|e| format!("Open shared migration backend: {e}"))?;
    let mut rng = OsRng;
    let (state, unsigned) = if external_signer {
        let (state, unsigned) = engine::build_preparation_unsigned(
            &context.network,
            target_height,
            &mut backend,
            &cached.plan,
            &mut rng,
        )
        .map_err(|e| format!("Commit shared migration for external signing: {e}"))?;
        (
            state,
            unsigned
                .into_iter()
                .map(|transaction| transaction.into_parts())
                .collect(),
        )
    } else {
        let state = engine::commit_preparation(
            &context.network,
            target_height,
            &mut backend,
            &cached.plan,
            &mut rng,
        )
        .map_err(|e| format!("Commit shared migration: {e}"))?;
        (state, Vec::new())
    };
    drop(backend);
    cache::clear(&context.db_path, account_bytes(context.account));
    Ok((state, unsigned))
}

fn reconcile_mined(context: &mut CallContext) -> Result<Option<MigrationState>, String> {
    let mut backend = Backend::new(
        &context.wallet,
        context.account,
        None,
        &mut context.store_conn,
    )
    .map_err(|e| format!("Open shared migration backend: {e}"))?;
    let Some(mut state) = backend
        .get_migration()
        .map_err(|e| format!("Read shared migration: {e}"))?
    else {
        return Ok(None);
    };
    if state.is_terminal() {
        return Ok(Some(state));
    }
    let broadcasts = state
        .transactions()
        .iter()
        .filter_map(|transaction| {
            transaction
                .state()
                .broadcast_txid()
                .map(|txid| (transaction.id(), txid))
        })
        .collect::<Vec<_>>();
    let mut changed = false;
    for (id, txid) in broadcasts {
        if let Some(height) = context
            .wallet
            .get_tx_height(TxId::from_bytes(txid))
            .map_err(|e| format!("Read migration transaction height: {e}"))?
        {
            state.mark_mined(id, height);
            changed = true;
        }
    }
    if changed {
        backend
            .replace_migration(&state)
            .map_err(|e| format!("Persist mined migration state: {e}"))?;
    }
    Ok(Some(state))
}

fn prove_one(
    context: &mut CallContext,
    state: &mut MigrationState,
    id: MigrationTxId,
) -> Result<bool, String> {
    let kind = state
        .transactions()
        .iter()
        .find(|transaction| transaction.id() == id)
        .map(|transaction| transaction.kind())
        .ok_or_else(|| format!("Unknown migration transaction {}", u32::from(id)))?;
    let natural_anchor = match kind {
        MigrationTxKind::Preparation { .. } => Some(
            finalize::natural_anchor_height(&context.wallet)
                .map_err(|e| format!("Read migration proof anchor: {e}"))?,
        ),
        MigrationTxKind::Transfer { .. } => None,
    };
    let fvk = {
        let backend = Backend::new(
            &context.wallet,
            context.account,
            None,
            &mut context.store_conn,
        )
        .map_err(|e| format!("Open shared migration backend: {e}"))?;
        backend
            .stored_orchard_fvk()
            .map_err(|e| format!("Read migration viewing key: {e}"))?
    };
    let mut prover = WalletMigrationProver::new(&mut context.wallet, context.account, fvk);
    if !finalize::prove_transaction(&mut prover, state, id, natural_anchor)
        .map_err(|e| e.to_string())?
    {
        return Ok(false);
    }
    let mut backend = Backend::new(
        &context.wallet,
        context.account,
        None,
        &mut context.store_conn,
    )
    .map_err(|e| format!("Open shared migration backend: {e}"))?;
    backend
        .replace_migration(state)
        .map_err(|e| format!("Persist proved migration state: {e}"))?;
    Ok(true)
}

fn transaction_bytes(
    state: &MigrationState,
    id: MigrationTxId,
) -> Result<(Vec<u8>, [u8; 32]), String> {
    let bytes = state
        .transactions()
        .iter()
        .find(|transaction| transaction.id() == id)
        .map(|transaction| transaction.pczt())
        .ok_or_else(|| format!("Unknown migration transaction {}", u32::from(id)))?;
    let pczt =
        pczt::Pczt::parse(bytes).map_err(|e| format!("Parse proved migration PCZT: {e:?}"))?;
    finalize::extract_tx(pczt).map_err(|e| e.to_string())
}

fn transaction_kind(state: &MigrationState, id: MigrationTxId) -> Result<MigrationTxKind, String> {
    state
        .transactions()
        .iter()
        .find(|transaction| transaction.id() == id)
        .map(MigrationTransaction::kind)
        .ok_or_else(|| format!("Unknown migration transaction {}", u32::from(id)))
}

fn with_scheduled_height(
    transaction: &MigrationTransaction,
    scheduled_height: BlockHeight,
) -> MigrationTransaction {
    MigrationTransaction::from_parts(
        transaction.id(),
        transaction.kind(),
        transaction.pczt().clone(),
        transaction.depends_on().clone(),
        scheduled_height,
        transaction.expiry_height(),
        transaction.anchor_boundary(),
        transaction.state(),
        transaction.lock_owner(),
    )
}

/// ZIP 318 requires a resumed wallet to release at most one overdue
/// transaction immediately. The shared engine intentionally leaves this
/// network-runtime policy to its consumer, so move the remaining overdue
/// transactions onto fresh memoryless delays after each accepted broadcast.
fn reschedule_overdue(
    state: &mut MigrationState,
    just_broadcast: MigrationTxId,
    tip: BlockHeight,
) -> Result<Option<String>, String> {
    let just_broadcast_kind = transaction_kind(state, just_broadcast)?;
    let mut overdue = state
        .transactions()
        .iter()
        .enumerate()
        .filter(|(_, transaction)| {
            transaction.id() != just_broadcast
                && std::mem::discriminant(&transaction.kind())
                    == std::mem::discriminant(&just_broadcast_kind)
                && !matches!(
                    transaction.state(),
                    MigrationTxState::Broadcast { .. } | MigrationTxState::Mined { .. }
                )
                && transaction.scheduled_height() <= tip
        })
        .map(|(index, _)| index)
        .collect::<Vec<_>>();
    if overdue.is_empty() {
        return Ok(None);
    }
    overdue.shuffle(&mut OsRng);

    let mut cursor = tip;
    let mut transactions = state.transactions().to_vec();
    for index in overdue {
        let delay = match just_broadcast_kind {
            MigrationTxKind::Preparation { .. } => scheduling::draw_prep_delay(&mut OsRng),
            MigrationTxKind::Transfer { .. } => scheduling::draw_delay(&mut OsRng),
        }
        .max(1);
        cursor = cursor + delay;
        let transaction = &transactions[index];
        if u32::from(transaction.expiry_height()) != 0
            && (cursor >= transaction.expiry_height()
                || scheduling::expiry_height(cursor) != transaction.expiry_height())
        {
            let failed = MigrationState::from_parts(
                EngineStatus::Failed,
                state.note_split().clone(),
                state.preparation().clone(),
                transactions,
            );
            *state = failed;
            return Ok(Some(
                "The refreshed migration schedule crossed an expiry boundary and must be signed again."
                    .to_string(),
            ));
        }
        transactions[index] = with_scheduled_height(transaction, cursor);
    }
    *state = MigrationState::from_parts(
        state.status(),
        state.note_split().clone(),
        state.preparation().clone(),
        transactions,
    );
    Ok(None)
}

async fn drive(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    usk: Option<UnifiedSpendingKey>,
    purpose: DrivePurpose<'_>,
) -> Result<(MigrationState, Vec<String>, Option<String>), String> {
    let mut context = open_context(db_path, network, account_uuid)?;
    let mut state = reconcile_mined(&mut context)?
        .ok_or("No shared Orchard migration is active for this account")?;
    let mut broadcasted = Vec::new();
    let mut message = None;

    loop {
        if purpose.is_cancelled() {
            message = Some("Migration preparation was cancelled.".to_string());
            break;
        }
        let tip = context.tip()?;
        let target_height = tip + 1;
        if state.expired_transactions(target_height).iter().any(|id| {
            matches!(
                transaction_kind(&state, *id),
                Ok(MigrationTxKind::Preparation { .. })
            )
        }) {
            state = fail_state(&state);
            let mut backend = Backend::new(
                &context.wallet,
                context.account,
                None,
                &mut context.store_conn,
            )
            .map_err(|e| format!("Open shared migration backend: {e}"))?;
            backend
                .replace_migration(&state)
                .map_err(|e| format!("Retire expired migration preparation: {e}"))?;
            message = Some(
                "A migration preparation transaction expired. Review a new migration plan."
                    .to_string(),
            );
            break;
        }
        match state.next_step(target_height) {
            zcash_pool_migration_backend::state::AdvanceStep::Prove { id } => {
                if !purpose.may_prove(transaction_kind(&state, id)?) {
                    break;
                }
                if !prove_one(&mut context, &mut state, id)? {
                    message = Some(
                        "Migration proof data is not ready yet. Sync and try again.".to_string(),
                    );
                    break;
                }
            }
            zcash_pool_migration_backend::state::AdvanceStep::Broadcast { id } => {
                let kind = transaction_kind(&state, id)?;
                if !purpose.may_broadcast(kind)
                    || purpose.broadcast_limit_reached(broadcasted.len())
                {
                    break;
                }
                let (raw, txid_bytes) = transaction_bytes(&state, id)?;
                let mut client = crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url)
                    .await
                    .map_err(|e| format!("Connect to lightwalletd for migration: {e}"))?;
                let response = match crate::wallet::sync_engine::send_transaction_with_status(
                    &mut client,
                    &raw,
                )
                .await
                {
                    Ok(response) => response,
                    Err(error) => {
                        message = Some(format!(
                            "Migration broadcast did not complete and will be retried: {error}"
                        ));
                        break;
                    }
                };
                if let Some(error) = super::broadcast::send_response_rejection_error(&response) {
                    message = Some(format!("{error}. The migration needs attention."));
                    break;
                }
                let txid = TxId::from_bytes(txid_bytes);
                state.mark_broadcast(id, txid);
                if let Some(reschedule_message) = reschedule_overdue(&mut state, id, target_height)?
                {
                    message = Some(reschedule_message);
                }
                let mut backend = Backend::new(
                    &context.wallet,
                    context.account,
                    None,
                    &mut context.store_conn,
                )
                .map_err(|e| format!("Open shared migration backend: {e}"))?;
                backend
                    .replace_migration(&state)
                    .map_err(|e| format!("Persist broadcast migration state: {e}"))?;
                if let Err(error) =
                    super::transactions::decrypt_and_store_transaction(db_path, network, &raw, None)
                {
                    message = Some(format!(
                        "Migration was accepted, but local transaction tracking failed: {error}"
                    ));
                }
                broadcasted.push(txid.to_string());
                if state.status() == EngineStatus::Failed {
                    break;
                }
            }
            zcash_pool_migration_backend::state::AdvanceStep::Rebuild { id } => {
                let Some(usk) = usk.clone() else {
                    message = Some(
                        "A migration transaction expired and must be signed again.".to_string(),
                    );
                    break;
                };
                let mut backend = Backend::new(
                    &context.wallet,
                    context.account,
                    Some(usk),
                    &mut context.store_conn,
                )
                .map_err(|e| format!("Open shared migration backend: {e}"))?;
                engine::rebuild_expired_transfer(
                    &context.network,
                    &backend,
                    &mut state,
                    id,
                    &mut OsRng,
                )
                .map_err(|e| format!("Rebuild expired migration transaction: {e}"))?;
                backend
                    .replace_migration(&state)
                    .map_err(|e| format!("Persist rebuilt migration transaction: {e}"))?;
            }
            zcash_pool_migration_backend::state::AdvanceStep::Waiting
            | zcash_pool_migration_backend::state::AdvanceStep::Complete => break,
        }
    }
    Ok((state, broadcasted, message))
}

fn result_from_state(
    state: &MigrationState,
    newly_broadcast: Vec<String>,
    message: Option<String>,
) -> IronwoodMigrationResult {
    let transfer_count = state.note_split().crossing_values().len();
    let started_transfers = state
        .transactions()
        .iter()
        .filter(|transaction| matches!(transaction.kind(), MigrationTxKind::Transfer { .. }))
        .filter(|transaction| {
            matches!(
                transaction.state(),
                MigrationTxState::Broadcast { .. } | MigrationTxState::Mined { .. }
            )
        })
        .count();
    let preparation_complete = state
        .transactions()
        .iter()
        .filter(|transaction| matches!(transaction.kind(), MigrationTxKind::Preparation { .. }))
        .all(|transaction| matches!(transaction.state(), MigrationTxState::Mined { .. }));
    let needs_fresh_signature = message
        .as_deref()
        .is_some_and(|message| message.contains("expired") || message.contains("signed again"));
    let status = if needs_fresh_signature && state.status() != EngineStatus::Failed {
        super::migration::PHASE_READY_TO_MIGRATE
    } else {
        match state.status() {
            EngineStatus::Complete => super::migration::PHASE_COMPLETE,
            EngineStatus::Failed => super::migration::PHASE_FAILED_TERMINAL,
            EngineStatus::Planning => super::migration::PHASE_READY_TO_PREPARE,
            EngineStatus::Committed | EngineStatus::InProgress => {
                if state.transactions().iter().any(|transaction| {
                    matches!(transaction.state(), MigrationTxState::AwaitingSignature)
                }) {
                    super::migration::PHASE_READY_TO_MIGRATE
                } else if !preparation_complete {
                    super::migration::PHASE_WAITING_DENOM_CONFIRMATIONS
                } else if started_transfers > 0 {
                    super::migration::PHASE_WAITING_MIGRATION_CONFIRMATIONS
                } else {
                    super::migration::PHASE_BROADCAST_SCHEDULED
                }
            }
        }
    };
    let migration_fees =
        u64::from(state.note_split().note_fee_buffer()).saturating_mul(transfer_count as u64);
    IronwoodMigrationResult {
        txids: newly_broadcast.join(","),
        status: status.to_string(),
        broadcasted_count: u32::try_from(started_transfers).unwrap_or(u32::MAX),
        total_count: u32::try_from(transfer_count).unwrap_or(u32::MAX),
        message,
        fee_zatoshi: u64::from(state.note_split().prep_fees()).saturating_add(migration_fees),
        migrated_zatoshi: u64::from(state.note_split().total_migratable()),
    }
}

pub(crate) async fn migrate_software(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    seed: SecretVec<u8>,
    approved_schedule: Vec<MigrationScheduleEntry>,
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let usk = derive_usk(db_path, network, account_uuid, seed)?;
    let mut context = open_context(db_path, network, account_uuid)?;
    let existing = {
        let backend = Backend::new(
            &context.wallet,
            context.account,
            None,
            &mut context.store_conn,
        )
        .map_err(|e| format!("Open shared migration backend: {e}"))?;
        backend
            .get_migration()
            .map_err(|e| format!("Read shared migration: {e}"))?
            .filter(|state| !state.is_terminal())
    };
    if existing.is_none() {
        commit_or_resume(
            &mut context,
            Some(usk.clone()),
            false,
            Some(&approved_schedule),
        )?;
    }
    drop(context);

    let (state, txids, message) = drive(
        db_path,
        lightwalletd_url,
        network,
        account_uuid,
        Some(usk),
        DrivePurpose::Broadcast {
            max_broadcasts: None,
        },
    )
    .await?;
    Ok(result_from_state(&state, txids, message))
}

fn prepare_signing_request(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    subset: SigningSubset,
    label: &str,
) -> Result<KeystoneMigrationSigningRequest, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    {
        let requests = signing_requests()
            .lock()
            .map_err(|_| "Keystone migration request store is unavailable".to_string())?;
        if requests.values().any(|request| {
            request.db_path == db_path
                && request.network == network
                && request.account_uuid == account_uuid
        }) {
            return Err("A Keystone migration signing request is already active".to_string());
        }
    }

    let mut context = open_context(db_path, network, account_uuid)?;
    let (mut state, mut unsigned) = commit_or_resume(&mut context, None, true, None)?;
    let expected_schedule = shared_approved_schedule(&context.store_conn, context.account)?;
    if matches!(subset, SigningSubset::Transfers | SigningSubset::All) {
        let target_height = context.tip()? + 1;
        let expired = state.expired_transactions(target_height);
        if expired.iter().any(|id| {
            matches!(
                transaction_kind(&state, *id),
                Ok(MigrationTxKind::Preparation { .. })
            )
        }) {
            let failed = fail_state(&state);
            let mut backend = Backend::new(
                &context.wallet,
                context.account,
                None,
                &mut context.store_conn,
            )
            .map_err(|e| format!("Open shared migration backend: {e}"))?;
            backend
                .replace_migration(&failed)
                .map_err(|e| format!("Retire expired migration preparation: {e}"))?;
            return Err(
                "An expired preparation transaction requires a new migration plan.".to_string(),
            );
        }
        if !expired.is_empty() {
            let mut backend = Backend::new(
                &context.wallet,
                context.account,
                None,
                &mut context.store_conn,
            )
            .map_err(|e| format!("Open shared migration backend: {e}"))?;
            for id in expired {
                let rebuilt = engine::rebuild_expired_transfer_unsigned(
                    &context.network,
                    &backend,
                    &mut state,
                    id,
                    &mut OsRng,
                )
                .map_err(|e| format!("Rebuild expired Keystone migration transaction: {e}"))?;
                unsigned.push(rebuilt.into_parts());
            }
            backend
                .replace_migration(&state)
                .map_err(|e| format!("Persist rebuilt Keystone migration transaction: {e}"))?;
        }
    }
    let transaction_kind = |id: MigrationTxId| {
        state
            .transactions()
            .iter()
            .find(|transaction| transaction.id() == id)
            .map(|transaction| transaction.kind())
    };
    let mut candidates = unsigned
        .into_iter()
        .filter(|(id, _)| match subset {
            SigningSubset::Preparations => matches!(
                transaction_kind(*id),
                Some(MigrationTxKind::Preparation { .. })
            ),
            SigningSubset::Transfers => matches!(
                transaction_kind(*id),
                Some(MigrationTxKind::Transfer { .. })
            ),
            SigningSubset::All => true,
        })
        .collect::<Vec<_>>();
    if candidates.is_empty() {
        return Err("This migration has no transactions awaiting a Keystone signature".to_string());
    }

    let limit = crate::wallet::keystone::ZCASH_SIGN_BATCH_MAX_MESSAGES;
    if matches!(subset, SigningSubset::All) && candidates.len() > limit {
        return Err(format!(
            "Single Keystone migration signing supports at most {limit} PCZTs, but this plan needs {}. Use the staged flow.",
            candidates.len()
        ));
    }
    candidates.truncate(limit);

    let messages = candidates
        .iter()
        .map(|(id, bytes)| {
            Ok(KeystoneMigrationMessage {
                id: u32::from(*id).to_string(),
                redacted_pczt: super::pczt::redact_pczt_for_batch_signer(bytes)?,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    let request_id = new_request_id(label);
    signing_requests()
        .lock()
        .map_err(|_| "Keystone migration request store is unavailable".to_string())?
        .insert(
            request_id.clone(),
            SigningRequest {
                db_path: db_path.to_string(),
                network,
                account_uuid: account_uuid.to_string(),
                ids: candidates.iter().map(|(id, _)| *id).collect(),
                expected_schedule,
            },
        );
    Ok(KeystoneMigrationSigningRequest {
        request_id,
        messages,
        signing_batch_limit: limit as u32,
    })
}

pub(crate) fn prepare_denominations_pczt(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<KeystoneMigrationSigningRequest, String> {
    prepare_signing_request(
        db_path,
        network,
        account_uuid,
        SigningSubset::Preparations,
        "preparations",
    )
}

pub(crate) fn prepare_single_qr_pczt(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<KeystoneMigrationSigningRequest, String> {
    prepare_signing_request(db_path, network, account_uuid, SigningSubset::All, "single")
}

pub(crate) fn prepare_batch_pczt(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<KeystoneMigrationSigningRequest, String> {
    prepare_signing_request(
        db_path,
        network,
        account_uuid,
        SigningSubset::Transfers,
        "batch",
    )
}

fn complete_signing_request(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    request_id: &str,
    signed_messages: &[KeystoneSignedMigrationMessage],
    approved_schedule: Option<&[MigrationScheduleEntry]>,
) -> Result<Option<MigrationState>, String> {
    let request = {
        let requests = signing_requests()
            .lock()
            .map_err(|_| "Keystone migration request store is unavailable".to_string())?;
        requests.get(request_id).cloned()
    };
    let Some(request) = request else {
        return Ok(None);
    };
    if request.db_path != db_path
        || request.network != network
        || request.account_uuid != account_uuid
    {
        return Err("Signed Keystone migration request does not match this account".to_string());
    }
    if let (Some(expected), Some(approved)) = (&request.expected_schedule, approved_schedule) {
        let mut expected = expected.clone();
        let mut approved = approved.to_vec();
        expected.sort_by_key(|entry| entry.part_index);
        approved.sort_by_key(|entry| entry.part_index);
        if expected != approved {
            return Err(
                "Migration plan changed. Review the refreshed amounts and schedule.".to_string(),
            );
        }
    }

    let mut expected_ids = request
        .ids
        .iter()
        .copied()
        .map(u32::from)
        .collect::<Vec<_>>();
    let mut supplied_ids = signed_messages
        .iter()
        .map(|message| {
            message
                .id
                .parse::<u32>()
                .map_err(|_| format!("Invalid shared migration message id {}", message.id))
        })
        .collect::<Result<Vec<_>, String>>()?;
    expected_ids.sort_unstable();
    supplied_ids.sort_unstable();
    if expected_ids != supplied_ids {
        return Err("Keystone returned a different migration message set".to_string());
    }

    let mut context = open_context(db_path, network, account_uuid)?;
    let mut backend = Backend::new(
        &context.wallet,
        context.account,
        None,
        &mut context.store_conn,
    )
    .map_err(|e| format!("Open shared migration backend: {e}"))?;
    let mut state = backend
        .get_migration()
        .map_err(|e| format!("Read shared migration: {e}"))?
        .ok_or("No shared migration is committed")?;

    for message in signed_messages {
        let id = MigrationTxId::new(
            message
                .id
                .parse::<u32>()
                .map_err(|_| format!("Invalid shared migration message id {}", message.id))?,
        );
        let base = state
            .transactions()
            .iter()
            .find(|transaction| transaction.id() == id)
            .map(|transaction| transaction.pczt().clone())
            .ok_or_else(|| format!("Unknown shared migration transaction {}", message.id))?;
        super::pczt::preflight_orchard_spend_auth_signatures(&base, &message.sigs)?;
        let parsed = pczt::Pczt::parse(&base)
            .map_err(|e| format!("Parse unsigned migration PCZT: {e:?}"))?;
        let signed =
            super::pczt::apply_compact_orchard_spend_auth_signatures(parsed, &message.sigs)?
                .serialize()
                .map_err(|e| format!("Serialize signed migration PCZT: {e:?}"))?;
        if !state.apply_signature(id, signed) {
            return Err(format!(
                "Migration transaction {} is not awaiting this signature",
                message.id
            ));
        }
    }
    backend
        .replace_migration(&state)
        .map_err(|e| format!("Persist signed migration state: {e}"))?;
    signing_requests()
        .lock()
        .map_err(|_| "Keystone migration request store is unavailable".to_string())?
        .remove(request_id);
    Ok(Some(state))
}

pub(crate) async fn complete_denominations_pczt(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    request_id: &str,
    signed_messages: Vec<KeystoneSignedMigrationMessage>,
    approved_schedule: Vec<MigrationScheduleEntry>,
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    complete_signing_request(
        db_path,
        network,
        account_uuid,
        request_id,
        &signed_messages,
        Some(&approved_schedule),
    )?
    .ok_or("Shared Keystone migration request disappeared")?;
    let (state, txids, message) = drive(
        db_path,
        lightwalletd_url,
        network,
        account_uuid,
        None,
        DrivePurpose::Broadcast {
            max_broadcasts: None,
        },
    )
    .await?;
    Ok(result_from_state(&state, txids, message))
}

pub(crate) async fn complete_single_qr_pczt(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    request_id: &str,
    signed_messages: Vec<KeystoneSignedMigrationMessage>,
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    complete_signing_request(
        db_path,
        network,
        account_uuid,
        request_id,
        &signed_messages,
        None,
    )?
    .ok_or("Shared Keystone migration request disappeared")?;
    let (state, txids, message) = drive(
        db_path,
        lightwalletd_url,
        network,
        account_uuid,
        None,
        DrivePurpose::Broadcast {
            max_broadcasts: None,
        },
    )
    .await?;
    Ok(result_from_state(&state, txids, message))
}

pub(crate) fn complete_batch_pczt(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    request_id: &str,
    signed_messages: Vec<KeystoneSignedMigrationMessage>,
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let state = complete_signing_request(
        db_path,
        network,
        account_uuid,
        request_id,
        &signed_messages,
        None,
    )?
    .ok_or("Shared Keystone migration request disappeared")?;
    Ok(result_from_state(
        &state,
        Vec::new(),
        Some("Migration transactions were signed and saved.".to_string()),
    ))
}

fn transaction_txid(
    state: &MigrationState,
    transaction: &MigrationTransaction,
) -> Result<Option<String>, String> {
    match transaction.state() {
        MigrationTxState::AwaitingSignature | MigrationTxState::Signed => Ok(None),
        MigrationTxState::Proved
        | MigrationTxState::Broadcast { .. }
        | MigrationTxState::Mined { .. } => transaction_bytes(state, transaction.id())
            .map(|(_, txid)| Some(TxId::from_bytes(txid).to_string())),
    }
}

fn confirmations(tip: BlockHeight, mined: BlockHeight) -> u32 {
    u32::from(tip)
        .saturating_sub(u32::from(mined))
        .saturating_add(1)
}

fn status_from_shared(
    state: &MigrationState,
    tip: BlockHeight,
    run_id: String,
) -> Result<MigrationStatus, String> {
    let target_height = tip + 1;
    let expired = state.expired_transactions(target_height);
    let preparation = state
        .transactions()
        .iter()
        .filter(|transaction| matches!(transaction.kind(), MigrationTxKind::Preparation { .. }))
        .collect::<Vec<_>>();
    let transfers = state
        .transactions()
        .iter()
        .filter(|transaction| matches!(transaction.kind(), MigrationTxKind::Transfer { .. }))
        .collect::<Vec<_>>();
    let any_awaiting_signature = state
        .transactions()
        .iter()
        .any(|transaction| matches!(transaction.state(), MigrationTxState::AwaitingSignature));
    let preparation_complete = preparation
        .iter()
        .all(|transaction| matches!(transaction.state(), MigrationTxState::Mined { .. }));
    let any_transfer_broadcast = transfers.iter().any(|transaction| {
        matches!(
            transaction.state(),
            MigrationTxState::Broadcast { .. } | MigrationTxState::Mined { .. }
        )
    });
    let phase = match state.status() {
        EngineStatus::Complete => super::migration::PHASE_COMPLETE,
        EngineStatus::Failed => super::migration::PHASE_FAILED_TERMINAL,
        EngineStatus::Planning => super::migration::PHASE_READY_TO_PREPARE,
        EngineStatus::Committed | EngineStatus::InProgress if !expired.is_empty() => {
            super::migration::PHASE_READY_TO_MIGRATE
        }
        EngineStatus::Committed | EngineStatus::InProgress if any_awaiting_signature => {
            super::migration::PHASE_READY_TO_MIGRATE
        }
        EngineStatus::Committed | EngineStatus::InProgress if !preparation_complete => {
            super::migration::PHASE_WAITING_DENOM_CONFIRMATIONS
        }
        EngineStatus::Committed | EngineStatus::InProgress if any_transfer_broadcast => {
            super::migration::PHASE_WAITING_MIGRATION_CONFIRMATIONS
        }
        EngineStatus::Committed | EngineStatus::InProgress => {
            super::migration::PHASE_BROADCAST_SCHEDULED
        }
    };

    let mut schedule_order = transfers
        .iter()
        .filter_map(|transaction| {
            transaction
                .kind()
                .transfer_crossing()
                .map(|crossing| (crossing, transaction.scheduled_height(), transaction.id()))
        })
        .collect::<Vec<_>>();
    schedule_order.sort_by_key(|(_, height, id)| (*height, u32::from(*id)));
    let schedule_order = schedule_order
        .into_iter()
        .enumerate()
        .map(|(order, (crossing, _, _))| (crossing, u32::try_from(order).unwrap_or(u32::MAX)))
        .collect::<HashMap<_, _>>();

    let confirmation_target = 1;
    let mut scheduled_broadcasts = Vec::new();
    let mut parts = Vec::with_capacity(transfers.len());
    for transaction in &transfers {
        let crossing = transaction
            .kind()
            .transfer_crossing()
            .ok_or("Shared migration transfer has no crossing index")?;
        let value_zatoshi = state
            .note_split()
            .crossing_values()
            .get(crossing)
            .copied()
            .map(u64::from)
            .ok_or("Shared migration transfer has no crossing value")?;
        let txid_hex = transaction_txid(state, transaction)?;
        let confirmation_count = transaction
            .state()
            .mined_height()
            .map(|height| confirmations(tip, height))
            .unwrap_or(0);
        let part_state = match transaction.state() {
            MigrationTxState::AwaitingSignature => MigrationPartState::NeedsInput,
            MigrationTxState::Signed if expired.contains(&transaction.id()) => {
                MigrationPartState::NeedsInput
            }
            MigrationTxState::Signed if state.deps_mined(transaction.depends_on()) => {
                MigrationPartState::Scheduled
            }
            MigrationTxState::Signed => MigrationPartState::Preparing,
            MigrationTxState::Proved if expired.contains(&transaction.id()) => {
                MigrationPartState::NeedsInput
            }
            MigrationTxState::Proved => MigrationPartState::Scheduled,
            MigrationTxState::Broadcast { .. } => MigrationPartState::Migrating,
            MigrationTxState::Mined { .. } => MigrationPartState::Completed,
        };
        let part_index = u32::try_from(crossing).unwrap_or(u32::MAX);
        if let Some(txid_hex) = txid_hex.clone() {
            scheduled_broadcasts.push(ScheduledMigrationBroadcast {
                txid_hex,
                value_zatoshi,
                scheduled_at_ms: 0,
                schedule_start_height: transaction.anchor_boundary().map(u32::from),
                scheduled_height: u32::from(transaction.scheduled_height()),
                status: transaction.state().as_ref().to_string(),
            });
        }
        parts.push(MigrationPartStatus {
            part_index,
            schedule_order: schedule_order.get(&crossing).copied(),
            value_zatoshi,
            state: part_state,
            txid_hex,
            schedule_start_height: transaction.anchor_boundary().map(u32::from),
            scheduled_height: Some(u32::from(transaction.scheduled_height())),
            confirmation_count,
            confirmation_target,
        });
    }
    parts.sort_by_key(|part| part.part_index);
    scheduled_broadcasts.sort_by_key(|broadcast| broadcast.scheduled_height);

    let next_action = state
        .transaction_statuses(target_height)
        .into_iter()
        .filter(|status| !matches!(status.state(), MigrationTxState::Mined { .. }))
        .filter_map(|status| {
            let height = if status.ready() {
                u32::from(tip)
            } else {
                match status.blocked_on() {
                    Some(zcash_pool_migration_backend::state::Blocker::Signature)
                    | Some(zcash_pool_migration_backend::state::Blocker::Expired) => return None,
                    Some(zcash_pool_migration_backend::state::Blocker::AnchorBoundary) => state
                        .transactions()
                        .iter()
                        .find(|transaction| transaction.id() == status.id())
                        .and_then(MigrationTransaction::anchor_boundary)
                        .map(u32::from)
                        .unwrap_or_else(|| u32::from(status.scheduled_height()))
                        .saturating_add(1),
                    _ => u32::from(status.scheduled_height()),
                }
            };
            let crossing = status.kind().transfer_crossing();
            Some((height, crossing))
        })
        .min_by_key(|(height, _)| *height);
    let estimated_completion_height = transfers
        .iter()
        .map(|transaction| {
            transaction
                .state()
                .mined_height()
                .unwrap_or_else(|| transaction.scheduled_height())
        })
        .max()
        .map(u32::from);
    let mined_preparation_count = preparation
        .iter()
        .filter(|transaction| matches!(transaction.state(), MigrationTxState::Mined { .. }))
        .count();
    let denomination_confirmation_count = if preparation.is_empty() {
        confirmation_target
    } else if mined_preparation_count == preparation.len() {
        confirmation_target
    } else {
        0
    };
    let prepared_note_count = transfers
        .iter()
        .filter(|transaction| state.deps_mined(transaction.depends_on()))
        .count();
    let no_transaction_started = state.transactions().iter().all(|transaction| {
        !matches!(
            transaction.state(),
            MigrationTxState::Broadcast { .. } | MigrationTxState::Mined { .. }
        )
    });

    Ok(MigrationStatus {
        phase: phase.to_string(),
        active_run_id: (!matches!(state.status(), EngineStatus::Complete)).then_some(run_id),
        target_values_zatoshi: state
            .note_split()
            .crossing_values()
            .iter()
            .copied()
            .map(u64::from)
            .collect(),
        prepared_note_count: u32::try_from(prepared_note_count).unwrap_or(u32::MAX),
        denomination_confirmation_count,
        denomination_confirmation_target: confirmation_target,
        denomination_split_completed_count: u32::try_from(mined_preparation_count)
            .unwrap_or(u32::MAX),
        denomination_split_total_count: u32::try_from(preparation.len()).unwrap_or(u32::MAX),
        pending_tx_count: u32::try_from(
            transfers
                .iter()
                .filter(|transaction| {
                    matches!(
                        transaction.state(),
                        MigrationTxState::Proved
                            | MigrationTxState::Broadcast { .. }
                            | MigrationTxState::Mined { .. }
                    )
                })
                .count(),
        )
        .unwrap_or(u32::MAX),
        broadcasted_tx_count: u32::try_from(
            transfers
                .iter()
                .filter(|transaction| {
                    matches!(transaction.state(), MigrationTxState::Broadcast { .. })
                })
                .count(),
        )
        .unwrap_or(u32::MAX),
        confirmed_tx_count: u32::try_from(
            transfers
                .iter()
                .filter(|transaction| matches!(transaction.state(), MigrationTxState::Mined { .. }))
                .count(),
        )
        .unwrap_or(u32::MAX),
        total_count: u32::try_from(transfers.len()).unwrap_or(u32::MAX),
        signed_child_pczt_count: u32::try_from(
            transfers
                .iter()
                .filter(|transaction| matches!(transaction.state(), MigrationTxState::Signed))
                .count(),
        )
        .unwrap_or(u32::MAX),
        pending_split_stage_count: u32::try_from(
            preparation.len().saturating_sub(mined_preparation_count),
        )
        .unwrap_or(u32::MAX),
        message: (!expired.is_empty())
            .then(|| "A migration transaction expired and must be signed again.".to_string()),
        can_abandon: no_transaction_started && !state.is_terminal(),
        signing_batch_limit: crate::wallet::keystone::ZCASH_SIGN_BATCH_MAX_MESSAGES as u32,
        schedule_mean_delay_blocks: scheduling::MEAN_DELAY,
        schedule_max_delay_blocks: scheduling::MAX_DELAY,
        max_prepared_notes_per_run: MIGRATION_MAX_PREPARED_NOTES_PER_RUN as u32,
        next_action_height: next_action.map(|(height, _)| height),
        estimated_completion_height,
        next_action_part_index: next_action
            .and_then(|(_, crossing)| crossing)
            .and_then(|crossing| u32::try_from(crossing).ok()),
        scheduled_broadcasts,
        parts,
    })
}

fn status_without_migration(
    context: &mut CallContext,
    orchard_spendable: u64,
    orchard_pending: u64,
    ironwood_spendable: u64,
    ironwood_pending: u64,
) -> Result<MigrationStatus, String> {
    let phase = if orchard_pending > 0 {
        super::migration::PHASE_WAITING_FOR_SPENDABLE_ORCHARD
    } else if orchard_spendable > 0 {
        let backend = Backend::new(
            &context.wallet,
            context.account,
            None,
            &mut context.store_conn,
        )
        .map_err(|e| format!("Open shared migration backend: {e}"))?;
        match engine::plan_migration(&context.network, &backend, &mut OsRng) {
            Ok(_) => super::migration::PHASE_READY_TO_PREPARE,
            Err(engine::MigrationError::NothingToMigrate) => {
                super::migration::PHASE_NO_ORCHARD_FUNDS
            }
            Err(error) => return Err(format!("Plan shared migration status: {error}")),
        }
    } else if ironwood_spendable > 0 {
        super::migration::PHASE_COMPLETE
    } else if ironwood_pending > 0 {
        super::migration::PHASE_WAITING_FOR_IRONWOOD_SPENDABILITY
    } else {
        super::migration::PHASE_NO_ORCHARD_FUNDS
    };

    Ok(MigrationStatus {
        phase: phase.to_string(),
        active_run_id: None,
        target_values_zatoshi: Vec::new(),
        prepared_note_count: 0,
        denomination_confirmation_count: 0,
        denomination_confirmation_target: 1,
        denomination_split_completed_count: 0,
        denomination_split_total_count: 0,
        pending_tx_count: 0,
        broadcasted_tx_count: 0,
        confirmed_tx_count: 0,
        total_count: 0,
        signed_child_pczt_count: 0,
        pending_split_stage_count: 0,
        message: None,
        can_abandon: false,
        signing_batch_limit: crate::wallet::keystone::ZCASH_SIGN_BATCH_MAX_MESSAGES as u32,
        schedule_mean_delay_blocks: scheduling::MEAN_DELAY,
        schedule_max_delay_blocks: scheduling::MAX_DELAY,
        max_prepared_notes_per_run: MIGRATION_MAX_PREPARED_NOTES_PER_RUN as u32,
        next_action_height: None,
        estimated_completion_height: None,
        next_action_part_index: None,
        scheduled_broadcasts: Vec::new(),
        parts: Vec::new(),
    })
}

pub(crate) fn migration_status(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    orchard_spendable: u64,
    orchard_pending: u64,
    ironwood_spendable: u64,
    ironwood_pending: u64,
) -> Result<MigrationStatus, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let mut context = open_context(db_path, network, account_uuid)?;
    let Some(state) = reconcile_mined(&mut context)? else {
        return status_without_migration(
            &mut context,
            orchard_spendable,
            orchard_pending,
            ironwood_spendable,
            ironwood_pending,
        );
    };
    let run_id = shared_run_id(&context.store_conn, context.account)?;
    let mut status = status_from_shared(&state, context.tip()?, run_id)?;
    if state.status() == EngineStatus::Complete {
        let backend = Backend::new(
            &context.wallet,
            context.account,
            None,
            &mut context.store_conn,
        )
        .map_err(|e| format!("Open shared migration backend: {e}"))?;
        match engine::plan_migration(&context.network, &backend, &mut OsRng) {
            Ok(_) => {
                status.phase = super::migration::PHASE_READY_TO_PREPARE.to_string();
                status.active_run_id = None;
                status.target_values_zatoshi.clear();
                status.parts.clear();
                status.scheduled_broadcasts.clear();
                status.prepared_note_count = 0;
                status.denomination_confirmation_count = 0;
                status.denomination_split_completed_count = 0;
                status.denomination_split_total_count = 0;
                status.pending_tx_count = 0;
                status.broadcasted_tx_count = 0;
                status.confirmed_tx_count = 0;
                status.total_count = 0;
                status.signed_child_pczt_count = 0;
                status.pending_split_stage_count = 0;
                status.next_action_height = None;
                status.estimated_completion_height = None;
                status.next_action_part_index = None;
            }
            Err(engine::MigrationError::NothingToMigrate) => {}
            Err(error) => return Err(format!("Plan the next shared migration run: {error}")),
        }
        if status.phase == super::migration::PHASE_COMPLETE
            && (orchard_spendable > 0 || orchard_pending > 0)
        {
            return status_without_migration(
                &mut context,
                orchard_spendable,
                orchard_pending,
                ironwood_spendable,
                ironwood_pending,
            );
        }
    }
    Ok(status)
}

pub(super) fn has_active_migration(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<bool, String> {
    let mut context = open_context(db_path, network, account_uuid)?;
    let backend = Backend::new(
        &context.wallet,
        context.account,
        None,
        &mut context.store_conn,
    )
    .map_err(|e| format!("Open shared migration backend: {e}"))?;
    backend
        .get_migration()
        .map(|state| state.is_some_and(|state| !state.is_terminal()))
        .map_err(|e| format!("Read shared migration: {e}"))
}

pub async fn broadcast_due(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let (state, txids, message) = drive(
        db_path,
        lightwalletd_url,
        network,
        account_uuid,
        None,
        DrivePurpose::Broadcast {
            max_broadcasts: None,
        },
    )
    .await?;
    Ok(result_from_state(&state, txids, message))
}

pub async fn broadcast_one(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let (state, txids, message) = drive(
        db_path,
        lightwalletd_url,
        network,
        account_uuid,
        None,
        DrivePurpose::Broadcast {
            max_broadcasts: Some(1),
        },
    )
    .await?;
    Ok(result_from_state(&state, txids, message))
}

pub(crate) async fn advance_preparation(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    expected_run_id: &str,
    cancel: &AtomicBool,
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let account = parse_account_uuid(account_uuid)?;
    let context = open_context(db_path, network, account_uuid)?;
    if expected_run_id != shared_run_id(&context.store_conn, account)? {
        return Err("Ironwood migration preparation run changed".to_string());
    }
    drop(context);
    let (state, txids, message) = drive(
        db_path,
        lightwalletd_url,
        network,
        account_uuid,
        None,
        DrivePurpose::Preparation { cancel },
    )
    .await?;
    Ok(result_from_state(&state, txids, message))
}

pub(crate) async fn prepare_outbox(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let (state, txids, message) = drive(
        db_path,
        lightwalletd_url,
        network,
        account_uuid,
        None,
        DrivePurpose::Outbox,
    )
    .await?;
    Ok(result_from_state(&state, txids, message))
}

pub(crate) fn export_outbox(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<Option<MigrationOutboxBatch>, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let mut context = open_context(db_path, network, account_uuid)?;
    let Some(state) = reconcile_mined(&mut context)? else {
        return Ok(None);
    };
    if state.is_terminal() {
        return Ok(None);
    }
    let tip = context.tip()?;
    let mut items = state
        .transactions()
        .iter()
        .filter_map(|transaction| {
            let crossing = transaction.kind().transfer_crossing()?;
            matches!(transaction.state(), MigrationTxState::Proved)
                .then_some((crossing, transaction))
        })
        .map(|(crossing, transaction)| {
            let (raw_tx, txid) = transaction_bytes(&state, transaction.id())?;
            let txid_hex = TxId::from_bytes(txid).to_string();
            let anchor_boundary_height = transaction
                .anchor_boundary()
                .map(u32::from)
                .ok_or("Shared migration transfer has no anchor boundary")?;
            Ok(MigrationOutboxItem {
                item_id: txid_hex.clone(),
                part_index: u32::try_from(crossing).unwrap_or(u32::MAX),
                txid_hex,
                raw_tx,
                anchor_boundary_height,
                scheduled_height: u32::from(transaction.scheduled_height()),
                schedule_start_height: anchor_boundary_height,
                expiry_height: u32::from(transaction.expiry_height()),
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    items.sort_by_key(|item| (item.scheduled_height, item.part_index));
    let next_proof_height = state
        .transactions()
        .iter()
        .filter(|transaction| {
            matches!(transaction.kind(), MigrationTxKind::Transfer { .. })
                && matches!(transaction.state(), MigrationTxState::Signed)
        })
        .filter_map(MigrationTransaction::anchor_boundary)
        .map(|height| u32::from(height).saturating_add(1).max(u32::from(tip)))
        .min();
    if items.is_empty() && next_proof_height.is_none() {
        return Ok(None);
    }
    Ok(Some(MigrationOutboxBatch {
        run_id: shared_run_id(&context.store_conn, context.account)?,
        timing_mean_blocks: scheduling::MEAN_DELAY,
        timing_max_blocks: scheduling::MAX_DELAY,
        next_proof_height,
        items,
    }))
}

fn fail_state(state: &MigrationState) -> MigrationState {
    MigrationState::from_parts(
        EngineStatus::Failed,
        state.note_split().clone(),
        state.preparation().clone(),
        state.transactions().to_vec(),
    )
}

fn apply_outbox_schedule_updates(
    state: &mut MigrationState,
    accepted_id: MigrationTxId,
    accepted_was_proved: bool,
    remote_height: u32,
    schedule_updates: &[(String, u32, u32)],
) -> Result<(), String> {
    if schedule_updates.is_empty() {
        if accepted_was_proved {
            let has_overdue_peer = state.transactions().iter().any(|transaction| {
                transaction.id() != accepted_id
                    && matches!(transaction.kind(), MigrationTxKind::Transfer { .. })
                    && matches!(transaction.state(), MigrationTxState::Proved)
                    && u32::from(transaction.scheduled_height()) <= remote_height
                    && u32::from(transaction.expiry_height()) > remote_height
            });
            if has_overdue_peer {
                return Err(
                    "Migration outbox receipt must reschedule every remaining overdue item"
                        .to_string(),
                );
            }
        }
        return Ok(());
    }

    let accepted_txid = transaction_txid(
        state,
        state
            .transactions()
            .iter()
            .find(|transaction| transaction.id() == accepted_id)
            .ok_or("Accepted migration outbox transaction disappeared")?,
    )?
    .ok_or("Accepted migration outbox transaction has no transaction ID")?
    .to_ascii_lowercase();
    let mut supplied = BTreeSet::new();
    let mut previous_scheduled_height = remote_height;
    for (item_id, scheduled_height, schedule_start_height) in schedule_updates {
        let item_id = item_id.to_ascii_lowercase();
        if item_id == accepted_txid {
            return Err("Accepted migration outbox item cannot reschedule itself".to_string());
        }
        if !supplied.insert(item_id.clone()) {
            return Err(format!(
                "Migration outbox schedule update {item_id} is duplicated"
            ));
        }
        if *schedule_start_height != remote_height {
            return Err(format!(
                "Migration outbox schedule update {item_id} does not start at the receipt height"
            ));
        }
        let incremental_delay = scheduled_height
            .checked_sub(previous_scheduled_height)
            .ok_or_else(|| format!("Migration outbox schedule update {item_id} moves backward"))?;
        if incremental_delay == 0 || incremental_delay > scheduling::MAX_DELAY {
            return Err(format!(
                "Migration outbox schedule update {item_id} is outside the timing window"
            ));
        }
        previous_scheduled_height = *scheduled_height;
    }

    if accepted_was_proved {
        let expected = state
            .transactions()
            .iter()
            .filter(|transaction| {
                transaction.id() != accepted_id
                    && matches!(transaction.kind(), MigrationTxKind::Transfer { .. })
                    && matches!(transaction.state(), MigrationTxState::Proved)
                    && u32::from(transaction.scheduled_height()) <= remote_height
                    && u32::from(transaction.expiry_height()) > remote_height
            })
            .map(|transaction| {
                transaction_txid(state, transaction).and_then(|txid| {
                    txid.map(|txid| txid.to_ascii_lowercase())
                        .ok_or("An overdue migration outbox item has no transaction ID".to_string())
                })
            })
            .collect::<Result<BTreeSet<_>, String>>()?;
        if supplied != expected {
            return Err(
                "Migration outbox receipt must reschedule exactly the remaining overdue items"
                    .to_string(),
            );
        }
    }

    let mut transactions = state.transactions().to_vec();
    for (item_id, scheduled_height, _) in schedule_updates {
        let mut matched = false;
        for transaction in &mut transactions {
            if !matches!(transaction.kind(), MigrationTxKind::Transfer { .. }) {
                continue;
            }
            let (_, txid) = transaction_bytes(state, transaction.id())?;
            if !TxId::from_bytes(txid)
                .to_string()
                .eq_ignore_ascii_case(item_id)
            {
                continue;
            }
            let scheduled_height = BlockHeight::from_u32(*scheduled_height);
            if scheduled_height >= transaction.expiry_height() {
                return Err(format!(
                    "Migration outbox item {item_id} was rescheduled past its expiry height"
                ));
            }
            if !accepted_was_proved {
                if !matches!(
                    transaction.state(),
                    MigrationTxState::Proved
                        | MigrationTxState::Broadcast { .. }
                        | MigrationTxState::Mined { .. }
                ) {
                    return Err(format!(
                        "Migration outbox schedule item {item_id} is no longer scheduled"
                    ));
                }
                if transaction.scheduled_height() != scheduled_height {
                    return Err(format!(
                        "Migration outbox schedule item {item_id} is no longer scheduled"
                    ));
                }
            } else {
                if !matches!(transaction.state(), MigrationTxState::Proved) {
                    return Err(format!(
                        "Migration outbox schedule item {item_id} is no longer scheduled"
                    ));
                }
                // A fresh delay may cross the PCZT's canonical expiry bucket.
                // The iOS outbox detects that before submission and returns a
                // `needsResign` receipt; the already accepted peer must still
                // be reconciled now.
                *transaction = with_scheduled_height(transaction, scheduled_height);
            }
            matched = true;
            break;
        }
        if !matched {
            return Err(format!(
                "Migration outbox schedule update {item_id} was not found"
            ));
        }
    }
    *state = MigrationState::from_parts(
        state.status(),
        state.note_split().clone(),
        state.preparation().clone(),
        transactions,
    );
    Ok(())
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn reconcile_outbox_receipt(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    run_id: &str,
    txid_hex: &str,
    outcome: &str,
    remote_height: u32,
    response_message: Option<&str>,
    schedule_updates: Vec<(String, u32, u32)>,
    accepted_raw_transaction: Option<Vec<u8>>,
) -> Result<(), String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let mut context = open_context(db_path, network, account_uuid)?;
    if run_id != shared_run_id(&context.store_conn, context.account)? {
        return Err("Migration outbox receipt does not match this account and run".to_string());
    }
    let mut backend = Backend::new(
        &context.wallet,
        context.account,
        None,
        &mut context.store_conn,
    )
    .map_err(|e| format!("Open shared migration backend: {e}"))?;
    let mut state = backend
        .get_migration()
        .map_err(|e| format!("Read shared migration: {e}"))?
        .ok_or("No shared migration is stored")?;
    let matching = state
        .transactions()
        .iter()
        .filter(|transaction| matches!(transaction.kind(), MigrationTxKind::Transfer { .. }))
        .map(|transaction| {
            transaction_txid(&state, transaction).map(|txid| {
                txid.map(|txid| {
                    (
                        transaction.id(),
                        transaction.expiry_height(),
                        transaction.state(),
                        txid,
                    )
                })
            })
        })
        .collect::<Result<Vec<_>, String>>()?
        .into_iter()
        .flatten()
        .find(|(_, _, _, txid)| txid.eq_ignore_ascii_case(txid_hex))
        .ok_or("Migration outbox receipt transaction was not found in this run")?;
    let (id, expiry_height, accepted_state, _) = matching;

    match outcome {
        "accepted" | "acceptedEquivalent" => {
            let expected_raw = transaction_bytes(&state, id)?.0;
            let accepted_raw = accepted_raw_transaction
                .ok_or("Accepted migration outbox receipt is missing its raw transaction")?;
            if accepted_raw != expected_raw {
                return Err("Accepted migration outbox transaction payload mismatch".to_string());
            }
            let accepted_was_proved = matches!(accepted_state, MigrationTxState::Proved);
            if !matches!(
                accepted_state,
                MigrationTxState::Proved
                    | MigrationTxState::Broadcast { .. }
                    | MigrationTxState::Mined { .. }
            ) {
                return Err(format!(
                    "Migration outbox receipt cannot accept a transaction in state {}",
                    accepted_state.as_ref()
                ));
            }
            apply_outbox_schedule_updates(
                &mut state,
                id,
                accepted_was_proved,
                remote_height,
                &schedule_updates,
            )?;
            if accepted_was_proved {
                state.mark_broadcast(
                    id,
                    TxId::from_bytes({
                        let (_, txid) = transaction_bytes(&state, id)?;
                        txid
                    }),
                );
            }
            backend
                .replace_migration(&state)
                .map_err(|e| format!("Persist migration outbox acceptance: {e}"))?;
            super::transactions::decrypt_and_store_transaction(
                db_path,
                network,
                &accepted_raw,
                None,
            )
        }
        "rejected" => {
            if !schedule_updates.is_empty() {
                return Err("Rejected migration outbox receipt cannot update schedules".to_string());
            }
            let _ = response_message;
            backend
                .replace_migration(&fail_state(&state))
                .map_err(|e| format!("Retire rejected shared migration: {e}"))
        }
        "expired" => {
            if !schedule_updates.is_empty() {
                return Err("Expired migration outbox receipt cannot update schedules".to_string());
            }
            if remote_height < u32::from(expiry_height) {
                return Err(
                    "Migration outbox receipt expired before the transaction expiry height"
                        .to_string(),
                );
            }
            // Keep the transaction in the engine state. Its normal `Rebuild`
            // step will replace the expired artifact and require a fresh
            // software or external signature.
            Ok(())
        }
        "needsResign" => {
            if !schedule_updates.is_empty() {
                return Err("Migration outbox re-sign receipt cannot update schedules".to_string());
            }
            backend
                .replace_migration(&fail_state(&state))
                .map_err(|e| format!("Retire shared migration for re-signing: {e}"))
        }
        _ => Err(format!(
            "Unsupported migration outbox receipt outcome: {outcome}"
        )),
    }
}

pub(crate) fn keystone_proof_status(
    request_id: &str,
) -> Result<KeystoneMigrationProofStatus, String> {
    let requests = signing_requests()
        .lock()
        .map_err(|_| "Keystone migration request store is unavailable".to_string())?;
    if let Some(request) = requests.get(request_id) {
        let count = u32::try_from(request.ids.len()).unwrap_or(u32::MAX);
        return Ok(KeystoneMigrationProofStatus {
            ready_count: count,
            total_count: count,
            is_ready: true,
            is_failed: false,
            message: None,
        });
    }
    Err(format!(
        "Keystone migration request {request_id} was not found"
    ))
}

pub(crate) fn discard_keystone_request(request_id: &str) -> Result<(), String> {
    signing_requests()
        .lock()
        .map_err(|_| "Keystone migration request store is unavailable".to_string())?
        .remove(request_id);
    Ok(())
}

pub(crate) fn discard_keystone_requests_for_account(
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<(), String> {
    signing_requests()
        .lock()
        .map_err(|_| "Keystone migration request store is unavailable".to_string())?
        .retain(|_, request| !(request.account_uuid == account_uuid && request.network == network));
    Ok(())
}

pub(crate) fn discard_all_keystone_requests() -> Result<(), String> {
    signing_requests()
        .lock()
        .map_err(|_| "Keystone migration request store is unavailable".to_string())?
        .clear();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use zcash_pool_migration_backend::{
        note_splitting::NoteSplitPlan, preparation::PreparationPlan,
    };
    use zcash_protocol::value::Zatoshis;

    #[test]
    fn shared_run_metadata_round_trips_the_approved_schedule() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        let account = AccountUuid::from_uuid(uuid::Uuid::from_u128(1));
        let first_schedule = vec![MigrationScheduleEntry {
            part_index: Some(0),
            value_zatoshi: 1_000_000,
            block_offset: 144,
        }];

        let first_run = replace_shared_run_id(&conn, account, &first_schedule).unwrap();
        assert_eq!(shared_run_id(&conn, account).unwrap(), first_run);
        assert_eq!(
            shared_approved_schedule(&conn, account).unwrap(),
            Some(first_schedule)
        );

        let second_schedule = vec![MigrationScheduleEntry {
            part_index: Some(0),
            value_zatoshi: 2_000_000,
            block_offset: 288,
        }];
        let second_run = replace_shared_run_id(&conn, account, &second_schedule).unwrap();
        assert_ne!(second_run, first_run);
        assert_eq!(
            shared_approved_schedule(&conn, account).unwrap(),
            Some(second_schedule)
        );
    }

    #[test]
    fn one_overdue_broadcast_respreads_the_remaining_transfers() {
        let tip = BlockHeight::from_u32(1_000);
        let expiry = scheduling::expiry_height(tip);
        let crossing_values = [1_000_000, 2_000_000, 3_000_000]
            .into_iter()
            .map(|value| Zatoshis::from_u64(value).unwrap())
            .collect::<Vec<_>>();
        let total = crossing_values
            .iter()
            .copied()
            .fold(Zatoshis::ZERO, |sum, value| (sum + value).unwrap());
        let split = NoteSplitPlan::from_stored_parts(
            crossing_values,
            Zatoshis::ZERO,
            None,
            Zatoshis::ZERO,
            total,
            total,
        )
        .unwrap();
        let transactions = (0..3)
            .map(|crossing| {
                MigrationTransaction::from_parts(
                    MigrationTxId::new(crossing as u32),
                    MigrationTxKind::Transfer { crossing },
                    Vec::new(),
                    Vec::new(),
                    BlockHeight::from_u32(900 + crossing as u32),
                    expiry,
                    Some(BlockHeight::from_u32(864)),
                    if crossing == 0 {
                        MigrationTxState::Broadcast {
                            txid: TxId::from_bytes([1; 32]),
                        }
                    } else {
                        MigrationTxState::Signed
                    },
                    None,
                )
            })
            .collect();
        let mut state = MigrationState::from_parts(
            EngineStatus::InProgress,
            split,
            PreparationPlan::from_parts(Vec::new(), Vec::new()),
            transactions,
        );

        let message = reschedule_overdue(&mut state, MigrationTxId::new(0), tip).unwrap();

        assert_eq!(message, None);
        let remaining = &state.transactions()[1..];
        assert!(remaining
            .iter()
            .all(|transaction| transaction.scheduled_height() > tip));
        let mut heights = remaining
            .iter()
            .map(MigrationTransaction::scheduled_height)
            .collect::<Vec<_>>();
        heights.sort_unstable();
        assert!(heights.windows(2).all(|pair| pair[0] < pair[1]));
        assert!(remaining.iter().all(|transaction| {
            scheduling::expiry_height(transaction.scheduled_height()) == transaction.expiry_height()
        }));
    }
}
