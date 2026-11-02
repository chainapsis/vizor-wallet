//! Pure participation evidence verification, shared by the wallet and updater.
use base64::{engine::general_purpose::STANDARD as B64, Engine};
use prost13::Message;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use tendermint::{block::signed_header::SignedHeader, validator};
use tendermint_light_client_verifier::operations::{
    commit_validator::{CommitValidator, ProdCommitValidator},
    voting_power::{ProdVotingPowerCalculator, VotingPowerCalculator},
};
pub(super) const INVALID: &str = "Voting participation evidence could not be verified";
#[derive(Deserialize)]
pub(super) struct Envelope<T> {
    pub(super) result: T,
}
#[derive(Deserialize)]
pub(super) struct CommitResult {
    pub(super) signed_header: SignedHeader,
}
#[derive(Deserialize)]
pub(super) struct ValidatorsResult {
    pub(super) validators: Vec<validator::Info>,
}
#[derive(Deserialize)]
pub(super) struct QueryResult {
    pub(super) response: QueryResponse,
}
#[derive(Deserialize)]
pub(super) struct QueryResponse {
    pub(super) code: u32,
    pub(super) height: String,
    pub(super) key: Option<String>,
    pub(super) value: Option<String>,
    #[serde(rename = "proofOps")]
    pub(super) proof_ops: ProofOps,
}
#[derive(Deserialize)]
pub(super) struct ProofOps {
    pub(super) ops: Vec<ProofOp>,
}
#[derive(Deserialize)]
pub(super) struct ProofOp {
    pub(super) r#type: String,
    pub(super) key: String,
    pub(super) data: String,
}
pub(super) fn checked_validator_set(
    validators: &ValidatorsResult,
) -> Result<validator::Set, String> {
    if validators.validators.is_empty() || validators.validators.len() > 100 {
        return Err(INVALID.into());
    }
    let power = validators
        .validators
        .iter()
        .try_fold(0u64, |sum, v| sum.checked_add(v.power.value()))
        .ok_or(INVALID)?;
    if power == 0
        || validators
            .validators
            .iter()
            .any(|v| v.power.value() == 0 || v.address != tendermint::account::Id::from(v.pub_key))
        || power > (i64::MAX as u64) / 8
        || validators
            .validators
            .iter()
            .map(|v| v.address)
            .collect::<std::collections::HashSet<_>>()
            .len()
            != validators.validators.len()
    {
        return Err(INVALID.into());
    }
    Ok(validator::Set::without_proposer(
        validators.validators.clone(),
    ))
}

pub(super) fn verify_header_with_trust(
    commit: &CommitResult,
    set: &validator::Set,
    chain: &str,
    trusted: &validator::Set,
    now: i64,
) -> Result<(), String> {
    let s = &commit.signed_header;
    let h = &s.header;
    let age = now.checked_sub(h.time.unix_timestamp()).ok_or(INVALID)?;
    if h.chain_id.as_str() != chain
        || set.hash() != h.validators_hash
        || h.hash() != s.commit.block_id.hash
        || h.height != s.commit.height
        || !(-60..=600).contains(&age)
    {
        return Err(INVALID.into());
    }
    ProdCommitValidator.validate(s, set).map_err(|_| INVALID)?;
    ProdCommitValidator
        .validate_full(s, set)
        .map_err(|_| INVALID)?;
    // Each quorum uses its own voting powers. New powers cannot inflate the
    // contribution of a signer within the bundled trust anchor.
    ProdVotingPowerCalculator::default()
        .check_enough_trust_and_signers(
            s,
            trusted,
            tendermint::trust_threshold::TrustThresholdFraction::TWO_THIRDS,
            set,
        )
        .map_err(|_| INVALID)?;
    Ok(())
}

/// Hash provider for the fixed IAVL and multistore proof specifications.
///
/// Both specifications permit only SHA-256. ICS23 checks every leaf and inner
/// operation against the specification before hashing, including the neighbors
/// in non-membership proofs. Keep this provider restricted to those verification
/// entry points; it cannot calculate roots for arbitrary proof specifications.
pub(super) struct VoteStoreHashes;

impl ics23::HostFunctionsProvider for VoteStoreHashes {
    fn sha2_256(message: &[u8]) -> [u8; 32] {
        Sha256::digest(message).into()
    }

    fn sha2_512(_: &[u8]) -> [u8; 64] {
        unreachable!()
    }

    fn sha2_512_truncated(_: &[u8]) -> [u8; 32] {
        unreachable!()
    }

    fn keccak_256(_: &[u8]) -> [u8; 32] {
        unreachable!()
    }

    fn ripemd160(_: &[u8]) -> [u8; 20] {
        unreachable!()
    }

    fn blake2b_512(_: &[u8]) -> [u8; 64] {
        unreachable!()
    }

    fn blake2s_256(_: &[u8]) -> [u8; 32] {
        unreachable!()
    }

    fn blake3(_: &[u8]) -> [u8; 32] {
        unreachable!()
    }
}

pub(super) fn proof(data: &str) -> Result<ics23::CommitmentProof, String> {
    let bytes = B64.decode(data).map_err(|_| INVALID)?;
    ics23::CommitmentProof::decode(bytes.as_slice()).map_err(|_| INVALID.into())
}

pub(super) fn verify_query(
    q: &QueryResponse,
    key: &[u8],
    app_hash: &[u8],
    height: u64,
) -> Result<bool, String> {
    if q.code != 0
        || q.height.parse::<u64>().ok() != Some(height)
        || q.key.as_ref().and_then(|k| B64.decode(k).ok()).as_deref() != Some(key)
        || q.proof_ops.ops.len() != 2
    {
        return Err(INVALID.into());
    }
    let ops = &q.proof_ops.ops;
    if ops[0].r#type != "ics23:iavl"
        || ops[1].r#type != "ics23:simple"
        || B64.decode(&ops[0].key).map_err(|_| INVALID)? != key
        || B64.decode(&ops[1].key).map_err(|_| INVALID)? != b"vote"
    {
        return Err(INVALID.into());
    }
    let store = proof(&ops[1].data)?;
    let Some(ics23::commitment_proof::Proof::Exist(ex)) = &store.proof else {
        return Err(INVALID.into());
    };
    let root = ex.value.clone();
    if !ics23::verify_membership::<VoteStoreHashes>(
        &store,
        &ics23::tendermint_spec(),
        &app_hash.to_vec(),
        b"vote",
        &root,
    ) {
        return Err(INVALID.into());
    }
    let p = proof(&ops[0].data)?;
    let value = q
        .value
        .as_ref()
        .map(|v| B64.decode(v))
        .transpose()
        .map_err(|_| INVALID)?
        .unwrap_or_default();
    let valid = if value == [1] {
        ics23::verify_membership::<VoteStoreHashes>(&p, &ics23::iavl_spec(), &root, key, &[1])
    } else if value.is_empty() {
        ics23::verify_non_membership::<VoteStoreHashes>(&p, &ics23::iavl_spec(), &root, key)
    } else {
        false
    };
    if !valid {
        return Err(INVALID.into());
    }
    Ok(!value.is_empty())
}
