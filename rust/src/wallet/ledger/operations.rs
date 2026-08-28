use std::{
    collections::HashSet,
    sync::{Mutex, OnceLock},
    time::{SystemTime, UNIX_EPOCH},
};

use rusqlite::{params, OptionalExtension};

use crate::wallet::{
    db::{open_wallet_raw_conn_with_timeout, with_wallet_db_write_lock, WALLET_DB_BUSY_TIMEOUT},
    network::WalletNetwork,
};

const TABLE: &str = "vizor_ledger_signed_operations";
const PCZT_BATCH_MAGIC: &[u8; 4] = b"VLB1";
const STATE_SIGNED_PENDING_BROADCAST: &str = "signed_pending_broadcast";
const STATE_RESULT_PENDING_ACK: &str = "result_pending_ack";
static ACTIVE_BROADCASTS: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct SignedOperationMetadata {
    pub operation_id: String,
    pub account_uuid: String,
    pub kind: String,
    pub external_ref: Option<String>,
    pub expiry_height: Option<u32>,
    pub state: String,
    pub txid: Option<String>,
    pub status: Option<String>,
    pub message: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct BroadcastResult {
    pub operation_id: String,
    pub txid: String,
    pub status: String,
    pub message: Option<String>,
    pub requires_ack: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum OperationKind {
    Send,
    SwapDeposit,
    PayDeposit,
    Shield,
}

impl OperationKind {
    fn parse(value: &str) -> Result<Self, String> {
        match value {
            "send" => Ok(Self::Send),
            "swap_deposit" => Ok(Self::SwapDeposit),
            "pay_deposit" => Ok(Self::PayDeposit),
            "shield" => Ok(Self::Shield),
            _ => Err(
                "Ledger operation kind must be send, swap_deposit, pay_deposit, or shield".into(),
            ),
        }
    }

    fn requires_ack(self) -> bool {
        matches!(self, Self::SwapDeposit | Self::PayDeposit)
    }
}

struct StoredOperation {
    kind: OperationKind,
    proof_pczts: Vec<Vec<u8>>,
    signature_pczts: Vec<Vec<u8>>,
}

struct BroadcastGuard {
    key: String,
}

impl BroadcastGuard {
    fn acquire(db_path: &str, network: WalletNetwork, operation_id: &str) -> Result<Self, String> {
        let key = format!("{db_path}\0{}\0{operation_id}", network_name(network));
        let mut active = ACTIVE_BROADCASTS
            .get_or_init(|| Mutex::new(HashSet::new()))
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if !active.insert(key.clone()) {
            return Err(format!(
                "Ledger operation {operation_id} is already being broadcast"
            ));
        }
        Ok(Self { key })
    }
}

impl Drop for BroadcastGuard {
    fn drop(&mut self) {
        ACTIVE_BROADCASTS
            .get_or_init(|| Mutex::new(HashSet::new()))
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .remove(&self.key);
    }
}

pub(crate) fn checkpoint(
    db_path: &str,
    network: WalletNetwork,
    operation_id: &str,
    account_uuid: &str,
    kind: &str,
    external_ref: Option<&str>,
    proof_pczt: &[u8],
    signature_pczt: &[u8],
) -> Result<SignedOperationMetadata, String> {
    checkpoint_batch(
        db_path,
        network,
        operation_id,
        account_uuid,
        kind,
        external_ref,
        &[proof_pczt.to_vec()],
        &[signature_pczt.to_vec()],
    )
}

pub(crate) fn checkpoint_batch(
    db_path: &str,
    network: WalletNetwork,
    operation_id: &str,
    account_uuid: &str,
    kind: &str,
    external_ref: Option<&str>,
    proof_pczts: &[Vec<u8>],
    signature_pczts: &[Vec<u8>],
) -> Result<SignedOperationMetadata, String> {
    validate_identifier("operation ID", operation_id)?;
    validate_identifier("account UUID", account_uuid)?;
    let operation_kind = OperationKind::parse(kind)?;
    validate_external_ref(operation_kind, external_ref)?;
    let expiry_height = validated_expiry_height(proof_pczts, signature_pczts)?;
    crate::wallet::sync::validate_signed_pczts(proof_pczts, signature_pczts, None, None)
        .map_err(|error| format!("Validate Ledger signed checkpoint: {error}"))?;
    let proof_pczt = encode_pczt_batch(proof_pczts)?;
    let signature_pczt = encode_pczt_batch(signature_pczts)?;
    let now = now_ms()?;
    let network = network_name(network);

    with_wallet_db_write_lock("ledger.operations.checkpoint", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, WALLET_DB_BUSY_TIMEOUT)?;
        ensure_table(&conn)?;
        let inserted = conn
            .execute(
                &format!(
                    "INSERT INTO {TABLE} (
                    network, operation_id, account_uuid, kind, external_ref,
                    proof_pczt, signature_pczt, expiry_height, state,
                    txid, status, message, created_at_ms, updated_at_ms
                 ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, NULL, NULL, NULL, ?10, ?10)
                 ON CONFLICT(network, operation_id) DO NOTHING"
                ),
                params![
                    network,
                    operation_id,
                    account_uuid,
                    kind,
                    external_ref,
                    &proof_pczt,
                    &signature_pczt,
                    expiry_height.map(i64::from),
                    STATE_SIGNED_PENDING_BROADCAST,
                    now,
                ],
            )
            .map_err(|error| format!("Checkpoint Ledger signed operation: {error}"))?;
        if inserted == 0 {
            let exact_match: bool = conn
                .query_row(
                    &format!(
                        "SELECT EXISTS(
                            SELECT 1 FROM {TABLE}
                            WHERE network = ?1 AND operation_id = ?2
                              AND account_uuid = ?3 AND kind = ?4
                              AND external_ref IS ?5
                              AND proof_pczt = ?6 AND signature_pczt = ?7
                              AND expiry_height IS ?8
                        )"
                    ),
                    params![
                        network,
                        operation_id,
                        account_uuid,
                        kind,
                        external_ref,
                        &proof_pczt,
                        &signature_pczt,
                        expiry_height.map(i64::from),
                    ],
                    |row| row.get(0),
                )
                .map_err(|e| format!("Verify repeated Ledger checkpoint: {e}"))?;
            if !exact_match {
                return Err(format!(
                    "Ledger operation {operation_id} is already checkpointed with different data"
                ));
            }
        }
        load_metadata(&conn, network, operation_id)?.ok_or_else(|| {
            format!("Ledger operation {operation_id} was not found after checkpointing")
        })
    })
}

pub(crate) fn list(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: Option<&str>,
) -> Result<Vec<SignedOperationMetadata>, String> {
    if let Some(account_uuid) = account_uuid {
        validate_identifier("account UUID", account_uuid)?;
    }
    let network = network_name(network);
    with_wallet_db_write_lock("ledger.operations.list", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, WALLET_DB_BUSY_TIMEOUT)?;
        ensure_table(&conn)?;
        let sql = format!(
            "SELECT operation_id, account_uuid, kind, external_ref, expiry_height,
                    state, txid, status, message, created_at_ms, updated_at_ms
             FROM {TABLE}
             WHERE network = ?1 AND (?2 IS NULL OR account_uuid = ?2)
             ORDER BY created_at_ms, operation_id"
        );
        let mut statement = conn
            .prepare(&sql)
            .map_err(|e| format!("Prepare Ledger operation list: {e}"))?;
        let rows = statement
            .query_map(params![network, account_uuid], metadata_from_row)
            .map_err(|e| format!("Query Ledger operations: {e}"))?;
        rows.collect::<rusqlite::Result<Vec<_>>>()
            .map_err(|e| format!("Read Ledger operation metadata: {e}"))
    })
}

pub(crate) async fn broadcast(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    operation_id: &str,
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<BroadcastResult, String> {
    validate_identifier("operation ID", operation_id)?;
    let _broadcast_guard = BroadcastGuard::acquire(db_path, network, operation_id)?;
    let stored = load_for_broadcast(db_path, network, operation_id)?;
    let result = crate::wallet::sync::store_and_broadcast_signed_pczts(
        db_path,
        lightwalletd_url,
        network,
        &stored.proof_pczts,
        &stored.signature_pczts,
        spend_params_path,
        output_params_path,
    )
    .await;

    match result {
        Ok(result) => apply_broadcast_outcome(
            db_path,
            network,
            operation_id,
            stored.kind,
            &result.txids,
            &result.status,
            result.message.as_deref(),
        ),
        Err(error) => {
            if record_broadcast_failure(db_path, network, operation_id, &error)? {
                Err(format!(
                    "Ledger signed operation cannot be retried: {error}"
                ))
            } else {
                Err(error)
            }
        }
    }
}

pub(crate) fn delete_for_account_with_tx(
    tx: &rusqlite::Transaction<'_>,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<usize, String> {
    let table_exists: bool = tx
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1)",
            [TABLE],
            |row| row.get(0),
        )
        .map_err(|error| format!("Check Ledger signed-operation outbox: {error}"))?;
    if !table_exists {
        return Ok(0);
    }

    tx.execute(
        &format!("DELETE FROM {TABLE} WHERE network = ?1 AND account_uuid = ?2"),
        params![network_name(network), account_uuid],
    )
    .map_err(|error| format!("Delete Ledger signed operations for account: {error}"))
}

pub(crate) fn acknowledge(
    db_path: &str,
    network: WalletNetwork,
    operation_id: &str,
) -> Result<(), String> {
    validate_identifier("operation ID", operation_id)?;
    let network = network_name(network);
    with_wallet_db_write_lock("ledger.operations.acknowledge", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, WALLET_DB_BUSY_TIMEOUT)?;
        ensure_table(&conn)?;
        let deleted = conn
            .execute(
                &format!(
                    "DELETE FROM {TABLE}
                     WHERE network = ?1 AND operation_id = ?2 AND state = ?3"
                ),
                params![network, operation_id, STATE_RESULT_PENDING_ACK],
            )
            .map_err(|e| format!("Acknowledge Ledger operation: {e}"))?;
        if deleted == 1 {
            Ok(())
        } else {
            Err(format!(
                "Ledger operation {operation_id} has no broadcast result awaiting acknowledgment"
            ))
        }
    })
}

fn load_for_broadcast(
    db_path: &str,
    network: WalletNetwork,
    operation_id: &str,
) -> Result<StoredOperation, String> {
    let network = network_name(network);
    with_wallet_db_write_lock("ledger.operations.load_for_broadcast", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, WALLET_DB_BUSY_TIMEOUT)?;
        ensure_table(&conn)?;
        conn.query_row(
            &format!(
                "SELECT kind, proof_pczt, signature_pczt
                 FROM {TABLE}
                 WHERE network = ?1 AND operation_id = ?2 AND state = ?3"
            ),
            params![network, operation_id, STATE_SIGNED_PENDING_BROADCAST],
            |row| {
                let kind: String = row.get(0)?;
                let proof_pczt: Vec<u8> = row.get(1)?;
                let signature_pczt: Vec<u8> = row.get(2)?;
                Ok((kind, proof_pczt, signature_pczt))
            },
        )
        .optional()
        .map_err(|e| format!("Load Ledger operation for broadcast: {e}"))?
        .ok_or_else(|| {
            format!("Ledger operation {operation_id} is not pending broadcast on {network}")
        })
        .and_then(|(kind, proof_pczt, signature_pczt)| {
            Ok(StoredOperation {
                kind: OperationKind::parse(&kind)?,
                proof_pczts: decode_pczt_batch(&proof_pczt)?,
                signature_pczts: decode_pczt_batch(&signature_pczt)?,
            })
        })
    })
}

fn apply_broadcast_outcome(
    db_path: &str,
    network: WalletNetwork,
    operation_id: &str,
    kind: OperationKind,
    txid: &str,
    status: &str,
    message: Option<&str>,
) -> Result<BroadcastResult, String> {
    let clean_terminal = status == "broadcasted" && !kind.requires_ack();
    let network = network_name(network);
    let now = now_ms()?;
    with_wallet_db_write_lock("ledger.operations.record_broadcast", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, WALLET_DB_BUSY_TIMEOUT)?;
        ensure_table(&conn)?;
        let changed = if clean_terminal {
            conn.execute(
                &format!("DELETE FROM {TABLE} WHERE network = ?1 AND operation_id = ?2"),
                params![network, operation_id],
            )
            .map_err(|e| format!("Complete Ledger operation: {e}"))?
        } else {
            conn.execute(
                &format!(
                    "UPDATE {TABLE}
                     SET state = ?3, txid = ?4, status = ?5, message = ?6, updated_at_ms = ?7
                     WHERE network = ?1 AND operation_id = ?2 AND state = ?8"
                ),
                params![
                    network,
                    operation_id,
                    STATE_RESULT_PENDING_ACK,
                    txid,
                    status,
                    message,
                    now,
                    STATE_SIGNED_PENDING_BROADCAST,
                ],
            )
            .map_err(|e| format!("Record Ledger broadcast result: {e}"))?
        };
        if changed != 1 {
            return Err(format!(
                "Ledger operation {operation_id} changed while its broadcast result was recorded"
            ));
        }
        Ok(BroadcastResult {
            operation_id: operation_id.to_string(),
            txid: txid.to_string(),
            status: status.to_string(),
            message: message.map(str::to_string),
            requires_ack: !clean_terminal,
        })
    })
}

fn record_broadcast_failure(
    db_path: &str,
    network: WalletNetwork,
    operation_id: &str,
    message: &str,
) -> Result<bool, String> {
    let network = network_name(network);
    let now = now_ms()?;
    with_wallet_db_write_lock("ledger.operations.record_failure", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, WALLET_DB_BUSY_TIMEOUT)?;
        ensure_table(&conn)?;
        if is_terminal_broadcast_failure(message) {
            conn.execute(
                &format!(
                    "DELETE FROM {TABLE}
                     WHERE network = ?1 AND operation_id = ?2 AND state = ?3"
                ),
                params![network, operation_id, STATE_SIGNED_PENDING_BROADCAST],
            )
            .map_err(|e| format!("Discard terminal Ledger operation: {e}"))?;
            return Ok(true);
        }
        conn.execute(
            &format!(
                "UPDATE {TABLE}
                 SET status = 'retryable_error', message = ?3, updated_at_ms = ?4
                 WHERE network = ?1 AND operation_id = ?2 AND state = ?5"
            ),
            params![
                network,
                operation_id,
                message,
                now,
                STATE_SIGNED_PENDING_BROADCAST
            ],
        )
        .map_err(|e| format!("Record Ledger broadcast failure: {e}"))?;
        Ok(false)
    })
}

fn is_terminal_broadcast_failure(message: &str) -> bool {
    let normalized = message.to_ascii_lowercase();
    normalized.contains("expired before broadcast") || normalized.contains("broadcast rejected")
}

fn validated_expiry_height(
    proof_pczts: &[Vec<u8>],
    signature_pczts: &[Vec<u8>],
) -> Result<Option<u32>, String> {
    if proof_pczts.is_empty() || proof_pczts.len() != signature_pczts.len() {
        return Err("Invalid Ledger signed PCZT round count".to_string());
    }
    let mut expiry_height = None;
    for (index, (proof_pczt, signature_pczt)) in proof_pczts.iter().zip(signature_pczts).enumerate()
    {
        let proof = pczt::Pczt::parse(proof_pczt).map_err(|e| {
            format!(
                "Parse proof PCZT round {} for Ledger checkpoint: {e:?}",
                index + 1
            )
        })?;
        let signature = pczt::Pczt::parse(signature_pczt).map_err(|e| {
            format!(
                "Parse signature PCZT round {} for Ledger checkpoint: {e:?}",
                index + 1
            )
        })?;
        let proof_expiry = *proof.global().expiry_height();
        let signature_expiry = *signature.global().expiry_height();
        if proof_expiry != signature_expiry {
            return Err(format!(
                "Ledger PCZT expiry mismatch in round {}: proof height {proof_expiry}, signature height {signature_expiry}",
                index + 1
            ));
        }
        if let Some(expected) = expiry_height {
            if proof_expiry != expected {
                return Err(format!(
                    "Ledger PCZT batch expiry mismatch: round 1 height {expected}, round {} height {proof_expiry}",
                    index + 1
                ));
            }
        } else {
            expiry_height = Some(proof_expiry);
        }
    }
    Ok(expiry_height.filter(|height| *height != 0))
}

fn encode_pczt_batch(pczts: &[Vec<u8>]) -> Result<Vec<u8>, String> {
    let count = u32::try_from(pczts.len()).map_err(|_| "Ledger PCZT batch is too large")?;
    let mut encoded = Vec::new();
    encoded.extend_from_slice(PCZT_BATCH_MAGIC);
    encoded.extend_from_slice(&count.to_le_bytes());
    for pczt in pczts {
        let len = u32::try_from(pczt.len()).map_err(|_| "Ledger PCZT is too large")?;
        encoded.extend_from_slice(&len.to_le_bytes());
        encoded.extend_from_slice(pczt);
    }
    Ok(encoded)
}

fn decode_pczt_batch(encoded: &[u8]) -> Result<Vec<Vec<u8>>, String> {
    if encoded.get(..4) != Some(PCZT_BATCH_MAGIC.as_slice()) {
        return Err("Ledger signed-operation batch has an invalid format".to_string());
    }
    let mut offset = 4;
    let count = read_batch_u32(encoded, &mut offset)? as usize;
    if count == 0 {
        return Err("Ledger signed-operation batch is empty".to_string());
    }
    if count > encoded.len().saturating_sub(offset) / 4 {
        return Err("Ledger signed-operation batch has an invalid round count".to_string());
    }
    let mut pczts = Vec::with_capacity(count);
    for _ in 0..count {
        let len = read_batch_u32(encoded, &mut offset)? as usize;
        let end = offset
            .checked_add(len)
            .filter(|end| *end <= encoded.len())
            .ok_or("Ledger signed-operation batch is truncated")?;
        pczts.push(encoded[offset..end].to_vec());
        offset = end;
    }
    if offset != encoded.len() {
        return Err("Ledger signed-operation batch has trailing data".to_string());
    }
    Ok(pczts)
}

fn read_batch_u32(encoded: &[u8], offset: &mut usize) -> Result<u32, String> {
    let end = offset
        .checked_add(4)
        .filter(|end| *end <= encoded.len())
        .ok_or("Ledger signed-operation batch is truncated")?;
    let value = u32::from_le_bytes(encoded[*offset..end].try_into().expect("four bytes"));
    *offset = end;
    Ok(value)
}

fn ensure_table(conn: &rusqlite::Connection) -> Result<(), String> {
    conn.execute_batch(&format!(
        "CREATE TABLE IF NOT EXISTS {TABLE} (
            network TEXT NOT NULL,
            operation_id TEXT NOT NULL,
            account_uuid TEXT NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('send', 'swap_deposit', 'pay_deposit', 'shield')),
            external_ref TEXT,
            proof_pczt BLOB NOT NULL,
            signature_pczt BLOB NOT NULL,
            expiry_height INTEGER,
            state TEXT NOT NULL CHECK(state IN ('signed_pending_broadcast', 'result_pending_ack')),
            txid TEXT,
            status TEXT,
            message TEXT,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL,
            PRIMARY KEY (network, operation_id)
        );
        CREATE INDEX IF NOT EXISTS vizor_ledger_signed_operations_account
            ON {TABLE}(network, account_uuid, created_at_ms);"
    ))
    .map_err(|e| format!("Initialize Ledger signed-operation outbox: {e}"))
}

fn load_metadata(
    conn: &rusqlite::Connection,
    network: &str,
    operation_id: &str,
) -> Result<Option<SignedOperationMetadata>, String> {
    conn.query_row(
        &format!(
            "SELECT operation_id, account_uuid, kind, external_ref, expiry_height,
                    state, txid, status, message, created_at_ms, updated_at_ms
             FROM {TABLE} WHERE network = ?1 AND operation_id = ?2"
        ),
        params![network, operation_id],
        metadata_from_row,
    )
    .optional()
    .map_err(|e| format!("Read Ledger operation metadata: {e}"))
}

fn metadata_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<SignedOperationMetadata> {
    let expiry_height: Option<i64> = row.get(4)?;
    Ok(SignedOperationMetadata {
        operation_id: row.get(0)?,
        account_uuid: row.get(1)?,
        kind: row.get(2)?,
        external_ref: row.get(3)?,
        expiry_height: expiry_height.map(u32::try_from).transpose().map_err(|e| {
            rusqlite::Error::FromSqlConversionFailure(
                4,
                rusqlite::types::Type::Integer,
                Box::new(e),
            )
        })?,
        state: row.get(5)?,
        txid: row.get(6)?,
        status: row.get(7)?,
        message: row.get(8)?,
        created_at_ms: row.get(9)?,
        updated_at_ms: row.get(10)?,
    })
}

fn validate_identifier(label: &str, value: &str) -> Result<(), String> {
    if value.trim().is_empty() {
        Err(format!("Ledger {label} must not be empty"))
    } else {
        Ok(())
    }
}

fn validate_external_ref(kind: OperationKind, external_ref: Option<&str>) -> Result<(), String> {
    match kind {
        OperationKind::SwapDeposit | OperationKind::PayDeposit => {
            if external_ref.is_some_and(|value| !value.trim().is_empty()) {
                Ok(())
            } else {
                Err(
                    "Ledger swap_deposit and pay_deposit operations require an external reference"
                        .into(),
                )
            }
        }
        OperationKind::Send | OperationKind::Shield => {
            if external_ref.is_none() {
                Ok(())
            } else {
                Err("Ledger send and shield operations must not have an external reference".into())
            }
        }
    }
}

fn network_name(network: WalletNetwork) -> &'static str {
    match network {
        WalletNetwork::Main => "main",
        WalletNetwork::Test => "test",
        WalletNetwork::Regtest => "regtest",
    }
}

fn now_ms() -> Result<i64, String> {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("Read clock for Ledger operation: {e}"))?
        .as_millis();
    i64::try_from(millis).map_err(|_| "Ledger operation timestamp exceeds SQLite range".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use pczt::roles::{
        creator::Creator, io_finalizer::IoFinalizer, signer::Signer, updater::Updater,
    };
    use transparent::{
        address::TransparentAddress,
        bundle::{OutPoint, TxOut},
    };
    use voting_crypto_deps::rand::rngs::OsRng;
    use zcash_primitives::transaction::{
        builder::{BuildConfig, Builder, BundlePadding, PcztResult},
        fees::zip317,
    };
    use zcash_protocol::{
        consensus::{BlockHeight, NetworkType, NetworkUpgrade, Parameters},
        value::Zatoshis,
    };

    #[derive(Clone, Copy, Debug)]
    struct TestNetwork;

    impl Parameters for TestNetwork {
        fn network_type(&self) -> NetworkType {
            NetworkType::Test
        }

        fn activation_height(&self, nu: NetworkUpgrade) -> Option<BlockHeight> {
            match nu {
                NetworkUpgrade::Nu6_3 => None,
                _ => Some(BlockHeight::from_u32(1)),
            }
        }
    }

    fn signed_pczt(target_height: u32) -> (Vec<u8>, Vec<u8>, u32) {
        let sk = secp256k1::SecretKey::from_slice(&[7; 32]).unwrap();
        let secp = secp256k1::Secp256k1::new();
        let pubkey = sk.public_key(&secp);
        let pubkey_bytes = pubkey.serialize();
        let address = TransparentAddress::from_pubkey(&pubkey);

        let mut builder = Builder::new(
            TestNetwork,
            target_height.into(),
            BuildConfig::Standard {
                sapling_anchor: None,
                orchard_anchor: None,
                ironwood_anchor: None,
                orchard_padding: BundlePadding::DEFAULT,
                ironwood_padding: BundlePadding::DEFAULT,
            },
        );
        builder
            .add_transparent_p2pkh_input(
                pubkey,
                OutPoint::new([1; 32], 0),
                TxOut::new(Zatoshis::const_from_u64(1_000_000), address.script().into()),
            )
            .unwrap();
        builder
            .add_transparent_output(&address, Zatoshis::const_from_u64(990_000))
            .unwrap();
        let PcztResult { pczt_parts, .. } = builder
            .build_for_pczt(OsRng, &zip317::FeeRule::standard())
            .unwrap();
        let proof = IoFinalizer::new(Creator::build_from_parts(pczt_parts).unwrap())
            .finalize_io()
            .unwrap();
        let derivation = transparent::pczt::Bip32Derivation::parse(
            [0x22; 32],
            vec![0x8000_002c, 0x8000_0001, 0x8000_0000, 0, 0],
        )
        .unwrap();
        let proof = Updater::new(proof)
            .update_transparent_with(|mut bundle| {
                bundle.update_input_with(0, |mut input| {
                    input.set_bip32_derivation(pubkey_bytes, derivation);
                    Ok(())
                })
            })
            .unwrap()
            .finish();
        let expiry_height = *proof.global().expiry_height();
        let proof_bytes = proof.serialize().unwrap();
        let parsed = super::super::parse_pczt(&proof_bytes).unwrap();
        let sighash = Signer::new(pczt::Pczt::parse(&proof_bytes).unwrap())
            .unwrap()
            .transparent_sighash(0)
            .unwrap();
        let signature = secp.sign_ecdsa(&secp256k1::Message::from_digest(sighash), &sk);
        let mut ledger_der = signature.serialize_der().to_vec();
        ledger_der[0] |= 1;
        let signature_bytes = super::super::apply_signatures(
            &proof_bytes,
            &parsed,
            &[super::super::TransparentInputSignature {
                signature: ledger_der,
                sighash_type: 1,
            }],
            &[],
        )
        .unwrap();
        (proof_bytes, signature_bytes, expiry_height)
    }

    fn checkpoint_test_operation(
        db_path: &str,
        operation_id: &str,
        kind: &str,
    ) -> SignedOperationMetadata {
        let (proof, signature, _) = signed_pczt(1_234_500);
        let external_ref = matches!(kind, "swap_deposit" | "pay_deposit").then_some("external-1");
        checkpoint(
            db_path,
            WalletNetwork::Main,
            operation_id,
            "account-1",
            kind,
            external_ref,
            &proof,
            &signature,
        )
        .unwrap()
    }

    #[test]
    fn checkpoint_roundtrip_lists_metadata_without_pczt_bytes() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let metadata = checkpoint_test_operation(file.path().to_str().unwrap(), "op-1", "send");
        assert_eq!(metadata.expiry_height, Some(signed_pczt(1_234_500).2));
        assert_eq!(metadata.state, STATE_SIGNED_PENDING_BROADCAST);

        let listed = list(
            file.path().to_str().unwrap(),
            WalletNetwork::Main,
            Some("account-1"),
        )
        .unwrap();
        assert_eq!(listed, vec![metadata]);

        let conn = rusqlite::Connection::open(file.path()).unwrap();
        let stored_lengths: (i64, i64) = conn
            .query_row(
                &format!(
                    "SELECT length(proof_pczt), length(signature_pczt) FROM {TABLE} WHERE operation_id = 'op-1'"
                ),
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert!(stored_lengths.0 > 0 && stored_lengths.1 > 0);
    }

    #[test]
    fn pczt_batch_encoding_preserves_round_boundaries_and_rejects_corruption() {
        let batch = vec![vec![1, 2, 3], vec![4, 5], vec![6]];
        let encoded = encode_pczt_batch(&batch).unwrap();
        assert_eq!(decode_pczt_batch(&encoded).unwrap(), batch);

        let mut truncated = encoded.clone();
        truncated.pop();
        assert!(decode_pczt_batch(&truncated)
            .unwrap_err()
            .contains("truncated"));

        let mut trailing = encoded;
        trailing.push(0);
        assert!(decode_pczt_batch(&trailing)
            .unwrap_err()
            .contains("trailing data"));

        let mut oversized_count = PCZT_BATCH_MAGIC.to_vec();
        oversized_count.extend_from_slice(&u32::MAX.to_le_bytes());
        assert!(decode_pczt_batch(&oversized_count)
            .unwrap_err()
            .contains("invalid round count"));
    }

    #[test]
    fn checkpoint_rejects_mismatched_pczt_expiry() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let (proof, _, _) = signed_pczt(100);
        let (_, signature, _) = signed_pczt(101);
        let error = checkpoint(
            file.path().to_str().unwrap(),
            WalletNetwork::Main,
            "op-1",
            "account-1",
            "send",
            None,
            &proof,
            &signature,
        )
        .unwrap_err();
        assert!(error.contains("expiry mismatch"));
    }

    #[test]
    fn checkpoint_is_idempotent_only_for_exactly_matching_data() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let db_path = file.path().to_str().unwrap();
        let first = checkpoint_test_operation(db_path, "op-1", "send");
        let second = checkpoint_test_operation(db_path, "op-1", "send");
        assert_eq!(second, first);

        let (different_proof, different_signature, _) = signed_pczt(1_234_501);
        let error = checkpoint(
            db_path,
            WalletNetwork::Main,
            "op-1",
            "account-1",
            "send",
            None,
            &different_proof,
            &different_signature,
        )
        .unwrap_err();
        assert!(error.contains("different data"));
        assert_eq!(list(db_path, WalletNetwork::Main, None).unwrap().len(), 1);
    }

    #[test]
    fn operation_kind_enforces_external_reference_contract() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let db_path = file.path().to_str().unwrap();
        let (proof, signature, _) = signed_pczt(100);
        assert!(checkpoint(
            db_path,
            WalletNetwork::Main,
            "swap",
            "account-1",
            "swap_deposit",
            None,
            &proof,
            &signature,
        )
        .unwrap_err()
        .contains("require an external reference"));
        assert!(checkpoint(
            db_path,
            WalletNetwork::Main,
            "send",
            "account-1",
            "send",
            Some("unexpected"),
            &proof,
            &signature,
        )
        .unwrap_err()
        .contains("must not have"));
    }

    #[test]
    fn checkpoint_rejects_a_signature_pczt_that_cannot_be_extracted() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let (proof, _, expiry_height) = signed_pczt(100);
        let signature = Creator::new(
            *pczt::Pczt::parse(&proof)
                .unwrap()
                .global()
                .consensus_branch_id(),
            expiry_height,
            133,
            None,
            None,
        )
        .unwrap()
        .build()
        .unwrap()
        .serialize()
        .unwrap();

        let error = checkpoint(
            file.path().to_str().unwrap(),
            WalletNetwork::Main,
            "op-1",
            "account-1",
            "send",
            None,
            &proof,
            &signature,
        )
        .unwrap_err();

        assert!(error.contains("Validate Ledger signed checkpoint"));
        assert!(
            list(file.path().to_str().unwrap(), WalletNetwork::Main, None,)
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn broadcast_guard_serializes_only_the_same_operation() {
        let first = BroadcastGuard::acquire("wallet.db", WalletNetwork::Main, "op-1").unwrap();
        let error = BroadcastGuard::acquire("wallet.db", WalletNetwork::Main, "op-1")
            .err()
            .expect("duplicate broadcast must be rejected");
        assert!(error.contains("already being broadcast"));

        let other = BroadcastGuard::acquire("wallet.db", WalletNetwork::Main, "op-2").unwrap();
        drop(other);
        drop(first);

        BroadcastGuard::acquire("wallet.db", WalletNetwork::Main, "op-1").unwrap();
    }

    #[test]
    fn broadcast_outcomes_transition_and_ack_without_network() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let db_path = file.path().to_str().unwrap();
        checkpoint_test_operation(db_path, "swap-1", "swap_deposit");
        let result = apply_broadcast_outcome(
            db_path,
            WalletNetwork::Main,
            "swap-1",
            OperationKind::SwapDeposit,
            "txid-1",
            "broadcasted",
            None,
        )
        .unwrap();
        assert!(result.requires_ack);
        let listed = list(db_path, WalletNetwork::Main, None).unwrap();
        assert_eq!(listed[0].state, STATE_RESULT_PENDING_ACK);
        assert_eq!(listed[0].txid.as_deref(), Some("txid-1"));
        acknowledge(db_path, WalletNetwork::Main, "swap-1").unwrap();
        assert!(list(db_path, WalletNetwork::Main, None).unwrap().is_empty());

        checkpoint_test_operation(db_path, "send-1", "send");
        let result = apply_broadcast_outcome(
            db_path,
            WalletNetwork::Main,
            "send-1",
            OperationKind::Send,
            "txid-2",
            "broadcasted",
            None,
        )
        .unwrap();
        assert!(!result.requires_ack);
        assert!(list(db_path, WalletNetwork::Main, None).unwrap().is_empty());
    }

    #[test]
    fn retryable_failure_preserves_signed_operation() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let db_path = file.path().to_str().unwrap();
        checkpoint_test_operation(db_path, "send-1", "send");
        let terminal = record_broadcast_failure(
            db_path,
            WalletNetwork::Main,
            "send-1",
            "network unavailable",
        )
        .unwrap();
        assert!(!terminal);

        let listed = list(db_path, WalletNetwork::Main, None).unwrap();
        assert_eq!(listed[0].state, STATE_SIGNED_PENDING_BROADCAST);
        assert_eq!(listed[0].status.as_deref(), Some("retryable_error"));
        assert!(acknowledge(db_path, WalletNetwork::Main, "send-1").is_err());
    }

    #[test]
    fn terminal_failure_discards_signed_operation() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let db_path = file.path().to_str().unwrap();
        checkpoint_test_operation(db_path, "send-1", "send");
        let terminal = record_broadcast_failure(
            db_path,
            WalletNetwork::Main,
            "send-1",
            "Hardware signing request expired before broadcast",
        )
        .unwrap();

        assert!(terminal);
        assert!(list(db_path, WalletNetwork::Main, None).unwrap().is_empty());
    }
}
