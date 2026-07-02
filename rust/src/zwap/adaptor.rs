use anyhow::{Context, Result, anyhow, bail, ensure};
use k256::elliptic_curve::Group as _;
use k256::elliptic_curve::ff::PrimeField;
use k256::elliptic_curve::sec1::{FromEncodedPoint, ToEncodedPoint};
use k256::{AffinePoint, EncodedPoint, ProjectivePoint, Scalar};
use num_bigint::BigUint;
use num_traits::{Num, Zero};
use rand_core::{OsRng, RngCore};

use secp256k1::{PublicKey, Secp256k1, SecretKey};
use sha2::{Digest, Sha256};

/// SHA-256 of `data` (local; the reference pulls this from `super::secp`).
pub fn sha256_bytes(data: &[u8]) -> [u8; 32] {
    let d = Sha256::digest(data);
    let mut out = [0u8; 32];
    out.copy_from_slice(&d);
    out
}

/// Compressed SEC1 secp256k1 public key for a 32-byte BE secret. Used to
/// candidate-select the recovered scalar in [`recover_scalar`].
pub fn public_key_from_secret(secret_be: &[u8; 32]) -> anyhow::Result<[u8; 33]> {
    let secp = Secp256k1::new();
    let sk = SecretKey::from_slice(secret_be)
        .map_err(|e| anyhow!("invalid secp256k1 secret key: {e}"))?;
    Ok(PublicKey::from_secret_key(&secp, &sk).serialize())
}

/// Low-S normalized compact (r‖s) ECDSA signature over `message_hash`. The
/// Pallas DLEq binds its secp witness with this. (Ported from `secp.rs`.)
pub fn sign_ecdsa_compact(
    secret_be: &[u8; 32],
    message_hash: &[u8; 32],
) -> anyhow::Result<[u8; 64]> {
    use secp256k1::Message;
    let secp = Secp256k1::new();
    let sk = SecretKey::from_slice(secret_be)
        .map_err(|e| anyhow!("invalid secp256k1 signing key: {e}"))?;
    let msg = Message::from_digest_slice(message_hash)
        .map_err(|e| anyhow!("invalid secp256k1 message: {e}"))?;
    let mut sig = secp.sign_ecdsa(&msg, &sk);
    sig.normalize_s();
    Ok(sig.serialize_compact())
}

/// Verify a compact (r‖s) ECDSA signature over `message_hash` for `public_key`.
pub fn verify_ecdsa_compact(
    signature: &[u8],
    message_hash: &[u8; 32],
    public_key: &[u8],
) -> anyhow::Result<bool> {
    use secp256k1::{ecdsa::Signature, Message};
    if signature.len() != 64 {
        return Ok(false);
    }
    let secp = Secp256k1::verification_only();
    let sig = Signature::from_compact(signature)
        .map_err(|e| anyhow!("invalid compact ECDSA signature: {e}"))?;
    let msg = Message::from_digest_slice(message_hash)
        .map_err(|e| anyhow!("invalid secp256k1 message: {e}"))?;
    let pk = PublicKey::from_slice(public_key)
        .map_err(|e| anyhow!("invalid secp256k1 public key: {e}"))?;
    Ok(secp.verify_ecdsa(&msg, &sig, &pk).is_ok())
}

const DOMAIN_NONCE_DLEQ: &[u8] = b"zwap-asmr/adaptor-nonce-dleq/v1";
const SECP256K1_ORDER_HEX: &str =
    "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141";
const SECP256K1_H_SEED: &str = "zwap-asmr-H_s-v1";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AdaptorSignature {
    pub encrypted_nonce: [u8; 33],
    pub offset_nonce: [u8; 33],
    pub encrypted_s: [u8; 32],
    pub nonce_dleq_proof: [u8; 64],
}

pub fn sign(
    signing_key: &[u8; 32],
    encryption_point: &[u8; 33],
    message_hash: &[u8; 32],
) -> Result<AdaptorSignature> {
    let x = bigint_from_be(signing_key);
    ensure!(
        !x.is_zero() && x < secp_order(),
        "invalid adaptor signing scalar"
    );
    let y_point = point_from_sec1(encryption_point).context("invalid adaptor encryption point")?;

    let r = random_scalar_biguint();
    let r_scalar = scalar_from_biguint(&r)?;
    let r_inv = mod_inv(&r, &secp_order())?;

    let r_encrypted = y_point * r_scalar;
    let r_offset = ProjectivePoint::GENERATOR * r_scalar;
    let encrypted_nonce = point_to_sec1(&r_encrypted)?;
    let offset_nonce = point_to_sec1(&r_offset)?;
    let nonce_dleq_proof = prove_same_nonce(&r, &y_point, &r_encrypted, &r_offset, message_hash)?;

    let r_x = point_x_mod_n(&r_encrypted)?;
    let m = bigint_from_be(message_hash) % secp_order();
    let s_tilde = (&r_inv * ((m + (r_x * x)) % secp_order())) % secp_order();

    Ok(AdaptorSignature {
        encrypted_nonce,
        offset_nonce,
        encrypted_s: be32_from_biguint(&s_tilde),
        nonce_dleq_proof,
    })
}

pub fn verify(
    public_key: &[u8; 33],
    encryption_point: &[u8; 33],
    adaptor_sig: &AdaptorSignature,
    message_hash: &[u8; 32],
) -> bool {
    verify_inner(public_key, encryption_point, adaptor_sig, message_hash).unwrap_or(false)
}

fn verify_inner(
    public_key: &[u8; 33],
    encryption_point: &[u8; 33],
    adaptor_sig: &AdaptorSignature,
    message_hash: &[u8; 32],
) -> Result<bool> {
    let x_point = point_from_sec1(public_key).context("invalid adaptor public key")?;
    let y_point = point_from_sec1(encryption_point).context("invalid adaptor encryption point")?;
    let r_encrypted =
        point_from_sec1(&adaptor_sig.encrypted_nonce).context("invalid encrypted nonce")?;
    let r_offset = point_from_sec1(&adaptor_sig.offset_nonce).context("invalid offset nonce")?;
    let s_tilde = bigint_from_be(&adaptor_sig.encrypted_s);
    if s_tilde.is_zero() || s_tilde >= secp_order() {
        return Ok(false);
    }

    if !verify_same_nonce(
        &y_point,
        &r_encrypted,
        &r_offset,
        message_hash,
        &adaptor_sig.nonce_dleq_proof,
    )? {
        return Ok(false);
    }

    let s_inv = mod_inv(&s_tilde, &secp_order())?;
    let r_x = point_x_mod_n(&r_encrypted)?;
    let m = bigint_from_be(message_hash) % secp_order();
    let u1 = (&s_inv * m) % secp_order();
    let u2 = (&s_inv * r_x) % secp_order();
    let expected = (ProjectivePoint::GENERATOR * scalar_from_biguint(&u1)?)
        + (x_point * scalar_from_biguint(&u2)?);

    Ok(projective_eq(&expected, &r_offset))
}

pub fn serialize(sig: &AdaptorSignature) -> Vec<u8> {
    let mut out = Vec::with_capacity(1 + 33 + 1 + 33 + 1 + 32 + 1 + 64);
    out.push(33);
    out.extend_from_slice(&sig.encrypted_nonce);
    out.push(33);
    out.extend_from_slice(&sig.offset_nonce);
    out.push(32);
    out.extend_from_slice(&sig.encrypted_s);
    out.push(64);
    out.extend_from_slice(&sig.nonce_dleq_proof);
    out
}

pub fn deserialize(data: &[u8]) -> Result<AdaptorSignature> {
    let mut offset = 0usize;
    let encrypted_nonce = read_len_array::<33>(data, &mut offset, "encryptedNonce")?;
    let offset_nonce = read_len_array::<33>(data, &mut offset, "offsetNonce")?;
    let encrypted_s = read_len_array::<32>(data, &mut offset, "encryptedS")?;
    let nonce_dleq_proof = read_len_array::<64>(data, &mut offset, "nonceDleqProof")?;
    ensure!(offset == data.len(), "trailing bytes in adaptor signature");
    Ok(AdaptorSignature {
        encrypted_nonce,
        offset_nonce,
        encrypted_s,
        nonce_dleq_proof,
    })
}

/// Recover the encryption scalar `y` (the buy-tx adaptor secret, equivalent
/// to Bob's `k_b`) given the original adaptor sig and the decrypted ECDSA
/// sig that landed on chain. Inverts the relationship `s_real = s_tilde / y`
/// in `decrypt()`. ECDSA's `s` malleability means the recovered scalar may
/// be either `y` or `-y mod n`; both are returned and the caller picks the
/// one that produces the expected pubkey via `secp::public_key_from_secret`.
pub fn recover_scalar(
    adaptor_sig: &AdaptorSignature,
    decrypted_sig_compact: &[u8; 64],
) -> Result<[[u8; 32]; 2]> {
    let order = secp_order();
    let s_tilde = bigint_from_be(&adaptor_sig.encrypted_s);
    let s_real = bigint_from_be(&decrypted_sig_compact[32..]);
    ensure!(
        !s_tilde.is_zero() && s_tilde < order,
        "invalid s_tilde for recover"
    );
    ensure!(
        !s_real.is_zero() && s_real < order,
        "invalid s_real for recover"
    );
    let s_real_inv = mod_inv(&s_real, &order)?;
    let y_candidate = (&s_tilde * s_real_inv) % &order;
    let y_neg = mod_neg(&y_candidate, &order);
    Ok([be32_from_biguint(&y_candidate), be32_from_biguint(&y_neg)])
}

pub fn decrypt(
    adaptor_sig: &AdaptorSignature,
    decryption_key: &[u8; 32],
) -> Result<[u8; 64]> {
    let order = secp_order();
    let s_tilde = bigint_from_be(&adaptor_sig.encrypted_s);
    ensure!(
        !s_tilde.is_zero() && s_tilde < order,
        "invalid encrypted adaptor s scalar"
    );
    let y = bigint_from_be(decryption_key);
    ensure!(
        !y.is_zero() && y < order,
        "invalid adaptor decryption scalar"
    );

    let y_inv = mod_inv(&y, &order)?;
    let mut s = (&s_tilde * y_inv) % &order;
    let half_order = &order >> 1usize;
    if s > half_order {
        s = mod_neg(&s, &order);
    }

    let encrypted_nonce =
        point_from_sec1(&adaptor_sig.encrypted_nonce).context("invalid encrypted nonce")?;
    let r = point_x_mod_n(&encrypted_nonce)?;

    let mut compact = [0u8; 64];
    compact[..32].copy_from_slice(&be32_from_biguint(&r));
    compact[32..].copy_from_slice(&be32_from_biguint(&s));
    Ok(compact)
}

fn read_len_array<const N: usize>(data: &[u8], offset: &mut usize, label: &str) -> Result<[u8; N]> {
    ensure!(*offset < data.len(), "missing {label} length");
    let len = data[*offset] as usize;
    *offset += 1;
    ensure!(len == N, "{label} length must be {N}, got {len}");
    ensure!(data.len() >= *offset + N, "truncated {label}");
    let mut out = [0u8; N];
    out.copy_from_slice(&data[*offset..*offset + N]);
    *offset += N;
    Ok(out)
}

fn prove_same_nonce(
    r: &BigUint,
    y_point: &ProjectivePoint,
    r_encrypted: &ProjectivePoint,
    r_offset: &ProjectivePoint,
    message_hash: &[u8; 32],
) -> Result<[u8; 64]> {
    let k = random_scalar_biguint();
    let k_scalar = scalar_from_biguint(&k)?;
    let a = ProjectivePoint::GENERATOR * k_scalar;
    let b = *y_point * k_scalar;
    let c = nonce_challenge(y_point, r_offset, r_encrypted, &a, &b, message_hash)?;
    let s = (k + (&c * r)) % secp_order();

    let mut proof = [0u8; 64];
    proof[..32].copy_from_slice(&be32_from_biguint(&c));
    proof[32..].copy_from_slice(&be32_from_biguint(&s));
    Ok(proof)
}

fn verify_same_nonce(
    y_point: &ProjectivePoint,
    r_encrypted: &ProjectivePoint,
    r_offset: &ProjectivePoint,
    message_hash: &[u8; 32],
    proof: &[u8; 64],
) -> Result<bool> {
    let c = bigint_from_be(&proof[..32]);
    let s = bigint_from_be(&proof[32..]);
    if c >= secp_order() || s >= secp_order() {
        return Ok(false);
    }
    let s_scalar = scalar_from_biguint(&s)?;
    let neg_c_scalar = scalar_from_biguint(&mod_neg(&c, &secp_order()))?;
    let a = (ProjectivePoint::GENERATOR * s_scalar) + (*r_offset * neg_c_scalar);
    let b = (*y_point * s_scalar) + (*r_encrypted * neg_c_scalar);
    let expected = nonce_challenge(y_point, r_offset, r_encrypted, &a, &b, message_hash)?;
    Ok(c == expected)
}

fn nonce_challenge(
    y_point: &ProjectivePoint,
    r_offset: &ProjectivePoint,
    r_encrypted: &ProjectivePoint,
    a: &ProjectivePoint,
    b: &ProjectivePoint,
    message_hash: &[u8; 32],
) -> Result<BigUint> {
    let mut transcript = Vec::with_capacity(DOMAIN_NONCE_DLEQ.len() + 33 * 5 + 32);
    transcript.extend_from_slice(DOMAIN_NONCE_DLEQ);
    transcript.extend_from_slice(&point_to_sec1(y_point)?);
    transcript.extend_from_slice(&point_to_sec1(r_offset)?);
    transcript.extend_from_slice(&point_to_sec1(r_encrypted)?);
    transcript.extend_from_slice(&point_to_sec1(a)?);
    transcript.extend_from_slice(&point_to_sec1(b)?);
    transcript.extend_from_slice(message_hash);
    Ok(bigint_from_be(&sha256_bytes(&transcript)) % secp_order())
}

pub fn get_hs_point() -> Result<ProjectivePoint> {
    for counter in 0..256u16 {
        let preimage = format!("{SECP256K1_H_SEED}:{counter}");
        let hash = sha256_bytes(preimage.as_bytes());
        let mut candidate = [0u8; 33];
        candidate[0] = 0x02;
        candidate[1..].copy_from_slice(&hash);
        if let Ok(point) = point_from_sec1(&candidate) {
            return Ok(point);
        }
    }
    bail!("failed to derive secp256k1 H_s point")
}

pub fn point_from_sec1(bytes: &[u8]) -> Result<ProjectivePoint> {
    let encoded =
        EncodedPoint::from_bytes(bytes).map_err(|e| anyhow!("invalid SEC1 point: {e}"))?;
    let affine = Option::<AffinePoint>::from(AffinePoint::from_encoded_point(&encoded))
        .ok_or_else(|| anyhow!("invalid secp256k1 point"))?;
    Ok(ProjectivePoint::from(affine))
}

pub fn point_to_sec1(point: &ProjectivePoint) -> Result<[u8; 33]> {
    ensure!(
        !bool::from(point.is_identity()),
        "cannot SEC1-encode point at infinity"
    );
    let affine = AffinePoint::from(*point);
    let encoded = affine.to_encoded_point(true);
    let bytes = encoded.as_bytes();
    bytes
        .try_into()
        .map_err(|_| anyhow!("unexpected SEC1 encoded length {}", bytes.len()))
}

pub fn point_x_mod_n(point: &ProjectivePoint) -> Result<BigUint> {
    let encoded = point_to_sec1(point)?;
    Ok(bigint_from_be(&encoded[1..]) % secp_order())
}

pub fn projective_eq(a: &ProjectivePoint, b: &ProjectivePoint) -> bool {
    AffinePoint::from(*a) == AffinePoint::from(*b)
}

pub fn scalar_from_biguint(value: &BigUint) -> Result<Scalar> {
    ensure!(value < &secp_order(), "secp256k1 scalar out of range");
    let bytes = be32_from_biguint(value);
    let scalar = Option::<Scalar>::from(Scalar::from_repr(bytes.into()))
        .ok_or_else(|| anyhow!("invalid secp256k1 scalar"))?;
    Ok(scalar)
}

pub fn random_scalar_biguint() -> BigUint {
    loop {
        let mut bytes = [0u8; 32];
        OsRng.fill_bytes(&mut bytes);
        let n = bigint_from_be(&bytes);
        if !n.is_zero() && n < secp_order() {
            return n;
        }
    }
}

pub fn secp_order() -> BigUint {
    BigUint::from_str_radix(SECP256K1_ORDER_HEX, 16).expect("valid secp order")
}

pub fn bigint_from_be(bytes: &[u8]) -> BigUint {
    BigUint::from_bytes_be(bytes)
}

pub fn be32_from_biguint(value: &BigUint) -> [u8; 32] {
    let bytes = value.to_bytes_be();
    let mut out = [0u8; 32];
    let start = bytes.len().saturating_sub(32);
    let slice = &bytes[start..];
    out[32 - slice.len()..].copy_from_slice(slice);
    out
}

pub fn mod_neg(value: &BigUint, modulus: &BigUint) -> BigUint {
    if value.is_zero() {
        BigUint::zero()
    } else {
        modulus - (value % modulus)
    }
}

pub fn mod_inv(value: &BigUint, modulus: &BigUint) -> Result<BigUint> {
    ensure!(!value.is_zero(), "zero has no modular inverse");
    Ok(value.modpow(&(modulus - BigUint::from(2u8)), modulus))
}

