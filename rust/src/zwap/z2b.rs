//! z2b (ZEC→BTC) responder material assembly — the pure, stateless step that
//! turns `(wallet seed, swap_id)` plus the solver's public Phase0 half into the
//! z2b artifacts the wallet needs:
//!
//! 1. the **joint ZEC unified address** the user funds from its own wallet (and
//!    the solver later drains once the user's `k_b` is revealed on-chain), and
//! 2. the **BTC HTLC lock** the solver funds and the user CLAIMS (branch-1) to
//!    its receive address — re-derived from both halves so the wallet never
//!    trusts material it was handed (fund-safety gate).
//!
//! z2b is b2z with the roles flipped (see the SDK `buildResponderPhase0`):
//!  - the user CLAIMS the lock (branch-1, `b_b` = the user's per-swap claim
//!    pubkey), the solver REFUNDS it (branch-2, `br_a` = the solver's refund
//!    pubkey);
//!  - `h_A` = the solver's hashlock (`SHA256(k_solver)`), `h_B` = `SHA256(user
//!    k_be)`;
//!  - the solver owns the swap secret, so `swap_hash` comes from the solver's
//!    half (the user does not derive/reveal it).
//!
//! All inputs are public except the wallet seed; no network, no chain.

use super::bech32_segwit::p2wsh_address_from_spk;
use super::btc_lock::{derive_lock, LockMaterial};
use super::dkm::{derive_btc_claim_keypair, derive_initiator_half, hashlock_commit};
use super::joint_orchard::{derive_joint_orchard, ZecNetwork};

/// The solver's public contribution to a z2b swap, as relayed by the orderbook
/// after the wallet re-verified the backing poold proof. All public. Differs
/// from the b2z `SolverPublicHalf`: z2b carries the solver's REFUND pubkey +
/// the solver-owned `swap_hash` (b2z carried the solver's claim pubkey).
#[derive(Clone, Debug)]
pub struct SolverPublicHalfZ2b {
    /// `ak_b = k_b · SpendAuthBase`, SEC1-compressed (33 bytes) — joint UA.
    pub ak_sec1: [u8; 33],
    /// `nsk_b` nullifier share, LE (32 bytes) — joint UA.
    pub nsk_le: [u8; 32],
    /// The solver's hashlock commitment `h_b = SHA256(k_solver)` — becomes the
    /// lock's `h_A` (branch-2 refund commitment; the solver refunds).
    pub h_b: [u8; 32],
    /// The solver's BTC refund pubkey `br_a` (33-byte compressed secp256k1).
    pub refund_pubkey: [u8; 33],
    /// `swap_hash = SHA256(secret)` — the solver owns the secret in z2b.
    pub swap_hash: [u8; 32],
}

/// CSV timelocks for the lock (blocks): `t1` = solver refund, `t2` = user
/// force-claim window. Must satisfy `16 < t1 < t2` (MINIMALDATA standardness).
#[derive(Clone, Copy, Debug)]
pub struct LockTimelocks {
    pub t1: u32,
    pub t2: u32,
}

/// The assembled z2b material.
#[derive(Clone, Debug)]
pub struct Z2bMaterial {
    /// Bech32 P2WSH address of the lock the solver funds (informational).
    pub btc_lock_address: String,
    /// The lock witnessScript (hex) — required to build the branch-1 claim.
    pub witness_script_hex: String,
    /// The user's per-swap BTC claim pubkey `b_b` (33-byte compressed hex) —
    /// reported to the orderbook as the FE material's `refundPubkey` field.
    pub claim_pubkey_hex: String,
    /// The joint Orchard unified address the user FUNDS from its wallet.
    pub joint_zec_address: String,
    /// The joint Orchard UFVK (`uview…`).
    pub joint_zec_ufvk: String,
    /// Joint Orchard `nk`/`rivk` (32-byte hex) — for the refund-path sweep only.
    pub joint_zec_nk_hex: String,
    pub joint_zec_rivk_hex: String,
    /// Joint `ak`/`ivk`/`diversifier` (hex) — refund-path local trial-decrypt.
    pub joint_zec_ak_hex: String,
    pub joint_zec_ivk_hex: String,
    pub joint_zec_diversifier_hex: String,
    /// `swap_hash` (hex) — the solver-owned lock branch-1 commitment.
    pub swap_hash_hex: String,
    /// `h_b = SHA256(user k_be)` (hex) — the lock's branch-1 `k_b` commitment.
    pub h_b_hex: String,
}

fn map_network(network: &str) -> ZecNetwork {
    match network {
        "mainnet" | "main" => ZecNetwork::Mainnet,
        "testnet" | "test" => ZecNetwork::Testnet,
        _ => ZecNetwork::Regtest,
    }
}

/// Assemble the z2b responder material. `network` is `mainnet` | `testnet` |
/// `regtest` and selects both the ZEC UA HRP and the BTC bech32 HRP.
pub fn derive_z2b_material(
    seed: &[u8],
    swap_id: &str,
    solver: &SolverPublicHalfZ2b,
    timelocks: LockTimelocks,
    network: &str,
) -> Result<Z2bMaterial, String> {
    // Our own stateless Orchard half + per-swap BTC claim key.
    let half = derive_initiator_half(seed, swap_id)?;
    let (_claim_sk, claim_pub) = derive_btc_claim_keypair(seed, swap_id)?;

    // Hashlocks (flipped): h_A = solver's hashlock; h_B = SHA256(user k_be).
    let h_a = solver.h_b;
    let h_b = hashlock_commit(&half.k_be);

    // Joint ZEC UA (re-derived from both halves — never trusted from the wire).
    let joint = derive_joint_orchard(
        &half.ak_sec1,
        &solver.ak_sec1,
        &half.nsk_le,
        &solver.nsk_le,
        map_network(network),
    )?;

    // BTC P2WSH HTLC lock (role-flipped: user claims via b_b, solver refunds via br_a).
    let lock = derive_lock(&LockMaterial {
        swap_hash: solver.swap_hash,
        h_a,
        h_b,
        b_b: claim_pub,
        br_a: solver.refund_pubkey,
        t1: timelocks.t1,
        t2: timelocks.t2,
    })?;
    let spk = hex::decode(&lock.p2wsh_spk_hex).map_err(|e| format!("spk hex: {e}"))?;
    let btc_lock_address = p2wsh_address_from_spk(&spk, network)?;

    Ok(Z2bMaterial {
        btc_lock_address,
        witness_script_hex: lock.witness_script_hex,
        claim_pubkey_hex: hex::encode(claim_pub),
        joint_zec_address: joint.deposit_address,
        joint_zec_ufvk: joint.joint_ufvk_encoded,
        joint_zec_nk_hex: hex::encode(joint.nk),
        joint_zec_rivk_hex: hex::encode(joint.rivk),
        joint_zec_ak_hex: hex::encode(joint.ak),
        joint_zec_ivk_hex: hex::encode(joint.ivk),
        joint_zec_diversifier_hex: hex::encode(joint.diversifier),
        swap_hash_hex: hex::encode(solver.swap_hash),
        h_b_hex: hex::encode(h_b),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::zwap::dkm::{derive_initiator_half as solver_like_half, hashlock_commit};

    /// Synthesize a plausible solver public half for z2b from a second seed.
    fn synth_solver(seed: &[u8], swap_id: &str) -> SolverPublicHalfZ2b {
        let h = solver_like_half(seed, swap_id).unwrap();
        let h_b = hashlock_commit(&h.k_be);
        // A throwaway but valid compressed secp pubkey for the solver refund key.
        let (_sk, refund) = derive_btc_claim_keypair(seed, swap_id).unwrap();
        SolverPublicHalfZ2b {
            ak_sec1: h.ak_sec1,
            nsk_le: h.nsk_le,
            h_b,
            refund_pubkey: refund,
            swap_hash: [0xcd; 32],
        }
    }

    #[test]
    fn derives_joint_ua_and_lock_regtest() {
        let seed = [9u8; 32];
        let solver = synth_solver(&[5u8; 32], "swap-z2b-1");
        let m = derive_z2b_material(&seed, "swap-z2b-1", &solver, LockTimelocks { t1: 24, t2: 48 }, "regtest").unwrap();
        assert!(m.btc_lock_address.starts_with("bcrt1q"), "btc lock: {}", m.btc_lock_address);
        assert!(m.joint_zec_address.starts_with("uregtest1"), "joint UA: {}", m.joint_zec_address);
        assert!(m.joint_zec_ufvk.starts_with("uview"), "ufvk: {}", m.joint_zec_ufvk);
        assert_eq!(m.claim_pubkey_hex.len(), 66);
        assert_eq!(m.swap_hash_hex, hex::encode([0xcd_u8; 32]));
        assert_eq!(m.h_b_hex.len(), 64);
    }

    #[test]
    fn deterministic() {
        let seed = [9u8; 32];
        let solver = synth_solver(&[5u8; 32], "swap-z2b-2");
        let a = derive_z2b_material(&seed, "swap-z2b-2", &solver, LockTimelocks { t1: 24, t2: 48 }, "regtest").unwrap();
        let b = derive_z2b_material(&seed, "swap-z2b-2", &solver, LockTimelocks { t1: 24, t2: 48 }, "regtest").unwrap();
        assert_eq!(a.joint_zec_address, b.joint_zec_address);
        assert_eq!(a.witness_script_hex, b.witness_script_hex);
        assert_eq!(a.claim_pubkey_hex, b.claim_pubkey_hex);
    }
}
