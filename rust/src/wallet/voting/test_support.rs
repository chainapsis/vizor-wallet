#![cfg(test)]
//! Shared voting test fixtures used across Rust unit tests.
//!
//! This module is intentionally test-only so fixture values do not leak into
//! non-test builds.

pub(crate) const ROUND_ID: &str =
    "0000000000000000000000000000000000000000000000000000000000000001";
pub(crate) const TEST_ACCOUNT_UUID: &str = "550e8400-e29b-41d4-a716-446655440000";
#[allow(dead_code)]
pub(crate) const TEST_MNEMONIC: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

pub(crate) fn test_api_round_params() -> zcash_voting::wire::VotingRoundParams {
    zcash_voting::wire::VotingRoundParams {
        vote_round_id: ROUND_ID.to_string(),
        snapshot_height: 100,
        ea_pk: vec![0xEA; 32],
        nc_root: vec![2; 32],
        nullifier_imt_root: vec![3; 32],
    }
}

pub(crate) fn test_note_info(position: u64) -> zcash_voting::NoteInfo {
    let mut unique = [0u8; 32];
    unique[..8].copy_from_slice(&position.to_le_bytes());

    zcash_voting::NoteInfo {
        commitment: unique.map(|byte| byte ^ 0x11).to_vec(),
        nullifier: unique.map(|byte| byte ^ 0x22).to_vec(),
        value: zcash_voting::governance::BALLOT_DIVISOR,
        position,
        diversifier: vec![3; 11],
        rho: unique.map(|byte| byte ^ 0x44).to_vec(),
        rseed: unique.map(|byte| byte ^ 0x55).to_vec(),
        scope: 0,
        ufvk_str: "uviewtest".to_string(),
    }
}
