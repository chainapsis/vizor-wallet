use std::collections::HashMap;

use ff::PrimeField;
use orchard::{
    keys::FullViewingKey,
    note::{RandomSeed, Rho},
    primitives::redpallas::{Signature, SpendAuth, VerificationKey},
};
use pasta_curves::pallas;
use voting_circuits::delegation::{synthetic_padding_note_parts, ImtProofData};
use zcash_keys::keys::UnifiedFullViewingKey;

use crate::delegate::{DelegationKeys, DelegationSigningRequest};
use crate::governance::BUNDLE_NOTE_SLOTS;
use crate::note_bundling::ChunkResult;
use crate::storage::queries;
use crate::storage::{
    KeystoneSignatureRecord, RoundPhase, RoundState, RoundSummary, VoteRecord, VotingDb,
};
use crate::types::{
    DelegationPirPrecomputeResult, DelegationProgressReporter, DelegationProofResult,
    DelegationSubmissionData, GovernancePczt, Network, NoteInfo, ProgressReporter, SharePayload,
    VoteCommitmentBundle, VotingError, VotingRoundParams, WireEncryptedShare, WitnessData,
};

fn nullifier_bytes_to_base(bytes: &[u8], label: &str) -> Result<pallas::Base, VotingError> {
    let nf_bytes: [u8; 32] = bytes.try_into().map_err(|_| VotingError::Internal {
        message: format!("{label} nullifier must be 32 bytes, got {}", bytes.len()),
    })?;
    Option::from(pallas::Base::from_repr(nf_bytes)).ok_or_else(|| VotingError::Internal {
        message: format!("{label} nullifier is not a valid field element"),
    })
}

fn validate_consensus_branch_id_for_round(
    params: &VotingRoundParams,
    stored_network: Network,
    keys: &DelegationKeys,
    consensus_branch_id: u32,
) -> Result<(), VotingError> {
    validate_network_matches_round(stored_network, keys.network, "delegation keys")?;

    let expected = crate::lwd::branch_id_for_height(stored_network, params.snapshot_height)?;
    if consensus_branch_id != expected {
        return Err(VotingError::InvalidInput {
            message: format!(
                "consensus_branch_id 0x{consensus_branch_id:08X} does not match snapshot height {} branch id 0x{expected:08X}",
                params.snapshot_height
            ),
        });
    }
    Ok(())
}

fn validate_network_matches_round(
    stored_network: Network,
    requested_network: Network,
    label: &str,
) -> Result<(), VotingError> {
    if requested_network != stored_network {
        return Err(VotingError::InvalidInput {
            message: format!(
                "{label} network {:?} does not match stored round network {:?}",
                requested_network, stored_network
            ),
        });
    }

    Ok(())
}

fn delegation_nullifier_targets(
    notes: &[NoteInfo],
    dummy_nullifiers: &[Vec<u8>],
) -> Result<Vec<([u8; 32], pallas::Base)>, VotingError> {
    let mut targets = Vec::with_capacity(notes.len() + dummy_nullifiers.len());

    for (idx, note) in notes.iter().enumerate() {
        let nf_bytes: [u8; 32] =
            note.nullifier
                .as_slice()
                .try_into()
                .map_err(|_| VotingError::Internal {
                    message: format!(
                        "note[{idx}] nullifier must be 32 bytes, got {}",
                        note.nullifier.len()
                    ),
                })?;
        let nf = nullifier_bytes_to_base(&nf_bytes, &format!("note[{idx}]"))?;
        targets.push((nf_bytes, nf));
    }

    for (idx, dummy) in dummy_nullifiers.iter().enumerate() {
        let nf_bytes: [u8; 32] =
            dummy
                .as_slice()
                .try_into()
                .map_err(|_| VotingError::Internal {
                    message: format!(
                        "padded_note[{idx}] nullifier must be 32 bytes, got {}",
                        dummy.len()
                    ),
                })?;
        let nf = nullifier_bytes_to_base(&nf_bytes, &format!("padded_note[{idx}]"))?;
        targets.push((nf_bytes, nf));
    }

    Ok(targets)
}

fn verify_delegation_spend_auth_signature(
    rk: &[u8],
    sighash: &[u8],
    signature: &[u8],
) -> Result<(), VotingError> {
    let rk_bytes: [u8; 32] = rk.try_into().map_err(|_| VotingError::Internal {
        message: format!("rk must be 32 bytes, got {}", rk.len()),
    })?;
    let sighash_bytes: [u8; 32] = sighash.try_into().map_err(|_| VotingError::Internal {
        message: format!("pczt_sighash must be 32 bytes, got {}", sighash.len()),
    })?;
    let signature_bytes: [u8; 64] =
        signature
            .try_into()
            .map_err(|_| VotingError::InvalidInput {
                message: format!("signature must be 64 bytes, got {}", signature.len()),
            })?;

    let verification_key =
        VerificationKey::<SpendAuth>::try_from(rk_bytes).map_err(|_| VotingError::Internal {
            message: "rk is not a valid SpendAuth verification key".to_string(),
        })?;
    let sig = Signature::<SpendAuth>::from(signature_bytes);
    verification_key
        .verify(&sighash_bytes, &sig)
        .map_err(|_| VotingError::InvalidInput {
            message: "signature does not verify against stored delegation rk and sighash"
                .to_string(),
        })
}

fn nullifier_imt_root_to_base(bytes: &[u8]) -> Result<pallas::Base, VotingError> {
    let root_bytes: [u8; 32] = bytes.try_into().map_err(|_| VotingError::Internal {
        message: format!("nullifier_imt_root must be 32 bytes, got {}", bytes.len()),
    })?;
    Option::from(pallas::Base::from_repr(root_bytes)).ok_or_else(|| VotingError::Internal {
        message: "nullifier_imt_root is not a valid field element".to_string(),
    })
}

/// Derive padded-slot nullifiers with the same synthetic padding points used by
/// the delegation circuit builder.
fn padded_nullifiers_for_circuit(
    notes: &[NoteInfo],
    padded_secrets: &[(Vec<u8>, Vec<u8>)],
    network: Network,
) -> Result<Vec<Vec<u8>>, VotingError> {
    if padded_secrets.is_empty() {
        return Ok(Vec::new());
    }
    let n_real = notes.len();
    let first_ufvk = &notes
        .first()
        .ok_or_else(|| VotingError::InvalidInput {
            message: "notes must be non-empty to derive padded nullifiers".to_string(),
        })?
        .ufvk_str;

    let ufvk =
        UnifiedFullViewingKey::decode(&network, first_ufvk).map_err(|e| VotingError::Internal {
            message: format!("failed to decode UFVK while deriving padded nullifiers: {e}"),
        })?;
    let fvk: FullViewingKey = ufvk
        .orchard()
        .ok_or_else(|| VotingError::Internal {
            message: "UFVK has no Orchard component".into(),
        })?
        .clone();

    let mut out = Vec::with_capacity(padded_secrets.len());
    for (i_pad, (rho_bytes, rseed_bytes)) in padded_secrets.iter().enumerate() {
        let i_slot = n_real + i_pad;
        let rho_arr: [u8; 32] =
            rho_bytes
                .as_slice()
                .try_into()
                .map_err(|_| VotingError::Internal {
                    message: format!(
                        "padded[{i_pad}] rho must be 32 bytes, got {}",
                        rho_bytes.len()
                    ),
                })?;
        let rho = Option::from(Rho::from_bytes(&rho_arr)).ok_or_else(|| VotingError::Internal {
            message: format!("padded[{i_pad}] rho is not a valid Rho"),
        })?;
        let rseed_arr: [u8; 32] =
            rseed_bytes
                .as_slice()
                .try_into()
                .map_err(|_| VotingError::Internal {
                    message: format!(
                        "padded[{i_pad}] rseed must be 32 bytes, got {}",
                        rseed_bytes.len()
                    ),
                })?;
        let rseed = Option::from(RandomSeed::from_bytes(rseed_arr, &rho)).ok_or_else(|| {
            VotingError::Internal {
                message: format!("padded[{i_pad}] rseed is not valid for the stored rho"),
            }
        })?;
        let parts = synthetic_padding_note_parts(&fvk, i_slot, rho, rseed).map_err(|e| {
            VotingError::Internal {
                message: format!("synthetic padding slot {i_slot}: {e}"),
            }
        })?;
        out.push(parts.nullifier.to_vec());
    }
    Ok(out)
}

fn precomputed_randomness_from_stored(
    notes_len: usize,
    padded_secrets: &[(Vec<u8>, Vec<u8>)],
    rseed_signed: &[u8],
    rseed_output: &[u8],
    bundle_index: u32,
) -> Result<voting_circuits::delegation::PrecomputedRandomness, VotingError> {
    use voting_circuits::delegation::{PaddedNoteData, PrecomputedRandomness};

    let expected_padded_count = BUNDLE_NOTE_SLOTS.saturating_sub(notes_len);
    if padded_secrets.len() != expected_padded_count {
        return Err(VotingError::InvalidInput {
            message: format!(
                "stored padded_note_secrets count ({}) must match expected padded note count ({expected_padded_count}) for bundle {bundle_index}",
                padded_secrets.len()
            ),
        });
    }

    let padded_notes: Vec<PaddedNoteData> = padded_secrets
        .iter()
        .enumerate()
        .map(|(i, (rho, rseed))| {
            let rho_arr: [u8; 32] =
                rho.as_slice()
                    .try_into()
                    .map_err(|_| VotingError::Internal {
                        message: format!(
                            "stored padded_note_secrets[{i}].rho must be 32 bytes, got {}",
                            rho.len()
                        ),
                    })?;
            let rseed_arr: [u8; 32] =
                rseed
                    .as_slice()
                    .try_into()
                    .map_err(|_| VotingError::Internal {
                        message: format!(
                            "stored padded_note_secrets[{i}].rseed must be 32 bytes, got {}",
                            rseed.len()
                        ),
                    })?;
            Ok(PaddedNoteData {
                rho: rho_arr,
                rseed: rseed_arr,
            })
        })
        .collect::<Result<Vec<_>, VotingError>>()?;

    let rseed_signed: [u8; 32] = rseed_signed.try_into().map_err(|_| VotingError::Internal {
        message: format!(
            "stored rseed_signed must be 32 bytes, got {}",
            rseed_signed.len()
        ),
    })?;
    let rseed_output: [u8; 32] = rseed_output.try_into().map_err(|_| VotingError::Internal {
        message: format!(
            "stored rseed_output must be 32 bytes, got {}",
            rseed_output.len()
        ),
    })?;

    Ok(PrecomputedRandomness {
        padded_notes,
        rseed_signed,
        rseed_output,
    })
}

fn verify_witnesses(witnesses: &[WitnessData]) -> Result<(), VotingError> {
    for w in witnesses {
        let valid = crate::witness::verify_witness(w)?;
        if !valid {
            return Err(VotingError::Internal {
                message: format!("witness verification failed for position {}", w.position),
            });
        }
    }

    Ok(())
}

fn validate_witnesses_for_round(
    witnesses: &[WitnessData],
    params: &VotingRoundParams,
) -> Result<(), VotingError> {
    verify_witnesses(witnesses)?;
    for witness in witnesses {
        if witness.root != params.nc_root {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "witness root for position {} does not match stored round nc_root",
                    witness.position
                ),
            });
        }
    }

    Ok(())
}

impl VotingDb {
    // --- Round management ---

    /// Initialize a new voting round. Stores params, sets phase to Initialized.
    pub fn init_round(
        &self,
        network: Network,
        params: &VotingRoundParams,
        session_json: Option<&str>,
    ) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::insert_round(&conn, &wallet_id, network, params, session_json)
    }

    /// Get the current state of a voting round.
    pub fn get_round_state(&self, round_id: &str) -> Result<RoundState, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::get_round_state(&conn, round_id, &wallet_id)
    }

    /// Loads the stored round network and rejects a caller-supplied mismatch.
    pub(crate) fn require_round_network(
        &self,
        round_id: &str,
        network: Network,
        label: &str,
    ) -> Result<Network, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        let stored_network = queries::load_round_network(&conn, round_id, &wallet_id)?;
        validate_network_matches_round(stored_network, network, label)?;
        Ok(stored_network)
    }

    /// Advance the round phase without allowing regressions.
    pub fn advance_round_phase(
        &self,
        round_id: &str,
        phase: RoundPhase,
    ) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::advance_round_phase(&conn, round_id, &wallet_id, phase)
    }

    /// Return whether a voting round exists for the current wallet.
    pub fn has_round(&self, round_id: &str) -> Result<bool, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::has_round(&conn, round_id, &wallet_id)
    }

    /// List all rounds.
    pub fn list_rounds(&self) -> Result<Vec<RoundSummary>, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::list_rounds(&conn, &wallet_id)
    }

    /// Get all votes for a round, including proposal, bundle, and choice.
    pub fn get_votes(&self, round_id: &str) -> Result<Vec<VoteRecord>, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::get_votes(&conn, round_id, &wallet_id)
    }

    /// Test-fixture helper for inserting a stored vote without running the
    /// full vote proof builder.
    ///
    /// This is intended for downstream FFI tests that need recovery-state rows
    /// backed by a vote. It is only compiled for this crate's tests.
    #[cfg(test)]
    pub fn insert_vote_fixture(
        &self,
        round_id: &str,
        bundle_index: u32,
        proposal_id: u32,
        choice: u32,
        commitment: &[u8],
    ) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::store_vote(
            &conn,
            round_id,
            &wallet_id,
            bundle_index,
            proposal_id,
            choice,
            commitment,
        )
    }

    /// Delete all data for a round.
    pub fn clear_round(&self, round_id: &str) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::clear_round(&conn, round_id, &wallet_id)
    }

    // --- Bundles ---

    /// Persist a previously planned bundle layout for a round.
    ///
    /// Returns `(bundle_count, eligible_weight)`. Only bundles already present in
    /// `plan` are persisted, so caller-owned planning remains the single source
    /// of truth for bundle policy.
    pub(crate) fn persist_bundle_plan(
        &self,
        round_id: &str,
        plan: &ChunkResult,
    ) -> Result<(u32, u64), VotingError> {
        let mut conn = self.conn();
        let wallet_id = self.wallet_id();
        if plan.dropped_count > 0 {
            eprintln!(
                "[persist_bundle_plan] Dropped {} notes in sub-threshold bundles",
                plan.dropped_count,
            );
        }
        let tx = conn.transaction().map_err(|e| VotingError::Internal {
            message: format!("failed to begin bundle setup transaction: {e}"),
        })?;
        for (i, chunk) in plan.bundles.iter().enumerate() {
            queries::insert_bundle_notes(&tx, round_id, &wallet_id, i as u32, chunk)?;
        }
        tx.commit().map_err(|e| VotingError::Internal {
            message: format!("failed to commit bundle setup transaction: {e}"),
        })?;
        Ok((plan.bundles.len() as u32, plan.eligible_weight))
    }

    /// Get the number of bundles for a round.
    pub fn get_bundle_count(&self, round_id: &str) -> Result<u32, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::get_bundle_count(&conn, round_id, &wallet_id)
    }

    /// Ensure synthetic padded-note secrets exist for a delegation bundle.
    ///
    /// These secrets determine the fixed-arity circuit padding nullifiers used
    /// by PIR precompute. They are sampled once per bundle and then treated as
    /// authoritative for later PCZT construction and proving.
    pub fn ensure_padded_secrets(
        &self,
        round_id: &str,
        bundle_index: u32,
        notes: &[NoteInfo],
    ) -> Result<Vec<(Vec<u8>, Vec<u8>)>, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::require_bundle_notes(&conn, round_id, &wallet_id, bundle_index, notes)?;
        let expected_padded_count = BUNDLE_NOTE_SLOTS.saturating_sub(notes.len());

        if let Some(secrets) =
            queries::load_padded_note_secrets_optional(&conn, round_id, &wallet_id, bundle_index)?
        {
            if secrets.len() != expected_padded_count {
                return Err(VotingError::InvalidInput {
                    message: format!(
                        "stored padded_note_secrets count ({}) must match expected padded note count ({expected_padded_count}) for bundle {bundle_index}",
                        secrets.len()
                    ),
                });
            }
            return Ok(secrets);
        }

        let sampled = crate::action::sample_padded_note_secrets(notes.len())?;
        queries::store_padded_note_secrets_if_absent(
            &conn,
            round_id,
            &wallet_id,
            bundle_index,
            &sampled,
        )?;
        let stored = queries::load_padded_note_secrets(&conn, round_id, &wallet_id, bundle_index)?;
        if stored.len() != expected_padded_count {
            return Err(VotingError::Internal {
                message: format!(
                    "stored padded_note_secrets count ({}) changed after initialization; expected {expected_padded_count}",
                    stored.len()
                ),
            });
        }
        Ok(stored)
    }
    // --- Phase 1: Delegation setup ---

    /// Load the account-scoped data needed to sign a persisted delegation PCZT.
    ///
    /// `keys` must be the same [`DelegationKeys`] used for PCZT setup. The
    /// prepared-bundle API enforces that by carrying the original keys across
    /// setup and signing request construction.
    pub fn get_delegation_signing_request(
        &self,
        round_id: &str,
        bundle_index: u32,
        keys: &DelegationKeys,
    ) -> Result<DelegationSigningRequest, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        let stored_network = queries::load_round_network(&conn, round_id, &wallet_id)?;
        validate_network_matches_round(stored_network, keys.network, "delegation keys")?;
        let sighash = queries::load_pczt_sighash(&conn, round_id, &wallet_id, bundle_index)?;
        let alpha = queries::load_alpha(&conn, round_id, &wallet_id, bundle_index)?;

        Ok(DelegationSigningRequest {
            account_index: keys.account_index,
            network: stored_network,
            seed_fingerprint: keys.seed_fingerprint,
            sighash: sighash
                .as_slice()
                .try_into()
                .map_err(|_| VotingError::Internal {
                    message: format!("pczt_sighash must be 32 bytes, got {}", sighash.len()),
                })?,
            alpha: alpha
                .as_slice()
                .try_into()
                .map_err(|_| VotingError::Internal {
                    message: format!("alpha must be 32 bytes, got {}", alpha.len()),
                })?,
        })
    }

    /// Build a governance-specific PCZT for Keystone signing.
    /// Loads round params from db. Notes come from caller.
    /// Computes governance values and builds a PCZT whose governance action
    /// belongs to the selected shielded protocol.
    ///
    /// - `consensus_branch_id`: branch ID active at the stored round snapshot height
    /// - `keys`: wallet account and voting hotkey metadata for the delegation PCZT
    pub fn build_governance_pczt(
        &self,
        round_id: &str,
        bundle_index: u32,
        notes: &[NoteInfo],
        keys: &DelegationKeys,
        consensus_branch_id: u32,
    ) -> Result<GovernancePczt, VotingError> {
        let wallet_id = self.wallet_id();
        let (params, stored_network) = {
            let conn = self.conn();
            let (params, stored_network) =
                queries::load_round_params_with_network(&conn, round_id, &wallet_id)?;
            validate_consensus_branch_id_for_round(
                &params,
                stored_network,
                keys,
                consensus_branch_id,
            )?;
            queries::require_bundle_notes(&conn, round_id, &wallet_id, bundle_index, notes)?;
            (params, stored_network)
        };
        let padded_note_secrets = self.ensure_padded_secrets(round_id, bundle_index, notes)?;
        let result = crate::action::build_governance_pczt(
            notes,
            &params,
            stored_network,
            &keys.fvk_bytes,
            &keys.hotkey_raw_address,
            consensus_branch_id,
            keys.coin_type,
            &keys.seed_fingerprint,
            keys.account_index,
            &keys.round_name,
            &padded_note_secrets,
        )?;
        // Compute total note value from input notes
        let total_note_value: u64 = notes
            .iter()
            .try_fold(0u64, |acc, n| acc.checked_add(n.value))
            .ok_or_else(|| VotingError::InvalidInput {
                message: "total note weight overflows u64".to_string(),
            })?;
        // Persist delegation data fields
        // plus padded_note_secrets and pczt_sighash for ZCA-74 randomness threading.
        let conn = self.conn();
        queries::store_delegation_data_with_pczt_fields(
            &conn,
            round_id,
            &wallet_id,
            bundle_index,
            &result.van_comm_rand,
            &result.dummy_nullifiers,
            &result.rho_signed,
            &result.padded_cmx,
            &result.nf_signed,
            &result.cmx_new,
            &result.alpha,
            &result.rseed_signed,
            &result.rseed_output,
            &result.van,
            total_note_value,
            keys.address_index,
            &result.padded_note_secrets,
            &result.pczt_sighash,
            &result.rk,
            &result.gov_nullifiers,
        )?;
        Ok(result)
    }

    /// Cache tree state fetched from lightwalletd by SDK.
    pub fn store_tree_state(&self, round_id: &str, tree_state: &[u8]) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        let params = queries::load_round_params(&conn, round_id, &wallet_id)?;
        queries::store_tree_state(
            &conn,
            round_id,
            &wallet_id,
            params.snapshot_height,
            tree_state,
        )
    }

    /// Report whether Merkle inclusion witnesses are already cached for a bundle.
    ///
    /// SDK callers use this to skip the expensive witness generation step when a
    /// prior precompute pass already warmed the bundle. Returns `true` when at
    /// least one witness row exists for `(round_id, bundle_index)`.
    pub fn has_witnesses(&self, round_id: &str, bundle_index: u32) -> Result<bool, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::has_witnesses(&conn, round_id, &wallet_id, bundle_index)
    }

    /// Report whether cached witnesses exactly cover the provided bundle notes.
    pub fn has_complete_witnesses(
        &self,
        round_id: &str,
        bundle_index: u32,
        notes: &[NoteInfo],
    ) -> Result<bool, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        let witnesses = queries::load_witnesses(&conn, round_id, &wallet_id, bundle_index)?;
        if witnesses.len() != notes.len() {
            return Ok(false);
        }

        let mut expected = notes
            .iter()
            .map(|note| (note.position, note.commitment.clone()))
            .collect::<Vec<_>>();
        let mut actual = witnesses
            .into_iter()
            .map(|witness| (witness.position, witness.note_commitment))
            .collect::<Vec<_>>();
        expected.sort_unstable();
        actual.sort_unstable();

        Ok(expected == actual)
    }

    /// Verify and cache Merkle inclusion witnesses for notes in a bundle.
    /// Witnesses are generated by the SDK (from wallet DB shard data + frontier)
    /// and passed in here for verification and caching.
    ///
    /// Returns cached witnesses on subsequent calls without re-verification.
    /// Must be called before build_and_prove_delegation.
    pub fn store_witnesses(
        &self,
        round_id: &str,
        bundle_index: u32,
        witnesses: &[WitnessData],
    ) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        let params = queries::load_round_params(&conn, round_id, &wallet_id)?;

        let cached_count = queries::witness_count(&conn, round_id, &wallet_id, bundle_index)?;
        // Return early if already cached
        if cached_count == witnesses.len() {
            return Ok(());
        }

        validate_witnesses_for_round(witnesses, &params)?;

        if cached_count == 0 {
            queries::store_witnesses(&conn, round_id, &wallet_id, bundle_index, witnesses)
        } else {
            drop(conn);
            self.replace_bundle_witnesses(round_id, bundle_index, witnesses)
        }
    }

    /// Verify and replace all cached Merkle inclusion witnesses for a bundle.
    pub fn replace_bundle_witnesses(
        &self,
        round_id: &str,
        bundle_index: u32,
        witnesses: &[WitnessData],
    ) -> Result<(), VotingError> {
        let mut conn = self.conn();
        let wallet_id = self.wallet_id();
        let params = queries::load_round_params(&conn, round_id, &wallet_id)?;
        validate_witnesses_for_round(witnesses, &params)?;
        queries::replace_bundle_witnesses(&mut conn, round_id, &wallet_id, bundle_index, witnesses)
    }

    // --- Phase 2: Delegation proof ---

    /// Fetch and persist PIR-backed IMT non-membership proofs for every ZKP #1
    /// note slot in this bundle: real notes plus the padded note slots that the
    /// delegation circuit will fill.
    ///
    /// This is safe to run before submit/auth: it only needs the note metadata
    /// already in the wallet plus the write-once padded-note rho/rseed pairs.
    /// No spending seed is required.
    ///
    /// The padded-slot nullifiers we cache are derived to match what the
    /// circuit builder asks for at proof-gen time (see
    /// `padded_nullifiers_for_circuit`).
    pub fn precompute_delegation_pir(
        &self,
        round_id: &str,
        bundle_index: u32,
        notes: &[NoteInfo],
        pir_client: &pir_client::PirClientBlocking,
        network: Network,
    ) -> Result<DelegationPirPrecomputeResult, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        let (params, stored_network) =
            queries::load_round_params_with_network(&conn, round_id, &wallet_id)?;
        validate_network_matches_round(stored_network, network, "delegation PIR")?;
        queries::require_bundle_notes(&conn, round_id, &wallet_id, bundle_index, notes)?;
        let padded_secrets =
            queries::load_padded_note_secrets(&conn, round_id, &wallet_id, bundle_index)?;
        let padded_nullifiers =
            padded_nullifiers_for_circuit(notes, &padded_secrets, stored_network)?;
        let targets = delegation_nullifier_targets(notes, &padded_nullifiers)?;

        let mut cached_count = 0u32;
        let mut missing = Vec::new();
        for (nf_bytes, nf) in targets {
            if queries::load_imt_proof(
                &conn,
                round_id,
                &wallet_id,
                bundle_index,
                &nf_bytes,
                &params.nullifier_imt_root,
            )?
            .is_some()
            {
                cached_count += 1;
            } else {
                missing.push((nf_bytes, nf));
            }
        }
        drop(conn);

        if missing.is_empty() {
            return Ok(DelegationPirPrecomputeResult {
                cached_count,
                fetched_count: 0,
            });
        }

        eprintln!(
            "[ZKP1] Precomputing PIR proofs: {} cached, {} missing",
            cached_count,
            missing.len()
        );
        let missing_nullifiers: Vec<_> = missing.iter().map(|(_, nf)| *nf).collect();
        let expected_nf_imt_root = nullifier_imt_root_to_base(&params.nullifier_imt_root)?;
        let raw_fetched_proofs =
            pir_client
                .fetch_proofs(&missing_nullifiers)
                .map_err(|e| VotingError::Internal {
                    message: format!("PIR parallel fetch failed: {e}"),
                })?;
        if raw_fetched_proofs.len() != missing_nullifiers.len() {
            return Err(VotingError::Internal {
                message: format!(
                    "PIR returned {} proofs for {} nullifiers",
                    raw_fetched_proofs.len(),
                    missing_nullifiers.len()
                ),
            });
        }
        let fetched_proofs: Vec<ImtProofData> = raw_fetched_proofs
            .into_iter()
            .zip(missing_nullifiers.iter().copied())
            .map(|(proof, nullifier)| {
                crate::zkp1::validate_and_convert_pir_proof(proof, nullifier, expected_nf_imt_root)
            })
            .collect::<Result<Vec<_>, _>>()?;

        let conn = self.conn();
        let fetched_count = fetched_proofs.len() as u32;
        for ((nf_bytes, _), proof) in missing.iter().zip(fetched_proofs.iter()) {
            queries::store_imt_proof(&conn, round_id, &wallet_id, bundle_index, nf_bytes, proof)?;
        }

        Ok(DelegationPirPrecomputeResult {
            cached_count,
            fetched_count,
        })
    }

    /// Build and prove the real delegation ZKP (#1). Long-running.
    ///
    /// Loads all required data from the voting DB:
    /// - alpha, van_comm_rand from delegation data (stored by `build_governance_pczt`)
    /// - Merkle witnesses (stored by `store_witnesses`)
    /// - Vote round params (stored by `init_round`)
    ///
    /// Notes for this bundle are passed in by the caller (queried from the wallet
    /// by the SDK glue layer).
    ///
    /// Fetches IMT exclusion proofs from the PIR server for each note's nullifier.
    /// For padded notes (< 5 real notes), the prover fetches proofs internally via PIR.
    ///
    /// Stores the proof result and advances phase to `DelegationProved`.
    pub fn build_and_prove_delegation(
        &self,
        round_id: &str,
        bundle_index: u32,
        notes: &[NoteInfo],
        keys: &DelegationKeys,
        pir_client: &pir_client::PirClientBlocking,
        stages: &dyn DelegationProgressReporter,
    ) -> Result<DelegationProofResult, VotingError> {
        let total_start = std::time::Instant::now();

        // Phase 1: DB queries
        let db_start = std::time::Instant::now();
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        let (params, stored_network) =
            queries::load_round_params_with_network(&conn, round_id, &wallet_id)?;
        validate_network_matches_round(stored_network, keys.network, "delegation keys")?;
        queries::require_bundle_notes(&conn, round_id, &wallet_id, bundle_index, notes)?;
        let alpha = queries::load_alpha(&conn, round_id, &wallet_id, bundle_index)?;
        let van_comm_rand = queries::load_van_comm_rand(&conn, round_id, &wallet_id, bundle_index)?;
        let witnesses = queries::load_witnesses(&conn, round_id, &wallet_id, bundle_index)?;
        validate_witnesses_for_round(&witnesses, &params)?;

        // Load Phase 1 randomness for ZCA-74 fix: ensures Phase 2 produces
        // the same nf_signed/cmx_new that Phase 1 committed to in the PCZT.
        let rseed_signed = queries::load_rseed_signed(&conn, round_id, &wallet_id, bundle_index)?;
        let rseed_output = queries::load_rseed_output(&conn, round_id, &wallet_id, bundle_index)?;
        let padded_secrets =
            queries::load_padded_note_secrets(&conn, round_id, &wallet_id, bundle_index)?;
        // These are the zero-value circuit-side padded nullifiers derived
        // from the Phase 1 padded-note rho/rseed pairs.
        let padded_nullifiers =
            padded_nullifiers_for_circuit(notes, &padded_secrets, stored_network)?;

        // Align witnesses (keyed by commitment) to notes order
        let witness_count = witnesses.len();
        if witness_count != notes.len() {
            return Err(VotingError::Internal {
                message: format!(
                    "witness count ({}) does not match note count ({}) for round {} bundle {}",
                    witness_count,
                    notes.len(),
                    round_id,
                    bundle_index,
                ),
            });
        }

        let mut witnesses_by_commitment: HashMap<Vec<u8>, WitnessData> =
            HashMap::with_capacity(witness_count);
        for w in witnesses {
            if witnesses_by_commitment
                .insert(w.note_commitment.clone(), w)
                .is_some()
            {
                return Err(VotingError::Internal {
                    message: "duplicate witness note_commitment in cache".to_string(),
                });
            }
        }

        let mut ordered_witnesses = Vec::with_capacity(notes.len());
        for (i, n) in notes.iter().enumerate() {
            let w = witnesses_by_commitment
                .remove(&n.commitment)
                .ok_or_else(|| VotingError::Internal {
                    message: format!(
                        "missing witness for note[{i}] commitment {}",
                        hex::encode(&n.commitment)
                    ),
                })?;
            ordered_witnesses.push(w);
        }
        if !witnesses_by_commitment.is_empty() {
            return Err(VotingError::Internal {
                message: "extra cached witnesses not matched to selected notes".to_string(),
            });
        }

        let db_elapsed = db_start.elapsed();
        eprintln!(
            "[ZKP1] DB queries: {:.2}s ({} notes, {} witnesses)",
            db_elapsed.as_secs_f64(),
            notes.len(),
            witness_count
        );
        drop(conn);

        // Phase 2: Load/fetch IMT exclusion proofs via PIR.
        let pir_start = std::time::Instant::now();
        let precompute = self.precompute_delegation_pir(
            round_id,
            bundle_index,
            notes,
            pir_client,
            keys.network,
        )?;

        let conn = self.conn();
        let real_targets = delegation_nullifier_targets(notes, &[])?;
        let dummy_targets = delegation_nullifier_targets(&[], &padded_nullifiers)?;
        let mut imt_proofs = Vec::with_capacity(real_targets.len());
        for (nf_bytes, _) in &real_targets {
            let proof = queries::load_imt_proof(
                &conn,
                round_id,
                &wallet_id,
                bundle_index,
                nf_bytes,
                &params.nullifier_imt_root,
            )?
            .ok_or_else(|| VotingError::Internal {
                message: "missing cached IMT proof after PIR precompute".to_string(),
            })?;
            imt_proofs.push(proof);
        }

        let mut extra_imt_proofs = Vec::with_capacity(dummy_targets.len());
        for (nf_bytes, _) in &dummy_targets {
            let proof = queries::load_imt_proof(
                &conn,
                round_id,
                &wallet_id,
                bundle_index,
                nf_bytes,
                &params.nullifier_imt_root,
            )?
            .ok_or_else(|| VotingError::Internal {
                message: "missing cached padded-note IMT proof after PIR precompute".to_string(),
            })?;
            extra_imt_proofs.push((*nf_bytes, proof));
        }
        drop(conn);

        let pir_elapsed = pir_start.elapsed();
        eprintln!(
            "[ZKP1] PIR prep total: {:.2}s ({} cached, {} fetched)",
            pir_elapsed.as_secs_f64(),
            precompute.cached_count,
            precompute.fetched_count
        );

        // Phase 3: Proof generation
        let prove_start = std::time::Instant::now();
        eprintln!("[ZKP1] Starting proof generation...");

        // Parse vote_round_id from hex string to 32-byte field element
        let vote_round_id_bytes =
            hex::decode(&params.vote_round_id).map_err(|e| VotingError::Internal {
                message: format!("invalid vote_round_id hex '{}': {e}", params.vote_round_id),
            })?;

        // Proof generation must reproduce the values already signed in the PCZT
        // instead of sampling new randomness when persisted data is incomplete.
        let precomputed = precomputed_randomness_from_stored(
            notes.len(),
            &padded_secrets,
            &rseed_signed,
            &rseed_output,
            bundle_index,
        )?;

        let result = crate::zkp1::build_and_prove_delegation(
            &notes,
            &keys.hotkey_raw_address,
            &alpha,
            &van_comm_rand,
            &vote_round_id_bytes,
            &ordered_witnesses,
            &imt_proofs,
            &extra_imt_proofs,
            keys.network,
            stages,
            Some(&precomputed),
        )?;
        let prove_elapsed = prove_start.elapsed();
        eprintln!(
            "[ZKP1] Proof generation: {:.2}s",
            prove_elapsed.as_secs_f64()
        );

        // Persist proof bytes, public inputs, and phase together. The public
        // inputs are checked against the PCZT fields before any partial proof
        // success state is committed.
        let mut conn = self.conn();
        let tx = conn.transaction().map_err(|e| VotingError::Internal {
            message: format!("failed to begin proof result transaction: {e}"),
        })?;
        queries::store_proof(&tx, round_id, &wallet_id, bundle_index, &result.proof)?;
        queries::store_proof_result_fields_with_van_comm(
            &tx,
            round_id,
            &wallet_id,
            bundle_index,
            &result.rk,
            &result.gov_nullifiers,
            &result.nf_signed,
            &result.cmx_new,
            &result.van_comm,
        )?;
        queries::advance_round_phase(&tx, round_id, &wallet_id, RoundPhase::DelegationProved)?;
        tx.commit().map_err(|e| VotingError::Internal {
            message: format!("failed to commit proof result transaction: {e}"),
        })?;

        let total_elapsed = total_start.elapsed();
        eprintln!(
            "[ZKP1] TOTAL: {:.2}s (DB: {:.2}s, PIR: {:.2}s, Prove: {:.2}s) — proof {} bytes",
            total_elapsed.as_secs_f64(),
            db_elapsed.as_secs_f64(),
            pir_elapsed.as_secs_f64(),
            prove_elapsed.as_secs_f64(),
            result.proof.len(),
        );

        Ok(result)
    }

    // --- Phase 3: Voting ---

    /// Build vote commitment + ZKP #2 for a proposal. Stores vote in db.
    ///
    /// Loads ZKP #2 inputs (gov_comm_rand, total_note_value, address_index, ea_pk,
    /// voting_round_id) from the DB, derives the SpendingKey from hotkey_seed
    /// using the stored round network after checking it against the vote signer,
    /// and generates a real Halo2 vote proof.
    ///
    /// The builder handles share decomposition and El Gamal encryption internally.
    /// The returned bundle includes the encrypted shares for reveal-share payloads.
    pub(crate) fn build_vote_commitment(
        &self,
        round_id: &str,
        bundle_index: u32,
        hotkey_seed: &[u8],
        signer_network: crate::Network,
        proposal_id: u32,
        choice: u32,
        num_options: u32,
        van_auth_path: &[[u8; 32]],
        van_position: u32,
        anchor_height: u32,
        single_share: bool,
        progress: &dyn ProgressReporter,
    ) -> Result<VoteCommitmentBundle, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        let stored_network = queries::load_round_network(&conn, round_id, &wallet_id)?;
        validate_network_matches_round(stored_network, signer_network, "vote signer")?;
        let zkp2_data = queries::load_zkp2_inputs(&conn, round_id, &wallet_id, bundle_index)?;

        // Decode voting_round_id from hex string to 32 bytes
        let voting_round_id_bytes =
            hex::decode(&zkp2_data.voting_round_id).map_err(|e| VotingError::Internal {
                message: format!(
                    "invalid voting_round_id hex '{}': {e}",
                    zkp2_data.voting_round_id
                ),
            })?;

        let bundle = crate::zkp2::build_vote_commitment(
            hotkey_seed,
            stored_network,
            zkp2_data.address_index,
            zkp2_data.total_note_value,
            &zkp2_data.gov_comm_rand,
            &voting_round_id_bytes,
            &zkp2_data.ea_pk,
            proposal_id,
            choice,
            num_options,
            van_auth_path,
            van_position,
            anchor_height,
            zkp2_data.proposal_authority,
            single_share,
            progress,
        )?;

        // Store the vote commitment as serialized bytes
        let commitment_bytes = serde_json::to_vec(&serde_json::json!({
            "van_nullifier": hex::encode(&bundle.van_nullifier),
            "vote_authority_note_new": hex::encode(&bundle.vote_authority_note_new),
            "vote_commitment": hex::encode(&bundle.vote_commitment),
            "proof": hex::encode(&bundle.proof),
        }))
        .map_err(|e| VotingError::Internal {
            message: format!("failed to serialize vote commitment: {}", e),
        })?;

        queries::store_vote(
            &conn,
            round_id,
            &wallet_id,
            bundle_index,
            proposal_id,
            choice,
            &commitment_bytes,
        )?;
        queries::advance_round_phase(&conn, round_id, &wallet_id, RoundPhase::VoteReady)?;
        Ok(bundle)
    }

    /// Build share payloads for helper server delegation.
    ///
    /// - `vote_decision`: The voter's choice (0-indexed into the proposal's options).
    /// - `num_options`: Number of options declared for this proposal (2-8).
    /// - `vc_tree_position`: Position of the Vote Commitment leaf in the VC tree,
    ///   known after the cast-vote TX is confirmed on chain.
    pub fn build_share_payloads(
        &self,
        enc_shares: &[WireEncryptedShare],
        commitment: &VoteCommitmentBundle,
        vote_decision: u32,
        num_options: u32,
        vc_tree_position: u64,
        single_share: bool,
    ) -> Result<Vec<SharePayload>, VotingError> {
        crate::vote_commitment::build_share_payloads(
            enc_shares,
            commitment,
            vote_decision,
            num_options,
            vc_tree_position,
            single_share,
        )
    }

    /// Store the VAN leaf position after delegation TX is confirmed on chain.
    /// The app calls this after parsing the delegation TX response events.
    pub fn store_van_position(
        &self,
        round_id: &str,
        bundle_index: u32,
        position: u32,
    ) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::store_van_position(&conn, round_id, &wallet_id, bundle_index, position)
    }

    /// Load the VAN leaf position for a bundle.
    pub fn load_van_position(&self, round_id: &str, bundle_index: u32) -> Result<u32, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::load_van_position(&conn, round_id, &wallet_id, bundle_index)
    }

    /// Reconstruct the delegation TX payload using an externally provided signature.
    ///
    /// This does not derive account keys or sign. Instead, the caller supplies
    /// the SpendAuth signature and the ZIP-244 sighash that the wallet signer
    /// signed.
    pub fn get_delegation_submission_with_signature(
        &self,
        round_id: &str,
        bundle_index: u32,
        signature: &[u8],
        sighash: &[u8],
    ) -> Result<DelegationSubmissionData, VotingError> {
        self.get_delegation_submission_with_checked_signature(
            round_id,
            bundle_index,
            signature,
            sighash,
            "signature",
            "sighash",
            "sighash does not match stored PCZT sighash",
        )
    }

    fn get_delegation_submission_with_checked_signature(
        &self,
        round_id: &str,
        bundle_index: u32,
        signature: &[u8],
        sighash: &[u8],
        signature_label: &str,
        sighash_label: &str,
        mismatch_message: &str,
    ) -> Result<DelegationSubmissionData, VotingError> {
        if signature.len() != 64 {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "{signature_label} must be 64 bytes, got {}",
                    signature.len()
                ),
            });
        }
        if sighash.len() != 32 {
            return Err(VotingError::InvalidInput {
                message: format!("{sighash_label} must be 32 bytes, got {}", sighash.len()),
            });
        }

        let conn = self.conn();
        let wallet_id = self.wallet_id();
        let data =
            queries::load_delegation_submission_data(&conn, round_id, &wallet_id, bundle_index)?;
        let stored_sighash = queries::load_pczt_sighash(&conn, round_id, &wallet_id, bundle_index)?;
        if stored_sighash.len() != 32 {
            return Err(VotingError::Internal {
                message: format!(
                    "pczt_sighash must be 32 bytes, got {}",
                    stored_sighash.len()
                ),
            });
        }
        if stored_sighash.as_slice() != sighash {
            return Err(VotingError::InvalidInput {
                message: mismatch_message.to_string(),
            });
        }
        verify_delegation_spend_auth_signature(&data.rk, &stored_sighash, signature)?;

        Ok(DelegationSubmissionData {
            proof: data.proof,
            rk: data.rk,
            nf_signed: data.nf_signed,
            cmx_new: data.cmx_new,
            gov_comm: data.gov_comm,
            gov_nullifiers: data.gov_nullifiers,
            alpha: data.alpha,
            vote_round_id: data.vote_round_id,
            spend_auth_sig: signature.to_vec(),
            sighash: stored_sighash,
        })
    }

    /// Delete bundle rows with index >= `keep_count`, so that only the first
    /// `keep_count` bundles remain. Witnesses and proofs cascade-delete via FK.
    /// Returns the number of deleted rows.
    pub fn delete_skipped_bundles(
        &self,
        round_id: &str,
        keep_count: u32,
    ) -> Result<u64, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::delete_bundles_from(&conn, round_id, &wallet_id, keep_count)
    }

    // --- Recovery state ---

    pub fn store_delegation_tx_hash(
        &self,
        round_id: &str,
        bundle_index: u32,
        tx_hash: &str,
    ) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::store_delegation_tx_hash(&conn, round_id, &wallet_id, bundle_index, tx_hash)
    }

    pub fn get_delegation_tx_hash(
        &self,
        round_id: &str,
        bundle_index: u32,
    ) -> Result<Option<String>, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::get_delegation_tx_hash(&conn, round_id, &wallet_id, bundle_index)
    }

    pub fn get_vote_tx_hash(
        &self,
        round_id: &str,
        bundle_index: u32,
        proposal_id: u32,
    ) -> Result<Option<String>, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::get_vote_tx_hash(&conn, round_id, &wallet_id, bundle_index, proposal_id)
    }

    pub fn record_vote_submission(
        &self,
        round_id: &str,
        bundle_index: u32,
        proposal_id: u32,
        tx_hash: &str,
    ) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::record_vote_submission(
            &conn,
            round_id,
            &wallet_id,
            bundle_index,
            proposal_id,
            tx_hash,
        )
    }

    /// Atomically records a delegation transaction hash with idempotency checks.
    pub fn mark_delegation_submitted(
        &self,
        round_id: &str,
        bundle_index: u32,
        tx_hash: &str,
    ) -> Result<(), VotingError> {
        let wallet_id = self.wallet_id();
        let mut conn = self.conn();
        let tx = conn.transaction().map_err(|e| VotingError::Internal {
            message: format!("begin delegation submitted transaction failed: {e}"),
        })?;
        let stored = queries::get_delegation_tx_hash(&tx, round_id, &wallet_id, bundle_index)?;
        check_text_conflict(stored.as_deref(), tx_hash, "delegation tx_hash")?;
        queries::store_delegation_tx_hash(&tx, round_id, &wallet_id, bundle_index, tx_hash)?;
        tx.commit().map_err(|e| VotingError::Internal {
            message: format!("commit delegation submitted transaction failed: {e}"),
        })
    }

    /// Atomically records a vote transaction hash with idempotency checks.
    pub fn mark_vote_submitted(
        &self,
        round_id: &str,
        bundle_index: u32,
        proposal_id: u32,
        tx_hash: &str,
    ) -> Result<(), VotingError> {
        let wallet_id = self.wallet_id();
        let mut conn = self.conn();
        let tx = conn.transaction().map_err(|e| VotingError::Internal {
            message: format!("begin vote submitted transaction failed: {e}"),
        })?;
        let stored =
            queries::get_vote_tx_hash(&tx, round_id, &wallet_id, bundle_index, proposal_id)?;
        check_text_conflict(stored.as_deref(), tx_hash, "vote tx_hash")?;
        queries::record_vote_submission(
            &tx,
            round_id,
            &wallet_id,
            bundle_index,
            proposal_id,
            tx_hash,
        )?;
        tx.commit().map_err(|e| VotingError::Internal {
            message: format!("commit vote submitted transaction failed: {e}"),
        })
    }

    pub fn get_commitment_bundle(
        &self,
        round_id: &str,
        bundle_index: u32,
        proposal_id: u32,
    ) -> Result<Option<(String, u64)>, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::get_commitment_bundle(&conn, round_id, &wallet_id, bundle_index, proposal_id)
    }

    /// Loads raw commitment-bundle recovery columns for one vote key.
    ///
    /// Unlike `get_commitment_bundle`, this lenient helper does not require
    /// `vc_tree_position` to be set. It is intended for recovery reporting code
    /// that distinguishes "JSON present but position pending" from "no JSON".
    pub(crate) fn get_commitment_bundle_recovery_fields(
        &self,
        round_id: &str,
        bundle_index: u32,
        proposal_id: u32,
    ) -> Result<Option<(Option<String>, Option<i64>)>, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::get_commitment_bundle_recovery(
            &conn,
            round_id,
            &wallet_id,
            bundle_index,
            proposal_id,
        )
    }

    pub fn store_keystone_signature(
        &self,
        round_id: &str,
        bundle_index: u32,
        sig: &[u8],
        sighash: &[u8],
        rk: &[u8],
    ) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::store_keystone_signature(
            &conn,
            round_id,
            &wallet_id,
            bundle_index,
            sig,
            sighash,
            rk,
        )
    }

    pub fn get_keystone_signatures(
        &self,
        round_id: &str,
    ) -> Result<Vec<KeystoneSignatureRecord>, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::get_keystone_signatures(&conn, round_id, &wallet_id)
    }

    /// Clears derived recovery artifacts while preserving the voter's ballot
    /// intent. Use `clear_round`/`delete_round` to remove the whole round,
    /// including recorded decisions.
    pub fn clear_recovery_state(&self, round_id: &str) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::clear_recovery_state(&conn, round_id, &wallet_id)
    }

    /// Clears unsigned delegation setup fields for one round while preserving
    /// submitted bundles and bundles with persisted Keystone signatures.
    pub fn clear_unsigned_delegation_setup_fields(
        &self,
        round_id: &str,
    ) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::clear_unsigned_delegation_setup_fields(&conn, round_id, &wallet_id)
    }

    // --- Share delegation tracking ---

    /// Record a share delegation after sending to helper servers.
    ///
    /// This raw storage helper is crate-internal because callers must provide a
    /// nullifier that matches the persisted vote recovery bundle. Wallet
    /// integrations should use `share::record`, which derives that nullifier
    /// from recovery state.
    pub(crate) fn record_share_delegation(
        &self,
        round_id: &str,
        bundle_index: u32,
        proposal_id: u32,
        share_index: u32,
        sent_to_urls: &[String],
        nullifier: &[u8],
        submit_at: u64,
    ) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::record_share_delegation(
            &conn,
            round_id,
            &wallet_id,
            bundle_index,
            proposal_id,
            share_index,
            sent_to_urls,
            nullifier,
            submit_at,
        )
    }

    /// Load all share delegations for a round.
    pub fn get_share_delegations(
        &self,
        round_id: &str,
    ) -> Result<Vec<crate::ShareDelegationRecord>, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::get_share_delegations(&conn, round_id, &wallet_id)
    }

    /// Load only unconfirmed share delegations for a round.
    pub fn get_unconfirmed_delegations(
        &self,
        round_id: &str,
    ) -> Result<Vec<crate::ShareDelegationRecord>, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::get_unconfirmed_delegations(&conn, round_id, &wallet_id)
    }

    /// Mark a share delegation as confirmed on-chain.
    pub fn mark_share_confirmed(
        &self,
        round_id: &str,
        bundle_index: u32,
        proposal_id: u32,
        share_index: u32,
    ) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::mark_share_confirmed(
            &conn,
            round_id,
            &wallet_id,
            bundle_index,
            proposal_id,
            share_index,
        )
    }

    /// Append new server URLs to a share delegation's sent_to_urls.
    pub fn add_sent_servers(
        &self,
        round_id: &str,
        bundle_index: u32,
        proposal_id: u32,
        share_index: u32,
        new_urls: &[String],
    ) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::add_sent_servers(
            &conn,
            round_id,
            &wallet_id,
            bundle_index,
            proposal_id,
            share_index,
            new_urls,
        )
    }
}

/// Accepts missing or matching text fields and rejects conflicting values.
fn check_text_conflict(
    existing: Option<&str>,
    requested: &str,
    field: &str,
) -> Result<(), VotingError> {
    if let Some(existing) = existing {
        if existing != requested {
            return Err(VotingError::InvalidInput {
                message: format!("{field} conflict: stored {existing}, requested {requested}"),
            });
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::VotingHotkey;

    // 64 hex chars = 32 bytes when decoded. Required because build_governance_pczt
    // hex-decodes vote_round_id and validates it as exactly 32 bytes (a Pallas field element).
    const ROUND_ID: &str = "0101010101010101010101010101010101010101010101010101010101010101";
    const W: &str = "test-wallet";
    const TESTNET_NU6_SNAPSHOT_HEIGHT: u64 = 3_536_500;
    const TESTNET_NU6_BRANCH_ID: u32 = 0x4DEC_4DF0;
    #[cfg(zcash_unstable = "nu6.3")]
    const REGTEST_NU6_3_SNAPSHOT_HEIGHT: u64 = crate::types::REGTEST_NU6_3_ACTIVATION_HEIGHT as u64;

    fn test_db() -> VotingDb {
        let db = VotingDb::open(":memory:").unwrap();
        db.set_wallet_id(W);
        db
    }

    fn test_params() -> VotingRoundParams {
        // Use SpendAuthG as a valid Pallas point for ea_pk in tests.
        use group::GroupEncoding;
        let ea_pk = pasta_curves::pallas::Point::from(voting_circuits::spend_auth_g_affine());
        VotingRoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: TESTNET_NU6_SNAPSHOT_HEIGHT,
            ea_pk: ea_pk.to_bytes().to_vec(),
            nc_root: vec![0xAA; 32],
            nullifier_imt_root: vec![0xBB; 32],
        }
    }

    #[cfg(zcash_unstable = "nu6.3")]
    fn test_params_nu6_3() -> VotingRoundParams {
        VotingRoundParams {
            snapshot_height: REGTEST_NU6_3_SNAPSHOT_HEIGHT,
            ..test_params()
        }
    }

    #[cfg(zcash_unstable = "nu6.3")]
    fn nu6_3_branch_id() -> u32 {
        u32::from(zcash_protocol::consensus::BranchId::Nu6_3)
    }

    fn test_params_with_nc_root(nc_root: Vec<u8>) -> VotingRoundParams {
        VotingRoundParams {
            nc_root,
            ..test_params()
        }
    }

    fn test_delegation_keys(
        fvk_bytes: Vec<u8>,
        voting_hotkey: &VotingHotkey,
        seed_fingerprint: [u8; 32],
        account_index: u32,
    ) -> DelegationKeys {
        DelegationKeys::with_voting_hotkey(
            fvk_bytes,
            voting_hotkey,
            seed_fingerprint,
            account_index,
            "test-round".to_string(),
        )
        .unwrap()
    }

    fn test_randomized_spendauth_signature(
        seed: &[u8],
        account_index: u32,
        alpha: &pallas::Scalar,
        sighash: &[u8; 32],
    ) -> ([u8; 32], [u8; 64]) {
        use orchard::{
            keys::{SpendAuthorizingKey, SpendingKey},
            primitives::redpallas::{SpendAuth, VerificationKey},
        };
        use zcash_keys::keys::UnifiedSpendingKey;
        use zcash_protocol::consensus::TEST_NETWORK;
        use zip32::AccountId;

        let account = AccountId::try_from(account_index).unwrap();
        let usk = UnifiedSpendingKey::from_seed(&TEST_NETWORK, seed, account).unwrap();
        let sk: SpendingKey = *usk.orchard();
        let ask = SpendAuthorizingKey::from(&sk);
        let rsk = ask.randomize(alpha);
        let rk: [u8; 32] = (&VerificationKey::<SpendAuth>::from(&rsk)).into();
        let mut rng = rand::rngs::OsRng;
        let sig = rsk.sign(&mut rng, sighash);

        (rk, (&sig).into())
    }

    #[cfg(zcash_unstable = "nu6.3")]
    fn sign_delegation_request(seed: &[u8], request: &DelegationSigningRequest) -> [u8; 64] {
        use orchard::keys::SpendAuthorizingKey;
        use zcash_keys::keys::UnifiedSpendingKey;
        use zip32::{fingerprint::SeedFingerprint, AccountId};

        let seed_fingerprint = SeedFingerprint::from_seed(seed)
            .expect("test seed length is valid")
            .to_bytes();
        assert_eq!(seed_fingerprint, request.seed_fingerprint);
        let account = AccountId::try_from(request.account_index).unwrap();
        let usk = UnifiedSpendingKey::from_seed(&request.network, seed, account).unwrap();
        let sk = *usk.orchard();
        let ask = SpendAuthorizingKey::from(&sk);
        let alpha = Option::<pallas::Scalar>::from(pallas::Scalar::from_repr(request.alpha))
            .expect("test stores a valid alpha scalar");
        let rsk = ask.randomize(&alpha);
        let mut rng = rand::rngs::OsRng;
        let sig = rsk.sign(&mut rng, &request.sighash);

        (&sig).into()
    }

    struct StaticPirTransport;

    impl pir_client::Transport for StaticPirTransport {
        fn get<'a>(&'a self, url: &'a str) -> pir_client::TransportFuture<'a> {
            Box::pin(async move {
                let path = request_path(url);
                match path {
                    "/tier0" => Ok(transport_response(vec![
                        0;
                        ((1usize
                            << pir_types::TIER0_LAYERS)
                            - 1)
                            * 32
                            + pir_types::TIER1_ROWS * 64
                    ])),
                    "/params/tier1" => Ok(transport_response(
                        serde_json::to_vec(&pir_types::YpirScenario {
                            num_items: pir_types::TIER1_YPIR_ROWS,
                            item_size_bits: pir_types::TIER1_ITEM_BITS,
                        })
                        .unwrap(),
                    )),
                    "/params/tier2" => Ok(transport_response(
                        serde_json::to_vec(&pir_types::YpirScenario {
                            num_items: pir_types::TIER1_YPIR_ROWS,
                            item_size_bits: pir_types::TIER2_ITEM_BITS,
                        })
                        .unwrap(),
                    )),
                    "/root" => Ok(transport_response(
                        serde_json::to_vec(&pir_types::RootInfo {
                            zcash_network: pir_types::ZcashNetwork::Test,
                            nullifier_pool: pir_types::NULLIFIER_POOL.to_owned(),
                            dataset_version: pir_types::DATASET_VERSION,
                            root29: hex::encode([0u8; 32]),
                            root25: hex::encode([0u8; 32]),
                            num_ranges: 1,
                            pir_depth: pir_types::PIR_DEPTH,
                            height: None,
                        })
                        .unwrap(),
                    )),
                    _ => Err(anyhow::anyhow!("unexpected GET {path}")),
                }
            })
        }

        fn post<'a>(&'a self, url: &'a str, _body: Vec<u8>) -> pir_client::TransportFuture<'a> {
            Box::pin(async move {
                Err(anyhow::anyhow!(
                    "unexpected POST {}; proofs should be cached",
                    request_path(url)
                ))
            })
        }
    }

    fn request_path(url: &str) -> &str {
        let without_scheme = url.split_once("://").map(|(_, rest)| rest).unwrap_or(url);
        without_scheme
            .find('/')
            .map(|idx| &without_scheme[idx..])
            .unwrap_or("/")
    }

    fn transport_response(body: Vec<u8>) -> pir_client::TransportResponse {
        pir_client::TransportResponse {
            status: 200,
            headers: Vec::new(),
            body,
        }
    }

    fn identity_test_note() -> NoteInfo {
        NoteInfo {
            commitment: vec![0x01; 32],
            nullifier: vec![0x02; 32],
            value: 13_000_000,
            position: 7,
            diversifier: vec![0x03; 11],
            rho: vec![0x04; 32],
            rseed: vec![0x05; 32],
            scope: 0,
            ufvk_str: "uview1test".to_string(),
        }
    }

    fn identity_note_with_position(position: u8) -> NoteInfo {
        NoteInfo {
            commitment: vec![position; 32],
            nullifier: vec![position.wrapping_add(10); 32],
            value: 13_000_000,
            position: u64::from(position),
            diversifier: vec![0x03; 11],
            rho: vec![0x04; 32],
            rseed: vec![0x05; 32],
            scope: 0,
            ufvk_str: "uview1test".to_string(),
        }
    }

    fn note_info_for_witness(witness: &WitnessData) -> NoteInfo {
        let position = u8::try_from(witness.position).expect("test fixture position fits in u8");
        NoteInfo {
            commitment: witness.note_commitment.clone(),
            nullifier: vec![position.wrapping_add(1); 32],
            value: 13_000_000,
            position: witness.position,
            diversifier: vec![0x03; 11],
            rho: vec![0x04; 32],
            rseed: vec![0x05; 32],
            scope: 0,
            ufvk_str: "uview1test".to_string(),
        }
    }

    fn valid_tree_witness(position: u64, leaf: orchard::tree::MerkleHashOrchard) -> WitnessData {
        use incrementalmerkletree::{Hashable, Level};
        use orchard::tree::MerkleHashOrchard;

        let mut current = leaf;
        let mut auth_path = Vec::with_capacity(32);
        let mut pos = position;

        for level in 0..32 {
            let tree_level = Level::from(level as u8);
            let sibling = if level == 0 {
                MerkleHashOrchard::empty_leaf()
            } else {
                MerkleHashOrchard::empty_root(tree_level)
            };
            auth_path.push(sibling.to_bytes().to_vec());

            current = if pos & 1 == 0 {
                MerkleHashOrchard::combine(tree_level, &current, &sibling)
            } else {
                MerkleHashOrchard::combine(tree_level, &sibling, &current)
            };
            pos >>= 1;
        }

        WitnessData {
            note_commitment: leaf.to_bytes().to_vec(),
            position,
            root: current.to_bytes().to_vec(),
            auth_path,
        }
    }

    fn valid_empty_tree_witness(position: u64) -> WitnessData {
        use incrementalmerkletree::Hashable;
        use orchard::tree::MerkleHashOrchard;

        valid_tree_witness(position, MerkleHashOrchard::empty_leaf())
    }

    fn valid_field_tree_witness(position: u64, value: u64) -> WitnessData {
        use orchard::tree::MerkleHashOrchard;

        let leaf_bytes = pallas::Base::from(value).to_repr();
        let leaf =
            Option::from(MerkleHashOrchard::from_bytes(&leaf_bytes)).expect("field encoding");
        valid_tree_witness(position, leaf)
    }

    fn init_round_for_witnesses(db: &VotingDb, witnesses: &[WitnessData]) {
        let nc_root = witnesses
            .first()
            .expect("test witness fixture is not empty")
            .root
            .clone();
        db.init_round(Network::Testnet, &test_params_with_nc_root(nc_root), None)
            .unwrap();
    }

    #[test]
    fn test_init_and_get_round() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();

        let state = db.get_round_state(ROUND_ID).unwrap();
        assert_eq!(state.phase, RoundPhase::Initialized);
        assert_eq!(state.network, Network::Testnet);
        assert_eq!(state.snapshot_height, TESTNET_NU6_SNAPSHOT_HEIGHT);
    }

    #[test]
    fn test_advance_round_phase_is_idempotent() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();

        db.advance_round_phase(ROUND_ID, RoundPhase::HotkeyGenerated)
            .unwrap();
        db.advance_round_phase(ROUND_ID, RoundPhase::HotkeyGenerated)
            .unwrap();

        let state = db.get_round_state(ROUND_ID).unwrap();
        assert_eq!(state.phase, RoundPhase::HotkeyGenerated);
    }

    #[test]
    fn test_advance_round_phase_rejects_regression() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();

        db.advance_round_phase(ROUND_ID, RoundPhase::DelegationConstructed)
            .unwrap();
        let err = db
            .advance_round_phase(ROUND_ID, RoundPhase::HotkeyGenerated)
            .expect_err("regression should fail");

        assert!(err.to_string().contains("refusing to regress round phase"));
    }

    #[test]
    fn test_has_round_is_scoped_to_wallet() {
        let db = test_db();
        assert!(!db.has_round(ROUND_ID).unwrap());

        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();
        assert!(db.has_round(ROUND_ID).unwrap());

        db.set_wallet_id("other-wallet");
        assert!(!db.has_round(ROUND_ID).unwrap());
    }

    #[test]
    fn test_list_and_clear_rounds() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();

        let rounds = db.list_rounds().unwrap();
        assert_eq!(rounds.len(), 1);

        db.clear_round(ROUND_ID).unwrap();
        assert!(db.list_rounds().unwrap().is_empty());
    }

    #[test]
    fn test_precomputed_randomness_requires_stored_rseeds() {
        let err = match precomputed_randomness_from_stored(5, &[], &[], &[0x11; 32], 0) {
            Ok(_) => panic!("empty signed rseed must fail"),
            Err(err) => err,
        };

        assert!(err.to_string().contains("rseed_signed"), "{err}");
    }

    #[cfg(zcash_unstable = "nu6.3")]
    #[test]
    fn test_padded_pir_nullifiers_match_persisted_dummy_nullifiers() {
        use orchard::{
            note::{NoteVersion, Rho},
            value::NoteValue,
        };
        use rand::rngs::OsRng;
        use zcash_keys::keys::UnifiedSpendingKey;
        use zip32::{AccountId, Scope};

        let seed = [0x42u8; 32];
        let account = AccountId::try_from(0u32).unwrap();
        let usk = UnifiedSpendingKey::from_seed(&Network::Regtest, &seed, account).unwrap();
        let ufvk = usk.to_unified_full_viewing_key();
        let fvk = ufvk.orchard().unwrap().clone();
        let address = fvk.address_at(0u32, Scope::External);

        let mut rng = OsRng;
        let (_, _, parent_note) = orchard::Note::dummy(&mut rng, None, NoteVersion::V3);
        let note = orchard::Note::new(
            address,
            NoteValue::from_raw(13_000_000),
            Rho::from_nf_old(parent_note.nullifier(&fvk)),
            NoteVersion::V3,
            &mut rng,
        );
        let note_info =
            NoteInfo::from_orchard_note(&note, 7, Scope::External, &ufvk, &Network::Regtest)
                .unwrap();

        let db = test_db();
        db.init_round(Network::Regtest, &test_params_nu6_3(), None)
            .unwrap();
        db.ensure_bundles(ROUND_ID, &[note_info.clone()]).unwrap();
        {
            let conn = db.conn();
            let err = queries::load_padded_note_secrets(&conn, ROUND_ID, W, 0).expect_err(
                "padded secrets should only exist after explicit warmup or PCZT construction",
            );
            assert!(
                err.to_string().contains("padded_note_secrets")
                    || err.to_string().contains("delegation data"),
                "{err}"
            );
        }

        let warmed = db
            .ensure_padded_secrets(ROUND_ID, 0, &[note_info.clone()])
            .unwrap();
        assert_eq!(warmed.len(), 4);
        let warmed_again = db
            .ensure_padded_secrets(ROUND_ID, 0, &[note_info.clone()])
            .unwrap();
        assert_eq!(warmed, warmed_again);
        let precompute_nullifiers =
            padded_nullifiers_for_circuit(&[note_info.clone()], &warmed, Network::Regtest).unwrap();
        {
            let conn = db.conn();
            assert!(queries::load_pczt_sighash(&conn, ROUND_ID, W, 0).is_err());
        }

        let voting_hotkey =
            VotingHotkey::from_stored_secret(&[0x43; 64], crate::types::Network::Regtest).unwrap();
        let seed_fingerprint = [0x42u8; 32];
        let keys =
            test_delegation_keys(fvk.to_bytes().to_vec(), &voting_hotkey, seed_fingerprint, 0);

        let result = db
            .build_governance_pczt(ROUND_ID, 0, &[note_info.clone()], &keys, nu6_3_branch_id())
            .unwrap();

        let conn = db.conn();
        let stored_dummy = queries::load_dummy_nullifiers(&conn, ROUND_ID, W, 0).unwrap();
        let padded_secrets = queries::load_padded_note_secrets(&conn, ROUND_ID, W, 0).unwrap();
        let pir_nullifiers =
            padded_nullifiers_for_circuit(&[note_info], &padded_secrets, Network::Regtest).unwrap();

        assert_eq!(result.padded_note_secrets, warmed_again);
        assert_eq!(precompute_nullifiers, result.dummy_nullifiers);
        assert_eq!(stored_dummy, result.dummy_nullifiers);
        assert_eq!(pir_nullifiers, result.dummy_nullifiers);
    }

    #[test]
    fn test_padded_secret_warmup_reuses_cached_pir_proofs_without_pczt() {
        use orchard::{
            note::{NoteVersion, Rho},
            value::NoteValue,
        };
        use rand::rngs::OsRng;
        use voting_circuits::delegation::ImtProvider;
        use zcash_keys::keys::UnifiedSpendingKey;
        use zcash_protocol::consensus::TEST_NETWORK;
        use zip32::{AccountId, Scope};

        let seed = [0x42u8; 32];
        let account = AccountId::try_from(0u32).unwrap();
        let usk = UnifiedSpendingKey::from_seed(&TEST_NETWORK, &seed, account).unwrap();
        let ufvk = usk.to_unified_full_viewing_key();
        let fvk = ufvk.orchard().unwrap().clone();
        let address = fvk.address_at(0u32, Scope::External);

        let mut rng = OsRng;
        let mut notes = Vec::new();
        for position in 0..BUNDLE_NOTE_SLOTS {
            let (_, _, parent_note) = orchard::Note::dummy(&mut rng, None, NoteVersion::V2);
            let note = orchard::Note::new(
                address,
                NoteValue::from_raw(13_000_000),
                Rho::from_nf_old(parent_note.nullifier(&fvk)),
                NoteVersion::V2,
                &mut rng,
            );
            notes.push(
                NoteInfo::from_orchard_note(
                    &note,
                    position as u64,
                    Scope::External,
                    &ufvk,
                    &TEST_NETWORK,
                )
                .unwrap(),
            );
        }

        let imt = voting_circuits::delegation::SpacedLeafImtProvider::new();
        let mut params = test_params();
        params.nullifier_imt_root = imt.root().to_repr().to_vec();

        let db = test_db();
        db.init_round(Network::Testnet, &params, None).unwrap();
        db.ensure_bundles(ROUND_ID, &notes).unwrap();
        {
            let conn = db.conn();
            for note in &notes {
                let nf_bytes: [u8; 32] = note.nullifier.as_slice().try_into().unwrap();
                let nf = Option::from(pallas::Base::from_repr(nf_bytes)).unwrap();
                let proof = imt.non_membership_proof(nf).unwrap();
                queries::store_imt_proof(&conn, ROUND_ID, W, 0, &nf_bytes, &proof).unwrap();
            }
        }

        let pir_client = pir_client::PirClientBlocking::with_transport(
            "https://pir.test",
            std::sync::Arc::new(StaticPirTransport),
        )
        .unwrap();

        db.ensure_padded_secrets(ROUND_ID, 0, &notes).unwrap();
        let result = db
            .precompute_delegation_pir(ROUND_ID, 0, &notes, &pir_client, Network::Testnet)
            .unwrap();

        assert_eq!(result.cached_count, BUNDLE_NOTE_SLOTS as u32);
        assert_eq!(result.fetched_count, 0);
        let conn = db.conn();
        assert!(queries::load_pczt_sighash(&conn, ROUND_ID, W, 0).is_err());
    }

    #[test]
    fn test_precompute_delegation_pir_rejects_network_mismatch() {
        let notes = vec![identity_test_note()];
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();
        db.ensure_bundles(ROUND_ID, &notes).unwrap();

        let pir_client = pir_client::PirClientBlocking::with_transport(
            "https://pir.test",
            std::sync::Arc::new(StaticPirTransport),
        )
        .unwrap();

        let err = db
            .precompute_delegation_pir(ROUND_ID, 0, &notes, &pir_client, Network::Mainnet)
            .unwrap_err();

        assert!(
            err.to_string().contains(
                "delegation PIR network Mainnet does not match stored round network Testnet"
            ),
            "{err}"
        );
    }

    #[test]
    fn test_build_vote_commitment_rejects_network_mismatch_before_zkp2_inputs() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();

        let err = db
            .build_vote_commitment(
                ROUND_ID,
                0,
                &[0x99; 64],
                Network::Mainnet,
                1,
                0,
                2,
                &[[0u8; 32]; crate::vote::VAN_AUTH_PATH_LEN],
                0,
                100,
                false,
                &crate::types::NoopProgressReporter,
            )
            .unwrap_err();

        assert!(
            err.to_string().contains(
                "vote signer network Mainnet does not match stored round network Testnet"
            ),
            "{err}"
        );
    }

    #[test]
    fn test_ensure_bundles() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();

        // A full slot count of 13M notes fits in one default bundle.
        let notes: Vec<NoteInfo> = (0..BUNDLE_NOTE_SLOTS)
            .map(|i| NoteInfo {
                commitment: vec![0x01; 32],
                nullifier: vec![i as u8 + 0x02; 32],
                value: 13_000_000,
                position: i as u64,
                diversifier: vec![0; 11],
                rho: vec![0; 32],
                rseed: vec![0; 32],
                scope: 0,
                ufvk_str: String::new(),
            })
            .collect();

        let layout = db.ensure_bundles(ROUND_ID, &notes).unwrap();
        assert_eq!(layout.bundle_count, 1);
        // Quantized: bundle 0 (65M → 5×12.5M=62.5M) = 62.5M
        assert_eq!(layout.eligible_weight, 62_500_000);
        assert_eq!(db.get_bundle_count(ROUND_ID).unwrap(), 1);
    }

    #[test]
    fn test_ensure_bundles_creates_once_then_reuses_matching_rows() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();
        let notes = vec![identity_test_note()];

        let created = db.ensure_bundles(ROUND_ID, &notes).unwrap();
        let reused = db.ensure_bundles(ROUND_ID, &notes).unwrap();

        assert_eq!(created.bundle_count, 1);
        assert_eq!(created, reused);
        assert_eq!(db.get_bundle_count(ROUND_ID).unwrap(), 1);
    }

    #[test]
    fn test_ensure_bundles_rejects_current_note_selection_drift() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();
        db.ensure_bundles(ROUND_ID, &[identity_test_note()])
            .unwrap();

        let shape_err = db
            .ensure_bundles(
                ROUND_ID,
                &[
                    identity_test_note(),
                    identity_note_with_position(1),
                    identity_note_with_position(2),
                    identity_note_with_position(3),
                    identity_note_with_position(4),
                    identity_note_with_position(5),
                ],
            )
            .expect_err("different bundle count must not match persisted rows");
        assert!(
            shape_err
                .to_string()
                .contains("existing bundle count 1 does not match planned bundle count 2"),
            "{shape_err}"
        );

        let mut substituted = identity_test_note();
        substituted.nullifier[0] ^= 0x01;
        let identity_err = db
            .ensure_bundles(ROUND_ID, &[substituted])
            .expect_err("same-position note substitution must be rejected");
        assert!(
            identity_err.to_string().contains("note identity mismatch"),
            "{identity_err}"
        );
    }

    #[test]
    fn test_ensure_bundles_rolls_back_partial_insert_on_error() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();

        let notes: Vec<NoteInfo> = (0..6)
            .map(|i| NoteInfo {
                commitment: vec![i as u8; 32],
                nullifier: vec![i as u8 + 1; 32],
                value: 13_000_000,
                position: i as u64,
                diversifier: vec![0; 11],
                rho: vec![0; 32],
                rseed: vec![0; 32],
                scope: 0,
                ufvk_str: String::new(),
            })
            .collect();

        {
            let conn = db.conn();
            queries::insert_bundle(&conn, ROUND_ID, W, 1, &[99]).unwrap();
        }

        let plan = crate::note_bundling::chunk_notes(&notes);
        let err = db
            .persist_bundle_plan(ROUND_ID, &plan)
            .expect_err("bundle index conflict should fail setup");
        assert!(err.to_string().contains("failed to insert bundle"));

        let conn = db.conn();
        let bundle_zero_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM bundles
                 WHERE round_id = ?1 AND wallet_id = ?2 AND bundle_index = 0",
                rusqlite::params![ROUND_ID, W],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(bundle_zero_count, 0);
        assert_eq!(queries::get_bundle_count(&conn, ROUND_ID, W).unwrap(), 1);
    }

    #[test]
    fn test_require_bundle_notes_rejects_each_identity_field_substitution() {
        fn mutate_commitment(note: &mut NoteInfo) {
            note.commitment[0] ^= 0x01;
        }
        fn mutate_nullifier(note: &mut NoteInfo) {
            note.nullifier[0] ^= 0x01;
        }
        fn mutate_value(note: &mut NoteInfo) {
            note.value += 1;
        }
        fn mutate_position(note: &mut NoteInfo) {
            note.position += 1;
        }
        fn mutate_diversifier(note: &mut NoteInfo) {
            note.diversifier[0] ^= 0x01;
        }
        fn mutate_rho(note: &mut NoteInfo) {
            note.rho[0] ^= 0x01;
        }
        fn mutate_rseed(note: &mut NoteInfo) {
            note.rseed[0] ^= 0x01;
        }
        fn mutate_scope(note: &mut NoteInfo) {
            note.scope += 1;
        }
        fn mutate_ufvk(note: &mut NoteInfo) {
            note.ufvk_str.push_str("-substituted");
        }

        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();
        let note = identity_test_note();
        let conn = db.conn();
        queries::insert_bundle_notes(&conn, ROUND_ID, W, 0, &[note.clone()]).unwrap();

        let cases: [(&str, fn(&mut NoteInfo)); 9] = [
            ("commitment", mutate_commitment),
            ("nullifier", mutate_nullifier),
            ("value", mutate_value),
            ("position", mutate_position),
            ("diversifier", mutate_diversifier),
            ("rho", mutate_rho),
            ("rseed", mutate_rseed),
            ("scope", mutate_scope),
            ("ufvk_str", mutate_ufvk),
        ];

        for (field, mutate) in cases {
            let mut substituted = note.clone();
            mutate(&mut substituted);

            let err = queries::require_bundle_notes(&conn, ROUND_ID, W, 0, &[substituted])
                .expect_err(field);
            assert!(err.to_string().contains("bundle_index 0"), "{field}: {err}");
        }
    }

    #[test]
    fn test_require_bundle_notes_allows_legacy_position_only_rows() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();
        let note = identity_test_note();
        let conn = db.conn();
        queries::insert_bundle(&conn, ROUND_ID, W, 0, &[note.position]).unwrap();

        let mut substituted = note;
        substituted.nullifier[0] ^= 0x01;
        substituted.rseed[0] ^= 0x01;
        substituted.ufvk_str.push_str("-substituted");

        queries::require_bundle_notes(&conn, ROUND_ID, W, 0, &[substituted]).unwrap();
    }

    #[test]
    fn test_build_governance_pczt_rejects_same_position_note_substitution() {
        use orchard::keys::{FullViewingKey, SpendingKey};

        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();

        let notes = vec![NoteInfo {
            commitment: vec![0x01; 32],
            nullifier: vec![0x02; 32],
            value: 13_000_000,
            position: 0,
            diversifier: vec![0; 11],
            rho: vec![0; 32],
            rseed: vec![0; 32],
            scope: 0,
            ufvk_str: String::new(),
        }];
        db.ensure_bundles(ROUND_ID, &notes).unwrap();

        let mut substituted_notes = notes.clone();
        substituted_notes[0].nullifier = vec![0x03; 32];

        let sk = SpendingKey::from_bytes([0x42; 32]).expect("valid spending key");
        let fvk = FullViewingKey::from(&sk);
        let voting_hotkey =
            VotingHotkey::from_stored_secret(&[0x43; 64], crate::types::Network::Testnet).unwrap();
        let seed_fingerprint = [0x42u8; 32];
        let keys =
            test_delegation_keys(fvk.to_bytes().to_vec(), &voting_hotkey, seed_fingerprint, 0);

        let err = db
            .build_governance_pczt(
                ROUND_ID,
                0,
                &substituted_notes,
                &keys,
                TESTNET_NU6_BRANCH_ID,
            )
            .unwrap_err();

        assert!(err.to_string().contains("note identity mismatch"));
    }

    #[test]
    fn test_build_governance_pczt_rejects_branch_mismatch_before_padded_secrets() {
        use orchard::keys::{FullViewingKey, SpendingKey};

        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();

        let note = identity_test_note();
        db.ensure_bundles(ROUND_ID, &[note.clone()]).unwrap();

        let sk = SpendingKey::from_bytes([0x42; 32]).expect("valid spending key");
        let fvk = FullViewingKey::from(&sk);
        let voting_hotkey =
            VotingHotkey::from_stored_secret(&[0x43; 64], crate::types::Network::Testnet).unwrap();
        let seed_fingerprint = [0x42u8; 32];
        let keys =
            test_delegation_keys(fvk.to_bytes().to_vec(), &voting_hotkey, seed_fingerprint, 0);

        let err = db
            .build_governance_pczt(ROUND_ID, 0, &[note], &keys, 0xC8E7_1055)
            .unwrap_err();

        assert!(
            err.to_string().contains("does not match snapshot height"),
            "{err}"
        );
        let conn = db.conn();
        assert!(
            queries::load_padded_note_secrets_optional(&conn, ROUND_ID, W, 0)
                .unwrap()
                .is_none()
        );
    }

    #[test]
    fn test_build_governance_pczt_rejects_key_network_mismatch_before_padded_secrets() {
        use orchard::keys::{FullViewingKey, SpendingKey};

        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();

        let note = identity_test_note();
        db.ensure_bundles(ROUND_ID, &[note.clone()]).unwrap();

        let sk = SpendingKey::from_bytes([0x42; 32]).expect("valid spending key");
        let fvk = FullViewingKey::from(&sk);
        let voting_hotkey =
            VotingHotkey::from_stored_secret(&[0x43; 64], crate::types::Network::Mainnet).unwrap();
        let seed_fingerprint = [0x42u8; 32];
        let keys =
            test_delegation_keys(fvk.to_bytes().to_vec(), &voting_hotkey, seed_fingerprint, 0);

        let err = db
            .build_governance_pczt(ROUND_ID, 0, &[note], &keys, TESTNET_NU6_BRANCH_ID)
            .unwrap_err();

        assert!(
            err.to_string()
                .contains("does not match stored round network"),
            "{err}"
        );
        let conn = db.conn();
        assert!(
            queries::load_padded_note_secrets_optional(&conn, ROUND_ID, W, 0)
                .unwrap()
                .is_none()
        );
    }

    #[test]
    fn test_get_delegation_signing_request_rejects_key_network_mismatch() {
        use orchard::keys::{FullViewingKey, SpendingKey};

        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();

        let sk = SpendingKey::from_bytes([0x42; 32]).expect("valid spending key");
        let fvk = FullViewingKey::from(&sk);
        let voting_hotkey =
            VotingHotkey::from_stored_secret(&[0x43; 64], crate::types::Network::Mainnet).unwrap();
        let keys = test_delegation_keys(fvk.to_bytes().to_vec(), &voting_hotkey, [0x42; 32], 0);
        let alpha = pallas::Scalar::from(7).to_repr();
        let pczt_sighash = [0x99; 32];

        {
            let conn = db.conn();
            queries::insert_bundle(&conn, ROUND_ID, W, 0, &[0]).unwrap();
            queries::store_delegation_data(
                &conn,
                ROUND_ID,
                W,
                0,
                &[0x11; 32],
                &[],
                &[0x22; 32],
                &[],
                &[0x33; 32],
                &[0x44; 32],
                &alpha,
                &[0x66; 32],
                &[0x77; 32],
                &[0x88; 32],
                1,
                0,
                &[],
                &pczt_sighash,
            )
            .unwrap();
        }

        let err = db
            .get_delegation_signing_request(ROUND_ID, 0, &keys)
            .expect_err("signing request network must match stored round");

        assert!(
            err.to_string().contains(
                "delegation keys network Mainnet does not match stored round network Testnet"
            ),
            "{err}"
        );
    }

    fn store_minimal_delegation_setup(conn: &rusqlite::Connection, alpha: &[u8]) {
        queries::store_delegation_data(
            conn,
            ROUND_ID,
            W,
            0,
            &[0x11; 32],
            &[],
            &[0x22; 32],
            &[],
            &[0x33; 32],
            &[0x44; 32],
            alpha,
            &[0x66; 32],
            &[0x77; 32],
            &[0x88; 32],
            1,
            0,
            &[],
            &[0x99; 32],
        )
        .unwrap();
        queries::store_padded_note_secrets_if_absent(conn, ROUND_ID, W, 0, &[]).unwrap();
    }

    #[test]
    fn test_build_and_prove_delegation_rejects_key_network_mismatch_before_pir() {
        use orchard::keys::{FullViewingKey, SpendingKey};

        let db = test_db();
        let witnesses = vec![valid_empty_tree_witness(0)];
        init_round_for_witnesses(&db, &witnesses);
        let note = note_info_for_witness(&witnesses[0]);
        let alpha = pallas::Scalar::from(7).to_repr();
        {
            let conn = db.conn();
            queries::insert_bundle(&conn, ROUND_ID, W, 0, &[note.position]).unwrap();
            store_minimal_delegation_setup(&conn, &alpha);
            queries::store_witnesses(&conn, ROUND_ID, W, 0, &witnesses).unwrap();
        }

        let sk = SpendingKey::from_bytes([0x42; 32]).expect("valid spending key");
        let fvk = FullViewingKey::from(&sk);
        let voting_hotkey =
            VotingHotkey::from_stored_secret(&[0x43; 64], crate::types::Network::Mainnet).unwrap();
        let keys = test_delegation_keys(fvk.to_bytes().to_vec(), &voting_hotkey, [0x42; 32], 0);
        let pir_client = pir_client::PirClientBlocking::with_transport(
            "https://pir.test",
            std::sync::Arc::new(StaticPirTransport),
        )
        .unwrap();

        let err = db
            .build_and_prove_delegation(
                ROUND_ID,
                0,
                &[note],
                &keys,
                &pir_client,
                &crate::types::NoopProgressReporter,
            )
            .expect_err("prove path must validate delegation key network");

        assert!(
            err.to_string().contains(
                "delegation keys network Mainnet does not match stored round network Testnet"
            ),
            "{err}"
        );
    }

    #[test]
    fn test_build_and_prove_delegation_rejects_raw_wrong_root_witness() {
        use orchard::keys::{FullViewingKey, SpendingKey};

        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();
        let witnesses = vec![valid_empty_tree_witness(0)];
        let note = note_info_for_witness(&witnesses[0]);
        let alpha = pallas::Scalar::from(7).to_repr();
        {
            let conn = db.conn();
            queries::insert_bundle(&conn, ROUND_ID, W, 0, &[note.position]).unwrap();
            store_minimal_delegation_setup(&conn, &alpha);
            queries::store_witnesses(&conn, ROUND_ID, W, 0, &witnesses).unwrap();
        }

        let sk = SpendingKey::from_bytes([0x42; 32]).expect("valid spending key");
        let fvk = FullViewingKey::from(&sk);
        let voting_hotkey =
            VotingHotkey::from_stored_secret(&[0x43; 64], crate::types::Network::Testnet).unwrap();
        let keys = test_delegation_keys(fvk.to_bytes().to_vec(), &voting_hotkey, [0x42; 32], 0);
        let pir_client = pir_client::PirClientBlocking::with_transport(
            "https://pir.test",
            std::sync::Arc::new(StaticPirTransport),
        )
        .unwrap();

        let err = db
            .build_and_prove_delegation(
                ROUND_ID,
                0,
                &[note],
                &keys,
                &pir_client,
                &crate::types::NoopProgressReporter,
            )
            .expect_err("raw witness rows must match stored round root before proving");

        assert!(
            err.to_string()
                .contains("witness root for position 0 does not match stored round nc_root"),
            "{err}"
        );
    }

    #[cfg(zcash_unstable = "nu6.3")]
    #[test]
    fn test_build_governance_pczt_rejects_nu6_3_branch_for_pre_nu6_3_snapshot() {
        use orchard::keys::{FullViewingKey, SpendingKey};
        use zcash_protocol::consensus::BranchId;

        let mut params = test_params();
        params.snapshot_height = u64::from(crate::types::REGTEST_NU6_3_ACTIVATION_HEIGHT) - 1;

        let db = test_db();
        db.init_round(Network::Regtest, &params, None).unwrap();

        let note = identity_test_note();
        db.ensure_bundles(ROUND_ID, &[note.clone()]).unwrap();

        let sk = SpendingKey::from_bytes([0x42; 32]).expect("valid spending key");
        let fvk = FullViewingKey::from(&sk);
        let voting_hotkey =
            VotingHotkey::from_stored_secret(&[0x43; 64], crate::types::Network::Regtest).unwrap();
        let seed_fingerprint = [0x42u8; 32];
        let keys =
            test_delegation_keys(fvk.to_bytes().to_vec(), &voting_hotkey, seed_fingerprint, 0);

        let err = db
            .build_governance_pczt(ROUND_ID, 0, &[note], &keys, u32::from(BranchId::Nu6_3))
            .unwrap_err();

        assert!(
            err.to_string().contains("does not match snapshot height"),
            "{err}"
        );
        let conn = db.conn();
        assert!(
            queries::load_padded_note_secrets_optional(&conn, ROUND_ID, W, 0)
                .unwrap()
                .is_none()
        );
    }

    #[test]
    fn test_store_proof_result_fields_rejects_pczt_mismatch() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();

        let rk = [0x10; 32];
        let wrong_rk = [0x11; 32];
        let gov_nullifiers = vec![vec![0x20; 32]; 5];
        let nf_signed = [0x30; 32];
        let cmx_new = [0x40; 32];
        let van_comm = [0x50; 32];

        let mut conn = db.conn();
        queries::insert_bundle(&conn, ROUND_ID, W, 0, &[0]).unwrap();
        queries::store_delegation_data_with_pczt_fields(
            &conn,
            ROUND_ID,
            W,
            0,
            &[0x01; 32],
            &[],
            &[0x02; 32],
            &[],
            &nf_signed,
            &cmx_new,
            &[0x03; 32],
            &[0x04; 32],
            &[0x05; 32],
            &van_comm,
            1,
            0,
            &[],
            &[0x06; 32],
            &rk,
            &gov_nullifiers,
        )
        .unwrap();

        let tx = conn.transaction().unwrap();
        queries::store_proof(&tx, ROUND_ID, W, 0, &[0xAB; 96]).unwrap();
        let err = queries::store_proof_result_fields_with_van_comm(
            &tx,
            ROUND_ID,
            W,
            0,
            &wrong_rk,
            &gov_nullifiers,
            &nf_signed,
            &cmx_new,
            &van_comm,
        )
        .expect_err("proof rk must match PCZT rk");
        assert!(err.to_string().contains("rk"));
        drop(tx);

        let proof_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM proofs
                 WHERE round_id = ?1 AND wallet_id = ?2 AND bundle_index = ?3",
                rusqlite::params![ROUND_ID, W, 0],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(proof_count, 0);

        queries::store_proof_result_fields_with_van_comm(
            &conn,
            ROUND_ID,
            W,
            0,
            &rk,
            &gov_nullifiers,
            &nf_signed,
            &cmx_new,
            &van_comm,
        )
        .unwrap();
    }

    #[test]
    fn test_store_proof_result_fields_allows_legacy_missing_pczt_fields() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();

        let rk = [0x10; 32];
        let gov_nullifiers = vec![vec![0x20; 32]; 5];
        let nf_signed = [0x30; 32];
        let cmx_new = [0x40; 32];
        let van_comm = [0x50; 32];

        let conn = db.conn();
        queries::insert_bundle(&conn, ROUND_ID, W, 0, &[0]).unwrap();
        queries::store_delegation_data(
            &conn,
            ROUND_ID,
            W,
            0,
            &[0x01; 32],
            &[],
            &[0x02; 32],
            &[],
            &nf_signed,
            &cmx_new,
            &[0x03; 32],
            &[0x04; 32],
            &[0x05; 32],
            &van_comm,
            1,
            0,
            &[],
            &[0x06; 32],
        )
        .unwrap();

        queries::store_proof_result_fields_with_van_comm(
            &conn,
            ROUND_ID,
            W,
            0,
            &rk,
            &gov_nullifiers,
            &nf_signed,
            &cmx_new,
            &van_comm,
        )
        .unwrap();
    }

    #[test]
    fn test_store_and_load_tree_state() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();

        let tree_state = vec![0xCC; 1024];
        db.store_tree_state(ROUND_ID, &tree_state).unwrap();

        let conn = db.conn();
        let loaded = queries::load_tree_state(&conn, ROUND_ID, W).unwrap();
        assert_eq!(loaded, tree_state);
    }

    #[test]
    fn test_get_commitment_bundle_rejects_missing_tree_position() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();
        let conn = db.conn();
        queries::insert_bundle(&conn, ROUND_ID, W, 0, &[0]).unwrap();
        queries::store_vote(&conn, ROUND_ID, W, 0, 1, 0, b"commitment").unwrap();
        conn.execute(
            "UPDATE votes SET commitment_bundle_json = '{}', vc_tree_position = NULL \
             WHERE round_id = ?1 AND wallet_id = ?2 AND bundle_index = 0 AND proposal_id = 1",
            rusqlite::params![ROUND_ID, W],
        )
        .unwrap();

        let err = queries::get_commitment_bundle(&conn, ROUND_ID, W, 0, 1)
            .expect_err("stored commitment bundle without position should fail");

        assert!(
            err.to_string().contains("refusing to assume position 0"),
            "{err}"
        );
    }

    #[test]
    fn has_witnesses_reflects_cached_state() {
        let db = test_db();
        let witnesses = vec![valid_empty_tree_witness(0), valid_empty_tree_witness(1)];
        init_round_for_witnesses(&db, &witnesses);
        let notes = witnesses
            .iter()
            .map(note_info_for_witness)
            .collect::<Vec<_>>();

        {
            let conn = db.conn();
            queries::insert_bundle(&conn, ROUND_ID, W, 0, &[0, 1]).unwrap();
        }

        assert!(!db.has_witnesses(ROUND_ID, 0).unwrap());
        assert!(!db.has_complete_witnesses(ROUND_ID, 0, &notes).unwrap());

        db.store_witnesses(ROUND_ID, 0, &witnesses[..1]).unwrap();

        assert!(db.has_witnesses(ROUND_ID, 0).unwrap());
        assert!(!db.has_complete_witnesses(ROUND_ID, 0, &notes).unwrap());

        db.store_witnesses(ROUND_ID, 0, &witnesses).unwrap();

        assert!(db.has_complete_witnesses(ROUND_ID, 0, &notes).unwrap());
        // A bundle index that was never warmed still reports no witnesses.
        assert!(!db.has_witnesses(ROUND_ID, 1).unwrap());
    }

    #[test]
    fn test_store_witnesses_rejects_wrong_round_root() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();
        let witnesses = vec![valid_empty_tree_witness(0)];

        {
            let conn = db.conn();
            queries::insert_bundle(&conn, ROUND_ID, W, 0, &[0]).unwrap();
        }

        let err = db
            .store_witnesses(ROUND_ID, 0, &witnesses)
            .expect_err("witness root must match stored round root");

        assert!(
            err.to_string()
                .contains("witness root for position 0 does not match stored round nc_root"),
            "{err}"
        );
        assert!(!db.has_witnesses(ROUND_ID, 0).unwrap());
    }

    #[test]
    fn test_replace_bundle_witnesses_replaces_cached_bundle() {
        let db = test_db();
        let original = vec![valid_empty_tree_witness(0), valid_empty_tree_witness(1)];
        init_round_for_witnesses(&db, &original);

        {
            let conn = db.conn();
            queries::insert_bundle(&conn, ROUND_ID, W, 0, &[0, 1]).unwrap();
        }

        db.store_witnesses(ROUND_ID, 0, &original).unwrap();

        let ignored = vec![
            valid_field_tree_witness(0, 7),
            valid_field_tree_witness(1, 8),
        ];
        // This second store is a no-op because the complete bundle already has cached rows;
        // replacement below is what actually overwrites the cache.
        db.store_witnesses(ROUND_ID, 0, &ignored).unwrap();

        {
            let conn = db.conn();
            let loaded = queries::load_witnesses(&conn, ROUND_ID, W, 0).unwrap();
            assert_eq!(loaded.len(), 2);
            assert_eq!(loaded[0].position, 0);
            assert_eq!(loaded[1].position, 1);
        }

        let replacement = vec![valid_empty_tree_witness(0), valid_empty_tree_witness(1)];
        db.replace_bundle_witnesses(ROUND_ID, 0, &replacement)
            .unwrap();

        let conn = db.conn();
        let loaded = queries::load_witnesses(&conn, ROUND_ID, W, 0).unwrap();
        assert_eq!(loaded.len(), 2);
        assert_eq!(loaded[0].position, 0);
        assert_eq!(loaded[1].position, 1);
        assert_eq!(loaded[0].note_commitment, replacement[0].note_commitment);
        assert_eq!(loaded[1].note_commitment, replacement[1].note_commitment);
    }

    #[test]
    fn test_replace_bundle_witnesses_rejects_wrong_round_root_without_clearing_cache() {
        let db = test_db();
        let original = vec![valid_empty_tree_witness(0), valid_empty_tree_witness(1)];
        init_round_for_witnesses(&db, &original);

        {
            let conn = db.conn();
            queries::insert_bundle(&conn, ROUND_ID, W, 0, &[0, 1]).unwrap();
        }

        db.store_witnesses(ROUND_ID, 0, &original).unwrap();

        let invalid_replacement = vec![
            valid_field_tree_witness(0, 7),
            valid_field_tree_witness(1, 8),
        ];
        let err = db
            .replace_bundle_witnesses(ROUND_ID, 0, &invalid_replacement)
            .expect_err("replacement witness root must match stored round root");
        assert!(
            err.to_string()
                .contains("witness root for position 0 does not match stored round nc_root"),
            "{err}"
        );

        let conn = db.conn();
        let loaded = queries::load_witnesses(&conn, ROUND_ID, W, 0).unwrap();
        assert_eq!(loaded.len(), 2);
        assert_eq!(loaded[0].note_commitment, original[0].note_commitment);
        assert_eq!(loaded[1].note_commitment, original[1].note_commitment);
    }

    #[test]
    fn test_replace_bundle_witnesses_rejects_position_mismatch_without_clearing_cache() {
        let db = test_db();
        let original = vec![valid_empty_tree_witness(0), valid_empty_tree_witness(1)];
        init_round_for_witnesses(&db, &original);

        {
            let conn = db.conn();
            queries::insert_bundle(&conn, ROUND_ID, W, 0, &[0, 1]).unwrap();
        }

        db.store_witnesses(ROUND_ID, 0, &original).unwrap();

        let invalid_replacement = vec![valid_empty_tree_witness(2)];
        let err = db
            .replace_bundle_witnesses(ROUND_ID, 0, &invalid_replacement)
            .expect_err("position mismatch should fail");
        assert!(err
            .to_string()
            .contains("witness positions do not match bundle note positions"));

        let conn = db.conn();
        let loaded = queries::load_witnesses(&conn, ROUND_ID, W, 0).unwrap();
        assert_eq!(loaded.len(), 2);
        assert_eq!(loaded[0].position, 0);
        assert_eq!(loaded[1].position, 1);
        assert_eq!(loaded[0].note_commitment, original[0].note_commitment);
        assert_eq!(loaded[1].note_commitment, original[1].note_commitment);
    }

    #[test]
    fn test_record_vote_submission() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();
        db.ensure_bundles(
            ROUND_ID,
            &[NoteInfo {
                commitment: vec![0x01; 32],
                nullifier: vec![0x02; 32],
                value: 13_000_000,
                position: 0,
                diversifier: vec![0; 11],
                rho: vec![0; 32],
                rseed: vec![0; 32],
                scope: 0,
                ufvk_str: String::new(),
            }],
        )
        .unwrap();

        db.insert_vote_fixture(ROUND_ID, 0, 0, 0, &[0xAA; 32])
            .unwrap();
        db.record_vote_submission(ROUND_ID, 0, 0, "vote-tx")
            .unwrap();
        db.record_vote_submission(ROUND_ID, 0, 0, "vote-tx")
            .unwrap();

        let err = db
            .record_vote_submission(ROUND_ID, 0, 99, "vote-tx")
            .unwrap_err();
        assert!(matches!(err, VotingError::InvalidInput { .. }));
    }

    #[test]
    fn test_mark_recovery_submission_writes_are_idempotent_and_conflict_checked() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();
        db.ensure_bundles(ROUND_ID, &[identity_test_note()])
            .unwrap();
        db.insert_vote_fixture(ROUND_ID, 0, 1, 0, &[0xAA; 32])
            .unwrap();

        db.mark_delegation_submitted(ROUND_ID, 0, "delegation-tx")
            .unwrap();
        db.mark_delegation_submitted(ROUND_ID, 0, "delegation-tx")
            .unwrap();
        let delegation_tx_conflict = db
            .mark_delegation_submitted(ROUND_ID, 0, "delegation-tx-2")
            .unwrap_err();
        assert!(delegation_tx_conflict
            .to_string()
            .contains("delegation tx_hash conflict"));

        db.mark_vote_submitted(ROUND_ID, 0, 1, "vote-tx").unwrap();
        db.mark_vote_submitted(ROUND_ID, 0, 1, "vote-tx").unwrap();
        let vote_tx_conflict = db
            .mark_vote_submitted(ROUND_ID, 0, 1, "vote-tx-2")
            .unwrap_err();
        assert!(vote_tx_conflict
            .to_string()
            .contains("vote tx_hash conflict"));
    }

    #[test]
    fn test_get_commitment_bundle_recovery_fields_reports_pending_position() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();
        db.ensure_bundles(ROUND_ID, &[identity_test_note()])
            .unwrap();
        db.insert_vote_fixture(ROUND_ID, 0, 1, 0, &[0xAA; 32])
            .unwrap();
        db.conn()
            .execute(
                "UPDATE votes SET commitment_bundle_json = :json, vc_tree_position = NULL
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                   AND bundle_index = 0 AND proposal_id = 1",
                rusqlite::named_params! {
                    ":json": r#"{"bundle":"pending"}"#,
                    ":round_id": ROUND_ID,
                    ":wallet_id": W,
                },
            )
            .unwrap();

        let fields = db
            .get_commitment_bundle_recovery_fields(ROUND_ID, 0, 1)
            .unwrap();

        assert_eq!(
            fields,
            Some((Some(r#"{"bundle":"pending"}"#.to_string()), None))
        );
    }

    #[test]
    fn test_recovery_stores_require_existing_rows() {
        fn assert_invalid_input(err: VotingError, expected: &str) {
            assert!(matches!(err, VotingError::InvalidInput { .. }), "{err}");
            assert!(err.to_string().contains(expected), "{err}");
        }

        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();

        assert_invalid_input(
            db.store_delegation_tx_hash(ROUND_ID, 0, "delegation-tx")
                .expect_err("missing bundle must fail"),
            "no bundle found",
        );

        db.ensure_bundles(ROUND_ID, &[identity_test_note()])
            .unwrap();
        db.store_delegation_tx_hash(ROUND_ID, 0, "delegation-tx")
            .unwrap();
        assert_eq!(
            db.get_delegation_tx_hash(ROUND_ID, 0).unwrap(),
            Some("delegation-tx".to_string())
        );
        assert_invalid_input(
            db.store_delegation_tx_hash(ROUND_ID, 0, "delegation-tx-2")
                .expect_err("different delegation tx hash must fail"),
            "delegation tx hash already recorded",
        );
        assert_eq!(
            db.get_delegation_tx_hash(ROUND_ID, 0).unwrap(),
            Some("delegation-tx".to_string())
        );
        assert_invalid_input(
            db.store_delegation_tx_hash(ROUND_ID, 1, "delegation-tx")
                .expect_err("missing bundle index must fail"),
            "no bundle found",
        );

        assert_invalid_input(
            db.record_vote_submission(ROUND_ID, 0, 1, "vote-tx")
                .expect_err("missing vote row must fail"),
            "no vote found",
        );
        db.insert_vote_fixture(ROUND_ID, 0, 1, 0, &[0xAA; 32])
            .unwrap();
        db.record_vote_submission(ROUND_ID, 0, 1, "vote-tx")
            .unwrap();
        assert_eq!(
            db.get_vote_tx_hash(ROUND_ID, 0, 1).unwrap(),
            Some("vote-tx".to_string())
        );
        db.record_vote_submission(ROUND_ID, 0, 1, "vote-tx")
            .unwrap();
        assert_invalid_input(
            db.record_vote_submission(ROUND_ID, 0, 1, "vote-tx-2")
                .expect_err("different submitted tx hash must fail"),
            "tx hash already recorded",
        );

        assert_invalid_input(
            db.record_vote_submission(ROUND_ID, 0, 2, "vote-tx")
                .expect_err("missing proposal row must fail"),
            "no vote found",
        );
    }

    #[test]
    fn test_clear_recovery_state_resets_vote_recovery() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();
        db.ensure_bundles(ROUND_ID, &[identity_test_note()])
            .unwrap();
        db.insert_vote_fixture(ROUND_ID, 0, 1, 0, &[0xAA; 32])
            .unwrap();
        db.record_vote_submission(ROUND_ID, 0, 1, "vote-tx")
            .unwrap();

        db.clear_recovery_state(ROUND_ID).unwrap();

        let vote = db
            .get_votes(ROUND_ID)
            .unwrap()
            .into_iter()
            .find(|vote| vote.proposal_id == 1)
            .expect("vote row remains");
        assert_eq!(vote.choice, 0);
        assert_eq!(db.get_vote_tx_hash(ROUND_ID, 0, 1).unwrap(), None);
    }

    #[test]
    fn test_insert_vote_fixture() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();
        db.ensure_bundles(
            ROUND_ID,
            &[NoteInfo {
                commitment: vec![0x01; 32],
                nullifier: vec![0x02; 32],
                value: 13_000_000,
                position: 0,
                diversifier: vec![0; 11],
                rho: vec![0; 32],
                rseed: vec![0; 32],
                scope: 0,
                ufvk_str: String::new(),
            }],
        )
        .unwrap();

        db.insert_vote_fixture(ROUND_ID, 0, 7, 1, &[0xAA; 32])
            .unwrap();

        let votes = db.get_votes(ROUND_ID).unwrap();
        assert_eq!(votes.len(), 1);
        assert_eq!(votes[0].bundle_index, 0);
        assert_eq!(votes[0].proposal_id, 7);
        assert_eq!(votes[0].choice, 1);
    }

    #[cfg(zcash_unstable = "nu6.3")]
    #[test]
    fn test_delegation_signing_request_signature_path_submits() {
        use orchard::{
            note::{NoteVersion, Rho},
            value::NoteValue,
        };
        use rand::rngs::OsRng;
        use zcash_keys::keys::UnifiedSpendingKey;
        use zip32::{fingerprint::SeedFingerprint, AccountId, Scope};

        struct StaticBranchId(u32);

        impl crate::delegate::BranchIdProvider for StaticBranchId {
            fn consensus_branch_id(&self) -> Result<u32, VotingError> {
                Ok(self.0)
            }
        }

        let db = test_db();
        db.init_round(Network::Regtest, &test_params_nu6_3(), None)
            .unwrap();

        let sender_seed = [0x42; 32];
        let account_index = 0;
        let account = AccountId::try_from(account_index).unwrap();
        let usk = UnifiedSpendingKey::from_seed(&Network::Regtest, &sender_seed, account).unwrap();
        let ufvk = usk.to_unified_full_viewing_key();
        let fvk = ufvk.orchard().unwrap().clone();
        let address = fvk.address_at(0u32, Scope::External);
        let mut rng = OsRng;
        let (_, _, parent_note) = orchard::Note::dummy(&mut rng, None, NoteVersion::V3);
        let note = orchard::Note::new(
            address,
            NoteValue::from_raw(13_000_000),
            Rho::from_nf_old(parent_note.nullifier(&fvk)),
            NoteVersion::V3,
            &mut rng,
        );
        let note_info =
            NoteInfo::from_orchard_note(&note, 7, Scope::External, &ufvk, &Network::Regtest)
                .unwrap();
        db.ensure_bundles(ROUND_ID, &[note_info.clone()]).unwrap();

        let voting_hotkey =
            VotingHotkey::from_stored_secret(&[0x43; 64], crate::types::Network::Regtest).unwrap();
        let seed_fingerprint = SeedFingerprint::from_seed(&sender_seed).unwrap().to_bytes();
        let keys = test_delegation_keys(
            fvk.to_bytes().to_vec(),
            &voting_hotkey,
            seed_fingerprint,
            account_index,
        );
        let setup = crate::delegate::setup(
            &db,
            ROUND_ID,
            0,
            &[note_info],
            &keys,
            &StaticBranchId(nu6_3_branch_id()),
            &crate::types::NoopProgressReporter,
        )
        .unwrap();
        queries::store_proof(&db.conn(), ROUND_ID, W, 0, &[0xAC; 96]).unwrap();

        let request = crate::delegate::signing_request(&db, ROUND_ID, 0, &keys).unwrap();
        assert_eq!(request.account_index, account_index);
        assert_eq!(request.network, crate::types::Network::Regtest);
        assert_eq!(request.seed_fingerprint, seed_fingerprint);
        assert_eq!(request.sighash, setup.pczt_sighash);

        let signature = sign_delegation_request(&sender_seed, &request);
        let submission = crate::delegate::submission(
            &db,
            ROUND_ID,
            0,
            crate::delegate::DelegationSigner::signature(signature, request.sighash),
        )
        .unwrap();

        assert_eq!(submission.rk, setup.rk);
        assert_eq!(submission.sighash, setup.pczt_sighash);
        assert_eq!(submission.spend_auth_sig, signature);
    }

    #[test]
    fn test_get_delegation_submission_with_signature_requires_stored_sighash() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();

        let stored_sighash = [0x99; 32];
        let wrong_sighash = [0x98; 32];
        let alpha = pallas::Scalar::from(7);
        let alpha_bytes = alpha.to_repr();
        let sender_seed = [0x42; 64];
        let (rk, signature) =
            test_randomized_spendauth_signature(&sender_seed, 0, &alpha, &stored_sighash);
        let (_, wrong_signature) =
            test_randomized_spendauth_signature(&sender_seed, 1, &alpha, &stored_sighash);

        {
            let conn = db.conn();
            queries::insert_bundle(&conn, ROUND_ID, W, 0, &[0]).unwrap();
            queries::store_delegation_data(
                &conn,
                ROUND_ID,
                W,
                0,
                &[0x11; 32],
                &[],
                &[0x22; 32],
                &[],
                &[0x33; 32],
                &[0x44; 32],
                &alpha_bytes,
                &[0x66; 32],
                &[0x77; 32],
                &[0x88; 32],
                1,
                0,
                &[],
                &stored_sighash,
            )
            .unwrap();
            queries::store_proof_result_fields_with_van_comm(
                &conn,
                ROUND_ID,
                W,
                0,
                &rk,
                &[vec![0x89; 32]],
                &[0x33; 32],
                &[0x44; 32],
                &[0x88; 32],
            )
            .unwrap();
            queries::store_proof(&conn, ROUND_ID, W, 0, &[0xAC; 96]).unwrap();
        }

        let err = db
            .get_delegation_submission_with_signature(ROUND_ID, 0, &signature, &wrong_sighash)
            .expect_err("mismatched sighash must fail");
        assert!(matches!(err, VotingError::InvalidInput { .. }));
        assert!(err
            .to_string()
            .contains("sighash does not match stored PCZT sighash"));

        let err = db
            .get_delegation_submission_with_signature(
                ROUND_ID,
                0,
                &wrong_signature,
                &stored_sighash,
            )
            .expect_err("wrong account signature must fail");
        assert!(matches!(err, VotingError::InvalidInput { .. }));
        assert!(err
            .to_string()
            .contains("signature does not verify against stored delegation rk and sighash"));

        let submission = db
            .get_delegation_submission_with_signature(ROUND_ID, 0, &signature, &stored_sighash)
            .unwrap();
        assert_eq!(submission.spend_auth_sig, signature.to_vec());
        assert_eq!(submission.sighash, stored_sighash.to_vec());
    }

    /// Multi-bundle test: 6 notes → 2 bundles (5+1), independent delegation + vote storage per bundle.
    #[cfg(zcash_unstable = "nu6.3")]
    #[test]
    fn test_multi_bundle_delegation_and_voting() {
        use orchard::keys::{FullViewingKey, SpendingKey};

        let db = test_db();
        db.init_round(Network::Regtest, &test_params_nu6_3(), None)
            .unwrap();

        // Create 6 notes with distinct positions and unique nullifiers
        let notes: Vec<NoteInfo> = (0..6)
            .map(|i| NoteInfo {
                commitment: vec![0x01; 32],
                nullifier: {
                    let mut nf = vec![0u8; 32];
                    nf[0] = i as u8;
                    nf
                },
                value: 13_000_000,
                position: i as u64,
                diversifier: vec![0; 11],
                rho: vec![0; 32],
                rseed: vec![0; 32],
                scope: 0,
                ufvk_str: String::new(),
            })
            .collect();

        // Setup bundles: 6 equal-value notes → sequential fill packs first 5, then 1
        // Sorted by value DESC (all equal) then position ASC: [0,1,2,3,4,5]
        // Bundle 0 = [0,1,2,3,4], bundle 1 = [5]
        let layout = db.ensure_bundles(ROUND_ID, &notes).unwrap();
        assert_eq!(layout.bundle_count, 2);
        // Quantized: bundle 0 (65M → 5×12.5M=62.5M) + bundle 1 (13M → 1×12.5M=12.5M) = 75M
        assert_eq!(layout.eligible_weight, 75_000_000);
        assert_eq!(db.get_bundle_count(ROUND_ID).unwrap(), 2);

        // Verify note positions per bundle (sequential fill)
        let conn = db.conn();
        let positions_0 = queries::load_bundle_note_positions(&conn, ROUND_ID, W, 0).unwrap();
        assert_eq!(positions_0, vec![0, 1, 2, 3, 4]);
        let positions_1 = queries::load_bundle_note_positions(&conn, ROUND_ID, W, 1).unwrap();
        assert_eq!(positions_1, vec![5]);
        drop(conn);

        // Derive keys for build_governance_pczt
        let sk = SpendingKey::from_bytes([0x42; 32]).expect("valid spending key");
        let fvk = FullViewingKey::from(&sk);
        let fvk_bytes = fvk.to_bytes().to_vec();
        let voting_hotkey =
            VotingHotkey::from_stored_secret(&[0x43; 64], crate::types::Network::Regtest).unwrap();
        let seed_fingerprint = [0x42u8; 32];
        let keys = test_delegation_keys(fvk_bytes.clone(), &voting_hotkey, seed_fingerprint, 0);

        // Build governance PCZT for each bundle independently
        let chunk_result = crate::note_bundling::chunk_notes(&notes);

        for (i, chunk) in chunk_result.bundles.iter().enumerate() {
            let result = db
                .build_governance_pczt(ROUND_ID, i as u32, chunk, &keys, nu6_3_branch_id())
                .unwrap();

            // Each bundle should have valid delegation data
            assert_eq!(result.rk.len(), 32);
            assert_eq!(result.van.len(), 32);
            assert_eq!(result.gov_nullifiers.len(), BUNDLE_NOTE_SLOTS);
            assert_eq!(result.pczt_sighash.len(), 32);

            // Verify data persisted per bundle
            let conn = db.conn();
            let stored_rand = queries::load_van_comm_rand(&conn, ROUND_ID, W, i as u32).unwrap();
            assert_eq!(stored_rand, result.van_comm_rand);
            let stored_alpha = queries::load_alpha(&conn, ROUND_ID, W, i as u32).unwrap();
            assert_eq!(stored_alpha, result.alpha);

            // ZKP2 inputs loadable per bundle
            let zkp2 = queries::load_zkp2_inputs(&conn, ROUND_ID, W, i as u32).unwrap();
            assert_eq!(zkp2.gov_comm_rand.len(), 32);
        }

        // Store VAN positions for each bundle
        db.store_van_position(ROUND_ID, 0, 100).unwrap();
        db.store_van_position(ROUND_ID, 1, 101).unwrap();
        assert_eq!(
            queries::load_van_position(&db.conn(), ROUND_ID, W, 0).unwrap(),
            100
        );
        assert_eq!(
            queries::load_van_position(&db.conn(), ROUND_ID, W, 1).unwrap(),
            101
        );

        // Store votes for proposal 0 across both bundles
        let conn = db.conn();
        queries::store_vote(&conn, ROUND_ID, W, 0, 0, 0, &[0xAA; 32]).unwrap();
        queries::store_vote(&conn, ROUND_ID, W, 1, 0, 0, &[0xBB; 32]).unwrap();
        drop(conn);

        let votes = db.get_votes(ROUND_ID).unwrap();
        assert_eq!(votes.len(), 2);
        assert_eq!(votes[0].bundle_index, 0);
        assert_eq!(votes[1].bundle_index, 1);

        // Record bundle 0's vote submission, verify bundle 1 still has no tx.
        db.record_vote_submission(ROUND_ID, 0, 0, "vote-tx")
            .unwrap();
        assert_eq!(
            db.get_vote_tx_hash(ROUND_ID, 0, 0).unwrap().as_deref(),
            Some("vote-tx")
        );
        assert_eq!(db.get_vote_tx_hash(ROUND_ID, 1, 0).unwrap(), None);

        // Verify proposal_authority reflects per-bundle submission state
        let conn = db.conn();
        let zkp2_0 = queries::load_zkp2_inputs(&conn, ROUND_ID, W, 0).unwrap();
        assert_eq!(zkp2_0.proposal_authority, 0xFFFF & !(1u64 << 0)); // bit 0 cleared
        let zkp2_1 = queries::load_zkp2_inputs(&conn, ROUND_ID, W, 1).unwrap();
        assert_eq!(zkp2_1.proposal_authority, 0xFFFF); // no bits cleared
        drop(conn);

        // Verify cascade: clearing the round removes everything
        db.clear_round(ROUND_ID).unwrap();
        assert!(db.list_rounds().unwrap().is_empty());
        assert_eq!(db.get_bundle_count(ROUND_ID).unwrap(), 0);
    }

    /// Share delegation lifecycle: record → query → confirm → resubmit → re-record preserves confirmed.
    #[test]
    fn test_share_delegation_lifecycle() {
        let db = test_db();
        db.init_round(Network::Testnet, &test_params(), None)
            .unwrap();
        db.ensure_bundles(
            ROUND_ID,
            &[NoteInfo {
                commitment: vec![0x01; 32],
                nullifier: vec![0x02; 32],
                value: 13_000_000,
                position: 0,
                diversifier: vec![0; 11],
                rho: vec![0; 32],
                rseed: vec![0; 32],
                scope: 0,
                ufvk_str: String::new(),
            }],
        )
        .unwrap();

        let urls_a = vec!["https://helper-a.example".to_string()];
        let urls_b = vec!["https://helper-b.example".to_string()];
        let nf = vec![0xDD; 32];

        // Record two share delegations (share 0 and share 1)
        db.record_share_delegation(ROUND_ID, 0, 0, 0, &urls_a, &nf, 1000)
            .unwrap();
        db.record_share_delegation(ROUND_ID, 0, 0, 1, &urls_b, &nf, 2000)
            .unwrap();

        // Query all — should return both
        let all = db.get_share_delegations(ROUND_ID).unwrap();
        assert_eq!(all.len(), 2);

        // Both unconfirmed
        let unconfirmed = db.get_unconfirmed_delegations(ROUND_ID).unwrap();
        assert_eq!(unconfirmed.len(), 2);

        // Confirm share 0
        db.mark_share_confirmed(ROUND_ID, 0, 0, 0).unwrap();

        // Only share 1 remains unconfirmed
        let unconfirmed = db.get_unconfirmed_delegations(ROUND_ID).unwrap();
        assert_eq!(unconfirmed.len(), 1);
        assert_eq!(unconfirmed[0].share_index, 1);

        // Confirming again is idempotent
        db.mark_share_confirmed(ROUND_ID, 0, 0, 0).unwrap();

        // Resubmit share 1 to additional servers
        let urls_c = vec!["https://helper-c.example".to_string()];
        db.add_sent_servers(ROUND_ID, 0, 0, 1, &urls_c).unwrap();

        // Verify URLs merged and deduplicated
        let all = db.get_share_delegations(ROUND_ID).unwrap();
        let share1 = all.iter().find(|s| s.share_index == 1).unwrap();
        assert!(share1
            .sent_to_urls
            .contains(&"https://helper-b.example".to_string()));
        assert!(share1
            .sent_to_urls
            .contains(&"https://helper-c.example".to_string()));
        assert_eq!(share1.sent_to_urls.len(), 2);
        // submit_at reset to 0 after resubmission
        assert_eq!(share1.submit_at, 0);

        let conflicting_nf = vec![0xEE; 32];
        let err = db
            .record_share_delegation(ROUND_ID, 0, 0, 1, &urls_b, &conflicting_nf, 2000)
            .unwrap_err();
        assert!(
            err.to_string().contains("share nullifier conflict"),
            "unexpected error: {err}"
        );

        // Re-record a confirmed share (e.g. recovery path) — confirmed must be preserved
        db.record_share_delegation(ROUND_ID, 0, 0, 0, &urls_a, &nf, 3000)
            .unwrap();
        let all = db.get_share_delegations(ROUND_ID).unwrap();
        let share0 = all.iter().find(|s| s.share_index == 0).unwrap();
        assert!(
            share0.confirmed,
            "ON CONFLICT must preserve confirmed status"
        );
        assert_eq!(share0.submit_at, 3000, "submit_at should be updated");

        // Confirm non-existent share — should error
        let err = db.mark_share_confirmed(ROUND_ID, 0, 99, 0);
        assert!(err.is_err());
    }
}
