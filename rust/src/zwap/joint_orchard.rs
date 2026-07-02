//! Joint 2-of-2 Orchard unified-address (UA) derivation — the ZEC deposit address both parties co-fund.
//! Ported VERBATIM from the audited `solverd-v2::wallet::joint_orchard` (keys only — NO halo2 prover, so no
//! OOM): joint `ak = canonical(ak_A + ak_B)`, `nk = nsk_A + nsk_B mod p`, per-party BLAKE2b `rivk` shares,
//! then `FullViewingKey → ivk → address_at(0)` and a unified-address encoding. Both parties run this with
//! the same exchanged public halves and get the byte-identical UA (matching the FE).
//!
//! The canonicalization (negate joint `ak` when its y is odd) is the SAME sign choice
//! [`crate::zwap::joint_keys::derive_joint_ask_secret`] makes on the reconstructed `ask`, so `ask·SpendAuthBase`
//! equals this `ak` — proven by the cross-module test. The actual 2-of-2 Orchard SPEND (note + halo2 proof)
//! is the separate prover-gated piece; this gives the fundable deposit UA.
//!
//! These are the ZEC-executor surface (the deposit/scan side); not yet called from the non-test binary
//! (the ZEC executor that drives a deposit needs the send daemon / prover), so `dead_code` is allowed at the
//! module level — mirroring `btc_claim`/`reactor::execute` before `LiveExecutor` wired them.
#![allow(dead_code)]

use blake2b_simd;
use ff::{Field, PrimeField};
use group::GroupEncoding;
use num_bigint::BigUint;
use num_traits::Num;
use orchard::keys::{FullViewingKey, Scope};
use orchard::primitives::redpallas::{self, SpendAuth, VerificationKey};
use orchard::Address;
use pasta_curves::arithmetic::{Coordinates, CurveAffine};
use pasta_curves::pallas;
use zcash_address::{
    unified::{self, Encoding, Receiver},
    ToAddress, ZcashAddress,
};
use zcash_keys::keys::UnifiedFullViewingKey;
use zcash_protocol::consensus::{BlockHeight, MainNetwork, NetworkType, TestNetwork};
use zcash_protocol::local_consensus::LocalNetwork;

const PALLAS_P_HEX: &str = "40000000000000000000000000000000224698fc094cf91b992d30ed00000001";
const PALLAS_Q_HEX: &str = "40000000000000000000000000000000224698fc0994a8dd8c46eb2100000001";
const RIVK_SHARE_DOMAIN: &[u8] = b"zwap-asmr/rivk-share/v1";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ZecNetwork {
    Mainnet,
    Testnet,
    Regtest,
}
impl ZecNetwork {
    fn network_type(&self) -> NetworkType {
        match self {
            ZecNetwork::Mainnet => NetworkType::Main,
            ZecNetwork::Testnet => NetworkType::Test,
            ZecNetwork::Regtest => NetworkType::Regtest,
        }
    }
}

fn pallas_p() -> BigUint {
    BigUint::from_str_radix(PALLAS_P_HEX, 16).unwrap()
}
fn pallas_q() -> BigUint {
    BigUint::from_str_radix(PALLAS_Q_HEX, 16).unwrap()
}
fn le32_from_biguint(value: &BigUint) -> [u8; 32] {
    let bytes = value.to_bytes_le();
    let mut out = [0u8; 32];
    let len = bytes.len().min(32);
    out[..len].copy_from_slice(&bytes[..len]);
    out
}

/// Decode a 33-byte SEC1-compressed Pallas point (validates on-curve).
pub fn pallas_point_from_sec1(bytes: &[u8]) -> Result<pallas::Point, String> {
    if bytes.len() != 33 {
        return Err("Pallas SEC1 point must be 33 bytes".into());
    }
    if bytes[0] != 0x02 && bytes[0] != 0x03 {
        return Err("Pallas SEC1 prefix must be 02/03".into());
    }
    let want_odd = bytes[0] == 0x03;
    let mut x_le = [0u8; 32];
    x_le.copy_from_slice(&bytes[1..]);
    x_le.reverse();
    let x = Option::<pallas::Base>::from(pallas::Base::from_repr(x_le)).ok_or("x not canonical")?;
    let rhs = x.square() * x + pallas::Base::from(5);
    let mut y = Option::<pallas::Base>::from(rhs.sqrt()).ok_or("x not on curve")?;
    if bool::from(y.is_odd()) != want_odd {
        y = -y;
    }
    let affine = Option::<pallas::Affine>::from(pallas::Affine::from_xy(x, y)).ok_or("invalid point")?;
    Ok(pallas::Point::from(affine))
}

/// Pallas BASE-field addition of two 32-byte LE values (mod p). Used for `nk = nsk_A + nsk_B`.
pub fn add_pallas_base_le(a: &[u8; 32], b: &[u8; 32]) -> [u8; 32] {
    let sum = (BigUint::from_bytes_le(a) + BigUint::from_bytes_le(b)) % pallas_p();
    le32_from_biguint(&sum)
}

/// Reduce a raw 32-byte value into the Pallas BASE field (mod p), returned LE — the canonical form for an
/// `nsk` share (which `add_pallas_base_le` / `derive_joint_orchard` consume LE). A raw KDF output may exceed p.
pub fn reduce_raw_to_base_le(raw: &[u8; 32]) -> [u8; 32] {
    le32_from_biguint(&(BigUint::from_bytes_be(raw) % pallas_p()))
}

/// The Orchard SpendAuthSig basepoint (Zcash NU5 constant) — `k · SpendAuthBase` is a party's public `ak` half.
pub const SPENDAUTH_BASEPOINT_BYTES: [u8; 32] = [
    99, 201, 117, 184, 132, 114, 26, 141, 12, 161, 112, 123, 227, 12, 127, 12, 95, 68, 95, 62, 124, 24, 141,
    59, 6, 214, 241, 40, 179, 35, 85, 183,
];

fn spendauth_basepoint() -> pallas::Point {
    use group::prime::PrimeCurveAffine;
    pallas::Affine::from_bytes(&SPENDAUTH_BASEPOINT_BYTES).unwrap().to_curve()
}

/// SEC1-compressed (33 bytes): `0x02/0x03` (y parity) ‖ x big-endian. The inverse of `pallas_point_from_sec1`;
/// matches the TS `pointToSec1`. The wire form of a party's public `ak` half.
pub fn point_to_sec1(point: &pallas::Point) -> [u8; 33] {
    use group::Curve;
    let affine = point.to_affine();
    let coords = Option::<Coordinates<pallas::Affine>>::from(affine.coordinates()).unwrap();
    let mut out = [0u8; 33];
    out[0] = if bool::from(coords.y().is_odd()) { 0x03 } else { 0x02 };
    let mut x_be = coords.x().to_repr();
    x_be.reverse();
    out[1..].copy_from_slice(&x_be);
    out
}

/// A party's public Orchard `ak` half = `k · SpendAuthBase`, SEC1-compressed. `k_be` is the BIG-ENDIAN
/// spend-auth scalar (the same `k` committed on-chain as `SHA256(k)`); it MUST be in the scalar field
/// (`solver_keys::reduce_be_mod_pallas_q` guarantees this). The joint UA's `ak` is the canonical sum
/// `canonical(ak_A + ak_B)` — `derive_joint_orchard` does the canonicalization, so this returns the raw half.
pub fn spendauth_pubkey_sec1(k_be: &[u8; 32]) -> Result<[u8; 33], String> {
    let mut le = *k_be;
    le.reverse();
    let scalar = Option::<pallas::Scalar>::from(pallas::Scalar::from_repr(le))
        .ok_or("k not in pallas scalar field (must be reduced)")?;
    Ok(point_to_sec1(&(spendauth_basepoint() * scalar)))
}

/// One party's `rivk` share: `BLAKE2b-256([len]‖DOMAIN‖sec1(ak)‖nsk_le)`.
pub fn rivk_share(ak_sec1: &[u8; 33], nsk_le: &[u8; 32]) -> [u8; 32] {
    let mut state = blake2b_simd::Params::new().hash_length(32).to_state();
    state.update(&[RIVK_SHARE_DOMAIN.len() as u8]);
    state.update(RIVK_SHARE_DOMAIN);
    state.update(ak_sec1);
    state.update(nsk_le);
    let mut buf = [0u8; 32];
    buf.copy_from_slice(state.finalize().as_bytes());
    buf
}

/// Joint `rivk` = `(rivk_A XOR rivk_B) mod q`.
pub fn combine_rivk_shares(rivk_a: &[u8; 32], rivk_b: &[u8; 32]) -> [u8; 32] {
    let mut xor = [0u8; 32];
    for i in 0..32 {
        xor[i] = rivk_a[i] ^ rivk_b[i];
    }
    le32_from_biguint(&(BigUint::from_bytes_le(&xor) % pallas_q()))
}

/// The derived joint Orchard receiver + its unified-address encoding.
#[derive(Clone, Debug)]
pub struct JointOrchardDerivation {
    pub raw_address: [u8; 43],
    pub ivk: [u8; 32],
    pub diversifier: [u8; 11],
    pub ak: [u8; 32],
    pub nk: [u8; 32],
    /// Joint `rivk` (randomized commitment-IVK scalar). Together with `(ak, nk)` this is the FULL viewing key
    /// material indexerd needs to compile a `FullViewingKey` and trial-decrypt deposits to the joint UA
    /// (`orchard_scan::Watcher::from_subscription` builds `FVK(ak‖nk‖rivk)`). The watch subscription carries it.
    pub rivk: [u8; 32],
    pub deposit_address: String,
    /// `uviewregtest1…` / `uview1…` encoded joint UFVK — what `zec-batcherd` `TrackAccount` registers so it
    /// view-only trial-decrypts deposits to the joint UA. MUST embed the SAME real joint rivk as the address.
    pub joint_ufvk_encoded: String,
}

/// Encode the joint Orchard UFVK (`uview…`) DIRECTLY from the already-combined joint `(ak, nk, rivk)` — the
/// material the FE derives + verifies and hands to the user-signer. Byte-identical to the `joint_ufvk_encoded`
/// that `derive_joint_orchard` produces from the two halves (same FVK bytes → same UFVK), so the user-signer is
/// self-sufficient: it never needs the OB to persist+relay the UFVK string. `ak/nk/rivk` are 32-byte each.
pub fn encode_joint_ufvk(ak: &[u8; 32], nk: &[u8; 32], rivk: &[u8; 32], network: ZecNetwork) -> Result<String, String> {
    let mut fvk_bytes = [0u8; 96];
    fvk_bytes[..32].copy_from_slice(ak);
    fvk_bytes[32..64].copy_from_slice(nk);
    fvk_bytes[64..].copy_from_slice(rivk);
    let fvk = FullViewingKey::from_bytes(&fvk_bytes).ok_or("invalid joint Orchard FVK components")?;
    let ufvk = UnifiedFullViewingKey::from_orchard_fvk(fvk).map_err(|e| format!("build UFVK: {e:?}"))?;
    Ok(encode_ufvk_for_network(&ufvk, network))
}

/// Derive the joint Orchard receiver from two parties' public halves `(sec1(ak_i), nsk_i)`.
pub fn derive_joint_orchard(
    initiator_pallas_sec1: &[u8; 33],
    responder_pallas_sec1: &[u8; 33],
    initiator_nsk: &[u8; 32],
    responder_nsk: &[u8; 32],
    network: ZecNetwork,
) -> Result<JointOrchardDerivation, String> {
    let ak_a = pallas_point_from_sec1(initiator_pallas_sec1)?;
    let ak_b = pallas_point_from_sec1(responder_pallas_sec1)?;

    // Canonicalize: if y(joint_ak) is odd, negate (mirrors orchard's ỹ(ak)=0 + joint_keys' ask flip).
    let mut joint_ak = ak_a + ak_b;
    let affine = pallas::Affine::from(joint_ak);
    let coords = Option::<Coordinates<pallas::Affine>>::from(affine.coordinates()).ok_or("joint ak identity")?;
    if bool::from(coords.y().is_odd()) {
        joint_ak = -joint_ak;
    }
    let ak = pallas::Affine::from(joint_ak).to_bytes();

    let nk = add_pallas_base_le(initiator_nsk, responder_nsk);
    let rivk = combine_rivk_shares(
        &rivk_share(initiator_pallas_sec1, initiator_nsk),
        &rivk_share(responder_pallas_sec1, responder_nsk),
    );

    // FullViewingKey(ak‖nk‖rivk) → ivk → address_at(0).
    let mut fvk_bytes = [0u8; 96];
    fvk_bytes[..32].copy_from_slice(&ak);
    fvk_bytes[32..64].copy_from_slice(&nk);
    fvk_bytes[64..].copy_from_slice(&rivk);
    let fvk = FullViewingKey::from_bytes(&fvk_bytes).ok_or("invalid joint Orchard FVK components")?;
    let ivk_full = fvk.to_ivk(Scope::External).to_bytes();
    let mut ivk = [0u8; 32];
    ivk.copy_from_slice(&ivk_full[32..]);

    let address: Address = fvk.address_at(0u32, Scope::External);
    let raw_address = address.to_raw_address_bytes();
    let mut diversifier = [0u8; 11];
    diversifier.copy_from_slice(&raw_address[..11]);

    let deposit_address = encode_unified_orchard_address(network, &raw_address)?;

    // Joint UFVK (Orchard-only) — what zec-batcherd TrackAccount registers to scan the joint UA. Embeds the
    // SAME ak‖nk‖rivk as the address above (a different/zero rivk would scan a different UA).
    let orchard_fvk = FullViewingKey::from_bytes(&fvk_bytes).ok_or("joint Orchard FVK (ufvk)")?;
    let ufvk = UnifiedFullViewingKey::from_orchard_fvk(orchard_fvk).map_err(|e| format!("build UFVK: {e:?}"))?;
    let joint_ufvk_encoded = encode_ufvk_for_network(&ufvk, network);

    Ok(JointOrchardDerivation { raw_address, ivk, diversifier, ak, nk, rivk, deposit_address, joint_ufvk_encoded })
}

/// Encode a `UnifiedFullViewingKey` for the network (`uview…`/`uviewtest…`/`uviewregtest…`). Regtest uses a
/// `LocalNetwork` with every upgrade through NU6.2 active at block 1 (matches zec-batcher's regtest params).
fn encode_ufvk_for_network(ufvk: &UnifiedFullViewingKey, network: ZecNetwork) -> String {
    match network {
        ZecNetwork::Mainnet => ufvk.encode(&MainNetwork),
        ZecNetwork::Testnet => ufvk.encode(&TestNetwork),
        ZecNetwork::Regtest => {
            let h = |n: u32| Some(BlockHeight::from_u32(n));
            let regtest = LocalNetwork {
                overwinter: h(1),
                sapling: h(1),
                blossom: h(1),
                heartwood: h(1),
                canopy: h(1),
                nu5: h(1),
                nu6: h(1),
                nu6_1: h(1),
                nu6_2: h(1),
            };
            ufvk.encode(&regtest)
        }
    }
}

/// Encode a 43-byte raw Orchard receiver as a `u…`/`uregtest1…` unified address.
pub fn encode_unified_orchard_address(network: ZecNetwork, raw_address: &[u8; 43]) -> Result<String, String> {
    let receiver = Receiver::Orchard(*raw_address);
    let ua = unified::Address::try_from_items(vec![receiver]).map_err(|e| format!("UA: {e:?}"))?;
    Ok(ZcashAddress::from_unified(network.network_type(), ua).encode())
}

#[allow(dead_code)]
fn redpallas_vk_bytes(sk: &redpallas::SigningKey<SpendAuth>) -> [u8; 32] {
    (&VerificationKey::<SpendAuth>::from(sk)).into()
}

#[cfg(test)]
mod tests {
    use super::*;
    use group::{Curve, GroupEncoding};

    // Orchard SpendAuthSig basepoint (Zcash NU5) — same const as joint_keys.
    const SPENDAUTH_BASEPOINT: [u8; 32] = [
        99, 201, 117, 184, 132, 114, 26, 141, 12, 161, 112, 123, 227, 12, 127, 12, 95, 68, 95, 62, 124, 24,
        141, 59, 6, 214, 241, 40, 179, 35, 85, 183,
    ];
    fn basepoint() -> pallas::Point {
        use group::prime::PrimeCurveAffine;
        pallas::Affine::from_bytes(&SPENDAUTH_BASEPOINT).unwrap().to_curve()
    }
    fn sec1(point: &pallas::Point) -> [u8; 33] {
        let affine = point.to_affine();
        let coords = Option::<Coordinates<pallas::Affine>>::from(affine.coordinates()).unwrap();
        let mut out = [0u8; 33];
        out[0] = if bool::from(coords.y().is_odd()) { 0x03 } else { 0x02 };
        let mut x_be = coords.x().to_repr();
        x_be.reverse();
        out[1..].copy_from_slice(&x_be);
        out
    }
    fn scalar(seed: u64) -> pallas::Scalar {
        pallas::Scalar::from(seed) + pallas::Scalar::from(0x9e37_79b9_7f4a_7c15u64)
    }
    fn nsk(seed: u64) -> [u8; 32] {
        (pallas::Base::from(seed) + pallas::Base::from(7)).to_repr()
    }

    #[test]
    #[ignore = "utility: print a distinct joint UA + its ivk:diversifier watch-key for the live e2e drive"]
    fn print_distinct_joint_ua() {
        // SCALARS env (a,b) varies the UA so each drive uses a fresh, un-collided recipient.
        let (sa, sb) = std::env::var("SCALARS")
            .ok()
            .and_then(|s| {
                let p: Vec<u64> = s.split(',').filter_map(|x| x.parse().ok()).collect();
                (p.len() == 2).then(|| (p[0], p[1]))
            })
            .unwrap_or((77, 88));
        let (ak_a, ak_b) = (basepoint() * scalar(sa), basepoint() * scalar(sb));
        let d = derive_joint_orchard(&sec1(&ak_a), &sec1(&ak_b), &nsk(sa), &nsk(sb), ZecNetwork::Regtest).unwrap();
        println!("DISTINCT_JOINT_UA={}", d.deposit_address);
        // Full FVK watch material — indexerd needs (ivk, diversifier, ak, nk, rivk) to trial-decrypt. The OB
        // zec watch_target carries all five, colon-joined, so the watcher subscribes the real joint viewing key.
        println!(
            "JOINT_WATCH_KEY={}:{}:{}:{}:{}",
            hex::encode(d.ivk),
            hex::encode(d.diversifier),
            hex::encode(d.ak),
            hex::encode(d.nk),
            hex::encode(d.rivk)
        );
    }

    #[test]
    fn joint_ua_is_valid_regtest_unified_and_deterministic() {
        let (ask_a, ask_b) = (scalar(11), scalar(22));
        let (ak_a, ak_b) = (basepoint() * ask_a, basepoint() * ask_b);
        let d1 = derive_joint_orchard(&sec1(&ak_a), &sec1(&ak_b), &nsk(1), &nsk(2), ZecNetwork::Regtest).unwrap();
        // valid unified regtest address that re-parses to an Orchard receiver
        assert!(d1.deposit_address.starts_with("uregtest1"), "addr: {}", d1.deposit_address);
        let (net, ua) = unified::Address::decode(&d1.deposit_address).unwrap();
        assert_eq!(net, NetworkType::Regtest);
        assert!(ua.contains_receiver(&Receiver::Orchard(d1.raw_address)), "UA holds the joint Orchard receiver");
        // deterministic: same inputs → same UA (both peers derive identically)
        let d2 = derive_joint_orchard(&sec1(&ak_a), &sec1(&ak_b), &nsk(1), &nsk(2), ZecNetwork::Regtest).unwrap();
        assert_eq!(d1.deposit_address, d2.deposit_address);
        assert_eq!(d1.raw_address, d2.raw_address);
        // different parties → different UA
        let d3 = derive_joint_orchard(&sec1(&ak_a), &sec1(&(basepoint() * scalar(99))), &nsk(1), &nsk(2), ZecNetwork::Regtest).unwrap();
        assert_ne!(d1.deposit_address, d3.deposit_address);
    }

    /// THE cross-module link: the joint `ak` this derives == `derive_joint_ask_secret(ask_a, ask_b)·B`.
    /// I.e. the spend authority [`crate::joint_keys`] reconstructs is exactly the key behind this deposit UA
    /// — the property that makes the cross-chain swap atomic (BTC/EVM reveal a k → this UA becomes spendable).
    #[test]
    fn joint_ak_matches_reconstructed_spend_authority() {
        let b = basepoint();
        for i in 1..20u64 {
            let ask_a = scalar(i);
            let ask_b = scalar(i.wrapping_mul(2654435761));
            let d = derive_joint_orchard(&sec1(&(b * ask_a)), &sec1(&(b * ask_b)), &nsk(i), &nsk(i + 1), ZecNetwork::Regtest).unwrap();

            let mut a_be = ask_a.to_repr();
            a_be.reverse();
            let mut bb_be = ask_b.to_repr();
            bb_be.reverse();
            let joint_ask_be = crate::zwap::joint_keys::derive_joint_ask_secret(&a_be, &bb_be).unwrap();
            let mut joint_ask_le = joint_ask_be;
            joint_ask_le.reverse();
            let joint_ask = pallas::Scalar::from_repr(joint_ask_le).unwrap();
            // VK(joint_ask) compressed bytes == the derived joint ak
            assert_eq!((b * joint_ask).to_affine().to_bytes(), d.ak, "ask·B must equal the deposit UA's ak (pair {i})");
        }
    }
}