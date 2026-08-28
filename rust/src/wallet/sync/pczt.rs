//! Hardware-wallet PCZT pipeline.
//!
//! Software sends are handled by `sync/send.rs`. This module owns the
//! PCZT pipeline used by Keystone signing. A proposal is IO-finalized, proved
//! locally, redacted for the signer, and returned with device signatures.
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
//!   3. store_and_broadcast_signed_pczts_for_proposal(          │
//!        [pcztWithProofs...], [pcztWithSignatures...],         │
//!      )                                               → validate/finalize all
//!                                                        + ordered broadcast
//!                                                        + atomic prefix store ◄┘
//! ```
//!
//! ## Critical invariants (each of these was a real regression at some point)
//!
//! 1. **Send validates every returned PCZT before touching the DB or network.**
//!    For TEX, round 2 must contain exactly one transparent input spending the
//!    extracted round-1 txid. Swaps, duplicates, modified effects, and missing
//!    shielded or transparent signatures are rejected before persistence.
//!
//! 2. **Broadcast precedes persistence.** A definite lightwalletd rejection
//!    must leave that PCZT out of the wallet DB. After each ordered broadcast
//!    attempt stops, the accepted-or-ambiguous prefix is persisted atomically;
//!    a later store failure rolls back every earlier write in that prefix.
//!
//! 3. **Sapling params must be passed to BOTH `add_proofs_to_pczt`
//!    AND the final store/broadcast call whenever the PCZT contains a
//!    Sapling bundle.** `add_proofs_to_pczt` uses `LocalTxProver` to
//!    build Sapling output proofs; finalization
//!    uses `LocalTxProver::verifying_keys()` to validate the
//!    extracted transaction and to let
//!    `extract_and_store_transaction_from_pczt` store it. If the
//!    caller supplied params to `add_proofs_to_pczt` but passed
//!    `None` here, extraction bails with `SaplingRequired` and the
//!    user sees a cryptic error after already downloading 50MB of
//!    params and approving on the device. The Dart call site in
//!    `send_screen.dart` threads
//!    `proposal.needsSaplingParams ? spendPath : null` into both.
//!
//! 4. **`PROPOSAL_STORE` is consume-on-entry for both execute paths,
//!    while its wallet-input lock remains releasable until the flow
//!    finishes.** `create_pczt_from_proposal` removes the replayable
//!    proposal at the top. A second call with the same `proposal_id`
//!    returns "Proposal not found (expired or already consumed)".
//!    `discard_proposal` is idempotent and releases the retained
//!    owner-scoped input lock after hardware cancel or pre-store failure.
//!    Successful post-broadcast storage finishes proposal bookkeeping because
//!    the persisted transactions now own recovery.

use std::convert::Infallible;
use std::sync::OnceLock;

use transparent::address::TransparentAddress;
use transparent::bundle::{OutPoint, TxOut};
use transparent::keys::TransparentKeyScope;
use zcash_address::{ToAddress, ZcashAddress};
use zcash_client_backend::data_api::{Account, OutputLockStore, WalletRead};
use zcash_client_backend::proposal::{Proposal, Step, StepOutputIndex};
use zcash_client_backend::wallet::WalletTransparentOutput;
use zcash_primitives::transaction::{builder::BundlePadding, Transaction, TxId};
use zcash_proofs::prover::LocalTxProver;
use zcash_protocol::consensus::{NetworkConstants, Parameters};

use crate::wallet::db::with_wallet_db_write_lock;
use crate::wallet::network::WalletNetwork;

use super::{
    consume_stored_proposal, discard_stored_proposal, finish_stored_proposal, open_wallet_db,
    retain_stored_proposal_lock_until_expiry, stored_proposal_lock,
};

pub struct ExtractAndBroadcastPcztResult {
    pub txid: String,
    pub status: String,
    pub message: Option<String>,
}

pub struct TexPcztPair {
    pub pczts: Vec<Vec<u8>>,
    pub signer_pczts: Vec<Vec<u8>>,
}

pub struct StoreAndBroadcastPcztsResult {
    pub txids: String,
    pub status: String,
    pub broadcasted_count: u32,
    pub total_count: u32,
    pub message: Option<String>,
}

impl StoreAndBroadcastPcztsResult {
    const BROADCASTED: &'static str = "broadcasted";
    const BROADCAST_UNKNOWN: &'static str = "broadcast_unknown";
    const PARTIAL_BROADCAST: &'static str = "partial_broadcast";
    const BROADCASTED_STORAGE_FAILED: &'static str = "broadcasted_storage_failed";
    const EXPIRED: &'static str = "expired";
}

#[derive(Debug)]
enum AtomicPcztStoreError {
    Sqlite(rusqlite::Error),
    Store(String),
}

impl From<rusqlite::Error> for AtomicPcztStoreError {
    fn from(error: rusqlite::Error) -> Self {
        Self::Sqlite(error)
    }
}

impl std::fmt::Display for AtomicPcztStoreError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Sqlite(error) => write!(formatter, "{error}"),
            Self::Store(error) => formatter.write_str(error),
        }
    }
}

fn singleton_proposal(
    source: &Proposal<super::send::WalletFeeRule, zcash_client_sqlite::ReceivedNoteId>,
    step: Step<zcash_client_sqlite::ReceivedNoteId>,
) -> Result<Proposal<super::send::WalletFeeRule, zcash_client_sqlite::ReceivedNoteId>, String> {
    Proposal::multi_step(
        source.fee_rule().clone(),
        source.min_target_height(),
        source.confirmations_policy(),
        nonempty::NonEmpty::singleton(step),
    )
    .map(|proposal| proposal.with_proposed_version(source.proposed_version()))
    .map_err(|e| format!("Build TEX PCZT step proposal: {e}"))
}

fn tex_ephemeral_output_index<F>(
    outputs: &[TxOut],
    expected_value: zcash_protocol::value::Zatoshis,
    mut address_scope: F,
) -> Result<usize, String>
where
    F: FnMut(&TransparentAddress) -> Result<Option<TransparentKeyScope>, String>,
{
    let mut matches = Vec::new();
    for (index, output) in outputs.iter().enumerate() {
        if output.value() != expected_value {
            continue;
        }
        let Some(address) = output.recipient_address() else {
            continue;
        };
        if address_scope(&address)? == Some(TransparentKeyScope::EPHEMERAL) {
            matches.push(index);
        }
    }
    if matches.len() != 1 {
        return Err("TEX ephemeral output is not uniquely identifiable".to_string());
    }
    Ok(matches[0])
}

fn transparent_output_user_address(
    network: WalletNetwork,
    output: &pczt::transparent::Output,
) -> Result<String, String> {
    let script = zcash_script::script::PubKey::parse(&zcash_script::script::Code(
        output.script_pubkey().clone(),
    ))
    .map_err(|_| "TEX PCZT has an invalid transparent output script")?;
    let address = TransparentAddress::from_script_pubkey(&script)
        .ok_or("TEX PCZT has an unsupported transparent output script")?;
    Ok(match address {
        TransparentAddress::PublicKeyHash(hash) => {
            ZcashAddress::from_transparent_p2pkh(network.network_type(), hash).encode()
        }
        TransparentAddress::ScriptHash(hash) => {
            ZcashAddress::from_transparent_p2sh(network.network_type(), hash).encode()
        }
    })
}

/// Produces the signer-only view accepted by Keystone's transparent-output
/// checker. ZIP 320 stores an ephemeral output without `user_address`, while a
/// TEX payment stores its `tex1...` address. Keystone instead requires every
/// transparent output to carry the matching legacy t-address. The first round
/// also needs its BIP 44 metadata so the device displays the ephemeral output
/// as wallet-owned change rather than as a payment.
fn prepare_tex_pczt_for_keystone(
    pczt_bytes: &[u8],
    network: WalletNetwork,
    owned_output_derivation: Option<(usize, [u8; 33], transparent::pczt::Bip32Derivation)>,
) -> Result<Vec<u8>, String> {
    use pczt::roles::updater::Updater;

    let pczt = pczt::Pczt::parse(pczt_bytes).map_err(|e| format!("Parse TEX PCZT: {e:?}"))?;
    let output_addresses = pczt
        .transparent()
        .outputs()
        .iter()
        .map(|output| transparent_output_user_address(network, output))
        .collect::<Result<Vec<_>, _>>()?;
    if owned_output_derivation
        .as_ref()
        .is_some_and(|(index, _, _)| *index >= output_addresses.len())
    {
        return Err("TEX ephemeral signer metadata references a missing output".to_string());
    }

    let mut owned_output_derivation = owned_output_derivation;
    let pczt = Updater::new(pczt)
        .update_transparent_with(|mut updater| {
            for (index, user_address) in output_addresses.into_iter().enumerate() {
                let derivation = match owned_output_derivation.as_ref() {
                    Some((owned_index, _, _)) if *owned_index == index => {
                        owned_output_derivation.take()
                    }
                    _ => None,
                };
                updater.update_output_with(index, |mut output| {
                    output.set_user_address(user_address);
                    if let Some((_, pubkey, derivation)) = derivation {
                        output.set_bip32_derivation(pubkey, derivation);
                    }
                    Ok(())
                })?;
            }
            Ok(())
        })
        .map_err(|e| format!("Prepare TEX PCZT for Keystone: {e:?}"))?
        .finish();

    serialize_signer_view(apply_signer_redaction(pczt, false))
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

/// Computes the transaction ID committed to by an IO-finalized v5 or v6 PCZT.
///
/// ZIP 244 transaction IDs commit only to transaction effects, so proofs and
/// authorization data do not need to be present. Rejecting modifiable PCZTs is
/// important here: the returned ID is only stable once every input and output
/// set has been finalized.
pub(crate) fn txid_from_io_finalized_pczt(pczt_bytes: &[u8]) -> Result<TxId, String> {
    use zcash_primitives::transaction::txid::{to_txid, TxIdDigester};

    let pczt = pczt::Pczt::parse(pczt_bytes).map_err(|e| format!("Parse PCZT: {e:?}"))?;
    if pczt.global().inputs_modifiable()
        || pczt.global().outputs_modifiable()
        || pczt.global().shielded_modifiable()
    {
        return Err("PCZT IO is not finalized".to_string());
    }

    let effects = pczt
        .into_effects()
        .map_err(|e| format!("Extract PCZT effects: {e:?}"))?;
    let txid_parts = effects.digest(TxIdDigester);
    Ok(to_txid(
        effects.version(),
        effects.consensus_branch_id(),
        &txid_parts,
    ))
}

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

/// The Orchard circuit version implied by a PCZT's `consensus_branch_id`.
///
/// Per ZIP 229 the Orchard bundle format — and therefore the circuit its
/// proofs are built and verified with — is keyed on the consensus branch, NOT
/// the transaction version (the pczt crate's `orchard_bundle_format` applies
/// the same branch-keyed mapping when parsing the bundle). In particular a
/// post-NU6.3 legacy-V5 transaction still carries an `orchard_v3`-format
/// bundle, so it needs the post-NU6.3 keys; branches at or before NU6.2 use
/// the fixed post-NU6.2 circuit (never the insecure pre-NU6.2 one — the
/// wallet only proves new transactions, never reconstructs historical keys).
fn orchard_circuit_version_for_consensus_branch(
    consensus_branch_id: u32,
) -> orchard::circuit::OrchardCircuitVersion {
    if matches!(
        zcash_protocol::consensus::BranchId::try_from(consensus_branch_id),
        Ok(zcash_protocol::consensus::BranchId::Nu6_3)
    ) {
        return ironwood_orchard_circuit_version();
    }
    orchard::circuit::OrchardCircuitVersion::FixedPostNu6_2
}

/// Selects the cached Orchard proving key for the circuit implied by a PCZT's
/// consensus branch (see [`orchard_circuit_version_for_consensus_branch`]).
fn orchard_proving_key_for_consensus_branch(
    consensus_branch_id: u32,
) -> &'static orchard::circuit::ProvingKey {
    if orchard_circuit_version_for_consensus_branch(consensus_branch_id)
        == orchard::circuit::OrchardCircuitVersion::PostNu6_3
    {
        ironwood_orchard_proving_key()
    } else {
        legacy_orchard_proving_key()
    }
}

/// Builds the Orchard verifying key for the circuit implied by a PCZT's
/// consensus branch (see [`orchard_circuit_version_for_consensus_branch`]).
fn orchard_verifying_key_for_consensus_branch(
    consensus_branch_id: u32,
) -> orchard::circuit::VerifyingKey {
    orchard::circuit::VerifyingKey::build(orchard_circuit_version_for_consensus_branch(
        consensus_branch_id,
    ))
}

fn ironwood_orchard_circuit_version() -> orchard::circuit::OrchardCircuitVersion {
    orchard::circuit::OrchardCircuitVersion::PostNu6_3
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
/// explicitly to release the stored proposal. After this function succeeds,
/// the caller must also discard when the hardware flow ends so the retained
/// owner-scoped wallet lock is released.
pub async fn create_pczt_from_proposal(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    proposal_id: u64,
    send_flow_id: &str,
) -> Result<Vec<u8>, String> {
    use zcash_client_backend::data_api::wallet::create_pczt_from_proposal as zcb_create_pczt;
    use zcash_client_backend::wallet::OvkPolicy;

    // Consume the proposal up-front (matches execute_proposal), so
    // that any later failure path leaves the PROPOSAL_STORE clean.
    let stored = consume_stored_proposal(
        proposal_id,
        send_flow_id,
        "Proposal not found (expired or already consumed)",
    )?;

    let proposal_lock = match stored_proposal_lock(stored.proposal_id, &stored.send_flow_id) {
        Ok(lock) => lock,
        Err(error) => {
            return match finish_stored_proposal(stored.proposal_id, &stored.send_flow_id, true) {
                Ok(()) => Err(error),
                Err(cleanup_error) => Err(format!(
                    "{error}; additionally failed to release proposal inputs: {cleanup_error}"
                )),
            };
        }
    };
    if proposal_lock.db_path != db_path || proposal_lock.network != network {
        let error = "Proposal belongs to a different wallet database or network".to_string();
        return match finish_stored_proposal(stored.proposal_id, &stored.send_flow_id, true) {
            Ok(()) => Err(error),
            Err(cleanup_error) => Err(format!(
                "{error}; additionally failed to release proposal inputs: {cleanup_error}"
            )),
        };
    }
    let live_expiry_height = match super::send::live_send_expiry_height(
        lightwalletd_url,
        zcash_protocol::consensus::BlockHeight::from(stored.proposal.min_target_height()),
    )
    .await
    {
        Ok(height) => height,
        Err(error) => {
            return match finish_stored_proposal(stored.proposal_id, &stored.send_flow_id, true) {
                Ok(()) => Err(error),
                Err(cleanup_error) => Err(format!(
                    "{error}; additionally failed to release proposal inputs: {cleanup_error}"
                )),
            };
        }
    };

    let result = with_wallet_db_write_lock("pczt.create_pczt_from_proposal", || {
        // The live-tip request above yields to Dart. A concurrent cancel may
        // have released this proposal while it was in flight, so re-check the
        // process-local capability after acquiring the wallet write lock and
        // before recreating any DB lock.
        let current_lock = stored_proposal_lock(stored.proposal_id, &stored.send_flow_id)?;
        if current_lock.owner != proposal_lock.owner
            || current_lock.db_path != proposal_lock.db_path
            || current_lock.network != proposal_lock.network
        {
            return Err(
                "Hardware proposal input lock changed while refreshing chain tip".to_string(),
            );
        }
        let mut db = open_wallet_db(db_path, network)?;
        db.lock_outputs(
            &super::send::proposal_input_refs(&stored.proposal),
            current_lock.owner,
            live_expiry_height,
        )
        .map_err(|e| format!("Revalidate hardware proposal input locks: {e:?}"))?;
        super::proposal_locks::update_expiry(db_path, current_lock.owner, live_expiry_height)?;
        // The transaction version rides on the proposal; expiry is pinned to
        // the live chain tip obtained immediately before this DB operation.
        let proposal_for_pczt = stored
            .proposal
            .clone()
            .with_proposed_version(stored.proposed_tx_version);
        let pczt = zcb_create_pczt::<_, _, Infallible, _, Infallible, _>(
            &mut db,
            &network,
            stored.account_id,
            OvkPolicy::Sender,
            &proposal_for_pczt,
            Some(live_expiry_height),
            BundlePadding::DEFAULT,
        )
        .map_err(|e| format!("Create PCZT failed: {e}"))?;
        let pczt_bytes = pczt
            .serialize()
            .map_err(|e| format!("Serialize PCZT: {e:?}"))?;

        // From this point the PCZT may leave the process and later be
        // broadcast. Persist the conservative restart policy before releasing
        // the wallet write lock, closing both the cancel/re-lock race and the
        // crash window before a follow-up retain FFI call. The in-memory
        // capability remains, so ordinary cancellation can still unlock it.
        super::proposal_locks::mark_retain_until_expiry(db_path, current_lock.owner)?;
        Ok(pczt_bytes)
    });

    match result {
        Ok(pczt_bytes) => Ok(pczt_bytes),
        Err(error) => {
            match finish_stored_proposal(stored.proposal_id, &stored.send_flow_id, true) {
                Ok(()) => Err(error),
                Err(cleanup_error) => Err(format!(
                    "{error}; additionally failed to release proposal inputs: {cleanup_error}"
                )),
            }
        }
    }
}

/// Creates the two dependent ZIP-320 PCZTs used by Keystone's non-batch
/// signer. The first PCZT fixes the ephemeral output and therefore its txid;
/// the second replaces the proposal's prior-step reference with that exact
/// outpoint while retaining the wallet's ephemeral BIP32 metadata.
pub async fn create_tex_pczts_from_proposal(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    proposal_id: u64,
    send_flow_id: &str,
) -> Result<TexPcztPair, String> {
    use zcash_client_backend::data_api::wallet::create_pczt_from_proposal as zcb_create_pczt;
    use zcash_client_backend::wallet::OvkPolicy;

    let stored = consume_stored_proposal(
        proposal_id,
        send_flow_id,
        "Proposal not found (expired or already consumed)",
    )?;
    if stored.proposal.steps().len() != 2 {
        let _ = finish_stored_proposal(stored.proposal_id, &stored.send_flow_id, true);
        return Err("Keystone TEX signing requires exactly two proposal steps".to_string());
    }
    let proposal_lock = match stored_proposal_lock(stored.proposal_id, &stored.send_flow_id) {
        Ok(lock) => lock,
        Err(error) => {
            let _ = finish_stored_proposal(stored.proposal_id, &stored.send_flow_id, true);
            return Err(error);
        }
    };
    if proposal_lock.db_path != db_path || proposal_lock.network != network {
        let _ = finish_stored_proposal(stored.proposal_id, &stored.send_flow_id, true);
        return Err("Proposal belongs to a different wallet database or network".to_string());
    }
    let live_expiry_height = match super::send::live_send_expiry_height(
        lightwalletd_url,
        zcash_protocol::consensus::BlockHeight::from(stored.proposal.min_target_height()),
    )
    .await
    {
        Ok(height) => height,
        Err(error) => {
            let _ = finish_stored_proposal(stored.proposal_id, &stored.send_flow_id, true);
            return Err(error);
        }
    };

    let result = with_wallet_db_write_lock("pczt.create_tex_pczts_from_proposal", || {
        let current_lock = stored_proposal_lock(stored.proposal_id, &stored.send_flow_id)?;
        if current_lock.owner != proposal_lock.owner
            || current_lock.db_path != proposal_lock.db_path
            || current_lock.network != proposal_lock.network
        {
            return Err(
                "Hardware proposal input lock changed while refreshing chain tip".to_string(),
            );
        }
        let mut db = open_wallet_db(db_path, network)?;
        db.lock_outputs(
            &super::send::proposal_input_refs(&stored.proposal),
            current_lock.owner,
            live_expiry_height,
        )
        .map_err(|e| format!("Revalidate hardware proposal input locks: {e:?}"))?;
        super::proposal_locks::update_expiry(db_path, current_lock.owner, live_expiry_height)?;

        let first_step = stored.proposal.steps().first().clone();
        let first_proposal = singleton_proposal(&stored.proposal, first_step.clone())?;
        let first_pczt = zcb_create_pczt::<_, _, Infallible, _, Infallible, _>(
            &mut db,
            &network,
            stored.account_id,
            OvkPolicy::Sender,
            &first_proposal,
            Some(live_expiry_height),
            BundlePadding::DEFAULT,
        )
        .map_err(|e| format!("Create TEX PCZT step 1 failed: {e}"))?;

        let second_source = stored.proposal.steps().last();
        if second_source.prior_step_inputs().len() != 1 {
            return Err("TEX proposal step 2 must spend exactly one prior output".to_string());
        }
        let prior = second_source.prior_step_inputs()[0];
        if prior.step_index() != 0 {
            return Err("TEX proposal step 2 references the wrong prior step".to_string());
        }
        let expected_value = match prior.output_index() {
            StepOutputIndex::Change(index) => first_step
                .balance()
                .proposed_change()
                .get(index)
                .filter(|change| change.is_ephemeral())
                .map(|change| change.value())
                .ok_or("TEX proposal does not reference ephemeral change")?,
            StepOutputIndex::Payment(_) => {
                return Err("TEX proposal must reference ephemeral change".to_string())
            }
        };
        let first_effects = first_pczt
            .clone()
            .into_effects()
            .map_err(|e| format!("Extract TEX PCZT step 1 effects: {e:?}"))?;
        let outputs = &first_effects
            .transparent_bundle()
            .ok_or("TEX PCZT step 1 has no transparent output")?
            .vout;
        let output_index = tex_ephemeral_output_index(outputs, expected_value, |address| {
            db.get_transparent_address_metadata(stored.account_id, address)
                .map(|metadata| metadata.and_then(|metadata| metadata.source().scope()))
                .map_err(|e| format!("Read TEX ephemeral address metadata: {e}"))
        })?;
        let txout = outputs
            .get(output_index)
            .ok_or("TEX ephemeral output index is missing from transaction effects")?;
        let ephemeral_address = txout
            .recipient_address()
            .ok_or("TEX ephemeral output has an unsupported script")?;
        let address_metadata = db
            .get_transparent_address_metadata(stored.account_id, &ephemeral_address)
            .map_err(|e| format!("Read TEX ephemeral address metadata: {e}"))?
            .ok_or("TEX ephemeral address metadata is missing")?;
        let scope = address_metadata
            .source()
            .scope()
            .filter(|scope| *scope == TransparentKeyScope::EPHEMERAL)
            .ok_or("TEX output is not derived from the ephemeral scope")?;
        let address_index = address_metadata
            .source()
            .address_index()
            .ok_or("TEX ephemeral output address index is missing")?;
        let account = db
            .get_account(stored.account_id)
            .map_err(|e| format!("Read TEX account: {e}"))?
            .ok_or("TEX account is missing")?;
        let account_derivation = account
            .source()
            .key_derivation()
            .ok_or("TEX hardware account derivation metadata is missing")?;
        let transparent_fvk = account
            .ufvk()
            .and_then(|ufvk| ufvk.transparent())
            .ok_or("TEX hardware account has no transparent viewing key")?;
        let ephemeral_pubkey = transparent_fvk
            .derive_address_pubkey(scope, address_index)
            .map_err(|e| format!("Derive TEX ephemeral public key: {e}"))?
            .serialize();
        let hardened = 1 << 31;
        let ephemeral_derivation = transparent::pczt::Bip32Derivation::parse(
            account_derivation.seed_fingerprint().to_bytes(),
            vec![
                44 | hardened,
                network.network_type().coin_type() | hardened,
                u32::from(account_derivation.account_index()) | hardened,
                2,
                address_index.index(),
            ],
        )
        .map_err(|e| format!("Build TEX ephemeral BIP 44 derivation: {e:?}"))?;
        let first_bytes = first_pczt
            .serialize()
            .map_err(|e| format!("Serialize TEX PCZT step 1: {e:?}"))?;
        let first_signer_bytes = prepare_tex_pczt_for_keystone(
            &first_bytes,
            network,
            Some((output_index, ephemeral_pubkey, ephemeral_derivation)),
        )?;
        let first_txid = txid_from_io_finalized_pczt(&first_bytes)?;
        let explicit_input = WalletTransparentOutput::from_parts(
            OutPoint::new(*first_txid.as_ref(), output_index as u32),
            txout.clone(),
            None,
            Some(()),
            Some(TransparentKeyScope::EPHEMERAL),
            None,
        )
        .ok_or("TEX ephemeral output has an unsupported script")?;
        let second_step = Step::from_parts(
            &[],
            second_source.transaction_request().clone(),
            second_source.payment_pools().clone(),
            vec![explicit_input],
            second_source.shielded_inputs().cloned(),
            second_source.anchor_height(),
            vec![],
            second_source.balance().clone(),
            second_source.is_shielding(),
            network.is_nu_active(
                zcash_protocol::consensus::NetworkUpgrade::Nu6_3,
                zcash_protocol::consensus::BlockHeight::from(stored.proposal.min_target_height()),
            ),
        )
        .map_err(|e| format!("Build TEX PCZT step 2: {e}"))?;
        let second_proposal = singleton_proposal(&stored.proposal, second_step)?;
        let second_pczt = zcb_create_pczt::<_, _, Infallible, _, Infallible, _>(
            &mut db,
            &network,
            stored.account_id,
            OvkPolicy::Sender,
            &second_proposal,
            Some(live_expiry_height),
            BundlePadding::DEFAULT,
        )
        .map_err(|e| format!("Create TEX PCZT step 2 failed: {e}"))?;
        let second_inputs = second_pczt.transparent().inputs();
        if second_inputs.len() != 1
            || second_inputs[0].prevout_txid() != first_txid.as_ref()
            || *second_inputs[0].prevout_index() != output_index as u32
        {
            return Err("TEX PCZT step 2 does not spend the exact step 1 output".to_string());
        }
        let second_bytes = second_pczt
            .serialize()
            .map_err(|e| format!("Serialize TEX PCZT step 2: {e:?}"))?;
        let second_signer_bytes = prepare_tex_pczt_for_keystone(&second_bytes, network, None)?;

        super::proposal_locks::mark_retain_until_expiry(db_path, current_lock.owner)?;
        Ok(TexPcztPair {
            pczts: vec![first_bytes, second_bytes],
            signer_pczts: vec![first_signer_bytes, second_signer_bytes],
        })
    });
    if result.is_err() {
        let _ = finish_stored_proposal(stored.proposal_id, &stored.send_flow_id, true);
    }
    result
}

/// Release a stored proposal without executing it. Called from the
/// Dart send flow when the user cancels before
/// [`create_pczt_from_proposal`] (e.g. dismisses the confirmation
/// dialog, cancels the Sapling params download prompt). Idempotent:
/// safe to call for a proposal that has already been consumed or
/// never existed.
pub fn discard_proposal(proposal_id: u64, send_flow_id: &str) -> Result<(), String> {
    discard_stored_proposal(proposal_id, send_flow_id)
}

/// Forget the in-memory proposal capability while leaving its wallet input
/// lock in place until the proposal's original expiry height.
///
/// Call this after a broadcast result that may have reached the network but
/// could not be stored locally. It prevents an immediate conflicting send.
pub fn retain_proposal_lock_until_expiry(
    proposal_id: u64,
    send_flow_id: &str,
) -> Result<(), String> {
    retain_stored_proposal_lock_until_expiry(proposal_id, send_flow_id)
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
    let consensus_branch_id = *pczt.global().consensus_branch_id();

    let mut prover = Prover::new(pczt);

    if prover.requires_orchard_proof() {
        prover = prover
            .create_orchard_proof(orchard_proving_key_for_consensus_branch(
                consensus_branch_id,
            ))
            .map_err(|e| format!("Orchard proof: {e:?}"))?;
    }

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

    prover
        .finish()
        .serialize()
        .map_err(|e| format!("Serialize PCZT with proofs: {e:?}"))
}

/// Redact information from a PCZT that the signer role doesn't need
/// (witnesses, proprietary metadata). Produces the bytes to send to
/// the hardware wallet for signing.
pub fn redact_pczt_for_signer(pczt_bytes: &[u8]) -> Result<Vec<u8>, String> {
    redact_pczt_for_signer_inner(pczt_bytes, false)
}

/// Redact a PCZT for a Keystone **migration batch** request.
///
/// The v6 path uses librustzcash's batch signer policy, including its checked
/// compaction of regenerable Orchard and Ironwood fields. Keystone requires an
/// entirely unsigned batch request, so this additionally removes signatures
/// retained on preauthorized padding spends. The wallet keeps the unredacted
/// PCZT for proof and signature combination.
///
/// Only use this for the migration batch flow; the single-transaction hardware
/// send keeps [`redact_pczt_for_signer`].
pub fn redact_pczt_for_batch_signer(pczt_bytes: &[u8]) -> Result<Vec<u8>, String> {
    redact_pczt_for_signer_inner(pczt_bytes, true)
}

/// Applies the standard signer policy, plus Keystone's additional migration
/// batch redaction when requested.
fn apply_signer_redaction(pczt: pczt::Pczt, for_batch: bool) -> pczt::Pczt {
    use pczt::roles::redactor::Redactor;

    // The compact signer view requires PCZT v2, while legacy v5 signing uses
    // v1 on the wire. Keep the existing local policy for v5 and ordinary sends.
    let compact =
        for_batch && *pczt.global().tx_version() == zcash_protocol::constants::V6_TX_VERSION;
    let pczt = if compact {
        zcash_client_backend::data_api::wallet::redact_pczt_for_batch_signer(&pczt)
    } else {
        pczt
    };

    fn redact_bundle(r: &mut pczt::roles::redactor::orchard::OrchardRedactor<'_>, compact: bool) {
        r.redact_actions(|mut ar| {
            ar.clear_spend_witness();
            ar.redact_output_proprietary("zcash_client_backend:output_info");
            if compact {
                // librustzcash retains signatures for preauthorized protocol
                // padding spends. Keystone's batch protocol rejects any
                // request containing a spend-authorization signature; the
                // wallet-owned base retains these signatures for extraction.
                ar.clear_spend_auth_sig();
            }
        });
    }

    let mut redactor = Redactor::new(pczt)
        .redact_global_with(|mut r| r.redact_proprietary("zcash_client_backend:proposal_info"))
        .redact_orchard_with(|mut r| {
            redact_bundle(&mut r, compact);
        });

    redactor = redactor.redact_ironwood_with(|mut r| {
        redact_bundle(&mut r, compact);
    });

    redactor
        .redact_sapling_with(|mut r| {
            // The generic helper retains Sapling witnesses for signers that
            // verify nullifiers. Preserve Keystone's existing omission.
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
        .finish()
}

/// Shared parser and serializer for [`redact_pczt_for_signer`] and
/// [`redact_pczt_for_batch_signer`].
fn redact_pczt_for_signer_inner(pczt_bytes: &[u8], for_batch: bool) -> Result<Vec<u8>, String> {
    let pczt = pczt::Pczt::parse(pczt_bytes).map_err(|e| format!("Parse PCZT: {e:?}"))?;

    serialize_signer_view(apply_signer_redaction(pczt, for_batch))
}

fn serialize_signer_view(pczt: pczt::Pczt) -> Result<Vec<u8>, String> {
    if *pczt.global().tx_version() == 5 {
        pczt::v1::Pczt::try_from(pczt)
            .map_err(|e| format!("Serialize legacy PCZT for signer: {e:?}"))
            .map(|v1| v1.serialize())
    } else {
        pczt.serialize()
            .map_err(|e| format!("Serialize PCZT for signer: {e:?}"))
    }
}

/// Replaces a deferred v6 Orchard anchor and sets spend witnesses selected by
/// their nullifiers.
///
/// Nullifiers are resolved before the PCZT is mutated. Every requested
/// nullifier must be unique and must identify exactly one action, preventing a
/// witness from being silently applied to the wrong spend when action order is
/// randomized. The existing anchor is cleared because staged transactions are
/// initially constructed with a placeholder anchor; the upstream Updater then
/// enforces that the transaction format supports deferred anchor updates and
/// that no proof is already present.
pub(crate) fn set_orchard_anchor_and_witnesses<'a>(
    pczt_bytes: &[u8],
    anchor: orchard::Anchor,
    spend_witnesses: impl IntoIterator<Item = (&'a str, &'a orchard::tree::MerklePath)>,
) -> Result<Vec<u8>, String> {
    use pczt::roles::{redactor::Redactor, updater::Updater};

    let pczt = pczt::Pczt::parse(pczt_bytes).map_err(|e| format!("Parse PCZT: {e:?}"))?;
    let mut requested_nullifiers = std::collections::HashSet::new();
    let mut witness_updates = Vec::new();
    for (spend_nullifier_hex, witness) in spend_witnesses {
        let spend_nullifier = parse_32_byte_hex(spend_nullifier_hex, "Orchard spend nullifier")?;
        if !requested_nullifiers.insert(spend_nullifier) {
            return Err("Duplicate Orchard spend nullifier requested".to_string());
        }

        let mut action_indices =
            pczt.orchard()
                .actions()
                .iter()
                .enumerate()
                .filter_map(|(index, action)| {
                    (*action.spend().nullifier() == spend_nullifier).then_some(index)
                });
        let action_index = action_indices
            .next()
            .ok_or_else(|| "Orchard spend nullifier not found in PCZT".to_string())?;
        if action_indices.next().is_some() {
            return Err("Orchard spend nullifier matched multiple PCZT actions".to_string());
        }
        witness_updates.push((action_index, witness.clone()));
    }
    if witness_updates.is_empty() {
        return Err("No Orchard spend witnesses provided".to_string());
    }

    let pczt = Redactor::new(pczt)
        .redact_orchard_with(|mut redactor| redactor.clear_anchor())
        .finish();
    let updated = Updater::new(pczt)
        .set_orchard_anchor(anchor)
        .map_err(|e| format!("Set Orchard anchor in PCZT: {e}"))?
        .set_orchard_spend_witnesses(witness_updates)
        .map_err(|e| format!("Set Orchard witnesses in PCZT: {e}"))?
        .finish();

    updated
        .serialize()
        .map_err(|e| format!("Serialize updated PCZT: {e:?}"))
}

pub(crate) fn set_orchard_anchor_and_witness(
    pczt_bytes: &[u8],
    anchor: orchard::Anchor,
    witness: &orchard::tree::MerklePath,
    spend_nullifier_hex: &str,
) -> Result<Vec<u8>, String> {
    set_orchard_anchor_and_witnesses(pczt_bytes, anchor, [(spend_nullifier_hex, witness)])
}

fn parse_32_byte_hex(value: &str, label: &str) -> Result<[u8; 32], String> {
    let mut bytes = [0u8; 32];
    hex::decode_to_slice(value, &mut bytes).map_err(|e| format!("Decode {label}: {e}"))?;
    Ok(bytes)
}

fn combine_pczts(proofs: &[u8], sigs: &[u8]) -> Result<pczt::Pczt, String> {
    use pczt::roles::{combiner::Combiner, redactor::Redactor};

    let p = pczt::Pczt::parse(proofs).map_err(|e| format!("Parse PCZT with proofs: {e:?}"))?;
    let s = pczt::Pczt::parse(sigs).map_err(|e| format!("Parse PCZT with signatures: {e:?}"))?;
    // The signer view may normalize a TEX output's display-only `user_address`
    // to its legacy t-address for Keystone. The wallet-owned proof PCZT keeps
    // the authoritative TEX metadata, so do not let the signer copy conflict
    // with or replace it during the merge.
    let s = Redactor::new(s)
        .redact_transparent_with(|mut redactor| {
            redactor.redact_outputs(|mut output| output.clear_user_address());
        })
        .finish();
    Combiner::new(vec![p, s])
        .combine()
        .map_err(|e| format!("Combine PCZTs: {e:?}"))
}

fn ensure_signed_pczt_matches_base(proofs: &[u8], sigs: &[u8]) -> Result<(), String> {
    let expected = txid_from_io_finalized_pczt(proofs)?;
    let actual = txid_from_io_finalized_pczt(sigs)?;
    if expected != actual {
        return Err("Signed PCZT transaction effects do not match the requested PCZT".to_string());
    }
    Ok(())
}

fn ensure_tex_pczt_dependency(proofs: &[Vec<u8>]) -> Result<(), String> {
    if proofs.len() != 2 {
        return Ok(());
    }
    let first_txid = txid_from_io_finalized_pczt(&proofs[0])?;
    let second = pczt::Pczt::parse(&proofs[1])
        .map_err(|error| format!("Parse TEX PCZT round 2: {error:?}"))?;
    let inputs = second.transparent().inputs();
    if inputs.len() != 1 || inputs[0].prevout_txid() != first_txid.as_ref() {
        return Err(
            "TEX signed PCZT round 2 does not spend the exact round 1 transaction".to_string(),
        );
    }
    Ok(())
}

/// Load the Sapling spend/output verifying keys from local params files, when
/// both paths are provided. Migration PCZTs are Orchard/Ironwood-only and pass
/// `None`; see invariant (3) in the module docstring for when params are
/// required.
fn load_sapling_verifying_keys(
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Option<(
    sapling_crypto::circuit::SpendVerifyingKey,
    sapling_crypto::circuit::OutputVerifyingKey,
)> {
    match (spend_params_path, output_params_path) {
        (Some(sp), Some(op)) if !sp.is_empty() && !op.is_empty() => {
            let prover = LocalTxProver::new(std::path::Path::new(sp), std::path::Path::new(op));
            Some(prover.verifying_keys())
        }
        _ => None,
    }
}

/// Finalize transparent spends and extract the fully-authorized transaction
/// from a combined PCZT (proofs + signatures already merged).
///
/// This is the single, shared tail of every extraction path. Both
/// [`extract_transaction_from_pczt`] (which combines a proofs-PCZT with a full
/// redacted signed PCZT) and [`apply_sigs_and_extract`] (which applies a
/// compact signature list directly onto the proofs-PCZT) funnel into here, so
/// the two produce identical transactions by construction.
fn finalize_and_extract(
    combined: pczt::Pczt,
    sapling_vks: Option<&(
        sapling_crypto::circuit::SpendVerifyingKey,
        sapling_crypto::circuit::OutputVerifyingKey,
    )>,
) -> Result<ExtractedPcztTransaction, String> {
    use pczt::roles::spend_finalizer::SpendFinalizer;
    use pczt::roles::tx_extractor::TransactionExtractor;

    let finalized_pczt = SpendFinalizer::new(combined)
        .finalize_spends()
        .map_err(|e| format!("Finalize transparent spends in PCZT: {e:?}"))?;

    let consensus_branch_id = *finalized_pczt.global().consensus_branch_id();
    // A single branch-keyed verifying key covers every Orchard-shaped bundle:
    // the Orchard and Ironwood bundles of a v6 transaction share the
    // post-NU6.3 circuit (see `orchard_circuit_version_for_consensus_branch`).
    let orchard_vk = orchard_verifying_key_for_consensus_branch(consensus_branch_id);

    let mut extractor = TransactionExtractor::new(finalized_pczt).with_orchard(&orchard_vk);
    if let Some((spend_vk, output_vk)) = sapling_vks {
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

pub(crate) fn extract_transaction_from_pczt(
    pczt_with_proofs_bytes: &[u8],
    pczt_with_signatures_bytes: &[u8],
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<ExtractedPcztTransaction, String> {
    let sapling_vks = load_sapling_verifying_keys(spend_params_path, output_params_path);
    ensure_signed_pczt_matches_base(pczt_with_proofs_bytes, pczt_with_signatures_bytes)?;
    let combined = combine_pczts(pczt_with_proofs_bytes, pczt_with_signatures_bytes)?;
    finalize_and_extract(combined, sapling_vks.as_ref())
}

struct PreparedSignedPczt {
    combined: pczt::Pczt,
    extracted: ExtractedPcztTransaction,
}

#[derive(Debug, PartialEq, Eq)]
enum PcztBroadcastAttempt {
    Accepted,
    TransportUnknown(String),
    DefiniteRejection(String),
    RouteUnavailable(String),
}

#[derive(Debug, PartialEq, Eq)]
struct PcztBroadcastPlan {
    persisted_prefix_len: usize,
    broadcasted_count: u32,
    status: &'static str,
    message: Option<String>,
}

#[derive(Debug, PartialEq, Eq)]
enum PcztBroadcastStep {
    Continue,
    Stop(PcztBroadcastPlan),
    Fail(String),
}

fn pczt_broadcast_step(
    index: usize,
    total_count: usize,
    attempt: PcztBroadcastAttempt,
) -> PcztBroadcastStep {
    match attempt {
        PcztBroadcastAttempt::Accepted if index + 1 < total_count => {
            PcztBroadcastStep::Continue
        }
        PcztBroadcastAttempt::Accepted => PcztBroadcastStep::Stop(PcztBroadcastPlan {
            persisted_prefix_len: index + 1,
            broadcasted_count: (index + 1) as u32,
            status: StoreAndBroadcastPcztsResult::BROADCASTED,
            message: None,
        }),
        PcztBroadcastAttempt::TransportUnknown(error) => {
            PcztBroadcastStep::Stop(PcztBroadcastPlan {
                // SendTransaction began, so this PCZT may already be on the
                // network and must be persisted for conservative recovery.
                persisted_prefix_len: index + 1,
                broadcasted_count: index as u32,
                status: if index == 0 {
                    StoreAndBroadcastPcztsResult::BROADCAST_UNKNOWN
                } else {
                    StoreAndBroadcastPcztsResult::PARTIAL_BROADCAST
                },
                message: Some(format!(
                    "Transaction {} of {total_count} has an unknown broadcast result: {error}",
                    index + 1
                )),
            })
        }
        PcztBroadcastAttempt::DefiniteRejection(error) if index == 0 => {
            PcztBroadcastStep::Fail(error)
        }
        PcztBroadcastAttempt::DefiniteRejection(error) => {
            PcztBroadcastStep::Stop(PcztBroadcastPlan {
                // The rejected PCZT itself must not be persisted. Only the
                // already-accepted dependency prefix is safe to store.
                persisted_prefix_len: index,
                broadcasted_count: index as u32,
                status: StoreAndBroadcastPcztsResult::PARTIAL_BROADCAST,
                message: Some(format!(
                    "Transaction {} of {total_count} was rejected and was not stored: {error}",
                    index + 1
                )),
            })
        }
        PcztBroadcastAttempt::RouteUnavailable(error) if index == 0 => {
            PcztBroadcastStep::Fail(error)
        }
        PcztBroadcastAttempt::RouteUnavailable(error) => {
            PcztBroadcastStep::Stop(PcztBroadcastPlan {
                persisted_prefix_len: index,
                broadcasted_count: index as u32,
                status: StoreAndBroadcastPcztsResult::PARTIAL_BROADCAST,
                message: Some(format!(
                    "Failed to open the broadcast route for transaction {} of {total_count}; it was not stored: {error}",
                    index + 1
                )),
            })
        }
    }
}

fn release_pczt_proposal_after_failure<T>(
    proposal_id: u64,
    send_flow_id: &str,
    error: String,
) -> Result<T, String> {
    match finish_stored_proposal(proposal_id, send_flow_id, true) {
        Ok(()) => Err(error),
        Err(cleanup_error) => Err(format!(
            "{error}; additionally failed to release proposal inputs: {cleanup_error}"
        )),
    }
}

fn release_signed_pczt_operation_after_failure<T>(
    proposal: Option<(u64, &str)>,
    error: String,
) -> Result<T, String> {
    match proposal {
        Some((proposal_id, send_flow_id)) => {
            release_pczt_proposal_after_failure(proposal_id, send_flow_id, error)
        }
        None => Err(error),
    }
}

fn prepare_signed_pczts(
    proofs: &[Vec<u8>],
    signatures: &[Vec<u8>],
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<Vec<PreparedSignedPczt>, String> {
    if proofs.is_empty() || proofs.len() != signatures.len() {
        return Err("Invalid signed PCZT round count".to_string());
    }
    ensure_tex_pczt_dependency(proofs)?;
    let sapling_vks = load_sapling_verifying_keys(spend_params_path, output_params_path);
    let mut seen = std::collections::HashSet::new();
    let prepared = proofs
        .iter()
        .zip(signatures)
        .enumerate()
        .map(|(index, (proof, signature))| {
            ensure_signed_pczt_matches_base(proof, signature)?;
            let combined = combine_pczts(proof, signature)?;
            let extracted = finalize_and_extract(combined.clone(), sapling_vks.as_ref())
                .map_err(|error| format!("Validate signed PCZT round {}: {error}", index + 1))?;
            if !seen.insert(extracted.txid) {
                return Err("Duplicate signed PCZT transaction".to_string());
            }
            Ok(PreparedSignedPczt {
                combined,
                extracted,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    if prepared.len() == 2 {
        let second_inputs = prepared[1]
            .extracted
            .tx
            .transparent_bundle()
            .map(|bundle| bundle.vin.as_slice())
            .unwrap_or_default();
        if second_inputs.len() != 1
            || second_inputs[0].prevout().hash() != prepared[0].extracted.txid.as_ref()
        {
            return Err(
                "TEX signed PCZT round 2 does not spend the exact round 1 transaction".to_string(),
            );
        }
    }
    Ok(prepared)
}

pub(crate) fn validate_signed_pczts(
    proofs: &[Vec<u8>],
    signatures: &[Vec<u8>],
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<(), String> {
    prepare_signed_pczts(proofs, signatures, spend_params_path, output_params_path).map(|_| ())
}

/// Validates every signed PCZT, broadcasts it in dependency order, and then
/// atomically persists only the accepted-or-ambiguous prefix. Definite
/// rejections are never written to the wallet DB. The outer SQLite transaction
/// makes each PCZT-aware store participate in the same commit, so a later store
/// failure rolls back every earlier item in the prefix.
pub async fn store_and_broadcast_signed_pczts_for_proposal(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    proposal_id: u64,
    send_flow_id: &str,
    proofs: &[Vec<u8>],
    signatures: &[Vec<u8>],
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<StoreAndBroadcastPcztsResult, String> {
    let proposal_lock = match stored_proposal_lock(proposal_id, send_flow_id) {
        Ok(lock) => lock,
        Err(error) => {
            return release_pczt_proposal_after_failure(proposal_id, send_flow_id, error);
        }
    };
    if proposal_lock.db_path != db_path || proposal_lock.network != network {
        return release_pczt_proposal_after_failure(
            proposal_id,
            send_flow_id,
            "Proposal belongs to a different wallet database or network".to_string(),
        );
    }

    store_and_broadcast_signed_pczts_inner(
        db_path,
        lightwalletd_url,
        network,
        proofs,
        signatures,
        spend_params_path,
        output_params_path,
        Some((proposal_id, send_flow_id)),
    )
    .await
}

pub(crate) async fn store_and_broadcast_signed_pczts(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    proofs: &[Vec<u8>],
    signatures: &[Vec<u8>],
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<StoreAndBroadcastPcztsResult, String> {
    store_and_broadcast_signed_pczts_inner(
        db_path,
        lightwalletd_url,
        network,
        proofs,
        signatures,
        spend_params_path,
        output_params_path,
        None,
    )
    .await
}

async fn store_and_broadcast_signed_pczts_inner(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    proofs: &[Vec<u8>],
    signatures: &[Vec<u8>],
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
    proposal: Option<(u64, &str)>,
) -> Result<StoreAndBroadcastPcztsResult, String> {
    use zcash_client_backend::data_api::wallet::{
        decrypt_and_store_transaction, extract_and_store_transaction_from_pczt,
    };

    // This performs all correlation, dependency, signature, proof, and
    // finalization checks before either the DB or the network is touched.
    let prepared =
        match prepare_signed_pczts(proofs, signatures, spend_params_path, output_params_path) {
            Ok(prepared) => prepared,
            Err(error) => {
                return release_signed_pczt_operation_after_failure(proposal, error);
            }
        };
    let sapling_vks = load_sapling_verifying_keys(spend_params_path, output_params_path);

    let txids = prepared
        .iter()
        .map(|item| item.extracted.txid.to_string())
        .collect::<Vec<_>>();
    let txids_joined = txids.join(",");
    let total_count = prepared.len() as u32;

    // Resolve a live tip before touching either the DB or the network. An
    // already-expired set is terminal and must not be persisted as pending.
    let mut expiry_client =
        match crate::wallet::sync_engine::open_isolated_lwd_channel(lightwalletd_url).await {
            Ok(client) => client,
            Err(error) => {
                return release_signed_pczt_operation_after_failure(
                    proposal,
                    format!("Failed to open the broadcast route: {error}"),
                );
            }
        };
    let latest = match crate::wallet::sync_engine::get_latest_block(&mut expiry_client).await {
        Ok(latest) => latest,
        Err(error) => {
            return release_signed_pczt_operation_after_failure(
                proposal,
                format!("Failed to read the chain tip before broadcast: {error}"),
            );
        }
    };
    if let Some(error) = prepared.iter().find_map(|item| {
        pczt_broadcast_expiry_error(
            &item.extracted.txid,
            u32::from(item.extracted.tx.expiry_height()),
            latest.height,
        )
    }) {
        let result = StoreAndBroadcastPcztsResult {
            txids: txids_joined,
            status: StoreAndBroadcastPcztsResult::EXPIRED.to_string(),
            broadcasted_count: 0,
            total_count,
            message: Some(error.clone()),
        };
        return match proposal {
            Some((proposal_id, send_flow_id)) => {
                match finish_stored_proposal(proposal_id, send_flow_id, true) {
                    Ok(()) => Ok(result),
                    Err(cleanup_error) => Err(format!(
                        "{error}; additionally failed to release proposal inputs: {cleanup_error}"
                    )),
                }
            }
            None => Ok(result),
        };
    }
    let mut first_client = Some(expiry_client);
    let broadcast_plan = 'broadcast: loop {
        for (index, item) in prepared.iter().enumerate() {
            let client = if let Some(client) = first_client.take() {
                Ok(client)
            } else {
                crate::wallet::sync_engine::open_isolated_lwd_channel(lightwalletd_url).await
            };
            let mut client = match client {
                Ok(client) => client,
                Err(error) => {
                    match pczt_broadcast_step(
                        index,
                        prepared.len(),
                        PcztBroadcastAttempt::RouteUnavailable(error.to_string()),
                    ) {
                        PcztBroadcastStep::Continue => unreachable!(),
                        PcztBroadcastStep::Stop(plan) => break 'broadcast plan,
                        PcztBroadcastStep::Fail(error) => {
                            return release_signed_pczt_operation_after_failure(proposal, error);
                        }
                    }
                }
            };
            let attempt = match crate::wallet::sync_engine::send_transaction_with_status(
                &mut client,
                &item.extracted.raw_tx,
            )
            .await
            {
                Ok(response) => match super::broadcast::send_response_rejection_error(&response) {
                    Some(error) => PcztBroadcastAttempt::DefiniteRejection(error),
                    None => PcztBroadcastAttempt::Accepted,
                },
                Err(error) => PcztBroadcastAttempt::TransportUnknown(error.to_string()),
            };
            match pczt_broadcast_step(index, prepared.len(), attempt) {
                PcztBroadcastStep::Continue => {}
                PcztBroadcastStep::Stop(plan) => break 'broadcast plan,
                PcztBroadcastStep::Fail(error) => {
                    return release_signed_pczt_operation_after_failure(proposal, error);
                }
            }
        }
        unreachable!("a non-empty PCZT set always yields a terminal broadcast plan");
    };

    let store_result: Result<(), String> = with_wallet_db_write_lock(
        "pczt.store_broadcast_pczts",
        || {
            let mut db = open_wallet_db(db_path, network)?;
            let primary_result = db.transactionally(|transactional_db| {
                for (index, item) in prepared
                    .iter()
                    .take(broadcast_plan.persisted_prefix_len)
                    .enumerate()
                {
                    let consensus_branch_id = *item.combined.global().consensus_branch_id();
                    let orchard_vk =
                        orchard_verifying_key_for_consensus_branch(consensus_branch_id);
                    extract_and_store_transaction_from_pczt::<
                            _,
                            zcash_client_sqlite::ReceivedNoteId,
                        >(
                            transactional_db,
                            item.combined.clone(),
                            sapling_vks.as_ref().map(|(spend, output)| (spend, output)),
                            Some(&orchard_vk),
                        )
                        .map_err(|error| {
                            AtomicPcztStoreError::Store(format!(
                                "Store signed PCZT round {}: {error}",
                                index + 1
                            ))
                        })?;
                }
                Ok::<(), AtomicPcztStoreError>(())
            });
            if let Err(primary_error) = primary_result {
                log::warn!(
                    "keystone: atomic PCZT-aware storage failed after broadcast: {primary_error}. \
                 Falling back to chain-style transaction storage."
                );
                db.transactionally(|transactional_db| {
                for (index, item) in prepared
                    .iter()
                    .take(broadcast_plan.persisted_prefix_len)
                    .enumerate()
                {
                    decrypt_and_store_transaction(
                        &network,
                        transactional_db,
                        &item.extracted.tx,
                        None,
                    )
                    .map_err(|error| {
                        AtomicPcztStoreError::Store(format!(
                            "Fallback-store broadcast PCZT round {}: {error}",
                            index + 1
                        ))
                    })?;
                }
                Ok::<(), AtomicPcztStoreError>(())
            })
            .map_err(|fallback_error| {
                format!(
                    "Primary PCZT storage failed: {primary_error}. Fallback storage failed: {fallback_error}"
                )
            })?;
            }
            Ok(())
        },
    );

    if let Err(storage_error) = store_result {
        let retain_error = proposal
            .and_then(|(proposal_id, send_flow_id)| {
                retain_stored_proposal_lock_until_expiry(proposal_id, send_flow_id).err()
            })
            .map(|error| format!(" Proposal input-lock retention also failed: {error}."))
            .unwrap_or_default();
        let network_message = broadcast_plan
            .message
            .as_deref()
            .map(|message| format!("{message} "))
            .unwrap_or_default();
        return Ok(StoreAndBroadcastPcztsResult {
            txids: txids_joined,
            status: if broadcast_plan.broadcasted_count == total_count {
                StoreAndBroadcastPcztsResult::BROADCASTED_STORAGE_FAILED.to_string()
            } else {
                broadcast_plan.status.to_string()
            },
            broadcasted_count: broadcast_plan.broadcasted_count,
            total_count,
            message: Some(format!(
                "{network_message}A transaction may already be on the network, but local storage failed: {storage_error}. Do not send again until sync or an explorer confirms the result.{retain_error}"
            )),
        });
    }

    // The persisted network-touched prefix now owns recovery, so the original
    // proposal input lock is no longer needed.
    if let Some((proposal_id, send_flow_id)) = proposal {
        if let Err(error) = finish_stored_proposal(proposal_id, send_flow_id, false) {
            log::warn!(
                "keystone: transactions stored but proposal lock bookkeeping failed: {error}"
            );
        }
    }

    let message = broadcast_plan.message.map(|message| {
        format!(
            "{message} The accepted-or-ambiguous transaction prefix was stored locally for recovery."
        )
    });
    Ok(StoreAndBroadcastPcztsResult {
        txids: txids_joined,
        status: broadcast_plan.status.to_string(),
        broadcasted_count: broadcast_plan.broadcasted_count,
        total_count,
        message,
    })
}

/// Applies externally-produced Orchard-protocol spend-authorization
/// signatures to a parsed PCZT.
///
/// This is deliberately proof-agnostic. For v6 transactions, `Signer::new`
/// uses the pre-authorization sighash, and
/// `Signer::apply_orchard_spend_auth_signature` verifies each signature
/// against the selected action's `rk` before storing it.
fn apply_compact_orchard_spend_auth_signatures(
    pczt: pczt::Pczt,
    sigs: &[pczt::roles::signer::SpendAuthSignature],
) -> Result<pczt::Pczt, String> {
    use pczt::roles::signer::Signer;

    let mut signer = Signer::new(pczt).map_err(|e| format!("Create PCZT signer: {e:?}"))?;
    let mut seen_sigs = std::collections::HashSet::new();
    for action_sig in sigs {
        if !seen_sigs.insert((action_sig.value_pool(), action_sig.action_index())) {
            return Err(format!(
                "Duplicate compact signature for pool {:?} action {}",
                action_sig.value_pool(),
                action_sig.action_index()
            ));
        }
        signer
            .apply_orchard_spend_auth_signature(action_sig)
            .map_err(|e| {
                format!(
                    "Apply {:?} signature at action {}: {e:?}",
                    action_sig.value_pool(),
                    action_sig.action_index()
                )
            })?;
    }

    Ok(signer.finish())
}

/// Verifies a compact signature response against the wallet's unredacted,
/// IO-finalized base PCZT before any dependent transaction is broadcast.
///
/// The wallet-owned base has a useful invariant: the IO Finalizer has already
/// authorized true dummy spends, while real spends that require an external
/// signer still have no `spend_auth_sig`. Therefore `sigs` must contain exactly
/// one unique signature for every unsigned Orchard or Ironwood action and none
/// for an already-authorized dummy action. Every supplied signature is then
/// cryptographically verified by the upstream [`Signer`] role.
///
/// This does not require proofs, spend witnesses, or finalized v6 anchors. It
/// intentionally does not reverify the existing true-dummy signatures, which
/// were produced locally by the IO Finalizer and are not part of the device's
/// signing responsibility. The contract consequently requires the caller to
/// pass the wallet's own unmodified, unredacted base PCZT rather than the
/// signer-redacted transport copy.
///
/// [`Signer`]: pczt::roles::signer::Signer
pub(crate) fn preflight_orchard_spend_auth_signatures(
    base_pczt_bytes: &[u8],
    sigs: &[pczt::roles::signer::SpendAuthSignature],
) -> Result<(), String> {
    let pczt = pczt::Pczt::parse(base_pczt_bytes)
        .map_err(|e| format!("Parse base PCZT for signature preflight: {e:?}"))?;

    let required = unsigned_orchard_action_locations(&pczt);

    let mut provided = std::collections::HashSet::new();
    for action_sig in sigs {
        let location = (action_sig.value_pool(), action_sig.action_index());
        if !provided.insert(location) {
            return Err(format!(
                "Duplicate compact signature for pool {:?} action {}",
                action_sig.value_pool(),
                action_sig.action_index()
            ));
        }
        if !required.contains(&location) {
            return Err(format!(
                "Unexpected compact signature for pool {:?} action {}; the action is absent or already authorized",
                action_sig.value_pool(),
                action_sig.action_index()
            ));
        }
    }

    if provided.len() != required.len() {
        return Err(format!(
            "Missing {} required compact spend-authorization signature(s)",
            required.len() - provided.len()
        ));
    }

    apply_compact_orchard_spend_auth_signatures(pczt, sigs).map(|_| ())
}

fn unsigned_orchard_action_locations(
    pczt: &pczt::Pczt,
) -> std::collections::HashSet<(orchard::ValuePool, usize)> {
    pczt.orchard()
        .actions()
        .iter()
        .enumerate()
        .filter_map(|(action_index, action)| {
            action
                .spend()
                .spend_auth_sig()
                .is_none()
                .then_some((orchard::ValuePool::Orchard, action_index))
        })
        .chain(
            pczt.ironwood()
                .actions()
                .iter()
                .enumerate()
                .filter_map(|(action_index, action)| {
                    action
                        .spend()
                        .spend_auth_sig()
                        .is_none()
                        .then_some((orchard::ValuePool::Ironwood, action_index))
                }),
        )
        .collect()
}

/// Apply a compact, signatures-only response onto the wallet's own
/// proofs-PCZT, then finalize and extract the transaction — the wallet side of
/// the "signatures-only" round-trip.
///
/// This is the equivalent of [`extract_transaction_from_pczt`] for the compact
/// path: instead of receiving a full redacted signed PCZT back from the device
/// and combining it, the device returns only the produced spend-authorization
/// signatures (decoded into [`SpendAuthSignature`]s).
/// We load the proofs-PCZT the wallet already holds into the [`Signer`] role
/// and re-apply each signature by (pool, action index).
/// [`Signer::apply_orchard_spend_auth_signature`] verifies each signature
/// against the action before storing it, so an incorrect or mismatched
/// signature fails here rather than at broadcast. The finalize + extract tail
/// is shared with the full path via [`finalize_and_extract`], which guarantees
/// the two paths produce identical transaction bytes and txid.
///
/// `sigs` must be the decoded signatures for the single message whose
/// proofs-PCZT is passed in. Sapling params are only required when the PCZT
/// carries a non-empty Sapling bundle (see the module docstring); migration
/// PCZTs are Orchard/Ironwood-only and pass `None`.
///
/// [`SpendAuthSignature`]: pczt::roles::signer::SpendAuthSignature
/// [`Signer`]: pczt::roles::signer::Signer
pub(crate) fn apply_sigs_and_extract(
    pczt_with_proofs_bytes: &[u8],
    sigs: &[pczt::roles::signer::SpendAuthSignature],
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<ExtractedPcztTransaction, String> {
    let sapling_vks = load_sapling_verifying_keys(spend_params_path, output_params_path);

    let pczt = pczt::Pczt::parse(pczt_with_proofs_bytes)
        .map_err(|e| format!("Parse PCZT with proofs: {e:?}"))?;
    let signed = apply_compact_orchard_spend_auth_signatures(pczt, sigs)?;
    finalize_and_extract(signed, sapling_vks.as_ref())
}

/// Read the spend-authorization signatures out of a fully-signed PCZT as a
/// compact [`SpendAuthSignature`] list — the inverse of
/// [`apply_sigs_and_extract`]'s input.
///
/// This is the local-signing analogue of decoding a device's compact
/// `zcash-batch-sig-result`: the software migration path signs a base PCZT with the
/// USK and then needs only the produced signatures (not the whole signed PCZT)
/// to persist for later finalization, so the encrypted migration DB column
/// stores the same compact form the hardware path stores. Every Orchard and
/// Ironwood action whose spend carries a `spend_auth_sig` is emitted with its
/// pool and action index; actions without a signature are skipped.
///
/// [`SpendAuthSignature`]: pczt::roles::signer::SpendAuthSignature
pub(crate) fn extract_compact_sigs_from_signed_pczt(
    signed_pczt_bytes: &[u8],
) -> Result<Vec<pczt::roles::signer::SpendAuthSignature>, String> {
    let pczt =
        pczt::Pczt::parse(signed_pczt_bytes).map_err(|e| format!("Parse signed PCZT: {e:?}"))?;

    extract_compact_sigs_from_pczt(&pczt)
}

/// Extract only signatures for actions that were unsigned in `base_pczt_bytes`.
///
/// Locally signed PCZTs also contain the IO Finalizer's signatures for true
/// dummy padding spends. Those signatures are already present in the base and
/// are not part of the compact signer response persisted by migration flows.
pub(crate) fn extract_required_compact_sigs_from_signed_pczt(
    base_pczt_bytes: &[u8],
    signed_pczt_bytes: &[u8],
) -> Result<Vec<pczt::roles::signer::SpendAuthSignature>, String> {
    let base_pczt = pczt::Pczt::parse(base_pczt_bytes)
        .map_err(|e| format!("Parse base PCZT for compact signature extraction: {e:?}"))?;
    let required = unsigned_orchard_action_locations(&base_pczt);
    let mut sigs = extract_compact_sigs_from_signed_pczt(signed_pczt_bytes)?;
    sigs.retain(|sig| required.contains(&(sig.value_pool(), sig.action_index())));
    Ok(sigs)
}

/// Read and validate the compact spend-authorization signature list from an
/// already parsed signed PCZT.
pub(crate) fn extract_compact_sigs_from_pczt(
    signed_pczt: &pczt::Pczt,
) -> Result<Vec<pczt::roles::signer::SpendAuthSignature>, String> {
    let sigs = pczt::roles::signer::extract_orchard_spend_auth_signatures(signed_pczt);

    if sigs.is_empty() {
        return Err("Signed PCZT has no spend-authorization signatures".to_string());
    }
    Ok(sigs)
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
            let consensus_branch_id = *combined_pczt.global().consensus_branch_id();
            let orchard_vk = orchard_verifying_key_for_consensus_branch(consensus_branch_id);
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
    let mut client = crate::wallet::sync_engine::open_isolated_lwd_channel(lightwalletd_url)
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
        // Once SendTransaction has started, a gRPC status is not proof that
        // the server rejected the transaction. The server may have accepted
        // and relayed it before the response or connection was lost. Treat
        // every transport status conservatively; explicit SendResponse
        // rejection below remains the only definite rejection path.
        Err(status) => {
            return Ok(handle_pczt_transport_failure(
                &txid.to_string(),
                &status,
                store_locally,
            ));
        }
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

fn handle_pczt_transport_failure<F>(
    txid: &str,
    status: &tonic::Status,
    store_locally: F,
) -> ExtractAndBroadcastPcztResult
where
    F: FnOnce() -> Result<(), String>,
{
    let mut message = format!(
        "Broadcast response was unavailable for txid={txid} ({status}). The transaction may \
         already be on the network. Do not send again until sync or an explorer confirms \
         whether this transaction was accepted."
    );
    match store_locally() {
        Ok(()) => {
            message.push_str(
                " It was stored locally and will retry automatically during sync until it is \
                 confirmed or expires.",
            );
        }
        Err(storage_err) => {
            log::error!(
                "keystone: failed to store tx after ambiguous broadcast transport failure \
                 (txid={txid}): {storage_err}"
            );
            message.push_str(&format!(
                " Local tracking also failed: {storage_err}. Check an explorer before retrying \
                 this send."
            ));
        }
    }
    ExtractAndBroadcastPcztResult::broadcast_unknown(txid.to_string(), message)
}

#[cfg(test)]
mod tests {
    use std::cell::Cell;

    use super::*;
    use zcash_client_backend::data_api::{WalletRead, WalletWrite};
    use zcash_client_backend::proto::service::SendResponse;
    use zcash_protocol::consensus::BlockHeight;

    fn send_response(error_code: i32, error_message: &str) -> SendResponse {
        SendResponse {
            error_code,
            error_message: error_message.to_string(),
        }
    }

    #[test]
    fn tex_ephemeral_output_selection_uses_wallet_scope_not_value_alone() {
        let expected_value = zcash_protocol::value::Zatoshis::const_from_u64(50_000);
        let ordinary_address = TransparentAddress::PublicKeyHash([1; 20]);
        let ephemeral_address = TransparentAddress::PublicKeyHash([2; 20]);
        let outputs = vec![
            TxOut::new(expected_value, ordinary_address.script().into()),
            TxOut::new(expected_value, ephemeral_address.script().into()),
        ];

        let selected = tex_ephemeral_output_index(&outputs, expected_value, |address| {
            Ok(if address == &ephemeral_address {
                Some(TransparentKeyScope::EPHEMERAL)
            } else {
                Some(TransparentKeyScope::EXTERNAL)
            })
        })
        .unwrap();

        assert_eq!(selected, 1);
    }

    #[test]
    fn tex_keystone_signer_view_normalizes_transparent_output_metadata() {
        use ::transparent::keys::{AccountPrivKey, IncomingViewingKey, NonHardenedChildIndex};
        use pczt::roles::{creator::Creator, io_finalizer::IoFinalizer, updater::Updater};
        use zcash_primitives::transaction::{
            builder::{BuildConfig, Builder},
            fees::zip317,
        };

        let network = WalletNetwork::Main;
        let seed = [7u8; 32];
        let account = AccountPrivKey::from_seed(&network, &seed, zip32::AccountId::ZERO).unwrap();
        let account_pubkey = account.to_account_pubkey();
        let (source_address, source_index) = account_pubkey
            .derive_external_ivk()
            .unwrap()
            .default_address();
        let source_pubkey = account_pubkey
            .derive_address_pubkey(TransparentKeyScope::EXTERNAL, source_index)
            .unwrap();
        let ephemeral_index = NonHardenedChildIndex::ZERO;
        let ephemeral_address = account_pubkey
            .derive_ephemeral_ivk()
            .unwrap()
            .derive_ephemeral_address(ephemeral_index)
            .unwrap();
        let ephemeral_pubkey = account_pubkey
            .derive_address_pubkey(TransparentKeyScope::EPHEMERAL, ephemeral_index)
            .unwrap()
            .serialize();

        let coin = TxOut::new(
            zcash_protocol::value::Zatoshis::const_from_u64(1_000_000),
            source_address.script().into(),
        );
        let mut builder = Builder::new(
            network,
            10_000_000.into(),
            BuildConfig::Standard {
                sapling_anchor: None,
                orchard_anchor: None,
                ironwood_anchor: None,
                orchard_padding: BundlePadding::DEFAULT,
                ironwood_padding: BundlePadding::DEFAULT,
            },
        );
        builder
            .add_transparent_p2pkh_input(source_pubkey, OutPoint::new([1; 32], 0), coin)
            .unwrap();
        builder
            .add_transparent_output(
                &ephemeral_address,
                zcash_protocol::value::Zatoshis::const_from_u64(990_000),
            )
            .unwrap();
        let zcash_primitives::transaction::builder::PcztResult { pczt_parts, .. } = builder
            .build_for_pczt(
                voting_crypto_deps::rand::rngs::OsRng,
                &zip317::FeeRule::standard(),
            )
            .unwrap();
        let base = IoFinalizer::new(Creator::build_from_parts(pczt_parts).unwrap())
            .finalize_io()
            .unwrap();
        let base_bytes = base.clone().serialize().unwrap();

        let seed_fingerprint = [8u8; 32];
        let hardened = 1 << 31;
        let path = vec![
            44 | hardened,
            133 | hardened,
            hardened,
            2,
            ephemeral_index.index(),
        ];
        let derivation =
            transparent::pczt::Bip32Derivation::parse(seed_fingerprint, path.clone()).unwrap();
        let first_signer = prepare_tex_pczt_for_keystone(
            &base_bytes,
            network,
            Some((0, ephemeral_pubkey, derivation)),
        )
        .unwrap();
        let expected_t_address = match ephemeral_address {
            TransparentAddress::PublicKeyHash(hash) => {
                ZcashAddress::from_transparent_p2pkh(network.network_type(), hash).encode()
            }
            TransparentAddress::ScriptHash(_) => unreachable!(),
        };
        pczt::roles::verifier::Verifier::new(pczt::Pczt::parse(&first_signer).unwrap())
            .with_transparent::<Infallible, _>(|bundle| {
                let output = &bundle.outputs()[0];
                assert_eq!(
                    output.user_address().as_deref(),
                    Some(expected_t_address.as_str())
                );
                let stored = output.bip32_derivation().get(&ephemeral_pubkey).unwrap();
                assert_eq!(stored.seed_fingerprint(), &seed_fingerprint);
                assert_eq!(
                    stored
                        .derivation_path()
                        .iter()
                        .map(|child| child.index() | u32::from(child.is_hardened()) * hardened)
                        .collect::<Vec<_>>(),
                    path
                );
                Ok(())
            })
            .unwrap();

        let tex_address = match ephemeral_address {
            TransparentAddress::PublicKeyHash(hash) => {
                ZcashAddress::from_tex(network.network_type(), hash).encode()
            }
            TransparentAddress::ScriptHash(_) => unreachable!(),
        };
        let tex_base = Updater::new(base)
            .update_transparent_with(|mut updater| {
                updater.update_output_with(0, |mut output| {
                    output.set_user_address(tex_address.clone());
                    Ok(())
                })
            })
            .unwrap()
            .finish()
            .serialize()
            .unwrap();
        let second_signer = prepare_tex_pczt_for_keystone(&tex_base, network, None).unwrap();
        pczt::roles::verifier::Verifier::new(pczt::Pczt::parse(&second_signer).unwrap())
            .with_transparent::<Infallible, _>(|bundle| {
                assert_eq!(
                    bundle.outputs()[0].user_address().as_deref(),
                    Some(expected_t_address.as_str())
                );
                Ok(())
            })
            .unwrap();

        let combined = combine_pczts(&tex_base, &second_signer).unwrap();
        assert_eq!(
            combined.transparent().outputs()[0]
                .user_address()
                .as_deref(),
            Some(tex_address.as_str())
        );
    }

    #[test]
    fn pczt_set_first_rejection_never_persists() {
        let step = pczt_broadcast_step(
            0,
            2,
            PcztBroadcastAttempt::DefiniteRejection("rejected".to_string()),
        );

        assert_eq!(step, PcztBroadcastStep::Fail("rejected".to_string()));
    }

    #[test]
    fn pczt_set_child_rejection_persists_only_accepted_parent() {
        let step = pczt_broadcast_step(
            1,
            2,
            PcztBroadcastAttempt::DefiniteRejection("rejected".to_string()),
        );

        let PcztBroadcastStep::Stop(plan) = step else {
            panic!("child rejection must stop with a partial-broadcast plan");
        };
        assert_eq!(plan.persisted_prefix_len, 1);
        assert_eq!(plan.broadcasted_count, 1);
        assert_eq!(plan.status, StoreAndBroadcastPcztsResult::PARTIAL_BROADCAST);
    }

    #[test]
    fn pczt_set_transport_unknown_persists_the_attempted_pczt() {
        let step = pczt_broadcast_step(
            0,
            2,
            PcztBroadcastAttempt::TransportUnknown("deadline".to_string()),
        );

        let PcztBroadcastStep::Stop(plan) = step else {
            panic!("ambiguous broadcast must stop with a recovery plan");
        };
        assert_eq!(plan.persisted_prefix_len, 1);
        assert_eq!(plan.broadcasted_count, 0);
        assert_eq!(plan.status, StoreAndBroadcastPcztsResult::BROADCAST_UNKNOWN);
    }

    #[test]
    fn outer_wallet_transaction_rolls_back_prior_write_on_later_error() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let phrase = crate::wallet::keys::generate_mnemonic();
        let seed = crate::wallet::keys::mnemonic_to_seed(&phrase).unwrap();
        crate::wallet::keys::init_db_and_create_account(
            db_path,
            WalletNetwork::Regtest,
            &seed,
            Some(100),
            "test",
        )
        .unwrap();

        let mut db = open_wallet_db(db_path, WalletNetwork::Regtest).unwrap();
        db.update_chain_tip(BlockHeight::from_u32(110)).unwrap();
        let result = db.transactionally(|transactional_db| {
            // Exercise a prior wallet write inside the same outer WalletDb
            // transaction primitive used by the production PCZT store loop.
            transactional_db
                .update_chain_tip(BlockHeight::from_u32(120))
                .map_err(|error| AtomicPcztStoreError::Store(error.to_string()))?;
            // A later store error must roll back the earlier wallet write.
            Err::<(), AtomicPcztStoreError>(AtomicPcztStoreError::Store(
                "forced second-round store failure".to_string(),
            ))
        });
        assert!(result.is_err());
        assert_eq!(db.chain_height().unwrap(), Some(BlockHeight::from_u32(110)));
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
    fn pczt_non_deadline_transport_failure_remains_ambiguous() {
        let store_calls = Cell::new(0);
        let result = handle_pczt_transport_failure(
            "txid",
            &tonic::Status::unavailable("connection reset after request"),
            || {
                store_calls.set(store_calls.get() + 1);
                Ok(())
            },
        );

        assert_eq!(
            result.status,
            ExtractAndBroadcastPcztResult::BROADCAST_UNKNOWN
        );
        assert!(result
            .message
            .as_deref()
            .unwrap_or_default()
            .contains("stored locally"));
        assert_eq!(store_calls.get(), 1);
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
    fn orchard_circuit_version_follows_consensus_branch() {
        use zcash_protocol::consensus::BranchId;

        // Branches at or before NU6.2 prove/verify the Orchard pool under the
        // fixed post-NU6.2 circuit. NU6.2 matches the crate's own bundle-format
        // mapping; earlier branches deliberately do NOT (the crate maps them to
        // the insecure pre-NU6.2 format, which the wallet never proves with).
        assert_eq!(
            orchard_circuit_version_for_consensus_branch(u32::from(BranchId::Nu6_2)),
            orchard::bundle::BundleVersion::orchard_v2().circuit_version(),
        );
        assert_eq!(
            orchard_circuit_version_for_consensus_branch(u32::from(BranchId::Nu6_1)),
            orchard::circuit::OrchardCircuitVersion::FixedPostNu6_2,
        );
        assert_eq!(
            orchard_circuit_version_for_consensus_branch(u32::from(BranchId::Nu5)),
            orchard::circuit::OrchardCircuitVersion::FixedPostNu6_2,
        );

        // NU6.3 selects the post-NU6.3 circuit from the branch alone — the tx
        // version is not consulted, so a post-activation legacy-V5 PCZT gets
        // the same keys as a V6 one (both carry `orchard_v3`-format bundles).
        assert_eq!(
            orchard_circuit_version_for_consensus_branch(u32::from(BranchId::Nu6_3)),
            orchard::bundle::BundleVersion::orchard_v3().circuit_version(),
        );
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

    // The headline correctness gate for the "signatures-only" round-trip: for a
    // real migration-shaped PCZT (Orchard spend -> Ironwood output), producing
    // the extracted transaction via the compact `apply_sigs_and_extract` path
    // must yield the same txid as the legacy "full redacted signed PCZT +
    // combine + extract" path. Same txid => the compact path is equivalent.
    //
    // Note on raw bytes: the extracted transactions are the same length and
    // agree everywhere except the Orchard/Ironwood binding signatures, which
    // `TransactionExtractor` regenerates with a fresh `OsRng` on every call.
    // Those bytes are NOT covered by the ZIP-244 txid (which commits to effects,
    // not authorizing data), so the txid match is the meaningful equivalence and
    // full raw-byte identity across two independent extractions is not
    // achievable for either path.
    mod sigs_only_byte_identity {
        // The functions under test live at the module file scope, which is two
        // levels up from this nested test module.
        use super::super::{
            apply_sigs_and_extract, ensure_signed_pczt_matches_base, ensure_tex_pczt_dependency,
            extract_compact_sigs_from_signed_pczt, extract_transaction_from_pczt,
            ironwood_orchard_proving_key, preflight_orchard_spend_auth_signatures,
            redact_pczt_for_signer, set_orchard_anchor_and_witnesses, txid_from_io_finalized_pczt,
            validate_signed_pczts,
        };
        use orchard::tree::MerkleHashOrchard;
        use pczt::roles::signer::SpendAuthSignature;
        use pczt::roles::{
            creator::Creator, io_finalizer::IoFinalizer, prover::Prover, signer::Signer,
            updater::Updater,
        };
        use shardtree::{store::memory::MemoryShardStore, ShardTree};
        use voting_crypto_deps::rand::rngs::OsRng;
        use zcash_note_encryption::try_note_decryption;
        use zcash_primitives::transaction::{builder::PcztResult, fees::zip317};
        use zcash_protocol::{
            consensus::{BlockHeight, NetworkType, NetworkUpgrade, Parameters},
            memo::{Memo, MemoBytes},
            value::Zatoshis,
        };

        // A consensus-parameter set that activates NU6.3 (Ironwood) at a low
        // height, matching the pinned pczt crate's own end-to-end test harness.
        #[derive(Clone, Copy, Debug)]
        struct Nu6_3Network;

        impl Parameters for Nu6_3Network {
            fn network_type(&self) -> NetworkType {
                NetworkType::Test
            }

            fn activation_height(&self, nu: NetworkUpgrade) -> Option<BlockHeight> {
                match nu {
                    NetworkUpgrade::Nu6_3 => Some(BlockHeight::from_u32(10)),
                    _ => zcash_protocol::consensus::MAIN_NETWORK.activation_height(nu),
                }
            }
        }

        /// Builds a real, IO-finalized v6 migration PCZT (single Orchard spend ->
        /// Ironwood output), returning the base PCZT bytes, the Orchard spend
        /// authorizing key, and the spend action index. This is the same shape
        /// the wallet's migration pipeline produces, minus the wallet DB.
        fn build_migration_base_pczt() -> (
            Vec<u8>,
            orchard::keys::SpendAuthorizingKey,
            usize,
            [u8; 32],
            Vec<u32>,
            [u8; 96],
        ) {
            let mut rng = OsRng;

            let seed = [7u8; 32];
            let seed_fingerprint = [8u8; 32];
            let account_index = zip32::AccountId::ZERO;
            let orchard_sk = orchard::keys::SpendingKey::from_zip32_seed(&seed, 133, account_index)
                .expect("valid Orchard ZIP 32 spending key");
            let orchard_ask = orchard::keys::SpendAuthorizingKey::from(&orchard_sk);
            let orchard_fvk = orchard::keys::FullViewingKey::from(&orchard_sk);
            let orchard_ivk = orchard_fvk.to_ivk(orchard::keys::Scope::Internal);
            let orchard_ovk = orchard_fvk.to_ovk(orchard::keys::Scope::Internal);
            let recipient = orchard_fvk.address_at(0u32, orchard::keys::Scope::Internal);

            // Pretend we already received an Orchard (V2) note.
            let value = orchard::value::NoteValue::from_raw(1_000_000);
            let note = {
                let orchard_bundle_version = orchard::bundle::BundleVersion::orchard_v2();
                let mut orchard_builder = orchard::builder::Builder::new(
                    orchard::builder::BundleType::DEFAULT,
                    orchard_bundle_version,
                    orchard_bundle_version.default_flags(),
                    orchard::Anchor::empty_tree(),
                )
                .unwrap();
                orchard_builder
                    .add_output(None, recipient, value, Memo::Empty.encode().into_bytes())
                    .unwrap();
                let (bundle, meta) = orchard_builder.build::<i64>(&mut rng).unwrap().unwrap();
                let action = bundle
                    .actions()
                    .get(meta.output_action_index(0).unwrap())
                    .unwrap();
                let domain = orchard::note_encryption::OrchardDomain::for_action(action);
                let (note, _, _) =
                    try_note_decryption(&domain, &orchard_ivk.prepare(), action).unwrap();
                note
            };

            // Single-leaf Orchard tree for the spend witness/anchor.
            let (anchor, merkle_path) = {
                let cmx: orchard::note::ExtractedNoteCommitment = note.commitment().into();
                let leaf = MerkleHashOrchard::from_cmx(&cmx);
                let mut tree = ShardTree::<_, 32, 16>::new(
                    MemoryShardStore::<MerkleHashOrchard, u32>::empty(),
                    100,
                );
                tree.append(leaf, incrementalmerkletree::Retention::Marked)
                    .unwrap();
                tree.checkpoint(9_999_999).unwrap();
                let position = 0.into();
                let merkle_path = tree
                    .witness_at_checkpoint_depth(position, 0)
                    .unwrap()
                    .unwrap();
                let anchor = merkle_path.root(leaf);
                (anchor.into(), merkle_path.into())
            };

            // Build a v6 transaction that spends Orchard and outputs to Ironwood
            // (the migration shape).
            let mut builder = crate::wallet::sync::send::migration_child_builder(
                Nu6_3Network,
                10_000_000.into(),
                10_000_000.into(),
                anchor,
            )
            .unwrap();
            builder
                .add_orchard_spend::<zip317::FeeRule>(orchard_fvk.clone(), note, merkle_path)
                .unwrap();
            builder
                .add_ironwood_output::<zip317::FeeRule>(
                    Some(orchard_ovk),
                    recipient,
                    // 1_000_000 input - the 15_000 ZIP-317 fee (3 logical
                    // actions: 2 padded Orchard + 1 unpadded Ironwood).
                    Zatoshis::const_from_u64(985_000),
                    MemoBytes::empty(),
                )
                .unwrap();
            let PcztResult {
                pczt_parts,
                orchard_meta,
                ..
            } = builder
                .build_for_pczt(OsRng, &zip317::FeeRule::standard())
                .unwrap();
            assert_eq!(
                u32::from(pczt_parts.expiry_height),
                crate::wallet::sync::migration::zip318_canonical_migration_expiry_height(
                    10_000_000
                )
                .unwrap()
            );

            let base = Creator::build_from_parts(pczt_parts).unwrap();
            let base = IoFinalizer::new(base).finalize_io().unwrap();
            let spend_index = orchard_meta.spend_action_index(0).unwrap();
            let account_child: zip32::ChildIndex = account_index.into();
            let derivation_path = vec![
                zip32::ChildIndex::hardened(32).index(),
                zip32::ChildIndex::hardened(133).index(),
                account_child.index(),
            ];
            let zip32_derivation =
                orchard::pczt::Zip32Derivation::parse(seed_fingerprint, derivation_path.clone())
                    .expect("valid ZIP 32 derivation");
            let base = Updater::new(base)
                .update_orchard_with(|mut updater| {
                    updater.update_action_with(spend_index, |mut action_updater| {
                        action_updater.set_spend_zip32_derivation(zip32_derivation);
                        Ok(())
                    })
                })
                .unwrap()
                .finish();

            (
                base.serialize().unwrap(),
                orchard_ask,
                spend_index,
                seed_fingerprint,
                derivation_path,
                orchard_fvk.to_bytes(),
            )
        }

        /// Reads the Orchard spend-authorization signature back out of a signed
        /// PCZT's action as raw `[u8; 64]` bytes — the wire form the device sends
        /// in a `zcash-batch-sig-result`. The pczt wire `Spend` already stores the
        /// signature as `[u8; 64]`, so this is exactly the bytes the compact
        /// path receives.
        fn orchard_spend_auth_sig_bytes(signed: &pczt::Pczt, spend_index: usize) -> [u8; 64] {
            (*signed
                .orchard()
                .actions()
                .get(spend_index)
                .expect("spend action present")
                .spend()
                .spend_auth_sig())
            .expect("Orchard spend should be signed")
        }

        /// Produces the deferred form used by staged transactions: the PCZT is
        /// IO-finalized but unproved, and both v6 anchors and all spend
        /// witnesses are absent. Its true dummy spends retain their locally
        /// created signatures, while the real Orchard spend remains unsigned.
        fn build_deferred_base_and_valid_sig() -> (Vec<u8>, SpendAuthSignature, usize) {
            use pczt::roles::redactor::Redactor;

            let (base_bytes, orchard_ask, spend_index, _, _, _) = build_migration_base_pczt();
            let deferred = Redactor::new(pczt::Pczt::parse(&base_bytes).unwrap())
                .redact_orchard_with(|mut r| {
                    r.redact_actions(|mut ar| ar.clear_spend_witness());
                    r.clear_anchor();
                })
                .redact_ironwood_with(|mut r| {
                    r.redact_actions(|mut ar| ar.clear_spend_witness());
                    r.clear_anchor();
                })
                .finish();

            // Signing this unproved, anchorless PCZT demonstrates that the v6
            // pre-authorization sighash is sufficient. Preflight independently
            // applies and verifies the resulting signature below.
            let mut signer = Signer::new(deferred.clone()).unwrap();
            signer.sign_orchard(spend_index, &orchard_ask).unwrap();
            let signature = SpendAuthSignature::from_parts(
                orchard::ValuePool::Orchard,
                spend_index,
                orchard_spend_auth_sig_bytes(&signer.finish(), spend_index),
            );

            (deferred.serialize().unwrap(), signature, spend_index)
        }

        #[test]
        fn orchard_witnesses_are_matched_by_nullifier_not_request_order() {
            use pczt::roles::redactor::Redactor;

            let (base_bytes, _, _, _, _, _) = build_migration_base_pczt();
            let base = pczt::Pczt::parse(&base_bytes).unwrap();
            assert_eq!(base.orchard().actions().len(), 2);

            let nullifiers = base
                .orchard()
                .actions()
                .iter()
                .map(|action| hex::encode(action.spend().nullifier()))
                .collect::<Vec<_>>();
            let zero =
                Option::<MerkleHashOrchard>::from(MerkleHashOrchard::from_bytes(&[0; 32])).unwrap();
            let witnesses = [
                orchard::tree::MerklePath::from_parts(3, [zero; 32]),
                orchard::tree::MerklePath::from_parts(7, [zero; 32]),
            ];
            let replacement_anchor = orchard::Anchor::empty_tree();

            // Supply the nullifiers in the opposite order from the randomized
            // action list. The nullifier helper must still place each witness on
            // the same action as the explicit-index Updater reference below.
            let actual = set_orchard_anchor_and_witnesses(
                &base_bytes,
                replacement_anchor,
                [
                    (nullifiers[1].as_str(), &witnesses[1]),
                    (nullifiers[0].as_str(), &witnesses[0]),
                ],
            )
            .unwrap();

            let anchor_cleared = Redactor::new(base)
                .redact_orchard_with(|mut redactor| redactor.clear_anchor())
                .finish();
            let expected = Updater::new(anchor_cleared)
                .set_orchard_anchor(replacement_anchor)
                .unwrap()
                .set_orchard_spend_witnesses([(0, witnesses[0].clone()), (1, witnesses[1].clone())])
                .unwrap()
                .finish();
            let actual = pczt::Pczt::parse(&actual).unwrap();
            assert_eq!(actual.orchard(), expected.orchard());

            let duplicate_err = set_orchard_anchor_and_witnesses(
                &base_bytes,
                replacement_anchor,
                [
                    (nullifiers[0].as_str(), &witnesses[0]),
                    (nullifiers[0].as_str(), &witnesses[1]),
                ],
            )
            .unwrap_err();
            assert!(duplicate_err.contains("Duplicate Orchard spend nullifier"));
        }

        #[test]
        fn io_finalized_pczt_txid_matches_extracted_transaction() {
            let (base_bytes, orchard_ask, spend_index, _, _, _) = build_migration_base_pczt();
            let pre_signature_txid = txid_from_io_finalized_pczt(&base_bytes)
                .expect("IO-finalized PCZT effects should have a stable txid");

            let pk = ironwood_orchard_proving_key();
            let proofs = Prover::new(pczt::Pczt::parse(&base_bytes).unwrap())
                .create_orchard_proof(pk)
                .unwrap()
                .create_ironwood_proof(pk)
                .unwrap()
                .finish()
                .serialize()
                .unwrap();
            let mut signer = Signer::new(pczt::Pczt::parse(&base_bytes).unwrap()).unwrap();
            signer.sign_orchard(spend_index, &orchard_ask).unwrap();
            let signed = redact_pczt_for_signer(&signer.finish().serialize().unwrap()).unwrap();
            let extracted = extract_transaction_from_pczt(&proofs, &signed, None, None).unwrap();

            assert_eq!(pre_signature_txid, extracted.txid);
        }

        #[test]
        fn signed_pczt_correlation_rejects_a_swapped_transaction() {
            let (first, ..) = build_migration_base_pczt();
            let (second, ..) = build_migration_base_pczt();
            assert_ne!(
                txid_from_io_finalized_pczt(&first).unwrap(),
                txid_from_io_finalized_pczt(&second).unwrap()
            );

            let error = ensure_signed_pczt_matches_base(&first, &second).unwrap_err();
            assert!(error.contains("transaction effects do not match"));
        }

        #[test]
        fn extraction_rejects_a_missing_transparent_signature() {
            use ::transparent::{
                bundle::{OutPoint, TxOut},
                keys::{AccountPrivKey, IncomingViewingKey, TransparentKeyScope},
            };
            use zcash_primitives::transaction::builder::{BuildConfig, Builder, BundlePadding};

            let (first, ..) = build_migration_base_pczt();
            let first_txid = txid_from_io_finalized_pczt(&first).unwrap();
            let account =
                AccountPrivKey::from_seed(&Nu6_3Network, &[1; 32], zip32::AccountId::ZERO).unwrap();
            let (address, index) = account
                .to_account_pubkey()
                .derive_external_ivk()
                .unwrap()
                .default_address();
            let pubkey = account
                .to_account_pubkey()
                .derive_address_pubkey(TransparentKeyScope::EXTERNAL, index)
                .unwrap();
            let coin = TxOut::new(Zatoshis::const_from_u64(1_000_000), address.script().into());
            let mut builder = Builder::new(
                Nu6_3Network,
                10_000_000.into(),
                BuildConfig::Standard {
                    sapling_anchor: None,
                    orchard_anchor: None,
                    ironwood_anchor: None,
                    orchard_padding: BundlePadding::DEFAULT,
                    ironwood_padding: BundlePadding::DEFAULT,
                },
            );
            builder
                .add_transparent_p2pkh_input(pubkey, OutPoint::new(*first_txid.as_ref(), 1), coin)
                .unwrap();
            builder
                .add_transparent_output(&address, Zatoshis::const_from_u64(990_000))
                .unwrap();
            let PcztResult { pczt_parts, .. } = builder
                .build_for_pczt(OsRng, &zip317::FeeRule::standard())
                .unwrap();
            let unsigned = IoFinalizer::new(Creator::build_from_parts(pczt_parts).unwrap())
                .finalize_io()
                .unwrap()
                .serialize()
                .unwrap();

            ensure_tex_pczt_dependency(&[first.clone(), unsigned.clone()]).unwrap();
            let reversed =
                ensure_tex_pczt_dependency(&[unsigned.clone(), first.clone()]).unwrap_err();
            assert!(reversed.contains("does not spend the exact round 1 transaction"));

            let validation_error = validate_signed_pczts(
                &[unsigned.clone(), first.clone()],
                &[unsigned.clone(), first],
                None,
                None,
            )
            .unwrap_err();
            assert!(validation_error.contains("does not spend the exact round 1 transaction"));

            let error = match extract_transaction_from_pczt(&unsigned, &unsigned, None, None) {
                Ok(_) => panic!("transparent input must be signed"),
                Err(error) => error,
            };
            assert!(error.contains("Finalize transparent spends"));
        }

        #[test]
        fn compact_signature_preflight_accepts_unproved_anchorless_v6_pczt() {
            let (deferred_bytes, signature, spend_index) = build_deferred_base_and_valid_sig();
            let deferred = pczt::Pczt::parse(&deferred_bytes).unwrap();

            assert!(deferred.orchard().anchor().is_none());
            assert!(deferred.ironwood().anchor().is_none());
            assert!(deferred.orchard().actions()[spend_index]
                .spend()
                .spend_auth_sig()
                .is_none());
            assert!(deferred.ironwood().actions()[0]
                .spend()
                .spend_auth_sig()
                .is_some());

            preflight_orchard_spend_auth_signatures(&deferred_bytes, &[signature])
                .expect("valid v6 signature should preflight without proofs or anchors");
        }

        #[test]
        fn compact_signature_preflight_enforces_exact_required_set_and_validity() {
            let (deferred_bytes, valid, spend_index) = build_deferred_base_and_valid_sig();

            let missing = preflight_orchard_spend_auth_signatures(&deferred_bytes, &[])
                .expect_err("the real Orchard spend requires one device signature");
            assert!(missing.contains("Missing 1 required compact spend-authorization signature"));

            let duplicate = preflight_orchard_spend_auth_signatures(
                &deferred_bytes,
                &[valid.clone(), valid.clone()],
            )
            .expect_err("duplicate locations must be rejected");
            assert!(duplicate.contains("Duplicate compact signature"));

            // The Ironwood action is a true dummy spend whose signature was
            // already created locally by IO finalization. It is deliberately
            // outside the device-required set.
            let dummy =
                SpendAuthSignature::from_parts(orchard::ValuePool::Ironwood, 0, *valid.signature());
            let unexpected = preflight_orchard_spend_auth_signatures(&deferred_bytes, &[dummy])
                .expect_err("a signature for an already-authorized dummy is unexpected");
            assert!(unexpected.contains("action is absent or already authorized"));

            let mut invalid_bytes = *valid.signature();
            invalid_bytes[0] ^= 1;
            let invalid = SpendAuthSignature::from_parts(
                orchard::ValuePool::Orchard,
                spend_index,
                invalid_bytes,
            );
            let invalid = preflight_orchard_spend_auth_signatures(&deferred_bytes, &[invalid])
                .expect_err("an invalid signature must fail cryptographic verification");
            assert!(invalid.contains("Apply Orchard signature"));
        }

        #[test]
        fn compact_sigs_path_matches_full_signed_pczt_path() {
            let (base_bytes, orchard_ask, spend_index, _, _, _) = build_migration_base_pczt();

            // The wallet's own proofs-PCZT clone: Orchard + Ironwood proofs over
            // the same base. This is what both extraction paths consume. Both
            // bundles of a v6 transaction use the post-NU6.3 circuit.
            let pk = ironwood_orchard_proving_key();
            let proofs_pczt = Prover::new(pczt::Pczt::parse(&base_bytes).unwrap())
                .create_orchard_proof(pk)
                .unwrap()
                .create_ironwood_proof(pk)
                .unwrap()
                .finish();
            let proofs_bytes = proofs_pczt.serialize().unwrap();

            // OLD path: sign the base PCZT to get a full signed PCZT, redact it
            // for transport the way the wallet does before combining, then
            // combine with the proofs clone and extract.
            let mut signer = Signer::new(pczt::Pczt::parse(&base_bytes).unwrap()).unwrap();
            signer.sign_orchard(spend_index, &orchard_ask).unwrap();
            let signed_pczt = signer.finish();
            let sig_bytes = orchard_spend_auth_sig_bytes(&signed_pczt, spend_index);
            let redacted_signed_bytes =
                redact_pczt_for_signer(&signed_pczt.clone().serialize().unwrap())
                    .expect("redact signed PCZT for transport");

            let old =
                extract_transaction_from_pczt(&proofs_bytes, &redacted_signed_bytes, None, None)
                    .expect("old combine+extract path should succeed");

            // A SECOND full-path extraction of the very same inputs. The
            // `TransactionExtractor` creates the Orchard/Ironwood binding
            // signatures with a fresh `OsRng` each call (no caller-controllable
            // RNG seam), and RedDSA binding signatures are randomized, so even
            // two identical full-path extractions are NOT byte-identical: they
            // differ only in those binding-signature bytes. We use this as the
            // baseline for "divergence inherent to extraction".
            let old_again =
                extract_transaction_from_pczt(&proofs_bytes, &redacted_signed_bytes, None, None)
                    .expect("second old combine+extract path should succeed");

            // The software path's compact extraction reads back every
            // spend-authorization signature in the signed PCZT — the real
            // spend's signature plus the dummy-spend signatures the IO
            // Finalizer produced for padding actions. The real signature must
            // be among them at the spend's (pool, action index).
            let extracted_sigs =
                extract_compact_sigs_from_signed_pczt(&signed_pczt.serialize().unwrap())
                    .expect("extract compact sigs from signed PCZT");
            assert!(
                extracted_sigs.contains(&SpendAuthSignature::from_parts(
                    orchard::ValuePool::Orchard,
                    spend_index,
                    sig_bytes,
                )),
                "compact sig extraction must include the signer's signature at the spend index"
            );

            // NEW path: hand the SAME signature to the compact path as a
            // (pool, action_index, sig) list and apply it onto the proofs clone.
            let sigs = vec![SpendAuthSignature::from_parts(
                orchard::ValuePool::Orchard,
                spend_index,
                sig_bytes,
            )];
            let new = apply_sigs_and_extract(&proofs_bytes, &sigs, None, None)
                .expect("compact apply_sigs_and_extract path should succeed");

            // The software migration path applies the FULL extracted set
            // (dummy-spend signatures included) onto a proofs base that already
            // carries the dummy signatures; re-applying an rk-valid signature
            // is an overwrite, not an error, and yields the same transaction.
            let software = apply_sigs_and_extract(&proofs_bytes, &extracted_sigs, None, None)
                .expect("software-path apply of all extracted sigs should succeed");
            assert_eq!(
                software.txid, new.txid,
                "applying the full extracted signature set must produce the same txid"
            );

            // Headline correctness gate: the compact sigs-only path produces the
            // SAME txid as the full signed-PCZT path. Under ZIP-244 the txid
            // commits to the transaction effects and *excludes* the authorizing
            // data (the randomized binding signatures), so an identical txid means
            // the two paths built the identical transaction.
            assert_eq!(
                old.txid, new.txid,
                "compact sigs-only path must produce the same txid as the full signed-PCZT path"
            );

            // The transactions are the same size down to the byte.
            assert_eq!(
                old.raw_tx.len(),
                new.raw_tx.len(),
                "compact and full paths must produce the same-length transaction"
            );

            // The only raw-byte differences between the compact path and the full
            // path are the freshly-randomized binding signatures. We measure this
            // two ways and require the compact path to be no noisier than the
            // full path's own non-determinism, both bounded by the two 64-byte
            // binding signatures (Orchard + Ironwood = 128 bytes). We bound rather
            // than require exact equality of the diff counts because RedDSA
            // signature bytes are uniformly random, so two random 64-byte
            // signatures coincide in a few byte positions by chance, making the
            // raw differing-byte count jitter slightly below 128.
            let count_diffs = |a: &[u8], b: &[u8]| a.iter().zip(b).filter(|(x, y)| x != y).count();
            let inherent_diff = count_diffs(&old.raw_tx, &old_again.raw_tx);
            let compact_vs_full_diff = count_diffs(&old.raw_tx, &new.raw_tx);

            // Two independent full-path extractions are already non-identical:
            // this proves the divergence is inherent to `TransactionExtractor`'s
            // randomized binding signatures, not something the compact path
            // introduced.
            assert!(
                inherent_diff > 0,
                "two full-path extractions are expected to differ in their randomized binding \
                 signatures"
            );
            assert!(
                inherent_diff <= 128,
                "inherent binding-signature divergence ({inherent_diff} bytes) must be within the \
                 two 64-byte binding signatures"
            );
            assert!(
                compact_vs_full_diff <= 128,
                "the compact path must not diverge from the full path beyond the two 64-byte \
                 binding signatures ({compact_vs_full_diff} bytes differ)"
            );

            // The extracted transaction re-derives the same txid through the real
            // `Transaction` type, confirming the compact path emits a
            // structurally valid, consensus-identical transaction.
            assert_eq!(new.tx.txid(), old.tx.txid());
        }

        // The batch redaction of a migration-shaped PCZT: the upstream
        // compact-PCZT format. Every action sheds `cv_net` and `cmx`, both
        // wallet-decryptable output ciphertexts (the Ironwood migration output
        // AND the deterministic zero-value Orchard output) travel as stripped
        // memo plaintext, preauthorized dummy spends shed their signatures and
        // `alpha`, and the v6 bundle anchors and `bsk`s are cleared. The wallet
        // retains the unredacted PCZT for proof/extraction.
        #[test]
        fn batch_redaction_elides_verified_fields_and_signs_identically() {
            use crate::wallet::sync::pczt::redact_pczt_for_batch_signer;
            use orchard::primitives::redpallas::{Signature, SpendAuth, VerificationKey};
            use pczt::roles::redactor::Redactor;

            fn preauthorized_spend_action_indices(bundle: &pczt::orchard::Bundle) -> Vec<usize> {
                bundle
                    .actions()
                    .iter()
                    .enumerate()
                    .filter_map(|(index, action)| {
                        action.spend().spend_auth_sig().is_some().then_some(index)
                    })
                    .collect()
            }

            let (base_bytes, orchard_ask, spend_index, _, _, _) = build_migration_base_pczt();
            let base = pczt::Pczt::parse(&base_bytes).unwrap();
            let orchard_preauthorized = preauthorized_spend_action_indices(base.orchard());
            let ironwood_preauthorized = preauthorized_spend_action_indices(base.ironwood());
            assert_eq!(orchard_preauthorized.len(), 1);
            assert_eq!(ironwood_preauthorized.len(), 1);

            let batch = redact_pczt_for_batch_signer(&base_bytes).unwrap();
            // The point of the compact format: a migration child small enough
            // for a short device QR carousel. The retained bytes are dominated
            // by the still-required `out_ciphertext`s and the
            // sighash-committed action fields.
            assert!(
                batch.len() < 1_900,
                "batch-redacted migration child should stay under ~1.9 kB, got {} bytes",
                batch.len(),
            );

            let parsed = pczt::Pczt::parse(&batch).unwrap();
            // V6 signatures do not commit to anchors, so both bundle anchors
            // are elided; the wallet's retained PCZT owns the real anchors.
            assert!(parsed.orchard().anchor().is_none());
            assert!(parsed.ironwood().anchor().is_none());
            assert_eq!(parsed.orchard().actions().len(), 2);
            assert_eq!(parsed.ironwood().actions().len(), 1);

            // Both pools: `cv_net` and `cmx` are elided, while the ciphertext
            // rides as memo plaintext (proving BOTH outputs elide). The other
            // sighash-committed fields stay byte-identical to the base.
            for (action, base_action) in parsed
                .orchard()
                .actions()
                .iter()
                .zip(base.orchard().actions().iter())
                .chain(
                    parsed
                        .ironwood()
                        .actions()
                        .iter()
                        .zip(base.ironwood().actions().iter()),
                )
            {
                assert!(action.spend().spend_auth_sig().is_none());
                assert!(action.cv_net().is_none());
                assert!(matches!(
                    action.output().enc_ciphertext(),
                    pczt::orchard::EncCiphertext::MemoPlaintext(_)
                ));
                assert_eq!(action.spend().nullifier(), base_action.spend().nullifier());
                assert_eq!(action.spend().rk(), base_action.spend().rk());
                assert!(action.output().cmx().is_none());
                assert_eq!(
                    action.output().ephemeral_key(),
                    base_action.output().ephemeral_key()
                );
            }

            let clear_fvks = |pczt: pczt::Pczt| {
                Redactor::new(pczt)
                    .redact_orchard_with(|mut r| {
                        r.redact_actions(|mut action| action.clear_spend_fvk());
                    })
                    .redact_ironwood_with(|mut r| {
                        r.redact_actions(|mut action| action.clear_spend_fvk());
                    })
                    .finish()
                    .serialize()
                    .unwrap()
            };
            assert_eq!(
                clear_fvks(parsed.clone()),
                batch,
                "batch redaction must already have cleared both pools' spend FVKs",
            );

            let clear_alphas =
                |pczt: pczt::Pczt, orchard_indices: &[usize], ironwood_indices: &[usize]| {
                    let mut redactor = Redactor::new(pczt).redact_orchard_with(|mut r| {
                        for index in orchard_indices {
                            r.redact_action(*index, |mut ar| ar.clear_spend_alpha());
                        }
                    });
                    redactor = redactor.redact_ironwood_with(|mut r| {
                        for index in ironwood_indices {
                            r.redact_action(*index, |mut ar| ar.clear_spend_alpha());
                        }
                    });
                    redactor.finish().serialize().unwrap()
                };
            assert_eq!(
                clear_alphas(
                    parsed.clone(),
                    &orchard_preauthorized,
                    &ironwood_preauthorized,
                ),
                batch,
                "dummy spend alphas must already be absent",
            );
            assert_ne!(
                clear_alphas(parsed.clone(), &[spend_index], &[]),
                batch,
                "the real spend must retain alpha for the device signer",
            );

            // The device path: `resolve_fields` recomputes `cv_net` from the
            // wire values and `rcv` and re-encrypts each memo plaintext from
            // the wire note fields. Both outputs must round-trip
            // byte-identically to the unredacted base.
            let mut refilled = pczt::Pczt::parse(&batch).unwrap();
            refilled.resolve_fields().unwrap();
            // `resolve_fields` does not resurrect anchors; v6 parsing
            // tolerates their absence.
            assert!(refilled.orchard().anchor().is_none());
            assert!(refilled.ironwood().anchor().is_none());
            for (reb, orig) in refilled
                .orchard()
                .actions()
                .iter()
                .zip(base.orchard().actions().iter())
                .chain(
                    refilled
                        .ironwood()
                        .actions()
                        .iter()
                        .zip(base.ironwood().actions().iter()),
                )
            {
                assert_eq!(reb.cv_net(), orig.cv_net());
                assert_eq!(reb.output().cmx(), orig.output().cmx());
                assert_eq!(
                    reb.output().enc_ciphertext(),
                    orig.output().enc_ciphertext()
                );
            }

            // "Signs identically", literally: the resolved compact request
            // yields a byte-identical v6 shielded sighash to the unredacted
            // base...
            let refilled_signer = Signer::new(refilled).unwrap();
            let mut base_signer = Signer::new(pczt::Pczt::parse(&base_bytes).unwrap()).unwrap();
            assert_eq!(
                refilled_signer.shielded_sighash(),
                base_signer.shielded_sighash(),
                "the compact request must produce the exact sighash of the unredacted base",
            );

            // ...so a signature produced over the base verifies against the
            // compact request's own sighash and wire `rk` — the transport
            // contract the device round-trip relies on.
            base_signer.sign_orchard(spend_index, &orchard_ask).unwrap();
            let sig_bytes = orchard_spend_auth_sig_bytes(&base_signer.finish(), spend_index);
            let wire_rk = *parsed
                .orchard()
                .actions()
                .get(spend_index)
                .unwrap()
                .spend()
                .rk();
            VerificationKey::<SpendAuth>::try_from(wire_rk)
                .unwrap()
                .verify(
                    &refilled_signer.shielded_sighash(),
                    &Signature::<SpendAuth>::from(sig_bytes),
                )
                .expect(
                    "base-side signature must verify under the compact request's sighash and rk",
                );
        }
    }
}
