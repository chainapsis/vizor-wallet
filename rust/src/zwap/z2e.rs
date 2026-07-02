//! z2e (ZEC→ETH/USDC) responder material assembly — the EVM analog of [`super::z2b`].
//!
//! Give-ZEC, EVM leg: the user funds the joint Orchard note; the solver funds a
//! singleton `ZwapHtlc` EVM lock (native ETH for z2e, ERC-20 for z2erc20),
//! reveals the secret + posts its `claim_buy` sig_a ADAPTOR; the user completes
//! that adaptor with its own `k_be` and calls `claim_buy(slotId, preimage,
//! sigA, sigB)` — revealing `k_user` on-chain so the solver drains the joint
//! note. Single-scalar reuse: the user's EVM CLAIM key IS its joint spend-auth
//! scalar `k_be` (so completing the claim reveals exactly the scalar the joint
//! `ask = k_user + k_solver` needs). Mirrors the SDK `buildResponderEvmPhase0`.

use secp256k1::{PublicKey, Secp256k1, SecretKey};

use super::dkm::{derive_initiator_half, hashlock_commit};
use super::evm::{eth_address, htlc_digest, slot_id, DOMAIN_CLAIM_BUY, DOMAIN_REFUND_TO_INITIATOR};
use super::joint_orchard::{derive_joint_orchard, ZecNetwork};

/// The solver's public contribution to a z2e swap (relayed via the verified
/// poold pair). `lock_pubkey` is the solver's `k_be·secp_G` — BOTH its EVM claim
/// address source (`b_a = eth_address(lock_pubkey)`) AND the adaptor encryption
/// point. `refund_pubkey` is the solver's EVM refund key; `h_b`/`swap_hash` are
/// the solver-owned commitments.
#[derive(Clone, Debug)]
pub struct SolverPublicHalfZ2e {
    pub ak_sec1: [u8; 33],
    pub nsk_le: [u8; 32],
    pub lock_pubkey: [u8; 33],
    pub refund_pubkey: [u8; 33],
    pub h_b: [u8; 32],
    pub swap_hash: [u8; 32],
}

/// The assembled z2e material.
#[derive(Clone, Debug)]
pub struct Z2eMaterial {
    /// The joint Orchard UA the USER funds from its wallet.
    pub joint_zec_address: String,
    pub joint_zec_ufvk: String,
    pub joint_zec_nk_hex: String,
    pub joint_zec_rivk_hex: String,
    pub joint_zec_ak_hex: String,
    pub joint_zec_ivk_hex: String,
    pub joint_zec_diversifier_hex: String,
    /// The EVM HTLC slot id (hex) — the lock the solver funds + the user claims.
    pub evm_slot_id_hex: String,
    /// `claim_buy` domain digest (hex) — the user signs it (sig_b) + completes
    /// the solver's adaptor over it (sig_a).
    pub claim_buy_digest_hex: String,
    /// `refund_to_initiator` domain digest (hex) — the user pre-signs sig_b over
    /// it (the solver's t1 inactivity-refund half).
    pub refund_to_initiator_digest_hex: String,
    /// The solver's EVM claim address `b_a` (hex) — the `expected_signer` when
    /// completing the solver's adaptor.
    pub solver_claim_addr_hex: String,
    /// `swap_hash` (hex, solver-owned) and `h_b = SHA256(user k_be)` (hex) — the
    /// phase0 hashlock commitments (lock `h_A`=solver's, `h_B`=this).
    pub swap_hash_hex: String,
    pub h_b_hex: String,
}

fn map_network(network: &str) -> ZecNetwork {
    match network {
        "mainnet" | "main" => ZecNetwork::Mainnet,
        "testnet" | "test" => ZecNetwork::Testnet,
        _ => ZecNetwork::Regtest,
    }
}

fn eth_addr_from_pub33(pk33: &[u8; 33]) -> Result<[u8; 20], String> {
    let pk = PublicKey::from_slice(pk33).map_err(|e| format!("pubkey: {e}"))?;
    Ok(eth_address(&pk))
}

fn eth_addr_from_sk32(sk32: &[u8; 32]) -> Result<[u8; 20], String> {
    let sk = SecretKey::from_slice(sk32).map_err(|e| format!("scalar as secp sk: {e}"))?;
    Ok(eth_address(&PublicKey::from_secret_key(&Secp256k1::new(), &sk)))
}

/// Assemble the z2e material. `recipient_evm_addr` (the user's connected wallet
/// where the claimed ETH lands) and `solver_evm_addr` (the solver's EVM home /
/// lock funder) come from the recover snapshot; both are bound into the slot id
/// (so the FE-derived slot equals the solver's). `token` is the zero address for
/// native ETH (z2e) or the ERC-20 contract (z2erc20). `contract` is the
/// singleton `ZwapHtlc` address.
#[allow(clippy::too_many_arguments)]
pub fn derive_z2e_material(
    seed: &[u8],
    swap_id: &str,
    solver: &SolverPublicHalfZ2e,
    recipient_evm_addr: &[u8; 20],
    solver_evm_addr: &[u8; 20],
    timelock: u64,
    chain_id: u64,
    contract: &[u8; 20],
    token: &[u8; 20],
    network: &str,
) -> Result<Z2eMaterial, String> {
    let half = derive_initiator_half(seed, swap_id)?;

    // Single-scalar: the user's EVM claim addr b_b = eth_address(k_be·G).
    let b_b = eth_addr_from_sk32(&half.k_be)?;
    let b_a = eth_addr_from_pub33(&solver.lock_pubkey)?; // solver claim addr
    // buyer = the user's receive wallet; initiator = the solver's lock funder.
    let buyer = *recipient_evm_addr;
    let initiator = *solver_evm_addr;

    let sid = slot_id(&solver.swap_hash, &b_a, &b_b, &buyer, &initiator, timelock, token);
    let claim_buy = htlc_digest(DOMAIN_CLAIM_BUY, chain_id, contract, &sid);
    let refund_to_init = htlc_digest(DOMAIN_REFUND_TO_INITIATOR, chain_id, contract, &sid);

    let joint = derive_joint_orchard(
        &half.ak_sec1,
        &solver.ak_sec1,
        &half.nsk_le,
        &solver.nsk_le,
        map_network(network),
    )?;

    Ok(Z2eMaterial {
        joint_zec_address: joint.deposit_address,
        joint_zec_ufvk: joint.joint_ufvk_encoded,
        joint_zec_nk_hex: hex::encode(joint.nk),
        joint_zec_rivk_hex: hex::encode(joint.rivk),
        joint_zec_ak_hex: hex::encode(joint.ak),
        joint_zec_ivk_hex: hex::encode(joint.ivk),
        joint_zec_diversifier_hex: hex::encode(joint.diversifier),
        evm_slot_id_hex: hex::encode(sid),
        claim_buy_digest_hex: hex::encode(claim_buy),
        refund_to_initiator_digest_hex: hex::encode(refund_to_init),
        solver_claim_addr_hex: hex::encode(b_a),
        swap_hash_hex: hex::encode(solver.swap_hash),
        h_b_hex: hex::encode(hashlock_commit(&half.k_be)),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::zwap::dkm::{derive_btc_claim_keypair, derive_initiator_half as solver_like_half};

    fn synth_solver(seed: &[u8], swap_id: &str) -> SolverPublicHalfZ2e {
        let h = solver_like_half(seed, swap_id).unwrap();
        let (_sk, lock_pub) = derive_btc_claim_keypair(seed, swap_id).unwrap();
        let (_sk2, refund_pub) = derive_btc_claim_keypair(seed, "refund").unwrap();
        SolverPublicHalfZ2e {
            ak_sec1: h.ak_sec1,
            nsk_le: h.nsk_le,
            lock_pubkey: lock_pub,
            refund_pubkey: refund_pub,
            h_b: crate::zwap::dkm::hashlock_commit(&h.k_be),
            swap_hash: [0xcd; 32],
        }
    }

    #[test]
    fn derives_joint_ua_and_evm_lock() {
        let seed = [9u8; 32];
        let solver = synth_solver(&[5u8; 32], "swap-z2e-1");
        let recipient = [0x11u8; 20];
        let solver_evm = [0x22u8; 20];
        let contract = [0x33u8; 20];
        let token = [0u8; 20]; // native ETH
        let m = derive_z2e_material(
            &seed, "swap-z2e-1", &solver, &recipient, &solver_evm, 5000, 31337, &contract, &token,
            "regtest",
        )
        .unwrap();
        assert!(m.joint_zec_address.starts_with("uregtest1"), "joint UA: {}", m.joint_zec_address);
        assert_eq!(m.evm_slot_id_hex.len(), 64);
        assert_eq!(m.claim_buy_digest_hex.len(), 64);
        assert_eq!(m.solver_claim_addr_hex.len(), 40);
        assert_eq!(m.swap_hash_hex, hex::encode([0xcd_u8; 32]));
    }

    #[test]
    fn deterministic() {
        let seed = [9u8; 32];
        let solver = synth_solver(&[5u8; 32], "swap-z2e-2");
        let a = derive_z2e_material(&seed, "swap-z2e-2", &solver, &[1u8; 20], &[2u8; 20], 5000, 31337, &[3u8; 20], &[0u8; 20], "regtest").unwrap();
        let b = derive_z2e_material(&seed, "swap-z2e-2", &solver, &[1u8; 20], &[2u8; 20], 5000, 31337, &[3u8; 20], &[0u8; 20], "regtest").unwrap();
        assert_eq!(a.evm_slot_id_hex, b.evm_slot_id_hex);
        assert_eq!(a.joint_zec_address, b.joint_zec_address);
    }
}
