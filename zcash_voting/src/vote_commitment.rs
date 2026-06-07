use crate::types::{
    validate_encrypted_shares, validate_proposal_id, validate_vote_decision, CastVoteSignature,
    Network, SharePayload, VoteCommitmentBundle, VotingError, WireEncryptedShare,
};

/// Build payloads for helper server (one per share).
///
/// Each payload contains the encrypted share data plus metadata the helper
/// needs to construct `MsgRevealShare`: the shares_hash (from the vote
/// commitment), proposal_id, vote_decision, and the VC tree position.
///
/// - `enc_shares`: Encrypted shares from `VoteCommitmentBundle.enc_shares`.
/// - `commitment`: The vote commitment bundle (provides shares_hash + proposal_id).
/// - `vote_decision`: The voter's choice (0-indexed into the proposal's options).
/// - `num_options`: Number of options declared for this proposal (2-8).
/// - `vc_tree_position`: Position of the Vote Commitment leaf in the VC tree,
///   known after the cast-vote TX is confirmed on chain.
pub fn build_share_payloads(
    enc_shares: &[WireEncryptedShare],
    commitment: &VoteCommitmentBundle,
    vote_decision: u32,
    num_options: u32,
    vc_tree_position: u64,
    single_share: bool,
) -> Result<Vec<SharePayload>, VotingError> {
    validate_encrypted_shares(enc_shares)?;
    validate_proposal_id(commitment.proposal_id)?;
    validate_vote_decision(vote_decision, num_options)?;

    let all_enc_shares: Vec<WireEncryptedShare> = enc_shares.to_vec();

    // In single-share mode (last-moment votes), only build a payload for share 0
    // which carries all the voting weight. The remaining 15 zero-value shares are
    // never sent to the helper, saving 15 ZKP #3 proofs and 15 on-chain transactions.
    let iter_shares: &[WireEncryptedShare] = if single_share {
        &enc_shares[..1.min(enc_shares.len())]
    } else {
        enc_shares
    };

    let mut payloads = Vec::with_capacity(iter_shares.len());
    for (i, share) in iter_shares.iter().enumerate() {
        let primary_blind =
            commitment
                .share_blinds
                .get(i)
                .cloned()
                .ok_or_else(|| VotingError::InvalidInput {
                    message: format!("missing primary blind for encrypted share index {i}"),
                })?;
        payloads.push(SharePayload {
            shares_hash: commitment.shares_hash.clone(),
            proposal_id: commitment.proposal_id,
            vote_decision,
            enc_share: share.clone(),
            tree_position: vc_tree_position,
            all_enc_shares: all_enc_shares.clone(),
            share_comms: commitment.share_comms.clone(),
            primary_blind,
        });
    }

    Ok(payloads)
}

/// Compute the canonical cast-vote sighash, decompress r_vpk, and sign.
///
/// This is a pure computation — no DB access needed. Takes the fields from
/// `VoteCommitmentBundle` plus the hotkey seed for signing.
///
/// `network`: Zcash network used to derive the hotkey spending key.
///
/// The canonical sighash must match Go's `ComputeCastVoteSighash`:
/// ```text
/// Blake2b-256(domain || vote_round_id || r_vpk || van_nullifier ||
///             vote_authority_note_new || vote_commitment ||
///             proposal_id(4 LE, padded 32) || anchor_height(8 LE, padded 32))
/// ```
pub(crate) fn sign_cast_vote(
    hotkey_seed: &[u8],
    network: Network,
    vote_round_id_hex: &str,
    r_vpk_bytes: &[u8],
    van_nullifier: &[u8],
    vote_authority_note_new: &[u8],
    vote_commitment: &[u8],
    proposal_id: u32,
    anchor_height: u32,
    alpha_v: &[u8],
) -> Result<CastVoteSignature, VotingError> {
    use ff::PrimeField;

    // Derive the voting hotkey SpendingKey from seed.
    let sk = crate::hotkey::spending_key_from_hotkey_seed(
        hotkey_seed,
        network,
        crate::hotkey::VOTING_HOTKEY_ACCOUNT_INDEX,
    )?;
    let ask = orchard::keys::SpendAuthorizingKey::from(&sk);

    // Deserialize alpha_v
    let alpha_v_arr: [u8; 32] = alpha_v.try_into().map_err(|_| VotingError::Internal {
        message: format!("alpha_v must be 32 bytes, got {}", alpha_v.len()),
    })?;
    let alpha_v_scalar: pasta_curves::pallas::Scalar =
        Option::from(pasta_curves::pallas::Scalar::from_repr(alpha_v_arr)).ok_or_else(|| {
            VotingError::Internal {
                message: "alpha_v is not a valid Pallas scalar".to_string(),
            }
        })?;

    // Compute rsk_v = ask_v.randomize(alpha_v)
    let rsk_v = ask.randomize(&alpha_v_scalar);

    // Validate r_vpk is 32 bytes
    if r_vpk_bytes.len() != 32 {
        return Err(VotingError::Internal {
            message: format!("r_vpk must be 32 bytes, got {}", r_vpk_bytes.len()),
        });
    }

    let sighash = cast_vote_sighash(
        vote_round_id_hex,
        r_vpk_bytes,
        van_nullifier,
        vote_authority_note_new,
        vote_commitment,
        proposal_id,
        anchor_height,
    )?;

    // Sign
    let mut rng = rand::rngs::OsRng;
    let sig = rsk_v.sign(&mut rng, &sighash);
    let sig_bytes: [u8; 64] = (&sig).into();

    Ok(CastVoteSignature {
        vote_auth_sig: sig_bytes.to_vec(),
    })
}

pub(crate) fn cast_vote_sighash(
    vote_round_id_hex: &str,
    r_vpk_bytes: &[u8],
    van_nullifier: &[u8],
    vote_authority_note_new: &[u8],
    vote_commitment: &[u8],
    proposal_id: u32,
    anchor_height: u32,
) -> Result<[u8; 32], VotingError> {
    let vote_round_id_bytes =
        hex::decode(vote_round_id_hex).map_err(|e| VotingError::Internal {
            message: format!("invalid vote_round_id hex: {e}"),
        })?;

    const CAST_VOTE_SIGHASH_DOMAIN: &[u8] = b"SVOTE_CAST_VOTE_SIGHASH_V0";
    let mut canonical = Vec::new();
    canonical.extend_from_slice(CAST_VOTE_SIGHASH_DOMAIN);
    extend_padded32(&mut canonical, &vote_round_id_bytes);
    canonical.extend_from_slice(r_vpk_bytes);
    extend_padded32(&mut canonical, van_nullifier);
    extend_padded32(&mut canonical, vote_authority_note_new);
    extend_padded32(&mut canonical, vote_commitment);

    let mut pid_buf = [0u8; 32];
    pid_buf[..4].copy_from_slice(&proposal_id.to_le_bytes());
    canonical.extend_from_slice(&pid_buf);

    let mut ah_buf = [0u8; 32];
    ah_buf[..8].copy_from_slice(&(anchor_height as u64).to_le_bytes());
    canonical.extend_from_slice(&ah_buf);

    let sighash_full = blake2b_simd::Params::new().hash_length(32).hash(&canonical);
    let mut sighash = [0u8; 32];
    sighash.copy_from_slice(sighash_full.as_bytes());
    Ok(sighash)
}

/// Append exactly 32 bytes to `out` from `b` (pad with zeros if shorter).
fn extend_padded32(out: &mut Vec<u8>, b: &[u8]) {
    let mut buf = [0u8; 32];
    let n = b.len().min(32);
    buf[..n].copy_from_slice(&b[..n]);
    out.extend_from_slice(&buf);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn mock_enc_shares() -> Vec<WireEncryptedShare> {
        vec![
            WireEncryptedShare {
                c1: vec![0xC1; 32],
                c2: vec![0xC2; 32],
                share_index: 0,
            },
            WireEncryptedShare {
                c1: vec![0xC1; 32],
                c2: vec![0xC2; 32],
                share_index: 1,
            },
        ]
    }

    fn mock_commitment() -> VoteCommitmentBundle {
        VoteCommitmentBundle {
            van_nullifier: vec![0xAA; 32],
            vote_authority_note_new: vec![0xBB; 32],
            vote_commitment: vec![0xCC; 32],
            proposal_id: 1,
            proof: vec![0xAB; 256],
            enc_shares: vec![],
            anchor_height: 0,
            vote_round_id: String::new(),
            shares_hash: vec![0xDD; 32],
            share_blinds: (0..5).map(|_| vec![0x11; 32]).collect(),
            share_comms: (0..5).map(|_| vec![0x22; 32]).collect(),
            r_vpk_bytes: vec![0xEE; 32],
            alpha_v: vec![0xFF; 32],
        }
    }

    #[test]
    fn test_build_share_payloads() {
        let commitment = mock_commitment();
        let result =
            build_share_payloads(&mock_enc_shares(), &commitment, 1, 2, 42, false).unwrap();
        assert_eq!(result.len(), 2);
        assert_eq!(result[0].proposal_id, 1);
        assert_eq!(result[0].vote_decision, 1);
        assert_eq!(result[0].tree_position, 42);
        assert_eq!(result[0].shares_hash, commitment.shares_hash);
        assert_eq!(result[0].enc_share.share_index, 0);
        assert_eq!(result[1].enc_share.share_index, 1);
    }

    #[test]
    fn test_build_share_payloads_rejects_missing_primary_blind() {
        let mut commitment = mock_commitment();
        commitment.share_blinds.truncate(1);

        let err = build_share_payloads(&mock_enc_shares(), &commitment, 1, 2, 42, false)
            .expect_err("missing share blind should fail");

        assert!(err.to_string().contains("missing primary blind"), "{err}");
    }

    #[test]
    fn test_build_share_payloads_rejects_invalid_vote_bounds() {
        let commitment = mock_commitment();

        let too_few_options =
            build_share_payloads(&mock_enc_shares(), &commitment, 0, 1, 42, false)
                .expect_err("too few options should fail");
        assert!(
            too_few_options.to_string().contains("num_options"),
            "{too_few_options}"
        );

        let too_many_options =
            build_share_payloads(&mock_enc_shares(), &commitment, 0, 9, 42, false)
                .expect_err("too many options should fail");
        assert!(
            too_many_options.to_string().contains("num_options"),
            "{too_many_options}"
        );

        let out_of_range_choice =
            build_share_payloads(&mock_enc_shares(), &commitment, 2, 2, 42, false)
                .expect_err("out of range vote decision should fail");
        assert!(
            out_of_range_choice.to_string().contains("vote_decision"),
            "{out_of_range_choice}"
        );
    }

    #[test]
    fn test_build_share_payloads_rejects_invalid_proposal_id() {
        let mut commitment = mock_commitment();
        commitment.proposal_id = 0;
        assert!(build_share_payloads(&mock_enc_shares(), &commitment, 0, 2, 42, false).is_err());

        let mut commitment = mock_commitment();
        commitment.proposal_id = 16;
        assert!(build_share_payloads(&mock_enc_shares(), &commitment, 0, 2, 42, false).is_err());
    }
}
