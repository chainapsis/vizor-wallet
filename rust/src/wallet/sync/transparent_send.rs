use std::collections::HashMap;
use std::num::NonZeroU32;

use rusqlite::{named_params, Row};
use transparent::{
    address::{Script, TransparentAddress},
    bundle::{OutPoint, TxOut},
    keys::TransparentKeyScope,
};
use zcash_client_backend::{
    data_api::{
        wallet::{ConfirmationsPolicy, TargetHeight},
        Balance, TransparentKeyOrigin,
    },
    encoding::AddressCodec,
    wallet::WalletTransparentOutput,
};
use zcash_client_sqlite::AccountUuid;
use zcash_primitives::transaction::{builder::DEFAULT_TX_EXPIRY_DELTA, fees::zip317};
use zcash_protocol::{
    consensus::{BlockHeight, COINBASE_MATURITY_BLOCKS},
    value::Zatoshis,
    PoolType,
};
use zcash_script::script;

use crate::wallet::network::WalletNetwork;

use super::open_readonly_conn;

pub(crate) struct TransparentSendBalance {
    pub spendable: u64,
    pub pending: u64,
}

struct TransparentCandidate {
    address: TransparentAddress,
    output: WalletTransparentOutput,
    key_origin: TransparentKeyOrigin,
    spendable: bool,
}

pub(crate) fn transparent_send_confirmations_policy() -> ConfirmationsPolicy {
    ConfirmationsPolicy::new(
        NonZeroU32::new(3).expect("nonzero trusted confirmations"),
        NonZeroU32::new(10).expect("nonzero untrusted confirmations"),
        false,
    )
    .expect("trusted confirmations must be <= untrusted confirmations")
}

pub(crate) fn get_transparent_send_balance(
    db_path: &str,
    network: WalletNetwork,
    account_id: AccountUuid,
    target_height: TargetHeight,
) -> Result<TransparentSendBalance, String> {
    let mut spendable = Zatoshis::ZERO;
    let mut pending = Zatoshis::ZERO;

    for candidate in query_transparent_candidates(db_path, network, account_id, target_height)? {
        if candidate.spendable {
            spendable = (spendable + candidate.output.value())
                .ok_or("Transparent spendable balance overflow")?;
        } else {
            pending = (pending + candidate.output.value())
                .ok_or("Transparent pending balance overflow")?;
        }
    }

    Ok(TransparentSendBalance {
        spendable: u64::from(spendable),
        pending: u64::from(pending),
    })
}

pub(crate) fn get_transparent_send_balances_by_address(
    db_path: &str,
    network: WalletNetwork,
    account_id: AccountUuid,
    target_height: TargetHeight,
) -> Result<HashMap<TransparentAddress, (TransparentKeyOrigin, Balance)>, String> {
    let mut result = HashMap::new();

    for candidate in query_transparent_candidates(db_path, network, account_id, target_height)? {
        if !candidate.spendable {
            continue;
        }

        let entry = result
            .entry(candidate.address)
            .or_insert((candidate.key_origin, Balance::ZERO));
        entry
            .1
            .add_spendable_value(candidate.output.value())
            .map_err(|e| format!("Transparent address balance overflow: {e}"))?;
    }

    Ok(result)
}

pub(crate) fn get_spendable_transparent_outputs_for_address(
    db_path: &str,
    network: WalletNetwork,
    account_id: AccountUuid,
    target_height: TargetHeight,
    address: &TransparentAddress,
) -> Result<Vec<WalletTransparentOutput>, String> {
    let candidates = query_transparent_candidates_for_address(
        db_path,
        network,
        account_id,
        target_height,
        address,
    )?;
    Ok(candidates
        .into_iter()
        .filter(|candidate| candidate.spendable)
        .map(|candidate| candidate.output)
        .collect())
}

fn query_transparent_candidates(
    db_path: &str,
    network: WalletNetwork,
    account_id: AccountUuid,
    target_height: TargetHeight,
) -> Result<Vec<TransparentCandidate>, String> {
    query_transparent_candidates_inner(db_path, network, account_id, target_height, None)
}

fn query_transparent_candidates_for_address(
    db_path: &str,
    network: WalletNetwork,
    account_id: AccountUuid,
    target_height: TargetHeight,
    address: &TransparentAddress,
) -> Result<Vec<TransparentCandidate>, String> {
    query_transparent_candidates_inner(db_path, network, account_id, target_height, Some(address))
}

fn query_transparent_candidates_inner(
    db_path: &str,
    network: WalletNetwork,
    account_id: AccountUuid,
    target_height: TargetHeight,
    address: Option<&TransparentAddress>,
) -> Result<Vec<TransparentCandidate>, String> {
    let conn = open_readonly_conn(db_path)?;
    let policy = transparent_send_confirmations_policy();
    let account_uuid = account_id.expose_uuid();
    let address_filter = address.map(|addr| addr.encode(&network));
    let mut stmt = conn
        .prepare(&format!(
            "SELECT u.address,
                    t.txid,
                    u.output_index,
                    u.script,
                    u.value_zat,
                    addresses.key_scope,
                    addresses.imported_transparent_receiver_script,
                    t.mined_height AS received_height,
                    t.tx_index,
                    IFNULL(t.trust_status, 0) AS trust_status
             FROM transparent_received_outputs u
             JOIN accounts ON accounts.id = u.account_id
             JOIN transactions t ON t.id_tx = u.transaction_id
             JOIN addresses ON addresses.id = u.address_id
             WHERE accounts.uuid = :account_uuid
             AND (:address IS NULL OR u.address = :address)
             AND u.value_zat > :min_value
             AND ({})
             AND u.id NOT IN ({})
             AND ({})
             ORDER BY IFNULL(t.mined_height, :target_height), u.output_index",
            tx_unexpired_condition("t"),
            spent_utxos_clause(),
            excluding_wallet_internal_ephemeral_outputs("u", "addresses", "t", "accounts"),
        ))
        .map_err(|e| format!("Failed to prepare transparent balance query: {e}"))?;

    let mut rows = stmt
        .query(named_params![
            ":account_uuid": account_uuid.as_bytes(),
            ":address": address_filter,
            ":target_height": u32::from(target_height),
            ":min_value": u64::from(zip317::MARGINAL_FEE),
        ])
        .map_err(|e| format!("Failed to query transparent balance: {e}"))?;

    let mut candidates = Vec::new();
    while let Some(row) = rows
        .next()
        .map_err(|e| format!("Failed to read transparent balance row: {e}"))?
    {
        candidates.push(row_to_candidate(row, &network, target_height, policy)?);
    }

    Ok(candidates)
}

fn row_to_candidate(
    row: &Row,
    network: &WalletNetwork,
    target_height: TargetHeight,
    policy: ConfirmationsPolicy,
) -> Result<TransparentCandidate, String> {
    let address_str: String = row
        .get("address")
        .map_err(|e| format!("Failed to read transparent address: {e}"))?;
    let address = TransparentAddress::decode(network, &address_str)
        .map_err(|e| format!("Failed to decode transparent address: {e}"))?;

    let key_scope_code: i64 = row
        .get("key_scope")
        .map_err(|e| format!("Failed to read transparent key scope: {e}"))?;
    let key_origin = transparent_key_origin(key_scope_code)?;
    let receiving_key_scope = receiving_zip32_scope(key_scope_code);
    let received_height_raw: Option<u32> = row
        .get("received_height")
        .map_err(|e| format!("Failed to read transparent received height: {e}"))?;
    let received_height = received_height_raw.map(BlockHeight::from);
    let tx_trusted: bool = row
        .get("trust_status")
        .map_err(|e| format!("Failed to read transparent trust status: {e}"))?;
    let tx_index: Option<u32> = row
        .get("tx_index")
        .map_err(|e| format!("Failed to read transparent tx index: {e}"))?;
    let output = row_to_wallet_output(row)?;
    let confirmations_remaining = policy.confirmations_until_spendable(
        target_height,
        PoolType::TRANSPARENT,
        receiving_key_scope,
        received_height,
        tx_trusted,
        None,
        false,
    );
    let spendable = confirmations_remaining == 0
        && !is_immature_coinbase(target_height, received_height_raw, tx_index);

    Ok(TransparentCandidate {
        address,
        output,
        key_origin,
        spendable,
    })
}

fn row_to_wallet_output(row: &Row) -> Result<WalletTransparentOutput, String> {
    let txid: Vec<u8> = row
        .get("txid")
        .map_err(|e| format!("Failed to read transparent txid: {e}"))?;
    let txid_bytes: [u8; 32] = txid
        .try_into()
        .map_err(|_| "Transparent txid must be 32 bytes".to_string())?;
    let index: u32 = row
        .get("output_index")
        .map_err(|e| format!("Failed to read transparent output index: {e}"))?;
    let script_pubkey =
        Script(script::Code(row.get("script").map_err(|e| {
            format!("Failed to read transparent script: {e}")
        })?));
    let raw_value: i64 = row
        .get("value_zat")
        .map_err(|e| format!("Failed to read transparent value: {e}"))?;
    let value = Zatoshis::from_nonnegative_i64(raw_value)
        .map_err(|_| format!("Invalid transparent UTXO value: {raw_value}"))?;
    let received_height: Option<u32> = row
        .get("received_height")
        .map_err(|e| format!("Failed to read transparent received height: {e}"))?;
    let mut output = WalletTransparentOutput::from_parts(
        OutPoint::new(txid_bytes, index),
        TxOut::new(value, script_pubkey),
        received_height.map(BlockHeight::from),
    )
    .ok_or_else(|| "Transparent UTXO script does not map to a supported address".to_string())?;

    let redeem_script: Option<Vec<u8>> = row
        .get("imported_transparent_receiver_script")
        .map_err(|e| format!("Failed to read transparent redeem script: {e}"))?;
    if let Some(redeem_script) = redeem_script {
        if let Ok(from_chain) = script::FromChain::parse(&script::Code(redeem_script)) {
            if let Some(input_size) = transparent::builder::p2sh_input_serialized_len(&from_chain) {
                output = output.with_known_input_size(input_size);
            }
        }
    }

    Ok(output)
}

fn receiving_zip32_scope(key_scope: i64) -> Option<zip32::Scope> {
    match key_scope {
        0 => Some(zip32::Scope::External),
        1 => Some(zip32::Scope::Internal),
        _ => None,
    }
}

fn transparent_key_origin(key_scope: i64) -> Result<TransparentKeyOrigin, String> {
    match key_scope {
        0 => Ok(TransparentKeyOrigin::Derived {
            scope: TransparentKeyScope::EXTERNAL,
        }),
        1 => Ok(TransparentKeyOrigin::Derived {
            scope: TransparentKeyScope::INTERNAL,
        }),
        2 => Ok(TransparentKeyOrigin::Derived {
            scope: TransparentKeyScope::custom(2).expect("valid transparent key scope"),
        }),
        -1 => Ok(TransparentKeyOrigin::Imported),
        other => Err(format!("Invalid transparent key scope code: {other}")),
    }
}

fn is_immature_coinbase(
    target_height: TargetHeight,
    received_height: Option<u32>,
    tx_index: Option<u32>,
) -> bool {
    tx_index == Some(0)
        && match received_height {
            Some(height) => {
                u32::from(target_height).saturating_sub(height) < COINBASE_MATURITY_BLOCKS
            }
            None => true,
        }
}

fn tx_unexpired_condition(tx: &str) -> String {
    format!(
        r#"
        {tx}.mined_height < :target_height
        OR {tx}.expiry_height = 0
        OR {tx}.expiry_height >= :target_height
        OR (
            {tx}.expiry_height IS NULL
            AND {tx}.min_observed_height + {DEFAULT_TX_EXPIRY_DELTA} >= :target_height
        )
        "#
    )
}

fn spent_utxos_clause() -> String {
    format!(
        r#"
        SELECT txo_spends.transparent_received_output_id
        FROM transparent_received_output_spends txo_spends
        JOIN transactions stx ON stx.id_tx = txo_spends.transaction_id
        WHERE {}
        "#,
        tx_unexpired_condition("stx")
    )
}

fn excluding_wallet_internal_ephemeral_outputs(
    transparent_received_outputs: &str,
    addresses: &str,
    tx: &str,
    accounts: &str,
) -> String {
    r#"
        {addresses}.key_scope != 2
        OR {tx}.id_tx NOT IN (
            SELECT transaction_id
            FROM v_received_output_spends
            WHERE v_received_output_spends.account_id = {accounts}.id
        )
        OR {transparent_received_outputs}.max_observed_unspent_height > {tx}.expiry_height
        "#
    .replace("{addresses}", addresses)
    .replace("{tx}", tx)
    .replace("{accounts}", accounts)
    .replace(
        "{transparent_received_outputs}",
        transparent_received_outputs,
    )
}
