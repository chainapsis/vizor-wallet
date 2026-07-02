use anyhow::{Context, Result, anyhow, ensure};
use ff::{Field, PrimeField};
use group::{Group, GroupEncoding};
use k256::ProjectivePoint as SecpPoint;
use num_bigint::BigUint;
use num_traits::{Num, One, Zero};
use pasta_curves::{
    arithmetic::{CurveAffine, CurveExt},
    pallas,
};
use rand_core::{OsRng, RngCore};
use sha2::{Digest, Sha512};

use super::adaptor::{
    be32_from_biguint, bigint_from_be, get_hs_point, mod_inv, mod_neg, point_from_sec1,
    point_to_sec1, projective_eq, scalar_from_biguint, secp_order,
};
use super::adaptor::{sha256_bytes, sign_ecdsa_compact, verify_ecdsa_compact};

const N_BITS: usize = 251;
const PROOF_VERSION: u8 = 0x02;
const DOMAIN_RING: &[u8] = b"zwap-asmr/dleq/ring-challenge-pallas/v2";
const DOMAIN_SCHNORR_P: &[u8] = b"zwap-asmr/dleq/schnorr-p/v2";
const PALLAS_BLINDING_BASE_SEC1: [u8; 33] = [
    0x03, 0x3f, 0x3e, 0xe0, 0xd3, 0xdf, 0xc7, 0xef, 0xb8, 0xca, 0x48, 0xd6, 0x52, 0x58, 0x93, 0x65,
    0x21, 0xab, 0xdf, 0x19, 0xd0, 0xb9, 0x48, 0x7f, 0xdb, 0xb1, 0x5b, 0xab, 0x05, 0x65, 0x00, 0x42,
    0xf1,
];
const PALLAS_Q_HEX: &str = "40000000000000000000000000000000224698fc0994a8dd8c46eb2100000001";
const PALLAS_P_HEX: &str = "40000000000000000000000000000000224698fc094cf91b992d30ed00000001";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PallasDleqBitProof {
    pub commitment_secp: [u8; 33],
    pub commitment_pallas: [u8; 33],
    pub challenge: [u8; 32],
    pub sub_challenge0: [u8; 32],
    pub responses: [[u8; 32]; 4],
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PallasDleqProof {
    pub bit_proofs: Vec<PallasDleqBitProof>,
    pub signature_secp: [u8; 64],
    pub signature_pallas: [u8; 65],
    pub public_key_secp: [u8; 33],
    pub public_key_pallas: [u8; 33],
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VerifiedPallasDleqKeys {
    pub public_key_secp: [u8; 33],
    pub public_key_pallas: [u8; 33],
}

pub fn prove(k_be: &[u8; 32]) -> Result<PallasDleqProof> {
    let k = bigint_from_be(k_be);
    ensure!(
        !k.is_zero() && k < pallas_q(),
        "Pallas DLEq scalar must be in (0, q)"
    );

    let h_s = get_hs_point()?;
    let g_s = SecpPoint::GENERATOR;
    let g_p = spend_auth_g();
    let g_blind_p = pallas_blinding_base();

    let g_s_bytes = point_to_sec1(&g_s)?;
    let h_s_bytes = point_to_sec1(&h_s)?;
    let g_p_bytes = pallas_point_to_sec1(&g_p)?;
    let g_blind_p_bytes = pallas_point_to_sec1(&g_blind_p)?;

    let mut bits = Vec::with_capacity(N_BITS);
    for i in 0..N_BITS {
        bits.push(bit(&k, i));
    }

    let mut blinding_factors = Vec::<BigUint>::with_capacity(N_BITS);
    let mut sum_secp = BigUint::zero();
    let mut sum_pallas = BigUint::zero();
    let n_s = secp_order();
    let n_p = pallas_q();
    for i in 0..(N_BITS - 2) {
        let r_i = random_pallas_scalar_biguint();
        let two_i = BigUint::one() << i;
        sum_secp = (sum_secp + (&r_i * &two_i)) % &n_s;
        sum_pallas = (sum_pallas + (&r_i * &two_i)) % &n_p;
        blinding_factors.push(r_i);
    }

    let r_nm2 = random_pallas_scalar_biguint();
    let two_nm2 = BigUint::one() << (N_BITS - 2);
    let two_nm1 = BigUint::one() << (N_BITS - 1);
    sum_secp = (sum_secp + (&r_nm2 * &two_nm2)) % &n_s;
    sum_pallas = (sum_pallas + (&r_nm2 * &two_nm2)) % &n_p;
    blinding_factors.push(r_nm2);

    let two_nm1_inv_s = mod_inv(&two_nm1, &n_s)?;
    let two_nm1_inv_p = mod_inv(&two_nm1, &n_p)?;
    let r_nm1_mod_s = (mod_neg(&sum_secp, &n_s) * two_nm1_inv_s) % &n_s;
    let r_nm1_mod_p = (mod_neg(&sum_pallas, &n_p) * two_nm1_inv_p) % &n_p;
    let ns_inv_p = mod_inv(&(&n_s % &n_p), &n_p)?;
    let r_nm1_mod_s_mod_p = &r_nm1_mod_s % &n_p;
    let delta = if r_nm1_mod_p >= r_nm1_mod_s_mod_p {
        &r_nm1_mod_p - &r_nm1_mod_s_mod_p
    } else {
        &r_nm1_mod_p + &n_p - &r_nm1_mod_s_mod_p
    };
    let r_nm1 = &r_nm1_mod_s + &n_s * ((delta * ns_inv_p) % &n_p);
    ensure!(!r_nm1.is_zero(), "CRT blinding scalar unexpectedly zero");
    blinding_factors.push(r_nm1);

    let mut chk_s = BigUint::zero();
    let mut chk_p = BigUint::zero();
    for (i, r_i) in blinding_factors.iter().enumerate() {
        let two_i = BigUint::one() << i;
        chk_s = (chk_s + (r_i * &two_i)) % &n_s;
        chk_p = (chk_p + (r_i * &two_i)) % &n_p;
    }
    ensure!(chk_s.is_zero(), "CRT cancellation failed on secp");
    ensure!(chk_p.is_zero(), "CRT cancellation failed on Pallas");

    let k_secp = &k % &n_s;
    let k_secp_scalar = scalar_from_biguint(&k_secp)?;
    let k_pallas_scalar = pallas_scalar_from_biguint(&k)?;
    let k_s_point = g_s * k_secp_scalar;
    let k_p_point = g_p * k_pallas_scalar;
    let k_s_bytes = point_to_sec1(&k_s_point)?;
    let k_p_bytes = pallas_point_to_sec1(&k_p_point)?;

    let bases = vec![
        g_s_bytes.to_vec(),
        h_s_bytes.to_vec(),
        g_p_bytes.to_vec(),
        g_blind_p_bytes.to_vec(),
    ];
    let keys = vec![k_s_bytes.to_vec(), k_p_bytes.to_vec()];

    let mut bit_proofs = Vec::with_capacity(N_BITS);
    for i in 0..N_BITS {
        let b = bits[i];
        let r_i = &blinding_factors[i];
        let r_i_mod_s = r_i % &n_s;
        let r_i_mod_p = r_i % &n_p;
        let r_s_scalar = scalar_from_biguint(&r_i_mod_s)?;
        let r_p_scalar = pallas_scalar_from_biguint(&r_i_mod_p)?;

        let mut c_s = if r_i_mod_s.is_zero() {
            SecpPoint::IDENTITY
        } else {
            h_s * r_s_scalar
        };
        if b == 1 {
            c_s += g_s;
        }
        let mut c_p = if r_i_mod_p.is_zero() {
            pallas::Point::identity()
        } else {
            g_blind_p * r_p_scalar
        };
        if b == 1 {
            c_p += g_p;
        }
        ensure!(
            !bool::from(c_s.is_identity()),
            "identity secp commitment is unsupported"
        );
        ensure!(
            !bool::from(c_p.is_identity()),
            "identity Pallas commitment is unsupported"
        );

        let c_bar_s = c_s - g_s;
        let c_bar_p = c_p - g_p;
        let ring = prove_ring_bit_pallas(
            b, &r_i_mod_s, &r_i_mod_p, &c_s, &c_p, &c_bar_s, &c_bar_p, &h_s, &g_blind_p, &bases,
            &keys, i,
        )?;
        bit_proofs.push(PallasDleqBitProof {
            commitment_secp: point_to_sec1(&c_s)?,
            commitment_pallas: pallas_point_to_sec1(&c_p)?,
            challenge: be32_from_biguint(&ring.challenge),
            sub_challenge0: be32_from_biguint(&ring.sub_challenge0),
            responses: ring.responses,
        });
    }

    let k_s_hash = sha256_bytes(&k_s_bytes);
    let signature_secp = sign_ecdsa_compact(&be32_from_biguint(&k_secp), &k_s_hash)?;
    let k_p_hash = sha256_bytes(&k_p_bytes);
    let signature_pallas = sign_pallas_schnorr(&k, &k_p_bytes, &k_p_hash)?;

    Ok(PallasDleqProof {
        bit_proofs,
        signature_secp,
        signature_pallas,
        public_key_secp: k_s_bytes,
        public_key_pallas: k_p_bytes,
    })
}

pub fn verify(proof: &PallasDleqProof) -> Result<VerifiedPallasDleqKeys> {
    ensure!(
        proof.bit_proofs.len() == N_BITS,
        "Expected {N_BITS} bit proofs, got {}",
        proof.bit_proofs.len()
    );

    let k_s_hash = sha256_bytes(&proof.public_key_secp);
    ensure!(
        verify_ecdsa_compact(&proof.signature_secp, &k_s_hash, &proof.public_key_secp)?,
        "secp256k1 proof-of-knowledge signature invalid"
    );
    let k_p_hash = sha256_bytes(&proof.public_key_pallas);
    ensure!(
        verify_pallas_schnorr(&proof.public_key_pallas, &k_p_hash, &proof.signature_pallas)?,
        "Pallas proof-of-knowledge signature invalid"
    );

    let h_s = get_hs_point()?;
    let g_s = SecpPoint::GENERATOR;
    let g_p = spend_auth_g();
    let g_blind_p = pallas_blinding_base();
    let bases = vec![
        point_to_sec1(&g_s)?.to_vec(),
        point_to_sec1(&h_s)?.to_vec(),
        pallas_point_to_sec1(&g_p)?.to_vec(),
        pallas_point_to_sec1(&g_blind_p)?.to_vec(),
    ];
    let keys = vec![
        proof.public_key_secp.to_vec(),
        proof.public_key_pallas.to_vec(),
    ];

    let claimed_secp = point_from_sec1(&proof.public_key_secp)
        .context("invalid secp256k1 public key in DLEq proof")?;
    let claimed_pallas = pallas_point_from_sec1(&proof.public_key_pallas)
        .context("invalid Pallas public key in DLEq proof")?;
    let mut reconstructed_secp = SecpPoint::IDENTITY;
    let mut reconstructed_pallas = pallas::Point::identity();

    for (i, bit_proof) in proof.bit_proofs.iter().enumerate() {
        let c_s = point_from_sec1(&bit_proof.commitment_secp)
            .with_context(|| format!("invalid secp commitment for bit {i}"))?;
        let c_p = pallas_point_from_sec1(&bit_proof.commitment_pallas)
            .with_context(|| format!("invalid Pallas commitment for bit {i}"))?;
        let c_bar_s = c_s - g_s;
        let c_bar_p = c_p - g_p;
        ensure!(
            verify_ring_bit_pallas(
                &c_s, &c_p, &c_bar_s, &c_bar_p, &h_s, &g_blind_p, bit_proof, &bases, &keys, i
            )?,
            "Ring signature verification failed for bit {i}"
        );
        let two_i_s = (BigUint::one() << i) % secp_order();
        let two_i_p = (BigUint::one() << i) % pallas_q();
        reconstructed_secp += c_s * scalar_from_biguint(&two_i_s)?;
        reconstructed_pallas += c_p * pallas_scalar_from_biguint(&two_i_p)?;
    }

    ensure!(
        projective_eq(&reconstructed_secp, &claimed_secp),
        "Reconstructed secp256k1 key does not match claimed key"
    );
    ensure!(
        pallas_projective_eq(&reconstructed_pallas, &claimed_pallas),
        "Reconstructed Pallas key does not match claimed key"
    );

    Ok(VerifiedPallasDleqKeys {
        public_key_secp: proof.public_key_secp,
        public_key_pallas: proof.public_key_pallas,
    })
}

struct RingProofBig {
    challenge: BigUint,
    sub_challenge0: BigUint,
    responses: [[u8; 32]; 4],
}

#[allow(clippy::too_many_arguments)]
fn prove_ring_bit_pallas(
    bit: u8,
    r_i_mod_s: &BigUint,
    r_i_mod_p: &BigUint,
    c_s: &SecpPoint,
    c_p: &pallas::Point,
    c_bar_s: &SecpPoint,
    c_bar_p: &pallas::Point,
    h_s: &SecpPoint,
    g_blind_p: &pallas::Point,
    bases: &[Vec<u8>],
    keys: &[Vec<u8>],
    bit_index: usize,
) -> Result<RingProofBig> {
    let nonce_s = super::adaptor::random_scalar_biguint();
    let nonce_p = random_pallas_scalar_biguint();
    let r_real_s = *h_s * scalar_from_biguint(&nonce_s)?;
    let r_real_p = *g_blind_p * pallas_scalar_from_biguint(&nonce_p)?;

    let c_fake = super::adaptor::random_scalar_biguint();
    let s_fake_s = super::adaptor::random_scalar_biguint();
    let s_fake_p = random_pallas_scalar_biguint();

    let (fake_commit_s, fake_commit_p) = if bit == 0 {
        (c_bar_s, c_bar_p)
    } else {
        (c_s, c_p)
    };
    let r_fake_s = (*h_s * scalar_from_biguint(&s_fake_s)?)
        + (*fake_commit_s * scalar_from_biguint(&mod_neg(&c_fake, &secp_order()))?);
    let c_fake_p = &c_fake % pallas_q();
    let r_fake_p = (*g_blind_p * pallas_scalar_from_biguint(&s_fake_p)?)
        + (*fake_commit_p * pallas_scalar_from_biguint(&mod_neg(&c_fake_p, &pallas_q()))?);

    let (r0_s, r0_p, r1_s, r1_p) = if bit == 0 {
        (r_real_s, r_real_p, r_fake_s, r_fake_p)
    } else {
        (r_fake_s, r_fake_p, r_real_s, r_real_p)
    };

    let full_challenge = ring_challenge_pallas(
        bit_index,
        bases,
        keys,
        &[
            point_to_sec1(c_s)?.to_vec(),
            pallas_point_to_sec1(c_p)?.to_vec(),
            point_to_sec1(&r0_s)?.to_vec(),
            pallas_point_to_sec1(&r0_p)?.to_vec(),
            point_to_sec1(&r1_s)?.to_vec(),
            pallas_point_to_sec1(&r1_p)?.to_vec(),
        ],
    );

    let c_real = if full_challenge >= c_fake {
        &full_challenge - &c_fake
    } else {
        &full_challenge + secp_order() - &c_fake
    };
    let c_real = c_real % secp_order();
    let s_real_s = (nonce_s + (&c_real * r_i_mod_s)) % secp_order();
    let c_real_p = &c_real % pallas_q();
    let s_real_p = (nonce_p + (&c_real_p * r_i_mod_p)) % pallas_q();

    if bit == 0 {
        Ok(RingProofBig {
            challenge: full_challenge,
            sub_challenge0: c_real.clone(),
            responses: [
                be32_from_biguint(&s_real_s),
                le32_from_biguint(&s_real_p),
                be32_from_biguint(&s_fake_s),
                le32_from_biguint(&s_fake_p),
            ],
        })
    } else {
        Ok(RingProofBig {
            challenge: full_challenge,
            sub_challenge0: c_fake.clone(),
            responses: [
                be32_from_biguint(&s_fake_s),
                le32_from_biguint(&s_fake_p),
                be32_from_biguint(&s_real_s),
                le32_from_biguint(&s_real_p),
            ],
        })
    }
}

#[allow(clippy::too_many_arguments)]
fn verify_ring_bit_pallas(
    c_s: &SecpPoint,
    c_p: &pallas::Point,
    c_bar_s: &SecpPoint,
    c_bar_p: &pallas::Point,
    h_s: &SecpPoint,
    g_blind_p: &pallas::Point,
    bit_proof: &PallasDleqBitProof,
    bases: &[Vec<u8>],
    keys: &[Vec<u8>],
    bit_index: usize,
) -> Result<bool> {
    let full_challenge = bigint_from_be(&bit_proof.challenge);
    let c0 = bigint_from_be(&bit_proof.sub_challenge0);
    let c1 = if full_challenge >= c0 {
        &full_challenge - &c0
    } else {
        &full_challenge + secp_order() - &c0
    } % secp_order();

    let s0_s = bigint_from_be(&bit_proof.responses[0]);
    let s0_p = bigint_from_le(&bit_proof.responses[1]);
    let s1_s = bigint_from_be(&bit_proof.responses[2]);
    let s1_p = bigint_from_le(&bit_proof.responses[3]);

    let r0_s = (*h_s * scalar_from_biguint(&s0_s)?)
        + (*c_s * scalar_from_biguint(&mod_neg(&c0, &secp_order()))?);
    let c0_p = &c0 % pallas_q();
    let r0_p = (*g_blind_p * pallas_scalar_from_biguint(&s0_p)?)
        + (*c_p * pallas_scalar_from_biguint(&mod_neg(&c0_p, &pallas_q()))?);
    let r1_s = (*h_s * scalar_from_biguint(&s1_s)?)
        + (*c_bar_s * scalar_from_biguint(&mod_neg(&c1, &secp_order()))?);
    let c1_p = &c1 % pallas_q();
    let r1_p = (*g_blind_p * pallas_scalar_from_biguint(&s1_p)?)
        + (*c_bar_p * pallas_scalar_from_biguint(&mod_neg(&c1_p, &pallas_q()))?);

    let computed = ring_challenge_pallas(
        bit_index,
        bases,
        keys,
        &[
            point_to_sec1(c_s)?.to_vec(),
            pallas_point_to_sec1(c_p)?.to_vec(),
            point_to_sec1(&r0_s)?.to_vec(),
            pallas_point_to_sec1(&r0_p)?.to_vec(),
            point_to_sec1(&r1_s)?.to_vec(),
            pallas_point_to_sec1(&r1_p)?.to_vec(),
        ],
    );
    Ok(computed == full_challenge)
}

fn ring_challenge_pallas(
    bit_index: usize,
    bases: &[Vec<u8>],
    keys: &[Vec<u8>],
    commitments: &[Vec<u8>],
) -> BigUint {
    let mut transcript = Vec::new();
    transcript.extend_from_slice(DOMAIN_RING);
    transcript.extend_from_slice(&(bit_index as u32).to_be_bytes());
    let mut all = Vec::with_capacity(bases.len() + keys.len() + commitments.len());
    all.extend_from_slice(bases);
    all.extend_from_slice(keys);
    all.extend_from_slice(commitments);
    transcript.extend_from_slice(&lp_encode(&all));
    bigint_from_be(&sha256_bytes(&transcript)) % secp_order()
}

fn lp_encode(parts: &[Vec<u8>]) -> Vec<u8> {
    let mut out = Vec::new();
    for part in parts {
        out.extend_from_slice(&(part.len() as u32).to_be_bytes());
        out.extend_from_slice(part);
    }
    out
}

fn sign_pallas_schnorr(
    k: &BigUint,
    public_key: &[u8; 33],
    message_hash: &[u8; 32],
) -> Result<[u8; 65]> {
    let r = random_pallas_scalar_biguint();
    let r_point = spend_auth_g() * pallas_scalar_from_biguint(&r)?;
    let r_bytes = pallas_point_to_sec1(&r_point)?;
    let mut transcript = Vec::new();
    transcript.extend_from_slice(DOMAIN_SCHNORR_P);
    transcript.extend_from_slice(&r_bytes);
    transcript.extend_from_slice(public_key);
    transcript.extend_from_slice(message_hash);
    let c = pallas_challenge_scalar(&transcript);
    let s = (r + (&c * k)) % pallas_q();
    let mut sig = [0u8; 65];
    sig[..33].copy_from_slice(&r_bytes);
    sig[33..].copy_from_slice(&le32_from_biguint(&s));
    Ok(sig)
}

fn verify_pallas_schnorr(
    public_key: &[u8; 33],
    message_hash: &[u8; 32],
    signature: &[u8; 65],
) -> Result<bool> {
    let r = pallas_point_from_sec1(&signature[..33])?;
    let s = bigint_from_le(&signature[33..]);
    let pk = pallas_point_from_sec1(public_key)?;
    let mut transcript = Vec::new();
    transcript.extend_from_slice(DOMAIN_SCHNORR_P);
    transcript.extend_from_slice(&signature[..33]);
    transcript.extend_from_slice(public_key);
    transcript.extend_from_slice(message_hash);
    let c = pallas_challenge_scalar(&transcript);
    let lhs = spend_auth_g() * pallas_scalar_from_biguint(&s)?;
    let rhs = r + (pk * pallas_scalar_from_biguint(&c)?);
    Ok(pallas_projective_eq(&lhs, &rhs))
}

fn pallas_challenge_scalar(transcript: &[u8]) -> BigUint {
    let digest = Sha512::digest(transcript);
    BigUint::from_bytes_be(&digest) % pallas_q()
}

pub fn serialize(proof: &PallasDleqProof) -> Vec<u8> {
    let mut out = Vec::with_capacity(
        1 + 2 + proof.bit_proofs.len() * (33 + 33 + 32 + 32 + 128) + 2 + 64 + 65 + 33 + 33,
    );
    out.push(PROOF_VERSION);
    out.extend_from_slice(&(proof.bit_proofs.len() as u16).to_le_bytes());
    for bp in &proof.bit_proofs {
        out.extend_from_slice(&bp.commitment_secp);
        out.extend_from_slice(&bp.commitment_pallas);
        out.extend_from_slice(&bp.challenge);
        out.extend_from_slice(&bp.sub_challenge0);
        for response in &bp.responses {
            out.extend_from_slice(response);
        }
    }
    out.extend_from_slice(&(proof.signature_secp.len() as u16).to_le_bytes());
    out.extend_from_slice(&proof.signature_secp);
    out.extend_from_slice(&proof.signature_pallas);
    out.extend_from_slice(&proof.public_key_secp);
    out.extend_from_slice(&proof.public_key_pallas);
    out
}

pub fn deserialize(data: &[u8]) -> Result<PallasDleqProof> {
    ensure!(!data.is_empty(), "Pallas DLEq proof: empty");
    ensure!(
        data[0] == PROOF_VERSION,
        "Pallas DLEq proof v{} unsupported; expected v{PROOF_VERSION}",
        data[0]
    );
    let mut offset = 1usize;
    ensure!(
        data.len() >= offset + 2,
        "Pallas DLEq proof missing bit count"
    );
    let bit_count = u16::from_le_bytes(data[offset..offset + 2].try_into().unwrap()) as usize;
    offset += 2;
    let mut bit_proofs = Vec::with_capacity(bit_count);
    for _ in 0..bit_count {
        let commitment_secp = read_array::<33>(data, &mut offset, "commitmentSecp")?;
        let commitment_pallas = read_array::<33>(data, &mut offset, "commitmentPallas")?;
        let challenge = read_array::<32>(data, &mut offset, "challenge")?;
        let sub_challenge0 = read_array::<32>(data, &mut offset, "subChallenge0")?;
        let responses = [
            read_array::<32>(data, &mut offset, "response0")?,
            read_array::<32>(data, &mut offset, "response1")?,
            read_array::<32>(data, &mut offset, "response2")?,
            read_array::<32>(data, &mut offset, "response3")?,
        ];
        bit_proofs.push(PallasDleqBitProof {
            commitment_secp,
            commitment_pallas,
            challenge,
            sub_challenge0,
            responses,
        });
    }
    ensure!(
        data.len() >= offset + 2,
        "Pallas DLEq proof missing secp signature length"
    );
    let sig_secp_len = u16::from_le_bytes(data[offset..offset + 2].try_into().unwrap()) as usize;
    offset += 2;
    ensure!(
        sig_secp_len == 64,
        "Pallas DLEq secp signature must be 64 bytes, got {sig_secp_len}"
    );
    let signature_secp = read_array::<64>(data, &mut offset, "signatureSecp")?;
    let signature_pallas = read_array::<65>(data, &mut offset, "signaturePallas")?;
    let public_key_secp = read_array::<33>(data, &mut offset, "publicKeySecp")?;
    let public_key_pallas = read_array::<33>(data, &mut offset, "publicKeyPallas")?;
    ensure!(offset == data.len(), "trailing bytes in Pallas DLEq proof");
    Ok(PallasDleqProof {
        bit_proofs,
        signature_secp,
        signature_pallas,
        public_key_secp,
        public_key_pallas,
    })
}

fn read_array<const N: usize>(data: &[u8], offset: &mut usize, label: &str) -> Result<[u8; N]> {
    ensure!(data.len() >= *offset + N, "truncated {label}");
    let mut out = [0u8; N];
    out.copy_from_slice(&data[*offset..*offset + N]);
    *offset += N;
    Ok(out)
}

pub(crate) fn spend_auth_g() -> pallas::Point {
    pallas::Point::hash_to_curve("z.cash:Orchard")(b"G")
}

fn pallas_blinding_base() -> pallas::Point {
    // Keep this fixed to the TypeScript reference's
    // hashToPallas("zwap-asmr/dleq/G_blind_p/v2", "") output. The upstream
    // `pasta_curves::Point::hash_to_curve` helper currently derives a
    // different point for the same domain prefix, so using it here creates
    // proofs that self-verify in Rust but fail the SDK verifier.
    pallas_point_from_sec1(&PALLAS_BLINDING_BASE_SEC1)
        .expect("hard-coded Pallas blinding base must be a valid SEC1 point")
}

pub fn pallas_point_to_sec1(point: &pallas::Point) -> Result<[u8; 33]> {
    ensure!(
        !bool::from(point.is_identity()),
        "cannot SEC1-encode Pallas identity"
    );
    let affine = pallas::Affine::from(*point);
    let coords =
        Option::<pasta_curves::arithmetic::Coordinates<pallas::Affine>>::from(affine.coordinates())
            .ok_or_else(|| anyhow!("Pallas point has no affine coordinates"))?;
    let mut x_be = coords.x().to_repr();
    x_be.reverse();
    let prefix = if bool::from(coords.y().is_odd()) {
        0x03
    } else {
        0x02
    };
    let mut out = [0u8; 33];
    out[0] = prefix;
    out[1..].copy_from_slice(&x_be);
    Ok(out)
}

pub fn pallas_point_from_sec1(bytes: &[u8]) -> Result<pallas::Point> {
    ensure!(bytes.len() == 33, "Pallas SEC1 point must be 33 bytes");
    ensure!(
        bytes[0] == 0x02 || bytes[0] == 0x03,
        "Pallas SEC1 point prefix must be 02 or 03"
    );
    let want_odd = bytes[0] == 0x03;
    let mut x_le = [0u8; 32];
    x_le.copy_from_slice(&bytes[1..]);
    x_le.reverse();
    let x = Option::<pallas::Base>::from(pallas::Base::from_repr(x_le))
        .ok_or_else(|| anyhow!("Pallas SEC1 x-coordinate is not canonical"))?;
    let rhs = x.square() * x + pallas::Base::from(5);
    let mut y = Option::<pallas::Base>::from(rhs.sqrt())
        .ok_or_else(|| anyhow!("Pallas SEC1 x-coordinate is not on curve"))?;
    if bool::from(y.is_odd()) != want_odd {
        y = -y;
    }
    let affine = Option::<pallas::Affine>::from(pallas::Affine::from_xy(x, y))
        .ok_or_else(|| anyhow!("invalid Pallas SEC1 point"))?;
    Ok(pallas::Point::from(affine))
}

pub fn pallas_point_to_orchard_bytes(point: &pallas::Point) -> Result<[u8; 32]> {
    ensure!(
        !bool::from(point.is_identity()),
        "cannot encode Pallas identity"
    );
    Ok(pallas::Affine::from(*point).to_bytes())
}

pub(crate) fn pallas_projective_eq(a: &pallas::Point, b: &pallas::Point) -> bool {
    pallas::Affine::from(*a) == pallas::Affine::from(*b)
}

pub(crate) fn pallas_scalar_from_biguint(value: &BigUint) -> Result<pallas::Scalar> {
    let reduced = value % pallas_q();
    let le = le32_from_biguint(&reduced);
    Option::<pallas::Scalar>::from(pallas::Scalar::from_repr(le))
        .ok_or_else(|| anyhow!("invalid Pallas scalar"))
}

pub(crate) fn pallas_q() -> BigUint {
    BigUint::from_str_radix(PALLAS_Q_HEX, 16).expect("valid Pallas q")
}

pub(crate) fn pallas_p() -> BigUint {
    BigUint::from_str_radix(PALLAS_P_HEX, 16).expect("valid Pallas p")
}

pub(crate) fn random_pallas_scalar_biguint() -> BigUint {
    loop {
        let mut bytes = [0u8; 32];
        OsRng.fill_bytes(&mut bytes);
        let n = BigUint::from_bytes_le(&bytes);
        if !n.is_zero() && n < pallas_q() {
            return n;
        }
    }
}

pub(crate) fn le32_from_biguint(value: &BigUint) -> [u8; 32] {
    let bytes = value.to_bytes_le();
    let mut out = [0u8; 32];
    let len = bytes.len().min(32);
    out[..len].copy_from_slice(&bytes[..len]);
    out
}

pub(crate) fn bigint_from_le(bytes: &[u8]) -> BigUint {
    BigUint::from_bytes_le(bytes)
}

fn bit(value: &BigUint, index: usize) -> u8 {
    if ((value >> index) & BigUint::one()).is_zero() {
        0
    } else {
        1
    }
}

