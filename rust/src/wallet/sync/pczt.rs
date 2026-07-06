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
    #[cfg(zcash_unstable = "nu6.3")]
    if matches!(
        zcash_protocol::consensus::BranchId::try_from(consensus_branch_id),
        Ok(zcash_protocol::consensus::BranchId::Nu6_3)
    ) {
        return ironwood_orchard_circuit_version();
    }
    #[cfg(not(zcash_unstable = "nu6.3"))]
    let _ = consensus_branch_id;
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

    pczt.serialize()
        .map_err(|e| format!("Serialize PCZT: {e:?}"))
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
    let consensus_branch_id = *pczt.global().consensus_branch_id();

    let mut prover = Prover::new(pczt);

    if prover.requires_orchard_proof() {
        prover = prover
            .create_orchard_proof(orchard_proving_key_for_consensus_branch(consensus_branch_id))
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

/// Redact a PCZT for a Keystone **migration batch** request. On top of
/// [`redact_pczt_for_signer`], this also clears from every Orchard and Ironwood
/// action:
///
/// - the spend `fvk`: the device verifies each spend's nullifier and `rk` against
///   the FVK it derives from its own stored UFVK and never reads the wire `fvk`,
///   so dropping it saves wire bytes and skips the device's parse-time
///   `FullViewingKey::from_bytes` cost for every action in every check pass;
/// - the spend `spend_auth_sig`: at request time the only signatures present are
///   the wallet's own IO-finalizer dummy signatures. The device skips those
///   dummy spends without needing them, and the wallet's stored copy of the
///   PCZT retains them for the post-signing combine, so on the wire they are
///   pure overhead (and the device would echo them back, bloating the
///   response);
/// - the output `ock`, ZIP32 derivation metadata, and user address string, when
///   present: the device never reads `ock` or ZIP32 metadata while checking,
///   displaying, or signing migration children, and it recovers the recipient
///   from the note ciphertext for wallet-owned migration outputs. The wallet
///   keeps the unredacted PCZT for proof/signature combination;
/// - for a v6 PCZT, the derived fields the device recomputes at parse time
///   (`cv_net`, `cmx`, `ephemeral_key`, `enc_ciphertext` tagged with its
///   [`MemoKind`](pczt::orchard::MemoKind)), the bundle `bsk`s, and any bundle
///   anchor. The action fields are gated by the pre-elision self-check in
///   [`plan_verified_batch_elisions`]; anchors are v6-only and the wallet keeps
///   the unredacted PCZT that owns the real anchor for proof/extraction.
///
/// Only use this for the migration batch flow; the single-transaction hardware
/// send keeps [`redact_pczt_for_signer`].
pub fn redact_pczt_for_batch_signer(pczt_bytes: &[u8]) -> Result<Vec<u8>, String> {
    redact_pczt_for_signer_inner(pczt_bytes, true)
}

/// Redacts a migration-batch PCZT and wraps it as a compressed kind-2 Keystone
/// payload. Firmware inflates this back into the same redacted PCZT before
/// running the normal review and signing checks.
pub fn redact_pczt_for_compressed_batch_signer(pczt_bytes: &[u8]) -> Result<Vec<u8>, String> {
    let redacted = redact_pczt_for_batch_signer(pczt_bytes)?;
    crate::wallet::keystone::encode_compressed_pczt_payload(&redacted)
}

/// Redacts a migration-child PCZT and encodes it in the compact migration child
/// payload shape consumed by matching firmware.
pub fn redact_pczt_for_compact_migration_child_signer(
    pczt_bytes: &[u8],
) -> Result<Vec<u8>, String> {
    pczt::compact_migration::encode_child_from_pczt_bytes(pczt_bytes)
        .map_err(|e| format!("Encode compact migration child PCZT: {e:?}"))
}

/// Derived-field elisions for one Orchard-shaped action of a batch request.
#[derive(Clone, Copy, PartialEq, Eq)]
struct ActionElisions {
    cv_net: bool,
    nullifier: bool,
    rk: bool,
    cmx: bool,
    ephemeral_key: bool,
    /// `Some(kind)` elides `enc_ciphertext`, tagging the note's memo as `kind`
    /// for the device to re-encrypt under.
    enc_ciphertext: Option<pczt::orchard::MemoKind>,
}

/// Elision plan for one Orchard-shaped bundle of a batch request.
#[derive(Clone, PartialEq, Eq, Default)]
struct BundleElisions {
    clear_anchor: bool,
    actions: Vec<ActionElisions>,
}

/// Elision plan for both Orchard-shaped bundles of a v6 batch request.
#[derive(Clone, PartialEq, Eq)]
struct PcztElisions {
    orchard: BundleElisions,
    ironwood: BundleElisions,
}

/// Builds the candidate elision plan for one bundle of the not-yet-redacted PCZT.
///
/// Per action, the three unconditionally recomputable derived fields (`cv_net`,
/// `cmx`, `ephemeral_key`) are candidates, and `enc_ciphertext` is a candidate
/// tagged by the memo the wallet attaches to that output kind. Zero-valued
/// outputs use the all-zero memo tag; the verification pass keeps the elision only
/// when recomputation is byte-identical, so external-scope randomized dummy
/// ciphertexts stay on the wire while internal-scope migration dummies can be
/// elided. Bundle anchors are v6-only batch candidates: `fill_derived_fields`
/// refills them with the fixed `empty_tree`
/// placeholder, and v6 signatures do not commit to anchors.
///
/// Every candidate is verified against a recomputation before use; see
/// [`plan_verified_batch_elisions`].
fn plan_candidate_bundle_elisions(bundle: &pczt::orchard::Bundle) -> BundleElisions {
    let actions = bundle
        .actions()
        .iter()
        .map(|action| {
            let can_refill_spend_fvk = action.spend().has_zip32_derivation();
            let enc_ciphertext = match *action.output().value() {
                Some(0) => Some(pczt::orchard::MemoKind::Zero),
                Some(_) => Some(pczt::orchard::MemoKind::Empty),
                None => None,
            };
            ActionElisions {
                cv_net: true,
                nullifier: can_refill_spend_fvk,
                rk: can_refill_spend_fvk,
                cmx: true,
                ephemeral_key: true,
                enc_ciphertext,
            }
        })
        .collect();
    BundleElisions {
        clear_anchor: true,
        actions,
    }
}

/// Verifies a candidate plan for one bundle against the receiver's actual
/// reconstruction: `probe` is the redacted-then-refilled copy, `original` the
/// untouched bundle. A field stays in the plan only if the refilled value is
/// byte-identical to the original. The elided anchor is intentionally not
/// byte-compared: in v6 it is not part of the signed data, and the wallet retains
/// the unredacted anchor-bearing PCZT for proof creation and extraction.
fn verify_bundle_elisions(
    original: &pczt::orchard::Bundle,
    probe: &pczt::orchard::Bundle,
    candidate: &BundleElisions,
) -> BundleElisions {
    let actions = candidate
        .actions
        .iter()
        .zip(original.actions().iter().zip(probe.actions().iter()))
        .map(|(cand, (orig, reb))| ActionElisions {
            cv_net: cand.cv_net && reb.cv_net() == orig.cv_net(),
            nullifier: cand.nullifier && reb.spend().nullifier() == orig.spend().nullifier(),
            rk: cand.rk && reb.spend().rk() == orig.spend().rk(),
            cmx: cand.cmx && reb.output().cmx() == orig.output().cmx(),
            ephemeral_key: cand.ephemeral_key
                && reb.output().ephemeral_key() == orig.output().ephemeral_key(),
            enc_ciphertext: cand
                .enc_ciphertext
                .filter(|_| reb.output().enc_ciphertext() == orig.output().enc_ciphertext()),
        })
        .collect();
    BundleElisions {
        clear_anchor: candidate.clear_anchor,
        actions,
    }
}

/// Pre-elision self-check for a v6 batch request: builds the candidate plan,
/// applies it to a clone, runs `fill_derived_fields()` on the clone (the exact
/// recomputation the receiver performs at parse time), byte-compares the result
/// against the unredacted original, and returns the plan restricted to the
/// fields that reconstructed identically. Returns `None` (no elision, plain
/// batch redaction) for non-v6 PCZTs or when the fill itself fails.
fn plan_verified_batch_elisions(original: &pczt::Pczt) -> Option<PcztElisions> {
    if *original.global().tx_version() != zcash_protocol::constants::V6_TX_VERSION {
        return None;
    }

    let candidate = PcztElisions {
        orchard: plan_candidate_bundle_elisions(original.orchard()),
        ironwood: plan_candidate_bundle_elisions(original.ironwood()),
    };

    let mut probe = apply_signer_redaction_inner(original.clone(), true, Some(&candidate), false);
    if let Err(e) = probe.fill_derived_fields() {
        log::warn!(
            "[MIGRATION] batch PCZT elision disabled: derived-field recomputation failed: {e:?}"
        );
        return None;
    }

    let verified = PcztElisions {
        orchard: verify_bundle_elisions(original.orchard(), probe.orchard(), &candidate.orchard),
        ironwood: verify_bundle_elisions(
            original.ironwood(),
            probe.ironwood(),
            &candidate.ironwood,
        ),
    };
    if verified != candidate {
        log::warn!(
            "[MIGRATION] batch PCZT elision self-check kept some fields that did not \
             reconstruct identically"
        );
    }
    Some(verified)
}

/// Applies the signer redaction to a parsed PCZT: the standard witness /
/// proprietary clears, the batch-only spend `fvk` and `spend_auth_sig` clears
/// when `for_batch` is set, and the given verified derived-field elisions (plus
/// `bsk`, never needed by the device — the wallet's stored copy retains it for
/// extraction) when a plan is supplied.
fn apply_signer_redaction(
    pczt: pczt::Pczt,
    for_batch: bool,
    elisions: Option<&PcztElisions>,
) -> pczt::Pczt {
    apply_signer_redaction_inner(pczt, for_batch, elisions, true)
}

fn apply_signer_redaction_inner(
    pczt: pczt::Pczt,
    for_batch: bool,
    elisions: Option<&PcztElisions>,
    clear_batch_spend_fvk: bool,
) -> pczt::Pczt {
    use pczt::roles::redactor::Redactor;

    fn apply_bundle_elisions(
        r: &mut pczt::roles::redactor::orchard::OrchardRedactor<'_>,
        plan: &BundleElisions,
    ) {
        r.clear_bsk();
        if plan.clear_anchor {
            r.clear_anchor();
        }
        for (index, e) in plan.actions.iter().enumerate() {
            r.redact_action(index, |mut ar| {
                if e.cv_net {
                    ar.clear_cv_net();
                }
                if e.nullifier {
                    ar.clear_nullifier();
                }
                if e.rk {
                    ar.clear_rk();
                }
                if e.cmx {
                    ar.clear_cmx();
                }
                if e.ephemeral_key {
                    ar.clear_ephemeral_key();
                }
                if let Some(kind) = e.enc_ciphertext {
                    ar.clear_enc_ciphertext(kind);
                }
            });
        }
    }

    let mut redactor = Redactor::new(pczt)
        .redact_global_with(|mut r| r.redact_proprietary("zcash_client_backend:proposal_info"))
        .redact_orchard_with(|mut r| {
            r.redact_actions(|mut ar| {
                ar.clear_spend_witness();
                ar.redact_output_proprietary("zcash_client_backend:output_info");
                if for_batch {
                    if clear_batch_spend_fvk {
                        ar.clear_spend_fvk();
                    }
                    ar.clear_spend_auth_sig();
                    ar.clear_output_ock();
                    ar.clear_output_zip32_derivation();
                    ar.clear_output_user_address();
                }
            });
            if let Some(plan) = elisions {
                apply_bundle_elisions(&mut r, &plan.orchard);
            }
        });

    #[cfg(zcash_unstable = "nu6.3")]
    {
        redactor = redactor.redact_ironwood_with(|mut r| {
            r.redact_actions(|mut ar| {
                ar.clear_spend_witness();
                ar.redact_output_proprietary("zcash_client_backend:output_info");
                if for_batch {
                    if clear_batch_spend_fvk {
                        ar.clear_spend_fvk();
                    }
                    ar.clear_spend_auth_sig();
                    ar.clear_output_ock();
                    ar.clear_output_zip32_derivation();
                    ar.clear_output_user_address();
                }
            });
            if let Some(plan) = elisions {
                apply_bundle_elisions(&mut r, &plan.ironwood);
            }
        });
    }

    redactor
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
        .finish()
}

/// Shared body of [`redact_pczt_for_signer`] and [`redact_pczt_for_batch_signer`]:
/// the standard signer redaction, plus (for batch requests) the spend `fvk` and
/// `spend_auth_sig` clears and the self-checked derived-field elisions.
fn redact_pczt_for_signer_inner(pczt_bytes: &[u8], for_batch: bool) -> Result<Vec<u8>, String> {
    let pczt = pczt::Pczt::parse(pczt_bytes).map_err(|e| format!("Parse PCZT: {e:?}"))?;

    let elisions = if for_batch {
        plan_verified_batch_elisions(&pczt)
    } else {
        None
    };
    let redacted = apply_signer_redaction(pczt, for_batch, elisions.as_ref());

    if *redacted.global().tx_version() == 5 {
        pczt::v1::Pczt::try_from(redacted)
            .map_err(|e| format!("Serialize legacy PCZT for signer: {e:?}"))
            .map(|v1| v1.serialize())
    } else {
        redacted
            .serialize()
            .map_err(|e| format!("Serialize PCZT for signer: {e:?}"))
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
            if *action.spend().nullifier() == Some(spend_nullifier) {
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

    updated
        .serialize()
        .map_err(|e| format!("Serialize updated PCZT: {e:?}"))
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
    let combined = combine_pczts(pczt_with_proofs_bytes, pczt_with_signatures_bytes)?;
    finalize_and_extract(combined, sapling_vks.as_ref())
}

/// Apply a compact, signatures-only response onto the wallet's own
/// proofs-PCZT, then finalize and extract the transaction — the wallet side of
/// the "signatures-only" round-trip.
///
/// This is the equivalent of [`extract_transaction_from_pczt`] for the compact
/// path: instead of receiving a full redacted signed PCZT back from the device
/// and combining it, the device returns only the produced spend-authorization
/// signatures (decoded into [`crate::wallet::keystone::DecodedActionSig`]s).
/// We load the proofs-PCZT the wallet already holds into the [`Signer`] role
/// and re-apply each signature by (pool, action index).
/// `apply_orchard_signature` / `apply_ironwood_signature` rk-verify each
/// signature against the action before storing it, so an incorrect or
/// mismatched signature fails here rather than at broadcast. The finalize +
/// extract tail is shared with the full path via [`finalize_and_extract`],
/// which guarantees the two paths produce identical transaction bytes and
/// txid.
///
/// `sigs` must be the decoded signatures for the single message whose
/// proofs-PCZT is passed in. Sapling params are only required when the PCZT
/// carries a non-empty Sapling bundle (see the module docstring); migration
/// PCZTs are Orchard/Ironwood-only and pass `None`.
///
/// [`Signer`]: pczt::roles::signer::Signer
pub(crate) fn apply_sigs_and_extract(
    pczt_with_proofs_bytes: &[u8],
    sigs: &[crate::wallet::keystone::DecodedActionSig],
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<ExtractedPcztTransaction, String> {
    use crate::wallet::keystone::{DECODED_SIG_POOL_IRONWOOD, DECODED_SIG_POOL_ORCHARD};
    use orchard::primitives::redpallas::{Signature, SpendAuth};
    use pczt::roles::signer::Signer;

    let sapling_vks = load_sapling_verifying_keys(spend_params_path, output_params_path);

    let pczt = pczt::Pczt::parse(pczt_with_proofs_bytes)
        .map_err(|e| format!("Parse PCZT with proofs: {e:?}"))?;
    let mut signer = Signer::new(pczt).map_err(|e| format!("Create PCZT signer: {e:?}"))?;

    let mut seen_sigs = std::collections::HashSet::new();
    for action_sig in sigs {
        if !seen_sigs.insert((action_sig.pool, action_sig.action_index)) {
            return Err(format!(
                "Duplicate compact signature for pool {} action {}",
                action_sig.pool, action_sig.action_index
            ));
        }
        let index = action_sig.action_index as usize;
        // `apply_*_signature` takes a typed redpallas SpendAuth signature; the
        // device sends raw 64-byte signatures, so reconstruct the typed form.
        let signature = Signature::<SpendAuth>::from(action_sig.sig);
        match action_sig.pool {
            DECODED_SIG_POOL_ORCHARD => {
                signer
                    .apply_orchard_signature(index, signature)
                    .map_err(|e| format!("Apply Orchard signature at action {index}: {e:?}"))?;
            }
            DECODED_SIG_POOL_IRONWOOD => {
                #[cfg(zcash_unstable = "nu6.3")]
                {
                    signer
                        .apply_ironwood_signature(index, signature)
                        .map_err(|e| {
                            format!("Apply Ironwood signature at action {index}: {e:?}")
                        })?;
                }
                #[cfg(not(zcash_unstable = "nu6.3"))]
                {
                    let _ = signature;
                    return Err(format!(
                        "Ironwood signature at action {index} requires nu6.3 support"
                    ));
                }
            }
            other => {
                return Err(format!("Unsupported signature pool {other}"));
            }
        }
    }

    let signed = signer.finish();
    finalize_and_extract(signed, sapling_vks.as_ref())
}

/// Read the spend-authorization signatures out of a fully-signed PCZT as a
/// compact [`crate::wallet::keystone::DecodedActionSig`] list — the inverse of
/// [`apply_sigs_and_extract`]'s input.
///
/// This is the local-signing analogue of decoding a device's compact
/// `zcash-batch-sig-result`: the software migration path signs a base PCZT with the
/// USK and then needs only the produced signatures (not the whole signed PCZT)
/// to persist for later finalization, so the encrypted migration DB column
/// stores the same compact form the hardware path stores. Every Orchard (and,
/// under nu6.3, Ironwood) action whose spend carries a `spend_auth_sig` is
/// emitted with its pool discriminant and action index; actions without a
/// signature (outputs / unsigned spends) are skipped.
pub(crate) fn extract_compact_sigs_from_signed_pczt(
    signed_pczt_bytes: &[u8],
) -> Result<Vec<crate::wallet::keystone::DecodedActionSig>, String> {
    use crate::wallet::keystone::{
        DecodedActionSig, DECODED_SIG_POOL_IRONWOOD, DECODED_SIG_POOL_ORCHARD,
    };

    let pczt =
        pczt::Pczt::parse(signed_pczt_bytes).map_err(|e| format!("Parse signed PCZT: {e:?}"))?;

    let mut sigs = Vec::new();
    for (index, action) in pczt.orchard().actions().iter().enumerate() {
        if let Some(sig) = action.spend().spend_auth_sig() {
            sigs.push(DecodedActionSig {
                pool: DECODED_SIG_POOL_ORCHARD,
                action_index: index as u32,
                sig: *sig,
            });
        }
    }

    #[cfg(zcash_unstable = "nu6.3")]
    for (index, action) in pczt.ironwood().actions().iter().enumerate() {
        if let Some(sig) = action.spend().spend_auth_sig() {
            sigs.push(DecodedActionSig {
                pool: DECODED_SIG_POOL_IRONWOOD,
                action_index: index as u32,
                sig: *sig,
            });
        }
    }

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
        #[cfg(zcash_unstable = "nu6.3")]
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
    #[cfg(zcash_unstable = "nu6.3")]
    mod sigs_only_byte_identity {
        // The functions under test live at the module file scope, which is two
        // levels up from this nested test module.
        use super::super::{
            apply_sigs_and_extract, extract_compact_sigs_from_signed_pczt,
            extract_transaction_from_pczt, ironwood_orchard_proving_key, redact_pczt_for_signer,
        };
        use crate::wallet::keystone::{DecodedActionSig, DECODED_SIG_POOL_ORCHARD};

        use orchard::tree::MerkleHashOrchard;
        use pczt::roles::{
            creator::Creator, io_finalizer::IoFinalizer, prover::Prover, signer::Signer,
            updater::Updater,
        };
        use rand_core::OsRng;
        use shardtree::{store::memory::MemoryShardStore, ShardTree};
        use zcash_note_encryption::try_note_decryption;
        use zcash_primitives::transaction::{
            builder::{BuildConfig, Builder, PcztResult},
            fees::zip317,
        };
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
            let mut builder = Builder::new(
                Nu6_3Network,
                10_000_000.into(),
                BuildConfig::Standard {
                    sapling_anchor: None,
                    orchard_anchor: Some(anchor),
                    ironwood_anchor: Some(orchard::Anchor::empty_tree()),
                },
            );
            builder
                .add_orchard_spend::<zip317::FeeRule>(orchard_fvk.clone(), note, merkle_path)
                .unwrap();
            builder
                .add_ironwood_output::<zip317::FeeRule>(
                    Some(orchard_ovk),
                    recipient,
                    // 1_000_000 input - the 10_000 ZIP-317 fee (2 logical
                    // actions: 1 unpadded Orchard + 1 unpadded Ironwood).
                    Zatoshis::const_from_u64(990_000),
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

        fn clear_batch_output_metadata(bytes: &[u8]) -> Vec<u8> {
            let parsed = pczt::Pczt::parse(bytes).unwrap();
            pczt::roles::redactor::Redactor::new(parsed)
                .redact_orchard_with(|mut r| {
                    r.redact_actions(|mut ar| {
                        ar.clear_output_ock();
                        ar.clear_output_zip32_derivation();
                        ar.clear_output_user_address();
                    });
                })
                .redact_ironwood_with(|mut r| {
                    r.redact_actions(|mut ar| {
                        ar.clear_output_ock();
                        ar.clear_output_zip32_derivation();
                        ar.clear_output_user_address();
                    });
                })
                .finish()
                .serialize()
                .unwrap()
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
                extracted_sigs.contains(&DecodedActionSig {
                    pool: DECODED_SIG_POOL_ORCHARD,
                    action_index: spend_index as u32,
                    sig: sig_bytes,
                }),
                "compact sig extraction must include the signer's signature at the spend index"
            );

            // NEW path: hand the SAME signature to the compact path as a
            // (pool, action_index, sig) list and apply it onto the proofs clone.
            let sigs = vec![DecodedActionSig {
                pool: DECODED_SIG_POOL_ORCHARD,
                action_index: spend_index as u32,
                sig: sig_bytes,
            }];
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

        // The batch redaction of a migration-shaped PCZT: elides exactly the
        // self-check-verified action fields, including the deterministic
        // undecryptable ciphertext of the output paired with the real spend, and
        // clears v6 anchors that the signature hash excludes. The wallet retains
        // the unredacted PCZT for proof/extraction, so the request only needs the
        // fields the device signs and displays.
        #[test]
        fn batch_redaction_elides_verified_fields_and_signs_identically() {
            use crate::wallet::sync::pczt::redact_pczt_for_batch_signer;

            let (
                base_bytes,
                orchard_ask,
                spend_index,
                seed_fingerprint,
                derivation_path,
                orchard_fvk,
            ) = build_migration_base_pczt();

            let batch = redact_pczt_for_batch_signer(&base_bytes).unwrap();
            // The whole point of the elision work: a migration child small enough
            // for a short device QR carousel. The retained bytes are now dominated
            // by the still-required `out_ciphertext`s.
            assert!(
                batch.len() < 1_600,
                "batch-redacted migration child should stay near 1.5 kB, got {} bytes",
                batch.len(),
            );

            let base = pczt::Pczt::parse(&base_bytes).unwrap();
            let parsed = pczt::Pczt::parse(&batch).unwrap();
            assert_eq!(
                clear_batch_output_metadata(&batch),
                batch,
                "batch redaction must already clear output ock, ZIP32 derivation metadata, and user address strings",
            );

            // V6 signatures do not commit to anchors, so both bundle anchors are
            // elided even though the Orchard anchor is not byte-identical to the
            // placeholder the receiver refills.
            assert!(parsed.orchard().anchor().is_none());
            assert!(parsed.ironwood().anchor().is_none());
            assert_eq!(parsed.orchard().actions().len(), 1);
            assert_eq!(parsed.ironwood().actions().len(), 1);

            for (index, action) in parsed.orchard().actions().iter().enumerate() {
                assert_eq!(index, spend_index);
                assert!(action.output().user_address().is_none());
                assert!(action.cv_net().is_none());
                assert!(action.output().cmx().is_none());
                assert!(action.output().ephemeral_key().is_none());
                assert!(action.output().enc_ciphertext().is_none());
                assert_eq!(
                    *action.output().memo_kind(),
                    Some(pczt::orchard::MemoKind::Zero)
                );
            }
            for action in parsed.ironwood().actions() {
                // The real migration output is built with `MemoBytes::empty()`.
                assert!(action.output().user_address().is_none());
                assert!(action.cv_net().is_none());
                assert!(action.output().cmx().is_none());
                assert!(action.output().ephemeral_key().is_none());
                assert!(action.output().enc_ciphertext().is_none());
                assert_eq!(
                    *action.output().memo_kind(),
                    Some(pczt::orchard::MemoKind::Empty)
                );
            }

            // Refilling reconstructs every elided action field byte-identically
            // and installs the placeholder anchors the device uses while parsing.
            let mut refilled = pczt::Pczt::parse(&batch).unwrap();
            assert_eq!(
                refilled.fill_missing_spend_fvks_for_zip32_path(
                    &seed_fingerprint,
                    &derivation_path,
                    orchard_fvk,
                ),
                1
            );
            refilled.fill_derived_fields().unwrap();
            assert_ne!(refilled.orchard().anchor(), base.orchard().anchor());
            assert_eq!(
                *refilled.orchard().anchor(),
                Some(orchard::Anchor::empty_tree().to_bytes())
            );
            assert_eq!(
                *refilled.ironwood().anchor(),
                Some(orchard::Anchor::empty_tree().to_bytes())
            );
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
                assert_eq!(reb.output().ephemeral_key(), orig.output().ephemeral_key());
                assert_eq!(
                    reb.output().enc_ciphertext(),
                    orig.output().enc_ciphertext()
                );
            }

            // Byte-identity of the refilled action fields is the on-chain-safety
            // gate: the v6 shielded sighash commits to exactly these action fields
            // and excludes the anchor, so identical action bytes imply the device
            // computes the identical sighash from the elided request. Signing over
            // the batch redaction with pczt's strict `Signer` role is not possible
            // here — the batch format drops the wire `fvk`s the role requires for
            // dummy spends; the Keystone firmware instead verifies against the FVK
            // derived from its own stored UFVK. The sigs-only test above covers the
            // signature transport; the pinned pczt crate's end-to-end tests pin
            // bytes ⟹ sighash ⟹ signature.
            let _ = orchard_ask;
        }
    }
}
