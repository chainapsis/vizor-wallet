use ff::PrimeField;
use pasta_curves::pallas;
use rusqlite::{named_params, Connection, OptionalExtension};
use voting_circuits::delegation::imt::ImtProofData;

use crate::storage::{KeystoneSignatureRecord, RoundPhase, RoundState, RoundSummary, VoteRecord};
use crate::types::{NoteInfo, ShareDelegationRecord, VotingError, VotingRoundParams, WitnessData};

const NOTE_IDENTITY_HASH_BYTES: usize = 32;
const NOTE_IDENTITY_DOMAIN: &[u8] = b"zcash-voting-note-identity-v1";

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

// --- Rounds ---

pub fn insert_round(
    conn: &Connection,
    wallet_id: &str,
    params: &VotingRoundParams,
    session_json: Option<&str>,
) -> Result<(), VotingError> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;

    conn.execute(
        "INSERT INTO rounds (round_id, wallet_id, snapshot_height, ea_pk, nc_root, nullifier_imt_root, session_json, phase, created_at)
         VALUES (:round_id, :wallet_id, :snapshot_height, :ea_pk, :nc_root, :nullifier_imt_root, :session_json, :phase, :created_at)",
        named_params! {
            ":round_id": params.vote_round_id,
            ":wallet_id": wallet_id,
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
    conn.query_row(
        "SELECT round_id, snapshot_height, ea_pk, nc_root, nullifier_imt_root FROM rounds WHERE round_id = :round_id AND wallet_id = :wallet_id",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
        |row| {
            Ok(VotingRoundParams {
                vote_round_id: row.get(0)?,
                snapshot_height: row.get::<_, i64>(1)? as u64,
                ea_pk: row.get(2)?,
                nc_root: row.get(3)?,
                nullifier_imt_root: row.get(4)?,
            })
        },
    )
    .map_err(|e| VotingError::InvalidInput {
        message: format!("round not found: {} ({})", round_id, e),
    })
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
    let (phase_int, snapshot_height): (i32, i64) = conn
        .query_row(
            "SELECT phase, snapshot_height FROM rounds WHERE round_id = :round_id AND wallet_id = :wallet_id",
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .map_err(|e| VotingError::InvalidInput {
            message: format!("round not found: {} ({})", round_id, e),
        })?;

    // proof_generated is true only when ALL bundles have a successful proof
    // AND all bundles have a VAN leaf position (delegation TX landed on chain).
    // This prevents the UI from treating delegation as complete before the
    // on-chain submission finishes.
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
        let proofs_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM proofs WHERE round_id = :round_id AND wallet_id = :wallet_id AND success = 1",
                named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
                |row| row.get(0),
            )
            .map_err(|e| VotingError::Internal {
                message: format!("failed to count proofs: {}", e),
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

        proofs_count >= bundle_count && van_positions_count >= bundle_count
    };

    Ok(RoundState {
        round_id: round_id.to_string(),
        phase: RoundPhase::from_i32(phase_int),
        snapshot_height: snapshot_height as u64,
        hotkey_address: None,
        delegated_weight: None,
        proof_generated,
    })
}

pub fn list_rounds(conn: &Connection, wallet_id: &str) -> Result<Vec<RoundSummary>, VotingError> {
    let mut stmt = conn
        .prepare("SELECT round_id, wallet_id, phase, snapshot_height, created_at FROM rounds WHERE wallet_id = :wallet_id ORDER BY created_at DESC")
        .map_err(|e| VotingError::Internal {
            message: format!("failed to prepare list_rounds query: {}", e),
        })?;

    let rounds = stmt
        .query_map(named_params! { ":wallet_id": wallet_id }, |row| {
            Ok(RoundSummary {
                round_id: row.get(0)?,
                wallet_id: row.get(1)?,
                phase: RoundPhase::from_i32(row.get(2)?),
                snapshot_height: row.get::<_, i64>(3)? as u64,
                created_at: row.get::<_, i64>(4)? as u64,
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

/// Persist all delegation action data in a single UPDATE on the bundles table:
/// blinding factor, dummy nullifiers, constrained rho, padded note cmx values,
/// signed action fields (nf_signed, cmx_new, alpha), note rseeds,
/// VAN leaf value, total note value, and address index.
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
        None,
        None,
    )
}

/// Persist delegation action data plus PCZT-derived public inputs that the
/// later delegation proof must reproduce.
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
    rk: Option<&[u8]>,
    gov_nullifiers_blob: Option<&[u8]>,
) -> Result<(), VotingError> {
    // Serialize padded-note nullifiers as a flat byte blob: [nf0 (32 bytes) | nf1 | nf2 | ...].
    // Length 0 means no padding was needed (all 5 notes were real).
    // Length 32/64/96/128 means 1/2/3/4 dummy notes respectively.
    let dummy_blob: Vec<u8> = dummy_nullifiers
        .iter()
        .flat_map(|n| n.iter().copied())
        .collect();

    // Same flat-blob encoding for padded cmx values.
    let padded_blob: Vec<u8> = padded_cmx.iter().flat_map(|c| c.iter().copied()).collect();

    // Serialize padded_note_secrets as flat blob: N * 64 bytes (rho[32] || rseed[32] per entry).
    let secrets_blob: Vec<u8> = padded_note_secrets
        .iter()
        .flat_map(|(rho, rseed)| rho.iter().copied().chain(rseed.iter().copied()))
        .collect();

    let rows = conn
        .execute(
            "UPDATE bundles SET van_comm_rand = :rand, dummy_nullifiers = :dummies, \
             rho_signed = :rho, padded_note_data = :padded, nf_signed = :nf_signed, \
             cmx_new = :cmx_new, alpha = :alpha, rseed_signed = :rseed_signed, \
             rseed_output = :rseed_output, gov_comm = :gov_comm, \
             total_note_value = :total_note_value, address_index = :address_index, \
             padded_note_secrets = :secrets, pczt_sighash = :sighash, \
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

/// Load padded note secrets (rho + rseed pairs) for Phase 2 randomness threading.
/// Returns Vec of (rho[32], rseed[32]) pairs. Deserializes from flat 64-byte-per-entry blob.
pub fn load_padded_note_secrets(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<Vec<(Vec<u8>, Vec<u8>)>, VotingError> {
    let blob: Vec<u8> = conn
        .query_row(
            "SELECT padded_note_secrets FROM bundles WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
            |row| row.get(0),
        )
        .map_err(|e| VotingError::InvalidInput {
            message: format!("no padded_note_secrets for round={}, bundle={} ({})", round_id, bundle_index, e),
        })?;

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

    // Compute current proposal_authority by clearing bits for already-submitted votes
    // for THIS bundle specifically.
    let mut authority = MAX_PROPOSAL_AUTHORITY;
    let mut stmt = conn
        .prepare("SELECT proposal_id FROM votes WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index AND submitted = 1")
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

// --- VAN leaf position ---

/// Store the VAN leaf position after delegation TX is confirmed on chain.
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
#[cfg_attr(not(feature = "client-pir"), allow(dead_code))]
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
}

/// Load all fields needed to reconstruct the chain-ready delegation TX payload.
pub fn load_delegation_submission_data(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<DelegationDbFields, VotingError> {
    let (proof_bytes, rk, nf_signed, cmx_new, gov_comm, gov_nullifiers_blob, alpha, vote_round_id): (
        Vec<u8>, Vec<u8>, Vec<u8>, Vec<u8>, Vec<u8>, Vec<u8>, Vec<u8>, String,
    ) = conn
        .query_row(
            "SELECT p.proof, b.rk, b.nf_signed, b.cmx_new, b.gov_comm, \
             b.gov_nullifiers_blob, b.alpha, b.round_id \
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

    Ok(DelegationDbFields {
        proof: proof_bytes,
        rk,
        nf_signed,
        cmx_new,
        gov_comm,
        gov_nullifiers,
        alpha,
        vote_round_id,
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

// --- Witnesses (Merkle inclusion proofs for Orchard notes) ---

/// Check if witnesses are already cached for a bundle.
pub fn has_witnesses(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
) -> Result<bool, VotingError> {
    conn.query_row(
        "SELECT COUNT(*) FROM witnesses WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id, ":bundle_index": bundle_index as i64 },
        |row| row.get::<_, i64>(0).map(|c| c > 0),
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
    require_witness_positions_match_bundle(conn, round_id, wallet_id, bundle_index, witnesses)?;

    let tx = conn.transaction().map_err(|e| VotingError::Internal {
        message: format!("failed to begin witness replacement transaction: {}", e),
    })?;

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

pub fn store_imt_proof(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    nullifier: &[u8],
    proof: &ImtProofData,
) -> Result<(), VotingError> {
    let root = field_to_bytes(proof.root);
    let nf_bounds = fields_to_blob(proof.nf_bounds);
    let path = fields_to_blob(proof.path);

    conn.execute(
        "INSERT INTO imt_proofs (round_id, wallet_id, bundle_index, nullifier, root, nf_bounds, leaf_pos, path, created_at)
         VALUES (:round_id, :wallet_id, :bundle_index, :nullifier, :root, :nf_bounds, :leaf_pos, :path, strftime('%s','now'))
         ON CONFLICT(round_id, wallet_id, bundle_index, nullifier)
         DO UPDATE SET root = :root, nf_bounds = :nf_bounds, leaf_pos = :leaf_pos, path = :path, created_at = strftime('%s','now')",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
            ":nullifier": nullifier,
            ":root": root,
            ":nf_bounds": nf_bounds,
            ":leaf_pos": proof.leaf_pos as i64,
            ":path": path,
        },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to store IMT proof for bundle {bundle_index}: {e}"),
    })?;
    Ok(())
}

pub fn load_imt_proof(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    nullifier: &[u8],
    expected_root: &[u8],
) -> Result<Option<ImtProofData>, VotingError> {
    let row = conn
        .query_row(
            "SELECT root, nf_bounds, leaf_pos, path FROM imt_proofs
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND nullifier = :nullifier",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
                ":nullifier": nullifier,
            },
            |row| {
                let root: Vec<u8> = row.get(0)?;
                let nf_bounds: Vec<u8> = row.get(1)?;
                let leaf_pos: i64 = row.get(2)?;
                let path: Vec<u8> = row.get(3)?;
                Ok((root, nf_bounds, leaf_pos, path))
            },
        )
        .optional()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to load IMT proof for bundle {bundle_index}: {e}"),
        })?;

    let Some((root, nf_bounds, leaf_pos, path)) = row else {
        return Ok(None);
    };

    if root != expected_root {
        return Ok(None);
    }

    Ok(Some(ImtProofData {
        root: field_from_bytes(&root, "imt_proof.root")?,
        nf_bounds: fields_from_blob::<3>(&nf_bounds, "imt_proof.nf_bounds")?,
        leaf_pos: u32::try_from(leaf_pos).map_err(|_| VotingError::Internal {
            message: format!("invalid IMT proof leaf_pos {leaf_pos}"),
        })?,
        path: fields_from_blob::<29>(&path, "imt_proof.path")?,
    }))
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

    conn.execute(
        "INSERT OR REPLACE INTO votes (round_id, wallet_id, bundle_index, proposal_id, choice, commitment, submitted, created_at)
         VALUES (:round_id, :wallet_id, :bundle_index, :proposal_id, :choice, :commitment, 0, :created_at)",
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
    Ok(())
}

/// Get all votes for a round (across all bundles).
pub fn get_votes(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<Vec<VoteRecord>, VotingError> {
    let mut stmt = conn
        .prepare("SELECT proposal_id, bundle_index, choice, submitted FROM votes WHERE round_id = :round_id AND wallet_id = :wallet_id")
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
                    submitted: row.get::<_, i64>(3)? != 0,
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

/// Delete all bundles (and their cascaded witnesses/proofs) with index >= `from_index`.
/// Used when the user skips remaining Keystone bundles — we remove the unsigned
/// bundle rows so that `proof_generated` (which counts ALL DB bundles) reflects
/// only the signed+proven bundles.
pub fn delete_bundles_from(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    from_index: u32,
) -> Result<u64, VotingError> {
    let rows = conn
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
    Ok(rows as u64)
}

pub fn mark_vote_submitted(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<(), VotingError> {
    let rows = conn
        .execute(
            "UPDATE votes SET submitted = 1 \
             WHERE round_id = :round_id \
             AND wallet_id = :wallet_id \
             AND bundle_index = :bundle_index \
             AND proposal_id = :proposal_id",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
                ":proposal_id": proposal_id as i64,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to mark vote submitted: {}", e),
        })?;

    if rows == 0 {
        return Err(VotingError::InvalidInput {
            message: format!(
                "no vote found for round={}, wallet={}, bundle={}, proposal={}",
                round_id, wallet_id, bundle_index, proposal_id
            ),
        });
    }

    Ok(())
}

// --- Recovery state: TX hashes ---

pub fn store_delegation_tx_hash(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    tx_hash: &str,
) -> Result<(), VotingError> {
    conn.execute(
        "UPDATE bundles SET delegation_tx_hash = :tx_hash WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index",
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
    Ok(())
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

pub fn store_vote_tx_hash(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    tx_hash: &str,
) -> Result<(), VotingError> {
    conn.execute(
        "UPDATE votes SET tx_hash = :tx_hash WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
        named_params! {
            ":tx_hash": tx_hash,
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
            ":proposal_id": proposal_id as i64,
        },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to store vote tx hash: {}", e),
    })?;
    Ok(())
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

// --- Recovery state: commitment bundles ---

pub fn store_commitment_bundle(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    bundle_json: &str,
    vc_tree_position: u64,
) -> Result<(), VotingError> {
    conn.execute(
        "UPDATE votes SET commitment_bundle_json = :json, vc_tree_position = :pos WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
        named_params! {
            ":json": bundle_json,
            ":pos": vc_tree_position as i64,
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
            ":proposal_id": proposal_id as i64,
        },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to store commitment bundle: {}", e),
    })?;
    Ok(())
}

pub fn get_commitment_bundle(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<Option<(String, u64)>, VotingError> {
    let result = conn.query_row(
        "SELECT commitment_bundle_json, vc_tree_position FROM votes WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
            ":proposal_id": proposal_id as i64,
        },
        |row| {
            let json: Option<String> = row.get(0)?;
            let pos: Option<i64> = row.get(1)?;
            Ok(json.map(|j| (j, pos.unwrap_or(0) as u64)))
        },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to get commitment bundle: {}", e),
    })?;
    Ok(result)
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

// --- Recovery state cleanup ---

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
        "UPDATE bundles SET delegation_tx_hash = NULL WHERE round_id = :round_id AND wallet_id = :wallet_id",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to clear delegation tx hashes: {}", e),
    })?;
    conn.execute(
        "UPDATE votes SET tx_hash = NULL, vc_tree_position = NULL, commitment_bundle_json = NULL WHERE round_id = :round_id AND wallet_id = :wallet_id",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to clear vote recovery columns: {}", e),
    })?;
    Ok(())
}

// --- Share delegation tracking ---

/// Record a share delegation after sending to helper servers.
pub fn record_share_delegation(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    sent_to_urls: &[String],
    nullifier: &[u8],
    submit_at: u64,
) -> Result<(), VotingError> {
    let urls_json = serde_json::to_string(sent_to_urls).map_err(|e| VotingError::Internal {
        message: format!("failed to serialize sent_to_urls: {}", e),
    })?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    conn.execute(
        "INSERT INTO share_delegations \
         (round_id, wallet_id, bundle_index, proposal_id, share_index, sent_to_urls, nullifier, confirmed, submit_at, created_at) \
         VALUES (:round_id, :wallet_id, :bundle_index, :proposal_id, :share_index, :sent_to_urls, :nullifier, 0, :submit_at, :created_at) \
         ON CONFLICT (round_id, wallet_id, bundle_index, proposal_id, share_index) DO UPDATE SET \
         sent_to_urls = excluded.sent_to_urls, \
         nullifier = excluded.nullifier, \
         submit_at = excluded.submit_at",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index,
            ":proposal_id": proposal_id,
            ":share_index": share_index,
            ":sent_to_urls": urls_json,
            ":nullifier": nullifier,
            ":submit_at": submit_at,
            ":created_at": now,
        },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to record share delegation: {}", e),
    })?;
    Ok(())
}

/// Load all share delegations for a round.
pub fn get_share_delegations(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<Vec<ShareDelegationRecord>, VotingError> {
    load_share_delegations(
        conn,
        "SELECT bundle_index, proposal_id, share_index, sent_to_urls, nullifier, confirmed, submit_at, created_at, round_id \
         FROM share_delegations WHERE round_id = :round_id AND wallet_id = :wallet_id \
         ORDER BY proposal_id, share_index",
        round_id,
        wallet_id,
    )
}

/// Load only unconfirmed share delegations for a round.
pub fn get_unconfirmed_delegations(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<Vec<ShareDelegationRecord>, VotingError> {
    load_share_delegations(
        conn,
        "SELECT bundle_index, proposal_id, share_index, sent_to_urls, nullifier, confirmed, submit_at, created_at, round_id \
         FROM share_delegations WHERE round_id = :round_id AND wallet_id = :wallet_id AND confirmed = 0 \
         ORDER BY proposal_id, share_index",
        round_id,
        wallet_id,
    )
}

fn load_share_delegations(
    conn: &Connection,
    sql: &str,
    round_id: &str,
    wallet_id: &str,
) -> Result<Vec<ShareDelegationRecord>, VotingError> {
    let mut stmt = conn.prepare(sql).map_err(|e| VotingError::Internal {
        message: format!("failed to prepare share delegation query: {}", e),
    })?;
    let rows = stmt
        .query_map(
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
            |row| {
                let urls_json: String = row.get(3)?;
                let nullifier_blob: Vec<u8> = row.get(4)?;
                let confirmed_int: i32 = row.get(5)?;
                let round_id_val: String = row.get(8)?;
                Ok((
                    row.get::<_, u32>(0)?,
                    row.get::<_, u32>(1)?,
                    row.get::<_, u32>(2)?,
                    urls_json,
                    nullifier_blob,
                    confirmed_int != 0,
                    row.get::<_, u64>(6)?,
                    row.get::<_, u64>(7)?,
                    round_id_val,
                ))
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to query share delegations: {}", e),
        })?;

    let mut results = Vec::new();
    for row in rows {
        let (
            bundle_index,
            proposal_id,
            share_index,
            urls_json,
            nullifier,
            confirmed,
            submit_at,
            created_at,
            round_id_val,
        ) = row.map_err(|e| VotingError::Internal {
            message: format!("failed to read share delegation row: {}", e),
        })?;
        let sent_to_urls: Vec<String> =
            serde_json::from_str(&urls_json).map_err(|e| VotingError::Internal {
                message: format!("failed to deserialize sent_to_urls: {}", e),
            })?;
        results.push(ShareDelegationRecord {
            round_id: round_id_val,
            bundle_index,
            proposal_id,
            share_index,
            sent_to_urls,
            nullifier,
            confirmed,
            submit_at,
            created_at,
        });
    }
    Ok(results)
}

/// Mark a share delegation as confirmed on-chain.
pub fn mark_share_confirmed(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
) -> Result<(), VotingError> {
    let updated = conn
        .execute(
            "UPDATE share_delegations SET confirmed = 1 \
             WHERE round_id = :round_id AND wallet_id = :wallet_id \
             AND bundle_index = :bundle_index AND proposal_id = :proposal_id AND share_index = :share_index",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index,
                ":proposal_id": proposal_id,
                ":share_index": share_index,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to mark share confirmed: {}", e),
        })?;
    if updated == 0 {
        return Err(VotingError::Internal {
            message: format!(
                "no share delegation found: round={}, bundle={}, proposal={}, share={}",
                round_id, bundle_index, proposal_id, share_index
            ),
        });
    }
    Ok(())
}

/// Append new server URLs to a share delegation's sent_to_urls.
/// Used after resubmitting an overdue share to additional servers.
pub fn add_sent_servers(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    new_urls: &[String],
) -> Result<(), VotingError> {
    // Read current URLs
    let current_json: String = conn
        .query_row(
            "SELECT sent_to_urls FROM share_delegations \
             WHERE round_id = :round_id AND wallet_id = :wallet_id \
             AND bundle_index = :bundle_index AND proposal_id = :proposal_id AND share_index = :share_index",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index,
                ":proposal_id": proposal_id,
                ":share_index": share_index,
            },
            |row| row.get(0),
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to read sent_to_urls for update: {}", e),
        })?;

    let mut urls: Vec<String> =
        serde_json::from_str(&current_json).map_err(|e| VotingError::Internal {
            message: format!("failed to deserialize sent_to_urls: {}", e),
        })?;

    // Append new URLs (deduplicated)
    for url in new_urls {
        if !urls.contains(url) {
            urls.push(url.clone());
        }
    }

    let updated_json = serde_json::to_string(&urls).map_err(|e| VotingError::Internal {
        message: format!("failed to serialize updated sent_to_urls: {}", e),
    })?;

    conn.execute(
        "UPDATE share_delegations SET sent_to_urls = :urls, submit_at = 0 \
         WHERE round_id = :round_id AND wallet_id = :wallet_id \
         AND bundle_index = :bundle_index AND proposal_id = :proposal_id AND share_index = :share_index",
        named_params! {
            ":urls": updated_json,
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index,
            ":proposal_id": proposal_id,
            ":share_index": share_index,
        },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to update sent_to_urls: {}", e),
    })?;
    Ok(())
}
