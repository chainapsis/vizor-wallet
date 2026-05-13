use ff::{Field, PrimeField};
use pasta_curves::arithmetic::{CurveAffine, CurveExt};
use pasta_curves::group::{Curve, Group, GroupEncoding};
use pasta_curves::pallas;
use rand::RngCore;
use subtle::CtOption;

use orchard::builder::{Builder, BundleType};
use orchard::keys::FullViewingKey;
use orchard::note::{ExtractedNoteCommitment, RandomSeed, Rho};
use orchard::pczt::Zip32Derivation;
use orchard::tree::{MerkleHashOrchard, MerklePath};
use orchard::value::NoteValue;
use orchard::{Address, Anchor};
use zcash_primitives::transaction::builder::PcztParts;
use zcash_primitives::transaction::TxVersion;
use zcash_protocol::consensus::{BlockHeight, BranchId, Network};
use zip32::Scope;

/// Orchard Merkle tree depth (32 levels).
const MERKLE_DEPTH: usize = 32;
const MAX_PCZT_LAYOUT_ATTEMPTS: usize = 32;
const ZIP32_MAINNET_COIN_TYPE: u32 = 133;

use crate::governance;
use crate::types::{
    validate_notes, validate_round_params, GovernancePczt, NoteInfo, VotingError, VotingRoundParams,
};

/// Orchard key diversification personalization for DiversifyHash^Orchard.
const ORCHARD_GD_PERSONALIZATION: &str = "z.cash:Orchard-gd";

/// Extract the affine x-coordinate bytes from a non-identity Pallas point.
fn point_x_bytes(point: &pallas::Point) -> Result<[u8; 32], VotingError> {
    point
        .to_affine()
        .coordinates()
        .map(|coords| coords.x().to_repr())
        .into_option()
        .ok_or_else(|| VotingError::InvalidInput {
            message: "point is identity; x-coordinate unavailable".to_string(),
        })
}

/// Derive (g_d_x, pk_d_x) from a 43-byte Orchard raw address.
///
/// - g_d_x: x-coordinate of DiversifyHash(d)
/// - pk_d_x: x-coordinate of the diversified transmission key pk_d
pub fn derive_hotkey_x_coords_from_raw_address(
    hotkey_raw_address: &[u8; 43],
) -> Result<([u8; 32], [u8; 32]), VotingError> {
    let diversifier: [u8; 11] = hotkey_raw_address[..11]
        .try_into()
        .expect("slice length is fixed to 11");
    let pk_d_bytes: [u8; 32] = hotkey_raw_address[11..]
        .try_into()
        .expect("slice length is fixed to 32");

    let pk_d_point: pallas::Point = pallas::Point::from_bytes(&pk_d_bytes)
        .into_option()
        .ok_or_else(|| VotingError::InvalidInput {
            message: "hotkey_raw_address contains invalid pk_d point encoding".to_string(),
        })?;
    let pk_d_x: [u8; 32] = point_x_bytes(&pk_d_point)?;

    // Orchard spec: if DiversifyHash(d) returns identity, use DiversifyHash([]) fallback.
    let hasher = pallas::Point::hash_to_curve(ORCHARD_GD_PERSONALIZATION);
    let mut g_d_point = hasher(&diversifier);
    if bool::from(g_d_point.is_identity()) {
        g_d_point = hasher(&[]);
    }
    let g_d_x: [u8; 32] = point_x_bytes(&g_d_point)?;

    Ok((g_d_x, pk_d_x))
}

/// Generate a random valid Rho (retries until the random bytes are a valid Pallas field element).
fn random_rho(rng: &mut impl RngCore) -> Rho {
    loop {
        let mut rho_bytes = [0u8; 32];
        rng.fill_bytes(&mut rho_bytes);
        let r: CtOption<Rho> = Rho::from_bytes(&rho_bytes);
        if r.is_some().into() {
            return r.expect("is_some checked above");
        }
    }
}

/// Generate a random valid RandomSeed for a given Rho.
fn random_rseed(rng: &mut impl RngCore, rho: &Rho) -> (RandomSeed, [u8; 32]) {
    loop {
        let mut rseed_bytes = [0u8; 32];
        rng.fill_bytes(&mut rseed_bytes);
        let rs: CtOption<RandomSeed> = RandomSeed::from_bytes(rseed_bytes, rho);
        if rs.is_some().into() {
            return (rs.expect("is_some checked above"), rseed_bytes);
        }
    }
}

/// Construct an Orchard note at the given address with the given value and Rho.
fn make_note(
    addr: Address,
    value: NoteValue,
    rho: Rho,
    rng: &mut impl RngCore,
) -> Result<(orchard::Note, [u8; 32]), VotingError> {
    let (rseed, rseed_bytes) = random_rseed(rng, &rho);
    let note = orchard::Note::from_parts(addr, value, rho, rseed);
    if !bool::from(note.is_some()) {
        return Err(VotingError::Internal {
            message: "failed to construct note".to_string(),
        });
    }
    Ok((note.expect("is_some checked above"), rseed_bytes))
}

/// Construct a 1-zatoshi Orchard note.
///
/// The signed note uses value 1 so Keystone renders a non-zero Orchard action.
fn make_dummy_note(
    addr: Address,
    rho: Rho,
    rng: &mut impl RngCore,
) -> Result<(orchard::Note, [u8; 32]), VotingError> {
    make_note(addr, NoteValue::from_raw(1), rho, rng)
}

/// Canonical delegate action payload encoding for external signing.
///
/// Field order:
/// nf_signed || rk || cmx_new || van_comm || gov_null_1 || gov_null_2 ||
/// gov_null_3 || gov_null_4 || gov_null_5 || vote_round_id.
///
/// TODO: This format might change when we standardize what the cosmos chain expects.
fn encode_delegation_action_bytes(
    nf_signed: &[u8; 32],
    rk: &[u8; 32],
    cmx_new: &[u8; 32],
    van_comm: &[u8],
    gov_nullifiers: &[Vec<u8>],
    vote_round_id: &[u8; 32],
) -> Result<Vec<u8>, VotingError> {
    crate::types::validate_32_bytes(van_comm, "van_comm")?;
    if gov_nullifiers.len() != 5 {
        return Err(VotingError::InvalidInput {
            message: format!(
                "gov_nullifiers must have exactly 5 entries, got {}",
                gov_nullifiers.len()
            ),
        });
    }

    let mut out = Vec::with_capacity(32 * 10);
    out.extend_from_slice(nf_signed);
    out.extend_from_slice(rk);
    out.extend_from_slice(cmx_new);
    out.extend_from_slice(van_comm);
    for (i, gn) in gov_nullifiers.iter().enumerate() {
        crate::types::validate_32_bytes(gn, &format!("gov_nullifiers[{}]", i))?;
        out.extend_from_slice(gn);
    }
    out.extend_from_slice(vote_round_id);
    Ok(out)
}

/// Build a governance-specific PCZT for Keystone signing.
///
/// Constructs a PCZT whose single real Orchard action is the governance dummy action
/// (spend of signed note with constrained rho → output to hotkey). The Builder
/// generates alpha/rk internally, and the PCZT's ZIP-244 sighash is computed by
/// Keystone when it runs the Signer role.
///
/// Parameters:
/// - `notes`: 1-5 input notes for governance nullifier derivation
/// - `params`: voting round parameters (round ID, snapshot height, etc.)
/// - `fvk_bytes`: 96-byte orchard FullViewingKey (ak[32] || nk[32] || rivk[32])
/// - `hotkey_raw_address`: 43-byte hotkey raw orchard address
/// - `consensus_branch_id`: network consensus branch ID (e.g. 0xC2D6D0B4 for NU5)
/// - `coin_type`: BIP-44 coin type (133 for mainnet, 1 for testnet)
/// - `seed_fingerprint`: 32-byte ZIP-32 seed fingerprint (Keystone needs this to
///   identify which seed to derive the spending key from)
/// - `account_index`: ZIP-32 account index (typically 0)
pub fn build_governance_pczt(
    notes: &[NoteInfo],
    params: &VotingRoundParams,
    fvk_bytes: &[u8],
    hotkey_raw_address: &[u8],
    consensus_branch_id: u32,
    coin_type: u32,
    seed_fingerprint: &[u8; 32],
    account_index: u32,
    round_name: &str,
) -> Result<GovernancePczt, VotingError> {
    validate_notes(notes)?;
    validate_round_params(params)?;

    // Parse FVK from 96 bytes: ak[32] || nk[32] || rivk[32]
    let fvk_96: [u8; 96] = fvk_bytes
        .try_into()
        .map_err(|_| VotingError::InvalidInput {
            message: format!("fvk_bytes must be 96 bytes, got {}", fvk_bytes.len()),
        })?;
    let fvk = FullViewingKey::from_bytes(&fvk_96).ok_or_else(|| VotingError::InvalidInput {
        message: "fvk_bytes is not a valid orchard FullViewingKey".to_string(),
    })?;
    let nk_bytes = &fvk_bytes[32..64];

    // Parse hotkey raw address (43 bytes: 11-byte diversifier + 32-byte pk_d)
    let addr_43: [u8; 43] =
        hotkey_raw_address
            .try_into()
            .map_err(|_| VotingError::InvalidInput {
                message: format!(
                    "hotkey_raw_address must be 43 bytes, got {}",
                    hotkey_raw_address.len()
                ),
            })?;
    let hotkey_addr: Address = Address::from_raw_address_bytes(&addr_43)
        .into_option()
        .ok_or_else(|| VotingError::InvalidInput {
            message: "hotkey_raw_address is not a valid orchard address".to_string(),
        })?;

    // Derive hotkey x-coordinates for VAN
    let (derived_g_d_new_x, derived_pk_d_new_x) =
        derive_hotkey_x_coords_from_raw_address(&addr_43)?;

    // Convert vote_round_id from hex string to 32 bytes
    let vote_round_id_bytes =
        hex::decode(&params.vote_round_id).map_err(|e| VotingError::InvalidInput {
            message: format!("vote_round_id is not valid hex: {}", e),
        })?;
    crate::types::validate_32_bytes(&vote_round_id_bytes, "vote_round_id (decoded hex)")?;
    let vri_32: [u8; 32] = vote_round_id_bytes
        .try_into()
        .expect("validated as 32 bytes above");

    let mut rng = rand::thread_rng();

    // --- Compute governance nullifiers ---
    let dom = governance::compute_nullifier_domain(&vri_32)?;
    let mut gov_nullifiers: Vec<Vec<u8>> = Vec::with_capacity(5);
    for note in notes {
        let gov_null = governance::derive_gov_nullifier(nk_bytes, &dom, &note.nullifier)?;
        gov_nullifiers.push(gov_null);
    }

    // Padded note generation (also collect rho+rseed for ZCA-74 randomness threading).
    // These must match the delegation circuit builder exactly: unused note slots
    // are zero-value notes at address index 1000+i.
    let mut padded_cmx: Vec<Vec<u8>> = Vec::new();
    let mut dummy_nullifiers: Vec<Vec<u8>> = Vec::new();
    let mut padded_note_secrets: Vec<(Vec<u8>, Vec<u8>)> = Vec::new();
    let n_real = notes.len();
    if n_real < 5 {
        for i in n_real..5 {
            let pad_addr = fvk.address_at(1000u32 + i as u32, Scope::External);
            let rho = random_rho(&mut rng);
            let (pad_note, rseed_bytes) = make_note(pad_addr, NoteValue::ZERO, rho, &mut rng)?;
            let cmx: ExtractedNoteCommitment = pad_note.commitment().into();
            let real_nf = pad_note.nullifier(&fvk);
            let gov_null = governance::derive_gov_nullifier(nk_bytes, &dom, &real_nf.to_bytes())?;
            padded_cmx.push(cmx.to_bytes().to_vec());
            gov_nullifiers.push(gov_null);
            dummy_nullifiers.push(real_nf.to_bytes().to_vec());
            // Store rho + rseed for this padded note so Phase 2 can reconstruct it
            let rho_bytes: [u8; 32] = rho.to_bytes();
            padded_note_secrets.push((rho_bytes.to_vec(), rseed_bytes.to_vec()));
        }
    }

    // Per-bundle weight
    let total_weight: u64 = notes
        .iter()
        .try_fold(0u64, |acc, n| acc.checked_add(n.value))
        .ok_or_else(|| VotingError::InvalidInput {
            message: "total note weight overflows u64".to_string(),
        })?;

    // Sample van_comm_rand
    let van_comm_rand_fp = pallas::Base::random(&mut rng);
    let van_comm_rand: [u8; 32] = van_comm_rand_fp.to_repr();

    // Compute VAN
    let van = governance::construct_van(
        &derived_g_d_new_x,
        &derived_pk_d_new_x,
        total_weight,
        &vri_32,
        &van_comm_rand,
    )?;

    // Collect all 5 cmx values
    let mut all_cmx: Vec<Vec<u8>> = Vec::with_capacity(5);
    for note in notes {
        all_cmx.push(note.commitment.clone());
    }
    all_cmx.extend(padded_cmx.iter().cloned());
    if all_cmx.len() != 5 {
        return Err(VotingError::Internal {
            message: format!("expected 5 cmx values, got {}", all_cmx.len()),
        });
    }

    // Compute constrained rho
    let rho_signed = governance::compute_rho_binding(
        &all_cmx[0],
        &all_cmx[1],
        &all_cmx[2],
        &all_cmx[3],
        &all_cmx[4],
        &van,
        &vri_32,
    )?;

    // --- Build signed note (§1.3.4.2) ---
    let rho_signed_32: [u8; 32] = rho_signed
        .clone()
        .try_into()
        .expect("rho_signed is 32 bytes from compute_rho_binding");
    let rho_for_note: Rho = Rho::from_bytes(&rho_signed_32)
        .into_option()
        .ok_or_else(|| VotingError::Internal {
            message: "rho_signed is not a valid Pallas field element for Rho".to_string(),
        })?;
    let sender_address = fvk.address_at(0u32, Scope::External);
    let (signed_note, rseed_signed_bytes) =
        make_dummy_note(sender_address, rho_for_note, &mut rng)?;

    // --- Build PCZT using orchard Builder ---
    // Dummy MerklePath: all-zero siblings, position 0.
    // Compute the anchor from the note commitment so the Builder's anchor check passes.
    let dummy_auth_path: [MerkleHashOrchard; MERKLE_DEPTH] = {
        let zero_hash = MerkleHashOrchard::from_bytes(&[0u8; 32])
            .into_option()
            .ok_or_else(|| VotingError::Internal {
                message: "zero bytes is not a valid MerkleHashOrchard".to_string(),
            })?;
        [zero_hash; MERKLE_DEPTH]
    };
    let dummy_merkle_path = MerklePath::from_parts(0u32, dummy_auth_path);
    let anchor = {
        let cm = signed_note.commitment();
        let root = dummy_merkle_path.root(cm.into());
        Anchor::from(root)
    };

    // Add output to hotkey address. The circuit commits to a zero-value output
    // note for cmx_new, so Phase 1 must use the same value and rseed.
    let ovk = fvk.to_ovk(Scope::External);
    let memo = {
        let zec_whole = total_weight / 100_000_000;
        let zec_frac = total_weight % 100_000_000;
        let memo_str = format!(
            "I am authorizing this hotkey managed by my wallet to vote on {} with {}.{:08} ZEC.",
            round_name, zec_whole, zec_frac
        );
        let mut buf = [0u8; 512];
        let bytes = memo_str.as_bytes();
        let len = bytes.len().min(512);
        buf[..len].copy_from_slice(&bytes[..len]);
        buf
    };
    // --- Serialize to full PCZT ---
    // Use Creator::build_from_parts to construct the PCZT with the orchard bundle,
    // matching the same path the wallet transaction builder uses.
    let branch_id =
        BranchId::try_from(consensus_branch_id).map_err(|e| VotingError::InvalidInput {
            message: format!(
                "invalid consensus_branch_id 0x{:08X}: {}",
                consensus_branch_id, e
            ),
        })?;
    let network = match coin_type {
        ZIP32_MAINNET_COIN_TYPE => Network::MainNetwork,
        _ => Network::TestNetwork,
    };

    for _ in 0..MAX_PCZT_LAYOUT_ATTEMPTS {
        let mut builder = Builder::new(BundleType::DEFAULT, anchor);

        // Add the governance signed note as a spend.
        builder
            .add_spend(fvk.clone(), signed_note.clone(), dummy_merkle_path.clone())
            .map_err(|e| VotingError::Internal {
                message: format!("Builder::add_spend failed: {:?}", e),
            })?;

        builder
            .add_output(
                Some(ovk.clone()),
                hotkey_addr.clone(),
                NoteValue::ZERO,
                memo,
            )
            .map_err(|e| VotingError::Internal {
                message: format!("Builder::add_output failed: {:?}", e),
            })?;

        // Build the PCZT bundle. The Orchard builder pads and shuffles spends
        // and outputs independently, so retry until the governance spend and
        // governance output are paired in the same action slot.
        let (mut orchard_pczt_bundle, bundle_meta) =
            builder
                .build_for_pczt(&mut rng)
                .map_err(|e| VotingError::Internal {
                    message: format!("Builder::build_for_pczt failed: {:?}", e),
                })?;

        // Extract data from the real governance action (may be shuffled by Builder)
        let spend_idx = bundle_meta
            .spend_action_index(0)
            .ok_or_else(|| VotingError::Internal {
                message: "BundleMetadata missing spend action index".to_string(),
            })?;
        let output_idx =
            bundle_meta
                .output_action_index(0)
                .ok_or_else(|| VotingError::Internal {
                    message: "BundleMetadata missing output action index".to_string(),
                })?;

        if spend_idx != output_idx {
            continue;
        }

        let action_index = spend_idx;
        let governance_action = &orchard_pczt_bundle.actions()[action_index];
        let nf_signed_bytes: [u8; 32] = governance_action.spend().nullifier().to_bytes();
        let rk_bytes: [u8; 32] = governance_action.spend().rk().into();
        let alpha = governance_action
            .spend()
            .alpha()
            .ok_or_else(|| VotingError::Internal {
                message: "PCZT spend missing alpha".to_string(),
            })?;
        let alpha_bytes: [u8; 32] = alpha.to_repr();
        let rseed_signed_from_pczt =
            governance_action
                .spend()
                .rseed()
                .ok_or_else(|| VotingError::Internal {
                    message: "PCZT spend missing rseed".to_string(),
                })?;
        // Verify rseed consistency between our note and the PCZT
        if rseed_signed_from_pczt.as_bytes() != &rseed_signed_bytes {
            return Err(VotingError::Internal {
                message: "rseed mismatch between note and PCZT".to_string(),
            });
        }

        let cmx_new_bytes: [u8; 32] = governance_action.output().cmx().to_bytes();
        let rseed_output =
            governance_action
                .output()
                .rseed()
                .ok_or_else(|| VotingError::Internal {
                    message: "PCZT output missing rseed".to_string(),
                })?;
        let rseed_output_bytes: [u8; 32] = *rseed_output.as_bytes();

        // --- Updater role: set zip32_derivation so Keystone can derive the spending key ---
        // Orchard ZIP-32 derivation path: m / 32' / coin_type' / account'
        let zip32_deriv = Zip32Derivation::parse(
            *seed_fingerprint,
            vec![
                32 | (1 << 31),            // purpose: hardened(32)
                coin_type | (1 << 31),     // coin_type
                account_index | (1 << 31), // account
            ],
        )
        .map_err(|e| VotingError::Internal {
            message: format!("Zip32Derivation::parse failed: {:?}", e),
        })?;
        orchard_pczt_bundle
            .update_with(|mut updater| {
                updater.update_action_with(action_index, |mut action_updater| {
                    action_updater.set_spend_zip32_derivation(zip32_deriv);
                    Ok(())
                })
            })
            .map_err(|e| VotingError::Internal {
                message: format!("PCZT updater failed: {:?}", e),
            })?;

        let parts = PcztParts {
            params: network,
            version: TxVersion::suggested_for_branch(branch_id),
            consensus_branch_id: branch_id,
            // Keystone's determine_lock_time returns global.lock_time() for pure-Orchard PCZTs
            // (no transparent inputs). Without a lock_time, it returns None → error.
            lock_time: 0,
            expiry_height: BlockHeight::from_u32(0), // no expiry (never broadcast)
            transparent: None,
            sapling: None,
            orchard: Some(orchard_pczt_bundle),
        };
        let pczt = pczt::roles::creator::Creator::build_from_parts(parts).ok_or_else(|| {
            VotingError::Internal {
                message: "Creator::build_from_parts returned None (incompatible tx version)"
                    .to_string(),
            }
        })?;

        // Run IO Finalizer so the Signer (Keystone) can compute the sighash.
        let pczt = pczt::roles::io_finalizer::IoFinalizer::new(pczt)
            .finalize_io()
            .map_err(|e| VotingError::Internal {
                message: format!("IoFinalizer::finalize_io failed: {:?}", e),
            })?;

        let pczt_bytes = pczt.serialize();
        let parsed_pczt = pczt::Pczt::parse(&pczt_bytes).map_err(|e| VotingError::Internal {
            message: format!("Failed to parse returned PCZT: {:?}", e),
        })?;
        let indexed_action = parsed_pczt
            .orchard()
            .actions()
            .get(action_index)
            .ok_or_else(|| VotingError::Internal {
                message: format!(
                    "GovernancePczt action_index {} is out of bounds for {} Orchard actions",
                    action_index,
                    parsed_pczt.orchard().actions().len()
                ),
            })?;
        if *indexed_action.spend().nullifier() != nf_signed_bytes
            || *indexed_action.output().cmx() != cmx_new_bytes
        {
            return Err(VotingError::Internal {
                message: "GovernancePczt action_index does not point to paired governance action"
                    .to_string(),
            });
        }

        // --- Extract ZIP-244 sighash ---
        // This is the sighash that Keystone signs; the non-Keystone path also uses it.
        let pczt_sighash = extract_pczt_sighash(&pczt_bytes)?;

        // --- Encode canonical action bytes for cosmos chain ---
        let action_bytes = encode_delegation_action_bytes(
            &nf_signed_bytes,
            &rk_bytes,
            &cmx_new_bytes,
            &van,
            &gov_nullifiers,
            &vri_32,
        )?;

        return Ok(GovernancePczt {
            pczt_bytes,
            rk: rk_bytes.to_vec(),
            alpha: alpha_bytes.to_vec(),
            nf_signed: nf_signed_bytes.to_vec(),
            cmx_new: cmx_new_bytes.to_vec(),
            gov_nullifiers,
            van,
            van_comm_rand: van_comm_rand.to_vec(),
            dummy_nullifiers,
            rho_signed,
            padded_cmx,
            rseed_signed: rseed_signed_bytes.to_vec(),
            rseed_output: rseed_output_bytes.to_vec(),
            action_bytes,
            action_index,
            padded_note_secrets,
            pczt_sighash: pczt_sighash.to_vec(),
        });
    }

    Err(VotingError::Internal {
        message: format!(
            "failed to build paired governance PCZT layout after {} attempts",
            MAX_PCZT_LAYOUT_ATTEMPTS
        ),
    })
}

/// Extract the ZIP-244 shielded sighash from finalized PCZT bytes.
///
/// Creates a Signer from the PCZT to compute the v5 signature hash, then
/// returns it. This is the sighash that Keystone signs internally.
pub fn extract_pczt_sighash(pczt_bytes: &[u8]) -> Result<[u8; 32], VotingError> {
    let pczt = pczt::Pczt::parse(pczt_bytes).map_err(|e| VotingError::Internal {
        message: format!("Failed to parse PCZT: {:?}", e),
    })?;
    let signer = pczt::roles::signer::Signer::new(pczt).map_err(|e| VotingError::Internal {
        message: format!("Failed to create Signer from PCZT: {:?}", e),
    })?;
    Ok(signer.shielded_sighash())
}

/// Extract the spend_auth_sig from a signed PCZT.
///
/// Keystone redacts sensitive fields (alpha, rseed, zip32_derivation, etc.) after signing,
/// so a byte-diff between unsigned and signed PCZTs doesn't work. This function parses
/// the signed PCZT structurally and reads the `spend_auth_sig` field directly.
///
/// Tries `action_index` first, then falls back to scanning all actions. The Builder
/// shuffles action order, so the governance spend may not end up at the expected index
/// from Keystone's perspective. Our governance PCZT has exactly 2 actions (1 real +
/// 1 dummy padding); only the real one gets signed (the dummy lacks zip32_derivation).
///
/// Returns the 64-byte SpendAuthSig, or an error if no signed action is found.
pub fn extract_spend_auth_sig(
    signed_pczt_bytes: &[u8],
    action_index: usize,
) -> Result<[u8; 64], VotingError> {
    let pczt = pczt::Pczt::parse(signed_pczt_bytes).map_err(|e| VotingError::Internal {
        message: format!("Failed to parse signed PCZT: {:?}", e),
    })?;

    let actions = pczt.orchard().actions();

    // Try the expected action index first.
    if action_index < actions.len() {
        if let Some(sig) = actions[action_index].spend().spend_auth_sig() {
            return Ok(*sig);
        }
    }

    // Fallback: scan all actions for a signature.
    // The governance PCZT has 2 actions; only the real governance spend gets signed
    // by Keystone (the padding action has no zip32_derivation so Keystone skips it).
    // This is safe because there is exactly one signable action.
    for action in actions {
        if let Some(sig) = action.spend().spend_auth_sig() {
            return Ok(*sig);
        }
    }

    Err(VotingError::Internal {
        message: format!(
            "No spend_auth_sig found in any of the {} actions in the signed PCZT",
            actions.len()
        ),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use orchard::keys::SpendingKey;

    fn mock_note() -> NoteInfo {
        NoteInfo {
            commitment: vec![0x01; 32],
            nullifier: vec![0x02; 32],
            value: 15_000_000,
            position: 42,
            diversifier: vec![0; 11],
            rho: vec![0; 32],
            rseed: vec![0; 32],
            scope: 0,
            ufvk_str: String::new(),
        }
    }

    fn mock_params() -> VotingRoundParams {
        VotingRoundParams {
            // Hex string representing 32 bytes
            vote_round_id: "0101010101010101010101010101010101010101010101010101010101010101"
                .to_string(),
            snapshot_height: 100_000,
            ea_pk: vec![0xEA; 32],
            nc_root: vec![0x01; 32],
            nullifier_imt_root: vec![0x02; 32],
        }
    }

    /// Derive a valid 96-byte FVK from a deterministic SpendingKey.
    fn mock_fvk_bytes() -> Vec<u8> {
        let sk = SpendingKey::from_bytes([0x42; 32]).expect("valid spending key");
        let fvk = FullViewingKey::from(&sk);
        fvk.to_bytes().to_vec()
    }

    /// Derive a valid 43-byte raw orchard address from a mock FVK.
    fn mock_hotkey_address() -> Vec<u8> {
        // Use a different key so the hotkey address differs from the sender
        let sk = SpendingKey::from_bytes([0x43; 32]).expect("valid spending key");
        let fvk = FullViewingKey::from(&sk);
        let addr = fvk.address_at(0u32, Scope::External);
        addr.to_raw_address_bytes().to_vec()
    }

    #[test]
    fn test_action_bytes_canonical_encoding_order() {
        let nf_signed = [0x01; 32];
        let rk = [0x02; 32];
        let cmx_new = [0x03; 32];
        let van_comm = vec![0x04; 32];
        let gov_nullifiers = vec![
            vec![0x05; 32],
            vec![0x06; 32],
            vec![0x07; 32],
            vec![0x08; 32],
            vec![0x0A; 32],
        ];
        let vote_round_id = [0x09; 32];

        let encoded = encode_delegation_action_bytes(
            &nf_signed,
            &rk,
            &cmx_new,
            &van_comm,
            &gov_nullifiers,
            &vote_round_id,
        )
        .unwrap();

        assert_eq!(encoded.len(), 32 * 10);
        assert_eq!(&encoded[0..32], &nf_signed);
        assert_eq!(&encoded[32..64], &rk);
        assert_eq!(&encoded[64..96], &cmx_new);
        assert_eq!(&encoded[96..128], &van_comm);
        assert_eq!(&encoded[128..160], &gov_nullifiers[0]);
        assert_eq!(&encoded[160..192], &gov_nullifiers[1]);
        assert_eq!(&encoded[192..224], &gov_nullifiers[2]);
        assert_eq!(&encoded[224..256], &gov_nullifiers[3]);
        assert_eq!(&encoded[256..288], &gov_nullifiers[4]);
        assert_eq!(&encoded[288..320], &vote_round_id);
    }

    #[test]
    fn test_action_bytes_rejects_non_canonical_gov_nullifier_count() {
        let encoded = encode_delegation_action_bytes(
            &[0x01; 32],
            &[0x02; 32],
            &[0x03; 32],
            &[0x04; 32],
            &vec![vec![0x05; 32]; 4],
            &[0x06; 32],
        );
        assert!(encoded.is_err());
    }

    // --- build_governance_pczt tests ---

    /// NU5 mainnet consensus branch ID
    const NU5_BRANCH_ID: u32 = 0xC2D6D0B4;
    /// Mock seed fingerprint (32 bytes)
    const MOCK_SEED_FP: [u8; 32] = [0xAA; 32];
    /// Mock account index
    const MOCK_ACCOUNT: u32 = 0;

    #[test]
    fn test_build_governance_pczt_one_note() {
        let result = build_governance_pczt(
            &[mock_note()],
            &mock_params(),
            &mock_fvk_bytes(),
            &mock_hotkey_address(),
            NU5_BRANCH_ID,
            ZIP32_MAINNET_COIN_TYPE,
            &MOCK_SEED_FP,
            MOCK_ACCOUNT,
            "Test Round",
        )
        .unwrap();

        // PCZT bytes are non-empty and parseable
        assert!(!result.pczt_bytes.is_empty());
        let parsed = pczt::Pczt::parse(&result.pczt_bytes);
        assert!(
            parsed.is_ok(),
            "PCZT bytes should parse: {:?}",
            parsed.err()
        );

        // rk is 32 bytes, non-zero
        assert_eq!(result.rk.len(), 32);
        assert_ne!(result.rk, vec![0u8; 32]);

        // alpha is 32 bytes, non-zero
        assert_eq!(result.alpha.len(), 32);
        assert_ne!(result.alpha, vec![0u8; 32]);

        // nf_signed is 32 bytes, non-zero
        assert_eq!(result.nf_signed.len(), 32);
        assert_ne!(result.nf_signed, vec![0u8; 32]);

        // cmx_new is 32 bytes, non-zero
        assert_eq!(result.cmx_new.len(), 32);
        assert_ne!(result.cmx_new, vec![0u8; 32]);

        // Gov nullifiers padded to 5
        assert_eq!(result.gov_nullifiers.len(), 5);
        for gn in &result.gov_nullifiers {
            assert_eq!(gn.len(), 32);
        }

        // VAN is 32 bytes
        assert_eq!(result.van.len(), 32);

        // van_comm_rand is 32 bytes
        assert_eq!(result.van_comm_rand.len(), 32);

        // rho_signed is 32 bytes
        assert_eq!(result.rho_signed.len(), 32);
        assert_ne!(result.rho_signed, vec![0u8; 32]);

        // 4 padded cmx (1 real + 4 padded = 5)
        assert_eq!(result.padded_cmx.len(), 4);

        // rseed values are 32 bytes each
        assert_eq!(result.rseed_signed.len(), 32);
        assert_ne!(result.rseed_signed, vec![0u8; 32]);
        assert_eq!(result.rseed_output.len(), 32);
        assert_ne!(result.rseed_output, vec![0u8; 32]);

        // action_bytes is 10 * 32 = 320 bytes
        assert_eq!(result.action_bytes.len(), 320);

        // action_index is 0 or 1 (2 actions total: 1 real + 1 dummy padding)
        assert!(result.action_index <= 1);

        // The parsed PCZT should have 2 orchard actions (1 real + 1 padding)
        let pczt = parsed.unwrap();
        assert_eq!(pczt.orchard().actions().len(), 2);
        let output_value = pczt
            .orchard()
            .actions()
            .iter()
            .find_map(|action| action.output().value().as_ref().copied())
            .expect("PCZT should expose the output value");
        assert_eq!(output_value, NoteValue::ZERO.inner());
    }

    #[test]
    fn test_build_governance_pczt_action_index_points_to_paired_governance_action() {
        for _ in 0..64 {
            let result = build_governance_pczt(
                &[mock_note()],
                &mock_params(),
                &mock_fvk_bytes(),
                &mock_hotkey_address(),
                NU5_BRANCH_ID,
                ZIP32_MAINNET_COIN_TYPE,
                &MOCK_SEED_FP,
                MOCK_ACCOUNT,
                "Test Round",
            )
            .unwrap();

            let pczt = pczt::Pczt::parse(&result.pczt_bytes).unwrap();
            let indexed_action = pczt
                .orchard()
                .actions()
                .get(result.action_index)
                .expect("action_index should point to an Orchard action");

            assert_eq!(
                indexed_action.spend().nullifier().to_vec(),
                result.nf_signed
            );
            assert_eq!(indexed_action.output().cmx().to_vec(), result.cmx_new);
        }
    }

    #[test]
    fn test_build_governance_pczt_padded_slots_match_circuit_zero_value_notes() {
        let note = mock_note();
        let params = mock_params();
        let fvk_bytes = mock_fvk_bytes();
        let result = build_governance_pczt(
            &[note.clone()],
            &params,
            &fvk_bytes,
            &mock_hotkey_address(),
            NU5_BRANCH_ID,
            ZIP32_MAINNET_COIN_TYPE,
            &MOCK_SEED_FP,
            MOCK_ACCOUNT,
            "Test Round",
        )
        .unwrap();

        let fvk_96: [u8; 96] = fvk_bytes.clone().try_into().unwrap();
        let fvk = FullViewingKey::from_bytes(&fvk_96).unwrap();
        let nk_bytes = &fvk_bytes[32..64];
        let vote_round_id_bytes = hex::decode(&params.vote_round_id).unwrap();
        let vri_32: [u8; 32] = vote_round_id_bytes.try_into().unwrap();
        let dom = crate::governance::compute_nullifier_domain(&vri_32).unwrap();

        assert_eq!(result.padded_cmx.len(), 4);
        assert_eq!(result.dummy_nullifiers.len(), 4);
        assert_eq!(result.padded_note_secrets.len(), 4);

        for (i_pad, (rho_bytes, rseed_bytes)) in result.padded_note_secrets.iter().enumerate() {
            let i_slot = 1 + i_pad;
            let pad_addr = fvk.address_at((1000 + i_slot) as u32, Scope::External);
            let rho_arr: [u8; 32] = rho_bytes.as_slice().try_into().unwrap();
            let rseed_arr: [u8; 32] = rseed_bytes.as_slice().try_into().unwrap();
            let rho = Rho::from_bytes(&rho_arr).unwrap();
            let rseed = RandomSeed::from_bytes(rseed_arr, &rho).unwrap();
            let pad_note =
                orchard::Note::from_parts(pad_addr, NoteValue::ZERO, rho, rseed).unwrap();
            let cmx: ExtractedNoteCommitment = pad_note.commitment().into();
            let nf = pad_note.nullifier(&fvk);
            let gov_null =
                crate::governance::derive_gov_nullifier(nk_bytes, &dom, &nf.to_bytes()).unwrap();

            assert_eq!(result.padded_cmx[i_pad], cmx.to_bytes().to_vec());
            assert_eq!(result.dummy_nullifiers[i_pad], nf.to_bytes().to_vec());
            assert_eq!(result.gov_nullifiers[i_slot], gov_null);
        }

        let mut all_cmx = vec![note.commitment];
        all_cmx.extend(result.padded_cmx.iter().cloned());
        let expected_rho_signed = crate::governance::compute_rho_binding(
            &all_cmx[0],
            &all_cmx[1],
            &all_cmx[2],
            &all_cmx[3],
            &all_cmx[4],
            &result.van,
            &vri_32,
        )
        .unwrap();
        assert_eq!(result.rho_signed, expected_rho_signed);
    }

    #[test]
    fn test_build_governance_pczt_five_notes() {
        let notes: Vec<NoteInfo> = (0..5)
            .map(|i| NoteInfo {
                commitment: vec![i as u8 + 1; 32],
                nullifier: vec![i as u8 + 0x10; 32],
                value: 13_000_000,
                position: i as u64,
                diversifier: vec![0; 11],
                rho: vec![0; 32],
                rseed: vec![0; 32],
                scope: 0,
                ufvk_str: String::new(),
            })
            .collect();

        let result = build_governance_pczt(
            &notes,
            &mock_params(),
            &mock_fvk_bytes(),
            &mock_hotkey_address(),
            NU5_BRANCH_ID,
            ZIP32_MAINNET_COIN_TYPE,
            &MOCK_SEED_FP,
            MOCK_ACCOUNT,
            "Test Round",
        )
        .unwrap();

        assert_eq!(result.gov_nullifiers.len(), 5);
        assert!(result.padded_cmx.is_empty());
        assert!(result.dummy_nullifiers.is_empty());

        // Gov nullifiers should all differ
        for i in 0..5 {
            for j in (i + 1)..5 {
                assert_ne!(result.gov_nullifiers[i], result.gov_nullifiers[j]);
            }
        }
    }

    #[test]
    fn test_build_governance_pczt_different_rk_each_call() {
        let result1 = build_governance_pczt(
            &[mock_note()],
            &mock_params(),
            &mock_fvk_bytes(),
            &mock_hotkey_address(),
            NU5_BRANCH_ID,
            ZIP32_MAINNET_COIN_TYPE,
            &MOCK_SEED_FP,
            MOCK_ACCOUNT,
            "Test Round",
        )
        .unwrap();

        let result2 = build_governance_pczt(
            &[mock_note()],
            &mock_params(),
            &mock_fvk_bytes(),
            &mock_hotkey_address(),
            NU5_BRANCH_ID,
            ZIP32_MAINNET_COIN_TYPE,
            &MOCK_SEED_FP,
            MOCK_ACCOUNT,
            "Test Round",
        )
        .unwrap();

        // rk and alpha should differ due to randomization
        assert_ne!(result1.rk, result2.rk);
        assert_ne!(result1.alpha, result2.alpha);

        // nf_signed should be deterministic (same rho_signed from same notes/params)
        // but rho_signed differs because VAN includes random van_comm_rand
        // So nf_signed will differ between calls
    }
}
