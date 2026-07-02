//! b2z (BTC→ZEC) initiator material assembly — the pure, stateless step that
//! turns `(wallet seed, swap_id)` plus the solver's public Phase0 half into the
//! two on-chain artifacts a b2z swap presents:
//!
//! 1. the **BTC lock address** the user funds (their BTC → P2WSH HTLC), and
//! 2. the **joint ZEC unified address** the solver funds and the user later
//!    sweeps — re-derived from both halves so the wallet never trusts a UA it
//!    was handed (fund-safety gate).
//!
//! All inputs are public except the wallet seed; no network, no chain. The
//! orchestrator (Phase 6) supplies `SolverPublicHalf` from a verified poold
//! entry and drives funding/sweep around this.

use super::bech32_segwit::p2wsh_address_from_spk;
use super::btc_lock::{derive_lock, LockMaterial};
use super::dkm::{derive_initiator_half, derive_swap_secret, hashlock_commit};
use super::joint_orchard::{derive_joint_orchard, ZecNetwork};

/// The solver's public contribution to a b2z swap, as relayed by the orderbook
/// after the wallet has re-verified the backing poold proof. All public.
#[derive(Clone, Debug)]
pub struct SolverPublicHalf {
    /// `ak_b = k_b · SpendAuthBase`, SEC1-compressed (33 bytes) — joint UA.
    pub ak_sec1: [u8; 33],
    /// `nsk_b` nullifier share, LE (32 bytes) — joint UA.
    pub nsk_le: [u8; 32],
    /// The solver's BTC claim pubkey `b_b` (33-byte compressed secp256k1).
    pub b_b: [u8; 33],
    /// `h_b = SHA256(k_b)` — the solver's hashlock commitment.
    pub h_b: [u8; 32],
}

/// CSV timelocks for the lock (blocks): `t1` = initiator refund, `t2` = solver
/// force-claim. Must satisfy `16 < t1 < t2` (MINIMALDATA standardness).
#[derive(Clone, Copy, Debug)]
pub struct LockTimelocks {
    pub t1: u32,
    pub t2: u32,
}

/// The assembled, displayable b2z material.
#[derive(Clone, Debug)]
pub struct B2zMaterial {
    /// Bech32 P2WSH address the user funds with BTC.
    pub btc_lock_address: String,
    /// The lock witnessScript (hex) — needed later to spend/refund.
    pub witness_script_hex: String,
    /// The joint Orchard unified address the solver funds and the user sweeps.
    pub joint_zec_address: String,
    /// The joint Orchard UFVK (`uview…`) — view-only key to scan the joint UA.
    pub joint_zec_ufvk: String,
    /// Joint Orchard `nk` (32-byte nullifier key), hex — required (with `ask`)
    /// to build the joint-note sweep. NOT the UFVK string.
    pub joint_zec_nk_hex: String,
    /// Joint Orchard `rivk` (32-byte scalar), hex — required for the sweep FVK.
    pub joint_zec_rivk_hex: String,
    /// Joint Orchard `ak`/`ivk` (32-byte hex) + `diversifier` (11-byte hex) —
    /// needed to trial-decrypt the joint note LOCALLY from the chain (so the
    /// sweep note is never trusted from the orderbook).
    pub joint_zec_ak_hex: String,
    pub joint_zec_ivk_hex: String,
    pub joint_zec_diversifier_hex: String,
    /// `swap_hash = SHA256(secret)` committed in branch 1 of the lock.
    pub swap_hash_hex: String,
    /// `h_a = SHA256(k_a)` — the initiator's hashlock commitment (refund branch).
    pub h_a_hex: String,
}

fn map_network(network: &str) -> ZecNetwork {
    match network {
        "mainnet" | "main" => ZecNetwork::Mainnet,
        "testnet" | "test" => ZecNetwork::Testnet,
        _ => ZecNetwork::Regtest,
    }
}

/// Assemble the b2z initiator material. `network` is `mainnet` | `testnet` |
/// `regtest` and selects both the ZEC UA HRP and the BTC bech32 HRP.
pub fn derive_b2z_material(
    seed: &[u8],
    swap_id: &str,
    solver: &SolverPublicHalf,
    timelocks: LockTimelocks,
    network: &str,
) -> Result<B2zMaterial, String> {
    // Our own stateless half + swap secret.
    let half = derive_initiator_half(seed, swap_id)?;
    let secret = derive_swap_secret(seed, swap_id);
    let swap_hash = hashlock_commit(&secret); // SHA256(secret)
    let h_a = hashlock_commit(&half.k_be); // SHA256(k_a)

    // The initiator's BTC refund pubkey (br_a) — the refund branch's CHECKSIG
    // key, stateless from the seed (`priv = SHA256(seed ‖ 0x42)`). The matching
    // private key stays in the wallet for the CSV refund path (Phase 4 signing).
    let br_a = derive_btc_refund_pubkey(seed)?;

    // Joint ZEC UA (re-derived from both halves — never trusted from the wire).
    let joint = derive_joint_orchard(
        &half.ak_sec1,
        &solver.ak_sec1,
        &half.nsk_le,
        &solver.nsk_le,
        map_network(network),
    )?;

    // BTC P2WSH HTLC lock.
    let lock = derive_lock(&LockMaterial {
        swap_hash,
        h_a,
        h_b: solver.h_b,
        b_b: solver.b_b,
        br_a,
        t1: timelocks.t1,
        t2: timelocks.t2,
    })?;
    let spk = hex::decode(&lock.p2wsh_spk_hex).map_err(|e| format!("spk hex: {e}"))?;
    let btc_lock_address = p2wsh_address_from_spk(&spk, network)?;

    Ok(B2zMaterial {
        btc_lock_address,
        witness_script_hex: lock.witness_script_hex,
        joint_zec_address: joint.deposit_address,
        joint_zec_ufvk: joint.joint_ufvk_encoded,
        joint_zec_nk_hex: hex::encode(joint.nk),
        joint_zec_rivk_hex: hex::encode(joint.rivk),
        joint_zec_ak_hex: hex::encode(joint.ak),
        joint_zec_ivk_hex: hex::encode(joint.ivk),
        joint_zec_diversifier_hex: hex::encode(joint.diversifier),
        swap_hash_hex: hex::encode(swap_hash),
        h_a_hex: hex::encode(h_a),
    })
}

/// Deterministic 33-byte compressed secp256k1 BTC refund pubkey from the wallet
/// seed (`priv = SHA256(seed ‖ 0x42)`), matching the SDK `deriveBtcRefundPubkey`.
fn derive_btc_refund_pubkey(seed: &[u8]) -> Result<[u8; 33], String> {
    use secp256k1::{PublicKey, Secp256k1, SecretKey};
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(seed);
    h.update([0x42]);
    let priv_bytes = h.finalize();
    let sk = SecretKey::from_slice(&priv_bytes).map_err(|e| format!("btc refund sk: {e}"))?;
    let pk = PublicKey::from_secret_key(&Secp256k1::new(), &sk);
    Ok(pk.serialize())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::zwap::dkm::derive_initiator_half as solver_like_half;

    /// Synthesize a plausible solver public half from a second seed (the math is
    /// symmetric: both sides are `k·SpendAuthBase` + an `nsk` share).
    fn synth_solver(seed: &[u8], swap_id: &str) -> SolverPublicHalf {
        let h = solver_like_half(seed, swap_id).unwrap();
        let h_b = crate::zwap::dkm::hashlock_commit(&h.k_be);
        // A throwaway but valid compressed secp pubkey for b_b.
        let b_b = super::derive_btc_refund_pubkey(seed).unwrap();
        SolverPublicHalf { ak_sec1: h.ak_sec1, nsk_le: h.nsk_le, b_b, h_b }
    }

    #[test]
    fn derives_both_addresses_regtest() {
        let seed = [9u8; 32];
        let solver = synth_solver(&[5u8; 32], "swap-b2z-1");
        let m = derive_b2z_material(
            &seed,
            "swap-b2z-1",
            &solver,
            LockTimelocks { t1: 72, t2: 144 },
            "regtest",
        )
        .unwrap();

        assert!(m.btc_lock_address.starts_with("bcrt1q"), "btc lock: {}", m.btc_lock_address);
        assert!(
            m.joint_zec_address.starts_with("uregtest1"),
            "joint ZEC UA: {}",
            m.joint_zec_address
        );
        assert!(m.joint_zec_ufvk.starts_with("uview"), "ufvk: {}", m.joint_zec_ufvk);
        assert_eq!(m.swap_hash_hex.len(), 64);
        assert_eq!(m.h_a_hex.len(), 64);
    }

    /// Print the b2z artifacts for a FIXED cross-impl parity vector. Run with
    /// `cargo test --lib zwap::b2z::tests::print_parity_vector -- --nocapture`.
    /// The zwap SDK, fed the SAME (seedA, seedB, swap_id, timelocks, network),
    /// must produce byte-identical `joint_zec_address` + `btc_lock_address`.
    #[test]
    fn print_parity_vector() {
        // seedA = wallet (initiator), seedB = stand-in solver. Both halves come
        // from the SAME `derive_initiator_half` the SDK exposes as `deriveInitiatorHalf`.
        let seed_a = [0x11u8; 32];
        let solver = synth_solver(&[0x22u8; 32], "parity-demo");
        let m = derive_b2z_material(
            &seed_a,
            "parity-demo",
            &solver,
            LockTimelocks { t1: 72, t2: 144 },
            "regtest",
        )
        .unwrap();
        let ha = crate::zwap::dkm::derive_initiator_half(&seed_a, "parity-demo").unwrap();
        println!("VIZOR_PARITY_JSON {{\"network\":\"regtest\",\"joint_zec_address\":\"{}\",\"btc_lock_address\":\"{}\",\"swap_hash_hex\":\"{}\",\"joint_zec_ufvk\":\"{}\",\"a_k_be\":\"{}\",\"a_ak_sec1\":\"{}\",\"a_nsk_le\":\"{}\"}}",
            m.joint_zec_address, m.btc_lock_address, m.swap_hash_hex, m.joint_zec_ufvk,
            hex::encode(ha.k_be), hex::encode(ha.ak_sec1), hex::encode(ha.nsk_le));

        // Same derivation on MAINNET parameters — the real addresses a mainnet
        // b2z swap would present (bc1q… lock, u1… joint UA). No funds needed;
        // proves the crypto is correct on mainnet, byte-checkable vs the SDK.
        let mm = derive_b2z_material(
            &seed_a,
            "parity-demo",
            &solver,
            LockTimelocks { t1: 72, t2: 144 },
            "mainnet",
        )
        .unwrap();
        println!("VIZOR_PARITY_JSON {{\"network\":\"mainnet\",\"joint_zec_address\":\"{}\",\"btc_lock_address\":\"{}\",\"swap_hash_hex\":\"{}\",\"joint_zec_ufvk\":\"{}\"}}",
            mm.joint_zec_address, mm.btc_lock_address, mm.swap_hash_hex, mm.joint_zec_ufvk);
    }

    #[test]
    fn deterministic_and_mainnet_hrps() {
        let seed = [9u8; 32];
        let solver = synth_solver(&[5u8; 32], "swap-b2z-2");
        let a = derive_b2z_material(&seed, "swap-b2z-2", &solver, LockTimelocks { t1: 72, t2: 144 }, "mainnet").unwrap();
        let b = derive_b2z_material(&seed, "swap-b2z-2", &solver, LockTimelocks { t1: 72, t2: 144 }, "mainnet").unwrap();
        assert_eq!(a.btc_lock_address, b.btc_lock_address, "deterministic BTC lock");
        assert_eq!(a.joint_zec_address, b.joint_zec_address, "deterministic joint UA");
        assert!(a.btc_lock_address.starts_with("bc1q"), "mainnet BTC: {}", a.btc_lock_address);
        assert!(a.joint_zec_address.starts_with("u1"), "mainnet ZEC UA: {}", a.joint_zec_address);
    }
}
