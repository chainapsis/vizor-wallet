// The PIR-RPC helpers and orchestration methods at the top of this file are
// gated behind the `client` feature. When that feature is off, several
// imports below are only reachable from `#[cfg(test)]` code, which is fine
// for `cargo test` but trips `unused_imports` on `cargo check`. Silence that
// narrow case rather than fragment the imports along feature/test lines.
#![cfg_attr(not(feature = "client-pir"), allow(unused_imports, dead_code))]

use std::collections::HashMap;

use ff::PrimeField;
use orchard::{
    keys::{FullViewingKey, Scope},
    note::{Note, RandomSeed, Rho},
    value::NoteValue,
};
use pasta_curves::pallas;
use voting_circuits::delegation::imt::ImtProofData;
use zcash_keys::keys::UnifiedFullViewingKey;
use zcash_protocol::consensus::Network;

use crate::storage::queries;
use crate::storage::{
    KeystoneSignatureRecord, RoundPhase, RoundState, RoundSummary, VoteRecord, VotingDb,
};
use crate::types::{
    DelegationPirPrecomputeResult, DelegationProofResult, DelegationSubmissionData, EncryptedShare,
    GovernancePczt, NoteInfo, ProofProgressReporter, SharePayload, VoteCommitmentBundle,
    VotingError, VotingHotkey, VotingRoundParams, WireEncryptedShare, WitnessData,
};

#[cfg(feature = "client-pir")]
fn nullifier_bytes_to_base(bytes: &[u8], label: &str) -> Result<pallas::Base, VotingError> {
    let nf_bytes: [u8; 32] = bytes.try_into().map_err(|_| VotingError::Internal {
        message: format!("{label} nullifier must be 32 bytes, got {}", bytes.len()),
    })?;
    Option::from(pallas::Base::from_repr(nf_bytes)).ok_or_else(|| VotingError::Internal {
        message: format!("{label} nullifier is not a valid field element"),
    })
}

#[cfg(feature = "client-pir")]
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

#[cfg(feature = "client-pir")]
fn nullifier_imt_root_to_base(bytes: &[u8]) -> Result<pallas::Base, VotingError> {
    let root_bytes: [u8; 32] = bytes.try_into().map_err(|_| VotingError::Internal {
        message: format!("nullifier_imt_root must be 32 bytes, got {}", bytes.len()),
    })?;
    Option::from(pallas::Base::from_repr(root_bytes)).ok_or_else(|| VotingError::Internal {
        message: "nullifier_imt_root is not a valid field element".to_string(),
    })
}

/// Derive the padded-slot nullifiers the way the delegation circuit builder
/// does: `Note::from_parts(fvk.address_at(1000+i, External), NoteValue::ZERO,
/// rho, rseed)` then `note.nullifier(&fvk)`.
///
/// The `dummy_nullifiers` DB column is populated from these same zero-value
/// padded notes. This helper recomputes from the stored rho/rseed pairs so PIR
/// precompute and proof generation share the exact circuit-side derivation.
#[cfg(feature = "client-pir")]
fn padded_nullifiers_for_circuit(
    notes: &[NoteInfo],
    padded_secrets: &[(Vec<u8>, Vec<u8>)],
    network_id: u32,
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

    let network = match network_id {
        0 => Network::TestNetwork,
        1 => Network::MainNetwork,
        _ => {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "invalid network_id {network_id}, expected 0 (testnet) or 1 (mainnet)"
                ),
            })
        }
    };
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
        let pad_addr = fvk.address_at((1000 + i_slot) as u32, Scope::External);
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
        let pad_note: Note = Option::from(Note::from_parts(pad_addr, NoteValue::ZERO, rho, rseed))
            .ok_or_else(|| VotingError::Internal {
                message: format!("padded[{i_pad}] note construction failed"),
            })?;
        out.push(pad_note.nullifier(&fvk).to_bytes().to_vec());
    }
    Ok(out)
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

impl VotingDb {
    // --- Round management ---

    /// Initialize a new voting round. Stores params, sets phase to Initialized.
    pub fn init_round(
        &self,
        params: &VotingRoundParams,
        session_json: Option<&str>,
    ) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::insert_round(&conn, &wallet_id, params, session_json)
    }

    /// Get the current state of a voting round.
    pub fn get_round_state(&self, round_id: &str) -> Result<RoundState, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::get_round_state(&conn, round_id, &wallet_id)
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

    /// Get all votes for a round (with choice, bundle_index, and submitted status).
    pub fn get_votes(&self, round_id: &str) -> Result<Vec<VoteRecord>, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::get_votes(&conn, round_id, &wallet_id)
    }

    /// Test-fixture helper for inserting a stored vote without running the
    /// full vote proof builder.
    ///
    /// This is intended for downstream FFI tests that need recovery-state rows
    /// backed by a vote. It is only compiled for this crate's tests or when the
    /// `test-fixtures` feature is explicitly enabled.
    #[cfg(any(test, feature = "test-fixtures"))]
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

    /// Split notes into value-aware bundles of up to 5 and insert bundle rows.
    /// Returns (bundle_count, eligible_weight) — only bundles meeting the BALLOT_DIVISOR
    /// threshold are created. Notes in sub-threshold bundles are dropped.
    pub fn setup_bundles(
        &self,
        round_id: &str,
        notes: &[NoteInfo],
    ) -> Result<(u32, u64), VotingError> {
        let mut conn = self.conn();
        let wallet_id = self.wallet_id();
        let result = crate::types::chunk_notes(notes);
        if result.dropped_count > 0 {
            eprintln!(
                "[setup_bundles] Dropped {} notes in sub-threshold bundles (eligible: {} of {} notes)",
                result.dropped_count,
                notes.len() - result.dropped_count,
                notes.len()
            );
        }
        let tx = conn.transaction().map_err(|e| VotingError::Internal {
            message: format!("failed to begin bundle setup transaction: {e}"),
        })?;
        for (i, chunk) in result.bundles.iter().enumerate() {
            queries::insert_bundle_notes(&tx, round_id, &wallet_id, i as u32, chunk)?;
        }
        tx.commit().map_err(|e| VotingError::Internal {
            message: format!("failed to commit bundle setup transaction: {e}"),
        })?;
        Ok((result.bundles.len() as u32, result.eligible_weight))
    }

    /// Get the number of bundles for a round.
    pub fn get_bundle_count(&self, round_id: &str) -> Result<u32, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::get_bundle_count(&conn, round_id, &wallet_id)
    }

    // --- Phase 1: Delegation setup ---

    /// Generate a voting hotkey from seed bytes. Returns the hotkey (SDK needs address for Keystone flow).
    /// The seed comes from a BIP39 mnemonic stored in iOS Keychain.
    pub fn generate_hotkey(
        &self,
        _round_id: &str,
        seed: &[u8],
    ) -> Result<VotingHotkey, VotingError> {
        crate::hotkey::generate_hotkey(seed)
    }

    /// Build a governance-specific PCZT for Keystone signing.
    /// Loads round params from db. Notes come from caller.
    /// Computes governance values and builds a PCZT whose single Orchard action
    /// IS the governance dummy action (spend of signed note → output to hotkey).
    ///
    /// - `fvk_bytes`: 96-byte orchard FullViewingKey (ak[32] || nk[32] || rivk[32])
    /// - `hotkey_raw_address`: 43-byte hotkey raw orchard address (for output note)
    /// - `consensus_branch_id`: NU6 = 0xC8E71055
    /// - `coin_type`: 133 (mainnet) or 1 (testnet)
    /// - `seed_fingerprint`: 32-byte ZIP-32 seed fingerprint for Keystone signing
    /// - `account_index`: ZIP-32 account index (typically 0)
    pub fn build_governance_pczt(
        &self,
        round_id: &str,
        bundle_index: u32,
        notes: &[NoteInfo],
        fvk_bytes: &[u8],
        hotkey_raw_address: &[u8],
        consensus_branch_id: u32,
        coin_type: u32,
        seed_fingerprint: &[u8; 32],
        account_index: u32,
        round_name: &str,
        address_index: u32,
    ) -> Result<GovernancePczt, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        let params = queries::load_round_params(&conn, round_id, &wallet_id)?;
        queries::require_bundle_notes(&conn, round_id, &wallet_id, bundle_index, notes)?;
        let result = crate::action::build_governance_pczt(
            notes,
            &params,
            fvk_bytes,
            hotkey_raw_address,
            consensus_branch_id,
            coin_type,
            seed_fingerprint,
            account_index,
            round_name,
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
            address_index,
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

        // Return early if already cached
        if queries::has_witnesses(&conn, round_id, &wallet_id, bundle_index)? {
            return Ok(());
        }

        verify_witnesses(witnesses)?;

        // Cache results
        queries::store_witnesses(&conn, round_id, &wallet_id, bundle_index, witnesses)?;

        Ok(())
    }

    /// Verify and replace all cached Merkle inclusion witnesses for a bundle.
    pub fn replace_bundle_witnesses(
        &self,
        round_id: &str,
        bundle_index: u32,
        witnesses: &[WitnessData],
    ) -> Result<(), VotingError> {
        verify_witnesses(witnesses)?;

        let mut conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::replace_bundle_witnesses(&mut conn, round_id, &wallet_id, bundle_index, witnesses)
    }

    // --- Phase 2: Delegation proof ---

    /// Fetch and persist PIR-backed IMT non-membership proofs for every ZKP #1
    /// note slot in this bundle: real notes plus the padded note slots that the
    /// delegation circuit will fill.
    ///
    /// This is safe to run before submit/auth: it only needs the note metadata
    /// already in the wallet plus the padded-note rho/rseed pairs that
    /// `build_governance_pczt` already wrote to the bundles row. No spending
    /// seed is required.
    ///
    /// The padded-slot nullifiers we cache are derived to match what the
    /// circuit builder asks for at proof-gen time (see
    /// `padded_nullifiers_for_circuit`).
    #[cfg(feature = "client-pir")]
    pub fn precompute_delegation_pir(
        &self,
        round_id: &str,
        bundle_index: u32,
        notes: &[NoteInfo],
        pir_client: &pir_client::PirClientBlocking,
        network_id: u32,
    ) -> Result<DelegationPirPrecomputeResult, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        let params = queries::load_round_params(&conn, round_id, &wallet_id)?;
        queries::require_bundle_notes(&conn, round_id, &wallet_id, bundle_index, notes)?;
        let padded_secrets =
            queries::load_padded_note_secrets(&conn, round_id, &wallet_id, bundle_index)?;
        let padded_nullifiers = padded_nullifiers_for_circuit(notes, &padded_secrets, network_id)?;
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
    #[cfg(feature = "client-pir")]
    pub fn build_and_prove_delegation(
        &self,
        round_id: &str,
        bundle_index: u32,
        notes: &[NoteInfo],
        hotkey_raw_address: &[u8],
        pir_client: &pir_client::PirClientBlocking,
        network_id: u32,
        progress: &dyn ProofProgressReporter,
    ) -> Result<DelegationProofResult, VotingError> {
        let total_start = std::time::Instant::now();

        // Phase 1: DB queries
        let db_start = std::time::Instant::now();
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        let params = queries::load_round_params(&conn, round_id, &wallet_id)?;
        queries::require_bundle_notes(&conn, round_id, &wallet_id, bundle_index, notes)?;
        let alpha = queries::load_alpha(&conn, round_id, &wallet_id, bundle_index)?;
        let van_comm_rand = queries::load_van_comm_rand(&conn, round_id, &wallet_id, bundle_index)?;
        let witnesses = queries::load_witnesses(&conn, round_id, &wallet_id, bundle_index)?;

        // Load Phase 1 randomness for ZCA-74 fix: ensures Phase 2 produces
        // the same nf_signed/cmx_new that Phase 1 committed to in the PCZT.
        let rseed_signed = queries::load_rseed_signed(&conn, round_id, &wallet_id, bundle_index)?;
        let rseed_output = queries::load_rseed_output(&conn, round_id, &wallet_id, bundle_index)?;
        let padded_secrets =
            queries::load_padded_note_secrets(&conn, round_id, &wallet_id, bundle_index)?;
        // These are the zero-value circuit-side padded nullifiers derived
        // from the Phase 1 padded-note rho/rseed pairs.
        let padded_nullifiers = padded_nullifiers_for_circuit(notes, &padded_secrets, network_id)?;

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
        let precompute =
            self.precompute_delegation_pir(round_id, bundle_index, notes, pir_client, network_id)?;

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

        // Construct PrecomputedRandomness from Phase 1 values (ZCA-74 fix).
        // If padded_note_secrets is empty (e.g. test data with no PCZT),
        // we fall back to None and the builder will sample fresh randomness.
        let precomputed = if !padded_secrets.is_empty() || !rseed_signed.is_empty() {
            use voting_circuits::delegation::builder::PaddedNoteData;
            let padded_notes: Vec<PaddedNoteData> = padded_secrets
                .iter()
                .map(|(rho, rseed)| {
                    let mut rho_arr = [0u8; 32];
                    let mut rseed_arr = [0u8; 32];
                    rho_arr.copy_from_slice(rho);
                    rseed_arr.copy_from_slice(rseed);
                    PaddedNoteData {
                        rho: rho_arr,
                        rseed: rseed_arr,
                    }
                })
                .collect();
            let mut rseed_signed_arr = [0u8; 32];
            rseed_signed_arr.copy_from_slice(&rseed_signed);
            let mut rseed_output_arr = [0u8; 32];
            rseed_output_arr.copy_from_slice(&rseed_output);
            Some(
                voting_circuits::delegation::builder::PrecomputedRandomness {
                    padded_notes,
                    rseed_signed: rseed_signed_arr,
                    rseed_output: rseed_output_arr,
                },
            )
        } else {
            None
        };

        let result = crate::zkp1::build_and_prove_delegation(
            &notes,
            hotkey_raw_address,
            &alpha,
            &van_comm_rand,
            &vote_round_id_bytes,
            &ordered_witnesses,
            &imt_proofs,
            &extra_imt_proofs,
            network_id,
            progress,
            precomputed.as_ref(),
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

    /// Encrypt voting shares under ea_pk. Loads ea_pk from round params.
    pub fn encrypt_shares(
        &self,
        round_id: &str,
        shares: &[u64],
    ) -> Result<Vec<EncryptedShare>, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        let params = queries::load_round_params(&conn, round_id, &wallet_id)?;
        crate::elgamal::encrypt_shares(shares, &params.ea_pk)
    }

    /// Build vote commitment + ZKP #2 for a proposal. Stores vote in db.
    ///
    /// Loads ZKP #2 inputs (gov_comm_rand, total_note_value, address_index, ea_pk,
    /// voting_round_id) from the DB, derives the SpendingKey from hotkey_seed,
    /// and generates a real Halo2 vote proof.
    ///
    /// The builder handles share decomposition and El Gamal encryption internally.
    /// The returned bundle includes the encrypted shares for reveal-share payloads.
    pub fn build_vote_commitment(
        &self,
        round_id: &str,
        bundle_index: u32,
        hotkey_seed: &[u8],
        network_id: u32,
        proposal_id: u32,
        choice: u32,
        num_options: u32,
        van_auth_path: &[[u8; 32]],
        van_position: u32,
        anchor_height: u32,
        single_share: bool,
        progress: &dyn ProofProgressReporter,
    ) -> Result<VoteCommitmentBundle, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
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
            network_id,
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

    /// Reconstruct the full chain-ready delegation TX payload from DB + seed.
    ///
    /// After `build_and_prove_delegation` completes, all proof artifacts (proof, rk,
    /// gov_nullifiers, nf_signed, cmx_new, gov_comm, alpha) are persisted in the DB.
    /// This method loads them, derives the sender's SpendingKey from seed, loads the
    /// ZIP-244 sighash (stored during PCZT construction), signs it, and returns
    /// everything the chain needs.
    pub fn get_delegation_submission(
        &self,
        round_id: &str,
        bundle_index: u32,
        sender_seed: &[u8],
        network_id: u32,
        account_index: u32,
    ) -> Result<DelegationSubmissionData, VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        let data =
            queries::load_delegation_submission_data(&conn, round_id, &wallet_id, bundle_index)?;
        let sighash_vec = queries::load_pczt_sighash(&conn, round_id, &wallet_id, bundle_index)?;
        drop(conn);

        let sighash: [u8; 32] =
            sighash_vec
                .as_slice()
                .try_into()
                .map_err(|_| VotingError::Internal {
                    message: format!("pczt_sighash must be 32 bytes, got {}", sighash_vec.len()),
                })?;

        // Derive sender SpendingKey from the same ZIP-32 account used to build the PCZT.
        let sk =
            crate::zkp2::derive_spending_key_for_account(sender_seed, network_id, account_index)?;
        let ask = orchard::keys::SpendAuthorizingKey::from(&sk);

        // Deserialize alpha
        let alpha_arr: [u8; 32] =
            data.alpha
                .as_slice()
                .try_into()
                .map_err(|_| VotingError::Internal {
                    message: format!("alpha must be 32 bytes, got {}", data.alpha.len()),
                })?;
        let alpha: pasta_curves::pallas::Scalar =
            Option::from(pasta_curves::pallas::Scalar::from_repr(alpha_arr)).ok_or_else(|| {
                VotingError::Internal {
                    message: "alpha is not a valid Pallas scalar".to_string(),
                }
            })?;

        // Compute rsk = ask.randomize(alpha)
        let rsk = ask.randomize(&alpha);

        // Sign the ZIP-244 sighash (extracted from PCZT during Phase 1)
        let mut rng = rand::rngs::OsRng;
        let sig = rsk.sign(&mut rng, &sighash);
        let sig_bytes: [u8; 64] = (&sig).into();

        Ok(DelegationSubmissionData {
            proof: data.proof,
            rk: data.rk,
            nf_signed: data.nf_signed,
            cmx_new: data.cmx_new,
            gov_comm: data.gov_comm,
            gov_nullifiers: data.gov_nullifiers,
            alpha: data.alpha,
            vote_round_id: data.vote_round_id,
            spend_auth_sig: sig_bytes.to_vec(),
            sighash: sighash.to_vec(),
        })
    }

    /// Reconstruct the delegation TX payload using a Keystone-provided signature.
    ///
    /// Unlike `get_delegation_submission`, this does NOT derive `ask` from a seed
    /// or re-sign. Instead, it uses the externally-provided Keystone signature
    /// and the ZIP-244 sighash that Keystone signed.
    pub fn get_delegation_submission_with_keystone_sig(
        &self,
        round_id: &str,
        bundle_index: u32,
        keystone_sig: &[u8],
        keystone_sighash: &[u8],
    ) -> Result<DelegationSubmissionData, VotingError> {
        if keystone_sig.len() != 64 {
            return Err(VotingError::InvalidInput {
                message: format!("keystone_sig must be 64 bytes, got {}", keystone_sig.len()),
            });
        }
        if keystone_sighash.len() != 32 {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "keystone_sighash must be 32 bytes, got {}",
                    keystone_sighash.len()
                ),
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
        if stored_sighash.as_slice() != keystone_sighash {
            return Err(VotingError::InvalidInput {
                message: "keystone_sighash does not match stored PCZT sighash".to_string(),
            });
        }

        Ok(DelegationSubmissionData {
            proof: data.proof,
            rk: data.rk,
            nf_signed: data.nf_signed,
            cmx_new: data.cmx_new,
            gov_comm: data.gov_comm,
            gov_nullifiers: data.gov_nullifiers,
            alpha: data.alpha,
            vote_round_id: data.vote_round_id,
            spend_auth_sig: keystone_sig.to_vec(),
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

    /// Mark a vote as submitted to the vote chain.
    pub fn mark_vote_submitted(
        &self,
        round_id: &str,
        bundle_index: u32,
        proposal_id: u32,
    ) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::mark_vote_submitted(&conn, round_id, &wallet_id, bundle_index, proposal_id)
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

    pub fn store_vote_tx_hash(
        &self,
        round_id: &str,
        bundle_index: u32,
        proposal_id: u32,
        tx_hash: &str,
    ) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::store_vote_tx_hash(
            &conn,
            round_id,
            &wallet_id,
            bundle_index,
            proposal_id,
            tx_hash,
        )
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

    pub fn store_commitment_bundle(
        &self,
        round_id: &str,
        bundle_index: u32,
        proposal_id: u32,
        bundle_json: &str,
        vc_tree_position: u64,
    ) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::store_commitment_bundle(
            &conn,
            round_id,
            &wallet_id,
            bundle_index,
            proposal_id,
            bundle_json,
            vc_tree_position,
        )
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

    pub fn clear_recovery_state(&self, round_id: &str) -> Result<(), VotingError> {
        let conn = self.conn();
        let wallet_id = self.wallet_id();
        queries::clear_recovery_state(&conn, round_id, &wallet_id)
    }

    // --- Share delegation tracking ---

    /// Record a share delegation after sending to helper servers.
    pub fn record_share_delegation(
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

#[cfg(test)]
mod tests {
    use super::*;

    // 64 hex chars = 32 bytes when decoded. Required because build_governance_pczt
    // hex-decodes vote_round_id and validates it as exactly 32 bytes (a Pallas field element).
    const ROUND_ID: &str = "0101010101010101010101010101010101010101010101010101010101010101";
    const W: &str = "test-wallet";

    fn test_db() -> VotingDb {
        let db = VotingDb::open(":memory:").unwrap();
        db.set_wallet_id(W);
        db
    }

    fn test_params() -> VotingRoundParams {
        // Use SpendAuthG as a valid Pallas point for ea_pk in tests.
        use group::GroupEncoding;
        let ea_pk =
            pasta_curves::pallas::Point::from(voting_circuits::vote_proof::spend_auth_g_affine());
        VotingRoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 1000,
            ea_pk: ea_pk.to_bytes().to_vec(),
            nc_root: vec![0xAA; 32],
            nullifier_imt_root: vec![0xBB; 32],
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

    #[test]
    fn test_init_and_get_round() {
        let db = test_db();
        db.init_round(&test_params(), None).unwrap();

        let state = db.get_round_state(ROUND_ID).unwrap();
        assert_eq!(state.phase, RoundPhase::Initialized);
        assert_eq!(state.snapshot_height, 1000);
    }

    #[test]
    fn test_advance_round_phase_is_idempotent() {
        let db = test_db();
        db.init_round(&test_params(), None).unwrap();

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
        db.init_round(&test_params(), None).unwrap();

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

        db.init_round(&test_params(), None).unwrap();
        assert!(db.has_round(ROUND_ID).unwrap());

        db.set_wallet_id("other-wallet");
        assert!(!db.has_round(ROUND_ID).unwrap());
    }

    #[test]
    fn test_list_and_clear_rounds() {
        let db = test_db();
        db.init_round(&test_params(), None).unwrap();

        let rounds = db.list_rounds().unwrap();
        assert_eq!(rounds.len(), 1);

        db.clear_round(ROUND_ID).unwrap();
        assert!(db.list_rounds().unwrap().is_empty());
    }

    #[test]
    fn test_generate_hotkey() {
        let db = test_db();
        let seed = [0x42_u8; 64];
        let hotkey = db.generate_hotkey(ROUND_ID, &seed).unwrap();
        assert_eq!(hotkey.secret_key.len(), 32);
        assert_eq!(hotkey.public_key.len(), 32);
    }

    #[test]
    fn test_setup_bundles() {
        let db = test_db();
        db.init_round(&test_params(), None).unwrap();

        // 5 notes each 13M — all fit in 1 bundle (capacity 5)
        let notes: Vec<NoteInfo> = (0..5)
            .map(|i| NoteInfo {
                commitment: vec![0x01; 32],
                nullifier: vec![0x02; 32],
                value: 13_000_000,
                position: i as u64,
                diversifier: vec![0; 11],
                rho: vec![0; 32],
                rseed: vec![0; 32],
                scope: 0,
                ufvk_str: String::new(),
            })
            .collect();

        let (count, eligible) = db.setup_bundles(ROUND_ID, &notes).unwrap();
        assert_eq!(count, 1);
        // Quantized: bundle 0 (65M → 5×12.5M=62.5M) = 62.5M
        assert_eq!(eligible, 62_500_000);
        assert_eq!(db.get_bundle_count(ROUND_ID).unwrap(), 1);
    }

    #[test]
    fn test_setup_bundles_rolls_back_partial_insert_on_error() {
        let db = test_db();
        db.init_round(&test_params(), None).unwrap();

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

        let err = db
            .setup_bundles(ROUND_ID, &notes)
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
        db.init_round(&test_params(), None).unwrap();
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
        db.init_round(&test_params(), None).unwrap();
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
        use zip32::Scope;

        let db = test_db();
        db.init_round(&test_params(), None).unwrap();

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
        db.setup_bundles(ROUND_ID, &notes).unwrap();

        let mut substituted_notes = notes.clone();
        substituted_notes[0].nullifier = vec![0x03; 32];

        let sk = SpendingKey::from_bytes([0x42; 32]).expect("valid spending key");
        let fvk = FullViewingKey::from(&sk);
        let hotkey_sk = SpendingKey::from_bytes([0x43; 32]).expect("valid spending key");
        let hotkey_fvk = FullViewingKey::from(&hotkey_sk);
        let hotkey_raw_address = hotkey_fvk
            .address_at(0u32, Scope::External)
            .to_raw_address_bytes()
            .to_vec();
        let seed_fingerprint = [0x42u8; 32];

        let err = db
            .build_governance_pczt(
                ROUND_ID,
                0,
                &substituted_notes,
                &fvk.to_bytes().to_vec(),
                &hotkey_raw_address,
                0xC8E71055,
                1,
                &seed_fingerprint,
                0,
                "test-round",
                0,
            )
            .unwrap_err();

        assert!(err.to_string().contains("note identity mismatch"));
    }

    #[test]
    fn test_store_proof_result_fields_rejects_pczt_mismatch() {
        let db = test_db();
        db.init_round(&test_params(), None).unwrap();

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
        db.init_round(&test_params(), None).unwrap();

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
        db.init_round(&test_params(), None).unwrap();

        let tree_state = vec![0xCC; 1024];
        db.store_tree_state(ROUND_ID, &tree_state).unwrap();

        let conn = db.conn();
        let loaded = queries::load_tree_state(&conn, ROUND_ID, W).unwrap();
        assert_eq!(loaded, tree_state);
    }

    #[test]
    fn test_replace_bundle_witnesses_replaces_cached_bundle() {
        let db = test_db();
        db.init_round(&test_params(), None).unwrap();

        {
            let conn = db.conn();
            queries::insert_bundle(&conn, ROUND_ID, W, 0, &[0, 1]).unwrap();
        }

        let original = vec![valid_empty_tree_witness(0), valid_empty_tree_witness(1)];
        db.store_witnesses(ROUND_ID, 0, &original).unwrap();

        let ignored = vec![valid_empty_tree_witness(2)];
        // This second store is a no-op because the bundle already has cached rows;
        // replacement below is what actually overwrites the cache.
        db.store_witnesses(ROUND_ID, 0, &ignored).unwrap();

        {
            let conn = db.conn();
            let loaded = queries::load_witnesses(&conn, ROUND_ID, W, 0).unwrap();
            assert_eq!(loaded.len(), 2);
            assert_eq!(loaded[0].position, 0);
            assert_eq!(loaded[1].position, 1);
        }

        let replacement = vec![
            valid_field_tree_witness(0, 1),
            valid_field_tree_witness(1, 2),
        ];
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
    fn test_replace_bundle_witnesses_rejects_position_mismatch_without_clearing_cache() {
        let db = test_db();
        db.init_round(&test_params(), None).unwrap();

        {
            let conn = db.conn();
            queries::insert_bundle(&conn, ROUND_ID, W, 0, &[0, 1]).unwrap();
        }

        let original = vec![valid_empty_tree_witness(0), valid_empty_tree_witness(1)];
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
    fn test_encrypt_shares() {
        let db = test_db();
        db.init_round(&test_params(), None).unwrap();

        let shares = db.encrypt_shares(ROUND_ID, &[1, 4]).unwrap();
        assert_eq!(shares.len(), 2);
        assert_eq!(shares[0].plaintext_value, 1);
        assert_eq!(shares[1].plaintext_value, 4);
    }

    #[test]
    fn test_mark_vote_submitted() {
        let db = test_db();
        db.init_round(&test_params(), None).unwrap();
        db.setup_bundles(
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
        db.mark_vote_submitted(ROUND_ID, 0, 0).unwrap();
        db.mark_vote_submitted(ROUND_ID, 0, 0).unwrap();

        let err = db.mark_vote_submitted(ROUND_ID, 0, 99).unwrap_err();
        assert!(matches!(err, VotingError::InvalidInput { .. }));
    }

    #[test]
    fn test_insert_vote_fixture() {
        let db = test_db();
        db.init_round(&test_params(), None).unwrap();
        db.setup_bundles(
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
        assert!(!votes[0].submitted);
    }

    #[test]
    fn test_get_delegation_submission_uses_account_index_for_seed_signing() {
        use orchard::{
            keys::{SpendAuthorizingKey, SpendingKey},
            primitives::redpallas::{Signature, SpendAuth, VerificationKey},
        };
        use zcash_keys::keys::UnifiedSpendingKey;
        use zcash_protocol::consensus::TEST_NETWORK;
        use zip32::AccountId;

        fn randomized_verification_key(
            seed: &[u8],
            account_index: u32,
            alpha: &pallas::Scalar,
        ) -> VerificationKey<SpendAuth> {
            let account = AccountId::try_from(account_index).unwrap();
            let usk = UnifiedSpendingKey::from_seed(&TEST_NETWORK, seed, account).unwrap();
            let sk: SpendingKey = *usk.orchard();
            let ask = SpendAuthorizingKey::from(&sk);
            VerificationKey::from(&ask.randomize(alpha))
        }

        let db = test_db();
        db.init_round(&test_params(), None).unwrap();

        let sender_seed = [0x42; 64];
        let alpha = pallas::Scalar::from(7);
        let alpha_bytes = alpha.to_repr();
        let sighash = [0x99; 32];
        let account_1_rk: [u8; 32] = (&randomized_verification_key(&sender_seed, 1, &alpha)).into();

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
                &[0x55; 32],
                &[0x66; 32],
                &[0x77; 32],
                1,
                0,
                &[],
                &sighash,
            )
            .unwrap();
            queries::store_proof_result_fields_with_van_comm(
                &conn,
                ROUND_ID,
                W,
                0,
                &account_1_rk,
                &[vec![0x88; 32]],
                &[0x33; 32],
                &[0x44; 32],
                &[0x77; 32],
            )
            .unwrap();
            queries::store_proof(&conn, ROUND_ID, W, 0, &[0xAB; 96]).unwrap();
        }

        let submission = db
            .get_delegation_submission(ROUND_ID, 0, &sender_seed, 0, 1)
            .unwrap();

        assert_eq!(submission.rk, account_1_rk.to_vec());
        assert_eq!(submission.sighash, sighash.to_vec());

        let sig_bytes: [u8; 64] = submission
            .spend_auth_sig
            .as_slice()
            .try_into()
            .expect("signature length was checked by signer");
        let sig = Signature::<SpendAuth>::from(sig_bytes);

        let returned_rk_bytes: [u8; 32] = submission
            .rk
            .as_slice()
            .try_into()
            .expect("test stores a 32-byte rk");
        let returned_rk = VerificationKey::<SpendAuth>::try_from(returned_rk_bytes).unwrap();
        returned_rk.verify(&submission.sighash, &sig).unwrap();

        let account_0_rk = randomized_verification_key(&sender_seed, 0, &alpha);
        assert!(account_0_rk.verify(&submission.sighash, &sig).is_err());
    }

    #[test]
    fn test_get_delegation_submission_with_keystone_sig_requires_stored_sighash() {
        let db = test_db();
        db.init_round(&test_params(), None).unwrap();

        let stored_sighash = [0x99; 32];
        let wrong_sighash = [0x98; 32];
        let keystone_sig = [0x42; 64];
        let rk = [0xAB; 32];

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
                &[0x55; 32],
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
            .get_delegation_submission_with_keystone_sig(ROUND_ID, 0, &keystone_sig, &wrong_sighash)
            .expect_err("mismatched sighash must fail");
        assert!(matches!(err, VotingError::InvalidInput { .. }));
        assert!(err
            .to_string()
            .contains("keystone_sighash does not match stored PCZT sighash"));

        let submission = db
            .get_delegation_submission_with_keystone_sig(
                ROUND_ID,
                0,
                &keystone_sig,
                &stored_sighash,
            )
            .unwrap();
        assert_eq!(submission.spend_auth_sig, keystone_sig.to_vec());
        assert_eq!(submission.sighash, stored_sighash.to_vec());
    }

    /// Multi-bundle test: 6 notes → 2 bundles (5+1), independent delegation + vote storage per bundle.
    #[test]
    fn test_multi_bundle_delegation_and_voting() {
        use orchard::keys::{FullViewingKey, SpendingKey};
        use zip32::Scope;

        let db = test_db();
        db.init_round(&test_params(), None).unwrap();

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
        let (bundle_count, eligible) = db.setup_bundles(ROUND_ID, &notes).unwrap();
        assert_eq!(bundle_count, 2);
        // Quantized: bundle 0 (65M → 5×12.5M=62.5M) + bundle 1 (13M → 1×12.5M=12.5M) = 75M
        assert_eq!(eligible, 75_000_000);
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
        let hotkey_sk = SpendingKey::from_bytes([0x43; 32]).expect("valid spending key");
        let hotkey_fvk = FullViewingKey::from(&hotkey_sk);
        let hotkey_addr = hotkey_fvk.address_at(0u32, Scope::External);
        let hotkey_raw_address = hotkey_addr.to_raw_address_bytes().to_vec();
        let seed_fingerprint = [0x42u8; 32];

        // Build governance PCZT for each bundle independently
        let chunk_result = crate::types::chunk_notes(&notes);

        for (i, chunk) in chunk_result.bundles.iter().enumerate() {
            let result = db
                .build_governance_pczt(
                    ROUND_ID,
                    i as u32,
                    chunk,
                    &fvk_bytes,
                    &hotkey_raw_address,
                    0xC8E71055, // NU6 consensus branch ID
                    1,          // testnet coin type
                    &seed_fingerprint,
                    0, // account_index
                    "test-round",
                    0, // address_index
                )
                .unwrap();

            // Each bundle should have valid delegation data
            assert_eq!(result.rk.len(), 32);
            assert_eq!(result.van.len(), 32);
            assert_eq!(result.gov_nullifiers.len(), 5);
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

        // Mark bundle 0's vote submitted, verify bundle 1 still unsubmitted
        db.mark_vote_submitted(ROUND_ID, 0, 0).unwrap();
        let votes = db.get_votes(ROUND_ID).unwrap();
        assert!(
            votes
                .iter()
                .find(|v| v.bundle_index == 0)
                .unwrap()
                .submitted
        );
        assert!(
            !votes
                .iter()
                .find(|v| v.bundle_index == 1)
                .unwrap()
                .submitted
        );

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
        db.init_round(&test_params(), None).unwrap();
        db.setup_bundles(
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
