//! ZEC joint-key crypto bridge — the linchpin that makes the cross-chain swap ATOMIC.
//!
//! Both parties co-fund a joint 2-of-2 Orchard note whose spend authority is `ask = ask_A + ask_B`. Neither
//! can spend alone. When the BTC lock is claimed/refunded the counterparty's scalar (k_B / k_A) is revealed
//! on-chain (proven on a live chain in `btc_claim`); the other party then reconstructs the full joint `ask`
//! and sweeps the ZEC. [`derive_joint_ask_secret`] is that reconstruction — ported VERBATIM from the audited
//! `solverd-v2::wallet::joint_orchard::derive_joint_ask_secret`, using `reddsa` (the Orchard SpendAuth
//! RedDSA, what `orchard::primitives::redpallas` wraps) directly so we avoid the heavy `orchard`/halo2 tree.
//!
//! The canonicalization (negate `ask` when `ask·SpendAuthBase` has odd y) MUST match `derive_joint_orchard`,
//! which negates the joint `ak` the same way — else `ask·SpendAuthBase != ak` on ~50% of key pairs and the
//! spend is rejected. The test does the real cryptographic check: `ask·B == canonical(k_A·B + k_B·B)`.

use ff::{Field, PrimeField};
use pasta_curves::pallas;
use reddsa::orchard::SpendAuth;
use reddsa::{SigningKey, VerificationKey};

/// Reconstruct the joint Orchard spending scalar `ask = ask_A + ask_B (mod q)`, applying the same
/// y-parity-flip canonicalization (against the Orchard SpendAuth basepoint) that `derive_joint_orchard`
/// applies to the joint `ak`. Inputs + output are 32-byte BIG-ENDIAN (the protocol wire form, matching the
/// BE `k` revealed in the BTC witness). Errors if either scalar is out of field or the sum is zero.
pub fn derive_joint_ask_secret(k_a_be: &[u8; 32], k_b_be: &[u8; 32]) -> Result<[u8; 32], String> {
    let mut k_a_le = *k_a_be;
    k_a_le.reverse();
    let mut k_b_le = *k_b_be;
    k_b_le.reverse();
    let scalar_a = Option::<pallas::Scalar>::from(pallas::Scalar::from_repr(k_a_le))
        .ok_or("k_a not in pallas scalar field")?;
    let scalar_b = Option::<pallas::Scalar>::from(pallas::Scalar::from_repr(k_b_le))
        .ok_or("k_b not in pallas scalar field")?;
    let mut joint = scalar_a + scalar_b;
    if bool::from(joint.is_zero()) {
        return Err("joint ask is zero".into());
    }
    // Probe the SpendAuth verification key for `joint`: its compressed-encoding high bit (byte 31 MSB) is
    // the y-parity of `joint · SpendAuthBase` — exactly what `derive_joint_orchard` canonicalises against.
    let probe_sk = SigningKey::<SpendAuth>::try_from(joint.to_repr())
        .map_err(|_| "joint ask not a canonical SpendAuth signing key".to_string())?;
    let probe_vk_bytes: [u8; 32] = VerificationKey::<SpendAuth>::from(&probe_sk).into();
    if (probe_vk_bytes[31] >> 7) == 1 {
        joint = -joint;
    }
    let mut le_repr = joint.to_repr();
    le_repr.reverse();
    Ok(le_repr)
}

#[cfg(test)]
mod tests {
    use super::*;
    use group::prime::PrimeCurveAffine; // to_curve()
    use group::{Curve, GroupEncoding};

    // The Orchard SpendAuthSig basepoint (Zcash protocol constant, NU5 §pallasandvesta).
    const SPENDAUTH_BASEPOINT: [u8; 32] = [
        99, 201, 117, 184, 132, 114, 26, 141, 12, 161, 112, 123, 227, 12, 127, 12, 95, 68, 95, 62, 124, 24,
        141, 59, 6, 214, 241, 40, 179, 35, 85, 183,
    ];

    fn basepoint() -> pallas::Point {
        pallas::Affine::from_bytes(&SPENDAUTH_BASEPOINT).unwrap().to_curve()
    }

    fn be(s: &pallas::Scalar) -> [u8; 32] {
        let mut b = s.to_repr();
        b.reverse();
        b
    }

    // small deterministic pallas scalars (not 1-16-sensitive; just field elements)
    fn scalar(seed: u64) -> pallas::Scalar {
        pallas::Scalar::from(seed) + pallas::Scalar::from(0x9e37_79b9_7f4a_7c15u64)
    }

    /// THE cryptographic correctness check: the reconstructed `ask` is the discrete log of the canonicalized
    /// joint spend-auth key. `ask·B == canonical(k_A·B + k_B·B)`. Run over many pairs (both parities).
    #[test]
    fn reconstructs_canonical_joint_spend_auth_key() {
        let b = basepoint();
        for i in 1..50u64 {
            let sa = scalar(i);
            let sb = scalar(i.wrapping_mul(2654435761));
            // joint point + canonicalization (negate if y odd), mirroring derive_joint_orchard.
            let mut joint_pt = b * sa + b * sb;
            if (joint_pt.to_affine().to_bytes()[31] >> 7) == 1 {
                joint_pt = -joint_pt;
            }
            let ask_be = derive_joint_ask_secret(&be(&sa), &be(&sb)).expect("derive");
            let mut ask_le = ask_be;
            ask_le.reverse();
            let ask = pallas::Scalar::from_repr(ask_le).unwrap();
            assert_eq!(
                (b * ask).to_affine().to_bytes(),
                joint_pt.to_affine().to_bytes(),
                "ask·B must equal the canonical joint ak (pair {i})"
            );
            // and the canonical result always has even y-parity
            assert_eq!((b * ask).to_affine().to_bytes()[31] >> 7, 0, "canonical ak has even y");
        }
    }

    #[test]
    fn commutative_and_nonzero() {
        let (a, c) = (be(&scalar(7)), be(&scalar(99)));
        assert_eq!(derive_joint_ask_secret(&a, &c).unwrap(), derive_joint_ask_secret(&c, &a).unwrap());
    }

    #[test]
    fn rejects_zero_sum() {
        // k_b = -k_a → sum is zero → rejected (can't spend an identity key).
        let sa = scalar(123);
        let neg = -sa;
        assert!(derive_joint_ask_secret(&be(&sa), &be(&neg)).unwrap_err().contains("zero"));
    }

    #[test]
    fn rejects_out_of_field() {
        // all-0xFF BE is > the pallas scalar modulus → not in field.
        assert!(derive_joint_ask_secret(&[0xff; 32], &[0x01; 32]).is_err());
    }
}
