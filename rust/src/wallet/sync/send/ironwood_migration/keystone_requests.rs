struct PreparedSoftwareMigrationRun {
    plan: super::migration::DenominationPlan,
    prepared_refs: Vec<super::migration::PreparedOrchardNoteRef>,
    denomination_stages: Vec<super::migration::DenominationStageInsert>,
    signed_children: Vec<super::migration::SignedMigrationPcztInsert>,
    fee_zatoshi: u64,
    total_migratable_zatoshi: u64,
}

#[derive(Clone)]
struct PredictedMigrationNote {
    txid_hex: String,
    output_index: u32,
    value_zatoshi: u64,
    note: orchard::Note,
}

struct BuiltPczt {
    bytes: Vec<u8>,
    redacted_bytes: Vec<u8>,
    orchard_spend_action_indices: Vec<usize>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum KeystoneMigrationRequestState {
    Proofing,
    ProofReady,
    ProofFailed,
    Completing,
}

#[derive(Clone)]
struct CreatedDenominationStagePczt {
    id: String,
    base_pczt: Vec<u8>,
    orchard_spend_action_indices: Vec<usize>,
    redacted_pczt: Vec<u8>,
    pczt_with_proofs: Option<Vec<u8>>,
    expected_txid_hex: String,
    target_height: u32,
    expiry_height: u32,
    fee_zatoshi: u64,
    deferred: bool,
    inputs: Vec<super::migration::DenominationStageInputRef>,
    outputs: Vec<super::migration::DenominationStageOutputRef>,
}

struct CreatedPaddedDenominationPczts {
    stages: Vec<CreatedDenominationStagePczt>,
    predicted_notes: Vec<PredictedMigrationNote>,
    total_migratable_zatoshi: u64,
    plan: super::migration::DenominationPlan,
}

struct StoredDenominationPczt {
    account_uuid: String,
    network: WalletNetwork,
    state: KeystoneMigrationRequestState,
    proof_error: Option<String>,
    split_stages: Vec<CreatedDenominationStagePczt>,
    total_migratable_zatoshi: u64,
    plan: super::migration::DenominationPlan,
}

struct StoredDenominationCompletion {
    split_stages: Vec<CreatedDenominationStagePczt>,
    total_migratable_zatoshi: u64,
    plan: super::migration::DenominationPlan,
}

#[derive(Clone)]
struct CreatedMigrationPczt {
    part_index: u32,
    id: String,
    base_pczt: Vec<u8>,
    orchard_spend_action_indices: Vec<usize>,
    pczt_with_proofs: Option<Vec<u8>>,
    redacted_pczt: Vec<u8>,
    target_height: u32,
    anchor_boundary_height: Option<u32>,
    expiry_height: u32,
    fee_zatoshi: u64,
    migrated_zatoshi: u64,
    selected_note: super::migration::PreparedOrchardNoteRef,
}

struct StoredMigrationPcztBatch {
    account_uuid: String,
    network: WalletNetwork,
    run_id: String,
    fallback_total_count: u32,
    fallback_migrated_zatoshi: u64,
    recovery_old_txids: Vec<String>,
    state: KeystoneMigrationRequestState,
    proof_error: Option<String>,
    messages: Vec<CreatedMigrationPczt>,
}

struct StoredMigrationBatchCompletion {
    run_id: String,
    fallback_total_count: u32,
    fallback_migrated_zatoshi: u64,
    recovery_old_txids: Vec<String>,
    messages: Vec<CreatedMigrationPczt>,
}

struct StoredSingleQrMigrationPczt {
    account_uuid: String,
    network: WalletNetwork,
    state: KeystoneMigrationRequestState,
    proof_error: Option<String>,
    split_stages: Vec<CreatedDenominationStagePczt>,
    total_migratable_zatoshi: u64,
    plan: super::migration::DenominationPlan,
    child_messages: Vec<CreatedMigrationPczt>,
}

struct StoredSingleQrMigrationCompletion {
    split_stages: Vec<CreatedDenominationStagePczt>,
    total_migratable_zatoshi: u64,
    plan: super::migration::DenominationPlan,
    child_messages: Vec<CreatedMigrationPczt>,
}

fn new_keystone_migration_request_id(label: &str) -> String {
    let nonce: u64 = OsRng.gen();
    format!("ironwood-migration-{label}-{nonce:016x}")
}

fn keystone_denomination_requests() -> &'static Mutex<HashMap<String, StoredDenominationPczt>> {
    KEYSTONE_DENOMINATION_REQUESTS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn keystone_migration_requests() -> &'static Mutex<HashMap<String, StoredMigrationPcztBatch>> {
    KEYSTONE_MIGRATION_REQUESTS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn keystone_single_qr_migration_requests(
) -> &'static Mutex<HashMap<String, StoredSingleQrMigrationPczt>> {
    KEYSTONE_SINGLE_QR_MIGRATION_REQUESTS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn prune_failed_denomination_requests(
    store: &mut HashMap<String, StoredDenominationPczt>,
    account_uuid: &str,
    network: WalletNetwork,
) {
    store.retain(|_, stored| {
        !(stored.account_uuid == account_uuid
            && stored.network == network
            && stored.state == KeystoneMigrationRequestState::ProofFailed)
    });
}

fn ensure_no_live_denomination_request(
    store: &mut HashMap<String, StoredDenominationPczt>,
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<(), String> {
    prune_failed_denomination_requests(store, account_uuid, network);
    if store
        .values()
        .any(|stored| stored.account_uuid == account_uuid && stored.network == network)
    {
        return Err(
            "A Keystone denomination request is already in progress. Reject it before preparing a new one."
                .to_string(),
        );
    }
    Ok(())
}

fn prune_failed_single_qr_migration_requests(
    store: &mut HashMap<String, StoredSingleQrMigrationPczt>,
    account_uuid: &str,
    network: WalletNetwork,
) {
    store.retain(|_, stored| {
        !(stored.account_uuid == account_uuid
            && stored.network == network
            && stored.state == KeystoneMigrationRequestState::ProofFailed)
    });
}

fn ensure_no_live_single_qr_migration_request(
    store: &mut HashMap<String, StoredSingleQrMigrationPczt>,
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<(), String> {
    prune_failed_single_qr_migration_requests(store, account_uuid, network);
    if store
        .values()
        .any(|stored| stored.account_uuid == account_uuid && stored.network == network)
    {
        return Err(
            "A Keystone migration request is already in progress. Reject it before preparing a new one."
                .to_string(),
        );
    }
    Ok(())
}

fn prune_failed_migration_requests(
    store: &mut HashMap<String, StoredMigrationPcztBatch>,
    account_uuid: &str,
    network: WalletNetwork,
    run_id: &str,
) {
    store.retain(|_, stored| {
        !(stored.account_uuid == account_uuid
            && stored.network == network
            && stored.run_id == run_id
            && stored.state == KeystoneMigrationRequestState::ProofFailed)
    });
}

fn ensure_no_live_migration_request(
    store: &mut HashMap<String, StoredMigrationPcztBatch>,
    account_uuid: &str,
    network: WalletNetwork,
    run_id: &str,
) -> Result<(), String> {
    prune_failed_migration_requests(store, account_uuid, network, run_id);
    if store.values().any(|stored| {
        stored.account_uuid == account_uuid && stored.network == network && stored.run_id == run_id
    }) {
        return Err(
            "A Keystone migration request is already in progress. Reject it before preparing a new one."
                .to_string(),
        );
    }
    Ok(())
}

fn validate_keystone_migration_messages(
    messages: &[KeystoneMigrationMessage],
) -> Result<(), String> {
    if messages.is_empty() {
        return Err("Keystone migration request has no messages".to_string());
    }
    if messages.len() > ZCASH_SIGN_BATCH_MAX_MESSAGES {
        return Err(format!(
            "Keystone migration signing supports at most {ZCASH_SIGN_BATCH_MAX_MESSAGES} PCZTs per round, but this round needs {}.",
            messages.len()
        ));
    }
    let mut ids = HashSet::with_capacity(messages.len());
    let mut payloads = HashSet::with_capacity(messages.len());
    for message in messages {
        if message.id.is_empty() {
            return Err("Keystone migration message id is empty".to_string());
        }
        if message.redacted_pczt.is_empty() {
            return Err(format!(
                "Keystone migration message {} has an empty PCZT payload",
                message.id
            ));
        }
        if !ids.insert(message.id.as_bytes().to_vec()) {
            return Err(format!(
                "Duplicate Keystone migration message id {}",
                message.id
            ));
        }
        if !payloads.insert(message.redacted_pczt.clone()) {
            return Err("Duplicate Keystone migration PCZT payload".to_string());
        }
    }
    Ok(())
}

pub(crate) fn keystone_migration_proof_status(
    request_id: &str,
) -> Result<KeystoneMigrationProofStatus, String> {
    if let Some(status) = keystone_single_qr_migration_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone single QR request store: {e}"))?
        .get(request_id)
        .map(|stored| {
            let roots = stored
                .split_stages
                .iter()
                .filter(|stage| !stage.deferred)
                .collect::<Vec<_>>();
            proof_status_from_counts(
                roots
                    .iter()
                    .filter(|stage| stage.pczt_with_proofs.is_some())
                    .count(),
                roots.len(),
                stored.state,
                stored.proof_error.clone(),
            )
        })
    {
        return Ok(status);
    }

    if let Some(status) = keystone_denomination_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone denomination request store: {e}"))?
        .get(request_id)
        .map(|stored| {
            let roots = stored
                .split_stages
                .iter()
                .filter(|stage| !stage.deferred)
                .collect::<Vec<_>>();
            proof_status_from_counts(
                roots
                    .iter()
                    .filter(|stage| stage.pczt_with_proofs.is_some())
                    .count(),
                roots.len(),
                stored.state,
                stored.proof_error.clone(),
            )
        })
    {
        return Ok(status);
    }

    keystone_migration_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone migration request store: {e}"))?
        .get(request_id)
        .map(|stored| {
            let ready_count = stored
                .messages
                .iter()
                .filter(|message| message.pczt_with_proofs.is_some())
                .count();
            proof_status_from_counts(
                ready_count,
                stored.messages.len(),
                stored.state,
                stored.proof_error.clone(),
            )
        })
        .ok_or_else(|| format!("Keystone migration request {request_id} was not found"))
}

pub(crate) fn discard_keystone_migration_request(request_id: &str) -> Result<(), String> {
    {
        let mut store = keystone_single_qr_migration_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone single QR request store: {e}"))?;
        if store
            .get(request_id)
            .is_some_and(|stored| stored.state == KeystoneMigrationRequestState::Completing)
        {
            return Ok(());
        }
        if store.remove(request_id).is_some() {
            return Ok(());
        }
    }

    {
        let mut store = keystone_denomination_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone denomination request store: {e}"))?;
        if store
            .get(request_id)
            .is_some_and(|stored| stored.state == KeystoneMigrationRequestState::Completing)
        {
            return Ok(());
        }
        if store.remove(request_id).is_some() {
            return Ok(());
        }
    }

    let mut store = keystone_migration_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone migration request store: {e}"))?;
    if store
        .get(request_id)
        .is_some_and(|stored| stored.state == KeystoneMigrationRequestState::Completing)
    {
        return Ok(());
    }
    store.remove(request_id);
    Ok(())
}

pub(crate) fn discard_keystone_migration_requests_for_account(
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<(), String> {
    keystone_single_qr_migration_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone single QR request store: {e}"))?
        .retain(|_, stored| stored.account_uuid != account_uuid || stored.network != network);
    keystone_denomination_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone denomination request store: {e}"))?
        .retain(|_, stored| stored.account_uuid != account_uuid || stored.network != network);
    keystone_migration_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone migration request store: {e}"))?
        .retain(|_, stored| stored.account_uuid != account_uuid || stored.network != network);
    Ok(())
}

pub(crate) fn discard_all_keystone_migration_requests() -> Result<(), String> {
    keystone_single_qr_migration_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone single QR request store: {e}"))?
        .clear();
    keystone_denomination_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone denomination request store: {e}"))?
        .clear();
    keystone_migration_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone migration request store: {e}"))?
        .clear();
    Ok(())
}

fn proof_status_from_counts(
    ready_count: usize,
    total_count: usize,
    state: KeystoneMigrationRequestState,
    message: Option<String>,
) -> KeystoneMigrationProofStatus {
    KeystoneMigrationProofStatus {
        ready_count: ready_count as u32,
        total_count: total_count as u32,
        is_ready: state == KeystoneMigrationRequestState::ProofReady,
        is_failed: state == KeystoneMigrationRequestState::ProofFailed,
        message,
    }
}

fn spawn_denomination_proof_worker(request_id: String, roots: Vec<(String, Vec<u8>)>) {
    let builder = thread::Builder::new().name("keystone-denomination-proof".to_string());
    let worker_request_id = request_id.clone();
    if let Err(e) = builder.spawn(move || {
        let total = roots.len();
        let started = Instant::now();
        log::info!("migration proofs: denomination started for {total} split roots");
        for (index, (id, base_pczt)) in roots.into_iter().enumerate() {
            let proof_started = Instant::now();
            let result = super::pczt::add_proofs_to_pczt(&base_pczt, None, None);
            let mut store = match keystone_denomination_requests().lock() {
                Ok(store) => store,
                Err(e) => {
                    log::error!("migration proofs: denomination store lock failed: {e}");
                    return;
                }
            };
            let Some(stored) = store.get_mut(&worker_request_id) else {
                log::info!("migration proofs: denomination request was discarded");
                return;
            };
            if stored.state == KeystoneMigrationRequestState::Completing {
                return;
            }
            match result {
                Ok(pczt_with_proofs) => {
                    let Some(stage) = stored.split_stages.iter_mut().find(|stage| stage.id == id)
                    else {
                        stored.proof_error = Some(format!("Missing split root {id}"));
                        stored.state = KeystoneMigrationRequestState::ProofFailed;
                        return;
                    };
                    stage.pczt_with_proofs = Some(pczt_with_proofs);
                    log::info!(
                        "migration proofs: denomination root {}/{} ready in {}ms",
                        index + 1,
                        total,
                        proof_started.elapsed().as_millis()
                    );
                }
                Err(e) => {
                    stored.proof_error = Some(e);
                    stored.state = KeystoneMigrationRequestState::ProofFailed;
                    log::warn!(
                        "migration proofs: denomination root {}/{} failed after {}ms",
                        index + 1,
                        total,
                        proof_started.elapsed().as_millis()
                    );
                    return;
                }
            }
        }

        let mut store = match keystone_denomination_requests().lock() {
            Ok(store) => store,
            Err(e) => {
                log::error!("migration proofs: denomination store lock failed: {e}");
                return;
            }
        };
        if let Some(stored) = store.get_mut(&worker_request_id) {
            if stored.state != KeystoneMigrationRequestState::Completing {
                stored.state = KeystoneMigrationRequestState::ProofReady;
                log::info!(
                    "migration proofs: all denomination roots ready in {}ms",
                    started.elapsed().as_millis()
                );
            }
        }
    }) {
        log::error!("migration proofs: failed to start denomination proof worker: {e}");
        if let Ok(mut store) = keystone_denomination_requests().lock() {
            if let Some(stored) = store.get_mut(&request_id) {
                stored.state = KeystoneMigrationRequestState::ProofFailed;
                stored.proof_error = Some(format!("Start proof worker: {e}"));
            }
        }
    }
}

fn spawn_single_qr_split_proof_worker(request_id: String, roots: Vec<(String, Vec<u8>)>) {
    let builder = thread::Builder::new().name("keystone-single-qr-split-proof".to_string());
    let worker_request_id = request_id.clone();
    if let Err(e) = builder.spawn(move || {
        let total = roots.len();
        let started = Instant::now();
        log::info!("migration proofs: single QR started for {total} split roots");
        for (index, (id, base_pczt)) in roots.into_iter().enumerate() {
            let proof_started = Instant::now();
            let result = super::pczt::add_proofs_to_pczt(&base_pczt, None, None);
            let mut store = match keystone_single_qr_migration_requests().lock() {
                Ok(store) => store,
                Err(e) => {
                    log::error!("migration proofs: single QR store lock failed: {e}");
                    return;
                }
            };
            let Some(stored) = store.get_mut(&worker_request_id) else {
                log::info!("migration proofs: single QR request was discarded");
                return;
            };
            if stored.state == KeystoneMigrationRequestState::Completing {
                return;
            }
            match result {
                Ok(pczt_with_proofs) => {
                    let Some(stage) = stored.split_stages.iter_mut().find(|stage| stage.id == id)
                    else {
                        stored.proof_error = Some(format!("Missing split root {id}"));
                        stored.state = KeystoneMigrationRequestState::ProofFailed;
                        return;
                    };
                    stage.pczt_with_proofs = Some(pczt_with_proofs);
                    log::info!(
                        "migration proofs: split root {}/{} ready in {}ms",
                        index + 1,
                        total,
                        proof_started.elapsed().as_millis()
                    );
                }
                Err(e) => {
                    stored.proof_error = Some(e);
                    stored.state = KeystoneMigrationRequestState::ProofFailed;
                    log::warn!(
                        "migration proofs: split root {}/{} failed after {}ms",
                        index + 1,
                        total,
                        proof_started.elapsed().as_millis()
                    );
                    return;
                }
            }
        }

        let mut store = match keystone_single_qr_migration_requests().lock() {
            Ok(store) => store,
            Err(e) => {
                log::error!("migration proofs: single QR store lock failed: {e}");
                return;
            }
        };
        if let Some(stored) = store.get_mut(&worker_request_id) {
            if stored.state != KeystoneMigrationRequestState::Completing {
                stored.state = KeystoneMigrationRequestState::ProofReady;
                log::info!(
                    "migration proofs: all split roots ready in {}ms",
                    started.elapsed().as_millis()
                );
            }
        }
    }) {
        log::error!("migration proofs: failed to start single QR split proof worker: {e}");
        if let Ok(mut store) = keystone_single_qr_migration_requests().lock() {
            if let Some(stored) = store.get_mut(&request_id) {
                stored.state = KeystoneMigrationRequestState::ProofFailed;
                stored.proof_error = Some(format!("Start proof worker: {e}"));
            }
        }
    }
}

fn spawn_migration_proof_worker(request_id: String, messages: Vec<(String, Vec<u8>)>) {
    let builder = thread::Builder::new().name("keystone-migration-proofs".to_string());
    let worker_request_id = request_id.clone();
    if let Err(e) = builder.spawn(move || {
        let total = messages.len();
        let started = Instant::now();
        log::info!("migration proofs: batch proof worker started for {total} messages");

        for (index, (id, base_pczt)) in messages.into_iter().enumerate() {
            {
                let store = match keystone_migration_requests().lock() {
                    Ok(store) => store,
                    Err(e) => {
                        log::error!("migration proofs: migration store lock failed: {e}");
                        return;
                    }
                };
                if !store.contains_key(&worker_request_id) {
                    log::info!("migration proofs: migration request was discarded");
                    return;
                }
            }

            let proof_started = Instant::now();
            let result = super::pczt::add_proofs_to_pczt(&base_pczt, None, None);
            let mut store = match keystone_migration_requests().lock() {
                Ok(store) => store,
                Err(e) => {
                    log::error!("migration proofs: migration store lock failed: {e}");
                    return;
                }
            };
            let Some(stored) = store.get_mut(&worker_request_id) else {
                return;
            };
            if stored.state == KeystoneMigrationRequestState::Completing {
                return;
            }
            match result {
                Ok(pczt_with_proofs) => {
                    if let Some(message) = stored.messages.iter_mut().find(|m| m.id == id) {
                        message.pczt_with_proofs = Some(pczt_with_proofs);
                    }
                    log::info!(
                        "migration proofs: batch message {}/{} ready in {}ms",
                        index + 1,
                        total,
                        proof_started.elapsed().as_millis()
                    );
                }
                Err(e) => {
                    stored.state = KeystoneMigrationRequestState::ProofFailed;
                    stored.proof_error = Some(e);
                    log::warn!(
                        "migration proofs: batch message {}/{} failed after {}ms",
                        index + 1,
                        total,
                        proof_started.elapsed().as_millis()
                    );
                    return;
                }
            }
        }

        let mut store = match keystone_migration_requests().lock() {
            Ok(store) => store,
            Err(e) => {
                log::error!("migration proofs: migration store lock failed: {e}");
                return;
            }
        };
        if let Some(stored) = store.get_mut(&worker_request_id) {
            if stored.state != KeystoneMigrationRequestState::Completing {
                stored.state = KeystoneMigrationRequestState::ProofReady;
                log::info!(
                    "migration proofs: batch proofs ready in {}ms",
                    started.elapsed().as_millis()
                );
            }
        }
    }) {
        log::error!("migration proofs: failed to start batch proof worker: {e}");
        if let Ok(mut store) = keystone_migration_requests().lock() {
            if let Some(stored) = store.get_mut(&request_id) {
                stored.state = KeystoneMigrationRequestState::ProofFailed;
                stored.proof_error = Some(format!("Start proof worker: {e}"));
            }
        }
    }
}

fn reset_migration_request_after_failed_completion(request_id: &str) {
    if let Ok(mut store) = keystone_migration_requests().lock() {
        if let Some(stored) = store.get_mut(request_id) {
            if stored.state == KeystoneMigrationRequestState::Completing {
                stored.state = KeystoneMigrationRequestState::ProofReady;
            }
        }
    }
}

fn reset_denomination_request_after_failed_completion(request_id: &str) {
    if let Ok(mut store) = keystone_denomination_requests().lock() {
        if let Some(stored) = store.get_mut(request_id) {
            if stored.state == KeystoneMigrationRequestState::Completing {
                stored.state = KeystoneMigrationRequestState::ProofReady;
            }
        }
    }
}

fn reset_single_qr_request_after_failed_completion(request_id: &str) {
    if let Ok(mut store) = keystone_single_qr_migration_requests().lock() {
        if let Some(stored) = store.get_mut(request_id) {
            if stored.state == KeystoneMigrationRequestState::Completing {
                stored.state = KeystoneMigrationRequestState::ProofReady;
            }
        }
    }
}

fn signed_migration_messages_by_id(
    request_id: &str,
    signed_messages: Vec<KeystoneSignedMigrationMessage>,
) -> Result<HashMap<String, Vec<pczt::roles::signer::SpendAuthSignature>>, String> {
    if signed_messages.is_empty() {
        return Err(format!(
            "Keystone returned no signed messages for request {request_id}"
        ));
    }

    let mut by_id = HashMap::with_capacity(signed_messages.len());
    for message in signed_messages {
        if message.id.is_empty() {
            return Err("Keystone signed message id is empty".to_string());
        }
        if message.sigs.is_empty() {
            return Err(format!(
                "Keystone signed message {} carried no signatures",
                message.id
            ));
        }
        if by_id.insert(message.id.clone(), message.sigs).is_some() {
            return Err(format!("Duplicate signed Keystone message {}", message.id));
        }
    }

    Ok(by_id)
}
