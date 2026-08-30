//! Compact delegation capability handoff for separately controlled funds and
//! voting hotkeys.

#[allow(unused_imports)]
pub(crate) use crate::backend::pasta_curves;
use std::collections::HashSet;

use base64::{engine::general_purpose::STANDARD as BASE64_STANDARD, Engine as _};
use pasta_curves::group::ff::PrimeField;
use pasta_curves::pallas;
use rusqlite::{named_params, OptionalExtension, TransactionBehavior};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use zcash_protocol::value::MAX_MONEY;

use crate::{
    action::derive_hotkey_x_coords_from_raw_address,
    governance::{construct_van, BALLOT_DIVISOR},
    storage::{queries, RoundPhase, VotingDb},
    types::{
        validate_round_params, validate_vote_chain_id, Network, RoundBoundVotingHotkeyTarget,
        VotingError, VotingHotkey, VotingHotkeyTarget, VotingRoundParams,
    },
    wire::VotingHotkeyTargetV1,
};

const CAPABILITY_FORMAT_VERSION: u32 = 1;

/// Maximum number of bundles in one version 1 capability.
pub const MAX_DELEGATION_CAPABILITY_BUNDLES: usize = 4_096;

/// Maximum accepted size of a canonical capability JSON document.
///
/// Network callers should enforce this while reading, before allocating the
/// complete buffer passed to [`DelegationCapabilityV1::from_json`] or
/// [`import_delegation_capability`].
pub const MAX_DELEGATION_CAPABILITY_JSON_BYTES: usize = 1_048_576;

/// One bundle in a version 1 delegation capability.
///
/// This type deliberately omits `Debug` because the blinding factor is
/// privacy-sensitive. Use [`DelegationCapabilityV1::from_json`] and
/// [`DelegationCapabilityV1::to_json`] rather than unchecked Serde decoding.
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DelegationCapabilityBundleV1 {
    /// Zero-based position in this complete batch.
    pub bundle_index: u32,
    /// Voting weight in whole ballots.
    pub num_ballots: u64,
    /// Canonical padded Base64 of the 32-byte VAN blinding factor.
    pub van_comm_rand: String,
    /// Lowercase SHA-256 of the exact signed vote-chain transaction bytes.
    pub delegation_tx_hash: String,
}

/// Canonical delegation capability handoff package.
///
/// It contains no voting hotkey secret, but it is privacy-sensitive and should
/// travel over the parties' authenticated confidential channel. This type
/// deliberately omits `Debug`.
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DelegationCapabilityV1 {
    /// Wire-format version. Version 1 requires the JSON number `1`.
    pub format_version: u32,
    /// Exact configured vote chain identifier.
    pub vote_chain_id: String,
    /// Exact lowercase Zcash network name.
    pub network: String,
    /// Canonical 32-byte round identifier as lowercase hex.
    pub vote_round_id: String,
    /// Version 1 voting hotkey address index. This must be zero.
    pub address_index: u32,
    /// Canonical padded Base64 of the 43-byte raw Orchard target.
    pub raw_orchard_address: String,
    /// Complete contiguous bundle batch in index order.
    pub bundles: Vec<DelegationCapabilityBundleV1>,
}

/// SHA-256 digest of exact canonical delegation capability bytes.
///
/// This type deliberately omits `Debug` because the digest is linkable to a
/// privacy-sensitive capability package.
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct DelegationCapabilityDigest([u8; 32]);

impl DelegationCapabilityDigest {
    fn from_package_bytes(package_bytes: &[u8]) -> Self {
        Self(Sha256::digest(package_bytes).into())
    }

    /// Returns the raw SHA-256 digest bytes.
    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }

    /// Returns the canonical lowercase hexadecimal digest.
    pub fn to_hex(&self) -> String {
        hex::encode(self.0)
    }
}

/// Canonical capability bytes and the digest computed from those exact bytes.
///
/// Export constructs both values together so callers cannot accidentally pair
/// bytes with a digest from a different serialization. This type deliberately
/// omits `Debug` because the package is privacy-sensitive.
#[derive(Clone, PartialEq, Eq)]
pub struct ExportedDelegationCapability {
    canonical_json: Vec<u8>,
    digest: DelegationCapabilityDigest,
}

impl ExportedDelegationCapability {
    fn from_capability(capability: DelegationCapabilityV1) -> Result<Self, VotingError> {
        let canonical_json = capability.to_json()?;
        let digest = DelegationCapabilityDigest::from_package_bytes(&canonical_json);
        Ok(Self {
            canonical_json,
            digest,
        })
    }

    /// Returns the exact canonical JSON bytes to store and deliver.
    pub fn canonical_json(&self) -> &[u8] {
        &self.canonical_json
    }

    /// Returns the digest of [`Self::canonical_json`].
    pub fn digest(&self) -> DelegationCapabilityDigest {
        self.digest
    }

    /// Consumes this value and returns the inseparable export results.
    pub fn into_parts(self) -> (Vec<u8>, DelegationCapabilityDigest) {
        (self.canonical_json, self.digest)
    }
}

impl DelegationCapabilityV1 {
    /// Parses exact canonical version 1 JSON.
    ///
    /// Whitespace, reordered fields, unknown or duplicate fields, and
    /// noncanonical scalar encodings are rejected so both parties hash the
    /// same bytes.
    pub fn from_json(json: &[u8]) -> Result<Self, VotingError> {
        Self::from_json_with_validation(json).map(|(capability, _)| capability)
    }

    fn from_json_with_validation(json: &[u8]) -> Result<(Self, ValidatedCapability), VotingError> {
        if json.len() > MAX_DELEGATION_CAPABILITY_JSON_BYTES {
            return Err(invalid(format!(
                "delegation capability JSON exceeds {MAX_DELEGATION_CAPABILITY_JSON_BYTES} bytes"
            )));
        }
        let capability: Self = serde_json::from_slice(json)
            .map_err(|e| invalid(format!("invalid delegation capability JSON: {e}")))?;
        let validated = capability.validate()?;
        if serde_json::to_vec(&capability).map_err(internal_serialize)? != json {
            return Err(invalid(
                "delegation capability JSON must use its exact canonical encoding",
            ));
        }
        Ok((capability, validated))
    }

    /// Returns the exact compact JSON bytes covered by the package digest.
    pub fn to_json(&self) -> Result<Vec<u8>, VotingError> {
        self.validate()?;
        serde_json::to_vec(self).map_err(internal_serialize)
    }

    fn validate(&self) -> Result<ValidatedCapability, VotingError> {
        if self.format_version != CAPABILITY_FORMAT_VERSION {
            return Err(invalid(format!(
                "format_version must be {CAPABILITY_FORMAT_VERSION}, got {}",
                self.format_version
            )));
        }
        let target_wire = VotingHotkeyTargetV1 {
            format_version: 1,
            vote_chain_id: self.vote_chain_id.clone(),
            network: self.network.clone(),
            vote_round_id: self.vote_round_id.clone(),
            address_index: self.address_index,
            raw_orchard_address: self.raw_orchard_address.clone(),
        };
        let (target, round_id) = target_wire.validated_parts()?;
        if self.bundles.is_empty() || self.bundles.len() > MAX_DELEGATION_CAPABILITY_BUNDLES {
            return Err(invalid(format!(
                "delegation capability must contain 1..={MAX_DELEGATION_CAPABILITY_BUNDLES} bundles"
            )));
        }

        let (g_d_x, pk_d_x) =
            derive_hotkey_x_coords_from_raw_address(target.raw_orchard_address())?;
        let mut tx_hashes = HashSet::with_capacity(self.bundles.len());
        let mut van_commitments = HashSet::with_capacity(self.bundles.len());
        let mut bundles = Vec::with_capacity(self.bundles.len());
        let mut batch_total = 0u64;
        for (expected_index, bundle) in self.bundles.iter().enumerate() {
            if bundle.bundle_index != expected_index as u32 {
                return Err(invalid(format!(
                    "bundle indices must be contiguous from zero; expected {expected_index}, got {}",
                    bundle.bundle_index
                )));
            }
            let total_note_value = canonical_total(bundle.num_ballots)?;
            batch_total = batch_total
                .checked_add(total_note_value)
                .filter(|total| *total <= MAX_MONEY)
                .ok_or_else(|| invalid("capability voting weight exceeds MAX_MONEY"))?;
            let van_comm_rand = decode_field(&bundle.van_comm_rand)?;
            let tx_hash = decode_hash(&bundle.delegation_tx_hash)?;
            if !tx_hashes.insert(tx_hash) {
                return Err(invalid("delegation transaction hashes must be unique"));
            }
            let van_comm: [u8; 32] =
                construct_van(&g_d_x, &pk_d_x, total_note_value, &round_id, &van_comm_rand)?
                    .try_into()
                    .expect("construct_van returns 32 bytes");
            if !van_commitments.insert(van_comm) {
                return Err(invalid("delegation VAN commitments must be unique"));
            }
            bundles.push(ValidatedBundle {
                index: bundle.bundle_index,
                total_note_value,
                rand: van_comm_rand,
                van: van_comm,
                tx_hash: bundle.delegation_tx_hash.clone(),
            });
        }
        Ok(ValidatedCapability { target, bundles })
    }
}

/// Independently trusted voter context for capability import.
pub struct ImportDelegationCapabilityParams<'a> {
    /// Voter-owned hotkey; its secret never enters the package.
    pub voting_hotkey: &'a VotingHotkey,
    /// Vote chain identifier obtained independently of the package.
    pub expected_chain_id: &'a str,
    /// Zcash network obtained independently of the package.
    pub expected_network: Network,
    /// Full authenticated round context obtained independently of the package.
    pub expected_round_params: &'a VotingRoundParams,
    /// Used only if the importer creates the round row.
    pub session_json: Option<&'a str>,
}

struct ValidatedCapability {
    target: VotingHotkeyTarget,
    bundles: Vec<ValidatedBundle>,
}

struct ValidatedBundle {
    index: u32,
    total_note_value: u64,
    rand: [u8; 32],
    van: [u8; 32],
    tx_hash: String,
}

/// Exports a capability from completed funds controller delegation state.
///
/// `signed_delegation_txs` must contain the exact transactions in bundle order.
/// Before broadcasting, the funds controller must durably store the target,
/// transaction bytes, package bytes, and digest, and retain them through round
/// close. It may deliver the package while broadcasting; the voter's matching
/// digest is a delivery receipt rather than a broadcast prerequisite. Supplying
/// the wrong target after a restart fails because it cannot reproduce the
/// persisted VAN commitments.
pub fn export_delegation_capability(
    db: &VotingDb,
    voting_target: &RoundBoundVotingHotkeyTarget,
    signed_delegation_txs: &[Vec<u8>],
) -> Result<ExportedDelegationCapability, VotingError> {
    let conn = db.conn();
    let wallet_id = db.wallet_id();
    let round_id = hex::encode(voting_target.vote_round_id());
    let (params, network) = queries::load_round_params_with_network(&conn, &round_id, &wallet_id)?;
    validate_round_params(&params).map_err(|e| VotingError::Internal {
        message: format!("stored round parameters are invalid: {e}"),
    })?;
    if network != voting_target.target().network() || params.vote_round_id != round_id {
        return Err(invalid(
            "voting target does not match the stored delegation round",
        ));
    }

    let rows = provider_bundles(&conn, &round_id, &wallet_id)?;
    if rows.is_empty() || rows.len() > MAX_DELEGATION_CAPABILITY_BUNDLES {
        return Err(invalid("delegation job has an invalid bundle count"));
    }
    if signed_delegation_txs.len() != rows.len() {
        return Err(invalid(format!(
            "signed transaction count {} does not match bundle count {}",
            signed_delegation_txs.len(),
            rows.len()
        )));
    }

    let target = voting_target.target();
    let (g_d_x, pk_d_x) = derive_hotkey_x_coords_from_raw_address(target.raw_orchard_address())?;
    let mut bundles = Vec::with_capacity(rows.len());
    let mut tx_hashes = HashSet::with_capacity(rows.len());
    let mut vans = HashSet::with_capacity(rows.len());
    let mut batch_total = 0u64;
    for (expected_index, (row, raw_tx)) in rows.into_iter().zip(signed_delegation_txs).enumerate() {
        let (index, rand, stored_van, total, address_index, stored_hash) = row;
        if index != expected_index as u32 {
            return Err(VotingError::Internal {
                message: "stored delegation bundle indices are not contiguous".to_string(),
            });
        }
        if address_index != target.address_index() || raw_tx.is_empty() {
            return Err(invalid("delegation target or transaction is invalid"));
        }
        if total > MAX_MONEY {
            return Err(internal(
                "stored delegation voting weight exceeds MAX_MONEY",
            ));
        }
        batch_total = batch_total
            .checked_add(total)
            .filter(|total| *total <= MAX_MONEY)
            .ok_or_else(|| internal("stored delegation batch weight exceeds MAX_MONEY"))?;
        let num_ballots = total / BALLOT_DIVISOR;
        let canonical_total = canonical_total(num_ballots)?;
        let expected_van: [u8; 32] = construct_van(
            &g_d_x,
            &pk_d_x,
            canonical_total,
            voting_target.vote_round_id(),
            &rand,
        )?
        .try_into()
        .expect("construct_van returns 32 bytes");
        if expected_van != stored_van || !vans.insert(expected_van) {
            return Err(invalid(
                "voting target does not match the persisted delegation commitment",
            ));
        }
        let tx_hash = hex::encode(Sha256::digest(raw_tx));
        if !tx_hashes.insert(tx_hash.clone())
            || stored_hash.as_deref().is_some_and(|hash| hash != tx_hash)
        {
            return Err(invalid("signed delegation transaction hash conflict"));
        }
        bundles.push(DelegationCapabilityBundleV1 {
            bundle_index: index,
            num_ballots,
            van_comm_rand: BASE64_STANDARD.encode(rand),
            delegation_tx_hash: tx_hash,
        });
    }

    let capability = DelegationCapabilityV1 {
        format_version: CAPABILITY_FORMAT_VERSION,
        vote_chain_id: voting_target.vote_chain_id().to_string(),
        network: queries::network_to_storage(network).to_string(),
        vote_round_id: round_id,
        address_index: target.address_index(),
        raw_orchard_address: BASE64_STANDARD.encode(target.raw_orchard_address()),
        bundles,
    };
    ExportedDelegationCapability::from_capability(capability)
}

/// Atomically imports a complete capability into the existing voting schema.
///
/// Missing round and bundle rows commit together. Exact re-import is a no-op,
/// including after confirmation advances VAN positions. Any partial,
/// locally-constructed, or conflicting bundle state is rejected. `capability_json`
/// must use the exact canonical encoding, and the returned lowercase digest
/// acknowledges those delivered bytes to the funds controller.
pub fn import_delegation_capability(
    db: &VotingDb,
    capability_json: &[u8],
    context: ImportDelegationCapabilityParams<'_>,
) -> Result<DelegationCapabilityDigest, VotingError> {
    validate_vote_chain_id(context.expected_chain_id)?;
    validate_round_params(context.expected_round_params)?;
    i64::try_from(context.expected_round_params.snapshot_height)
        .map_err(|_| invalid("snapshot_height does not fit in SQLite INTEGER"))?;
    let (capability, validated) =
        DelegationCapabilityV1::from_json_with_validation(capability_json)?;
    if capability.vote_chain_id != context.expected_chain_id
        || capability.vote_round_id != context.expected_round_params.vote_round_id
        || validated.target.network() != context.expected_network
        || context.voting_hotkey.network() != context.expected_network
        || validated.target != context.voting_hotkey.delegation_target()
    {
        return Err(invalid(
            "delegation capability does not match the trusted voter context",
        ));
    }

    let digest = DelegationCapabilityDigest::from_package_bytes(capability_json);
    let wallet_id = db.wallet_id();
    let mut conn = db.conn();
    let tx = conn
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|e| VotingError::Internal {
            message: format!("begin delegation capability import failed: {e}"),
        })?;
    if queries::has_round(&tx, &capability.vote_round_id, &wallet_id)? {
        let (stored, network) =
            queries::load_round_params_with_network(&tx, &capability.vote_round_id, &wallet_id)?;
        if stored != *context.expected_round_params || network != context.expected_network {
            return Err(invalid(
                "stored round context conflicts with the capability",
            ));
        }
    } else {
        queries::insert_round(
            &tx,
            &wallet_id,
            context.expected_network,
            context.expected_round_params,
            context.session_json,
        )?;
    }

    let stored_count = queries::get_bundle_count(&tx, &capability.vote_round_id, &wallet_id)?;
    if stored_count == 0 {
        for bundle in &validated.bundles {
            insert_bundle(&tx, &capability.vote_round_id, &wallet_id, bundle)?;
        }
    } else if stored_count == validated.bundles.len() as u32 {
        for bundle in &validated.bundles {
            if !bundle_matches(&tx, &capability.vote_round_id, &wallet_id, bundle)? {
                return Err(invalid("stored bundle state conflicts with the capability"));
            }
        }
    } else {
        return Err(invalid(
            "stored bundle count conflicts with the complete capability",
        ));
    }
    tx.execute(
        "UPDATE rounds SET phase = :phase
         WHERE round_id = :round_id AND wallet_id = :wallet_id AND phase < :phase",
        named_params! {
            ":phase": RoundPhase::DelegationProved as i32,
            ":round_id": capability.vote_round_id,
            ":wallet_id": wallet_id,
        },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("advance imported round phase failed: {e}"),
    })?;
    tx.commit().map_err(|e| VotingError::Internal {
        message: format!("commit delegation capability import failed: {e}"),
    })?;
    Ok(digest)
}

type ProviderBundleRow = (u32, [u8; 32], [u8; 32], u64, u32, Option<String>);

fn provider_bundles(
    conn: &rusqlite::Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<Vec<ProviderBundleRow>, VotingError> {
    let total_count = queries::get_bundle_count(conn, round_id, wallet_id)? as usize;
    let mut stmt = conn
        .prepare(
            "SELECT b.bundle_index, b.van_comm_rand, b.gov_comm,
                    b.total_note_value, b.address_index, b.delegation_tx_hash
             FROM bundles b
             WHERE b.round_id = :round_id AND b.wallet_id = :wallet_id
               AND b.note_positions_blob IS NOT NULL
               AND b.van_comm_rand IS NOT NULL AND b.gov_comm IS NOT NULL
               AND b.total_note_value IS NOT NULL AND b.address_index IS NOT NULL
               AND EXISTS (
                   SELECT 1 FROM proofs p
                   WHERE p.round_id = b.round_id AND p.wallet_id = b.wallet_id
                     AND p.bundle_index = b.bundle_index
                     AND p.success = 1 AND p.proof IS NOT NULL
               )
             ORDER BY b.bundle_index",
        )
        .map_err(|e| internal(format!("prepare provider capability query failed: {e}")))?;
    let rows = stmt
        .query_map(
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, Vec<u8>>(1)?,
                    row.get::<_, Vec<u8>>(2)?,
                    row.get::<_, i64>(3)?,
                    row.get::<_, i64>(4)?,
                    row.get::<_, Option<String>>(5)?,
                ))
            },
        )
        .map_err(|e| internal(format!("query provider capability bundles failed: {e}")))?;
    let raw = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| internal(format!("read provider capability bundles failed: {e}")))?;
    if raw.len() != total_count {
        return Err(invalid(
            "delegation bundles must be locally prepared and proven",
        ));
    }
    raw.into_iter()
        .map(|(index, rand, van, total, address_index, hash)| {
            let rand = array32(rand, "van_comm_rand")?;
            let van = array32(van, "gov_comm")?;
            if pallas::Base::from_repr(rand).is_none().into()
                || pallas::Base::from_repr(van).is_none().into()
            {
                return Err(internal(
                    "stored delegation commitment data is not canonical",
                ));
            }
            Ok((
                u32::try_from(index).map_err(|_| internal("stored bundle index is invalid"))?,
                rand,
                van,
                u64::try_from(total).map_err(|_| internal("stored voting weight is invalid"))?,
                u32::try_from(address_index)
                    .map_err(|_| internal("stored address index is invalid"))?,
                hash,
            ))
        })
        .collect()
}

fn insert_bundle(
    conn: &rusqlite::Connection,
    round_id: &str,
    wallet_id: &str,
    bundle: &ValidatedBundle,
) -> Result<(), VotingError> {
    conn.execute(
        "INSERT INTO bundles (
             round_id, wallet_id, bundle_index, van_comm_rand, gov_comm,
             total_note_value, address_index, delegation_tx_hash
         ) VALUES (:round_id, :wallet_id, :bundle_index, :rand, :van,
                   :total, 0, :tx_hash)",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": i64::from(bundle.index),
            ":rand": bundle.rand,
            ":van": bundle.van,
            ":total": bundle.total_note_value as i64,
            ":tx_hash": bundle.tx_hash,
        },
    )
    .map_err(|e| internal(format!("insert delegation capability bundle failed: {e}")))?;
    Ok(())
}

fn bundle_matches(
    conn: &rusqlite::Connection,
    round_id: &str,
    wallet_id: &str,
    bundle: &ValidatedBundle,
) -> Result<bool, VotingError> {
    conn.query_row(
        "SELECT COALESCE(b.note_positions_blob IS NULL
                AND b.note_identity_hashes_blob IS NULL
                AND b.dummy_nullifiers IS NULL AND b.rho_signed IS NULL
                AND b.padded_note_data IS NULL AND b.nf_signed IS NULL
                AND b.cmx_new IS NULL AND b.alpha IS NULL
                AND b.rseed_signed IS NULL AND b.rseed_output IS NULL
                AND b.rk IS NULL AND b.gov_nullifiers_blob IS NULL
                AND b.padded_note_secrets IS NULL AND b.pczt_sighash IS NULL
                AND b.tx1_effects IS NULL
                AND b.van_comm_rand = :rand AND b.gov_comm = :van
                AND b.total_note_value = :total AND b.address_index = 0
                AND b.delegation_tx_hash = :tx_hash
                AND NOT EXISTS (
                    SELECT 1 FROM proofs p
                    WHERE p.round_id = b.round_id AND p.wallet_id = b.wallet_id
                      AND p.bundle_index = b.bundle_index
                ), 0)
         FROM bundles b
         WHERE b.round_id = :round_id AND b.wallet_id = :wallet_id
           AND b.bundle_index = :bundle_index",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": i64::from(bundle.index),
            ":rand": bundle.rand,
            ":van": bundle.van,
            ":total": bundle.total_note_value as i64,
            ":tx_hash": bundle.tx_hash,
        },
        |row| row.get::<_, i64>(0).map(|value| value == 1),
    )
    .optional()
    .map(|value| value.unwrap_or(false))
    .map_err(|e| internal(format!("validate imported capability bundle failed: {e}")))
}

fn canonical_total(num_ballots: u64) -> Result<u64, VotingError> {
    num_ballots
        .checked_mul(BALLOT_DIVISOR)
        .filter(|total| num_ballots > 0 && *total <= MAX_MONEY)
        .ok_or_else(|| invalid("num_ballots exceeds the supported voting weight"))
}

fn decode_field(value: &str) -> Result<[u8; 32], VotingError> {
    let decoded = BASE64_STANDARD
        .decode(value)
        .map_err(|_| invalid("van_comm_rand must be canonical padded standard Base64"))?;
    if value.len() != 44 || !value.ends_with('=') || BASE64_STANDARD.encode(&decoded) != value {
        return Err(invalid(
            "van_comm_rand must be canonical padded standard Base64",
        ));
    }
    let bytes: [u8; 32] = decoded
        .try_into()
        .map_err(|_| invalid("van_comm_rand must decode to 32 bytes"))?;
    if pallas::Base::from_repr(bytes).is_none().into() {
        return Err(invalid(
            "van_comm_rand must be a canonical Pallas field element",
        ));
    }
    Ok(bytes)
}

fn decode_hash(value: &str) -> Result<[u8; 32], VotingError> {
    let decoded = hex::decode(value)
        .map_err(|_| invalid("delegation_tx_hash must be 64 lowercase hex characters"))?;
    if decoded.len() != 32 || hex::encode(&decoded) != value {
        return Err(invalid(
            "delegation_tx_hash must be 64 lowercase hex characters",
        ));
    }
    Ok(decoded.try_into().expect("validated hash has 32 bytes"))
}

fn array32(value: Vec<u8>, field: &str) -> Result<[u8; 32], VotingError> {
    let len = value.len();
    value.try_into().map_err(|_| {
        internal(format!(
            "stored delegation {field} must be 32 bytes, got {len}"
        ))
    })
}

fn invalid(message: impl Into<String>) -> VotingError {
    VotingError::InvalidInput {
        message: message.into(),
    }
}

fn internal(message: impl Into<String>) -> VotingError {
    VotingError::Internal {
        message: message.into(),
    }
}

fn internal_serialize(error: serde_json::Error) -> VotingError {
    internal(format!(
        "serialize delegation capability JSON failed: {error}"
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use pasta_curves::group::{Group, GroupEncoding};
    use rusqlite::params;
    use std::path::PathBuf;

    const WALLET: &str = "capability-wallet";
    const CHAIN_ID: &str = "vote-chain-1";

    fn round_params() -> VotingRoundParams {
        VotingRoundParams {
            vote_round_id: hex::encode(pallas::Base::from(7).to_repr()),
            snapshot_height: 100,
            ea_pk: pallas::Point::generator().to_bytes().to_vec(),
            nc_root: vec![0xAA; 32],
            nullifier_imt_root: vec![0xBB; 32],
        }
    }

    fn hotkey(byte: u8) -> VotingHotkey {
        VotingHotkey::from_stored_secret(&[byte; 64], Network::Regtest).unwrap()
    }

    fn bound_target(
        hotkey: &VotingHotkey,
        params: &VotingRoundParams,
    ) -> RoundBoundVotingHotkeyTarget {
        VotingHotkeyTargetV1 {
            format_version: 1,
            vote_chain_id: CHAIN_ID.to_string(),
            network: "regtest".to_string(),
            vote_round_id: params.vote_round_id.clone(),
            address_index: 0,
            raw_orchard_address: BASE64_STANDARD.encode(hotkey.raw_orchard_address()),
        }
        .validate_for(CHAIN_ID, Network::Regtest, params)
        .unwrap()
    }

    fn test_db(path: &str) -> VotingDb {
        let db = VotingDb::open(path).unwrap();
        db.set_wallet_id(WALLET);
        db
    }

    fn seed_provider(
        db: &VotingDb,
        params: &VotingRoundParams,
        targets: &[&RoundBoundVotingHotkeyTarget],
    ) {
        db.init_round(Network::Regtest, params, None).unwrap();
        let conn = db.conn();
        for (index, target) in targets.iter().enumerate() {
            queries::insert_bundle(
                &conn,
                &params.vote_round_id,
                WALLET,
                index as u32,
                &[index as u64],
            )
            .unwrap();
            let rand = pallas::Base::from(index as u64 + 11).to_repr();
            let (g_d_x, pk_d_x) =
                derive_hotkey_x_coords_from_raw_address(target.target().raw_orchard_address())
                    .unwrap();
            let total = (index as u64 + 2) * BALLOT_DIVISOR + 7;
            let van = construct_van(&g_d_x, &pk_d_x, total, target.vote_round_id(), &rand).unwrap();
            conn.execute(
                "UPDATE bundles SET van_comm_rand=?1, gov_comm=?2,
                 total_note_value=?3, address_index=0
                 WHERE round_id=?4 AND wallet_id=?5 AND bundle_index=?6",
                params![
                    rand.as_slice(),
                    van,
                    total as i64,
                    params.vote_round_id,
                    WALLET,
                    index as i64
                ],
            )
            .unwrap();
            queries::store_proof(&conn, &params.vote_round_id, WALLET, index as u32, &[0xAC])
                .unwrap();
        }
    }

    fn exported_fixture() -> (
        VotingDb,
        VotingRoundParams,
        VotingHotkey,
        DelegationCapabilityV1,
    ) {
        let params = round_params();
        let hotkey = hotkey(0x21);
        let target = bound_target(&hotkey, &params);
        let db = test_db(":memory:");
        seed_provider(&db, &params, &[&target, &target]);
        let exported =
            export_delegation_capability(&db, &target, &[b"tx-zero".to_vec(), b"tx-one".to_vec()])
                .unwrap();
        let capability = DelegationCapabilityV1::from_json(exported.canonical_json()).unwrap();
        (db, params, hotkey, capability)
    }

    fn import_context<'a>(
        hotkey: &'a VotingHotkey,
        params: &'a VotingRoundParams,
    ) -> ImportDelegationCapabilityParams<'a> {
        ImportDelegationCapabilityParams {
            voting_hotkey: hotkey,
            expected_chain_id: CHAIN_ID,
            expected_network: Network::Regtest,
            expected_round_params: params,
            session_json: Some("{\"round\":1}"),
        }
    }

    fn import_capability(
        db: &VotingDb,
        capability: &DelegationCapabilityV1,
        context: ImportDelegationCapabilityParams<'_>,
    ) -> Result<DelegationCapabilityDigest, VotingError> {
        import_delegation_capability(db, &capability.to_json()?, context)
    }

    fn temp_db_path(label: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "zcash-voting-{label}-{}-{}.sqlite",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ))
    }

    #[test]
    fn provider_export_survives_reopen_and_rejects_wrong_or_mixed_targets() {
        let path = temp_db_path("capability-provider");
        let params = round_params();
        let hotkey_a = hotkey(0x21);
        let hotkey_b = hotkey(0x31);
        let target_a = bound_target(&hotkey_a, &params);
        let target_b = bound_target(&hotkey_b, &params);
        let raw_txs = [b"tx-zero".to_vec(), b"tx-one".to_vec()];
        {
            let db = test_db(path.to_str().unwrap());
            seed_provider(&db, &params, &[&target_a, &target_a]);
        }

        let db = test_db(path.to_str().unwrap());
        let first = export_delegation_capability(&db, &target_a, &raw_txs).unwrap();
        let second = export_delegation_capability(&db, &target_a, &raw_txs).unwrap();
        assert_eq!(first.canonical_json(), second.canonical_json());
        assert!(first.digest() == second.digest());
        assert!(
            first.digest()
                == DelegationCapabilityDigest::from_package_bytes(first.canonical_json())
        );
        assert_eq!(first.digest().to_hex().len(), 64);
        let first_capability = DelegationCapabilityV1::from_json(first.canonical_json()).unwrap();
        assert_eq!(first_capability.bundles[0].num_ballots, 2);
        assert_eq!(first_capability.bundles[1].num_ballots, 3);
        assert_eq!(
            first_capability.bundles[0].delegation_tx_hash,
            hex::encode(Sha256::digest(&raw_txs[0]))
        );
        assert!(export_delegation_capability(&db, &target_a, &raw_txs[..1]).is_err());
        assert!(export_delegation_capability(
            &db,
            &target_a,
            &[raw_txs[0].clone(), raw_txs[0].clone()]
        )
        .is_err());
        assert!(export_delegation_capability(&db, &target_b, &raw_txs).is_err());

        let rand = pallas::Base::from(12).to_repr();
        let (g_d_x, pk_d_x) =
            derive_hotkey_x_coords_from_raw_address(target_b.target().raw_orchard_address())
                .unwrap();
        let mixed_van = construct_van(
            &g_d_x,
            &pk_d_x,
            3 * BALLOT_DIVISOR,
            target_b.vote_round_id(),
            &rand,
        )
        .unwrap();
        db.conn()
            .execute(
                "UPDATE bundles SET gov_comm=?1 WHERE round_id=?2 AND wallet_id=?3 AND bundle_index=1",
                params![mixed_van, params.vote_round_id, WALLET],
            )
            .unwrap();
        assert!(export_delegation_capability(&db, &target_a, &raw_txs).is_err());

        drop(db);
        std::fs::remove_file(path).ok();
    }

    #[test]
    fn canonical_codec_rejects_malleable_or_incomplete_packages() {
        let (_, params, hotkey, capability) = exported_fixture();
        let json = capability.to_json().unwrap();
        assert!(DelegationCapabilityV1::from_json(&json).unwrap() == capability);

        let noncanonical = [json.as_slice(), b" "].concat();
        assert!(DelegationCapabilityV1::from_json(&noncanonical).is_err());
        let customer = test_db(":memory:");
        assert!(import_delegation_capability(
            &customer,
            &noncanonical,
            import_context(&hotkey, &params),
        )
        .is_err());
        assert!(!customer.has_round(&params.vote_round_id).unwrap());
        let text = String::from_utf8(json).unwrap();
        let unknown = text.replacen("{", "{\"extra\":true,", 1);
        assert!(DelegationCapabilityV1::from_json(unknown.as_bytes()).is_err());
        let duplicate = text.replacen("{", "{\"format_version\":1,", 1);
        assert!(DelegationCapabilityV1::from_json(duplicate.as_bytes()).is_err());
        assert!(DelegationCapabilityV1::from_json(&vec![
            b' ';
            MAX_DELEGATION_CAPABILITY_JSON_BYTES + 1
        ])
        .is_err());

        let mut invalid = capability.clone();
        invalid.bundles.clear();
        assert!(invalid.to_json().is_err());
        let mut invalid = capability.clone();
        invalid.bundles[1].bundle_index = 2;
        assert!(invalid.to_json().is_err());
        let mut invalid = capability.clone();
        invalid.bundles[1].delegation_tx_hash = invalid.bundles[0].delegation_tx_hash.clone();
        assert!(invalid.to_json().is_err());
        let mut invalid = capability.clone();
        invalid.bundles[1].van_comm_rand = invalid.bundles[0].van_comm_rand.clone();
        invalid.bundles[1].num_ballots = invalid.bundles[0].num_ballots;
        assert!(invalid.to_json().is_err());
        let mut invalid = capability.clone();
        invalid.bundles[0].num_ballots = 0;
        assert!(invalid.to_json().is_err());
        let mut invalid = capability.clone();
        invalid.bundles[0].num_ballots = MAX_MONEY / BALLOT_DIVISOR + 1;
        assert!(invalid.to_json().is_err());
        let mut invalid = capability.clone();
        invalid.bundles[0].van_comm_rand = "AA==".to_string();
        assert!(invalid.to_json().is_err());
        let mut invalid = capability.clone();
        invalid.bundles = vec![invalid.bundles[0].clone(); MAX_DELEGATION_CAPABILITY_BUNDLES + 1];
        assert!(invalid.to_json().is_err());
        let mut invalid = capability;
        invalid.bundles[0].delegation_tx_hash = "AA".repeat(32);
        assert!(invalid.to_json().is_err());
    }

    #[test]
    fn import_is_atomic_idempotent_and_uses_the_existing_schema() {
        let (_, params, hotkey, capability) = exported_fixture();
        let capability_json = capability.to_json().unwrap();
        let path = temp_db_path("capability-customer");
        let customer = test_db(path.to_str().unwrap());
        let digest = import_delegation_capability(
            &customer,
            &capability_json,
            import_context(&hotkey, &params),
        )
        .unwrap();
        assert!(digest == DelegationCapabilityDigest::from_package_bytes(&capability_json));
        assert_eq!(
            digest.to_hex(),
            hex::encode(Sha256::digest(&capability_json))
        );
        assert_eq!(customer.get_bundle_count(&params.vote_round_id).unwrap(), 2);
        let conn = customer.conn();
        let version: u32 = conn
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .unwrap();
        assert_eq!(version, 16);
        for index in 0..2 {
            let data =
                queries::load_zkp2_inputs(&conn, &params.vote_round_id, WALLET, index).unwrap();
            assert_eq!(
                data.total_note_value,
                (u64::from(index) + 2) * BALLOT_DIVISOR
            );
            assert_eq!(data.address_index, 0);
        }
        queries::store_van_position(&conn, &params.vote_round_id, WALLET, 0, 42).unwrap();
        queries::store_van_position(&conn, &params.vote_round_id, WALLET, 1, 43).unwrap();
        assert!(
            queries::get_round_state(&conn, &params.vote_round_id, WALLET)
                .unwrap()
                .proof_generated
        );
        drop(conn);
        drop(customer);

        let customer = test_db(path.to_str().unwrap());
        assert!(
            import_delegation_capability(
                &customer,
                &capability_json,
                import_context(&hotkey, &params),
            )
            .unwrap()
                == digest
        );
        assert_eq!(
            queries::load_van_position(&customer.conn(), &params.vote_round_id, WALLET, 0).unwrap(),
            42
        );
        assert_eq!(
            queries::load_van_position(&customer.conn(), &params.vote_round_id, WALLET, 1).unwrap(),
            43
        );

        let mut conflicting = capability.clone();
        conflicting.bundles[0].delegation_tx_hash = "11".repeat(32);
        assert!(
            import_capability(&customer, &conflicting, import_context(&hotkey, &params),).is_err()
        );
        assert_eq!(
            queries::get_delegation_tx_hash(&customer.conn(), &params.vote_round_id, WALLET, 0)
                .unwrap(),
            Some(capability.bundles[0].delegation_tx_hash.clone())
        );
        drop(customer);
        std::fs::remove_file(path).ok();
    }

    #[test]
    fn imported_capability_survives_recovery_and_session_reset() {
        let (_, params, hotkey, capability) = exported_fixture();
        let capability_json = capability.to_json().unwrap();
        let customer = test_db(":memory:");
        let digest = import_delegation_capability(
            &customer,
            &capability_json,
            import_context(&hotkey, &params),
        )
        .unwrap();
        let validated = capability.validate().unwrap();

        crate::recovery::clear(&customer, &params.vote_round_id).unwrap();
        crate::precompute::reset_voting_session_state(&customer, &params.vote_round_id).unwrap();

        let conn = customer.conn();
        for bundle in &validated.bundles {
            assert!(
                bundle_matches(&conn, &params.vote_round_id, WALLET, bundle).unwrap(),
                "imported bundle {} changed during cleanup",
                bundle.index
            );
        }
        drop(conn);
        assert!(
            import_delegation_capability(
                &customer,
                &capability_json,
                import_context(&hotkey, &params),
            )
            .unwrap()
                == digest
        );
    }

    #[test]
    fn import_rejects_context_and_local_state_without_writes() {
        let (_, params, customer_hotkey, capability) = exported_fixture();
        let wrong_hotkey = hotkey(0x44);
        let customer = test_db(":memory:");
        assert!(import_capability(
            &customer,
            &capability,
            import_context(&wrong_hotkey, &params),
        )
        .is_err());
        assert!(!customer.has_round(&params.vote_round_id).unwrap());

        customer
            .init_round(Network::Regtest, &params, None)
            .unwrap();
        queries::insert_bundle(&customer.conn(), &params.vote_round_id, WALLET, 0, &[9]).unwrap();
        assert!(import_capability(
            &customer,
            &capability,
            import_context(&customer_hotkey, &params),
        )
        .is_err());
        assert_eq!(customer.get_bundle_count(&params.vote_round_id).unwrap(), 1);
        assert_eq!(
            queries::load_bundle_note_positions(&customer.conn(), &params.vote_round_id, WALLET, 0)
                .unwrap(),
            vec![9]
        );

        let conflicting_round = test_db(":memory:");
        let mut stored_params = params.clone();
        stored_params.nc_root[0] ^= 1;
        conflicting_round
            .init_round(Network::Regtest, &stored_params, None)
            .unwrap();
        assert!(import_capability(
            &conflicting_round,
            &capability,
            import_context(&customer_hotkey, &params),
        )
        .is_err());
        assert_eq!(
            conflicting_round
                .get_bundle_count(&params.vote_round_id)
                .unwrap(),
            0
        );
    }

    #[test]
    fn late_bundle_insert_failure_rolls_back_the_round_and_batch() {
        let (_, params, hotkey, capability) = exported_fixture();
        let customer = test_db(":memory:");
        customer
            .conn()
            .execute_batch(
                "CREATE TRIGGER fail_second_capability_bundle
                 BEFORE INSERT ON bundles WHEN NEW.bundle_index = 1
                 BEGIN SELECT RAISE(ABORT, 'injected import failure'); END;",
            )
            .unwrap();

        assert!(
            import_capability(&customer, &capability, import_context(&hotkey, &params),).is_err()
        );
        assert!(!customer.has_round(&params.vote_round_id).unwrap());
    }

    #[test]
    fn confirmation_must_match_the_transaction_hash_in_the_package() {
        use crate::confirmation::{confirm_delegation_submission, TxEvent, TxEventAttribute};

        let (_, params, hotkey, capability) = exported_fixture();
        let customer = test_db(":memory:");
        import_capability(&customer, &capability, import_context(&hotkey, &params)).unwrap();
        let events = [TxEvent {
            event_type: "delegate_vote".to_string(),
            attributes: vec![
                TxEventAttribute {
                    key: "vote_round_id".to_string(),
                    value: params.vote_round_id.clone(),
                },
                TxEventAttribute {
                    key: "leaf_index".to_string(),
                    value: "0".to_string(),
                },
            ],
        }];

        let error = confirm_delegation_submission(
            &customer,
            &params.vote_round_id,
            0,
            &"ff".repeat(32),
            &events,
        )
        .expect_err("confirmation must bind the exact signed transaction");
        assert!(
            error.to_string().contains("delegation tx_hash conflict"),
            "{error}"
        );
        assert!(
            queries::load_van_position(&customer.conn(), &params.vote_round_id, WALLET, 0).is_err()
        );
    }

    #[test]
    fn imported_capability_blocks_fresh_votes_until_every_delegation_confirms() {
        use crate::{
            types::NoopProgressReporter,
            vote::{DraftVote, VanWitness, VoteSigner},
        };

        let (provider, params, hotkey, capability) = exported_fixture();
        provider
            .require_capability_delegations_confirmed(&params.vote_round_id)
            .expect("locally prepared rounds retain per-bundle voting");

        let customer = test_db(":memory:");
        import_capability(&customer, &capability, import_context(&hotkey, &params)).unwrap();
        queries::store_van_position(&customer.conn(), &params.vote_round_id, WALLET, 0, 42)
            .unwrap();

        let commit = || {
            crate::vote::commit(
                &customer,
                &params.vote_round_id,
                0,
                &DraftVote {
                    proposal_id: 1,
                    choice: 0,
                    num_options: 2,
                    single_share: true,
                    vc_tree_position: 0,
                },
                &VanWitness {
                    auth_path: Vec::new(),
                    position: 42,
                    anchor_height: 100,
                },
                VoteSigner::hotkey(&hotkey),
                &NoopProgressReporter,
            )
        };

        let blocked = commit().expect_err("the second imported bundle is unconfirmed");
        assert!(
            blocked.to_string().contains(
                "cannot create votes until every delegation is confirmed; bundle 1 is still unconfirmed"
            ),
            "{blocked}"
        );
        assert!(customer
            .get_votes(&params.vote_round_id)
            .unwrap()
            .is_empty());

        queries::store_van_position(&customer.conn(), &params.vote_round_id, WALLET, 1, 43)
            .unwrap();
        let unblocked = commit().expect_err("the intentionally empty witness remains invalid");
        assert!(unblocked.to_string().contains("24 siblings"), "{unblocked}");
        assert!(customer
            .get_votes(&params.vote_round_id)
            .unwrap()
            .is_empty());
    }

    fn assert_imported_capability_rejects_bundle_trim(keep_count: u32) {
        let (_, params, hotkey, capability) = exported_fixture();
        let customer = test_db(":memory:");
        let digest =
            import_capability(&customer, &capability, import_context(&hotkey, &params)).unwrap();
        queries::store_van_position(&customer.conn(), &params.vote_round_id, WALLET, 0, 42)
            .unwrap();

        let error = customer
            .delete_skipped_bundles(&params.vote_round_id, keep_count)
            .expect_err("imported capability batches must remain complete");
        assert!(matches!(&error, VotingError::InvalidInput { .. }));
        assert!(
            error
                .to_string()
                .contains("cannot delete bundles independently"),
            "{error}"
        );
        assert_eq!(customer.get_bundle_count(&params.vote_round_id).unwrap(), 2);
        assert_eq!(
            queries::load_van_position(&customer.conn(), &params.vote_round_id, WALLET, 0).unwrap(),
            42
        );
        let blocked = customer
            .require_capability_delegations_confirmed(&params.vote_round_id)
            .expect_err("the second imported bundle must remain unconfirmed");
        assert!(
            blocked
                .to_string()
                .contains("bundle 1 is still unconfirmed"),
            "{blocked}"
        );
        assert!(
            import_capability(&customer, &capability, import_context(&hotkey, &params)).unwrap()
                == digest
        );
    }

    #[test]
    fn imported_capability_rejects_suffix_bundle_deletion() {
        assert_imported_capability_rejects_bundle_trim(1);
    }

    #[test]
    fn imported_capability_rejects_full_bundle_deletion() {
        assert_imported_capability_rejects_bundle_trim(0);
    }

    #[test]
    fn terminal_capability_reset_accepts_a_corrected_complete_package() {
        let (_, params, hotkey, capability) = exported_fixture();
        let customer = test_db(":memory:");
        import_capability(&customer, &capability, import_context(&hotkey, &params)).unwrap();
        queries::store_van_position(&customer.conn(), &params.vote_round_id, WALLET, 0, 42)
            .unwrap();

        customer.clear_round(&params.vote_round_id).unwrap();
        let mut corrected = capability.clone();
        corrected.bundles[1].delegation_tx_hash = "11".repeat(32);
        import_capability(&customer, &corrected, import_context(&hotkey, &params)).unwrap();

        assert!(
            queries::load_van_position(&customer.conn(), &params.vote_round_id, WALLET, 0).is_err(),
            "the old confirmation must not survive the reset"
        );
        assert_eq!(
            queries::get_delegation_tx_hash(&customer.conn(), &params.vote_round_id, WALLET, 0)
                .unwrap(),
            Some(capability.bundles[0].delegation_tx_hash.clone())
        );
        assert_eq!(
            queries::get_delegation_tx_hash(&customer.conn(), &params.vote_round_id, WALLET, 1)
                .unwrap(),
            Some(corrected.bundles[1].delegation_tx_hash.clone())
        );
        assert!(customer
            .get_votes(&params.vote_round_id)
            .unwrap()
            .is_empty());

        queries::store_van_position(&customer.conn(), &params.vote_round_id, WALLET, 0, 52)
            .unwrap();
        queries::store_van_position(&customer.conn(), &params.vote_round_id, WALLET, 1, 53)
            .unwrap();
        customer
            .require_capability_delegations_confirmed(&params.vote_round_id)
            .unwrap();
    }

    fn confirmed_capability_fixture(
        path: &str,
    ) -> (
        VotingDb,
        VotingRoundParams,
        VotingHotkey,
        crate::vote::VanWitness,
    ) {
        use crate::confirmation::{confirm_delegation_submission, TxEvent, TxEventAttribute};
        use vote_commitment_tree::MemoryTreeServer;

        let (_, params, hotkey, capability) = exported_fixture();
        let customer = test_db(path);
        import_capability(&customer, &capability, import_context(&hotkey, &params)).unwrap();

        for bundle_index in 0..2 {
            let tx_hash = capability.bundles[bundle_index].delegation_tx_hash.clone();
            confirm_delegation_submission(
                &customer,
                &params.vote_round_id,
                bundle_index as u32,
                &tx_hash,
                &[TxEvent {
                    event_type: "delegate_vote".to_string(),
                    attributes: vec![
                        TxEventAttribute {
                            key: "vote_round_id".to_string(),
                            value: params.vote_round_id.clone(),
                        },
                        TxEventAttribute {
                            key: "leaf_index".to_string(),
                            value: bundle_index.to_string(),
                        },
                    ],
                }],
            )
            .unwrap();
        }

        let validated = capability.validate().unwrap();
        let mut server = MemoryTreeServer::empty();
        for bundle in &validated.bundles {
            let leaf = Option::from(pallas::Base::from_repr(bundle.van)).unwrap();
            server.append(leaf).unwrap();
        }
        server.checkpoint(1).unwrap();

        let tree = crate::tree_sync::VoteTreeSync::new();
        let anchor_height = tree
            .sync_with_api(&customer, &params.vote_round_id, &server)
            .unwrap();
        let witness = tree
            .generate_van_witness(&customer, &params.vote_round_id, 0, anchor_height)
            .unwrap();

        (customer, params, hotkey, witness)
    }

    #[test]
    #[ignore = "generates a real ZKP2 proof"]
    fn delegation_capability_handoff_confirms_tree_leaf_and_builds_a_real_vote() {
        use crate::{
            types::NoopProgressReporter,
            vote::{DraftVote, VoteSigner},
        };
        let (customer, params, hotkey, witness) = confirmed_capability_fixture(":memory:");
        let committed = crate::vote::commit(
            &customer,
            &params.vote_round_id,
            0,
            &DraftVote {
                proposal_id: 1,
                choice: 0,
                num_options: 2,
                single_share: true,
                vc_tree_position: 0,
            },
            &witness,
            VoteSigner::hotkey(&hotkey),
            &NoopProgressReporter,
        )
        .unwrap();

        assert_eq!(committed.proposal_id, 1);
        assert!(!committed.proof.is_empty());
    }

    #[test]
    #[ignore = "generates two real ZKP2 proofs"]
    fn fresh_vote_batch_chains_signs_and_recovers_after_restart() {
        use crate::backend::orchard::primitives::redpallas::{
            Signature, SpendAuth, VerificationKey,
        };
        use crate::{
            session::Decision,
            types::NoopProgressReporter,
            vote::{DraftVote, VoteSigner},
        };

        let path = temp_db_path("capability-batch-vote");
        let path_string = path.to_str().unwrap().to_string();
        let (customer, params, hotkey, witness) = confirmed_capability_fixture(&path_string);
        let drafts = [
            DraftVote {
                proposal_id: 1,
                choice: 0,
                num_options: 2,
                single_share: true,
                vc_tree_position: 0,
            },
            DraftVote {
                proposal_id: 2,
                choice: 1,
                num_options: 2,
                single_share: true,
                vc_tree_position: 0,
            },
        ];
        for draft in &drafts {
            customer
                .set_ballot_intent(
                    &params.vote_round_id,
                    draft.proposal_id,
                    Decision::Choice(draft.choice),
                    draft.num_options,
                )
                .unwrap();
        }

        let state =
            queries::load_zkp2_inputs(&customer.conn(), &params.vote_round_id, WALLET, 0).unwrap();
        let round_id_bytes = hex::decode(&params.vote_round_id).unwrap();
        let first_transition = crate::zkp2::plan_vote_authority_transition(
            hotkey.stored_secret(),
            Network::Regtest,
            state.address_index,
            state.total_note_value,
            &state.gov_comm_rand,
            &round_id_bytes,
            drafts[0].proposal_id,
            state.proposal_authority,
        )
        .unwrap();
        let second_transition = crate::zkp2::plan_vote_authority_transition(
            hotkey.stored_secret(),
            Network::Regtest,
            state.address_index,
            state.total_note_value,
            &state.gov_comm_rand,
            &round_id_bytes,
            drafts[1].proposal_id,
            first_transition.proposal_authority_new,
        )
        .unwrap();
        assert_eq!(
            second_transition.vote_authority_note_old,
            first_transition.vote_authority_note_new
        );

        let committed = crate::vote::commit_atomic_vote_batch(
            &customer,
            &params.vote_round_id,
            0,
            &drafts,
            &witness,
            VoteSigner::hotkey(&hotkey),
            &NoopProgressReporter,
        )
        .unwrap();

        assert_eq!(committed.commitments.len(), 2);
        assert_eq!(
            committed.commitments[0].vote_authority_note_new,
            first_transition.vote_authority_note_new
        );
        assert_eq!(
            committed.commitments[1].vote_authority_note_new,
            second_transition.vote_authority_note_new
        );
        let digest = committed.batch_digest;
        for commitment in &committed.commitments {
            VerificationKey::<SpendAuth>::try_from(commitment.r_vpk)
                .unwrap()
                .verify(
                    &digest,
                    &Signature::<SpendAuth>::from(commitment.vote_auth_sig),
                )
                .unwrap();
        }
        let batch_json = committed.batch_json;
        drop(customer);

        let reopened = test_db(&path_string);
        let recovered = crate::vote::recover_atomic_vote_batch(
            &reopened,
            &params.vote_round_id,
            0,
            drafts[0].proposal_id,
        )
        .unwrap();
        assert_eq!(recovered.batch_digest, digest);
        assert_eq!(recovered.batch_json, batch_json);
        assert_eq!(recovered.commitments.len(), 2);

        drop(reopened);
        std::fs::remove_file(path).ok();
    }
}
