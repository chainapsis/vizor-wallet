//! Delegation lifecycle API.
//!
//! The functions in this module are the stable wallet-facing delegation flow:
//! build a governance PCZT, precompute proof inputs, prove delegation, assemble
//! chain submission data, and record chain recovery data.

pub use crate::phases::DelegationPhase;

use std::borrow::Borrow;

pub use crate::lwd::branch_id_for_height;
use crate::note_bundling::BundlePolicy;
pub use crate::selection::{
    gather_delegation_wallet_inputs, DelegationWalletInputs, GatherDelegationWalletParams,
};
use crate::{
    governance::BUNDLE_NOTE_SLOTS,
    precompute::PirPrecomputeReport,
    round::{BundleLayout, RoundParams, VotingDb},
    types::{DelegationProgressReporter, Network, NoteInfo, VotingError, VotingHotkey},
};
use zcash_client_backend::data_api::{wallet::ConfirmationsPolicy, Account, WalletRead};
use zcash_client_sqlite::{AccountUuid, WalletDb};
use zcash_protocol::consensus::{NetworkConstants, Parameters};

/// Wallet-derived keys and chain parameters needed to build a delegation PCZT.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct DelegationKeys {
    /// Orchard full viewing key bytes for the delegating account.
    pub(crate) fvk_bytes: Vec<u8>,
    /// Raw Orchard address bytes for the hotkey output target.
    pub(crate) hotkey_raw_address: [u8; 43],
    /// ZIP-32 seed fingerprint for the account that owns the delegated notes.
    pub(crate) seed_fingerprint: [u8; 32],
    /// ZIP-32 account index used to derive account-scoped signing keys.
    pub(crate) account_index: u32,
    /// Address index used for governance PCZT output metadata.
    pub(crate) address_index: u32,
    /// Target Zcash network for the hotkey output and proof builders.
    pub(crate) network: Network,
    /// SLIP-44 coin type for the target Zcash network.
    pub(crate) coin_type: u32,
    /// Human-readable round name embedded in PCZT metadata.
    pub(crate) round_name: String,
}

impl DelegationKeys {
    /// Builds delegation keys while validating the raw Orchard hotkey address.
    ///
    /// The returned value is suitable for [`setup`].
    ///
    /// # Errors
    ///
    /// Returns [`VotingError::InvalidInput`] when `hotkey_raw_address` is not
    /// exactly 43 bytes.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn with_hotkey_bytes(
        fvk_bytes: Vec<u8>,
        hotkey_raw_address: &[u8],
        seed_fingerprint: [u8; 32],
        account_index: u32,
        address_index: u32,
        network: Network,
        round_name: String,
    ) -> Result<Self, VotingError> {
        Ok(Self {
            fvk_bytes,
            hotkey_raw_address: array43("hotkey_raw_address", hotkey_raw_address)?,
            seed_fingerprint,
            account_index,
            address_index,
            network,
            coin_type: network.network_type().coin_type(),
            round_name,
        })
    }

    /// Builds delegation keys from a crate-derived voting hotkey.
    ///
    /// The hotkey supplies the raw Orchard output address and address index used
    /// by the governance PCZT. Account fingerprint and account index still refer
    /// to the wallet account that owns the delegated notes.
    #[allow(clippy::too_many_arguments)]
    pub fn with_voting_hotkey(
        fvk_bytes: Vec<u8>,
        hotkey: &VotingHotkey,
        seed_fingerprint: [u8; 32],
        account_index: u32,
        round_name: String,
    ) -> Result<Self, VotingError> {
        Self::with_hotkey_bytes(
            fvk_bytes,
            hotkey.raw_orchard_address(),
            seed_fingerprint,
            account_index,
            hotkey.address_index(),
            hotkey.network(),
            round_name,
        )
    }
}

/// Delegation workflow progress events.
///
/// Host apps emit the bookend variants while orchestrating note selection,
/// signing, and payload assembly. Library functions emit the PCZT/proof stages.
#[derive(Clone, Copy, Debug, PartialEq)]
#[non_exhaustive]
pub enum DelegationProgress {
    SelectingNotes,
    PcztBuilding,
    PcztBuilt,
    ProofStarting,
    ProofProgress(f64),
    ProofComplete,
    SigningPayload,
    PayloadReady,
}

/// Deprecated alias retained for existing SDK integrations.
#[deprecated(note = "use DelegationProgress")]
pub type DelegationStage = DelegationProgress;

/// Supplies the consensus branch id used for a delegation PCZT.
pub trait BranchIdProvider {
    fn consensus_branch_id(&self) -> Result<u32, VotingError>;
}

/// Resolved branch-id provider for delegation PCZT construction.
#[derive(Clone, Debug)]
pub struct LightwalletdBranchIdProvider {
    resolved: u32,
}

impl LightwalletdBranchIdProvider {
    /// Resolves the branch id active at the voting snapshot height.
    pub fn for_height(network: Network, height: u64) -> Result<Self, VotingError> {
        let resolved = crate::lwd::branch_id_for_height(network, height)?;
        Ok(Self { resolved })
    }

    /// Fetches the current lightwalletd tip and resolves the active branch id.
    ///
    /// Round delegation setup should use [`Self::for_height`] with the round
    /// snapshot height so PCZT construction matches note selection and witnesses.
    pub async fn resolve(lightwalletd_url: &str, network: Network) -> Result<Self, VotingError> {
        let branch_height = crate::lwd::latest_block_height_with_retry(lightwalletd_url).await?;
        let resolved = crate::lwd::branch_id_for_height(network, branch_height)?;
        Ok(Self { resolved })
    }

    /// Builds a provider from an already-resolved branch id.
    pub fn resolved(consensus_branch_id: u32) -> Self {
        Self {
            resolved: consensus_branch_id,
        }
    }
}

impl BranchIdProvider for LightwalletdBranchIdProvider {
    fn consensus_branch_id(&self) -> Result<u32, VotingError> {
        Ok(self.resolved)
    }
}

/// Wallet account metadata required to build delegation PCZTs.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DelegationAccountKeys {
    /// ZIP-32 account index of the loaded wallet account.
    pub account_index: u32,
    /// Orchard full viewing key bytes for the loaded account.
    pub orchard_fvk_bytes: [u8; 96],
    /// ZIP-32 seed fingerprint of the loaded account.
    pub seed_fingerprint: [u8; 32],
}

/// Delegation bundle state assembled by wallet integrations before signing.
pub struct DelegationBundleContext {
    pub voting_db: VotingDb,
    pub round_id: String,
    pub bundle_index: u32,
    pub bundle_setup: BundleLayout,
    pub selected_weight_zatoshi: u64,
    pub bundle_note_infos: Vec<NoteInfo>,
    pub delegated_weight_zatoshi: u64,
    pub delegation_keys: DelegationKeys,
    pub branch_id_provider: LightwalletdBranchIdProvider,
    pub round_name: String,
}
/// Round metadata needed to build delegation PCZT inputs.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DelegationRoundContext {
    pub snapshot_height: u64,
    pub round_name: String,
}

/// Ensures the round exists and resolves the display name used in delegation metadata.
///
/// An empty `round_name` falls back to `params.vote_round_id`.
pub fn ensure_round_context(
    voting_db: &VotingDb,
    network: Network,
    params: &RoundParams,
    round_name: &str,
    session_json: Option<&str>,
) -> Result<DelegationRoundContext, VotingError> {
    let state = voting_db.ensure_round_state(network, params, session_json)?;
    Ok(DelegationRoundContext {
        snapshot_height: state.snapshot_height,
        round_name: crate::round::delegation_round_name(params, round_name),
    })
}

/// Parameters for resolving lightwalletd-derived delegation inputs.
pub struct ResolveDelegationLwdParams<'a> {
    pub lightwalletd_url: &'a str,
    pub network: Network,
    pub round_params: crate::VotingRoundParams,
    pub round_name: &'a str,
}

/// Lightwalletd-derived inputs for delegation precompute.
#[derive(Clone, Debug)]
pub struct DelegationLwdInputs {
    pub network: Network,
    pub round_params: crate::VotingRoundParams,
    pub resolved_round_name: String,
    pub anchor_tree_state_bytes: Vec<u8>,
    pub branch_id_provider: LightwalletdBranchIdProvider,
}

/// Parameters for preparing one delegation bundle from caller-owned wallet state.
pub struct PrepareDelegationBundleParams<'a> {
    pub lwd: DelegationLwdInputs,
    pub session_json: Option<&'a str>,
    pub account_uuid: &'a str,
    pub voting_hotkey: &'a VotingHotkey,
    pub bundle_index: u32,
    pub bundle_policy: BundlePolicy,
}

/// Plain delegation bundle state reused by precompute, signing, and submission.
#[derive(Clone, Debug)]
pub struct PreparedDelegationBundle {
    pub round_id: String,
    pub round_params: crate::VotingRoundParams,
    pub bundle_index: u32,
    pub layout: BundleLayout,
    pub bundle_note_infos: Vec<NoteInfo>,
    pub delegation_keys: DelegationKeys,
    pub branch_id_provider: LightwalletdBranchIdProvider,
    pub anchor_tree_state_bytes: Vec<u8>,
    pub network: Network,
    pub round_name: String,
}

/// Validates round params and resolves lightwalletd anchor and branch state.
pub async fn gather_delegation_lwd_inputs(
    params: ResolveDelegationLwdParams<'_>,
) -> Result<DelegationLwdInputs, VotingError> {
    crate::validate_round_params(&params.round_params)?;
    let resolved_round_name =
        crate::round::delegation_round_name(&params.round_params, params.round_name);
    let anchor_tree_state_bytes = crate::lwd::anchor_tree_state_bytes_with_retry(
        params.lightwalletd_url,
        params.round_params.snapshot_height,
    )
    .await?;
    let branch_id_provider = LightwalletdBranchIdProvider::for_height(
        params.network,
        params.round_params.snapshot_height,
    )?;

    Ok(DelegationLwdInputs {
        network: params.network,
        round_params: params.round_params,
        resolved_round_name,
        anchor_tree_state_bytes,
        branch_id_provider,
    })
}

/// Prepares one delegation bundle from caller-owned DB handles and LWD inputs.
///
/// Callers should resolve [`DelegationLwdInputs`] before opening a non-`Send`
/// wallet DB handle in async contexts. This validates/persists round metadata,
/// snapshots wallet state at the current scanned height, and ensures required
/// witnesses exist for the selected bundle.
///
/// # Errors
///
/// Returns an error if round context initialization, wallet access, bundle
/// preparation, or witness persistence fails.
pub fn prepare_delegation_bundle<C, P, CL, R>(
    voting_db: &VotingDb,
    wallet_db: &WalletDb<C, P, CL, R>,
    params: PrepareDelegationBundleParams<'_>,
) -> Result<PreparedDelegationBundle, VotingError>
where
    C: Borrow<rusqlite::Connection>,
    P: Parameters,
{
    let lwd = params.lwd;
    let session_json = params.session_json;
    if lwd.network != params.voting_hotkey.network() {
        return Err(VotingError::InvalidInput {
            message: "delegation LWD network does not match voting hotkey network".to_string(),
        });
    }
    // Ensure the round is present in the voting database.
    ensure_round_context(
        voting_db,
        lwd.network,
        &lwd.round_params,
        &lwd.resolved_round_name,
        session_json,
    )?;
    let DelegationLwdInputs {
        round_params,
        resolved_round_name,
        anchor_tree_state_bytes,
        branch_id_provider,
        network,
    } = lwd;
    let round_id = round_params.vote_round_id.clone();
    let round_name = resolved_round_name.clone();

    // Get the scanned height from the wallet.
    let scanned_height = match wallet_db
        .get_wallet_summary(ConfirmationsPolicy::default())
        .map_err(|e| VotingError::Internal {
            message: format!("wallet summary lookup failed: {e}"),
        })? {
        Some(summary) => u32::from(summary.fully_scanned_height()) as u64,
        None => 0,
    };

    // Gather the wallet inputs.
    let wallet_inputs = gather_delegation_wallet_inputs(GatherDelegationWalletParams {
        wallet_db,
        account_uuid: params.account_uuid,
        voting_hotkey: params.voting_hotkey,
        snapshot_height: round_params.snapshot_height,
        scanned_height,
        anchor_tree_state_bytes,
        resolved_round_name,
    })?;

    // Ensure the round is present in the voting database.
    voting_db.ensure_round(network, &round_params, None)?;
    // Ensure the bundles are present in the voting database.
    let layout = voting_db.ensure_bundles_with_skipped_suffix_with_policy(
        &round_id,
        &wallet_inputs.round_note_infos,
        params.bundle_policy,
    )?;
    let bundle_note_infos = crate::round::bundle_notes_for_index_with_policy(
        &wallet_inputs.round_note_infos,
        &layout,
        params.bundle_index,
        params.bundle_policy,
    )?;

    let prepared = PreparedDelegationBundle {
        round_id,
        round_params,
        bundle_index: params.bundle_index,
        layout,
        bundle_note_infos,
        delegation_keys: wallet_inputs.delegation_keys,
        branch_id_provider,
        anchor_tree_state_bytes: wallet_inputs.anchor_tree_state_bytes,
        network,
        round_name,
    };

    // Ensure witnesses are present in the voting database.
    prepared.ensure_witnesses(voting_db, wallet_db)?;

    Ok(prepared)
}

/// Inputs gathered from lightwalletd and the wallet before voting-DB work.
#[derive(Clone, Debug)]
pub struct DelegationInputs {
    pub account_uuid: String,
    pub round_params: crate::VotingRoundParams,
    pub anchor_tree_state_bytes: Vec<u8>,
    pub round_note_infos: Vec<NoteInfo>,
    pub branch_id_provider: LightwalletdBranchIdProvider,
    pub delegation_keys: DelegationKeys,
}
/// PCZT setup output that callers hand to a signer or QR encoder.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DelegationSetup {
    pub pczt_bytes: Vec<u8>,
    pub pczt_sighash: [u8; 32],
    pub rk: [u8; 32],
    pub action_index: usize,
    pub action_bytes: Vec<u8>,
}

/// Account-scoped data a wallet needs to sign a delegation PCZT locally.
///
/// Wallets should keep root seed material outside this crate. A software wallet
/// can use `account_index`, `network`, `sighash`, and `alpha` to derive its
/// account SpendAuth key locally, randomize it, sign `sighash`, and pass the
/// resulting signature back through [`PreparedSigner::signature`].
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DelegationSigningRequest {
    /// ZIP-32 account index for the account that owns the delegated notes.
    pub account_index: u32,
    /// Target Zcash network for the account signing key.
    pub network: Network,
    /// ZIP-32 seed fingerprint for routing the request to the right wallet seed.
    ///
    /// Wallet-owned signing code should verify or route by this fingerprint before
    /// deriving the account SpendAuth key.
    pub seed_fingerprint: [u8; 32],
    /// ZIP-244 PCZT sighash to sign.
    pub sighash: [u8; 32],
    /// Spend auth randomizer scalar used to compute the randomized signing key.
    pub alpha: [u8; 32],
}

/// Generated delegation proof and public submission fields for one bundle.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DelegationProof {
    pub bytes: Vec<u8>,
    pub rk: [u8; 32],
    pub nf_signed: [u8; 32],
    pub cmx_new: [u8; 32],
    pub van_comm: [u8; 32],
    pub gov_nullifiers: [[u8; 32]; BUNDLE_NOTE_SLOTS],
}

/// Signature source used when assembling a delegation transaction payload.
pub enum DelegationSigner {
    /// Signature that already covers the stored PCZT sighash.
    Signature { sig: [u8; 64], sighash: [u8; 32] },
}

impl DelegationSigner {
    /// Builds a delegation signer from an externally produced SpendAuth signature.
    ///
    /// # Errors
    ///
    /// Returns [`VotingError::InvalidInput`] unless `sig` is 64 bytes and
    /// `sighash` is 32 bytes.
    pub fn signature_from_bytes(sig: &[u8], sighash: &[u8]) -> Result<Self, VotingError> {
        Ok(Self::Signature {
            sig: array64_slice("signature", sig)?,
            sighash: array32_slice("sighash", sighash)?,
        })
    }

    /// Builds a delegation signer from an externally produced SpendAuth signature.
    pub fn signature(sig: [u8; 64], sighash: [u8; 32]) -> Self {
        Self::Signature { sig, sighash }
    }
}

/// Signature source for a prepared delegation bundle.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PreparedSigner {
    /// Signature that already covers the stored PCZT sighash.
    Signature { sig: [u8; 64], sighash: [u8; 32] },
}

impl PreparedSigner {
    /// Builds a prepared signer from an externally produced SpendAuth signature.
    pub fn signature(sig: [u8; 64], sighash: [u8; 32]) -> Self {
        Self::Signature { sig, sighash }
    }

    /// Builds a prepared signer from externally produced SpendAuth signature bytes.
    ///
    /// # Errors
    ///
    /// Returns [`VotingError::InvalidInput`] unless `sig` is 64 bytes and
    /// `sighash` is 32 bytes.
    pub fn signature_from_bytes(sig: &[u8], sighash: &[u8]) -> Result<Self, VotingError> {
        Ok(Self::Signature {
            sig: array64_slice("signature", sig)?,
            sighash: array32_slice("sighash", sighash)?,
        })
    }
}

/// Chain-ready delegation transaction fields for one bundle.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DelegationSubmission {
    pub proof: Vec<u8>,
    pub rk: [u8; 32],
    pub nf_signed: [u8; 32],
    pub cmx_new: [u8; 32],
    pub gov_comm: [u8; 32],
    pub gov_nullifiers: [[u8; 32]; BUNDLE_NOTE_SLOTS],
    pub alpha: [u8; 32],
    pub vote_round_id: String,
    pub spend_auth_sig: [u8; 64],
    pub sighash: [u8; 32],
}

/// Signed delegation bundle plus bundle-level metadata for wallet submission.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SignedDelegationBundle {
    /// Chain-ready delegation fields produced by [`submission`].
    pub submission: DelegationSubmission,
    /// Full governance PCZT bytes that were signed for this bundle.
    pub pczt_bytes: Vec<u8>,
    /// Total eligible round weight after bundle quantization.
    pub eligible_weight_zatoshi: u64,
    /// Quantized weight represented by this bundle.
    pub delegated_weight_zatoshi: u64,
    /// Number of persisted delegation bundles for the round.
    pub bundle_count: u32,
    /// Bundle index represented by this signed payload.
    pub bundle_index: u32,
}

/// Voting PCZT request that should be signed by an external signer.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KeystoneSigningRequest {
    /// Full setup output persisted for later proof and submission assembly.
    pub pczt_bytes: Vec<u8>,
    /// Redacted PCZT bytes safe to send to the signer role.
    pub redacted_pczt_bytes: Vec<u8>,
    /// ZIP-244 sighash extracted from the setup PCZT.
    pub pczt_sighash: Vec<u8>,
    /// Randomized verification key (rk) for signature verification.
    pub rk: Vec<u8>,
    /// Governance action index within the selected shielded protocol bundle.
    pub action_index: u32,
    /// Human-readable memo shown to the signer.
    pub display_memo: String,
    /// Total eligible round weight after bundle quantization.
    pub eligible_weight_zatoshi: u64,
    /// Quantized weight represented by this request's bundle.
    pub delegated_weight_zatoshi: u64,
    /// Number of persisted delegation bundles for the round.
    pub bundle_count: u32,
    /// Bundle index represented by this signing request.
    pub bundle_index: u32,
}

/// Result of warming delegation PIR inputs for one bundle.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PreparedDelegationReport {
    /// PIR rows reused from storage or fetched from the PIR server.
    pub report: PirPrecomputeReport,
    /// Current bundle layout for the round.
    pub layout: BundleLayout,
    /// Bundle index warmed by the precompute operation.
    pub bundle_index: u32,
}

impl PreparedDelegationBundle {
    fn snapshot_branch_id_provider(&self) -> Result<LightwalletdBranchIdProvider, VotingError> {
        LightwalletdBranchIdProvider::for_height(self.network, self.round_params.snapshot_height)
    }

    fn validate_snapshot_branch_id_provider(&self) -> Result<(), VotingError> {
        let expected = self.snapshot_branch_id_provider()?.consensus_branch_id()?;
        let actual = self.branch_id_provider.consensus_branch_id()?;
        if actual != expected {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "delegation branch id 0x{actual:08X} does not match snapshot height {} branch id 0x{expected:08X}",
                    self.round_params.snapshot_height
                ),
            });
        }
        Ok(())
    }

    /// Returns the quantized weight represented by this prepared bundle.
    ///
    /// This is the weight used in delegation payload metadata. Display text may
    /// still use raw ZEC precision through [`display_memo`].
    pub fn delegated_weight_zatoshi(&self) -> Result<u64, VotingError> {
        crate::round::quantized_bundle_weight(&self.bundle_note_infos)
    }

    /// Total eligible round weight after bundle quantization.
    pub fn eligible_weight_zatoshi(&self) -> u64 {
        self.layout.eligible_weight
    }

    /// Persists bundle witnesses when they are missing.
    ///
    /// Callers that separately warm PIR rows can use this before proving without
    /// knowing how witness rows are cached.
    pub fn ensure_witnesses<C, P, CL, R>(
        &self,
        voting_db: &VotingDb,
        wallet_db: &WalletDb<C, P, CL, R>,
    ) -> Result<(), VotingError>
    where
        C: Borrow<rusqlite::Connection>,
        P: Parameters,
    {
        if !voting_db.has_complete_witnesses(
            &self.round_id,
            self.bundle_index,
            &self.bundle_note_infos,
        )? {
            crate::precompute::note_witnesses(
                voting_db,
                &self.round_id,
                self.bundle_index,
                &self.anchor_tree_state_bytes,
                &self.bundle_note_infos,
                wallet_db,
            )?;
        }
        Ok(())
    }

    /// Persists bundle witnesses, initializes padded secrets, and warms PIR rows.
    ///
    /// This is the prepared-bundle replacement for the older loose
    /// `PrecomputeDelegationInputs` path. It never recalculates bundle membership;
    /// the prepared bundle is the source of truth for notes, layout, and network.
    pub fn precompute<C, P, CL, R>(
        &self,
        voting_db: &VotingDb,
        wallet_db: &WalletDb<C, P, CL, R>,
        pir_client: &pir_client::PirClientBlocking,
    ) -> Result<PreparedDelegationReport, VotingError>
    where
        C: Borrow<rusqlite::Connection>,
        P: Parameters,
    {
        self.ensure_witnesses(voting_db, wallet_db)?;

        crate::precompute::warm_delegation_pir(
            voting_db,
            &self.round_id,
            self.bundle_index,
            &self.bundle_note_infos,
            self.layout.clone(),
            pir_client,
            self.network,
        )
    }

    /// Builds and persists the governance PCZT setup for this prepared bundle.
    pub fn setup(
        &self,
        voting_db: &VotingDb,
        stages: &dyn DelegationProgressReporter,
    ) -> Result<DelegationSetup, VotingError> {
        self.validate_snapshot_branch_id_provider()?;
        crate::delegate::setup(
            voting_db,
            &self.round_id,
            self.bundle_index,
            &self.bundle_note_infos,
            &self.delegation_keys,
            &self.branch_id_provider,
            stages,
        )
    }

    /// Generates and persists the delegation proof for this prepared bundle.
    pub fn prove(
        &self,
        voting_db: &VotingDb,
        pir_client: &pir_client::PirClientBlocking,
        stages: &dyn DelegationProgressReporter,
    ) -> Result<DelegationProof, VotingError> {
        crate::delegate::prove(
            voting_db,
            &self.round_id,
            self.bundle_index,
            &self.bundle_note_infos,
            &self.delegation_keys,
            pir_client,
            stages,
        )
    }

    /// Assembles chain-ready submission fields for this prepared bundle.
    pub fn submission(
        &self,
        voting_db: &VotingDb,
        signer: PreparedSigner,
    ) -> Result<DelegationSubmission, VotingError> {
        let signer = match signer {
            PreparedSigner::Signature { sig, sighash } => DelegationSigner::signature(sig, sighash),
        };
        crate::delegate::submission(voting_db, &self.round_id, self.bundle_index, signer)
    }

    /// Assembles a signed delegation bundle plus wallet-facing metadata.
    ///
    /// Pass the full PCZT bytes returned by [`PreparedDelegationBundle::setup`]
    /// for software signing. External signer flows that must not retain the PCZT
    /// in the returned payload can pass an empty vector after verifying the
    /// signature against the stored setup sighash.
    pub fn signed_bundle(
        &self,
        voting_db: &VotingDb,
        pczt_bytes: Vec<u8>,
        signer: PreparedSigner,
    ) -> Result<SignedDelegationBundle, VotingError> {
        if !pczt_bytes.is_empty() {
            let provided_sighash = pczt_sighash(&pczt_bytes)?;
            let PreparedSigner::Signature { sighash, .. } = &signer;
            if provided_sighash != *sighash {
                return Err(VotingError::InvalidInput {
                    message: "pczt_bytes sighash does not match delegation signer sighash"
                        .to_string(),
                });
            }
        }
        let submission = self.submission(voting_db, signer)?;
        Ok(SignedDelegationBundle {
            submission,
            pczt_bytes,
            eligible_weight_zatoshi: self.eligible_weight_zatoshi(),
            delegated_weight_zatoshi: self.delegated_weight_zatoshi()?,
            bundle_count: self.layout.bundle_count,
            bundle_index: self.bundle_index,
        })
    }

    /// Loads the account-scoped data needed to sign this prepared bundle locally.
    ///
    /// Call [`PreparedDelegationBundle::setup`] first so the PCZT sighash and
    /// spend auth randomizer have been persisted.
    pub fn signing_request(
        &self,
        voting_db: &VotingDb,
    ) -> Result<DelegationSigningRequest, VotingError> {
        crate::delegate::signing_request(
            voting_db,
            &self.round_id,
            self.bundle_index,
            &self.delegation_keys,
        )
    }

    /// Builds the redacted Keystone signing request for this prepared bundle.
    pub fn keystone_request(
        &self,
        voting_db: &VotingDb,
        stages: &dyn DelegationProgressReporter,
    ) -> Result<KeystoneSigningRequest, VotingError> {
        let setup = self.setup(voting_db, stages)?;
        let redacted_pczt_bytes = redact_delegation_pczt_for_signer(&setup.pczt_bytes)?;
        let display_weight_zatoshi = crate::round::raw_bundle_weight(&self.bundle_note_infos)?;
        let display_memo = display_memo(&self.round_name, display_weight_zatoshi);
        let action_index = crate::wire::BoundedU32::try_from(setup.action_index).map_err(|_| {
            VotingError::InvalidInput {
                message: format!("action_index {} does not fit u32", setup.action_index),
            }
        })?;

        Ok(KeystoneSigningRequest {
            pczt_bytes: setup.pczt_bytes,
            redacted_pczt_bytes,
            pczt_sighash: setup.pczt_sighash.to_vec(),
            rk: setup.rk.to_vec(),
            action_index: action_index.0,
            display_memo,
            eligible_weight_zatoshi: self.eligible_weight_zatoshi(),
            delegated_weight_zatoshi: self.delegated_weight_zatoshi()?,
            bundle_count: self.layout.bundle_count,
            bundle_index: self.bundle_index,
        })
    }
}

/// Loads account keys needed by delegation PCZT construction from a wallet DB.
///
/// `account_uuid` must be a UUID string for an account in `db`. The account
/// must have ZIP-32 derivation metadata, a UFVK, and an Orchard component.
///
/// # Errors
///
/// Returns [`VotingError::InvalidInput`] for malformed UUIDs, missing accounts,
/// or accounts without the required derivation/viewing-key material. Wallet DB
/// read failures are returned as [`VotingError::Internal`].
pub fn load_account_keys<C, P, CL, R>(
    db: &WalletDb<C, P, CL, R>,
    account_uuid: &str,
) -> Result<DelegationAccountKeys, VotingError>
where
    C: Borrow<rusqlite::Connection>,
    P: Parameters,
{
    let account_uuid = parse_account_uuid(account_uuid)?;
    let account = db
        .get_account(account_uuid)
        .map_err(|e| VotingError::Internal {
            message: format!("failed to load voting account: {e}"),
        })?
        .ok_or_else(|| VotingError::InvalidInput {
            message: "voting account not found".to_string(),
        })?;
    let derivation =
        account
            .source()
            .key_derivation()
            .ok_or_else(|| VotingError::InvalidInput {
                message: "voting account has no ZIP-32 derivation metadata".to_string(),
            })?;
    let ufvk = account.ufvk().ok_or_else(|| VotingError::InvalidInput {
        message: "voting account has no UFVK".to_string(),
    })?;
    let orchard_fvk = ufvk.orchard().ok_or_else(|| VotingError::InvalidInput {
        message: "voting account has no Orchard viewing key".to_string(),
    })?;

    Ok(DelegationAccountKeys {
        account_index: u32::from(derivation.account_index()),
        orchard_fvk_bytes: orchard_fvk.to_bytes(),
        seed_fingerprint: derivation.seed_fingerprint().to_bytes(),
    })
}

fn parse_account_uuid(account_uuid: &str) -> Result<AccountUuid, VotingError> {
    let uuid = uuid::Uuid::parse_str(account_uuid).map_err(|e| VotingError::InvalidInput {
        message: format!("invalid account UUID: {e}"),
    })?;
    Ok(AccountUuid::from_uuid(uuid))
}

/// Builds and persists a governance PCZT for one bundle.
///
/// The bundle must already exist via [`VotingDb::ensure_bundles`]. The returned
/// sighash is the exact message that an external signer must sign.
pub fn setup(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    notes: &[NoteInfo],
    keys: &DelegationKeys,
    branch_id_provider: &dyn BranchIdProvider,
    stages: &dyn DelegationProgressReporter,
) -> Result<DelegationSetup, VotingError> {
    let consensus_branch_id = branch_id_provider.consensus_branch_id()?;
    stages.on_progress(DelegationProgress::PcztBuilding);
    let pczt =
        db.build_governance_pczt(round_id, bundle_index, notes, keys, consensus_branch_id)?;
    stages.on_progress(DelegationProgress::PcztBuilt);

    let pczt_sighash = array32("pczt_sighash", pczt.pczt_sighash)?;
    Ok(DelegationSetup {
        pczt_bytes: pczt.pczt_bytes,
        pczt_sighash,
        rk: array32("rk", pczt.rk)?,
        action_index: pczt.action_index,
        action_bytes: pczt.action_bytes,
    })
}

/// Loads the account-scoped data needed to sign a delegation PCZT locally.
///
/// Call [`setup`] first so the PCZT sighash and spend auth randomizer have been
/// persisted for the bundle. `keys` must be the same [`DelegationKeys`] passed
/// to [`setup`]; use [`PreparedDelegationBundle::signing_request`] when working
/// through the prepared-bundle lifecycle.
pub fn signing_request(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    keys: &DelegationKeys,
) -> Result<DelegationSigningRequest, VotingError> {
    db.get_delegation_signing_request(round_id, bundle_index, keys)
}

/// Generates and persists the delegation proof for one bundle.
///
/// Witnesses and PIR proof precompute data must already be present. The proof
/// result is checked against PCZT-derived public fields before persistence.
pub fn prove(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    notes: &[NoteInfo],
    keys: &DelegationKeys,
    pir_client: &pir_client::PirClientBlocking,
    stages: &dyn DelegationProgressReporter,
) -> Result<DelegationProof, VotingError> {
    stages.on_progress(DelegationProgress::ProofStarting);
    let proof =
        db.build_and_prove_delegation(round_id, bundle_index, notes, keys, pir_client, stages)?;
    stages.on_progress(DelegationProgress::ProofComplete);

    Ok(DelegationProof {
        bytes: proof.proof,
        rk: array32("rk", proof.rk)?,
        nf_signed: array32("nf_signed", proof.nf_signed)?,
        cmx_new: array32("cmx_new", proof.cmx_new)?,
        van_comm: array32("van_comm", proof.van_comm)?,
        gov_nullifiers: array32x_bundle_note_slots("gov_nullifiers", proof.gov_nullifiers)?,
    })
}

/// Assembles chain-ready delegation submission fields for one bundle.
///
/// Signers provide a SpendAuth signature over the stored PCZT sighash.
pub fn submission(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    signer: DelegationSigner,
) -> Result<DelegationSubmission, VotingError> {
    let data = match signer {
        DelegationSigner::Signature { sig, sighash } => {
            db.get_delegation_submission_with_signature(round_id, bundle_index, &sig, &sighash)
        }
    }?;

    Ok(DelegationSubmission {
        proof: data.proof,
        rk: array32("rk", data.rk)?,
        nf_signed: array32("nf_signed", data.nf_signed)?,
        cmx_new: array32("cmx_new", data.cmx_new)?,
        gov_comm: array32("gov_comm", data.gov_comm)?,
        gov_nullifiers: array32x_bundle_note_slots("gov_nullifiers", data.gov_nullifiers)?,
        alpha: array32("alpha", data.alpha)?,
        vote_round_id: data.vote_round_id,
        spend_auth_sig: array64("spend_auth_sig", data.spend_auth_sig)?,
        sighash: array32("sighash", data.sighash)?,
    })
}

/// Records the submitted delegation transaction hash for recovery.
pub fn record_submission(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    tx_hash: &str,
) -> Result<(), VotingError> {
    db.store_delegation_tx_hash(round_id, bundle_index, tx_hash)
}

/// Records the confirmed VAN leaf position for a delegated bundle.
pub fn record_van_position(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    position: u32,
) -> Result<(), VotingError> {
    db.store_van_position(round_id, bundle_index, position)
}

/// Extracts the ZIP-244 shielded sighash from a serialized voting PCZT.
pub fn pczt_sighash(pczt_bytes: &[u8]) -> Result<[u8; 32], VotingError> {
    crate::action::extract_pczt_sighash(pczt_bytes)
}

/// Extracts one SpendAuth signature from a Keystone-signed voting PCZT.
pub fn spend_auth_signature(
    signed_pczt_bytes: &[u8],
    action_index: usize,
) -> Result<[u8; 64], VotingError> {
    crate::action::extract_spend_auth_sig(signed_pczt_bytes, action_index)
}

/// Redacts delegation PCZT metadata that signer devices do not need.
///
/// The output preserves signing-relevant transaction data while removing
/// witness and wallet-proprietary metadata before QR or hardware transport.
fn redact_delegation_pczt_for_signer(pczt_bytes: &[u8]) -> Result<Vec<u8>, VotingError> {
    use pczt::roles::redactor::Redactor;

    let pczt = pczt::Pczt::parse(pczt_bytes).map_err(|e| VotingError::InvalidInput {
        message: format!("parse PCZT failed: {e:?}"),
    })?;

    let redactor = Redactor::new(pczt)
        .redact_global_with(|mut r| r.redact_proprietary("zcash_client_backend:proposal_info"))
        .redact_orchard_with(redact_orchard_like_bundle_for_signer);

    #[cfg(zcash_unstable = "nu6.3")]
    let redactor = redactor.redact_ironwood_with(redact_orchard_like_bundle_for_signer);

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

    redacted.serialize().map_err(|e| VotingError::Internal {
        message: format!("PCZT serialization failed: {:?}", e),
    })
}

fn redact_orchard_like_bundle_for_signer(
    mut r: pczt::roles::redactor::orchard::OrchardRedactor<'_>,
) {
    r.redact_actions(|mut ar| {
        ar.clear_spend_witness();
        ar.redact_output_proprietary("zcash_client_backend:output_info");
    });
}

/// Returns the human-readable Keystone memo for a delegation PCZT.
///
/// `total_weight_zatoshi` is displayed with exact 8-decimal ZEC precision. The
/// returned string is capped at 512 bytes to fit signer display constraints.
pub fn display_memo(round_name: &str, total_weight_zatoshi: u64) -> String {
    const DISPLAY_MEMO_MAX_BYTES: usize = 512;
    const DISPLAY_MEMO_PREFIX: &str =
        "I am authorizing this hotkey managed by my wallet to vote on ";
    const DISPLAY_MEMO_ROUND_SUFFIX: &str = ".\nAmount:";

    let zec_whole = total_weight_zatoshi / 100_000_000;
    let zec_frac = total_weight_zatoshi % 100_000_000;
    let amount_suffix = format!(" {}.{:08} ZEC.", zec_whole, zec_frac);
    // ASCII round-name capacity with a 13-digit whole ZEC amount:
    // 512 - len(prefix=61) - len(".\nAmount:"=9) - len(" {whole13}.{frac8} ZEC."=28) = 414.
    // For ASCII input, this byte budget equals the maximum character count.
    let round_name_budget = DISPLAY_MEMO_MAX_BYTES.saturating_sub(
        DISPLAY_MEMO_PREFIX.len() + DISPLAY_MEMO_ROUND_SUFFIX.len() + amount_suffix.len(),
    );
    let round_name_visible = truncate_utf8_prefix(round_name, round_name_budget);
    let memo = format!(
        "{}{}{}{}",
        DISPLAY_MEMO_PREFIX, round_name_visible, DISPLAY_MEMO_ROUND_SUFFIX, amount_suffix
    );

    debug_assert!(memo.len() <= DISPLAY_MEMO_MAX_BYTES);
    memo
}

fn truncate_utf8_prefix(value: &str, max_bytes: usize) -> &str {
    if value.len() <= max_bytes {
        return value;
    }

    let mut end = max_bytes;
    while !value.is_char_boundary(end) {
        end = end.saturating_sub(1);
    }

    &value[..end]
}

fn array32(label: &str, value: Vec<u8>) -> Result<[u8; 32], VotingError> {
    value
        .try_into()
        .map_err(|value: Vec<u8>| VotingError::Internal {
            message: format!("{label} must be 32 bytes, got {}", value.len()),
        })
}

fn array64(label: &str, value: Vec<u8>) -> Result<[u8; 64], VotingError> {
    value
        .try_into()
        .map_err(|value: Vec<u8>| VotingError::Internal {
            message: format!("{label} must be 64 bytes, got {}", value.len()),
        })
}

fn array32x_bundle_note_slots(
    label: &str,
    values: Vec<Vec<u8>>,
) -> Result<[[u8; 32]; BUNDLE_NOTE_SLOTS], VotingError> {
    if values.len() != BUNDLE_NOTE_SLOTS {
        return Err(VotingError::Internal {
            message: format!(
                "{label} must contain {BUNDLE_NOTE_SLOTS} entries, got {}",
                values.len()
            ),
        });
    }

    let arrays = values
        .into_iter()
        .enumerate()
        .map(|(idx, value)| array32(&format!("{label}[{idx}]"), value))
        .collect::<Result<Vec<_>, _>>()?;

    arrays
        .try_into()
        .map_err(|arrays: Vec<[u8; 32]>| VotingError::Internal {
            message: format!(
                "{label} must contain {BUNDLE_NOTE_SLOTS} entries, got {}",
                arrays.len()
            ),
        })
}

fn array43(label: &str, value: &[u8]) -> Result<[u8; 43], VotingError> {
    value.try_into().map_err(|_| VotingError::InvalidInput {
        message: format!("{label} must be 43 bytes, got {}", value.len()),
    })
}

fn array32_slice(label: &str, value: &[u8]) -> Result<[u8; 32], VotingError> {
    value.try_into().map_err(|_| VotingError::InvalidInput {
        message: format!("{label} must be 32 bytes, got {}", value.len()),
    })
}

fn array64_slice(label: &str, value: &[u8]) -> Result<[u8; 64], VotingError> {
    value.try_into().map_err(|_| VotingError::InvalidInput {
        message: format!("{label} must be 64 bytes, got {}", value.len()),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    use orchard::{
        note::{NoteVersion, RandomSeed, Rho},
        value::NoteValue,
        ValuePool,
    };
    use rusqlite::{params, Connection};
    use secrecy::{ExposeSecret, SecretVec};
    use zcash_client_backend::data_api::{chain::ChainState, AccountBirthday, WalletWrite};
    use zcash_client_sqlite::{util::SystemClock, wallet::init::init_wallet_db};
    use zcash_primitives::block::BlockHash;
    #[cfg(zcash_unstable = "nu6.3")]
    use zcash_protocol::consensus::BranchId;
    use zcash_protocol::consensus::{
        Network as ZcashNetwork, NetworkConstants, NetworkUpgrade, Parameters,
    };
    use zip32::Scope;

    const TESTNET_NU6_SNAPSHOT_HEIGHT: u64 = 3_536_500;
    const TESTNET_NU6_BRANCH_ID: u32 = 0x4DEC_4DF0;
    #[cfg(zcash_unstable = "nu6.3")]
    const REGTEST_NU6_3_SNAPSHOT_HEIGHT: u64 = crate::types::REGTEST_NU6_3_ACTIVATION_HEIGHT as u64;

    fn test_voting_hotkey() -> VotingHotkey {
        VotingHotkey::from_stored_secret(&[0x77; 64], Network::Testnet).unwrap()
    }

    #[cfg(zcash_unstable = "nu6.3")]
    fn test_regtest_voting_hotkey() -> VotingHotkey {
        VotingHotkey::from_stored_secret(&[0x77; 64], Network::Regtest).unwrap()
    }

    #[test]
    fn ensure_round_context_initializes_round_and_resolves_round_name() {
        let voting_db = VotingDb::open_in_memory().unwrap();
        voting_db.set_wallet_id("ensure-round-context");
        let params = crate::VotingRoundParams {
            vote_round_id: "0101010101010101010101010101010101010101010101010101010101010101"
                .to_string(),
            snapshot_height: 42,
            ea_pk: vec![1; 32],
            nc_root: vec![2; 32],
            nullifier_imt_root: vec![3; 32],
        };

        let named = ensure_round_context(
            &voting_db,
            Network::Testnet,
            &params,
            "Demo Round",
            Some("{}"),
        )
        .unwrap();
        let fallback =
            ensure_round_context(&voting_db, Network::Testnet, &params, "", None).unwrap();

        assert_eq!(named.snapshot_height, 42);
        assert_eq!(named.round_name, "Demo Round");
        assert_eq!(fallback.round_name, params.vote_round_id);
        assert_eq!(voting_db.list_rounds().unwrap().len(), 1);
    }

    #[cfg(zcash_unstable = "nu6.3")]
    #[test]
    fn prepare_delegation_bundle_returns_plain_reusable_bundle_state() {
        let (_voting_db, round_params, hotkey, prepared) = prepared_wallet_delegation_fixture();
        let divisor = crate::governance::BALLOT_DIVISOR;

        assert_eq!(prepared.round_id, round_params.vote_round_id);
        assert_eq!(
            prepared.round_params.snapshot_height,
            REGTEST_NU6_3_SNAPSHOT_HEIGHT
        );
        assert_eq!(prepared.bundle_index, 0);
        assert_eq!(prepared.layout.bundle_count, 1);
        assert_eq!(prepared.layout.eligible_weight, divisor * 3);
        assert_eq!(prepared.bundle_note_infos.len(), 2);
        assert_eq!(prepared.bundle_note_infos[0].position, 3);
        assert_eq!(prepared.bundle_note_infos[1].position, 7);
        assert_eq!(prepared.anchor_tree_state_bytes, vec![0xAA, 0xBB]);
        assert_eq!(prepared.network, Network::Regtest);
        assert_eq!(prepared.round_name, "Demo Round");
        assert_eq!(
            prepared.branch_id_provider.consensus_branch_id().unwrap(),
            u32::from(BranchId::Nu6_3)
        );
        assert_eq!(
            &prepared.delegation_keys.hotkey_raw_address,
            hotkey.raw_orchard_address()
        );
    }

    #[cfg(zcash_unstable = "nu6.3")]
    #[test]
    fn signed_bundle_rejects_pczt_sighash_mismatch() {
        let (voting_db, _round_params, _hotkey, prepared) = prepared_wallet_delegation_fixture();
        let setup = prepared
            .setup(&voting_db, &crate::types::NoopProgressReporter)
            .unwrap();
        let mut wrong_sighash = setup.pczt_sighash;
        wrong_sighash[0] ^= 0xFF;

        let err = prepared
            .signed_bundle(
                &voting_db,
                setup.pczt_bytes,
                PreparedSigner::signature([0; 64], wrong_sighash),
            )
            .unwrap_err()
            .to_string();

        assert!(err.contains("pczt_bytes sighash does not match delegation signer sighash"));
    }

    #[cfg(zcash_unstable = "nu6.3")]
    #[test]
    fn signing_request_rejects_key_network_mismatch() {
        let (voting_db, _round_params, _hotkey, prepared) = prepared_wallet_delegation_fixture();
        let mut wrong_network_keys = prepared.delegation_keys.clone();
        wrong_network_keys.network = Network::Mainnet;
        wrong_network_keys.coin_type = Network::Mainnet.network_type().coin_type();

        {
            let conn = voting_db.conn();
            crate::storage::queries::store_delegation_data(
                &conn,
                &prepared.round_id,
                "prepare-delegation-bundle-test",
                prepared.bundle_index,
                &[0x11; 32],
                &[],
                &[0x22; 32],
                &[],
                &[0x33; 32],
                &[0x44; 32],
                &[0x55; 32],
                &[0x66; 32],
                &[0x77; 32],
                &[0x88; 32],
                1,
                0,
                &[],
                &[0x99; 32],
            )
            .unwrap();
        }

        let err = signing_request(
            &voting_db,
            &prepared.round_id,
            prepared.bundle_index,
            &wrong_network_keys,
        )
        .expect_err("signing request network must match stored round")
        .to_string();

        assert!(err.contains(
            "delegation keys network Mainnet does not match stored round network Regtest"
        ));
    }

    #[test]
    fn prepared_bundle_metadata_uses_quantized_weight() {
        let divisor = crate::governance::BALLOT_DIVISOR;
        let prepared = prepared_bundle_fixture(vec![note_info(0, divisor + 23)]);

        assert_eq!(prepared.delegated_weight_zatoshi().unwrap(), divisor);
        assert_eq!(
            crate::round::raw_bundle_weight(&prepared.bundle_note_infos).unwrap(),
            divisor + 23
        );
    }

    fn setup_test_account(
        conn: &mut Connection,
    ) -> (
        zcash_client_sqlite::AccountUuid,
        orchard::keys::FullViewingKey,
    ) {
        setup_test_account_for_network(conn, Network::Testnet)
    }

    fn setup_test_account_for_network(
        conn: &mut Connection,
        network: Network,
    ) -> (
        zcash_client_sqlite::AccountUuid,
        orchard::keys::FullViewingKey,
    ) {
        let seed = SecretVec::new(vec![7u8; 32]);
        let mut db = WalletDb::from_connection(conn, network, SystemClock, rand::rngs::OsRng);
        init_wallet_db(&mut db, Some(SecretVec::new(seed.expose_secret().to_vec()))).unwrap();

        let sapling_height = network
            .activation_height(NetworkUpgrade::Sapling)
            .expect("test network has Sapling activation");
        let birthday = AccountBirthday::from_parts(
            ChainState::empty(sapling_height - 1, BlockHash([0; 32])),
            None,
        );
        let (account_uuid, usk) = db.create_account("voter", &seed, &birthday, None).unwrap();
        let orchard_fvk = usk
            .to_unified_full_viewing_key()
            .orchard()
            .expect("test account has Orchard viewing key")
            .clone();

        (account_uuid, orchard_fvk)
    }

    fn account_internal_id(
        conn: &Connection,
        account_uuid: &zcash_client_sqlite::AccountUuid,
    ) -> i64 {
        conn.query_row(
            "SELECT id FROM accounts WHERE uuid = ?1",
            params![account_uuid.expose_uuid().as_bytes()],
            |row| row.get(0),
        )
        .unwrap()
    }

    fn prepared_bundle_fixture(bundle_note_infos: Vec<NoteInfo>) -> PreparedDelegationBundle {
        PreparedDelegationBundle {
            round_id: "round-1".to_string(),
            round_params: crate::VotingRoundParams {
                vote_round_id: "round-1".to_string(),
                snapshot_height: TESTNET_NU6_SNAPSHOT_HEIGHT,
                ea_pk: vec![1; 32],
                nc_root: vec![2; 32],
                nullifier_imt_root: vec![3; 32],
            },
            bundle_index: 0,
            layout: BundleLayout {
                bundle_count: 1,
                eligible_weight: crate::round::quantized_bundle_weight(&bundle_note_infos).unwrap(),
                dropped_count: 0,
            },
            bundle_note_infos,
            delegation_keys: DelegationKeys {
                fvk_bytes: vec![0; 96],
                hotkey_raw_address: [0; 43],
                seed_fingerprint: [0; 32],
                account_index: 0,
                address_index: 0,
                network: Network::Testnet,
                coin_type: Network::Testnet.network_type().coin_type(),
                round_name: "Demo Round".to_string(),
            },
            branch_id_provider: LightwalletdBranchIdProvider::resolved(TESTNET_NU6_BRANCH_ID),
            anchor_tree_state_bytes: vec![0xAA],
            network: Network::Testnet,
            round_name: "Demo Round".to_string(),
        }
    }

    #[cfg(zcash_unstable = "nu6.3")]
    fn prepared_wallet_delegation_fixture() -> (
        VotingDb,
        crate::VotingRoundParams,
        VotingHotkey,
        PreparedDelegationBundle,
    ) {
        let mut conn = Connection::open_in_memory().unwrap();
        let (account_uuid, orchard_fvk) =
            setup_test_account_for_network(&mut conn, Network::Regtest);
        let account_ref = account_internal_id(&conn, &account_uuid);
        let divisor = crate::governance::BALLOT_DIVISOR;

        insert_ironwood_note(
            &conn,
            account_ref,
            &orchard_fvk,
            1,
            (REGTEST_NU6_3_SNAPSHOT_HEIGHT - 2) as u32,
            divisor,
            7,
        );
        insert_ironwood_note(
            &conn,
            account_ref,
            &orchard_fvk,
            2,
            (REGTEST_NU6_3_SNAPSHOT_HEIGHT - 2) as u32,
            divisor * 2,
            3,
        );
        insert_ironwood_note(
            &conn,
            account_ref,
            &orchard_fvk,
            3,
            (REGTEST_NU6_3_SNAPSHOT_HEIGHT + 4) as u32,
            divisor * 3,
            11,
        );

        let wallet_db =
            WalletDb::from_connection(&conn, Network::Regtest, SystemClock, rand::rngs::OsRng);
        let voting_db = VotingDb::open_in_memory().unwrap();
        voting_db.set_wallet_id("prepare-delegation-bundle-test");
        let hotkey = test_regtest_voting_hotkey();
        use group::GroupEncoding;
        let ea_pk = pasta_curves::pallas::Point::from(voting_circuits::spend_auth_g_affine());
        let round_params = crate::VotingRoundParams {
            vote_round_id: "0101010101010101010101010101010101010101010101010101010101010101"
                .to_string(),
            snapshot_height: REGTEST_NU6_3_SNAPSHOT_HEIGHT,
            ea_pk: ea_pk.to_bytes().to_vec(),
            nc_root: vec![2; 32],
            nullifier_imt_root: vec![3; 32],
        };
        let lwd = DelegationLwdInputs {
            network: Network::Regtest,
            round_params: round_params.clone(),
            resolved_round_name: "Demo Round".to_string(),
            anchor_tree_state_bytes: vec![0xAA, 0xBB],
            branch_id_provider: LightwalletdBranchIdProvider::resolved(u32::from(BranchId::Nu6_3)),
        };
        let wallet_inputs = gather_delegation_wallet_inputs(GatherDelegationWalletParams {
            wallet_db: &wallet_db,
            account_uuid: &account_uuid.expose_uuid().to_string(),
            voting_hotkey: &hotkey,
            snapshot_height: round_params.snapshot_height,
            scanned_height: REGTEST_NU6_3_SNAPSHOT_HEIGHT,
            anchor_tree_state_bytes: lwd.anchor_tree_state_bytes.clone(),
            resolved_round_name: lwd.resolved_round_name.clone(),
        })
        .unwrap();
        voting_db
            .ensure_round(Network::Regtest, &round_params, None)
            .unwrap();
        let layout = voting_db
            .ensure_bundles_with_skipped_suffix_with_policy(
                round_params.vote_round_id.as_str(),
                &wallet_inputs.round_note_infos,
                crate::BundlePolicy::default(),
            )
            .unwrap();
        let bundle_note_infos = crate::round::bundle_notes_for_index_with_policy(
            &wallet_inputs.round_note_infos,
            &layout,
            0,
            crate::BundlePolicy::default(),
        )
        .unwrap();
        let prepared = PreparedDelegationBundle {
            round_id: round_params.vote_round_id.clone(),
            round_params: lwd.round_params,
            bundle_index: 0,
            layout,
            bundle_note_infos,
            delegation_keys: wallet_inputs.delegation_keys,
            branch_id_provider: lwd.branch_id_provider,
            anchor_tree_state_bytes: wallet_inputs.anchor_tree_state_bytes,
            network: hotkey.network(),
            round_name: lwd.resolved_round_name,
        };

        (voting_db, round_params, hotkey, prepared)
    }

    fn note_info(position: u64, value: u64) -> NoteInfo {
        NoteInfo {
            commitment: vec![position as u8; 32],
            nullifier: vec![position as u8 + 1; 32],
            value,
            position,
            diversifier: vec![0x03; 11],
            rho: vec![0x04; 32],
            rseed: vec![0x05; 32],
            scope: 0,
            ufvk_str: "uview1test".to_string(),
        }
    }

    fn insert_transaction(conn: &Connection, txid_tag: u8, mined_height: u32) -> i64 {
        let txid = [txid_tag; 32];
        conn.execute(
            "INSERT INTO transactions (txid, mined_height, min_observed_height)
             VALUES (?1, ?2, ?3)",
            params![txid, mined_height, mined_height],
        )
        .unwrap();
        conn.last_insert_rowid()
    }

    fn insert_orchard_note(
        conn: &Connection,
        account_ref: i64,
        orchard_fvk: &orchard::keys::FullViewingKey,
        note_tag: u8,
        mined_height: u32,
        value_zatoshi: u64,
        commitment_tree_position: u64,
    ) {
        insert_note(
            conn,
            account_ref,
            orchard_fvk,
            note_tag,
            mined_height,
            value_zatoshi,
            commitment_tree_position,
            ValuePool::Orchard,
        );
    }

    #[cfg(zcash_unstable = "nu6.3")]
    fn insert_ironwood_note(
        conn: &Connection,
        account_ref: i64,
        orchard_fvk: &orchard::keys::FullViewingKey,
        note_tag: u8,
        mined_height: u32,
        value_zatoshi: u64,
        commitment_tree_position: u64,
    ) {
        insert_note(
            conn,
            account_ref,
            orchard_fvk,
            note_tag,
            mined_height,
            value_zatoshi,
            commitment_tree_position,
            ValuePool::Ironwood,
        );
    }

    fn insert_note(
        conn: &Connection,
        account_ref: i64,
        orchard_fvk: &orchard::keys::FullViewingKey,
        note_tag: u8,
        mined_height: u32,
        value_zatoshi: u64,
        commitment_tree_position: u64,
        pool: ValuePool,
    ) {
        let (table_prefix, note_version) = match pool {
            ValuePool::Orchard => ("orchard", NoteVersion::V2),
            ValuePool::Ironwood => ("ironwood", NoteVersion::V3),
        };
        let transaction_id = insert_transaction(conn, note_tag, mined_height);
        let note = test_note_with_version(orchard_fvk, note_tag, value_zatoshi, note_version);
        let nullifier = note.nullifier(orchard_fvk);

        conn.execute(
            &format!(
                "INSERT INTO {table_prefix}_received_notes (
                transaction_id, action_index, account_id, diversifier, value, rho, rseed,
                nf, is_change, commitment_tree_position, recipient_key_scope, note_version
             )
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 0, ?9, 0, ?10)"
            ),
            params![
                transaction_id,
                i64::from(note_tag),
                account_ref,
                note.recipient().diversifier().as_array(),
                value_zatoshi,
                note.rho().to_bytes(),
                note.rseed().as_bytes(),
                nullifier.to_bytes(),
                commitment_tree_position,
                note_version_code(note_version),
            ],
        )
        .unwrap();
    }

    fn test_note_with_version(
        orchard_fvk: &orchard::keys::FullViewingKey,
        note_tag: u8,
        value_zatoshi: u64,
        note_version: NoteVersion,
    ) -> orchard::Note {
        let recipient = orchard_fvk.address_at(u64::from(note_tag), Scope::External);
        let rho = rho_from_nonce(u64::from(note_tag) + 1);

        for seed_nonce in 1..10_000 {
            let mut seed = [0u8; 32];
            seed[..8].copy_from_slice(&(seed_nonce + u64::from(note_tag) * 10_000).to_le_bytes());
            if let Some(rseed) = Option::<RandomSeed>::from(RandomSeed::from_bytes(seed, &rho)) {
                if let Some(note) = Option::<orchard::Note>::from(orchard::Note::from_parts(
                    recipient,
                    NoteValue::from_raw(value_zatoshi),
                    rho,
                    rseed,
                    note_version,
                )) {
                    return note;
                }
            }
        }

        panic!("failed to generate valid Orchard note fixture");
    }

    fn note_version_code(version: NoteVersion) -> u8 {
        match version {
            NoteVersion::V2 => 2,
            NoteVersion::V3 => 3,
        }
    }

    fn rho_from_nonce(nonce: u64) -> Rho {
        let mut bytes = [0u8; 32];
        bytes[..8].copy_from_slice(&nonce.to_le_bytes());
        Option::<Rho>::from(Rho::from_bytes(&bytes))
            .expect("small integers are valid pallas base field elements")
    }

    #[test]
    fn display_memo_uses_raw_zec_precision() {
        assert_eq!(
            display_memo("Poll", 123_456_789),
            "I am authorizing this hotkey managed by my wallet to vote on Poll.\nAmount: 1.23456789 ZEC."
        );
    }

    #[test]
    fn display_memo_truncates_long_messages() {
        let memo = display_memo(&"A".repeat(600), crate::governance::BALLOT_DIVISOR);
        let expected_suffix = format!(
            ".\nAmount: {}.{:08} ZEC.",
            crate::governance::BALLOT_DIVISOR / 100_000_000,
            crate::governance::BALLOT_DIVISOR % 100_000_000
        );

        assert_eq!(memo.len(), 512);
        assert!(memo.starts_with("I am authorizing this hotkey"));
        assert!(memo.ends_with(&expected_suffix));
    }

    #[test]
    fn display_memo_truncation_preserves_utf8_boundaries() {
        let memo = display_memo(&"é".repeat(300), crate::governance::BALLOT_DIVISOR);
        let expected_suffix = format!(
            ".\nAmount: {}.{:08} ZEC.",
            crate::governance::BALLOT_DIVISOR / 100_000_000,
            crate::governance::BALLOT_DIVISOR % 100_000_000
        );

        assert!(memo.len() <= 512);
        assert!(memo.ends_with(&expected_suffix));
        assert!(memo.is_char_boundary(memo.len()));
    }

    #[test]
    fn display_memo_keeps_amount_line_for_varied_amount_magnitudes() {
        let amount_cases = [
            0_u64,
            1_u64,
            99_999_999_u64,
            100_000_000_u64,
            1_234_567_890_123_456_u64,
            u64::MAX,
        ];

        for amount in amount_cases {
            let memo = display_memo("Poll", amount);
            let expected_amount_line = format!(
                "Amount: {}.{:08} ZEC.",
                amount / 100_000_000,
                amount % 100_000_000
            );

            assert!(memo.contains("\nAmount: "));
            assert!(
                memo.ends_with(&expected_amount_line),
                "memo should preserve amount line for amount={amount}, memo={memo}"
            );
            assert!(memo.len() <= 512);
        }
    }

    #[test]
    fn display_memo_allows_full_ascii_title_when_exactly_at_budget() {
        const DISPLAY_MEMO_MAX_BYTES: usize = 512;
        const DISPLAY_MEMO_PREFIX: &str =
            "I am authorizing this hotkey managed by my wallet to vote on ";
        const DISPLAY_MEMO_ROUND_SUFFIX: &str = ".\nAmount:";

        let amount = 9_999_999_999_999_999_u64;
        let amount_suffix = format!(" {}.{:08} ZEC.", amount / 100_000_000, amount % 100_000_000);
        let title_budget = DISPLAY_MEMO_MAX_BYTES
            - DISPLAY_MEMO_PREFIX.len()
            - DISPLAY_MEMO_ROUND_SUFFIX.len()
            - amount_suffix.len();
        let title = "A".repeat(title_budget);

        let memo = display_memo(&title, amount);
        assert_eq!(memo.len(), 512);
        assert!(memo.contains(&format!("vote on {}", title)));
        assert!(memo.ends_with(&format!("Amount:{amount_suffix}")));
    }

    #[test]
    fn display_memo_truncates_over_budget_ascii_title_only() {
        const DISPLAY_MEMO_MAX_BYTES: usize = 512;
        const DISPLAY_MEMO_PREFIX: &str =
            "I am authorizing this hotkey managed by my wallet to vote on ";
        const DISPLAY_MEMO_ROUND_SUFFIX: &str = ".\nAmount:";

        let amount = 9_999_999_999_999_999_u64;
        let amount_suffix = format!(" {}.{:08} ZEC.", amount / 100_000_000, amount % 100_000_000);
        let title_budget = DISPLAY_MEMO_MAX_BYTES
            - DISPLAY_MEMO_PREFIX.len()
            - DISPLAY_MEMO_ROUND_SUFFIX.len()
            - amount_suffix.len();
        let title = "B".repeat(title_budget + 20);

        let memo = display_memo(&title, amount);
        assert_eq!(memo.len(), 512);
        assert!(memo.contains(&format!("vote on {}", "B".repeat(title_budget))));
        assert!(memo.ends_with(&format!("Amount:{amount_suffix}")));
    }

    #[test]
    fn display_memo_truncates_unicode_title_without_breaking_utf8() {
        let title = "🙂".repeat(300);
        let amount = 42_u64;

        let memo = display_memo(&title, amount);
        assert!(memo.len() <= 512);
        assert!(memo.is_char_boundary(memo.len()));
        assert!(memo.contains("\nAmount: "));
        assert!(memo.ends_with("Amount: 0.00000042 ZEC."));
    }

    #[test]
    fn delegation_keys_validate_hotkey_address_length() {
        let err = DelegationKeys::with_hotkey_bytes(
            vec![8; 96],
            &[7; 42],
            [9; 32],
            0,
            0,
            Network::Testnet,
            "Demo Round".to_string(),
        )
        .unwrap_err()
        .to_string();

        assert!(err.contains("hotkey_raw_address must be 43 bytes"));
    }

    #[test]
    fn lightwalletd_branch_id_provider_resolved_returns_branch_id() {
        let provider = LightwalletdBranchIdProvider::resolved(0x4DEC_4DF0);

        assert_eq!(provider.consensus_branch_id().unwrap(), 0x4DEC_4DF0);
    }

    #[test]
    fn lightwalletd_branch_id_provider_for_height_returns_snapshot_branch_id() {
        let provider =
            LightwalletdBranchIdProvider::for_height(Network::Testnet, TESTNET_NU6_SNAPSHOT_HEIGHT)
                .unwrap();

        assert_eq!(
            provider.consensus_branch_id().unwrap(),
            TESTNET_NU6_BRANCH_ID
        );
    }

    #[cfg(zcash_unstable = "nu6.3")]
    #[test]
    fn prepared_setup_rejects_branch_id_that_does_not_match_snapshot_height() {
        let voting_db = VotingDb::open_in_memory().unwrap();
        let mut prepared =
            prepared_bundle_fixture(vec![note_info(0, crate::governance::BALLOT_DIVISOR)]);
        prepared.network = Network::Regtest;
        prepared.round_params.snapshot_height =
            u64::from(crate::types::REGTEST_NU6_3_ACTIVATION_HEIGHT) - 1;
        prepared.branch_id_provider =
            LightwalletdBranchIdProvider::resolved(u32::from(BranchId::Nu6_3));

        let err = prepared
            .setup(&voting_db, &crate::types::NoopProgressReporter)
            .unwrap_err()
            .to_string();

        assert!(err.contains("does not match snapshot height"));
    }

    #[test]
    fn external_signature_signer_validates_signature_shapes() {
        assert!(matches!(
            DelegationSigner::signature_from_bytes(&[1; 64], &[2; 32]).unwrap(),
            DelegationSigner::Signature { .. }
        ));

        let sig_err = match DelegationSigner::signature_from_bytes(&[1; 63], &[2; 32]) {
            Ok(_) => panic!("short signature should be rejected"),
            Err(err) => err.to_string(),
        };
        let sighash_err = match DelegationSigner::signature_from_bytes(&[1; 64], &[2; 31]) {
            Ok(_) => panic!("short sighash should be rejected"),
            Err(err) => err.to_string(),
        };

        assert!(sig_err.contains("signature must be 64 bytes"));
        assert!(sighash_err.contains("sighash must be 32 bytes"));
    }

    #[test]
    fn load_account_keys_rejects_malformed_uuid() {
        let db = WalletDb::from_connection(
            rusqlite::Connection::open_in_memory().unwrap(),
            zcash_protocol::consensus::Network::TestNetwork,
            zcash_client_sqlite::util::SystemClock,
            rand::rngs::OsRng,
        );
        let err = load_account_keys(&db, "not-a-uuid")
            .unwrap_err()
            .to_string();

        assert!(err.contains("invalid account UUID"));
    }

    #[test]
    fn gather_delegation_wallet_inputs_rejects_malformed_uuid() {
        let db = WalletDb::from_connection(
            rusqlite::Connection::open_in_memory().unwrap(),
            ZcashNetwork::TestNetwork,
            SystemClock,
            rand::rngs::OsRng,
        );
        let hotkey = test_voting_hotkey();
        let err = gather_delegation_wallet_inputs(GatherDelegationWalletParams {
            wallet_db: &db,
            account_uuid: "not-a-uuid",
            voting_hotkey: &hotkey,
            snapshot_height: 12,
            scanned_height: 12,
            anchor_tree_state_bytes: vec![0xAA, 0xBB],
            resolved_round_name: "Demo Round".to_string(),
        })
        .unwrap_err()
        .to_string();

        assert!(err.contains("invalid account UUID"));
    }

    #[test]
    fn gather_delegation_wallet_inputs_rejects_unsynced_wallet() {
        let db = WalletDb::from_connection(
            rusqlite::Connection::open_in_memory().unwrap(),
            ZcashNetwork::TestNetwork,
            SystemClock,
            rand::rngs::OsRng,
        );
        let hotkey = test_voting_hotkey();
        let err = gather_delegation_wallet_inputs(GatherDelegationWalletParams {
            wallet_db: &db,
            account_uuid: "550e8400-e29b-41d4-a716-446655440000",
            voting_hotkey: &hotkey,
            snapshot_height: 12,
            scanned_height: 11,
            anchor_tree_state_bytes: vec![0xAA, 0xBB],
            resolved_round_name: "Demo Round".to_string(),
        })
        .unwrap_err()
        .to_string();

        assert!(err.contains("wallet is not synced to voting snapshot height 12"));
    }

    #[cfg(zcash_unstable = "nu6.3")]
    #[test]
    fn gather_delegation_wallet_inputs_selects_sorted_notes_and_keys() {
        let mut conn = Connection::open_in_memory().unwrap();
        let (account_uuid, orchard_fvk) =
            setup_test_account_for_network(&mut conn, Network::Regtest);
        let account_ref = account_internal_id(&conn, &account_uuid);
        let divisor = crate::governance::BALLOT_DIVISOR;

        insert_ironwood_note(&conn, account_ref, &orchard_fvk, 1, 8, divisor, 7);
        insert_ironwood_note(&conn, account_ref, &orchard_fvk, 2, 8, divisor * 2, 3);
        insert_ironwood_note(&conn, account_ref, &orchard_fvk, 3, 16, divisor * 3, 11);

        let db = WalletDb::from_connection(&conn, Network::Regtest, SystemClock, rand::rngs::OsRng);
        let hotkey = test_regtest_voting_hotkey();
        let inputs = gather_delegation_wallet_inputs(GatherDelegationWalletParams {
            wallet_db: &db,
            account_uuid: &account_uuid.expose_uuid().to_string(),
            voting_hotkey: &hotkey,
            snapshot_height: REGTEST_NU6_3_SNAPSHOT_HEIGHT,
            scanned_height: REGTEST_NU6_3_SNAPSHOT_HEIGHT,
            anchor_tree_state_bytes: vec![0xAA, 0xBB],
            resolved_round_name: "Demo Round".to_string(),
        })
        .unwrap();

        assert_eq!(inputs.anchor_tree_state_bytes, vec![0xAA, 0xBB]);
        assert_eq!(inputs.round_note_infos.len(), 2);
        assert_eq!(inputs.round_note_infos[0].position, 3);
        assert_eq!(inputs.round_note_infos[1].position, 7);
        assert_eq!(
            &inputs.delegation_keys.hotkey_raw_address,
            hotkey.raw_orchard_address()
        );
        assert_eq!(inputs.delegation_keys.address_index, hotkey.address_index());
        assert_eq!(
            inputs.delegation_keys.coin_type,
            Network::Regtest.network_type().coin_type()
        );
        assert_eq!(inputs.delegation_keys.round_name, "Demo Round");
    }

    #[cfg(zcash_unstable = "nu6.3")]
    #[test]
    fn gather_delegation_wallet_inputs_rejects_empty_snapshot() {
        let mut conn = Connection::open_in_memory().unwrap();
        let (account_uuid, _) = setup_test_account_for_network(&mut conn, Network::Regtest);
        let db = WalletDb::from_connection(&conn, Network::Regtest, SystemClock, rand::rngs::OsRng);
        let hotkey = test_regtest_voting_hotkey();
        let err = gather_delegation_wallet_inputs(GatherDelegationWalletParams {
            wallet_db: &db,
            account_uuid: &account_uuid.expose_uuid().to_string(),
            voting_hotkey: &hotkey,
            snapshot_height: REGTEST_NU6_3_SNAPSHOT_HEIGHT,
            scanned_height: REGTEST_NU6_3_SNAPSHOT_HEIGHT,
            anchor_tree_state_bytes: vec![0xAA, 0xBB],
            resolved_round_name: "Demo Round".to_string(),
        })
        .unwrap_err()
        .to_string();

        assert!(err.contains("no spendable voting notes"));
    }

    #[test]
    fn gather_delegation_wallet_inputs_rejects_network_mismatch() {
        let mut conn = Connection::open_in_memory().unwrap();
        let (account_uuid, orchard_fvk) = setup_test_account(&mut conn);
        let account_ref = account_internal_id(&conn, &account_uuid);
        insert_orchard_note(
            &conn,
            account_ref,
            &orchard_fvk,
            1,
            10,
            crate::governance::BALLOT_DIVISOR,
            7,
        );

        let db = WalletDb::from_connection(
            &conn,
            ZcashNetwork::TestNetwork,
            SystemClock,
            rand::rngs::OsRng,
        );
        let hotkey = VotingHotkey::from_stored_secret(&[0x77; 64], Network::Mainnet).unwrap();
        let err = gather_delegation_wallet_inputs(GatherDelegationWalletParams {
            wallet_db: &db,
            account_uuid: &account_uuid.expose_uuid().to_string(),
            voting_hotkey: &hotkey,
            snapshot_height: 12,
            scanned_height: 12,
            anchor_tree_state_bytes: vec![0xAA, 0xBB],
            resolved_round_name: "Demo Round".to_string(),
        })
        .unwrap_err()
        .to_string();

        assert!(err.contains("voting hotkey network does not match wallet DB network"));
    }

    #[test]
    fn redact_delegation_pczt_for_signer_rejects_invalid_pczt_bytes() {
        let err = redact_delegation_pczt_for_signer(&[0xFF, 0x00])
            .unwrap_err()
            .to_string();

        assert!(err.contains("parse PCZT failed"));
    }

    #[cfg(zcash_unstable = "nu6.3")]
    const OUTPUT_INFO_KEY: &str = "zcash_client_backend:output_info";

    #[cfg(zcash_unstable = "nu6.3")]
    fn ironwood_spend_witnesses_present(pczt: &pczt::Pczt) -> Vec<bool> {
        let mut witnesses = Vec::new();
        pczt::roles::updater::Updater::new(pczt.clone())
            .update_ironwood_with(|updater| {
                witnesses = updater
                    .bundle()
                    .actions()
                    .iter()
                    .map(|action| action.spend().witness().is_some())
                    .collect();
                Ok(())
            })
            .expect("inspect Ironwood spend witnesses");
        witnesses
    }

    #[cfg(zcash_unstable = "nu6.3")]
    fn pczt_with_ironwood_output_info(pczt: &pczt::Pczt) -> pczt::Pczt {
        pczt::roles::updater::Updater::new(pczt.clone())
            .update_ironwood_with(|mut updater| {
                for index in 0..updater.bundle().actions().len() {
                    updater.update_action_with(index, |mut action| {
                        action.set_output_proprietary(OUTPUT_INFO_KEY.to_string(), vec![1, 2, 3]);
                        Ok(())
                    })?;
                }
                Ok(())
            })
            .expect("seed Ironwood output info")
            .finish()
    }

    #[cfg(zcash_unstable = "nu6.3")]
    #[test]
    fn redact_delegation_pczt_for_signer_redacts_ironwood_actions() {
        let (voting_db, _round_params, _hotkey, mut prepared) =
            prepared_wallet_delegation_fixture();
        prepared.network = Network::Regtest;
        prepared.delegation_keys.network = Network::Regtest;
        prepared.delegation_keys.coin_type = Network::Regtest.network_type().coin_type();
        prepared.round_params.snapshot_height =
            u64::from(crate::types::REGTEST_NU6_3_ACTIVATION_HEIGHT);
        prepared.branch_id_provider =
            LightwalletdBranchIdProvider::resolved(u32::from(BranchId::Nu6_3));
        {
            let conn = voting_db.conn();
            let wallet_id = voting_db.wallet_id();
            conn.execute(
                "UPDATE rounds SET network = ?1, snapshot_height = ?2 WHERE round_id = ?3 AND wallet_id = ?4",
                params![
                    crate::storage::queries::network_to_storage(Network::Regtest),
                    prepared.round_params.snapshot_height as i64,
                    prepared.round_id.as_str(),
                    wallet_id,
                ],
            )
            .unwrap();
        }

        let request = prepared
            .keystone_request(&voting_db, &crate::types::NoopProgressReporter)
            .expect("build Keystone request");
        let full_pczt = pczt::Pczt::parse(&request.pczt_bytes).expect("parse full PCZT");
        let seeded_pczt = pczt_with_ironwood_output_info(&full_pczt);
        let seeded_pczt_bytes = seeded_pczt.serialize().expect("serialize seeded PCZT");
        let redacted_pczt_bytes = redact_delegation_pczt_for_signer(&seeded_pczt_bytes)
            .expect("redact seeded Ironwood PCZT");
        let redacted_pczt = pczt::Pczt::parse(&redacted_pczt_bytes).expect("parse redacted PCZT");

        assert!(full_pczt.orchard().actions().is_empty());
        assert_eq!(full_pczt.ironwood().actions().len(), 2);
        assert!(ironwood_spend_witnesses_present(&full_pczt)
            .iter()
            .any(|witness| *witness));

        assert!(redacted_pczt.orchard().actions().is_empty());
        assert_eq!(redacted_pczt.ironwood().actions().len(), 2);
        assert!(ironwood_spend_witnesses_present(&redacted_pczt)
            .iter()
            .all(|witness| !*witness));
        assert!(redacted_pczt
            .ironwood()
            .actions()
            .iter()
            .all(|action| { !action.output().proprietary().contains_key(OUTPUT_INFO_KEY) }));
        assert_eq!(
            pczt_sighash(&redacted_pczt_bytes).unwrap(),
            pczt_sighash(&seeded_pczt_bytes).unwrap()
        );
    }
}
