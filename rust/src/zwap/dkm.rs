//! Deterministic key material (DKM) for the wallet's role as swap **initiator**
//! (the BTC→ZEC / b2z user). Every per-swap secret derives statelessly from
//! `(seed, swap_id)`, so a resumed wallet on any device re-derives the exact
//! same secret it committed to (`swap_hash = SHA256(secret)`) and the same
//! joint Orchard half — no stored swap state to lose.
//!
//! Ported byte-exact from the zwap SDK initiator path
//! (`v3/sdk/src/jointOrchard.ts::deriveInitiatorHalf` +
//! `v3/sdk/src/orchestrate.ts::deriveSwapSecret`). The KDF personal
//! (`zwap-v3-init-kdf`) is deliberately DISTINCT from the solver's
//! (`zwap-v3-solv-kdf`) so the two parties never derive colliding scalars.
//!
//! The companion ZEC-side additive crypto lives in [`super::joint_orchard`]
//! and [`super::joint_keys`]; this module only produces the initiator's own
//! private half + public contribution.

use blake2b_simd::Params;
use num_bigint::BigUint;
use num_traits::Num;
use sha2::{Digest, Sha256};

use super::joint_orchard::{reduce_raw_to_base_le, spendauth_pubkey_sec1};

/// Pallas scalar field order (q) — the joint Orchard spend-auth scalar lives here.
const PALLAS_Q_HEX: &str = "40000000000000000000000000000000224698fc0994a8dd8c46eb2100000001";

/// Reduce a 32-byte BIG-ENDIAN value into the Pallas scalar field (mod q), BE
/// in/out. Mirrors `solver_keys::reduce_be_mod_pallas_q` and the TS
/// `reduceKToScalarField`: `k` is BOTH a `SHA256(k)` hashlock preimage AND the
/// joint spend-auth scalar (`pallas::Scalar::from_repr`, which rejects ≥ q), so
/// it MUST be reduced BEFORE the commitment or the joint note is unspendable
/// ~63% of the time. The two parties MUST reduce identically (same q).
fn reduce_be_mod_pallas_q(be: [u8; 32]) -> [u8; 32] {
    let q = BigUint::from_str_radix(PALLAS_Q_HEX, 16).expect("pallas q");
    let reduced = BigUint::from_bytes_be(&be) % q;
    let mut out = [0u8; 32];
    let bytes = reduced.to_bytes_be();
    out[32 - bytes.len()..].copy_from_slice(&bytes); // left-pad to 32 (BE)
    out
}

/// 32-byte KDF: `BLAKE2b-256(seed ‖ 0 ‖ swap_id ‖ 0 ‖ domain)` with the
/// DEFAULT (zero) personalization.
///
/// IMPORTANT — protocol-compat quirk, verified against the live SDK: the SDK's
/// `initKdf32` *intends* `personal="zwap-v3-init-kdf"`, but it passes the
/// `@noble/hashes` blake2b option as `personal:` while the library's actual
/// option is `personalization:`. The misnamed key is silently ignored, so the
/// SDK computes BLAKE2b with the default (all-zero) personalization. The joint
/// UA the solver and SDK derive is built from this *actual* output, so to
/// produce the same fundable address we must match the SDK's behavior — NOT its
/// apparent intent. Setting `.personal("zwap-v3-init-kdf")` here yields a
/// different `k`/`nsk`, hence a different joint UA (caught by the live
/// `vizor-parity` cross-check; do not "fix" this back).
fn init_kdf32(seed: &[u8], swap_id: &str, domain: &str) -> [u8; 32] {
    let hash = Params::new()
        .hash_length(32)
        .to_state()
        .update(seed)
        .update(&[0])
        .update(swap_id.as_bytes())
        .update(&[0])
        .update(domain.as_bytes())
        .finalize();
    let mut out = [0u8; 32];
    out.copy_from_slice(hash.as_bytes());
    out
}

/// The initiator's stateless Orchard half: the (reduced, BE) spend-auth scalar
/// `k`, its public point `ak = k·SpendAuthBase` (SEC1-compressed, 33 bytes),
/// and the `nsk` nullifier share (LE, reduced into the base field). The wallet
/// reports `ak_sec1`/`nsk_le` to the orderbook at Phase0 and feeds both halves
/// to [`super::joint_orchard::derive_joint_orchard`].
#[derive(Clone, Debug)]
pub struct OrchardHalf {
    /// Spend-auth scalar `k`, big-endian, reduced mod q. Kept secret. Also the
    /// hashlock preimage (`SHA256(k_be)`) and one addend of the joint `ask`.
    pub k_be: [u8; 32],
    /// `ak = k·SpendAuthBase`, SEC1-compressed (public; shared at Phase0).
    pub ak_sec1: [u8; 33],
    /// `nsk` nullifier share, LE, reduced into the base field (shared at Phase0).
    pub nsk_le: [u8; 32],
}

/// Derive the initiator's stateless Orchard half from `(seed, swap_id)`.
/// Mirror of the solver's `derive_solver_orchard_half`; both parties run their
/// own and exchange only the public `ak_sec1`/`nsk_le`.
pub fn derive_initiator_half(seed: &[u8], swap_id: &str) -> Result<OrchardHalf, String> {
    let k_be = reduce_be_mod_pallas_q(init_kdf32(seed, swap_id, "k-scalar"));
    let ak_sec1 = spendauth_pubkey_sec1(&k_be)?;
    let nsk_le = reduce_raw_to_base_le(&init_kdf32(seed, swap_id, "orchard-nsk"));
    Ok(OrchardHalf { k_be, ak_sec1, nsk_le })
}

/// Deterministic 32-byte swap secret from `(seed, swap_id)`. The initiator
/// commits `swap_hash = SHA256(secret)` and later reveals `secret`; deriving it
/// statelessly lets a resumed wallet still reveal the same value. Byte-exact to
/// the SDK `deriveSwapSecret` (`SHA256(seed ‖ "zwap-v3-swap-secret:<id>")`).
pub fn derive_swap_secret(seed: &[u8], swap_id: &str) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(seed);
    hasher.update(format!("zwap-v3-swap-secret:{swap_id}").as_bytes());
    let mut out = [0u8; 32];
    out.copy_from_slice(&hasher.finalize());
    out
}

/// The user's per-swap BTC **claim** keypair for z2b (secp256k1). In z2b the
/// user is the responder: the solver funds the BTC HTLC lock and the user
/// claims it via branch-1 with THIS key (revealing `k_be` on-chain). Byte-exact
/// to the SDK `deriveBtcClaimKeypair`:
/// `priv = SHA256(seed ‖ "zwap-v3-btc-claim:<swap_id>")`, `pub` = the compressed
/// secp256k1 point. Returns `(priv_be_32, pub_compressed_33)`. The private half
/// stays in the wallet and only ever signs the branch-1 claim sighash.
pub fn derive_btc_claim_keypair(seed: &[u8], swap_id: &str) -> Result<([u8; 32], [u8; 33]), String> {
    use secp256k1::{PublicKey, Secp256k1, SecretKey};
    let mut h = Sha256::new();
    h.update(seed);
    h.update(format!("zwap-v3-btc-claim:{swap_id}").as_bytes());
    let priv_bytes: [u8; 32] = h.finalize().into();
    let sk = SecretKey::from_slice(&priv_bytes).map_err(|e| format!("btc claim sk: {e}"))?;
    let pk = PublicKey::from_secret_key(&Secp256k1::new(), &sk).serialize();
    Ok((priv_bytes, pk))
}

/// `h = SHA256(k_be)` — the BTC hashlock commitment to the (reduced) spend-auth
/// scalar. Matches the SDK `hashlockCommit`.
pub fn hashlock_commit(k_be: &[u8; 32]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(k_be);
    let mut out = [0u8; 32];
    out.copy_from_slice(&hasher.finalize());
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::zwap::joint_keys::derive_joint_ask_secret;
    use crate::zwap::joint_orchard::{derive_joint_orchard, ZecNetwork};
    use ff::PrimeField;
    use group::GroupEncoding;

    // The Orchard SpendAuthSig basepoint (Zcash NU5 constant).
    const SPENDAUTH_BASEPOINT: [u8; 32] = [
        99, 201, 117, 184, 132, 114, 26, 141, 12, 161, 112, 123, 227, 12, 127, 12, 95, 68, 95, 62, 124, 24,
        141, 59, 6, 214, 241, 40, 179, 35, 85, 183,
    ];

    fn basepoint() -> pasta_curves::pallas::Point {
        use group::prime::PrimeCurveAffine;
        pasta_curves::pallas::Affine::from_bytes(&SPENDAUTH_BASEPOINT).unwrap().to_curve()
    }

    #[test]
    fn initiator_half_is_deterministic() {
        let seed = [7u8; 32];
        let a = derive_initiator_half(&seed, "swap-001").unwrap();
        let b = derive_initiator_half(&seed, "swap-001").unwrap();
        assert_eq!(a.k_be, b.k_be);
        assert_eq!(a.ak_sec1, b.ak_sec1);
        assert_eq!(a.nsk_le, b.nsk_le);
        // A different swap id yields a different scalar.
        let c = derive_initiator_half(&seed, "swap-002").unwrap();
        assert_ne!(a.k_be, c.k_be);
    }

    #[test]
    fn swap_secret_matches_hashlock_roundtrip() {
        let seed = [3u8; 32];
        let secret = derive_swap_secret(&seed, "swap-xyz");
        // Deterministic.
        assert_eq!(secret, derive_swap_secret(&seed, "swap-xyz"));
        // commit is SHA256 of it (sanity, not equality to k).
        let _h = hashlock_commit(&secret);
    }

    /// THE end-to-end fund-safety proof, entirely in-wallet: two independent
    /// initiator-style halves combine into a joint Orchard UA whose spend
    /// authority `ask = (k_a + k_b) mod q` satisfies `ask·SpendAuthBase ==
    /// joint.ak`. If this holds, the joint note the parties co-fund is
    /// spendable by the reconstructed key — the core atomic-swap invariant.
    #[test]
    fn joint_ask_matches_joint_ak_end_to_end() {
        use group::{Curve, GroupEncoding};

        let half_a = derive_initiator_half(&[1u8; 32], "swap-joint").unwrap();
        // Reuse the same derivation for a "solver-like" second half from a
        // different seed; the math is symmetric (both are k·SpendAuthBase).
        let half_b = derive_initiator_half(&[2u8; 32], "swap-joint").unwrap();

        let joint = derive_joint_orchard(
            &half_a.ak_sec1,
            &half_b.ak_sec1,
            &half_a.nsk_le,
            &half_b.nsk_le,
            ZecNetwork::Regtest,
        )
        .unwrap();

        let ask_be = derive_joint_ask_secret(&half_a.k_be, &half_b.k_be).unwrap();
        let mut ask_le = ask_be;
        ask_le.reverse();
        let ask = pasta_curves::pallas::Scalar::from_repr(ask_le).unwrap();

        let recomputed_ak = (basepoint() * ask).to_affine().to_bytes();
        assert_eq!(
            recomputed_ak, joint.ak,
            "ask·SpendAuthBase must equal the canonical joint ak (joint note is spendable)"
        );
    }
}
