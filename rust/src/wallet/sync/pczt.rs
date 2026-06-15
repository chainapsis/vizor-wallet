//! Hardware-wallet PCZT pipeline.
//!
//! Software sends are handled by `sync/send.rs`. This module owns the
//! three-PCZT pipeline the hardware (Keystone) send flow uses, which
//! matches the `zcash-android-wallet-sdk` / Zashi pattern:
//!
//! ```text
//!   1. create_pczt_from_proposal                      → base PCZT (phone)
//!      (IO-finalized, no proofs, no signatures)
//!         │
//!         ├── 2a. add_proofs_to_pczt(base, params?)   → pcztWithProofs   (phone, CPU)
//!         │       (Orchard proof always; Sapling output proofs if
//!         │        the proposal has a non-empty Sapling bundle)
//!         │
//!         └── 2b. redact_pczt_for_signer(base)        → redactedPczt     (phone)
//!                 → Keystone device (animated QR)
//!                 → device signs Orchard spend_auth_sig
//!                 → signed PCZT back to phone          → pcztWithSignatures
//!                                                            │
//!   3. extract_and_broadcast_pczt(                             │
//!        pcztWithProofs, pcztWithSignatures,                   │
//!        spend_params?, output_params?,                        │
//!      )                                               → finalize transparent spends
//!                                                        + extract tx + txid ◄┘
//! ```
//!
//! ## Critical invariants (each of these was a real regression at some point)
//!
//! 1. **`extract_and_broadcast_pczt` broadcasts before it persists.**
//!    Extract the `Transaction` in-memory, send it to the network,
//!    and *only then* write it to the wallet DB. The naive
//!    store-then-broadcast path leaves the wallet unrecoverable when
//!    lightwalletd rejects the tx: the DB thinks the notes are
//!    spent, the network has no record, and the user has to
//!    manually rescue the wallet.
//!
//! 2. **Local storage failure after a successful broadcast must not
//!    surface as a send failure.** Primary store path is
//!    `extract_and_store_transaction_from_pczt` (preserves rich
//!    PCZT recipient/memo metadata). On failure, fall back to
//!    `decrypt_and_store_transaction` — the same path sync uses when
//!    it discovers one of our sent txs on-chain. Spent notes still
//!    get marked spent via nullifier matching; only the PCZT-only
//!    display metadata is lost. Only if both paths fail do we
//!    return an error — and the error explains the tx is on the
//!    network and not to retry.
//!
//! 3. **Sapling params must be passed to BOTH `add_proofs_to_pczt`
//!    AND `extract_and_broadcast_pczt` whenever the PCZT contains a
//!    Sapling bundle.** `add_proofs_to_pczt` uses `LocalTxProver` to
//!    build Sapling output proofs; `extract_and_broadcast_pczt`
//!    uses `LocalTxProver::verifying_keys()` to validate the
//!    extracted transaction and to let
//!    `extract_and_store_transaction_from_pczt` store it. If the
//!    caller supplied params to `add_proofs_to_pczt` but passed
//!    `None` here, extraction bails with `SaplingRequired` and the
//!    user sees a cryptic error after already downloading 50MB of
//!    params and approving on the device. The Dart call site in
//!    `send_screen.dart` threads
//!    `proposal.needsSaplingParams ? spendPath : null` into both —
//!    keep it that way.
//!
//! 4. **`PROPOSAL_STORE` is consume-on-entry for both execute paths,
//!    plus explicit discard on cancel.** `create_pczt_from_proposal`
//!    calls `PROPOSAL_STORE.remove()` at the top (dropping the lock
//!    before any DB work). A second call with the same `proposal_id`
//!    returns "Proposal not found (expired or already consumed)".
//!    `discard_proposal` is idempotent; the Dart `finally` cleanup
//!    calls it when the consume path was never reached (user
//!    cancelled, exception before the consume call, etc.).

use std::convert::Infallible;
use std::sync::OnceLock;

use zcash_primitives::transaction::{Transaction, TxId};
use zcash_proofs::prover::LocalTxProver;

use crate::wallet::db::with_wallet_db_write_lock;
use crate::wallet::network::WalletNetwork;

use super::{consume_stored_proposal, discard_stored_proposal, open_wallet_db};

pub struct ExtractAndBroadcastPcztResult {
    pub txid: String,
    pub status: String,
    pub message: Option<String>,
}

impl ExtractAndBroadcastPcztResult {
    const BROADCASTED: &'static str = "broadcasted";
    const BROADCAST_UNKNOWN: &'static str = "broadcast_unknown";
    const BROADCASTED_STORAGE_FAILED: &'static str = "broadcasted_storage_failed";

    fn broadcasted(txid: String) -> Self {
        Self {
            txid,
            status: Self::BROADCASTED.to_string(),
            message: None,
        }
    }

    fn broadcast_unknown(txid: String, message: String) -> Self {
        Self {
            txid,
            status: Self::BROADCAST_UNKNOWN.to_string(),
            message: Some(message),
        }
    }

    fn broadcasted_storage_failed(txid: String, message: String) -> Self {
        Self {
            txid,
            status: Self::BROADCASTED_STORAGE_FAILED.to_string(),
            message: Some(message),
        }
    }
}

pub(crate) struct ExtractedPcztTransaction {
    pub txid: TxId,
    pub raw_tx: Vec<u8>,
    pub tx: Transaction,
}

const LEGACY_V5_TX_VERSION: u32 = 5;

fn legacy_orchard_proving_key() -> &'static orchard::circuit::ProvingKey {
    static LEGACY_ORCHARD_PROVING_KEY: OnceLock<orchard::circuit::ProvingKey> = OnceLock::new();
    LEGACY_ORCHARD_PROVING_KEY.get_or_init(|| {
        orchard::circuit::ProvingKey::build(orchard::circuit::OrchardCircuitVersion::FixedPostNu6_2)
    })
}

fn ironwood_orchard_proving_key() -> &'static orchard::circuit::ProvingKey {
    static IRONWOOD_ORCHARD_PROVING_KEY: OnceLock<orchard::circuit::ProvingKey> = OnceLock::new();
    IRONWOOD_ORCHARD_PROVING_KEY
        .get_or_init(|| orchard::circuit::ProvingKey::build(ironwood_orchard_circuit_version()))
}

fn orchard_proving_key_for_tx_version(tx_version: u32) -> &'static orchard::circuit::ProvingKey {
    if tx_version == LEGACY_V5_TX_VERSION {
        legacy_orchard_proving_key()
    } else {
        ironwood_orchard_proving_key()
    }
}

fn orchard_verifying_key_for_tx_version(tx_version: u32) -> orchard::circuit::VerifyingKey {
    orchard::circuit::VerifyingKey::build(if tx_version == LEGACY_V5_TX_VERSION {
        orchard::circuit::OrchardCircuitVersion::FixedPostNu6_2
    } else {
        ironwood_orchard_circuit_version()
    })
}

fn ironwood_orchard_circuit_version() -> orchard::circuit::OrchardCircuitVersion {
    orchard::circuit::OrchardCircuitVersion::Ironwood
}

/// Create a PCZT from a stored proposal (for hardware wallet signing).
///
/// This is the hardware-wallet analogue of `execute_proposal`, and
/// mirrors its lifecycle: the proposal is **removed** from the store
/// on entry, so any subsequent failure (PCZT creation error,
/// hardware signing cancel, broadcast rejection) can't leave a
/// replayable proposal ID behind. If the caller aborts the send flow
/// before reaching this function (e.g. the confirmation dialog is
/// cancelled), Dart is expected to call [`discard_proposal`]
/// explicitly to release the stored proposal.
pub fn create_pczt_from_proposal(
    db_path: &str,
    network: WalletNetwork,
    proposal_id: u64,
    send_flow_id: &str,
) -> Result<Vec<u8>, String> {
    use zcash_client_backend::data_api::wallet::{
        create_pczt_from_proposal as zcb_create_pczt,
        create_pczt_from_proposal_with_tx_version as zcb_create_pczt_with_tx_version,
    };
    use zcash_client_backend::wallet::OvkPolicy;

    // Consume the proposal up-front (matches execute_proposal), so
    // that any later failure path leaves the PROPOSAL_STORE clean.
    let stored = consume_stored_proposal(
        proposal_id,
        send_flow_id,
        "Proposal not found (expired or already consumed)",
    )?;

    let pczt = with_wallet_db_write_lock("pczt.create_pczt_from_proposal", || {
        let mut db = open_wallet_db(db_path, network)?;
        if let Some(proposed_tx_version) = stored.proposed_tx_version {
            zcb_create_pczt_with_tx_version::<_, _, Infallible, _, Infallible, _>(
                &mut db,
                &network,
                stored.account_id,
                OvkPolicy::Sender,
                &stored.proposal,
                proposed_tx_version,
            )
        } else {
            zcb_create_pczt::<_, _, Infallible, _, Infallible, _>(
                &mut db,
                &network,
                stored.account_id,
                OvkPolicy::Sender,
                &stored.proposal,
            )
        }
        .map_err(|e| format!("Create PCZT failed: {e}"))
    })?;

    Ok(pczt.serialize())
}

/// Release a stored proposal without executing it. Called from the
/// Dart send flow when the user cancels before
/// [`create_pczt_from_proposal`] (e.g. dismisses the confirmation
/// dialog, cancels the Sapling params download prompt). Idempotent:
/// safe to call for a proposal that has already been consumed or
/// never existed.
pub fn discard_proposal(proposal_id: u64, send_flow_id: &str) {
    discard_stored_proposal(proposal_id, send_flow_id);
}

/// Add Orchard (and, if needed, Sapling) proofs to a PCZT locally.
/// Returns a PCZT-with-proofs, which must later be combined with the
/// signed PCZT returned by the hardware signer.
///
/// Sapling params paths are only required when the PCZT contains a
/// non-empty Sapling bundle (e.g. the recipient is a Sapling-only
/// address or a Unified Address without an Orchard receiver).
/// Orchard-only sends can pass `None` for both paths. This matches
/// the Zashi / zcash-android-wallet-sdk hardware-wallet flow: the
/// hardware device only signs Orchard spends, the phone generates
/// all ZK proofs.
pub fn add_proofs_to_pczt(
    pczt_bytes: &[u8],
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<Vec<u8>, String> {
    use pczt::roles::prover::Prover;

    let pczt = pczt::Pczt::parse(pczt_bytes).map_err(|e| format!("Parse PCZT: {e:?}"))?;
    let tx_version = *pczt.global().tx_version();

    let mut prover = Prover::new(pczt);

    if prover.requires_orchard_proof() {
        prover = prover
            .create_orchard_proof(orchard_proving_key_for_tx_version(tx_version))
            .map_err(|e| format!("Orchard proof: {e:?}"))?;
    }

    #[cfg(zcash_unstable = "nu6.3")]
    if prover.requires_ironwood_proof() {
        prover = prover
            .create_ironwood_proof(ironwood_orchard_proving_key())
            .map_err(|e| format!("Ironwood proof: {e:?}"))?;
    }

    if prover.requires_sapling_proofs() {
        match (spend_params_path, output_params_path) {
            (Some(sp), Some(op)) if !sp.is_empty() && !op.is_empty() => {
                let local_prover =
                    LocalTxProver::new(std::path::Path::new(sp), std::path::Path::new(op));
                prover = prover
                    .create_sapling_proofs(&local_prover, &local_prover)
                    .map_err(|e| format!("Sapling proofs: {e:?}"))?;
            }
            _ => {
                return Err(
                    "PCZT requires Sapling proofs but no Sapling params were supplied. \
                     Download sapling-spend.params and sapling-output.params first."
                        .into(),
                );
            }
        }
    }

    Ok(prover.finish().serialize())
}

/// Redact information from a PCZT that the signer role doesn't need
/// (witnesses, proprietary metadata). Produces the bytes to send to
/// the hardware wallet for signing.
pub fn redact_pczt_for_signer(pczt_bytes: &[u8]) -> Result<Vec<u8>, String> {
    use pczt::roles::redactor::Redactor;

    let pczt = pczt::Pczt::parse(pczt_bytes).map_err(|e| format!("Parse PCZT: {e:?}"))?;

    let mut redactor = Redactor::new(pczt)
        .redact_global_with(|mut r| r.redact_proprietary("zcash_client_backend:proposal_info"))
        .redact_orchard_with(|mut r| {
            r.redact_actions(|mut ar| {
                ar.clear_spend_witness();
                ar.redact_output_proprietary("zcash_client_backend:output_info");
            });
        });

    #[cfg(zcash_unstable = "nu6.3")]
    {
        redactor = redactor.redact_ironwood_with(|mut r| {
            r.redact_actions(|mut ar| {
                ar.clear_spend_witness();
                ar.redact_output_proprietary("zcash_client_backend:output_info");
            });
        });
    }

    let redacted = redactor
        .redact_sapling_with(|mut r| {
            r.redact_spends(|mut sr| sr.clear_witness());
            r.redact_outputs(|mut or| {
                or.redact_proprietary("zcash_client_backend:output_info");
            });
        })
        .redact_transparent_with(|mut r| {
            r.redact_outputs(|mut or| {
                or.redact_proprietary("zcash_client_backend:output_info");
            });
        })
        .finish();

    if *redacted.global().tx_version() == 5 {
        redacted
            .serialize_legacy_v1()
            .map_err(|e| format!("Serialize legacy PCZT for signer: {e}"))
    } else {
        Ok(redacted.serialize())
    }
}

pub(crate) fn set_orchard_anchor_and_witness(
    pczt_bytes: &[u8],
    anchor: orchard::Anchor,
    witness: &orchard::tree::MerklePath,
    spend_nullifier_hex: &str,
) -> Result<Vec<u8>, String> {
    use pczt::roles::updater::{OrchardSpendWitness, Updater};

    let pczt = pczt::Pczt::parse(pczt_bytes).map_err(|e| format!("Parse PCZT: {e:?}"))?;
    let spend_nullifier = parse_32_byte_hex(spend_nullifier_hex, "Orchard spend nullifier")?;
    let action_indices = pczt
        .orchard()
        .actions()
        .iter()
        .enumerate()
        .filter_map(|(index, action)| {
            if *action.spend().nullifier() == spend_nullifier {
                Some(index)
            } else {
                None
            }
        })
        .collect::<Vec<_>>();
    let action_index = match action_indices.as_slice() {
        [index] => *index,
        [] => {
            return Err("Orchard spend nullifier not found in PCZT".to_string());
        }
        _ => {
            return Err("Orchard spend nullifier matched multiple PCZT actions".to_string());
        }
    };
    let updated = Updater::new(pczt)
        .set_v6_orchard_anchor(anchor)
        .map_err(|e| format!("Set Orchard anchor in PCZT: {e}"))?
        .set_orchard_spend_witnesses([OrchardSpendWitness::from_merkle_path(
            action_index,
            witness.clone(),
        )])
        .map_err(|e| format!("Set Orchard witness in PCZT: {e}"))?
        .finish();

    Ok(updated.serialize())
}

fn parse_32_byte_hex(value: &str, label: &str) -> Result<[u8; 32], String> {
    let mut bytes = [0u8; 32];
    hex::decode_to_slice(value, &mut bytes).map_err(|e| format!("Decode {label}: {e}"))?;
    Ok(bytes)
}

fn combine_pczts(proofs: &[u8], sigs: &[u8]) -> Result<pczt::Pczt, String> {
    use pczt::roles::combiner::Combiner;

    let p = pczt::Pczt::parse(proofs).map_err(|e| format!("Parse PCZT with proofs: {e:?}"))?;
    let s = pczt::Pczt::parse(sigs).map_err(|e| format!("Parse PCZT with signatures: {e:?}"))?;
    Combiner::new(vec![p, s])
        .combine()
        .map_err(|e| format!("Combine PCZTs: {e:?}"))
}

pub(crate) fn extract_transaction_from_pczt(
    pczt_with_proofs_bytes: &[u8],
    pczt_with_signatures_bytes: &[u8],
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<ExtractedPcztTransaction, String> {
    use pczt::roles::spend_finalizer::SpendFinalizer;
    use pczt::roles::tx_extractor::TransactionExtractor;

    let sapling_vks: Option<(
        sapling_crypto::circuit::SpendVerifyingKey,
        sapling_crypto::circuit::OutputVerifyingKey,
    )> = match (spend_params_path, output_params_path) {
        (Some(sp), Some(op)) if !sp.is_empty() && !op.is_empty() => {
            let prover = LocalTxProver::new(std::path::Path::new(sp), std::path::Path::new(op));
            Some(prover.verifying_keys())
        }
        _ => None,
    };

    let finalized_pczt = SpendFinalizer::new(combine_pczts(
        pczt_with_proofs_bytes,
        pczt_with_signatures_bytes,
    )?)
    .finalize_spends()
    .map_err(|e| format!("Finalize transparent spends in PCZT: {e:?}"))?;

    let tx_version = *finalized_pczt.global().tx_version();
    let orchard_vk = orchard_verifying_key_for_tx_version(tx_version);
    let ironwood_vk = orchard::circuit::VerifyingKey::build(ironwood_orchard_circuit_version());

    let mut extractor = TransactionExtractor::new(finalized_pczt).with_orchard(&orchard_vk);
    #[cfg(zcash_unstable = "nu6.3")]
    {
        extractor = extractor.with_ironwood(&ironwood_vk);
    }
    if let Some((spend_vk, output_vk)) = sapling_vks.as_ref() {
        extractor = extractor.with_sapling(spend_vk, output_vk);
    }

    let tx = extractor
        .extract()
        .map_err(|e| format!("Extract TX from PCZT: {e:?}"))?;
    let txid = tx.txid();
    let mut raw_tx = Vec::new();
    tx.write(&mut raw_tx)
        .map_err(|e| format!("Serialize TX: {e}"))?;

    Ok(ExtractedPcztTransaction { txid, raw_tx, tx })
}

/// Combine a PCZT-with-proofs and a PCZT-with-signatures, broadcast
/// the resulting transaction, and persist it to the wallet DB after
/// the broadcast is accepted, or after a broadcast response deadline
/// leaves acceptance ambiguous.
///
/// Ordering is critical here. See invariants (1) and (2) in the
/// module-level docstring.
pub async fn extract_and_broadcast_pczt(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    pczt_with_proofs_bytes: &[u8],
    pczt_with_signatures_bytes: &[u8],
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<ExtractAndBroadcastPcztResult, String> {
    use zcash_client_backend::data_api::wallet::{
        decrypt_and_store_transaction, extract_and_store_transaction_from_pczt,
    };

    // Load Sapling verifying keys once if the caller supplied params.
    // The prover keeps the underlying params alive, and
    // `verifying_keys()` returns owned
    // `(SpendVerifyingKey, OutputVerifyingKey)`. We hand references
    // into this tuple to both `TransactionExtractor::with_sapling`
    // and `extract_and_store_transaction_from_pczt`.
    let sapling_vks: Option<(
        sapling_crypto::circuit::SpendVerifyingKey,
        sapling_crypto::circuit::OutputVerifyingKey,
    )> = match (spend_params_path, output_params_path) {
        (Some(sp), Some(op)) if !sp.is_empty() && !op.is_empty() => {
            let prover = LocalTxProver::new(std::path::Path::new(sp), std::path::Path::new(op));
            Some(prover.verifying_keys())
        }
        _ => None,
    };

    // Step 1: extract the Transaction without touching the DB. We
    // keep `tx` around after broadcast so the fallback storage path
    // can use it.
    let extracted = extract_transaction_from_pczt(
        pczt_with_proofs_bytes,
        pczt_with_signatures_bytes,
        spend_params_path,
        output_params_path,
    )?;
    let txid = extracted.txid;
    let tx_bytes = extracted.raw_tx.clone();
    let tx = extracted.tx;

    let store_locally = || -> Result<(), String> {
        with_wallet_db_write_lock("pczt.extract_and_broadcast_pczt.store", || {
            let mut db = open_wallet_db(db_path, network)?;

            // Primary path: rich PCZT-aware storage (preserves
            // recipient/memo). Hand Sapling verifying keys in whenever the
            // combined PCZT has a Sapling bundle, otherwise librustzcash
            // rejects the extraction with `SaplingRequired` before we can
            // store anything.
            let sapling_vk_pair = sapling_vks.as_ref().map(|(s, o)| (s, o));
            let combined_pczt = combine_pczts(pczt_with_proofs_bytes, pczt_with_signatures_bytes)?;
            let tx_version = *combined_pczt.global().tx_version();
            let orchard_vk = orchard_verifying_key_for_tx_version(tx_version);
            match extract_and_store_transaction_from_pczt::<_, zcash_client_sqlite::ReceivedNoteId>(
                &mut db,
                combined_pczt,
                sapling_vk_pair,
                Some(&orchard_vk),
            ) {
                Ok(_) => return Ok(()),
                Err(primary_err) => {
                    log::warn!(
                        "keystone: PCZT-aware storage failed \
                         (txid={txid}): {primary_err}. Falling back to chain-style \
                         decrypt_and_store_transaction; rich recipient metadata \
                         will not be available in history until the next sync."
                    );

                    // Fallback path: same code sync uses when it discovers a
                    // wallet tx on the chain. Marks spent notes correctly
                    // via nullifier matching and picks up any change note
                    // back to us from enc_ciphertext decryption. The
                    // recipient/memo metadata that was only in the PCZT
                    // proprietary fields is lost, but correctness is
                    // preserved — the spent notes no longer appear
                    // spendable.
                    decrypt_and_store_transaction(&network, &mut db, &tx, None).map_err(
                        |fallback_err| format!("Primary: {primary_err}. Fallback: {fallback_err}"),
                    )?;
                }
            }

            Ok(())
        })
    };

    // Step 2: broadcast. Definite rejection leaves the DB untouched,
    // but a response deadline is ambiguous: lightwalletd may already
    // have relayed the transaction, so we store locally and let the
    // normal pending/resubmit path reconcile it.
    let mut client = crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url)
        .await
        .map_err(|e| e.to_string())?;
    let latest = crate::wallet::sync_engine::get_latest_block(&mut client)
        .await
        .map_err(|e| e.to_string())?;
    if let Some(error) =
        pczt_broadcast_expiry_error(&txid, u32::from(tx.expiry_height()), latest.height)
    {
        return Err(error);
    }

    let resp = match crate::wallet::sync_engine::send_transaction_with_status(
        &mut client,
        &tx_bytes,
    )
    .await
    {
        Ok(resp) => resp,
        Err(status) if status.code() == tonic::Code::DeadlineExceeded => {
            let mut message = format!(
                "Broadcast response timed out for txid={txid}. The transaction may already \
                 be on the network. Do not send again until sync or an explorer confirms \
                 whether this transaction was accepted."
            );
            match store_locally() {
                Ok(()) => {
                    message.push_str(
                        " It was stored locally and will retry automatically during sync until \
                         it is confirmed or expires.",
                    );
                }
                Err(storage_err) => {
                    log::error!(
                        "keystone: failed to store tx after ambiguous broadcast timeout \
                         (txid={txid}): {storage_err}"
                    );
                    message.push_str(&format!(
                        " Local tracking also failed: {storage_err}. Check an explorer before \
                         retrying this send."
                    ));
                }
            }
            return Ok(ExtractAndBroadcastPcztResult::broadcast_unknown(
                txid.to_string(),
                message,
            ));
        }
        Err(status) => return Err(format!("Broadcast: {status}")),
    };

    handle_pczt_send_response(&txid.to_string(), &resp, store_locally)
}

fn pczt_broadcast_expiry_error(
    txid: &TxId,
    expiry_height: u32,
    current_height: u64,
) -> Option<String> {
    if expiry_height == 0 || current_height < u64::from(expiry_height) {
        None
    } else {
        Some(format!(
            "Hardware signing request expired before broadcast: txid={txid}, \
             expiry height {expiry_height}, current chain height {current_height}. \
             Start the signing flow again so Vizor can build a fresh transaction."
        ))
    }
}

fn handle_pczt_send_response<F>(
    txid: &str,
    resp: &zcash_client_backend::proto::service::SendResponse,
    store_locally: F,
) -> Result<ExtractAndBroadcastPcztResult, String>
where
    F: FnOnce() -> Result<(), String>,
{
    // zebra-lightwalletd returns the txid in `error_message` on
    // success, so the only reliable clean-success signal is
    // `error_code`. Duplicate/already-known responses are also
    // definite acceptance because the network already has the tx.
    if let Some(error) = super::broadcast::send_response_rejection_error(resp) {
        return Err(error);
    }

    // Broadcast was accepted. Persist locally so the UI sees the tx
    // immediately and the spent notes stop showing up as spendable.
    if let Err(storage_err) = store_locally() {
        log::error!(
            "keystone: broadcast succeeded but local storage failed \
             (txid={txid}): {storage_err}"
        );
        return Ok(ExtractAndBroadcastPcztResult::broadcasted_storage_failed(
            txid.to_string(),
            format!(
                "Broadcast succeeded (txid={txid}) but local storage failed. {storage_err}. \
                 The transaction is on the network; check an explorer to confirm, and do not \
                 attempt to send again until the next sync reconciles your balance."
            ),
        ));
    }

    Ok(ExtractAndBroadcastPcztResult::broadcasted(txid.to_string()))
}

#[cfg(test)]
mod tests {
    use std::cell::Cell;

    use super::*;
    use zcash_client_backend::proto::service::SendResponse;

    fn send_response(error_code: i32, error_message: &str) -> SendResponse {
        SendResponse {
            error_code,
            error_message: error_message.to_string(),
        }
    }

    #[test]
    fn pczt_success_response_stores_locally_and_returns_broadcasted() {
        let store_calls = Cell::new(0);

        let result = handle_pczt_send_response("txid", &send_response(0, "txid"), || {
            store_calls.set(store_calls.get() + 1);
            Ok(())
        })
        .unwrap();

        assert_eq!(result.status, ExtractAndBroadcastPcztResult::BROADCASTED);
        assert_eq!(result.message, None);
        assert_eq!(store_calls.get(), 1);
    }

    #[test]
    fn pczt_duplicate_response_stores_locally_and_returns_broadcasted() {
        let store_calls = Cell::new(0);

        let result =
            handle_pczt_send_response("txid", &send_response(18, "txn-already-in-mempool"), || {
                store_calls.set(store_calls.get() + 1);
                Ok(())
            })
            .unwrap();

        assert_eq!(result.status, ExtractAndBroadcastPcztResult::BROADCASTED);
        assert_eq!(result.message, None);
        assert_eq!(store_calls.get(), 1);
    }

    #[test]
    fn pczt_duplicate_response_with_storage_failure_is_network_success() {
        let result = handle_pczt_send_response("txid", &send_response(18, "already known"), || {
            Err("database is busy".to_string())
        })
        .unwrap();

        assert_eq!(
            result.status,
            ExtractAndBroadcastPcztResult::BROADCASTED_STORAGE_FAILED
        );
        assert!(result
            .message
            .as_deref()
            .unwrap_or_default()
            .contains("The transaction is on the network"));
    }

    #[test]
    fn pczt_fatal_rejection_does_not_store_locally() {
        let store_calls = Cell::new(0);

        let err =
            handle_pczt_send_response("txid", &send_response(18, "bad-txns-inputs-spent"), || {
                store_calls.set(store_calls.get() + 1);
                Ok(())
            })
            .err()
            .unwrap();

        assert_eq!(err, "Broadcast rejected: bad-txns-inputs-spent (code 18)");
        assert_eq!(store_calls.get(), 0);
    }

    #[test]
    fn pczt_broadcast_expiry_allows_no_expiry() {
        let txid = TxId::from_bytes([0; 32]);

        assert!(pczt_broadcast_expiry_error(&txid, 0, 500).is_none());
    }

    #[test]
    fn pczt_broadcast_expiry_allows_unexpired_tx() {
        let txid = TxId::from_bytes([0; 32]);

        assert!(pczt_broadcast_expiry_error(&txid, 501, 500).is_none());
    }

    #[test]
    fn pczt_broadcast_expiry_rejects_expired_tx() {
        let txid = TxId::from_bytes([0; 32]);

        let err = pczt_broadcast_expiry_error(&txid, 500, 500).unwrap();

        assert!(err.contains("expired before broadcast"));
        assert!(err.contains("expiry height 500"));
        assert!(err.contains("current chain height 500"));
    }
}
