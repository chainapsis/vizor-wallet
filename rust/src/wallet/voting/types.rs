/// Internal progress phases for delegation PCZT build/prove/sign/broadcast.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ProofEvent {
    SelectingNotes,
    BuildingPczt,
    BuildingProof,
    SigningPczt,
    Broadcasting,
    Done { txid_hex: String },
}

/// Completed delegation bundle plus broadcast/storage status.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SignedDelegation {
    pub pczt_bytes: Vec<u8>,
    pub txid_hex: String,
    pub status: String,
    pub message: Option<String>,
    pub proof: Vec<u8>,
    pub rk: Vec<u8>,
    pub spend_auth_sig: Vec<u8>,
    pub sighash: Vec<u8>,
    pub nf_signed: Vec<u8>,
    pub cmx_new: Vec<u8>,
    pub gov_comm: Vec<u8>,
    pub gov_nullifiers: Vec<Vec<u8>>,
    pub vote_round_id: String,
    pub eligible_weight_zatoshi: u64,
    pub delegated_weight_zatoshi: u64,
    pub bundle_count: u32,
    pub bundle_index: u32,
}

/// Result of preparing bundle rows for a voting round.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BundleSetupResult {
    pub bundle_count: u32,
    pub eligible_weight_zatoshi: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DelegationPirPrecomputeResult {
    pub cached_count: u32,
    pub fetched_count: u32,
    pub bundle_count: u32,
    pub bundle_index: u32,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub(super) struct PreparedDelegationKey {
    pub(super) db_path: String,
    pub(super) account_uuid: String,
    pub(super) round_id: String,
    pub(super) bundle_index: u32,
    pub(super) hotkey_raw_address: Vec<u8>,
}
