use std::fmt;

use ff::PrimeField;
use orchard::note::ExtractedNoteCommitment;
use pasta_curves::pallas;
use serde::{Deserialize, Serialize};
use subtle::CtOption;
use thiserror::Error;
use zcash_client_backend::proto::service::TreeState;
use zcash_keys::keys::UnifiedFullViewingKey;
use zcash_protocol::consensus::{
    self, BlockHeight, Network as ZcashNetwork, NetworkType, NetworkUpgrade, Parameters,
};
use zeroize::Zeroizing;
use zip32::Scope;

use crate::governance::BUNDLE_NOTE_SLOTS;
pub use crate::wire::VotingRoundParams;

/// Lowest valid on-chain proposal identifier. Proposal id 0 is reserved by the
/// vote circuit.
pub const MIN_PROPOSAL_ID: u32 = 1;

/// Highest valid on-chain proposal identifier supported by the vote circuit.
pub const MAX_PROPOSAL_ID: u32 = 15;

/// Minimum number of options a proposal can declare.
pub const MIN_VOTE_OPTIONS: u32 = 2;

/// Maximum number of options a proposal can declare.
pub const MAX_VOTE_OPTIONS: u32 = 8;

#[cfg(zcash_unstable = "nu6.3")]
pub(crate) const REGTEST_NU6_3_ACTIVATION_HEIGHT: u32 = 10;

#[derive(Debug, Error)]
pub enum VotingError {
    #[error("Invalid input: {message}")]
    InvalidInput { message: String },
    #[error("Proof generation failed: {message}")]
    ProofFailed { message: String },
    #[error("Internal error: {message}")]
    Internal { message: String },
}

/// Zcash network selector used by wallet-facing voting APIs.
///
/// The enum replaces the historical `network_id` convention, where `0`
/// meant testnet and `1` meant mainnet. Use [`Network::id`] only when calling
/// legacy internals that still take the numeric representation.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Network {
    Testnet,
    Mainnet,
    Regtest,
}

impl Parameters for Network {
    fn network_type(&self) -> NetworkType {
        match self {
            Self::Mainnet => NetworkType::Main,
            Self::Testnet => NetworkType::Test,
            Self::Regtest => NetworkType::Regtest,
        }
    }

    fn activation_height(&self, nu: NetworkUpgrade) -> Option<BlockHeight> {
        match self {
            Self::Mainnet => ZcashNetwork::MainNetwork.activation_height(nu),
            Self::Testnet => ZcashNetwork::TestNetwork.activation_height(nu),
            Self::Regtest => match nu {
                NetworkUpgrade::Overwinter
                | NetworkUpgrade::Sapling
                | NetworkUpgrade::Blossom
                | NetworkUpgrade::Heartwood
                | NetworkUpgrade::Canopy
                | NetworkUpgrade::Nu5
                | NetworkUpgrade::Nu6
                | NetworkUpgrade::Nu6_1
                | NetworkUpgrade::Nu6_2 => Some(BlockHeight::from_u32(1)),
                #[cfg(zcash_unstable = "nu6.3")]
                NetworkUpgrade::Nu6_3 => {
                    Some(BlockHeight::from_u32(REGTEST_NU6_3_ACTIVATION_HEIGHT))
                }
                #[cfg(not(zcash_unstable = "nu6.3"))]
                NetworkUpgrade::Nu6_3 => None,
            },
        }
    }
}

/// Unwrap a `CtOption`, returning a `VotingError` on `None`.
pub fn ct_option_to_result<T>(opt: CtOption<T>, msg: &str) -> Result<T, VotingError> {
    if opt.is_some().into() {
        Ok(opt.unwrap())
    } else {
        Err(VotingError::Internal {
            message: msg.to_string(),
        })
    }
}

/// Voting hotkey material used as the delegation output target and vote signer.
#[derive(PartialEq, Eq)]
pub struct VotingHotkey {
    stored_secret: Zeroizing<Vec<u8>>,
    raw_orchard_address: [u8; 43],
    address_index: u32,
    network: Network,
}

impl VotingHotkey {
    /// Reconstructs a voting hotkey from previously stored hotkey secret bytes.
    ///
    /// `stored_secret` must be material previously returned by
    /// [`VotingHotkey::stored_secret`] after [`crate::hotkey::generate_random_voting_hotkey`].
    /// It is not wallet seed or mnemonic-derived material.
    ///
    /// # Errors
    ///
    /// Returns [`VotingError::InvalidInput`] when `stored_secret` is not the
    /// expected stored hotkey length or cannot produce an Orchard key for
    /// `network`.
    pub fn from_stored_secret(stored_secret: &[u8], network: Network) -> Result<Self, VotingError> {
        crate::hotkey::voting_hotkey_from_stored_secret(stored_secret, network)
    }

    /// Builds a voting hotkey from crate-derived secret material and address bytes.
    pub(crate) fn from_parts(
        stored_secret: Vec<u8>,
        raw_orchard_address: [u8; 43],
        address_index: u32,
        network: Network,
    ) -> Self {
        Self {
            stored_secret: Zeroizing::new(stored_secret),
            raw_orchard_address,
            address_index,
            network,
        }
    }

    /// Returns the opaque hotkey secret that should be stored for later reuse.
    ///
    /// Wallet integrations should treat these bytes as an opaque app-owned
    /// voting hotkey secret, not as wallet seed material.
    pub fn stored_secret(&self) -> &[u8] {
        self.stored_secret.as_slice()
    }

    /// Returns the raw Orchard address bytes used as the delegation PCZT output.
    pub fn raw_orchard_address(&self) -> &[u8; 43] {
        &self.raw_orchard_address
    }

    /// Returns the Orchard address index used for governance metadata.
    pub fn address_index(&self) -> u32 {
        self.address_index
    }

    /// Returns the network used to derive this hotkey's Orchard address.
    pub fn network(&self) -> Network {
        self.network
    }
}

impl Clone for VotingHotkey {
    fn clone(&self) -> Self {
        Self::from_parts(
            self.stored_secret.as_slice().to_vec(),
            self.raw_orchard_address,
            self.address_index,
            self.network,
        )
    }
}

impl fmt::Debug for VotingHotkey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("VotingHotkey")
            .field("stored_secret_len", &self.stored_secret.len())
            .field("raw_orchard_address", &self.raw_orchard_address)
            .field("address_index", &self.address_index)
            .field("network", &self.network)
            .finish()
    }
}

/// A shielded voting note from the wallet DB.
///
/// This branch supports Ironwood/V3 note material for NU6.3 voting rounds.
/// `NoteInfo` contains the fields needed for delegation proof construction and
/// governance PCZT building.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NoteInfo {
    /// Extracted note commitment (cmx), recomputed from note parts.
    pub commitment: Vec<u8>,
    /// Nullifier (32 bytes).
    pub nullifier: Vec<u8>,
    /// Note value in zatoshis.
    pub value: u64,
    /// Position in the note commitment tree.
    pub position: u64,
    /// Diversifier bytes (11 bytes).
    pub diversifier: Vec<u8>,
    /// Rho field (32 bytes, LE encoding of pallas::Base).
    pub rho: Vec<u8>,
    /// Random seed (32 bytes).
    pub rseed: Vec<u8>,
    /// Key scope: 0 = external, 1 = internal.
    pub scope: u32,
    /// Unified full viewing key string for this note's account.
    pub ufvk_str: String,
}

impl NoteInfo {
    /// Builds voting note metadata from a shielded note owned by the given UFVK.
    ///
    /// The `orchard` crate represents both Orchard/V2 and Ironwood/V3 notes.
    /// Callers are responsible for selecting Ironwood/V3 notes for the voting
    /// round.
    pub fn from_orchard_note<P: consensus::Parameters>(
        note: &orchard::note::Note,
        position: u64,
        scope: Scope,
        ufvk: &UnifiedFullViewingKey,
        network: &P,
    ) -> Result<Self, VotingError> {
        let fvk = ufvk.orchard().ok_or_else(|| VotingError::InvalidInput {
            message: "ufvk has no Orchard component".to_string(),
        })?;
        let nullifier = note.nullifier(fvk);
        let commitment: ExtractedNoteCommitment = note.commitment().into();
        let scope = match scope {
            Scope::External => 0,
            Scope::Internal => 1,
        };

        Ok(Self {
            commitment: commitment.to_bytes().to_vec(),
            nullifier: nullifier.to_bytes().to_vec(),
            value: note.value().inner(),
            position,
            diversifier: note.recipient().diversifier().as_array().to_vec(),
            rho: note.rho().to_bytes().to_vec(),
            rseed: note.rseed().as_bytes().to_vec(),
            scope,
            ufvk_str: ufvk.encode(network),
        })
    }
}

/// A snapshot-eligible shielded note selected for voting.
///
/// `NoteInfo` is the executable proof input. `NoteRef` keeps wallet/UI metadata
/// beside the same note material so SDKs can display the selected notes.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NoteRef {
    /// Shielded pool label for wallet/UI display, such as `orchard` or `ironwood`.
    pub pool: String,
    pub txid_hex: String,
    pub output_index: u32,
    pub value_zatoshi: u64,
    /// Compatibility field for callers that display individual note rows.
    ///
    /// Voting power is quantized per smart bundle, not per note. This mirrors
    /// `value_zatoshi` so sub-divisor notes remain visible to callers while
    /// [`crate::note_bundling::voting_power`] reports the real bundle-quantized total.
    pub voting_weight_zatoshi: u64,
    pub commitment: Vec<u8>,
    pub nullifier: Vec<u8>,
    pub diversifier: Vec<u8>,
    pub rho: Vec<u8>,
    pub rseed: Vec<u8>,
    pub scope: u32,
    pub ufvk_str: String,
    pub commitment_tree_position: u64,
    pub mined_height: u64,
    pub anchor_height: u64,
}

impl NoteRef {
    /// Converts this wallet-selected note into the core voting note payload.
    pub fn to_voting_note_info(&self) -> NoteInfo {
        NoteInfo {
            commitment: self.commitment.clone(),
            nullifier: self.nullifier.clone(),
            value: self.value_zatoshi,
            position: self.commitment_tree_position,
            diversifier: self.diversifier.clone(),
            rho: self.rho.clone(),
            rseed: self.rseed.clone(),
            scope: self.scope,
            ufvk_str: self.ufvk_str.clone(),
        }
    }
}

/// Spendable notes at a voting snapshot, plus the anchor tree state for proofs.
#[derive(Clone, Debug)]
pub struct SelectedNotes {
    pub notes: Vec<NoteRef>,
    pub snapshot_height: u64,
    pub anchor_tree_state: TreeState,
}

impl SelectedNotes {
    /// Returns deterministic notes in the shape expected by proof APIs.
    pub fn voting_note_infos(&self) -> Vec<NoteInfo> {
        self.notes
            .iter()
            .map(NoteRef::to_voting_note_info)
            .collect()
    }
}

/// Delegation action for Keystone signing.
#[derive(Clone, Debug)]
pub struct DelegationAction {
    pub action_bytes: Vec<u8>,
    pub rk: Vec<u8>,
    /// Governance nullifiers, always padded to [`BUNDLE_NOTE_SLOTS`].
    pub gov_nullifiers: Vec<Vec<u8>>,
    /// 32-byte governance commitment (VAN).
    pub van: Vec<u8>,
    /// 32-byte blinding factor used for VAN (must be persisted for later use).
    pub van_comm_rand: Vec<u8>,
    /// Nullifiers for zero-value padded notes (needed for circuit witness in later steps).
    pub dummy_nullifiers: Vec<Vec<u8>>,
    /// Constrained rho for the signed note (32 bytes). Spec §1.3.4.1.
    pub rho_signed: Vec<u8>,
    /// Extracted note commitments (cmx) for padded dummy notes.
    /// Needed for ZKP witness construction in later steps.
    pub padded_cmx: Vec<Vec<u8>>,
    /// Signed note nullifier (32 bytes). Public input to ZKP #1.
    pub nf_signed: Vec<u8>,
    /// Output note commitment (32 bytes). Public input to ZKP #1.
    pub cmx_new: Vec<u8>,
    /// Spend auth randomizer scalar (32 bytes). Needed for Keystone signing.
    pub alpha: Vec<u8>,
    /// Spend authorization signature over `sighash` (64 bytes), supplied after Keystone signing.
    pub spend_auth_sig: Option<Vec<u8>>,
    /// Signed note rseed (32 bytes). Needed for witness reconstruction.
    pub rseed_signed: Vec<u8>,
    /// Output note rseed (32 bytes). Needed for witness reconstruction.
    pub rseed_output: Vec<u8>,
}

/// Governance PCZT for Keystone signing.
///
/// Contains a serialized PCZT whose governance action belongs to the Ironwood
/// shielded protocol for NU6.3 voting rounds. The PCZT's rk and ZIP-244 sighash
/// are internally consistent, so Keystone's SpendAuth signature will verify
/// against them.
#[derive(Clone, Debug)]
pub struct GovernancePczt {
    /// Serialized PCZT bytes ready for UR-encoding and Keystone signing.
    pub pczt_bytes: Vec<u8>,
    /// Randomized verification key (32 bytes). Extracted from the PCZT spend action.
    pub rk: Vec<u8>,
    /// Spend auth randomizer scalar (32 bytes). Needed for ZKP witness.
    pub alpha: Vec<u8>,
    /// Signed note nullifier (32 bytes). Public input to ZKP #1.
    pub nf_signed: Vec<u8>,
    /// Output note commitment (32 bytes). Public input to ZKP #1.
    pub cmx_new: Vec<u8>,
    /// Governance nullifiers, always padded to [`BUNDLE_NOTE_SLOTS`].
    pub gov_nullifiers: Vec<Vec<u8>>,
    /// 32-byte governance commitment (VAN).
    pub van: Vec<u8>,
    /// 32-byte blinding factor used for VAN (must be persisted for later use).
    pub van_comm_rand: Vec<u8>,
    /// Nullifiers for zero-value padded notes (needed for circuit witness).
    pub dummy_nullifiers: Vec<Vec<u8>>,
    /// Constrained rho for the signed note (32 bytes). Spec §1.3.4.1.
    pub rho_signed: Vec<u8>,
    /// Extracted note commitments (cmx) for padded dummy notes.
    pub padded_cmx: Vec<Vec<u8>>,
    /// Signed note rseed (32 bytes). Needed for witness reconstruction.
    pub rseed_signed: Vec<u8>,
    /// Output note rseed (32 bytes). Needed for witness reconstruction.
    pub rseed_output: Vec<u8>,
    /// Canonical delegation action payload for cosmos chain submission.
    pub action_bytes: Vec<u8>,
    /// Index of the paired governance action whose spend and output produce
    /// `nf_signed`, `rk`, `alpha`, and `cmx_new`.
    /// (Actions are padded/shuffled by the Builder.)
    pub action_index: usize,
    /// Padded note secrets: N_padded * 64 bytes (32 rho + 32 rseed per padded note).
    /// Needed to thread Phase 1 randomness to Phase 2 (ZCA-74 fix).
    pub padded_note_secrets: Vec<(Vec<u8>, Vec<u8>)>,
    /// ZIP-244 sighash extracted from the PCZT (32 bytes).
    /// Both Keystone and non-Keystone paths sign this.
    pub pczt_sighash: Vec<u8>,
}

/// El Gamal ciphertext of a voting share.
///
/// SECURITY: `plaintext_value` and `randomness` are secret client-side fields.
/// Only `c1`, `c2`, and `share_index` may be sent to the helper server.
/// Leaking `randomness` lets the helper recover plaintext shares via
/// `v*G = C2 - r*pk`, breaking voter privacy. Do NOT derive `Serialize`
/// on this struct without skipping these fields. `Debug` is hand-written
/// below to redact the secret fields — do not replace it with a derive.
#[derive(Clone)]
pub struct EncryptedShare {
    pub c1: Vec<u8>,
    pub c2: Vec<u8>,
    pub share_index: u32,
    /// Raw share value. SECRET — must not be sent over the network.
    pub plaintext_value: u64,
    /// El Gamal randomness `r` (32 bytes, LE pallas::Scalar repr).
    /// Deterministically derived from (sk, round_id, proposal_id, van_commitment, share_index)
    /// so the client can re-derive it after a crash. SECRET — must not be sent over the network.
    pub randomness: Vec<u8>,
}

/// Hand-written so `{:?}` (and `Debug` on any enclosing struct, e.g.
/// `VoteCommitmentBundle`) never prints `randomness` or `plaintext_value`.
/// With `randomness` and the public `c2`/`ea_pk`, the share plaintext is
/// recoverable via `v*G = C2 - r*pk`; `plaintext_value` is the plaintext itself.
impl std::fmt::Debug for EncryptedShare {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("EncryptedShare")
            .field("c1", &hex::encode(&self.c1))
            .field("c2", &hex::encode(&self.c2))
            .field("share_index", &self.share_index)
            .field("plaintext_value", &"<redacted>")
            .field("randomness", &"<redacted>")
            .finish()
    }
}

/// Complete vote commitment bundle for submission to vote chain.
#[derive(Clone, Debug)]
pub struct VoteCommitmentBundle {
    pub van_nullifier: Vec<u8>,
    pub vote_authority_note_new: Vec<u8>,
    pub vote_commitment: Vec<u8>,
    pub proposal_id: u32,
    pub proof: Vec<u8>,
    /// Encrypted shares generated by the ZKP #2 builder (16 shares).
    /// These are the exact ciphertexts committed in the vote commitment hash
    /// and must be used for reveal-share payloads.
    pub enc_shares: Vec<EncryptedShare>,
    /// Tree anchor height used for the proof.
    pub anchor_height: u32,
    /// Voting round ID (hex string).
    pub vote_round_id: String,
    /// Poseidon hash of encrypted share coordinates (32 bytes).
    /// Intermediate value: vote_commitment = H(DOMAIN_VC, voting_round_id, shares_hash, proposal_id, vote_decision).
    pub shares_hash: Vec<u8>,
    /// Per-share blind factors (16 x 32 bytes, LE pallas::Base repr).
    /// Deterministically derived from (sk, round_id, proposal_id, van_commitment, share_index).
    pub share_blinds: Vec<Vec<u8>>,
    /// Pre-computed per-share Poseidon commitments (N x 32 bytes, LE pallas::Base repr).
    /// share_comm_i = Poseidon(blind_i, c1_i_x, c2_i_x, c1_i_y, c2_i_y).
    /// Sent as public inputs to ZKP #3; the helper only needs the primary blind.
    pub share_comms: Vec<Vec<u8>>,
    /// Compressed r_vpk (32 bytes) for sighash computation and signature verification.
    pub r_vpk_bytes: Vec<u8>,
    /// Spend-auth randomizer alpha_v (32 bytes, LE scalar repr).
    /// Needed to sign the TX2 sighash: rsk_v = ask_v.randomize(&alpha_v).
    pub alpha_v: Vec<u8>,
}

/// Wire-safe encrypted share — contains only the public ciphertext components.
/// Secrets (`plaintext_value`, `randomness`) are kept inside Rust and never cross the FFI boundary.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct WireEncryptedShare {
    #[serde(with = "crate::wire::serde_base64_bytes")]
    pub c1: Vec<u8>,
    #[serde(with = "crate::wire::serde_base64_bytes")]
    pub c2: Vec<u8>,
    pub share_index: u32,
}

impl From<&EncryptedShare> for WireEncryptedShare {
    fn from(s: &EncryptedShare) -> Self {
        Self {
            c1: s.c1.clone(),
            c2: s.c2.clone(),
            share_index: s.share_index,
        }
    }
}

impl From<EncryptedShare> for WireEncryptedShare {
    fn from(s: EncryptedShare) -> Self {
        Self {
            c1: s.c1,
            c2: s.c2,
            share_index: s.share_index,
        }
    }
}

/// Payload sent to helper server for delegated share submission.
#[derive(Clone, Debug)]
pub struct SharePayload {
    pub shares_hash: Vec<u8>,
    pub proposal_id: u32,
    pub vote_decision: u32,
    pub enc_share: WireEncryptedShare,
    pub tree_position: u64,
    /// All encrypted shares (public components only).
    pub all_enc_shares: Vec<WireEncryptedShare>,
    /// Pre-computed per-share Poseidon commitments (N x 32 bytes).
    /// Provided as public inputs to ZKP #3.
    pub share_comms: Vec<Vec<u8>>,
    /// Blind factor for this specific share (32 bytes, LE pallas::Base repr).
    /// Only the revealed share's blind is needed for ZKP #3.
    pub primary_blind: Vec<u8>,
}

/// A share delegation record from the local DB.
/// Tracks which helper servers received each share and its on-chain confirmation status.
#[derive(Clone, Debug)]
pub struct ShareDelegationRecord {
    pub round_id: String,
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub share_index: u32,
    /// JSON-decoded list of helper server URLs that received this share.
    pub sent_to_urls: Vec<String>,
    /// Pre-computed share reveal nullifier (32 bytes).
    pub nullifier: Vec<u8>,
    /// Whether the share has been confirmed on-chain.
    pub confirmed: bool,
    /// Unix seconds: when the helper should submit the share (0 = immediate).
    pub submit_at: u64,
    /// Unix seconds: when the share was delegated.
    pub created_at: u64,
}

/// Computed signature fields for cast-vote TX submission.
/// Returned by `sign_cast_vote` after ZKP #2 builds the vote commitment bundle.
/// The sighash is computed on-chain from the message fields; the client only
/// needs to provide the signature (which was signed over the same sighash).
#[derive(Clone, Debug)]
pub struct CastVoteSignature {
    /// Spend auth signature over the canonical sighash (64 bytes).
    pub vote_auth_sig: Vec<u8>,
}

/// All fields needed to submit a delegation TX to the chain.
/// Fields from DB (proof, rk, nf_signed, cmx_new, gov_comm, gov_nullifiers, alpha)
/// plus computed fields (spend_auth_sig, sighash).
#[derive(Clone, Debug)]
pub struct DelegationSubmissionData {
    pub proof: Vec<u8>,
    pub rk: Vec<u8>,
    pub nf_signed: Vec<u8>,
    pub cmx_new: Vec<u8>,
    pub gov_comm: Vec<u8>,
    pub gov_nullifiers: Vec<Vec<u8>>,
    pub alpha: Vec<u8>,
    pub vote_round_id: String,
    /// Spend auth signature over sighash (64 bytes).
    ///
    /// Legacy seed paths compute this from `seed + alpha`; new integrations pass
    /// an externally produced SpendAuth signature.
    pub spend_auth_sig: Vec<u8>,
    /// Canonical sighash (32 bytes). Blake2b-256 of domain-separated fields.
    pub sighash: Vec<u8>,
}

/// Result of real delegation proof generation (ZKP #1).
#[derive(Clone, Debug)]
pub struct DelegationProofResult {
    /// Halo2 proof bytes.
    pub proof: Vec<u8>,
    /// 12 public input field elements, each as 32-byte LE arrays.
    pub public_inputs: Vec<Vec<u8>>,
    /// Signed note nullifier (32 bytes) — the ZKP's nf_signed (v=0 note).
    pub nf_signed: Vec<u8>,
    /// Output note commitment (32 bytes) — the ZKP's cmx_new (v=0 note).
    pub cmx_new: Vec<u8>,
    /// 5 governance nullifiers (each 32 bytes).
    pub gov_nullifiers: Vec<Vec<u8>>,
    /// Governance commitment / VAN (32 bytes).
    pub van_comm: Vec<u8>,
    /// Randomized verification key (32 bytes, compressed).
    pub rk: Vec<u8>,
}

/// Result of pre-fetching PIR-backed IMT non-membership proofs for ZKP #1.
#[derive(Clone, Debug)]
pub struct DelegationPirPrecomputeResult {
    /// Number of nullifier proofs that were already cached for this bundle.
    pub cached_count: u32,
    /// Number of nullifier proofs fetched from the PIR server during this call.
    pub fetched_count: u32,
}

/// Merkle witness for a note in the selected shielded commitment tree.
#[derive(Clone, Debug)]
pub struct WitnessData {
    pub note_commitment: Vec<u8>,
    pub position: u64,
    pub root: Vec<u8>,
    pub auth_path: Vec<Vec<u8>>,
}

/// Callback for delegation workflow progress events.
pub trait DelegationProgressReporter: Send + Sync {
    fn on_progress(&self, progress: crate::delegate::DelegationProgress);
}

/// Deprecated alias retained for existing SDK integrations.
#[deprecated(note = "use DelegationProgressReporter")]
pub trait DelegationStageReporter: Send + Sync {
    fn on_stage(&self, stage: crate::delegate::DelegationProgress);
}

#[allow(deprecated)]
impl<T> DelegationStageReporter for T
where
    T: DelegationProgressReporter + ?Sized,
{
    fn on_stage(&self, stage: crate::delegate::DelegationProgress) {
        self.on_progress(stage);
    }
}

fn clamp_delegation_progress(
    progress: crate::delegate::DelegationProgress,
) -> crate::delegate::DelegationProgress {
    match progress {
        crate::delegate::DelegationProgress::ProofProgress(value) => {
            crate::delegate::DelegationProgress::ProofProgress(value.clamp(0.0, 1.0))
        }
        progress => progress,
    }
}

/// Delegation progress reporter backed by a closure.
pub struct DelegationProgressBridge<F>
where
    F: Fn(crate::delegate::DelegationProgress) + Send + Sync + 'static,
{
    on_progress: F,
}

impl<F> DelegationProgressBridge<F>
where
    F: Fn(crate::delegate::DelegationProgress) + Send + Sync + 'static,
{
    pub fn new(on_progress: F) -> Self {
        Self { on_progress }
    }
}

impl<F> DelegationProgressReporter for DelegationProgressBridge<F>
where
    F: Fn(crate::delegate::DelegationProgress) + Send + Sync + 'static,
{
    fn on_progress(&self, progress: crate::delegate::DelegationProgress) {
        (self.on_progress)(clamp_delegation_progress(progress));
    }
}

/// Deprecated alias retained for existing SDK integrations.
#[deprecated(note = "use DelegationProgressBridge")]
pub type DelegationStageBridge<F> = DelegationProgressBridge<F>;

impl<T> DelegationProgressReporter for T
where
    T: ProgressReporter + ?Sized,
{
    fn on_progress(&self, progress: crate::delegate::DelegationProgress) {
        if let crate::delegate::DelegationProgress::ProofProgress(value) =
            clamp_delegation_progress(progress)
        {
            self.on_progress(value);
        }
    }
}

/// Callback for cast-vote lifecycle and proof progress stages.
pub trait VoteCommitStageReporter: Send + Sync {
    fn on_stage(&self, stage: crate::vote::VoteCommitStage);
}

fn clamp_vote_commit_stage(stage: crate::vote::VoteCommitStage) -> crate::vote::VoteCommitStage {
    match stage {
        crate::vote::VoteCommitStage::ProofProgress {
            proposal_id,
            bundle_index,
            progress,
        } => crate::vote::VoteCommitStage::ProofProgress {
            proposal_id,
            bundle_index,
            progress: progress.clamp(0.0, 1.0),
        },
        stage => stage,
    }
}

/// Cast-vote stage reporter backed by a closure.
pub struct VoteCommitStageBridge<F>
where
    F: Fn(crate::vote::VoteCommitStage) + Send + Sync + 'static,
{
    on_stage: F,
}

impl<F> VoteCommitStageBridge<F>
where
    F: Fn(crate::vote::VoteCommitStage) + Send + Sync + 'static,
{
    pub fn new(on_stage: F) -> Self {
        Self { on_stage }
    }
}

impl<F> VoteCommitStageReporter for VoteCommitStageBridge<F>
where
    F: Fn(crate::vote::VoteCommitStage) + Send + Sync + 'static,
{
    fn on_stage(&self, stage: crate::vote::VoteCommitStage) {
        (self.on_stage)(clamp_vote_commit_stage(stage));
    }
}

impl<T> VoteCommitStageReporter for T
where
    T: ProgressReporter + ?Sized,
{
    fn on_stage(&self, stage: crate::vote::VoteCommitStage) {
        if let crate::vote::VoteCommitStage::ProofProgress { progress, .. } =
            clamp_vote_commit_stage(stage)
        {
            self.on_progress(progress);
        }
    }
}

/// Callback for proof-generation progress in flows that only report fractions.
pub trait ProgressReporter: Send + Sync {
    fn on_progress(&self, progress: f64);
}

/// No-op progress reporter for contexts where progress isn't observed.
pub struct NoopProgressReporter;

impl ProgressReporter for NoopProgressReporter {
    fn on_progress(&self, _progress: f64) {}
}

// --- Validation helpers ---

pub fn validate_32_bytes(v: &[u8], name: &str) -> Result<(), VotingError> {
    if v.len() != 32 {
        return Err(VotingError::InvalidInput {
            message: format!("{} must be 32 bytes, got {}", name, v.len()),
        });
    }
    Ok(())
}

pub fn validate_share_index(index: u32) -> Result<(), VotingError> {
    if index > 15 {
        return Err(VotingError::InvalidInput {
            message: format!("share_index must be 0..15, got {}", index),
        });
    }
    Ok(())
}

/// Validates that a proposal id is within the vote circuit's on-chain range.
pub fn validate_proposal_id(proposal_id: u32) -> Result<(), VotingError> {
    if !(MIN_PROPOSAL_ID..=MAX_PROPOSAL_ID).contains(&proposal_id) {
        return Err(VotingError::InvalidInput {
            message: format!(
                "proposal_id must be {}..={}, got {}",
                MIN_PROPOSAL_ID, MAX_PROPOSAL_ID, proposal_id
            ),
        });
    }
    Ok(())
}

/// Validates the declared option count for a proposal.
pub fn validate_vote_options(num_options: u32) -> Result<(), VotingError> {
    if !(MIN_VOTE_OPTIONS..=MAX_VOTE_OPTIONS).contains(&num_options) {
        return Err(VotingError::InvalidInput {
            message: format!(
                "num_options must be {}..={}, got {}",
                MIN_VOTE_OPTIONS, MAX_VOTE_OPTIONS, num_options
            ),
        });
    }
    Ok(())
}

/// Validates a zero-indexed vote decision against the proposal option count.
pub fn validate_vote_decision(decision: u32, num_options: u32) -> Result<(), VotingError> {
    validate_vote_options(num_options)?;
    if decision >= num_options {
        return Err(VotingError::InvalidInput {
            message: format!(
                "vote_decision must be in [0, {}), got {}",
                num_options, decision
            ),
        });
    }
    Ok(())
}

pub fn validate_notes(notes: &[NoteInfo]) -> Result<(), VotingError> {
    if notes.is_empty() || notes.len() > BUNDLE_NOTE_SLOTS {
        return Err(VotingError::InvalidInput {
            message: format!(
                "notes must have 1..={BUNDLE_NOTE_SLOTS} entries, got {}",
                notes.len()
            ),
        });
    }
    for (i, note) in notes.iter().enumerate() {
        validate_32_bytes(&note.commitment, &format!("notes[{}].commitment", i))?;
        validate_32_bytes(&note.nullifier, &format!("notes[{}].nullifier", i))?;
    }
    Ok(())
}

pub fn validate_round_params(params: &VotingRoundParams) -> Result<(), VotingError> {
    validate_vote_round_id_hex(&params.vote_round_id)?;
    validate_32_bytes(&params.ea_pk, "ea_pk")?;
    validate_32_bytes(&params.nc_root, "nc_root")?;
    validate_32_bytes(&params.nullifier_imt_root, "nullifier_imt_root")?;
    Ok(())
}

/// Validate a hex-encoded voting round id.
///
/// A valid round id is exactly 32 bytes encoded as lowercase hex, and those
/// bytes must be a canonical little-endian [`pallas::Base`] encoding. This
/// validates the round-id representation accepted by the voting circuits; it
/// does not recompute the on-chain Poseidon preimage for the round id.
pub fn validate_vote_round_id_hex(vote_round_id: &str) -> Result<(), VotingError> {
    if vote_round_id.len() != 64 {
        return Err(VotingError::InvalidInput {
            message: format!(
                "vote_round_id must be 64 lowercase hex characters, got {}",
                vote_round_id.len()
            ),
        });
    }
    if !vote_round_id
        .bytes()
        .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err(VotingError::InvalidInput {
            message: "vote_round_id must be lowercase hex".to_string(),
        });
    }
    let bytes = hex::decode(vote_round_id).map_err(|e| VotingError::InvalidInput {
        message: format!("vote_round_id is not valid hex: {e}"),
    })?;
    validate_vote_round_id_bytes(&bytes)
}

/// Validate raw voting round-id bytes as a canonical Pallas base-field element.
pub fn validate_vote_round_id_bytes(vote_round_id: &[u8]) -> Result<(), VotingError> {
    let bytes: [u8; 32] = vote_round_id
        .try_into()
        .map_err(|_| VotingError::InvalidInput {
            message: format!(
                "vote_round_id must be 32 bytes, got {}",
                vote_round_id.len()
            ),
        })?;
    Option::<pallas::Base>::from(pallas::Base::from_repr(bytes)).ok_or_else(|| {
        VotingError::InvalidInput {
            message: "vote_round_id is not a canonical Pallas field element".to_string(),
        }
    })?;
    Ok(())
}

/// Validate any number of notes for a round (>0). Checks commitments/nullifiers.
/// Unlike `validate_notes` (which enforces 1-5 per bundle), this allows any count.
pub fn validate_notes_for_round(notes: &[NoteInfo]) -> Result<(), VotingError> {
    if notes.is_empty() {
        return Err(VotingError::InvalidInput {
            message: "notes must not be empty".to_string(),
        });
    }
    for (i, note) in notes.iter().enumerate() {
        validate_32_bytes(&note.commitment, &format!("notes[{}].commitment", i))?;
        validate_32_bytes(&note.nullifier, &format!("notes[{}].nullifier", i))?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::governance::BALLOT_DIVISOR;
    use orchard::note::{ExtractedNoteCommitment, NoteVersion, Rho};
    use orchard::value::NoteValue;
    use rand::rngs::OsRng;
    use zcash_keys::keys::UnifiedSpendingKey;
    use zcash_protocol::consensus::TEST_NETWORK;
    use zip32::{AccountId, Scope};

    fn placeholder_tree_state(snapshot_height: u64) -> TreeState {
        TreeState {
            network: "test".to_string(),
            height: snapshot_height,
            hash: String::new(),
            time: 0,
            sapling_tree: String::new(),
            orchard_tree: String::new(),
            ironwood_tree: String::new(),
        }
    }

    #[test]
    fn vote_decision_validation_rejects_invalid_option_counts() {
        assert!(validate_vote_decision(0, MIN_VOTE_OPTIONS).is_ok());
        assert!(validate_vote_decision(MAX_VOTE_OPTIONS - 1, MAX_VOTE_OPTIONS).is_ok());

        assert!(validate_vote_decision(0, MIN_VOTE_OPTIONS - 1).is_err());
        assert!(validate_vote_decision(0, MAX_VOTE_OPTIONS + 1).is_err());
        assert!(validate_vote_decision(2, 2).is_err());
    }

    #[test]
    fn selected_notes_convert_to_voting_note_info() {
        let selected = SelectedNotes {
            notes: vec![NoteRef {
                pool: "orchard".to_string(),
                txid_hex: hex::encode([9u8; 32]),
                output_index: 2,
                value_zatoshi: 13_000_000,
                voting_weight_zatoshi: BALLOT_DIVISOR,
                commitment: vec![1; 32],
                nullifier: vec![2; 32],
                diversifier: vec![3; 11],
                rho: vec![4; 32],
                rseed: vec![5; 32],
                scope: 1,
                ufvk_str: "uviewtest".to_string(),
                commitment_tree_position: 42,
                mined_height: 100,
                anchor_height: 123,
            }],
            snapshot_height: 123,
            anchor_tree_state: placeholder_tree_state(123),
        };

        let infos = selected.voting_note_infos();

        assert_eq!(infos.len(), 1);
        assert_eq!(infos[0].value, 13_000_000);
        assert_eq!(infos[0].position, 42);
        assert_eq!(infos[0].commitment, vec![1; 32]);
        assert_eq!(infos[0].nullifier, vec![2; 32]);
        assert_eq!(infos[0].diversifier, vec![3; 11]);
        assert_eq!(infos[0].rho, vec![4; 32]);
        assert_eq!(infos[0].rseed, vec![5; 32]);
        assert_eq!(infos[0].scope, 1);
        assert_eq!(infos[0].ufvk_str, "uviewtest");
    }

    #[test]
    fn delegation_progress_bridge_forwards_clamped_proof_progress() {
        use std::sync::{Arc, Mutex};

        let seen = Arc::new(Mutex::new(Vec::new()));
        let seen_for_reporter = seen.clone();
        let reporter = DelegationProgressBridge::new(move |progress| {
            seen_for_reporter.lock().unwrap().push(progress);
        });

        reporter.on_progress(crate::delegate::DelegationProgress::PcztBuilding);
        reporter.on_progress(crate::delegate::DelegationProgress::ProofProgress(1.5));

        assert_eq!(
            *seen.lock().unwrap(),
            vec![
                crate::delegate::DelegationProgress::PcztBuilding,
                crate::delegate::DelegationProgress::ProofProgress(1.0),
            ]
        );
    }

    #[test]
    fn vote_commit_stage_bridge_forwards_clamped_proof_progress() {
        use std::sync::{Arc, Mutex};

        let seen = Arc::new(Mutex::new(Vec::new()));
        let seen_for_reporter = seen.clone();
        let reporter = VoteCommitStageBridge::new(move |stage| {
            seen_for_reporter.lock().unwrap().push(stage);
        });

        reporter.on_stage(crate::vote::VoteCommitStage::ProofStarting {
            proposal_id: 1,
            bundle_index: 2,
        });
        reporter.on_stage(crate::vote::VoteCommitStage::ProofProgress {
            proposal_id: 1,
            bundle_index: 2,
            progress: 1.5,
        });

        assert_eq!(
            *seen.lock().unwrap(),
            vec![
                crate::vote::VoteCommitStage::ProofStarting {
                    proposal_id: 1,
                    bundle_index: 2,
                },
                crate::vote::VoteCommitStage::ProofProgress {
                    proposal_id: 1,
                    bundle_index: 2,
                    progress: 1.0,
                },
            ]
        );
    }

    #[test]
    fn from_orchard_note_populates_note_info() {
        let seed = [0x42u8; 32];
        let account = AccountId::try_from(0u32).unwrap();
        let usk = UnifiedSpendingKey::from_seed(&TEST_NETWORK, &seed, account).unwrap();
        let ufvk = usk.to_unified_full_viewing_key();
        let fvk = ufvk.orchard().unwrap().clone();
        let address = fvk.address_at(0u32, Scope::External);

        let mut rng = OsRng;
        let (_, _, parent_note) = orchard::Note::dummy(&mut rng, None, NoteVersion::V2);
        let note = orchard::Note::new(
            address,
            NoteValue::from_raw(12_500_000),
            Rho::from_nf_old(parent_note.nullifier(&fvk)),
            NoteVersion::V2,
            &mut rng,
        );

        let note_info =
            NoteInfo::from_orchard_note(&note, 42, Scope::External, &ufvk, &TEST_NETWORK).unwrap();
        let commitment: ExtractedNoteCommitment = note.commitment().into();

        assert_eq!(note_info.commitment, commitment.to_bytes().to_vec());
        assert_eq!(
            note_info.nullifier,
            note.nullifier(&fvk).to_bytes().to_vec()
        );
        assert_eq!(note_info.value, 12_500_000);
        assert_eq!(note_info.position, 42);
        assert_eq!(
            note_info.diversifier,
            note.recipient().diversifier().as_array().to_vec()
        );
        assert_eq!(note_info.rho, note.rho().to_bytes().to_vec());
        assert_eq!(note_info.rseed, note.rseed().as_bytes().to_vec());
        assert_eq!(note_info.scope, 0);
        assert_eq!(note_info.ufvk_str, ufvk.encode(&TEST_NETWORK));
    }
    #[test]
    fn validate_vote_round_id_accepts_canonical_lowercase_hex() {
        assert!(validate_vote_round_id_hex(&"01".repeat(32)).is_ok());
    }

    #[test]
    fn validate_vote_round_id_rejects_non_canonical_field_encoding() {
        assert!(validate_vote_round_id_hex(&"ff".repeat(32)).is_err());
    }

    #[test]
    fn validate_vote_round_id_rejects_uppercase_hex() {
        assert!(validate_vote_round_id_hex(&"AA".repeat(32)).is_err());
    }
}

pub fn validate_encrypted_shares(shares: &[WireEncryptedShare]) -> Result<(), VotingError> {
    for (i, share) in shares.iter().enumerate() {
        validate_32_bytes(&share.c1, &format!("enc_shares[{}].c1", i))?;
        validate_32_bytes(&share.c2, &format!("enc_shares[{}].c2", i))?;
        validate_share_index(share.share_index)?;
    }
    Ok(())
}
