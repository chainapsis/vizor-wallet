#[allow(unused_imports)]
pub(crate) use crate::backend::pasta_curves;
use pasta_curves::group::ff::PrimeField;
use pasta_curves::pallas;
use rusqlite::{named_params, Connection, OptionalExtension, Transaction, TransactionBehavior};
use serde::{Deserialize, Serialize};

use crate::note_bundling::BundlePolicy;
use crate::storage::{KeystoneSignatureRecord, RoundPhase, RoundState, RoundSummary, VoteRecord};
use crate::types::{Network, NoteInfo, VotingError, VotingRoundParams, WitnessData};

mod share_delegations;

#[cfg(test)]
pub(crate) use share_delegations::record_share_delegation_with_after_read;
pub use share_delegations::{
    add_ambiguous_servers, add_attempting_server, add_sent_servers_preserving_schedule,
    clear_stale_share_delegations_for_intent, get_share_delegations, get_unconfirmed_delegations,
    pending_share_rounds, remove_attempting_server, share_is_confirmed,
};
pub(crate) use share_delegations::{
    add_ambiguous_servers_for_generation, add_attempting_server_for_generation,
    add_sent_servers_for_generation, add_sent_servers_preserving_schedule_for_generation,
    mark_share_confirmed, record_share_delegation, record_share_delegation_for_vote_generation,
    remove_attempting_server_for_generation, share_is_confirmed_for_generation,
    ShareAttemptReservation,
};

const NOTE_IDENTITY_HASH_BYTES: usize = 32;
const NOTE_IDENTITY_DOMAIN: &[u8] = b"zcash-voting-note-identity-v1";
const BUNDLE_POLICY_SCHEMA_VERSION: u32 = 1;

fn deserialize_required_option<'de, D, T>(deserializer: D) -> Result<Option<T>, D::Error>
where
    D: serde::Deserializer<'de>,
    T: Deserialize<'de>,
{
    Option::<T>::deserialize(deserializer)
}

/// Exact on-disk representation of bundle policy schema version 1.
///
/// All fields are required intentionally. Adding a runtime policy field requires
/// a new persistence DTO and schema version rather than a serde default here.
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct PersistedBundlePolicyV1 {
    max_real_notes_per_bundle: usize,
    #[serde(deserialize_with = "deserialize_required_option")]
    bundle_addition_threshold_zatoshi: Option<u64>,
    #[serde(deserialize_with = "deserialize_required_option")]
    max_privacy_bundles: Option<usize>,
    privacy_drop_bps: u32,
    #[serde(deserialize_with = "deserialize_required_option")]
    max_privacy_drop_zatoshi: Option<u64>,
}

impl From<BundlePolicy> for PersistedBundlePolicyV1 {
    fn from(policy: BundlePolicy) -> Self {
        Self {
            max_real_notes_per_bundle: policy.max_real_notes_per_bundle(),
            bundle_addition_threshold_zatoshi: policy.bundle_addition_threshold(),
            max_privacy_bundles: policy.max_privacy_bundles(),
            privacy_drop_bps: policy.privacy_drop_bps(),
            max_privacy_drop_zatoshi: policy.max_privacy_drop_zatoshi(),
        }
    }
}

impl PersistedBundlePolicyV1 {
    fn into_policy(self) -> Result<BundlePolicy, VotingError> {
        let mut policy = BundlePolicy::new(self.max_real_notes_per_bundle)?;
        if let Some(threshold) = self.bundle_addition_threshold_zatoshi {
            policy = policy.with_bundle_addition_threshold(threshold);
        }
        Ok(policy
            .with_max_privacy_bundles(self.max_privacy_bundles)
            .with_privacy_drop_bps(self.privacy_drop_bps)?
            .with_max_privacy_drop_zatoshi(self.max_privacy_drop_zatoshi))
    }
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct PersistedBundlePolicyEnvelope<T> {
    version: u32,
    policy: T,
}

fn encode_bundle_policy(policy: BundlePolicy) -> Result<String, serde_json::Error> {
    serde_json::to_string(&PersistedBundlePolicyEnvelope::<PersistedBundlePolicyV1> {
        version: BUNDLE_POLICY_SCHEMA_VERSION,
        policy: policy.into(),
    })
}

fn decode_bundle_policy(json: &str) -> Result<BundlePolicy, String> {
    let envelope: PersistedBundlePolicyEnvelope<serde_json::Value> =
        serde_json::from_str(json).map_err(|e| format!("invalid versioned policy: {e}"))?;
    if envelope.version != BUNDLE_POLICY_SCHEMA_VERSION {
        return Err(format!("unsupported schema version {}", envelope.version));
    }
    let persisted: PersistedBundlePolicyV1 = serde_json::from_value(envelope.policy)
        .map_err(|e| format!("invalid version 1 policy: {e}"))?;

    persisted
        .into_policy()
        .map_err(|e| format!("invalid policy value: {e}"))
}

#[cfg(test)]
mod bundle_policy_schema_tests {
    use super::*;
    use crate::note_bundling::MAX_PRIVACY_DROP_BPS;

    fn custom_policy() -> BundlePolicy {
        BundlePolicy::new(1)
            .unwrap()
            .with_bundle_addition_threshold(42)
            .with_max_privacy_bundles(Some(3))
            .with_privacy_drop_bps(75)
            .unwrap()
            .with_max_privacy_drop_zatoshi(Some(99))
    }

    #[test]
    fn bundle_policy_writes_a_versioned_envelope() {
        let json = encode_bundle_policy(custom_policy()).unwrap();
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();

        assert_eq!(value["version"], BUNDLE_POLICY_SCHEMA_VERSION);
        assert!(value["policy"].is_object());
        assert_eq!(decode_bundle_policy(&json).unwrap(), custom_policy());
    }

    #[test]
    fn bundle_policy_rejects_unversioned_payloads() {
        let unversioned =
            serde_json::to_string(&PersistedBundlePolicyV1::from(custom_policy())).unwrap();

        let error = decode_bundle_policy(&unversioned).unwrap_err();
        assert!(error.contains("invalid versioned policy"));
    }

    #[test]
    fn bundle_policy_rejects_missing_persisted_fields() {
        let incomplete = serde_json::json!({
            "version": BUNDLE_POLICY_SCHEMA_VERSION,
            "policy": {
                "max_real_notes_per_bundle": 1,
                "bundle_addition_threshold_zatoshi": null,
                "max_privacy_bundles": 2,
                "privacy_drop_bps": 100
            }
        });

        let error = decode_bundle_policy(&incomplete.to_string()).unwrap_err();
        assert!(error.contains("missing field `max_privacy_drop_zatoshi`"));
    }

    #[test]
    fn bundle_policy_rejects_unknown_schema_versions() {
        let json = serde_json::json!({
            "version": BUNDLE_POLICY_SCHEMA_VERSION + 1,
            "policy": PersistedBundlePolicyV1::from(custom_policy())
        });

        let error = decode_bundle_policy(&json.to_string()).unwrap_err();
        assert!(error.contains("unsupported schema version"));
    }

    #[test]
    fn bundle_policy_rejects_privacy_drop_bps_above_max() {
        let mut persisted = PersistedBundlePolicyV1::from(custom_policy());
        persisted.privacy_drop_bps = MAX_PRIVACY_DROP_BPS + 1;

        let json = serde_json::json!({
            "version": BUNDLE_POLICY_SCHEMA_VERSION,
            "policy": persisted
        });

        let error = decode_bundle_policy(&json.to_string()).unwrap_err();
        assert!(error.contains("privacy_drop_bps"));
    }
}

fn update_hash_with_len_prefixed_bytes(state: &mut blake2b_simd::State, value: &[u8]) {
    state.update(&(value.len() as u64).to_le_bytes());
    state.update(value);
}

fn note_identity_hash(note: &NoteInfo) -> [u8; NOTE_IDENTITY_HASH_BYTES] {
    let mut state = blake2b_simd::Params::new()
        .hash_length(NOTE_IDENTITY_HASH_BYTES)
        .to_state();
    // The domain string is longer than BLAKE2b's 16-byte personalization field.
    state.update(NOTE_IDENTITY_DOMAIN);
    state.update(&note.position.to_le_bytes());
    state.update(&note.value.to_le_bytes());
    state.update(&note.scope.to_le_bytes());
    update_hash_with_len_prefixed_bytes(&mut state, &note.commitment);
    update_hash_with_len_prefixed_bytes(&mut state, &note.nullifier);
    update_hash_with_len_prefixed_bytes(&mut state, &note.diversifier);
    update_hash_with_len_prefixed_bytes(&mut state, &note.rho);
    update_hash_with_len_prefixed_bytes(&mut state, &note.rseed);
    update_hash_with_len_prefixed_bytes(&mut state, note.ufvk_str.as_bytes());

    let hash = state.finalize();
    let mut out = [0u8; NOTE_IDENTITY_HASH_BYTES];
    out.copy_from_slice(hash.as_bytes());
    out
}

fn note_positions_blob(note_positions: &[u64]) -> Vec<u8> {
    note_positions
        .iter()
        .flat_map(|position| position.to_le_bytes())
        .collect()
}

fn note_positions_blob_for_notes(notes: &[NoteInfo]) -> Vec<u8> {
    notes
        .iter()
        .map(|note| note.position)
        .flat_map(|position| position.to_le_bytes())
        .collect()
}

fn note_identity_hashes_blob(notes: &[NoteInfo]) -> Vec<u8> {
    notes
        .iter()
        .flat_map(|note| note_identity_hash(note))
        .collect()
}

fn encode_gov_nullifiers_blob(gov_nullifiers: &[Vec<u8>]) -> Vec<u8> {
    gov_nullifiers
        .iter()
        .flat_map(|n| n.iter().copied())
        .collect()
}

fn encode_padded_note_secrets(padded_note_secrets: &[(Vec<u8>, Vec<u8>)]) -> Vec<u8> {
    padded_note_secrets
        .iter()
        .flat_map(|(rho, rseed)| rho.iter().copied().chain(rseed.iter().copied()))
        .collect()
}

fn decode_padded_note_secrets(blob: Vec<u8>) -> Result<Vec<(Vec<u8>, Vec<u8>)>, VotingError> {
    if blob.len() % 64 != 0 {
        return Err(VotingError::Internal {
            message: format!(
                "corrupt padded_note_secrets blob: length {} is not a multiple of 64",
                blob.len()
            ),
        });
    }
    Ok(blob
        .chunks_exact(64)
        .map(|c| (c[..32].to_vec(), c[32..].to_vec()))
        .collect())
}

// --- Rounds ---

pub(crate) fn network_to_storage(network: Network) -> &'static str {
    match network {
        Network::Mainnet => "mainnet",
        Network::Testnet => "testnet",
        Network::Regtest => "regtest",
    }
}

pub(crate) fn network_from_storage(value: &str) -> Result<Network, VotingError> {
    match value {
        "mainnet" => Ok(Network::Mainnet),
        "testnet" => Ok(Network::Testnet),
        "regtest" => Ok(Network::Regtest),
        _ => Err(VotingError::Internal {
            message: format!("stored round network is invalid: {value}"),
        }),
    }
}

pub fn insert_round(
    conn: &Connection,
    wallet_id: &str,
    network: Network,
    params: &VotingRoundParams,
    session_json: Option<&str>,
) -> Result<(), VotingError> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;

    conn.execute(
        "INSERT INTO rounds (round_id, wallet_id, network, snapshot_height, ea_pk, nc_root, nullifier_imt_root, session_json, phase, created_at)
         VALUES (:round_id, :wallet_id, :network, :snapshot_height, :ea_pk, :nc_root, :nullifier_imt_root, :session_json, :phase, :created_at)",
        named_params! {
            ":round_id": params.vote_round_id,
            ":wallet_id": wallet_id,
            ":network": network_to_storage(network),
            ":snapshot_height": params.snapshot_height as i64,
            ":ea_pk": params.ea_pk,
            ":nc_root": params.nc_root,
            ":nullifier_imt_root": params.nullifier_imt_root,
            ":session_json": session_json,
            ":phase": RoundPhase::Initialized as i32,
            ":created_at": now,
        },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to insert round: {}", e),
    })?;

    Ok(())
}

/// Set a round phase without checking lifecycle ordering.
///
/// Prefer `advance_round_phase` for normal workflow transitions.
#[deprecated(note = "use advance_round_phase to preserve forward-only round progression")]
pub fn update_round_phase(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    phase: RoundPhase,
) -> Result<(), VotingError> {
    let rows = conn
        .execute(
            "UPDATE rounds SET phase = :phase WHERE round_id = :round_id AND wallet_id = :wallet_id",
            named_params! {
                ":phase": phase as i32,
                ":round_id": round_id,
                ":wallet_id": wallet_id,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to update round phase: {}", e),
        })?;

    if rows == 0 {
        return Err(VotingError::InvalidInput {
            message: format!("round not found: {}", round_id),
        });
    }

    Ok(())
}

/// Advance a round phase without allowing regressions.
///
/// Re-applying the current phase is treated as idempotent.
pub fn advance_round_phase(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    phase: RoundPhase,
) -> Result<(), VotingError> {
    let requested_rank = phase as i32;
    let rows = conn
        .execute(
            "UPDATE rounds
             SET phase = :phase
             WHERE round_id = :round_id
               AND wallet_id = :wallet_id
               AND phase < :phase",
            named_params! {
                ":phase": requested_rank,
                ":round_id": round_id,
                ":wallet_id": wallet_id,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to advance round phase: {}", e),
        })?;
    if rows > 0 {
        return Ok(());
    }

    let current = get_round_state(conn, round_id, wallet_id)?.phase;
    let current_rank = current as i32;

    // This can only happen if another connection changes the row between the
    // failed UPDATE and this readback.
    if current_rank < requested_rank {
        Err(VotingError::Internal {
            message: format!(
                "failed to advance round phase for {round_id}: current={current_rank}, requested={requested_rank}"
            ),
        })
    } else if current_rank > requested_rank {
        Err(VotingError::InvalidInput {
            message: format!(
                "refusing to regress round phase for {round_id}: current={current_rank}, requested={requested_rank}"
            ),
        })
    } else {
        Ok(())
    }
}

pub fn load_round_params(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<VotingRoundParams, VotingError> {
    load_round_params_with_network(conn, round_id, wallet_id).map(|(params, _)| params)
}

pub fn load_round_params_with_network(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<(VotingRoundParams, Network), VotingError> {
    conn.query_row(
        "SELECT round_id, network, snapshot_height, ea_pk, nc_root, nullifier_imt_root FROM rounds WHERE round_id = :round_id AND wallet_id = :wallet_id",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
        |row| {
            let network: String = row.get(1)?;
            Ok((
                VotingRoundParams {
                vote_round_id: row.get(0)?,
                    snapshot_height: row.get::<_, i64>(2)? as u64,
                    ea_pk: row.get(3)?,
                    nc_root: row.get(4)?,
                    nullifier_imt_root: row.get(5)?,
                },
                network,
            ))
        },
    )
    .map_err(|e| VotingError::InvalidInput {
        message: format!("round not found: {} ({})", round_id, e),
    })
    .and_then(|(params, network)| Ok((params, network_from_storage(&network)?)))
}

pub fn load_round_network(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<Network, VotingError> {
    conn.query_row(
        "SELECT network FROM rounds WHERE round_id = :round_id AND wallet_id = :wallet_id",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
        |row| row.get::<_, String>(0),
    )
    .map_err(|e| VotingError::InvalidInput {
        message: format!("round not found: {} ({})", round_id, e),
    })
    .and_then(|network| network_from_storage(&network))
}

pub fn has_round(conn: &Connection, round_id: &str, wallet_id: &str) -> Result<bool, VotingError> {
    conn.query_row(
        "SELECT 1 FROM rounds WHERE round_id = :round_id AND wallet_id = :wallet_id LIMIT 1",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
        |_| Ok(()),
    )
    .optional()
    .map(|row| row.is_some())
    .map_err(|e| VotingError::Internal {
        message: format!("failed to check round existence: {}", e),
    })
}

pub fn get_round_state(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<RoundState, VotingError> {
    let (phase_int, network, snapshot_height): (i32, String, i64) = conn
        .query_row(
            "SELECT phase, network, snapshot_height FROM rounds WHERE round_id = :round_id AND wallet_id = :wallet_id",
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .map_err(|e| VotingError::InvalidInput {
            message: format!("round not found: {} ({})", round_id, e),
        })?;
    let network = network_from_storage(&network)?;

    // proof_generated is true only when ALL bundles are locally proven or
    // capability-imported AND all bundles have a VAN leaf position. This keeps
    // the legacy UI field false until every delegation transaction lands.
    let bundle_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id",
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
            |row| row.get(0),
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to count bundles: {}", e),
        })?;

    let proof_generated = if bundle_count == 0 {
        false
    } else {
        let proven_count: i64 = conn
            .query_row(
                "SELECT COUNT(*)
                 FROM bundles b
                 WHERE b.round_id = :round_id AND b.wallet_id = :wallet_id
                   AND (
                       EXISTS (
                           SELECT 1 FROM proofs p
                           WHERE p.round_id = b.round_id
                             AND p.wallet_id = b.wallet_id
                             AND p.bundle_index = b.bundle_index
                             AND p.success = 1
                       )
                       OR (
                           b.note_positions_blob IS NULL
                           AND b.van_comm_rand IS NOT NULL
                           AND b.gov_comm IS NOT NULL
                           AND b.total_note_value IS NOT NULL
                           AND b.address_index = 0
                           AND b.delegation_tx_hash IS NOT NULL
                       )
                   )",
                named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
                |row| row.get(0),
            )
            .map_err(|e| VotingError::Internal {
                message: format!("failed to count completed delegations: {}", e),
            })?;

        let van_positions_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND van_leaf_position IS NOT NULL",
                named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
                |row| row.get(0),
            )
            .map_err(|e| VotingError::Internal {
                message: format!("failed to count VAN positions: {}", e),
            })?;

        proven_count >= bundle_count && van_positions_count >= bundle_count
    };

    Ok(RoundState {
        round_id: round_id.to_string(),
        phase: RoundPhase::from_i32(phase_int),
        network,
        snapshot_height: snapshot_height as u64,
        hotkey_address: None,
        delegated_weight: None,
        proof_generated,
    })
}

pub fn list_rounds(conn: &Connection, wallet_id: &str) -> Result<Vec<RoundSummary>, VotingError> {
    let mut stmt = conn
        .prepare("SELECT round_id, wallet_id, phase, network, snapshot_height, created_at FROM rounds WHERE wallet_id = :wallet_id ORDER BY created_at DESC")
        .map_err(|e| VotingError::Internal {
            message: format!("failed to prepare list_rounds query: {}", e),
        })?;

    let rounds = stmt
        .query_map(named_params! { ":wallet_id": wallet_id }, |row| {
            Ok(RoundSummary {
                round_id: row.get(0)?,
                wallet_id: row.get(1)?,
                phase: RoundPhase::from_i32(row.get(2)?),
                network: network_from_storage(&row.get::<_, String>(3)?).map_err(|e| {
                    rusqlite::Error::FromSqlConversionFailure(
                        3,
                        rusqlite::types::Type::Text,
                        Box::new(e),
                    )
                })?,
                snapshot_height: row.get::<_, i64>(4)? as u64,
                created_at: row.get::<_, i64>(5)? as u64,
            })
        })
        .map_err(|e| VotingError::Internal {
            message: format!("failed to list rounds: {}", e),
        })?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to collect rounds: {}", e),
        })?;

    Ok(rounds)
}

/// Delete a round and all associated data. Child tables (bundles, cached_tree_state,
/// proofs, witnesses, votes) are removed automatically via ON DELETE CASCADE.
pub fn clear_round(conn: &Connection, round_id: &str, wallet_id: &str) -> Result<(), VotingError> {
    conn.execute(
        "DELETE FROM rounds WHERE round_id = :round_id AND wallet_id = :wallet_id",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to clear round: {}", e),
    })?;
    Ok(())
}

// --- Bundles ---

/// Insert a bundle row from positions only.
///
/// Retained for SDK/FFI compatibility with callers that cannot provide full
/// notes at insertion time. Rows written this way have a NULL
/// `note_identity_hashes_blob`, so `require_bundle_notes` can only enforce the
/// legacy position check until callers migrate to `insert_bundle_notes`.
pub fn insert_bundle(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    note_positions: &[u64],
) -> Result<(), VotingError> {
    let positions_blob = note_positions_blob(note_positions);

    conn.execute(
        "INSERT INTO bundles (round_id, wallet_id, bundle_index, note_positions_blob)
         VALUES (:round_id, :wallet_id, :bundle_index, :note_positions_blob)",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
            ":note_positions_blob": positions_blob,
        },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to insert bundle: {}", e),
    })?;

    Ok(())
}

/// Insert a bundle row from full notes, persisting both positions and note identity hashes.
pub fn insert_bundle_notes(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    notes: &[NoteInfo],
) -> Result<(), VotingError> {
    let positions_blob = note_positions_blob_for_notes(notes);
    let identity_hashes_blob = note_identity_hashes_blob(notes);

    conn.execute(
        "INSERT INTO bundles (round_id, wallet_id, bundle_index, note_positions_blob, note_identity_hashes_blob)
         VALUES (:round_id, :wallet_id, :bundle_index, :note_positions_blob, :note_identity_hashes_blob)",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
            ":note_positions_blob": positions_blob,
            ":note_identity_hashes_blob": identity_hashes_blob,
        },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to insert bundle: {}", e),
    })?;

    Ok(())
}

fn decode_note_positions_blob(blob: &[u8]) -> Result<Vec<u64>, VotingError> {
    if blob.len() % 8 != 0 {
        return Err(VotingError::Internal {
            message: format!(
                "corrupt note_positions_blob: length {} is not a multiple of 8",
                blob.len()
            ),
        });
    }

    Ok(blob
        .chunks_exact(8)
        .map(|c| u64::from_le_bytes(c.try_into().expect("chunks_exact(8) guarantees 8 bytes")))
        .collect())
}

/// Get the number of bundles for a round.
pub fn get_bundle_count(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<u32, VotingError> {
    conn.query_row(
        "SELECT COUNT(*) FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
        |row| row.get::<_, i64>(0).map(|c| c as u32),
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to get bundle count: {}", e),
    })
}

/// Reads the bundle policy persisted with a round, if one was stored.
///
/// Returns `None` when the column is NULL, or when the stored JSON is an
/// unknown schema version / otherwise unreadable. Callers then fall back the
/// same way as for pre-policy rounds: keep the caller's capacity/threshold and
/// disable the privacy trim when bundle rows already exist. Strict decode is
/// still used when a readable policy is present; this only avoids bricking a
/// round after a future schema bump on downgrade.
pub fn get_round_bundle_policy(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<Option<BundlePolicy>, VotingError> {
    let stored: Option<String> = conn
        .query_row(
            "SELECT bundle_policy_json FROM rounds WHERE round_id = :round_id AND wallet_id = :wallet_id",
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to read stored bundle policy: {e}"),
        })?
        .flatten();

    Ok(stored.and_then(|json| decode_bundle_policy(&json).ok()))
}

/// Records the bundle policy that produced a round's persisted bundle rows.
///
/// Later planning passes re-derive with this value instead of the caller's, so
/// an SDK upgrade that changes the defaults cannot invalidate bundles that were
/// already signed or submitted.
///
/// # Invariant
///
/// `bundle_policy_json` is non-NULL if and only if the round has at least one
/// bundle row, and it holds the policy that produced those rows. The `EXISTS`
/// clause below enforces one direction; [`delete_bundles_from`] enforces the
/// other by clearing the column once the last row is gone.
///
/// Callers writing a freshly planned round must therefore insert the bundle
/// rows *before* calling this, in the same transaction. A plan with no
/// surviving bundles writes nothing, which leaves the round free to replan
/// under a different policy.
pub fn set_round_bundle_policy(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    policy: BundlePolicy,
) -> Result<(), VotingError> {
    let json = encode_bundle_policy(policy).map_err(|e| VotingError::Internal {
        message: format!("failed to encode bundle policy: {e}"),
    })?;
    conn.execute(
        "UPDATE rounds SET bundle_policy_json = :policy
         WHERE round_id = :round_id
           AND wallet_id = :wallet_id
           AND EXISTS (SELECT 1 FROM bundles b
                        WHERE b.round_id = :round_id AND b.wallet_id = :wallet_id)",
        named_params! {
            ":policy": json,
            ":round_id": round_id,
            ":wallet_id": wallet_id,
        },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to store bundle policy: {e}"),
    })?;
    Ok(())
}

/// Imported bundles omit local note positions; local bundle insertion always stores them.
fn round_has_imported_capability_bundles(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<bool, VotingError> {
    conn.query_row(
        "SELECT EXISTS (
             SELECT 1
             FROM bundles
             WHERE round_id = :round_id
               AND wallet_id = :wallet_id
               AND note_positions_blob IS NULL
         )",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
        |row| row.get::<_, bool>(0),
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to check for imported capability bundles: {e}"),
    })
}

/// Require every delegation in an imported capability round to be confirmed
/// before fresh vote state is created.
///
/// Locally prepared rounds retain their existing per-bundle voting behavior.
pub(crate) fn require_capability_delegations_confirmed(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<(), VotingError> {
    if !round_has_imported_capability_bundles(conn, round_id, wallet_id)? {
        return Ok(());
    }

    let pending_bundle = conn
        .query_row(
            "SELECT pending.bundle_index
             FROM bundles pending
             WHERE pending.round_id = :round_id
               AND pending.wallet_id = :wallet_id
               AND pending.van_leaf_position IS NULL
             ORDER BY pending.bundle_index
             LIMIT 1",
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
            |row| row.get::<_, i64>(0),
        )
        .optional()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to check imported delegation confirmations: {e}"),
        })?;

    if let Some(bundle_index) = pending_bundle {
        return Err(VotingError::InvalidInput {
            message: format!(
                "imported capability round {round_id} cannot create votes until every delegation is confirmed; bundle {bundle_index} is still unconfirmed"
            ),
        });
    }

    Ok(())
}

/// Load the note positions for a specific bundle.
pub fn load_bundle_note_positions(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<Vec<u64>, VotingError> {
    let blob: Vec<u8> = conn
        .query_row(
            "SELECT note_positions_blob FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
            },
            |row| row.get(0),
        )
        .map_err(|e| VotingError::InvalidInput {
            message: format!("bundle not found: round={}, bundle={} ({})", round_id, bundle_index, e),
        })?;

    decode_note_positions_blob(&blob)
}

pub fn require_bundle_notes(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    notes: &[NoteInfo],
) -> Result<(), VotingError> {
    let (positions_blob, identity_hashes_blob): (Vec<u8>, Option<Vec<u8>>) = conn
        .query_row(
            "SELECT note_positions_blob, note_identity_hashes_blob FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
            },
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .map_err(|e| VotingError::InvalidInput {
            message: format!(
                "bundle not found: round={}, bundle={} ({})",
                round_id, bundle_index, e
            ),
        })?;

    let stored_positions = decode_note_positions_blob(&positions_blob)?;
    let requested_positions = notes.iter().map(|note| note.position).collect::<Vec<_>>();
    if stored_positions != requested_positions {
        return Err(VotingError::InvalidInput {
            message: format!(
                "bundle_index {bundle_index} notes do not match persisted setup: stored positions {:?}, requested positions {:?}",
                stored_positions, requested_positions
            ),
        });
    }

    // Legacy carve-out: bundles persisted before 0.5.8 were ALTER-migrated to
    // v8 with a NULL `note_identity_hashes_blob` because the original
    // `NoteInfo` payloads cannot be backfilled. For those rows we fall back to
    // the position-only check above; identity verification only applies to
    // bundles set up under 0.5.8 or later.
    let Some(identity_hashes_blob) = identity_hashes_blob else {
        return Ok(());
    };

    if identity_hashes_blob.len() % NOTE_IDENTITY_HASH_BYTES != 0 {
        return Err(VotingError::Internal {
            message: format!(
                "corrupt note_identity_hashes_blob: length {} is not a multiple of {}",
                identity_hashes_blob.len(),
                NOTE_IDENTITY_HASH_BYTES
            ),
        });
    }

    let stored_hashes = identity_hashes_blob
        .chunks_exact(NOTE_IDENTITY_HASH_BYTES)
        .collect::<Vec<_>>();
    if stored_hashes.len() != notes.len() {
        return Err(VotingError::InvalidInput {
            message: format!(
                "bundle_index {bundle_index} note identity count mismatch: stored {}, requested {}",
                stored_hashes.len(),
                notes.len()
            ),
        });
    }

    for (index, (stored_hash, note)) in stored_hashes.iter().zip(notes.iter()).enumerate() {
        let requested_hash = note_identity_hash(note);
        if *stored_hash != requested_hash {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "bundle_index {bundle_index} note identity mismatch at index {index}"
                ),
            });
        }
    }

    Ok(())
}

// --- Delegation Secrets ---
//
// After build_governance_pczt computes the VAN (governance commitment),
// we persist two values needed for later proof steps:
//   - van_comm_rand: the 32-byte blinding factor used in the VAN Poseidon hash.
//     Needed again in ZKP #2 (vote commitment) to reconstruct the VAN as a witness.
//   - dummy_nullifiers: nullifiers generated for zero-value padded note slots (§1.3.5).
//     Each is 32 bytes. Stored so the witness builder can reconstruct padded notes.

/// Persist all delegation action data and finalized TX1 effects in a single
/// UPDATE on the bundles table. The effects are required by
/// [`load_delegation_submission_data`].
pub fn store_delegation_data(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    van_comm_rand: &[u8],
    dummy_nullifiers: &[Vec<u8>],
    rho_signed: &[u8],
    padded_cmx: &[Vec<u8>],
    nf_signed: &[u8],
    cmx_new: &[u8],
    alpha: &[u8],
    rseed_signed: &[u8],
    rseed_output: &[u8],
    gov_comm: &[u8],
    total_note_value: u64,
    address_index: u32,
    padded_note_secrets: &[(Vec<u8>, Vec<u8>)],
    pczt_sighash: &[u8],
    tx1_effects: &[u8],
) -> Result<(), VotingError> {
    store_delegation_data_inner(
        conn,
        round_id,
        wallet_id,
        bundle_index,
        van_comm_rand,
        dummy_nullifiers,
        rho_signed,
        padded_cmx,
        nf_signed,
        cmx_new,
        alpha,
        rseed_signed,
        rseed_output,
        gov_comm,
        total_note_value,
        address_index,
        padded_note_secrets,
        pczt_sighash,
        Some(tx1_effects),
        None,
        None,
    )
}

/// Persist delegation action data, the finalized TX1 effects, and PCZT-derived
/// public inputs that the later delegation proof must reproduce.
pub(crate) fn store_delegation_data_with_pczt_fields(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    van_comm_rand: &[u8],
    dummy_nullifiers: &[Vec<u8>],
    rho_signed: &[u8],
    padded_cmx: &[Vec<u8>],
    nf_signed: &[u8],
    cmx_new: &[u8],
    alpha: &[u8],
    rseed_signed: &[u8],
    rseed_output: &[u8],
    gov_comm: &[u8],
    total_note_value: u64,
    address_index: u32,
    padded_note_secrets: &[(Vec<u8>, Vec<u8>)],
    pczt_sighash: &[u8],
    tx1_effects: &[u8],
    rk: &[u8],
    gov_nullifiers: &[Vec<u8>],
) -> Result<(), VotingError> {
    let gov_nullifiers_blob = encode_gov_nullifiers_blob(gov_nullifiers);
    store_delegation_data_inner(
        conn,
        round_id,
        wallet_id,
        bundle_index,
        van_comm_rand,
        dummy_nullifiers,
        rho_signed,
        padded_cmx,
        nf_signed,
        cmx_new,
        alpha,
        rseed_signed,
        rseed_output,
        gov_comm,
        total_note_value,
        address_index,
        padded_note_secrets,
        pczt_sighash,
        Some(tx1_effects),
        Some(rk),
        Some(gov_nullifiers_blob.as_slice()),
    )
}

fn store_delegation_data_inner(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    van_comm_rand: &[u8],
    dummy_nullifiers: &[Vec<u8>],
    rho_signed: &[u8],
    padded_cmx: &[Vec<u8>],
    nf_signed: &[u8],
    cmx_new: &[u8],
    alpha: &[u8],
    rseed_signed: &[u8],
    rseed_output: &[u8],
    gov_comm: &[u8],
    total_note_value: u64,
    address_index: u32,
    padded_note_secrets: &[(Vec<u8>, Vec<u8>)],
    pczt_sighash: &[u8],
    tx1_effects: Option<&[u8]>,
    rk: Option<&[u8]>,
    gov_nullifiers_blob: Option<&[u8]>,
) -> Result<(), VotingError> {
    if let Some(tx1_effects) = tx1_effects {
        crate::tx1::validate_tx1_effects(tx1_effects)?;
    }

    // Serialize padded-note nullifiers as a flat byte blob: [nf0 (32 bytes) | nf1 | nf2 | ...].
    // Length 0 means no padding was needed because all note slots were real.
    let dummy_blob: Vec<u8> = dummy_nullifiers
        .iter()
        .flat_map(|n| n.iter().copied())
        .collect();

    // Same flat-blob encoding for padded cmx values.
    let padded_blob: Vec<u8> = padded_cmx.iter().flat_map(|c| c.iter().copied()).collect();

    // Serialize padded_note_secrets as flat blob: N * 64 bytes (rho[32] || rseed[32] per entry).
    let secrets_blob = encode_padded_note_secrets(padded_note_secrets);

    let existing: Option<(Option<Vec<u8>>, Option<Vec<u8>>, Option<Vec<u8>>)> = conn
        .query_row(
            "SELECT padded_note_secrets, pczt_sighash, tx1_effects FROM bundles \
             WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
            },
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to load existing delegation data: {}", e),
        })?;
    let Some((existing_secrets, existing_sighash, existing_tx1_effects)) = existing else {
        return Err(VotingError::InvalidInput {
            message: format!(
                "bundle not found: round={}, bundle={}",
                round_id, bundle_index
            ),
        });
    };
    if let Some(existing_secrets) = existing_secrets {
        if existing_secrets != secrets_blob {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "refusing to overwrite padded_note_secrets for round={}, bundle={}",
                    round_id, bundle_index
                ),
            });
        }
    }
    if let Some(existing_sighash) = existing_sighash {
        if existing_sighash != pczt_sighash {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "refusing to overwrite pczt_sighash for round={}, bundle={}",
                    round_id, bundle_index
                ),
            });
        }
    }
    if let (Some(existing_tx1_effects), Some(tx1_effects)) = (existing_tx1_effects, tx1_effects) {
        if existing_tx1_effects != tx1_effects {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "refusing to overwrite tx1_effects for round={}, bundle={}",
                    round_id, bundle_index
                ),
            });
        }
    }

    let rows = conn
        .execute(
            "UPDATE bundles SET van_comm_rand = :rand, dummy_nullifiers = :dummies, \
             rho_signed = :rho, padded_note_data = :padded, nf_signed = :nf_signed, \
             cmx_new = :cmx_new, alpha = :alpha, rseed_signed = :rseed_signed, \
             rseed_output = :rseed_output, gov_comm = :gov_comm, \
             total_note_value = :total_note_value, address_index = :address_index, \
             padded_note_secrets = COALESCE(padded_note_secrets, :secrets), \
             pczt_sighash = COALESCE(pczt_sighash, :sighash), \
             tx1_effects = COALESCE(tx1_effects, :tx1_effects), \
             rk = COALESCE(:rk, rk), \
             gov_nullifiers_blob = COALESCE(:gov_nullifiers_blob, gov_nullifiers_blob) \
             WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
            named_params! {
                ":rand": van_comm_rand,
                ":dummies": dummy_blob,
                ":rho": rho_signed,
                ":padded": padded_blob,
                ":nf_signed": nf_signed,
                ":cmx_new": cmx_new,
                ":alpha": alpha,
                ":rseed_signed": rseed_signed,
                ":rseed_output": rseed_output,
                ":gov_comm": gov_comm,
                ":total_note_value": total_note_value as i64,
                ":address_index": address_index as i64,
                ":secrets": secrets_blob,
                ":sighash": pczt_sighash,
                ":tx1_effects": tx1_effects,
                ":rk": rk,
                ":gov_nullifiers_blob": gov_nullifiers_blob,
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to store delegation data: {}", e),
        })?;

    // If no rows were updated, the bundle doesn't exist.
    if rows == 0 {
        return Err(VotingError::InvalidInput {
            message: format!(
                "bundle not found: round={}, bundle={}",
                round_id, bundle_index
            ),
        });
    }

    Ok(())
}

/// Load nf_signed (signed note nullifier, 32 bytes) for a bundle.
pub fn load_nf_signed(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<Vec<u8>, VotingError> {
    conn.query_row(
        "SELECT nf_signed FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
        |row| row.get(0),
    )
    .map_err(|e| VotingError::InvalidInput {
        message: format!("no nf_signed for round={}, bundle={} ({})", round_id, bundle_index, e),
    })
}

/// Load cmx_new (output note commitment, 32 bytes) for a bundle.
pub fn load_cmx_new(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<Vec<u8>, VotingError> {
    conn.query_row(
        "SELECT cmx_new FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
        |row| row.get(0),
    )
    .map_err(|e| VotingError::InvalidInput {
        message: format!("no cmx_new for round={}, bundle={} ({})", round_id, bundle_index, e),
    })
}

/// Load alpha (spend auth randomizer scalar, 32 bytes) for a bundle.
pub fn load_alpha(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<Vec<u8>, VotingError> {
    conn.query_row(
        "SELECT alpha FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
        |row| row.get(0),
    )
    .map_err(|e| VotingError::InvalidInput {
        message: format!("no alpha for round={}, bundle={} ({})", round_id, bundle_index, e),
    })
}

/// Load signed note rseed (32 bytes) for a bundle.
pub fn load_rseed_signed(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<Vec<u8>, VotingError> {
    conn.query_row(
        "SELECT rseed_signed FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
        |row| row.get(0),
    )
    .map_err(|e| VotingError::InvalidInput {
        message: format!("no rseed_signed for round={}, bundle={} ({})", round_id, bundle_index, e),
    })
}

/// Load output note rseed (32 bytes) for a bundle.
pub fn load_rseed_output(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<Vec<u8>, VotingError> {
    conn.query_row(
        "SELECT rseed_output FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
        |row| row.get(0),
    )
    .map_err(|e| VotingError::InvalidInput {
        message: format!("no rseed_output for round={}, bundle={} ({})", round_id, bundle_index, e),
    })
}

/// Write padded note secrets once for a bundle, leaving an existing value intact.
pub fn store_padded_note_secrets_if_absent(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    padded_note_secrets: &[(Vec<u8>, Vec<u8>)],
) -> Result<(), VotingError> {
    let secrets_blob = encode_padded_note_secrets(padded_note_secrets);
    let rows = conn
        .execute(
            "UPDATE bundles SET padded_note_secrets = :secrets \
             WHERE round_id = :round_id AND wallet_id = :wallet_id \
               AND bundle_index = :bundle_index AND padded_note_secrets IS NULL",
            named_params! {
                ":secrets": secrets_blob,
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to store padded_note_secrets: {}", e),
        })?;

    if rows == 0 {
        let exists = conn
            .query_row(
                "SELECT 1 FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
                named_params! {
                    ":round_id": round_id,
                    ":wallet_id": wallet_id,
                    ":bundle_index": bundle_index as i64,
                },
                |_| Ok(()),
            )
            .optional()
            .map_err(|e| VotingError::Internal {
                message: format!("failed to check bundle existence: {}", e),
            })?
            .is_some();
        if !exists {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "bundle not found: round={}, bundle={}",
                    round_id, bundle_index
                ),
            });
        }
    }

    Ok(())
}

/// Load padded note secrets if they have already been initialized for a bundle.
pub fn load_padded_note_secrets_optional(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<Option<Vec<(Vec<u8>, Vec<u8>)>>, VotingError> {
    let blob: Option<Vec<u8>> = conn
        .query_row(
            "SELECT padded_note_secrets FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
            |row| row.get(0),
        )
        .map_err(|e| VotingError::InvalidInput {
            message: format!("no padded_note_secrets for round={}, bundle={} ({})", round_id, bundle_index, e),
        })?;

    blob.map(decode_padded_note_secrets).transpose()
}

/// Load padded note secrets (rho + rseed pairs) for Phase 2 randomness threading.
/// Returns Vec of (rho[32], rseed[32]) pairs. Deserializes from flat 64-byte-per-entry blob.
pub fn load_padded_note_secrets(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<Vec<(Vec<u8>, Vec<u8>)>, VotingError> {
    load_padded_note_secrets_optional(conn, round_id, wallet_id, bundle_index)?.ok_or_else(|| {
        VotingError::InvalidInput {
            message: format!(
                "no padded_note_secrets for round={}, bundle={}",
                round_id, bundle_index
            ),
        }
    })
}

/// Load the ZIP-244 sighash extracted from the PCZT (32 bytes).
pub fn load_pczt_sighash(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<Vec<u8>, VotingError> {
    conn.query_row(
        "SELECT pczt_sighash FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
        |row| row.get(0),
    )
    .map_err(|e| VotingError::InvalidInput {
        message: format!("no pczt_sighash for round={}, bundle={} ({})", round_id, bundle_index, e),
    })
}

/// Load the versioned Ironwood TX1 effecting data persisted at PCZT setup.
pub fn load_tx1_effects(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<Vec<u8>, VotingError> {
    let effects: Vec<u8> = conn
        .query_row(
            "SELECT tx1_effects FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
            |row| row.get(0),
        )
        .map_err(|e| VotingError::InvalidInput {
            message: format!(
                "no tx1_effects for round={}, bundle={} ({})",
                round_id, bundle_index, e
            ),
        })?;
    crate::tx1::validate_tx1_effects(&effects)?;
    Ok(effects)
}

/// Load the VAN blinding factor for a bundle. Needed as a private witness in ZKP #2.
pub fn load_van_comm_rand(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<Vec<u8>, VotingError> {
    conn.query_row(
        "SELECT van_comm_rand FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
        |row| row.get(0),
    )
    .map_err(|e| VotingError::InvalidInput {
        message: format!("no van_comm_rand for round={}, bundle={} ({})", round_id, bundle_index, e),
    })
}

/// Load dummy nullifiers for padded note slots. Returns 0-3 entries of 32 bytes each.
/// Deserializes the flat blob back into individual 32-byte nullifiers.
pub fn load_dummy_nullifiers(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<Vec<Vec<u8>>, VotingError> {
    let blob: Vec<u8> = conn
        .query_row(
            "SELECT dummy_nullifiers FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
            |row| row.get(0),
        )
        .map_err(|e| VotingError::InvalidInput {
            message: format!("no dummy_nullifiers for round={}, bundle={} ({})", round_id, bundle_index, e),
        })?;

    // Split the flat blob back into 32-byte chunks, one per dummy nullifier.
    if blob.len() % 32 != 0 {
        return Err(VotingError::Internal {
            message: format!(
                "corrupt dummy_nullifiers blob: length {} is not a multiple of 32",
                blob.len()
            ),
        });
    }
    Ok(blob.chunks_exact(32).map(|c| c.to_vec()).collect())
}

// --- Rho & Padded Note Data ---

/// Load rho_signed for a bundle (32-byte constrained rho).
pub fn load_rho_signed(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<Vec<u8>, VotingError> {
    conn.query_row(
        "SELECT rho_signed FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
        |row| row.get(0),
    )
    .map_err(|e| VotingError::InvalidInput {
        message: format!("no rho_signed for round={}, bundle={} ({})", round_id, bundle_index, e),
    })
}

/// Load padded note cmx data. Returns 0-3 entries of 32 bytes each.
pub fn load_padded_cmx(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<Vec<Vec<u8>>, VotingError> {
    let blob: Vec<u8> = conn
        .query_row(
            "SELECT padded_note_data FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
            |row| row.get(0),
        )
        .map_err(|e| VotingError::InvalidInput {
            message: format!("no padded_note_data for round={}, bundle={} ({})", round_id, bundle_index, e),
        })?;

    if blob.len() % 32 != 0 {
        return Err(VotingError::Internal {
            message: format!(
                "corrupt padded_note_data blob: length {} is not a multiple of 32",
                blob.len()
            ),
        });
    }
    Ok(blob.chunks_exact(32).map(|c| c.to_vec()).collect())
}

// --- ZKP #2 inputs ---

/// Data from delegation that ZKP #2 needs.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Zkp2DelegationData {
    pub gov_comm_rand: Vec<u8>,
    pub total_note_value: u64,
    pub address_index: u32,
    pub ea_pk: Vec<u8>,
    pub voting_round_id: String,
    /// Current proposal authority bitmask (starts at 0xFFFF, decremented per submitted vote).
    /// Bit `i` is set iff the voter has not yet cast a vote for proposal `i`.
    /// Since proposal IDs are 1-indexed (matching on-chain IDs), bit 0 is never
    /// cleared and acts as a structural invariant — it corresponds to the circuit's
    /// sentinel value rejected by the non-zero gate.
    pub proposal_authority: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct VoteRowState {
    pub choice: i64,
    pub commitment: Option<Vec<u8>>,
    pub tx_hash: Option<String>,
    pub vc_tree_position: Option<i64>,
    pub commitment_bundle_json: Option<String>,
}

/// Snapshot of persisted state needed to prepare or validate a single vote draft.
///
/// `ballot_intent` is `None` when no intent row exists for the proposal.
/// `vote` is `None` when no votes row exists for `(bundle_index, proposal_id)`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct VotePreparationState {
    pub network: Network,
    pub zkp2: Zkp2DelegationData,
    pub van_position: u32,
    /// `(skipped, choice)` from `ballot_intent`, if present.
    pub ballot_intent: Option<(bool, Option<u32>)>,
    pub vote: Option<VoteRowState>,
}

/// Initial authority bitmask: all 16 bits set. Bit 0 is the dead sentinel
/// (proposal_id=0 is rejected by the circuit); bits 1–15 are the usable slots.
const MAX_PROPOSAL_AUTHORITY: u64 = 65535;

/// Load all fields ZKP #2 needs from the bundles table (persisted during delegation).
/// Computes proposal_authority from submitted votes — each submitted vote clears its
/// proposal's bit, so the next vote's VAN reconstruction matches what's in the VC tree.
pub fn load_zkp2_inputs(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<Zkp2DelegationData, VotingError> {
    let data = conn.query_row(
        "SELECT b.van_comm_rand, b.total_note_value, b.address_index, r.ea_pk, r.round_id \
         FROM bundles b JOIN rounds r ON b.round_id = r.round_id AND b.wallet_id = r.wallet_id \
         WHERE b.round_id = :round_id AND b.wallet_id = :wallet_id AND b.bundle_index = :bundle_index",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
        |row| {
            Ok(Zkp2DelegationData {
                gov_comm_rand: row.get(0)?,
                total_note_value: row.get::<_, i64>(1)? as u64,
                address_index: row.get::<_, i64>(2)? as u32,
                ea_pk: row.get(3)?,
                voting_round_id: row.get(4)?,
                proposal_authority: 0, // computed below
            })
        },
    )
    .map_err(|e| VotingError::InvalidInput {
        message: format!("failed to load ZKP2 inputs for round={}, bundle={} ({})", round_id, bundle_index, e),
    })?;

    // Compute current proposal_authority by clearing bits for votes with a
    // durable tx hash for THIS bundle specifically.
    let mut authority = MAX_PROPOSAL_AUTHORITY;
    let mut stmt = conn
        .prepare("SELECT proposal_id FROM votes WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index AND tx_hash IS NOT NULL")
        .map_err(|e| VotingError::Internal {
            message: format!("failed to prepare proposal_authority query: {}", e),
        })?;
    let rows = stmt
        .query_map(
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
            |row| row.get::<_, i64>(0),
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to query submitted votes: {}", e),
        })?;
    for row in rows {
        let pid = row.map_err(|e| VotingError::Internal {
            message: format!("failed to read proposal_id: {}", e),
        })? as u64;
        authority &= !(1u64 << pid);
    }

    Ok(Zkp2DelegationData {
        proposal_authority: authority,
        ..data
    })
}

/// Load the read-only snapshot used before preparing or committing a vote.
///
/// Returns network, ZKP2 delegation inputs (including live `proposal_authority`),
/// the bundle's confirmed VAN leaf position, optional ballot intent for
/// `proposal_id`, and optional existing vote-row state for
/// `(bundle_index, proposal_id)`.
///
/// Missing ballot-intent or votes rows yield `None` fields; they are not errors.
///
/// # Errors
///
/// - [`VotingError::InvalidInput`] if the round/bundle is missing, or the VAN
///   leaf position is unset.
/// - [`VotingError::Internal`] on SQL failures loading ballot intent or vote state.
pub(crate) fn load_vote_preparation_state(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<VotePreparationState, VotingError> {
    let network = load_round_network(conn, round_id, wallet_id)?;
    let zkp2 = load_zkp2_inputs(conn, round_id, wallet_id, bundle_index)?;
    let van_position = load_van_position(conn, round_id, wallet_id, bundle_index)?;
    let ballot_intent = conn
        .query_row(
            "SELECT skipped, choice FROM ballot_intent
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND proposal_id = :proposal_id",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":proposal_id": proposal_id as i64,
            },
            |row| {
                Ok((
                    row.get::<_, i64>(0)? != 0,
                    row.get::<_, Option<i64>>(1)?.map(|choice| choice as u32),
                ))
            },
        )
        .optional()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to load ballot intent before vote preparation: {e}"),
        })?;
    let vote = load_vote_row_state(conn, round_id, wallet_id, bundle_index, proposal_id)?;

    Ok(VotePreparationState {
        network,
        zkp2,
        van_position,
        ballot_intent,
        vote,
    })
}

pub(crate) fn load_vote_row_state(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<Option<VoteRowState>, VotingError> {
    conn.query_row(
        "SELECT choice, commitment, tx_hash, vc_tree_position, commitment_bundle_json
             FROM votes
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
            ":proposal_id": proposal_id as i64,
        },
        |row| {
            Ok(VoteRowState {
                choice: row.get(0)?,
                commitment: row.get(1)?,
                tx_hash: row.get(2)?,
                vc_tree_position: row.get(3)?,
                commitment_bundle_json: row.get(4)?,
            })
        },
    )
    .optional()
    .map_err(|e| VotingError::Internal {
        message: format!("failed to load vote state before vote preparation: {e}"),
    })
}

// --- VAN leaf position ---

/// Store the VAN leaf position after delegation TX is confirmed on chain.
///
/// Cast-vote confirmations should use `confirmation::confirm_vote_submission`
/// so the vote hash, successor VAN position, and VC position are recorded
/// atomically.
pub fn store_van_position(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    position: u32,
) -> Result<(), VotingError> {
    let rows = conn
        .execute(
            "UPDATE bundles SET van_leaf_position = :position WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
            named_params! {
                ":position": position as i64,
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to store VAN position: {}", e),
        })?;
    if rows == 0 {
        return Err(VotingError::InvalidInput {
            message: format!(
                "bundle not found: round={}, bundle={}",
                round_id, bundle_index
            ),
        });
    }
    Ok(())
}

/// Load the VAN leaf position for witness generation.
pub fn load_van_position(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<u32, VotingError> {
    conn.query_row(
        "SELECT van_leaf_position FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
        |row| row.get::<_, Option<i64>>(0),
    )
    .map_err(|e| VotingError::InvalidInput {
        message: format!("no van_leaf_position for round={}, bundle={} ({})", round_id, bundle_index, e),
    })?
    .map(|v| v as u32)
    .ok_or_else(|| VotingError::InvalidInput {
        message: format!("van_leaf_position not yet set for round={}, bundle={}", round_id, bundle_index),
    })
}

/// One confirmed VAN position that must be retained during vote-tree sync.
pub(crate) struct VanTreeEntry {
    pub bundle_index: u32,
    pub position: u32,
    /// Present only while the delegation VAN is still the bundle's current VAN.
    pub expected_delegation_van: Option<pallas::Base>,
}

/// Loads confirmed VAN positions and expected delegation VANs that remain
/// current.
///
/// A submitted vote replaces the delegation VAN with a successor commitment,
/// so only bundles without a submitted vote can be checked against `gov_comm`.
pub(crate) fn load_van_tree_entries(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<Vec<VanTreeEntry>, VotingError> {
    let mut stmt = conn
        .prepare(
            "SELECT b.bundle_index, b.van_leaf_position, b.gov_comm,
                    EXISTS (
                        SELECT 1 FROM votes v
                        WHERE v.round_id = b.round_id
                          AND v.wallet_id = b.wallet_id
                          AND v.bundle_index = b.bundle_index
                          AND v.tx_hash IS NOT NULL
                    )
             FROM bundles b
             WHERE b.round_id = :round_id
               AND b.wallet_id = :wallet_id
               AND b.van_leaf_position IS NOT NULL
             ORDER BY b.bundle_index",
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to prepare VAN tree entries query: {e}"),
        })?;
    let rows = stmt
        .query_map(
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, Option<Vec<u8>>>(2)?,
                    row.get::<_, i64>(3)? != 0,
                ))
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to query VAN tree entries: {e}"),
        })?;

    rows.map(|row| {
        let (bundle_index, position, commitment, has_submitted_vote) =
            row.map_err(|e| VotingError::Internal {
                message: format!("failed to read VAN tree entry: {e}"),
            })?;
        let bundle_index = u32::try_from(bundle_index).map_err(|_| VotingError::Internal {
            message: "stored VAN bundle index does not fit in u32".to_string(),
        })?;
        let position = u32::try_from(position).map_err(|_| VotingError::Internal {
            message: format!("stored VAN position for bundle {bundle_index} does not fit in u32"),
        })?;
        let expected_delegation_van = if has_submitted_vote {
            None
        } else {
            let commitment = commitment.ok_or_else(|| VotingError::Internal {
                message: format!(
                    "confirmed delegation bundle {bundle_index} is missing its VAN commitment"
                ),
            })?;
            Some(field_from_bytes(
                &commitment,
                &format!("bundle {bundle_index} VAN commitment"),
            )?)
        };
        Ok(VanTreeEntry {
            bundle_index,
            position,
            expected_delegation_van,
        })
    })
    .collect()
}

// --- Delegation proof result fields ---

fn require_matching_stored_field(
    stored: Option<&[u8]>,
    requested: &[u8],
    field: &str,
) -> Result<(), VotingError> {
    if let Some(stored) = stored {
        if stored != requested {
            return Err(VotingError::InvalidInput {
                message: format!("delegation proof result {field} does not match stored PCZT data"),
            });
        }
    }

    Ok(())
}

/// Persist public inputs from DelegationProofResult after proof generation.
/// If PCZT-derived values already exist, the proof result must reproduce them.
pub fn store_proof_result_fields(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    rk: &[u8],
    gov_nullifiers: &[Vec<u8>],
    nf_signed: &[u8],
    cmx_new: &[u8],
) -> Result<(), VotingError> {
    store_proof_result_fields_inner(
        conn,
        round_id,
        wallet_id,
        bundle_index,
        rk,
        gov_nullifiers,
        nf_signed,
        cmx_new,
        None,
    )
}

/// Persist proof public inputs and compare the proof VAN against the stored PCZT VAN.
pub(crate) fn store_proof_result_fields_with_van_comm(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    rk: &[u8],
    gov_nullifiers: &[Vec<u8>],
    nf_signed: &[u8],
    cmx_new: &[u8],
    van_comm: &[u8],
) -> Result<(), VotingError> {
    store_proof_result_fields_inner(
        conn,
        round_id,
        wallet_id,
        bundle_index,
        rk,
        gov_nullifiers,
        nf_signed,
        cmx_new,
        Some(van_comm),
    )
}

fn store_proof_result_fields_inner(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    rk: &[u8],
    gov_nullifiers: &[Vec<u8>],
    nf_signed: &[u8],
    cmx_new: &[u8],
    van_comm: Option<&[u8]>,
) -> Result<(), VotingError> {
    // Serialize gov_nullifiers as flat blob: [nf0 (32 bytes) | ... | nf4]
    let gov_nullifiers_blob = encode_gov_nullifiers_blob(gov_nullifiers);

    let (stored_rk, stored_gov_nullifiers, stored_nf_signed, stored_cmx_new, stored_gov_comm): (
        Option<Vec<u8>>,
        Option<Vec<u8>>,
        Option<Vec<u8>>,
        Option<Vec<u8>>,
        Option<Vec<u8>>,
    ) = conn
        .query_row(
            "SELECT rk, gov_nullifiers_blob, nf_signed, cmx_new, gov_comm \
             FROM bundles \
             WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
            },
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?, row.get(4)?)),
        )
        .map_err(|e| VotingError::InvalidInput {
            message: format!(
                "bundle not found: round={}, bundle={} ({})",
                round_id, bundle_index, e
            ),
        })?;

    require_matching_stored_field(stored_rk.as_deref(), rk, "rk")?;
    require_matching_stored_field(
        stored_gov_nullifiers.as_deref(),
        &gov_nullifiers_blob,
        "gov_nullifiers",
    )?;
    require_matching_stored_field(stored_nf_signed.as_deref(), nf_signed, "nf_signed")?;
    require_matching_stored_field(stored_cmx_new.as_deref(), cmx_new, "cmx_new")?;
    if let Some(van_comm) = van_comm {
        require_matching_stored_field(stored_gov_comm.as_deref(), van_comm, "van_comm")?;
    }

    let rows = conn
        .execute(
            "UPDATE bundles SET rk = :rk, gov_nullifiers_blob = :gov_nullifiers_blob, \
             nf_signed = :nf_signed, cmx_new = :cmx_new \
             WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
            named_params! {
                ":rk": rk,
                ":gov_nullifiers_blob": gov_nullifiers_blob,
                ":nf_signed": nf_signed,
                ":cmx_new": cmx_new,
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to store proof result fields: {}", e),
        })?;

    if rows == 0 {
        return Err(VotingError::InvalidInput {
            message: format!(
                "bundle not found: round={}, bundle={}",
                round_id, bundle_index
            ),
        });
    }

    Ok(())
}

/// Raw delegation data loaded from DB for submission reconstruction.
pub struct DelegationDbFields {
    pub proof: Vec<u8>,
    pub rk: Vec<u8>,
    pub nf_signed: Vec<u8>,
    pub cmx_new: Vec<u8>,
    pub gov_comm: Vec<u8>,
    pub gov_nullifiers: Vec<Vec<u8>>,
    pub alpha: Vec<u8>,
    pub vote_round_id: String,
    pub tx1_effects: Vec<u8>,
}

/// Load all fields needed to reconstruct the chain-ready delegation TX payload.
pub fn load_delegation_submission_data(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<DelegationDbFields, VotingError> {
    let (
        proof_bytes,
        rk,
        nf_signed,
        cmx_new,
        gov_comm,
        gov_nullifiers_blob,
        alpha,
        vote_round_id,
        tx1_effects,
    ): (
        Vec<u8>,
        Vec<u8>,
        Vec<u8>,
        Vec<u8>,
        Vec<u8>,
        Vec<u8>,
        Vec<u8>,
        String,
        Vec<u8>,
    ) = conn
        .query_row(
            "SELECT p.proof, b.rk, b.nf_signed, b.cmx_new, b.gov_comm, \
             b.gov_nullifiers_blob, b.alpha, b.round_id, b.tx1_effects \
             FROM bundles b JOIN proofs p ON b.round_id = p.round_id AND b.bundle_index = p.bundle_index AND b.wallet_id = p.wallet_id \
             WHERE b.round_id = :round_id AND b.wallet_id = :wallet_id AND b.bundle_index = :bundle_index AND p.success = 1",
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                    row.get(5)?,
                    row.get(6)?,
                    row.get(7)?,
                    row.get(8)?,
                ))
            },
        )
        .map_err(|e| VotingError::InvalidInput {
            message: format!(
                "failed to load delegation submission data for round={}, bundle={} ({})",
                round_id, bundle_index, e
            ),
        })?;

    // Deserialize gov_nullifiers from flat blob back to Vec<Vec<u8>>
    if gov_nullifiers_blob.len() % 32 != 0 {
        return Err(VotingError::Internal {
            message: format!(
                "corrupt gov_nullifiers_blob: length {} is not a multiple of 32",
                gov_nullifiers_blob.len()
            ),
        });
    }
    let gov_nullifiers: Vec<Vec<u8>> = gov_nullifiers_blob
        .chunks_exact(32)
        .map(|c| c.to_vec())
        .collect();
    crate::tx1::validate_tx1_effects(&tx1_effects)?;

    Ok(DelegationDbFields {
        proof: proof_bytes,
        rk,
        nf_signed,
        cmx_new,
        gov_comm,
        gov_nullifiers,
        alpha,
        vote_round_id,
        tx1_effects,
    })
}

// --- Cached Tree State ---

pub fn store_tree_state(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    snapshot_height: u64,
    tree_state: &[u8],
) -> Result<(), VotingError> {
    conn.execute(
        "INSERT OR REPLACE INTO cached_tree_state (round_id, wallet_id, snapshot_height, tree_state)
         VALUES (:round_id, :wallet_id, :snapshot_height, :tree_state)",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":snapshot_height": snapshot_height as i64,
            ":tree_state": tree_state,
        },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to store tree state: {}", e),
    })?;
    Ok(())
}

pub fn load_tree_state(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<Vec<u8>, VotingError> {
    conn.query_row(
        "SELECT tree_state FROM cached_tree_state WHERE round_id = :round_id AND wallet_id = :wallet_id",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
        |row| row.get(0),
    )
    .map_err(|e| VotingError::InvalidInput {
        message: format!("no cached tree state for round: {} ({})", round_id, e),
    })
}

// --- Witnesses (Merkle inclusion proofs for shielded notes) ---

/// Check if witnesses are already cached for a bundle.
pub fn has_witnesses(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<bool, VotingError> {
    witness_count(conn, round_id, wallet_id, bundle_index).map(|count| count > 0)
}

/// Count cached witnesses for a bundle.
pub fn witness_count(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<usize, VotingError> {
    conn.query_row(
        "SELECT COUNT(*) FROM witnesses WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
        |row| row.get::<_, i64>(0).map(|c| c as usize),
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to check witnesses: {}", e),
    })
}

/// Store witness data for multiple notes in a bundle.
/// Each WitnessData's auth_path (Vec<Vec<u8>>) is serialized as a flat 1024-byte blob
/// (32 levels × 32 bytes each).
pub fn store_witnesses(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    witnesses: &[WitnessData],
) -> Result<(), VotingError> {
    insert_witnesses(conn, round_id, wallet_id, bundle_index, witnesses)
}

fn require_witness_positions_match_bundle(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    witnesses: &[WitnessData],
) -> Result<(), VotingError> {
    let mut expected = load_bundle_note_positions(conn, round_id, wallet_id, bundle_index)?;
    let mut actual = witnesses.iter().map(|w| w.position).collect::<Vec<_>>();
    expected.sort_unstable();
    actual.sort_unstable();

    if expected != actual {
        return Err(VotingError::InvalidInput {
            message: format!(
                "witness positions do not match bundle note positions for round={}, bundle={}: expected {:?}, got {:?}",
                round_id, bundle_index, expected, actual
            ),
        });
    }

    Ok(())
}

fn insert_witnesses(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    witnesses: &[WitnessData],
) -> Result<(), VotingError> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;

    for w in witnesses {
        // Serialize auth_path as flat blob: 32 × 32 = 1024 bytes
        let auth_blob: Vec<u8> = w.auth_path.iter().flat_map(|h| h.iter().copied()).collect();

        conn.execute(
            "INSERT OR REPLACE INTO witnesses (round_id, wallet_id, bundle_index, note_position, note_commitment, root, auth_path, created_at)
             VALUES (:round_id, :wallet_id, :bundle_index, :position, :commitment, :root, :auth_path, :created_at)",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
                ":position": w.position as i64,
                ":commitment": w.note_commitment,
                ":root": w.root,
                ":auth_path": auth_blob,
                ":created_at": now,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to store witness for position {}: {}", w.position, e),
        })?;
    }

    Ok(())
}

/// Atomically replace all cached witnesses for a bundle.
pub fn replace_bundle_witnesses(
    conn: &mut Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    witnesses: &[WitnessData],
) -> Result<(), VotingError> {
    let tx = conn
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|e| VotingError::Internal {
            message: format!("failed to begin witness replacement transaction: {}", e),
        })?;
    require_witness_positions_match_bundle(&tx, round_id, wallet_id, bundle_index, witnesses)?;

    tx.execute(
        "DELETE FROM witnesses
         WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
        },
    )
    .map_err(|e| VotingError::Internal {
        message: format!(
            "failed to clear witnesses for bundle {}: {}",
            bundle_index, e
        ),
    })?;

    insert_witnesses(&tx, round_id, wallet_id, bundle_index, witnesses)?;

    tx.commit().map_err(|e| VotingError::Internal {
        message: format!("failed to commit witness replacement: {}", e),
    })
}

/// Load cached witnesses for a bundle, ordered by position.
pub fn load_witnesses(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<Vec<crate::types::WitnessData>, VotingError> {
    let mut stmt = conn
        .prepare(
            "SELECT note_position, note_commitment, root, auth_path FROM witnesses
             WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index ORDER BY note_position",
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to prepare load_witnesses: {}", e),
        })?;

    let witnesses = stmt
        .query_map(
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
            |row| {
                let position: i64 = row.get(0)?;
                let note_commitment: Vec<u8> = row.get(1)?;
                let root: Vec<u8> = row.get(2)?;
                let auth_blob: Vec<u8> = row.get(3)?;
                Ok((position as u64, note_commitment, root, auth_blob))
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to load witnesses: {}", e),
        })?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to collect witnesses: {}", e),
        })?;

    witnesses
        .into_iter()
        .map(|(position, note_commitment, root, auth_blob)| {
            // Deserialize auth_path from flat blob back to Vec<Vec<u8>>
            if auth_blob.len() != 32 * 32 {
                return Err(VotingError::Internal {
                    message: format!(
                        "corrupt auth_path blob for position {}: expected 1024 bytes, got {}",
                        position,
                        auth_blob.len()
                    ),
                });
            }
            let auth_path: Vec<Vec<u8>> = auth_blob.chunks_exact(32).map(|c| c.to_vec()).collect();

            Ok(crate::types::WitnessData {
                note_commitment,
                position,
                root,
                auth_path,
            })
        })
        .collect()
}

// --- PIR-backed IMT non-membership proof cache ---

fn field_to_bytes(value: pallas::Base) -> Vec<u8> {
    value.to_repr().to_vec()
}

fn field_from_bytes(bytes: &[u8], name: &str) -> Result<pallas::Base, VotingError> {
    let arr: [u8; 32] = bytes.try_into().map_err(|_| VotingError::Internal {
        message: format!("{name} must be 32 bytes, got {}", bytes.len()),
    })?;
    Option::from(pallas::Base::from_repr(arr)).ok_or_else(|| VotingError::Internal {
        message: format!("{name} is not a valid Pallas field element"),
    })
}

fn fields_to_blob(values: impl IntoIterator<Item = pallas::Base>) -> Vec<u8> {
    values
        .into_iter()
        .flat_map(|value| field_to_bytes(value).into_iter())
        .collect()
}

fn fields_from_blob<const N: usize>(
    blob: &[u8],
    name: &str,
) -> Result<[pallas::Base; N], VotingError> {
    let expected_len = N * 32;
    if blob.len() != expected_len {
        return Err(VotingError::Internal {
            message: format!("{name} must be {expected_len} bytes, got {}", blob.len()),
        });
    }

    let fields: Vec<pallas::Base> = blob
        .chunks_exact(32)
        .enumerate()
        .map(|(idx, chunk)| field_from_bytes(chunk, &format!("{name}[{idx}]")))
        .collect::<Result<_, _>>()?;

    fields.try_into().map_err(|_| VotingError::Internal {
        message: format!("{name} did not decode to {N} field elements"),
    })
}

// --- Bundle-independent PIR proof cache ---
//
// Rows here are keyed by (wallet_id, network, root, nullifier) with no round or
// bundle attached, so proofs can be warmed before any bundle exists and the
// same nullifier can hold proofs for several IMT snapshots at once.

pub(crate) const PIR_PROOF_CACHE_TTL_SECS: i64 = 28 * 24 * 60 * 60;

/// Deletes PIR proof cache rows created more than four weeks ago.
///
/// This is intentionally based on `created_at`, not `updated_at`, so repeatedly
/// storing the same cache key does not extend its lifetime indefinitely.
pub fn prune_expired_pir_cache(conn: &Connection) -> Result<usize, VotingError> {
    conn.execute(
        "DELETE FROM pir_proof_cache
         WHERE created_at < strftime('%s','now') - :ttl",
        named_params! { ":ttl": PIR_PROOF_CACHE_TTL_SECS },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to prune expired PIR proof cache rows: {e}"),
    })
}

/// Stores a PIR proof under `(wallet_id, network, proof.root, nullifier)`,
/// updating the existing row in place when that exact key is already present.
pub fn store_pir_cache_proof(
    conn: &Connection,
    wallet_id: &str,
    network: Network,
    nullifier: &[u8],
    proof: &pir_client::ImtProofData,
) -> Result<(), VotingError> {
    let root = field_to_bytes(proof.root);
    let nf_bounds = fields_to_blob(proof.nf_bounds);
    let path = fields_to_blob(proof.path);

    conn.execute(
        "INSERT INTO pir_proof_cache (wallet_id, network, nullifier, root, nf_bounds, leaf_pos, path, created_at, updated_at)
         VALUES (:wallet_id, :network, :nullifier, :root, :nf_bounds, :leaf_pos, :path, strftime('%s','now'), strftime('%s','now'))
         ON CONFLICT(wallet_id, network, root, nullifier)
         DO UPDATE SET nf_bounds = :nf_bounds, leaf_pos = :leaf_pos, path = :path, updated_at = strftime('%s','now')",
        named_params! {
            ":wallet_id": wallet_id,
            ":network": network_to_storage(network),
            ":nullifier": nullifier,
            ":root": root,
            ":nf_bounds": nf_bounds,
            ":leaf_pos": proof.leaf_pos as i64,
            ":path": path,
        },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to store cached PIR proof: {e}"),
    })?;
    Ok(())
}

/// Raw `pir_proof_cache` blobs for one `(wallet_id, network, root, nullifier)`.
///
/// Decoding is separate from the SQLite load so a corrupt row can be treated as
/// a cache miss (and overwritten) without looking like a storage failure.
pub struct PirCacheRow {
    pub nf_bounds: Vec<u8>,
    pub leaf_pos: i64,
    pub path: Vec<u8>,
    root: Vec<u8>,
}

impl PirCacheRow {
    /// Decode the stored blobs into a PIR proof. Fails only on corrupt bytes.
    pub fn decode(&self) -> Result<pir_client::ImtProofData, VotingError> {
        Ok(pir_client::ImtProofData {
            root: field_from_bytes(&self.root, "pir_proof_cache.root")?,
            nf_bounds: fields_from_blob::<3>(&self.nf_bounds, "pir_proof_cache.nf_bounds")?,
            leaf_pos: u32::try_from(self.leaf_pos).map_err(|_| VotingError::Internal {
                message: format!("invalid cached PIR proof leaf_pos {}", self.leaf_pos),
            })?,
            path: fields_from_blob::<29>(&self.path, "pir_proof_cache.path")?,
        })
    }
}

/// Loads the raw cached PIR proof row for exactly `(wallet_id, network, root,
/// nullifier)`, or `None` when no proof is cached under that root.
///
/// Storage errors propagate; blob decode is left to [`PirCacheRow::decode`].
pub fn load_pir_cache_row(
    conn: &Connection,
    wallet_id: &str,
    network: Network,
    root: &[u8],
    nullifier: &[u8],
) -> Result<Option<PirCacheRow>, VotingError> {
    conn.query_row(
        "SELECT root, nf_bounds, leaf_pos, path FROM pir_proof_cache
         WHERE wallet_id = :wallet_id AND network = :network
           AND root = :root AND nullifier = :nullifier",
        named_params! {
            ":wallet_id": wallet_id,
            ":network": network_to_storage(network),
            ":root": root,
            ":nullifier": nullifier,
        },
        |row| {
            Ok(PirCacheRow {
                root: row.get(0)?,
                nf_bounds: row.get(1)?,
                leaf_pos: row.get(2)?,
                path: row.get(3)?,
            })
        },
    )
    .optional()
    .map_err(|e| VotingError::Internal {
        message: format!("failed to load cached PIR proof: {e}"),
    })
}

/// Loads and decodes the cached PIR proof for exactly `(wallet_id, network,
/// root, nullifier)`, or `None` when no proof is cached under that root.
pub fn load_pir_cache_proof(
    conn: &Connection,
    wallet_id: &str,
    network: Network,
    root: &[u8],
    nullifier: &[u8],
) -> Result<Option<pir_client::ImtProofData>, VotingError> {
    match load_pir_cache_row(conn, wallet_id, network, root, nullifier)? {
        Some(row) => Ok(Some(row.decode()?)),
        None => Ok(None),
    }
}

/// Lists every root the nullifier has a cached proof under on this network,
/// most recently updated first.
pub fn list_pir_cache_roots(
    conn: &Connection,
    wallet_id: &str,
    network: Network,
    nullifier: &[u8],
) -> Result<Vec<Vec<u8>>, VotingError> {
    conn.prepare(
        "SELECT root FROM pir_proof_cache
         WHERE wallet_id = :wallet_id AND network = :network AND nullifier = :nullifier
         ORDER BY updated_at DESC, root",
    )
    .and_then(|mut stmt| {
        stmt.query_map(
            named_params! {
                ":wallet_id": wallet_id,
                ":network": network_to_storage(network),
                ":nullifier": nullifier,
            },
            |row| row.get(0),
        )?
        .collect()
    })
    .map_err(|e| VotingError::Internal {
        message: format!("failed to list cached PIR proof roots: {e}"),
    })
}

// --- Proofs ---

pub fn store_proof(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proof_bytes: &[u8],
) -> Result<(), VotingError> {
    conn.execute(
        "INSERT INTO proofs (round_id, wallet_id, bundle_index, proof, success, created_at)
         VALUES (:round_id, :wallet_id, :bundle_index, :proof, 1, strftime('%s','now'))
         ON CONFLICT(round_id, wallet_id, bundle_index) DO UPDATE SET proof = :proof, success = 1",
        named_params! {
            ":proof": proof_bytes,
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
        },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to store proof: {}", e),
    })?;
    Ok(())
}

// --- Votes ---

pub fn store_vote(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    choice: u32,
    commitment: &[u8],
) -> Result<(), VotingError> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;

    conn.execute_batch("SAVEPOINT store_vote_replace")
        .map_err(|e| VotingError::Internal {
            message: format!("failed to start store vote savepoint: {}", e),
        })?;

    let result: Result<(), VotingError> = (|| {
        let existing_vote: Option<(i64, Option<Vec<u8>>, bool)> = conn
            .query_row(
                "SELECT choice, commitment, tx_hash IS NOT NULL FROM votes
                 WHERE round_id = :round_id
                   AND wallet_id = :wallet_id
                   AND bundle_index = :bundle_index
                   AND proposal_id = :proposal_id",
                named_params! {
                    ":round_id": round_id,
                    ":wallet_id": wallet_id,
                    ":bundle_index": bundle_index as i64,
                    ":proposal_id": proposal_id as i64,
                },
                |row| Ok((row.get(0)?, row.get(1)?, row.get::<_, i64>(2)? != 0)),
            )
            .optional()
            .map_err(|e| VotingError::Internal {
                message: format!("failed to load existing vote before store: {}", e),
            })?;
        let vote_changed = existing_vote
            .as_ref()
            .map(|(stored_choice, stored_commitment, _)| {
                *stored_choice != choice as i64 || stored_commitment.as_deref() != Some(commitment)
            })
            .unwrap_or(false);
        if let Some((_, _, true)) = existing_vote.as_ref() {
            if vote_changed {
                return Err(VotingError::InvalidInput {
                    message: format!(
                        "cannot replace submitted vote for round={}, wallet={}, bundle={}, proposal={}",
                        round_id, wallet_id, bundle_index, proposal_id
                    ),
                });
            }
            return Ok(());
        }
        if existing_vote.is_some() && !vote_changed {
            return Ok(());
        }

        conn.execute(
            "INSERT OR REPLACE INTO votes (round_id, wallet_id, bundle_index, proposal_id, choice, commitment, created_at)
             VALUES (:round_id, :wallet_id, :bundle_index, :proposal_id, :choice, :commitment, :created_at)",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
                ":proposal_id": proposal_id as i64,
                ":choice": choice as i64,
                ":commitment": commitment,
                ":created_at": now,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to store vote: {}", e),
        })?;

        if vote_changed {
            share_delegations::delete_for_replaced_vote(
                conn,
                round_id,
                wallet_id,
                bundle_index,
                proposal_id,
            )?;
        }

        Ok(())
    })();

    match result {
        Ok(()) => conn
            .execute_batch("RELEASE SAVEPOINT store_vote_replace")
            .map_err(|e| VotingError::Internal {
                message: format!("failed to commit store vote savepoint: {}", e),
            }),
        Err(err) => {
            let _ = conn.execute_batch(
                "ROLLBACK TO SAVEPOINT store_vote_replace; RELEASE SAVEPOINT store_vote_replace",
            );
            Err(err)
        }
    }
}

pub fn ensure_no_submitted_vote_conflict_for_intent(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    proposal_id: u32,
    skipped: bool,
    choice: Option<u32>,
) -> Result<(), VotingError> {
    let conflicting_bundle = conn
        .query_row(
            "SELECT bundle_index
             FROM votes
             WHERE round_id = :round_id
               AND wallet_id = :wallet_id
               AND proposal_id = :proposal_id
               AND tx_hash IS NOT NULL
               AND (:skipped != 0 OR choice != :choice)
             ORDER BY bundle_index
             LIMIT 1",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":proposal_id": proposal_id as i64,
                ":skipped": if skipped { 1_i64 } else { 0_i64 },
                ":choice": choice.map(|c| c as i64),
            },
            |row| row.get::<_, i64>(0),
        )
        .optional()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to check submitted vote intent conflict: {}", e),
        })?;

    if let Some(bundle_index) = conflicting_bundle {
        return Err(VotingError::InvalidInput {
            message: format!(
                "round {round_id} bundle {bundle_index} proposal {proposal_id} has a submitted vote that conflicts with ballot intent"
            ),
        });
    }

    Ok(())
}

/// Get all votes for a round (across all bundles).
pub fn get_votes(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<Vec<VoteRecord>, VotingError> {
    let mut stmt = conn
        .prepare("SELECT proposal_id, bundle_index, choice FROM votes WHERE round_id = :round_id AND wallet_id = :wallet_id")
        .map_err(|e| VotingError::Internal {
            message: format!("failed to prepare get_votes: {}", e),
        })?;

    let votes = stmt
        .query_map(
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
            |row| {
                Ok(VoteRecord {
                    proposal_id: row.get::<_, i64>(0)? as u32,
                    bundle_index: row.get::<_, i64>(1)? as u32,
                    choice: row.get::<_, i64>(2)? as u32,
                })
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to get votes: {}", e),
        })?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to collect votes: {}", e),
        })?;

    Ok(votes)
}

/// Delete all local bundles (and their cascaded witnesses/proofs) with index >= `from_index`.
/// Used when the user skips remaining Keystone bundles — we remove the unsigned
/// bundle rows so that `proof_generated` (which counts ALL DB bundles) reflects
/// only the signed+proven bundles. When no bundle rows remain, clears
/// `bundle_policy_json` so a later replan can honor the caller's policy.
/// Imported capability batches are atomic and must instead be replaced with
/// `clear_round` followed by a complete re-import.
pub fn delete_bundles_from(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    from_index: u32,
) -> Result<u64, VotingError> {
    let tx = Transaction::new_unchecked(conn, TransactionBehavior::Immediate).map_err(|e| {
        VotingError::Internal {
            message: format!("failed to begin bundle deletion: {e}"),
        }
    })?;
    if round_has_imported_capability_bundles(&tx, round_id, wallet_id)? {
        return Err(VotingError::InvalidInput {
            message: format!(
                "imported capability round {round_id} cannot delete bundles independently; clear the round before importing a complete replacement capability"
            ),
        });
    }

    let rows = tx
        .execute(
            "DELETE FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index >= :from_index",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":from_index": from_index as i64,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to delete bundles from index {}: {}", from_index, e),
        })?;
    if get_bundle_count(&tx, round_id, wallet_id)? == 0 {
        tx.execute(
            "UPDATE rounds SET bundle_policy_json = NULL
             WHERE round_id = :round_id AND wallet_id = :wallet_id",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to clear bundle policy after deleting all bundles: {e}"),
        })?;
    }
    tx.commit().map_err(|e| VotingError::Internal {
        message: format!("failed to commit bundle deletion: {e}"),
    })?;
    Ok(rows as u64)
}

// --- Recovery state: TX hashes ---

pub fn store_delegation_tx_hash(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    tx_hash: &str,
) -> Result<(), VotingError> {
    let rows = conn
        .execute(
            "UPDATE bundles SET delegation_tx_hash = :tx_hash
             WHERE round_id = :round_id
               AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index
               AND (delegation_tx_hash IS NULL OR delegation_tx_hash = :tx_hash)",
            named_params! {
                ":tx_hash": tx_hash,
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to store delegation tx hash: {}", e),
        })?;
    if rows == 0 {
        if let Some(existing) =
            existing_delegation_tx_hash(conn, round_id, wallet_id, bundle_index)?
        {
            if existing.as_deref() == Some(tx_hash) {
                return Ok(());
            }
            if existing.is_some() {
                return Err(VotingError::InvalidInput {
                    message: format!(
                        "delegation tx hash already recorded for round={}, wallet={}, bundle={}",
                        round_id, wallet_id, bundle_index
                    ),
                });
            }
        }
        return Err(VotingError::InvalidInput {
            message: format!(
                "no bundle found for round={}, wallet={}, bundle={}",
                round_id, wallet_id, bundle_index
            ),
        });
    }
    Ok(())
}

fn existing_delegation_tx_hash(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<Option<Option<String>>, VotingError> {
    conn.query_row(
        "SELECT delegation_tx_hash
         FROM bundles
         WHERE round_id = :round_id
           AND wallet_id = :wallet_id
           AND bundle_index = :bundle_index",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
        },
        |row| row.get(0),
    )
    .optional()
    .map_err(|e| VotingError::Internal {
        message: format!("failed to load existing delegation tx hash: {}", e),
    })
}

pub fn get_delegation_tx_hash(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<Option<String>, VotingError> {
    conn.query_row(
        "SELECT delegation_tx_hash FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
        },
        |row| row.get(0),
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to get delegation tx hash: {}", e),
    })
}

pub fn record_vote_submission(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    tx_hash: &str,
) -> Result<(), VotingError> {
    ensure_vote_submission_matches_ballot_intent(
        conn,
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
    )?;
    let rows = conn
        .execute(
            "UPDATE votes SET tx_hash = :tx_hash
             WHERE round_id = :round_id
               AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index
               AND proposal_id = :proposal_id
               AND (tx_hash IS NULL OR tx_hash = :tx_hash)
               AND (
                   NOT EXISTS (
                       SELECT 1 FROM ballot_intent
                       WHERE round_id = :round_id
                         AND wallet_id = :wallet_id
                         AND proposal_id = :proposal_id
                   )
                   OR EXISTS (
                       SELECT 1 FROM ballot_intent
                       WHERE round_id = :round_id
                         AND wallet_id = :wallet_id
                         AND proposal_id = :proposal_id
                         AND skipped = 0
                         AND choice = votes.choice
                   )
               )",
            named_params! {
                ":tx_hash": tx_hash,
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
                ":proposal_id": proposal_id as i64,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to record vote submission: {}", e),
        })?;
    if rows == 0 {
        ensure_vote_submission_matches_ballot_intent(
            conn,
            round_id,
            wallet_id,
            bundle_index,
            proposal_id,
        )?;
        if let Some(existing) =
            existing_vote_tx_hash(conn, round_id, wallet_id, bundle_index, proposal_id)?
        {
            if existing.as_deref() == Some(tx_hash) {
                return Ok(());
            }
            if existing.is_some() {
                return Err(VotingError::InvalidInput {
                    message: format!(
                        "vote tx hash already recorded for round={}, wallet={}, bundle={}, proposal={}",
                        round_id, wallet_id, bundle_index, proposal_id
                    ),
                });
            }
        }
        return Err(VotingError::InvalidInput {
            message: format!(
                "no vote found for round={}, wallet={}, bundle={}, proposal={}",
                round_id, wallet_id, bundle_index, proposal_id
            ),
        });
    }
    Ok(())
}

fn existing_vote_tx_hash(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<Option<Option<String>>, VotingError> {
    conn.query_row(
        "SELECT tx_hash FROM votes
         WHERE round_id = :round_id
           AND wallet_id = :wallet_id
           AND bundle_index = :bundle_index
           AND proposal_id = :proposal_id",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
            ":proposal_id": proposal_id as i64,
        },
        |row| row.get(0),
    )
    .optional()
    .map_err(|e| VotingError::Internal {
        message: format!("failed to load existing vote tx hash: {}", e),
    })
}

pub fn get_vote_tx_hash(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<Option<String>, VotingError> {
    conn.query_row(
        "SELECT tx_hash FROM votes WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
            ":proposal_id": proposal_id as i64,
        },
        |row| row.get(0),
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to get vote tx hash: {}", e),
    })
}

pub fn get_commitment_bundle(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<Option<(String, u64)>, VotingError> {
    let (json, pos): (Option<String>, Option<i64>) = conn.query_row(
        "SELECT commitment_bundle_json, vc_tree_position FROM votes WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
            ":proposal_id": proposal_id as i64,
        },
        |row| Ok((row.get(0)?, row.get(1)?)),
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to get commitment bundle: {}", e),
    })?;
    match (json, pos) {
        (Some(json), Some(pos)) => {
            let position = u64::try_from(pos).map_err(|_| VotingError::Internal {
                message: format!("stored vc_tree_position must be non-negative, got {pos}"),
            })?;
            Ok(Some((json, position)))
        }
        (Some(_), None) => Err(VotingError::Internal {
            message:
                "commitment bundle is stored without vc_tree_position; refusing to assume position 0"
                    .to_string(),
        }),
        (None, _) => Ok(None),
    }
}

/// Loads raw commitment-bundle recovery columns for one vote key.
///
/// This lenient reader returns nullable `commitment_bundle_json` and
/// `vc_tree_position` exactly as stored, so callers can distinguish in-progress
/// recovery rows from fully confirmed rows.
pub(crate) fn get_commitment_bundle_recovery(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<Option<(Option<String>, Option<i64>)>, VotingError> {
    conn.query_row(
        "SELECT commitment_bundle_json, vc_tree_position FROM votes
         WHERE round_id = :round_id AND wallet_id = :wallet_id
           AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
            ":proposal_id": proposal_id as i64,
        },
        |row| Ok((row.get(0)?, row.get(1)?)),
    )
    .optional()
    .map_err(|e| VotingError::Internal {
        message: format!("failed to get commitment bundle recovery fields: {}", e),
    })
}

// --- Keystone signatures ---

pub fn store_keystone_signature(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    sig: &[u8],
    sighash: &[u8],
    rk: &[u8],
) -> Result<(), VotingError> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    conn.execute(
        "INSERT OR REPLACE INTO keystone_signatures (round_id, wallet_id, bundle_index, sig, sighash, rk, created_at) VALUES (:round_id, :wallet_id, :bundle_index, :sig, :sighash, :rk, :created_at)",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
            ":sig": sig,
            ":sighash": sighash,
            ":rk": rk,
            ":created_at": now as i64,
        },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to store keystone signature: {}", e),
    })?;
    Ok(())
}

pub fn get_keystone_signatures(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<Vec<KeystoneSignatureRecord>, VotingError> {
    let mut stmt = conn
        .prepare(
            "SELECT bundle_index, sig, sighash, rk FROM keystone_signatures WHERE round_id = :round_id AND wallet_id = :wallet_id ORDER BY bundle_index",
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to prepare get_keystone_signatures: {}", e),
        })?;

    let rows = stmt
        .query_map(
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
            |row| {
                Ok(KeystoneSignatureRecord {
                    bundle_index: row.get::<_, i64>(0)? as u32,
                    sig: row.get(1)?,
                    sighash: row.get(2)?,
                    rk: row.get(3)?,
                })
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to query keystone signatures: {}", e),
        })?;

    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to read keystone signature row: {}", e),
        })
}

// --- Session reset cleanup ---

/// Clears locally prepared unsigned delegation setup fields for one round.
///
/// Imported capability bundles have no local note selection, so their NULL
/// `note_positions_blob` keeps their voting fields outside this cleanup.
pub fn clear_unsigned_delegation_setup_fields(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<(), VotingError> {
    conn.execute(
        "UPDATE bundles
         SET van_comm_rand = NULL,
             dummy_nullifiers = NULL,
             rho_signed = NULL,
             padded_note_data = NULL,
             nf_signed = NULL,
             cmx_new = NULL,
             alpha = NULL,
             rseed_signed = NULL,
             rseed_output = NULL,
             gov_comm = NULL,
             total_note_value = NULL,
             address_index = NULL,
             rk = NULL,
             gov_nullifiers_blob = NULL,
             padded_note_secrets = NULL,
             pczt_sighash = NULL,
             tx1_effects = NULL
         WHERE round_id = :round_id
           AND wallet_id = :wallet_id
           AND note_positions_blob IS NOT NULL
           AND delegation_tx_hash IS NULL
           AND van_leaf_position IS NULL
           AND bundle_index NOT IN (
               SELECT bundle_index
               FROM keystone_signatures
               WHERE round_id = :round_id AND wallet_id = :wallet_id
           )",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to clear unsigned delegation setup fields: {e}"),
    })?;
    Ok(())
}

// --- Recovery state cleanup ---

/// Clears retryable recovery state without erasing recorded confirmations or
/// imported delegation capabilities.
pub fn clear_recovery_state(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<(), VotingError> {
    conn.execute(
        "DELETE FROM share_delegations WHERE round_id = :round_id AND wallet_id = :wallet_id",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to clear share delegations: {}", e),
    })?;
    conn.execute(
        "DELETE FROM keystone_signatures WHERE round_id = :round_id AND wallet_id = :wallet_id",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to clear keystone signatures: {}", e),
    })?;
    conn.execute(
        "UPDATE bundles SET delegation_tx_hash = NULL
         WHERE round_id = :round_id
           AND wallet_id = :wallet_id
           AND note_positions_blob IS NOT NULL
           AND van_leaf_position IS NULL",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to clear delegation tx hashes: {}", e),
    })?;
    conn.execute(
        "UPDATE votes SET tx_hash = NULL, commitment_bundle_json = NULL
         WHERE round_id = :round_id
           AND wallet_id = :wallet_id
           AND vc_tree_position IS NULL",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to clear vote recovery columns: {}", e),
    })?;
    Ok(())
}

fn ensure_vote_submission_matches_ballot_intent(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<(), VotingError> {
    let intent = load_ballot_intent(conn, round_id, wallet_id, proposal_id, "vote submission")?;
    let Some((skipped, choice)) = intent else {
        return Ok(());
    };
    let vote_choice = load_vote_choice_for_intent_check(
        conn,
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
        "vote submission",
    )?;
    let Some(vote_choice) = vote_choice else {
        return Ok(());
    };
    if skipped != 0 {
        return Err(VotingError::InvalidInput {
            message: format!(
                "cannot record vote submission for skipped proposal round={}, wallet={}, bundle={}, proposal={}",
                round_id, wallet_id, bundle_index, proposal_id
            ),
        });
    }
    let Some(choice) = choice else {
        return Err(VotingError::InvalidInput {
            message: format!(
                "ballot intent choice missing for round={}, wallet={}, proposal={}",
                round_id, wallet_id, proposal_id
            ),
        });
    };
    if vote_choice == choice {
        return Ok(());
    }
    Err(VotingError::InvalidInput {
        message: format!(
            "vote submission conflicts with ballot intent for round={}, wallet={}, bundle={}, proposal={}",
            round_id, wallet_id, bundle_index, proposal_id
        ),
    })
}

fn load_ballot_intent(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    proposal_id: u32,
    artifact: &str,
) -> Result<Option<(i64, Option<i64>)>, VotingError> {
    conn.query_row(
        "SELECT skipped, choice FROM ballot_intent
         WHERE round_id = :round_id
           AND wallet_id = :wallet_id
           AND proposal_id = :proposal_id",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":proposal_id": proposal_id as i64,
        },
        |row| Ok((row.get(0)?, row.get(1)?)),
    )
    .optional()
    .map_err(|e| VotingError::Internal {
        message: format!("failed to load ballot intent for {}: {}", artifact, e),
    })
}

fn load_vote_choice_for_intent_check(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    artifact: &str,
) -> Result<Option<i64>, VotingError> {
    conn.query_row(
        "SELECT choice FROM votes
         WHERE round_id = :round_id
           AND wallet_id = :wallet_id
           AND bundle_index = :bundle_index
           AND proposal_id = :proposal_id",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
            ":proposal_id": proposal_id as i64,
        },
        |row| row.get(0),
    )
    .optional()
    .map_err(|e| VotingError::Internal {
        message: format!("failed to load vote choice for {}: {}", artifact, e),
    })
}
