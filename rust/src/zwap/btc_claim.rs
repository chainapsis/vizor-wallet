//! BTC HTLC **branch-1 claim** spend builder — the z2b (ZEC→BTC) user side.
//!
//! In z2b the user is the responder: the solver funds the redesign single-script
//! P2WSH lock, reveals the swap secret, and the user then claims the lock's UTXO
//! to their own BTC receive address via BRANCH-1 — revealing `k_b` (the user's
//! joint spend-auth scalar) on-chain so the solver can reconstruct the joint
//! `ask` and drain the co-funded ZEC note. This module builds + signs that real
//! BTC transaction.
//!
//! Byte-faithful port of the SDK `v3/sdk/src/btcClaim.ts::buildBtcClaimTx`,
//! itself a port of the solver reference `v3/solver-v3/src/btc_claim.rs::
//! build_claim_tx` (+ `lock.rs::claim_witness`), golden-pinned to btc-batcher's
//! consensus vectors. Manual BIP143 serialization (no `bitcoin` crate) using
//! only `secp256k1` + `sha2` (already deps). The witness stack itself is built
//! by the golden-pinned [`super::btc_lock::claim_witness`].
//!
//! FUND-SAFETY: branch-1 requires `SHA256(swap_secret)==swapHash` AND
//! `SHA256(k_b)==h_B` (both committed in the lock witnessScript), so a wrong
//! secret / `k_b` is rejected by BTC consensus, never silently mis-spent. The
//! payout spk must be a standard form and above the dust threshold, refused
//! BEFORE signing (mirrors the Rust reference review-fix #8).

use secp256k1::{Message, Secp256k1, SecretKey};
use sha2::{Digest, Sha256};

use super::btc_lock::claim_witness;

const SIGHASH_ALL: u8 = 0x01;
/// BIP125 opt-in RBF; branch-1 has no CSV, so a stuck claim can be fee-bumped.
const RBF_SEQUENCE: u32 = 0xffff_fffd;

/// Inputs to build the branch-1 claim spend of a funded redesign lock.
///
/// ⚠️ ENDIANNESS: `k_b_be` MUST be the same 32 BIG-ENDIAN bytes the lock
/// committed to as `h_B = SHA256(k_b_be)`. A Pallas scalar is little-endian —
/// callers reverse it to BE first (the wallet stores `k_be` BE already). No
/// LE↔BE reversal happens here.
pub struct BtcClaimParams {
    pub lock_txid: String,
    pub lock_vout: u32,
    pub lock_value_sat: u64,
    /// The redesign lock witnessScript (hex) — `Z2bMaterial::witness_script_hex`.
    pub witness_script_hex: String,
    /// The user's BTC claim PRIVATE key (BE, 32B) — signs branch-1.
    pub claim_sk_be: [u8; 32],
    /// The user's `k_b` joint scalar (BE, 32B) — branch-1 checks `SHA256(k_b)==h_B`.
    pub k_b_be: [u8; 32],
    /// The swap secret (32B) the solver revealed — branch-1 checks `SHA256(x)==swapHash`.
    pub swap_secret: [u8; 32],
    /// The user's BTC receive scriptPubKey (hex) — where the claimed BTC lands.
    pub dest_spk_hex: String,
    /// Explicit fee (sats).
    pub fee_sat: u64,
}

fn dsha256(b: &[u8]) -> [u8; 32] {
    let first = Sha256::digest(b);
    Sha256::digest(first).into()
}

/// Bitcoin CompactSize (varInt).
fn var_int(n: usize) -> Vec<u8> {
    if n < 0xfd {
        vec![n as u8]
    } else if n <= 0xffff {
        let mut v = vec![0xfd];
        v.extend_from_slice(&(n as u16).to_le_bytes());
        v
    } else if n <= 0xffff_ffff {
        let mut v = vec![0xfe];
        v.extend_from_slice(&(n as u32).to_le_bytes());
        v
    } else {
        let mut v = vec![0xff];
        v.extend_from_slice(&(n as u64).to_le_bytes());
        v
    }
}

fn var_int_len(n: usize) -> usize {
    if n < 0xfd {
        1
    } else if n <= 0xffff {
        3
    } else if n <= 0xffff_ffff {
        5
    } else {
        9
    }
}

/// A length-prefixed (CompactSize) byte field — scriptCode + scriptPubKey.
fn with_len(b: &[u8]) -> Vec<u8> {
    let mut v = var_int(b.len());
    v.extend_from_slice(b);
    v
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum SpkKind {
    P2wpkh,
    P2wsh,
    P2tr,
    P2pkh,
    P2sh,
}

/// Classify a payout scriptPubKey to the standard forms the Rust reference
/// accepts (review-fix #8). `None` ⇒ non-standard (would relay-fail).
fn spk_kind(spk: &[u8]) -> Option<SpkKind> {
    if spk.len() == 22 && spk[0] == 0x00 && spk[1] == 0x14 {
        Some(SpkKind::P2wpkh)
    } else if spk.len() == 34 && spk[0] == 0x00 && spk[1] == 0x20 {
        Some(SpkKind::P2wsh)
    } else if spk.len() == 34 && spk[0] == 0x51 && spk[1] == 0x20 {
        Some(SpkKind::P2tr)
    } else if spk.len() == 25
        && spk[0] == 0x76
        && spk[1] == 0xa9
        && spk[2] == 0x14
        && spk[23] == 0x88
        && spk[24] == 0xac
    {
        Some(SpkKind::P2pkh)
    } else if spk.len() == 23 && spk[0] == 0xa9 && spk[1] == 0x14 && spk[22] == 0x87 {
        Some(SpkKind::P2sh)
    } else {
        None
    }
}

/// Core/`rust-bitcoin` `minimal_non_dust` at the default 3 sat/vB dust-relay
/// fee. Computed (not hardcoded) so it tracks the spk type exactly: witness
/// spends cost 67 vB to redeem, legacy 148. Yields the canonical constants
/// (p2wpkh 294, p2wsh/p2tr 330, p2pkh 546, p2sh 540).
fn dust_threshold(spk: &[u8], kind: SpkKind) -> u64 {
    let out_size = 8 + var_int_len(spk.len()) + spk.len();
    let is_witness = matches!(kind, SpkKind::P2wpkh | SpkKind::P2wsh | SpkKind::P2tr);
    let spend_cost = if is_witness { 67 } else { 148 };
    ((out_size + spend_cost) * 3) as u64
}

/// Build + sign the branch-1 claim spend of a funded redesign P2WSH lock,
/// returning `(raw_tx_hex, txid)`. Pure (no I/O). Witness =
/// `[sig_B‖0x01, k_B, swap_secret, 0x01, witnessScript]`; version 2, nSequence
/// 0xfffffffd (RBF), locktime 0; single input → single output.
pub fn build_btc_claim_tx(p: &BtcClaimParams) -> Result<(String, String), String> {
    if p.lock_value_sat <= p.fee_sat {
        return Err(format!("fee {} exceeds lock value {}", p.fee_sat, p.lock_value_sat));
    }
    let dest_spk = hex::decode(&p.dest_spk_hex).map_err(|e| format!("dest_spk hex: {e}"))?;
    let kind = spk_kind(&dest_spk).ok_or_else(|| {
        format!("dest_spk is not a standard scriptPubKey (p2wpkh/p2wsh/p2tr/p2pkh/p2sh): {}", p.dest_spk_hex)
    })?;
    let dest_value = p.lock_value_sat - p.fee_sat;
    let dust = dust_threshold(&dest_spk, kind);
    if dest_value < dust {
        return Err(format!("payout {dest_value} is below the dust threshold {dust} for the dest spk"));
    }

    let witness_script = hex::decode(&p.witness_script_hex).map_err(|e| format!("witness_script hex: {e}"))?;

    let txid_bytes = hex::decode(&p.lock_txid).map_err(|e| format!("lock_txid hex: {e}"))?;
    if txid_bytes.len() != 32 {
        return Err(format!("lock_txid must be 32 bytes, got {}", txid_bytes.len()));
    }
    // outpoint = internal LE txid ‖ vout(LE)
    let mut outpoint = txid_bytes.clone();
    outpoint.reverse();
    outpoint.extend_from_slice(&p.lock_vout.to_le_bytes());
    let seq = RBF_SEQUENCE.to_le_bytes().to_vec();
    // outputSer = value(LE u64) ‖ withLen(destSpk)
    let mut output_ser = dest_value.to_le_bytes().to_vec();
    output_ser.extend_from_slice(&with_len(&dest_spk));

    // BIP143 sighash (segwit v0, single P2WSH input, SIGHASH_ALL).
    let mut preimage = Vec::new();
    preimage.extend_from_slice(&2u32.to_le_bytes()); // nVersion
    preimage.extend_from_slice(&dsha256(&outpoint)); // hashPrevouts (single input)
    preimage.extend_from_slice(&dsha256(&seq)); // hashSequence
    preimage.extend_from_slice(&outpoint); // this input's outpoint
    preimage.extend_from_slice(&with_len(&witness_script)); // scriptCode
    preimage.extend_from_slice(&p.lock_value_sat.to_le_bytes()); // input amount
    preimage.extend_from_slice(&seq); // this input's nSequence
    preimage.extend_from_slice(&dsha256(&output_ser)); // hashOutputs (single output)
    preimage.extend_from_slice(&0u32.to_le_bytes()); // nLockTime
    preimage.extend_from_slice(&(SIGHASH_ALL as u32).to_le_bytes()); // sighash type
    let sighash = dsha256(&preimage);

    // RFC6979-deterministic, low-S DER signature (secp256k1 `sign_ecdsa` is
    // low-S normalized — byte-identical to @noble/curves lowS in the SDK).
    let secp = Secp256k1::new();
    let sk = SecretKey::from_slice(&p.claim_sk_be).map_err(|e| format!("claim sk: {e}"))?;
    let msg = Message::from_digest(sighash);
    let sig = secp.sign_ecdsa(&msg, &sk);
    let sig_der = sig.serialize_der();

    // Branch-1 witness stack: [sig‖0x01, k_B, swap_secret, 0x01, witnessScript].
    let witness = claim_witness(sig_der.as_ref(), &p.k_b_be, &p.swap_secret, SIGHASH_ALL, &witness_script);

    // Final segwit serialization.
    let mut raw = Vec::new();
    raw.extend_from_slice(&2u32.to_le_bytes()); // version
    raw.extend_from_slice(&[0x00, 0x01]); // segwit marker + flag
    raw.extend_from_slice(&var_int(1)); // vin count
    raw.extend_from_slice(&outpoint);
    raw.extend_from_slice(&var_int(0)); // empty scriptSig
    raw.extend_from_slice(&seq);
    raw.extend_from_slice(&var_int(1)); // vout count
    raw.extend_from_slice(&output_ser);
    raw.extend_from_slice(&var_int(witness.len())); // witness stack item count
    for item in &witness {
        raw.extend_from_slice(&with_len(item));
    }
    raw.extend_from_slice(&0u32.to_le_bytes()); // locktime

    // txid = reverse(dSHA256(non-witness serialization)).
    let mut non_witness = Vec::new();
    non_witness.extend_from_slice(&2u32.to_le_bytes());
    non_witness.extend_from_slice(&var_int(1));
    non_witness.extend_from_slice(&outpoint);
    non_witness.extend_from_slice(&var_int(0));
    non_witness.extend_from_slice(&seq);
    non_witness.extend_from_slice(&var_int(1));
    non_witness.extend_from_slice(&output_ser);
    non_witness.extend_from_slice(&0u32.to_le_bytes());
    let mut txid = dsha256(&non_witness);
    txid.reverse();

    Ok((hex::encode(&raw), hex::encode(txid)))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A p2wpkh dest spk (22 bytes: OP_0 push20) is standard and non-dust for a
    /// 100k-sat lock; a random 10-byte spk is refused before signing.
    #[test]
    fn rejects_nonstandard_and_dust() {
        let mut p = BtcClaimParams {
            lock_txid: "11".repeat(32),
            lock_vout: 0,
            lock_value_sat: 100_000,
            witness_script_hex: "51".to_string(), // OP_1 (dummy; not consensus-checked here)
            claim_sk_be: [7u8; 32],
            k_b_be: [3u8; 32],
            swap_secret: [9u8; 32],
            dest_spk_hex: "0014".to_string() + &"22".repeat(20), // p2wpkh
            fee_sat: 500,
        };
        let ok = build_btc_claim_tx(&p);
        assert!(ok.is_ok(), "standard p2wpkh claim should build: {ok:?}");
        let (raw, txid) = ok.unwrap();
        // version(02000000) + segwit marker/flag(0001) + vin count(01).
        assert!(raw.starts_with("02000000000101"), "version+marker+flag+vin: {}", &raw[..14]);
        assert_eq!(txid.len(), 64);

        // Non-standard spk → refused.
        p.dest_spk_hex = "abcdef".to_string();
        assert!(build_btc_claim_tx(&p).is_err(), "non-standard spk must be refused");

        // Fee ≥ value → refused.
        p.dest_spk_hex = "0014".to_string() + &"22".repeat(20);
        p.fee_sat = 100_000;
        assert!(build_btc_claim_tx(&p).is_err(), "fee ≥ lock value must be refused");
    }

    /// Deterministic: same inputs → same signed tx (RFC6979 + low-S).
    #[test]
    fn deterministic() {
        let p = BtcClaimParams {
            lock_txid: "ab".repeat(32),
            lock_vout: 1,
            lock_value_sat: 250_000,
            witness_script_hex: "5221aa21bb52ae".to_string(),
            claim_sk_be: [5u8; 32],
            k_b_be: [6u8; 32],
            swap_secret: [8u8; 32],
            dest_spk_hex: "0014".to_string() + &"33".repeat(20),
            fee_sat: 500,
        };
        let a = build_btc_claim_tx(&p).unwrap();
        let b = build_btc_claim_tx(&p).unwrap();
        assert_eq!(a, b, "claim tx must be deterministic");
    }
}
